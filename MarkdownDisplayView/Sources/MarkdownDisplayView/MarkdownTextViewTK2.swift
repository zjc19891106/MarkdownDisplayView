//
//  MarkdownTextViewTK2.swift
//  MarkdownDisplayView
//
//  Created by 朱继超 on 12/15/25.
//

import UIKit
import Foundation

// MARK: - TextKit2 TextView

/// 使用 TextKit 2 的自定义 TextView
@available(iOS 15.0, *)
class MarkdownTextViewTK2: UIView {

    private let textLayoutManager: NSTextLayoutManager
    private let textContentStorage: NSTextContentStorage
    let textContainer: NSTextContainer

    var attributedText: NSAttributedString? {
        didSet {
            updateContent()
        }
    }

    var linkTextAttributes: [NSAttributedString.Key: Any] = [:]
    var onLinkTap: ((URL) -> Void)?
    var onImageTap: ((String) -> Void)?

    private var calculatedHeight: CGFloat = 0
    private var heightConstraint: NSLayoutConstraint?

    // ⭐️ 管理自定义附件视图（如表格）
    private var attachmentProviders: [NSTextAttachment: NSTextAttachmentViewProvider] = [:]

    override init(frame: CGRect) {
        textContentStorage = NSTextContentStorage()
        textLayoutManager = NSTextLayoutManager()
        textContainer = NSTextContainer()

        super.init(frame: frame)

        setupTextKit2()
        setupGestures()
        setupHeightConstraint()
    }

    required init?(coder: NSCoder) {
        textContentStorage = NSTextContentStorage()
        textLayoutManager = NSTextLayoutManager()
        textContainer = NSTextContainer()

        super.init(coder: coder)

        setupTextKit2()
        setupGestures()
        setupHeightConstraint()
    }

    private func setupHeightConstraint() {
        // 初始化高度约束，优先级略低于 required，允许在极端情况下被压缩（防止冲突），但通常足以撑开
        let constraint = heightAnchor.constraint(equalToConstant: 0)
        constraint.priority = UILayoutPriority(999)
        constraint.isActive = true
        self.heightConstraint = constraint

        // ⭐️ 防止被 StackView 压缩
        self.setContentCompressionResistancePriority(.required, for: .vertical)
    }

    private func setupTextKit2() {
        textContentStorage.addTextLayoutManager(textLayoutManager)
        textLayoutManager.textContainer = textContainer
        textContainer.lineFragmentPadding = 0
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
        textContainer.lineBreakMode = .byWordWrapping
        backgroundColor = .clear
        isUserInteractionEnabled = true
        contentMode = .topLeft
    }

    // 在 MarkdownTextViewTK2 类中

    override var intrinsicContentSize: CGSize {
        // 直接使用约束值作为 intrinsic size，确保与 Auto Layout 同步
        // 避免 calculatedHeight 变量在某些时序下滞后的问题
        return CGSize(width: UIView.noIntrinsicMetric, height: heightConstraint?.constant ?? 0)
    }

    func applyLayout(width: CGFloat, force: Bool = false) {
        guard width > 0 else { return }

        let widthChanged = abs(textContainer.size.width - width) > 0.1

        if widthChanged {
            textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        }

        if force || widthChanged || calculatedHeight == 0 {
            textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)

            var height: CGFloat = 0
            textLayoutManager.enumerateTextLayoutFragments(from: textLayoutManager.documentRange.location, options: [.ensuresLayout]) { fragment in
                let fragmentFrame = fragment.layoutFragmentFrame
                height = max(height, fragmentFrame.maxY)
                return true
            }

            // ⭐️ 核心修复：直接更新高度约束
            // 加上一点 buffer (e.g. 1px) 防止精度问题导致的截断
            var newHeight = ceil(height)

            // Fallback: 如果 TextKit 2 计算为 0 但有文本，使用 boundingRect 估算
            if newHeight == 0, let attrText = textContentStorage.attributedString, attrText.length > 0 {
                let fallbackSize = attrText.boundingRect(
                    with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                ).size
                newHeight = ceil(fallbackSize.height + 1) // +1 buffer
            }

            if heightConstraint?.constant != newHeight {
                heightConstraint?.constant = newHeight
                calculatedHeight = newHeight
                invalidateIntrinsicContentSize() // 通知系统 update constraints
                setNeedsDisplay() // ⭐️ 高度变化后强制重绘，防止内容空白
            }

            // ⭐️ 布局完成后，更新附件视图位置
            layoutAttachments()
        }
    }

    // ⚡️ 性能优化：支持直接设置预计算的高度
    func setFixedHeight(_ height: CGFloat) {
        guard height > 0 else { return }
        if heightConstraint?.constant != height {
            heightConstraint?.constant = height
            calculatedHeight = height
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    private func setupGestures() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tapGesture)
    }

    private func updateContent() {
        guard let attributedText = attributedText else {
            textContentStorage.attributedString = nil
            calculatedHeight = 0

            // 清理所有附件视图
            attachmentProviders.values.forEach { $0.view?.removeFromSuperview() }
            attachmentProviders.removeAll()

            invalidateIntrinsicContentSize()
            setNeedsDisplay()
            return
        }

        // 1. 更新 TextKit 存储
        textContentStorage.attributedString = attributedText

        // 2. 标记需要重绘 (但不立即触发布局，等待外部显式调用 applyLayout 或 layoutSubviews)
        // 这里的关键是：不要使用 bounds.width 进行猜测性布局，防止"旧宽度"导致的高度跳变
        setNeedsDisplay()

        // 注意：这里不立即调用 layoutAttachments，因为 TextKit 可能还没布局
        // layoutAttachments 会在 applyLayout 或 layoutSubviews 中被调用
    }

    private func layoutText() {
        // ⭐️ 修复 1: 增加防抖检查。
        // 如果宽度没有实质性变化（比如布局循环中微小的浮点误差），或者是 0，
        // 就不要重新触发昂贵的 TextKit 布局，防止覆盖掉外部递归计算出的正确宽度。
        if bounds.width > 0 && abs(bounds.width - textContainer.size.width) > 0.5 {
            applyLayout(width: bounds.width, force: false)
        } else {
            // 即使不需要重新计算 text layout，也需要确保附件视图位置正确 (例如 view frame 变化)
            layoutAttachments()
        }
    }

    private func layoutAttachments() {
        guard let attrString = textContentStorage.attributedString else { return }

        var usedAttachments = Set<NSTextAttachment>()

        textLayoutManager.enumerateTextLayoutFragments(from: textLayoutManager.documentRange.location, options: [.ensuresLayout]) { fragment in
            for textLine in fragment.textLineFragments {
                let lineRange = textLine.characterRange

                attrString.enumerateAttribute(.attachment, in: NSRange(location: lineRange.location, length: lineRange.length)) { value, range, stop in
                    guard let attachment = value as? NSTextAttachment else { return }

                    // 检查是否支持 viewProvider (例如 MarkdownTableAttachment)
                    // 注意：标准 image attachment 不会返回 viewProvider，除非显式实现

                    // 尝试获取或创建 Provider
                    var provider = self.attachmentProviders[attachment]

                    if provider == nil {
                        // Safely unwrap the location
                        if let location = self.textLayoutManager.location(self.textLayoutManager.documentRange.location, offsetBy: range.location),
                           let newProvider = attachment.viewProvider(for: self, location: location, textContainer: self.textContainer) {
                            newProvider.loadView()
                            self.attachmentProviders[attachment] = newProvider
                            provider = newProvider
                            if let view = newProvider.view {
                                self.addSubview(view)
                            }
                        }
                    }

                    if let provider = provider {
                        usedAttachments.insert(attachment)
                        if let view = provider.view {
                            if view.superview != self {
                                self.addSubview(view)
                            }
                            // 简单的布局策略：将视图填满 Fragment 区域
                            // 对于表格这种独占一行的 Attachment，这是正确的
                            view.frame = fragment.layoutFragmentFrame
                        }
                    }
                }
            }
            return true
        }

        // 清理不再使用的附件视图
        for (attachment, provider) in attachmentProviders {
            if !usedAttachments.contains(attachment) {
                provider.view?.removeFromSuperview()
                attachmentProviders.removeValue(forKey: attachment)
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // ⭐️ 修复 2: 确保视图有尺寸时触发布局检查
        if textContentStorage.attributedString != nil {
            layoutText()
        }

        // ⭐️ 修复 3: 强制重绘
        // 当 StackView 展开时，bounds 从 0 变为有值，但 TextKit 可能需要一个显式的重绘信号
        // 尤其是在 backgroundColor 为 clear 的情况下
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        guard let context = UIGraphicsGetCurrentContext() else { return }

        var hasFragments = false
        textLayoutManager.enumerateTextLayoutFragments(from: textLayoutManager.documentRange.location, options: [.ensuresLayout]) { fragment in
            fragment.draw(at: fragment.layoutFragmentFrame.origin, in: context)
            hasFragments = true
            return true
        }

        // Fallback: 如果 TextKit 2 没有生成任何片段（但有文本），说明布局引擎在视图隐藏时可能未正确更新
        // 使用 NSAttributedString 直接绘制以确保内容可见
        if !hasFragments, let attrText = textContentStorage.attributedString, attrText.length > 0 {
            attrText.draw(in: rect)
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        guard let textLayoutFragment = textLayoutManager.textLayoutFragment(for: location) else { return }

        let locationInFragment = CGPoint(
            x: location.x - textLayoutFragment.layoutFragmentFrame.origin.x,
            y: location.y - textLayoutFragment.layoutFragmentFrame.origin.y
        )

        var caretLocation: NSTextLocation?
        textLayoutFragment.textLineFragments.forEach { lineFragment in
            let lineFrame = lineFragment.typographicBounds
            let adjustedLineFrame = CGRect(
                x: lineFrame.origin.x,
                y: lineFrame.origin.y,
                width: lineFrame.width,
                height: lineFrame.height
            )

            if adjustedLineFrame.contains(locationInFragment) {
                let characterIndex = lineFragment.characterIndex(for: locationInFragment)
                if characterIndex != NSNotFound,
                   let textRange = textLayoutFragment.textElement?.elementRange,
                   let startLocation = textRange.location as? NSTextLocation {
                    caretLocation = textLayoutManager.location(startLocation, offsetBy: characterIndex)
                }
            }
        }

        guard let location = caretLocation else { return }
        let offset = textLayoutManager.offset(from: textLayoutManager.documentRange.location, to: location)

        guard let attributedText = textContentStorage.attributedString,
              offset >= 0 && offset < attributedText.length else { return }

        let attributes = attributedText.attributes(at: offset, effectiveRange: nil)

        if let attachment = attributes[.attachment] as? MarkdownImageAttachment,
           let urlString = attachment.imageURL {
            onImageTap?(urlString)
            return
        }

        if let url = attributes[.link] as? URL {
            onLinkTap?(url)
        }
    }
}

// MARK: - Typewriter Support
@available(iOS 15.0, *)
extension MarkdownTextViewTK2 {

    // 缓存一个 mutable copy，避免每次 run loop 都深拷贝整个文档
    private struct AssociatedKeys {
        static var cachedMutableString = "cachedMutableString"
        static var lastRevealedIndex = "lastRevealedIndex"  // ⭐️ 新增：追踪上次显示位置
    }

    private var cachedMutableString: NSMutableAttributedString? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.cachedMutableString) as? NSMutableAttributedString
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.cachedMutableString, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    // ⭐️ 新增：追踪上次显示到哪个位置
    private var lastRevealedIndex: Int {
        get {
            return (objc_getAssociatedObject(self, &AssociatedKeys.lastRevealedIndex) as? Int) ?? 0
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.lastRevealedIndex, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    /// 准备打字机效果：将所有文字设为透明，但保留布局占位
    func prepareForTypewriter() {
        guard let attr = textContentStorage.attributedString else {
            print("[TYPEWRITER] ⚠️ prepareForTypewriter 失败: textContentStorage.attributedString 为 nil")
            return
        }

        print("[TYPEWRITER] 🎯 prepareForTypewriter 开始, 文本长度: \(attr.length), 内容: \(attr.string.prefix(50))...")

        // ⭐️ 重置显示位置
        lastRevealedIndex = 0

        // ⚡️ 强制触发布局，确保高度和位置在开始打字前是正确的
        // 这能防止在 hidden = false 瞬间因为布局未完成而导致的闪烁或跳动
        layoutIfNeeded()

        // 初始化缓存
        let mutable = NSMutableAttributedString(attributedString: attr)
        let fullRange = NSRange(location: 0, length: attr.length)

        // 1. 设置全透明
        mutable.addAttribute(.foregroundColor, value: UIColor.clear, range: fullRange)

        // 2. ⭐️ 核心修复：移除 .link 属性
        // 防止系统（或TextKit）强制渲染链接颜色，导致文字无法隐藏
        mutable.removeAttribute(.link, range: fullRange)

        cachedMutableString = mutable

        // 赋值给 storage
        // 注意：这里 copy 一份是为了避免引用问题，但在 TextKit 2 中，
        // 给 textContentStorage 赋值本身就会触发某些处理。
        textContentStorage.attributedString = mutable

        // ⭐️ 关键修复：强制 TextKit 2 重新布局，确保透明属性立即生效
        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
        setNeedsDisplay()

        print("[TYPEWRITER] 🎯 prepareForTypewriter 完成")
    }

    /// 揭示前 N 个字符（支持批量显示）
    func revealCharacter(upto index: Int) {
        guard let originalAttr = attributedText, // 原始带颜色的文本
              let workingAttr = cachedMutableString,
              index > 0 else {
            print("[TYPEWRITER] ⚠️ revealCharacter 提前返回: attributedText=\(attributedText != nil), cachedMutableString=\(cachedMutableString != nil), index=\(index)")
            return
        }

        let length = originalAttr.length
        if index > length { return }

        // ⭐️ 批量支持：从上次位置到当前位置，显示所有字符
        let startIndex = lastRevealedIndex
        let endIndex = index

        // 如果没有新字符需要显示，直接返回
        guard endIndex > startIndex else { return }

        // 遍历需要显示的每个字符，恢复其原始属性
        for charIndex in startIndex..<endIndex {
            let range = NSRange(location: charIndex, length: 1)

            // 从原始文本中获取该位置的属性（包含颜色）
            let originalAttributes = originalAttr.attributes(at: charIndex, effectiveRange: nil)

            // 先移除 .clear 颜色，再应用原始属性
            workingAttr.removeAttribute(.foregroundColor, range: range)
            workingAttr.addAttributes(originalAttributes, range: range)
        }

        // 更新上次显示位置
        lastRevealedIndex = endIndex

        // 更新显示
        textContentStorage.attributedString = workingAttr

        // 强制重绘
        setNeedsDisplay()
    }
}
