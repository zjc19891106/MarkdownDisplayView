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
class MarkdownTextViewTK2: UIView, UIGestureRecognizerDelegate {

    private let textLayoutManager: NSTextLayoutManager
    private let textContentStorage: NSTextContentStorage
    let textContainer: NSTextContainer

    /// 自己持有的 textStorage。
    ///
    /// `NSTextContentStorage` 默认不创建 textStorage，而给 `attributedString` 赋值是整篇替换、
    /// 会失效全文布局。显式持有一个 storage 后，增量修改就有了稳定的作用目标：
    /// 在 `performEditingTransaction` 里改它，TextKit 2 只失效被改动的范围。
    private let textStorage = NSTextStorage()

    var attributedText: NSAttributedString? {
        didSet {
            updateContent()
        }
    }

    /// 当前实际参与排版的文本快照。
    ///
    /// 打字机播放期间 storage 是中间态（append 模式只有已显示前缀、reveal 模式尚未显示的部分是
    /// 透明占位），与 `attributedText` 持有的原文并不相同，故单独暴露以便断言增量修改的结果。
    var displayedAttributedString: NSAttributedString {
        NSAttributedString(attributedString: textStorage)
    }

    var linkTextAttributes: [NSAttributedString.Key: Any] = [:]
    var onLinkTap: ((URL) -> Void)?
    var onImageTap: ((String) -> Void)?

    private var calculatedHeight: CGFloat = 0
    private var heightConstraint: NSLayoutConstraint?
    private var lastDisplayInvalidationBoundsSize: CGSize = .zero

    // ⭐️ 管理自定义附件视图（如表格）
    private var attachmentProviders: [NSTextAttachment: NSTextAttachmentViewProvider] = [:]

    // 打字机期间行内公式附件的字符索引（attachment -> 字符位置）
    private var inlineAttachmentCharacterIndexes: [NSTextAttachment: Int] = [:]

    // nil 表示正常显示；非 nil 表示打字机只允许显示该 UTF-16 位置之前的附件。
    // 状态独立于 provider 生命周期，确保 prepare 后才延迟创建的附件也不会提前闪现。
    private var inlineAttachmentRevealLimit: Int?

    var typewriterTextMode: MarkdownTypewriterTextMode = .reveal
    /// ⚠️ 已不再参与 append 打字机的测高决策，保留仅为兼容既有配置。
    ///
    /// 它原先的作用是"每 N 个字符才重新测一次高"。但软折行不产生 "\n"、也不一定
    /// 正好凑够 N 个字符，被它拦下的那段时间里新行没有高度可用，就是流式输出在
    /// 折行边界的闪烁来源。现在 `revealCharacter` 每帧都测（增量布局，成本很低），
    /// 改由"高度是否真的变化"来节流向宿主的上报。
    var typewriterHeightUpdateInterval: Int = 20

    private var cachedOriginalAttributedString: NSAttributedString?
    private var isAppendingTypewriterText = false

    /// 当前内容是否含附件，用于跳过无附件时的全文片段遍历
    private var contentHasAttachments = false

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
        textContentStorage.textStorage = textStorage
        textContentStorage.addTextLayoutManager(textLayoutManager)
        textLayoutManager.textContainer = textContainer
        textLayoutManager.delegate = self  // 接管链接渲染属性，控制下划线等样式
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
            // ensureLayout 内部只重排失效的片段；配合增量文本更新，
            // 流式追加时的代价与新增内容成正比而非与全文长度成正比。
            textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)

            // 用 usageBounds 一次读出已排版内容的高度。
            // 原先逐个 enumerate 全部 fragment 取 maxY，是 O(全文片段数)，
            // 而打字机每 20 字符就调一次，累积成 O(n²)。
            let height = textLayoutManager.usageBoundsForTextContainer.maxY

            // ⭐️ 核心修复：直接更新高度约束
            // 加 1pt 安全 buffer，避免某些字体/行距组合在边界值时被裁剪
            var newHeight = ceil(height + 1)

            // Fallback: 如果 TextKit 2 计算为 0 但有文本，使用 boundingRect 估算
            if newHeight == 0, textStorage.length > 0 {
                let fallbackSize = textStorage.boundingRect(
                    with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                ).size
                newHeight = ceil(fallbackSize.height + 1) // +1 buffer
            }

            // append 打字机播放期间，可见内容只会增加。即使父布局临时修正宽度，
            // 也不能让已经展示的内容高度回缩，否则外层 Cell 会产生上下跳动。
            if isAppendingTypewriterText {
                newHeight = max(newHeight, calculatedHeight)
            }

            if heightConstraint?.constant != newHeight {
                heightConstraint?.constant = newHeight
                calculatedHeight = newHeight
                invalidateIntrinsicContentSize() // 通知系统 update constraints
            }

            // ⭐️ 无条件重绘：高度没变也可能是内容变了（同一行内追加），
            // 且 contentMode 为 .topLeft 时视图长高本身不会触发 draw。
            setNeedsDisplay()

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

    /// Atomic rich blocks are revealed as one unit, so their descendants never receive
    /// individual typewriter tasks. Expand only text that is still using append mode's
    /// provisional 1pt height; attachment-backed views keep their precalculated heights.
    func prepareDeferredAppendTextForAtomicDisplay() {
        guard typewriterTextMode == .append,
              textStorage.length > 0,
              (heightConstraint?.constant ?? calculatedHeight) <= 1.5,
              textContainer.size.width > 0 else {
            return
        }

        applyLayout(width: textContainer.size.width, force: true)
    }

    /// 结束 append 打字机播放，恢复正常的响应式测高。
    /// 最后一帧应先在播放保护下完成测量，再由引擎调用本方法。
    func finishAppendTypewriterPlayback() {
        isAppendingTypewriterText = false
        setInlineAttachmentRevealLimit(nil)
    }

    private func setupGestures() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        // 不拦截子视图触摸（例如表格 CollectionView 的 cell 点击）
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        addGestureRecognizer(tapGesture)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer.view === self else { return true }
        guard let touchedView = touch.view else { return true }

        // 附件视图（表格等）由其自身处理点击，避免被外层文本 Tap 手势抢占
        for provider in attachmentProviders.values {
            guard let attachmentView = provider.view else { continue }
            if touchedView === attachmentView || touchedView.isDescendant(of: attachmentView) {
                return false
            }
        }

        return true
    }

    private func updateContent() {
        // attributedText 被外部替换意味着上一轮 append 播放已经结束。
        isAppendingTypewriterText = false
        cachedOriginalAttributedString = nil
        inlineAttachmentCharacterIndexes.removeAll()
        inlineAttachmentRevealLimit = nil

        guard let attributedText = attributedText else {
            setStorageContent(nil)
            calculatedHeight = 0
            contentHasAttachments = false

            // 清理所有附件视图
            attachmentProviders.values.forEach { $0.view?.removeFromSuperview() }
            attachmentProviders.removeAll()

            invalidateIntrinsicContentSize()
            setNeedsDisplay()
            return
        }

        // 只在内容替换时算一次；打字机播放期间显示的是它的前缀，附件集合不会变多
        contentHasAttachments = attributedText.containsAttachments(
            in: NSRange(location: 0, length: attributedText.length)
        )

        // 1. 更新 TextKit 存储
        setStorageContent(attributedText)

        // 2. 标记需要重绘 (但不立即触发布局，等待外部显式调用 applyLayout 或 layoutSubviews)
        // 这里的关键是：不要使用 bounds.width 进行猜测性布局，防止"旧宽度"导致的高度跳变
        setNeedsDisplay()

        // 注意：这里不立即调用 layoutAttachments，因为 TextKit 可能还没布局
        // layoutAttachments 会在 applyLayout 或 layoutSubviews 中被调用
    }

    /// 全量替换文本内容。所有写入都走同一个 storage，保证增量修改有确定的作用目标。
    private func setStorageContent(_ newValue: NSAttributedString?) {
        textContentStorage.performEditingTransaction {
            textStorage.setAttributedString(newValue ?? NSAttributedString())
        }
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
        let attrString = textStorage

        // 绝大多数文本不含附件。该遍历是 O(全文片段数)，而 applyLayout 每次
        // 测高都会调用它，流式播放下会累积成 O(n²)。
        guard contentHasAttachments || !attachmentProviders.isEmpty else { return }

        var usedAttachments = Set<NSTextAttachment>()

        textLayoutManager.enumerateTextLayoutFragments(from: textLayoutManager.documentRange.location, options: [.ensuresLayout]) { fragment in
            let fragmentDocumentOffset = self.textLayoutManager.offset(
                from: self.textLayoutManager.documentRange.location,
                to: fragment.rangeInElement.location
            )

            for textLine in fragment.textLineFragments {
                // NSTextLineFragment.characterRange is relative to its paragraph/layout
                // fragment, while textStorage is indexed from the document origin. Without
                // this offset, every paragraph after the first re-enumerates the first
                // paragraph's attachments and can hide them with a CGRect.zero lookup.
                let relativeLineRange = textLine.characterRange
                let lineRange = NSRange(
                    location: fragmentDocumentOffset + relativeLineRange.location,
                    length: relativeLineRange.length
                )
                guard lineRange.location >= 0,
                      NSMaxRange(lineRange) <= attrString.length else {
                    continue
                }

                attrString.enumerateAttribute(.attachment, in: NSRange(location: lineRange.location, length: lineRange.length)) { value, range, stop in
                    guard let attachment = value as? NSTextAttachment else { return }

                    // 计算附件字符在文档中的位置（用于获取 glyph 矩形）
                    guard let location = self.textLayoutManager.location(self.textLayoutManager.documentRange.location, offsetBy: range.location) else { return }

                    // 尝试获取或创建 Provider
                    var provider = self.attachmentProviders[attachment]

                    if provider == nil {
                        if let newProvider = attachment.viewProvider(for: self, location: location, textContainer: self.textContainer) {
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

                            if let inlineLatex = attachment as? LaTeXAttachment, inlineLatex.isInline {
                                // 行内附件：定位到其 glyph 矩形（而非整个段落 fragment），
                                // 避免公式覆盖/居中到整个段落上。
                                let glyphRect = fragment.frameForTextAttachment(at: location)
                                if glyphRect != .zero {
                                    view.frame = CGRect(
                                        x: fragment.layoutFragmentFrame.origin.x + glyphRect.origin.x,
                                        y: fragment.layoutFragmentFrame.origin.y + glyphRect.origin.y,
                                        width: glyphRect.width,
                                        height: glyphRect.height
                                    )
                                    self.applyInlineAttachmentVisibility(
                                        to: view,
                                        attachment: attachment,
                                        characterIndex: range.location
                                    )
                                } else {
                                    // TextKit 尚未提供有效 glyph frame 时绝不能回退为整段
                                    // fragment，否则附件会覆盖整段文字。等待下一次有效布局。
                                    view.frame = .zero
                                    view.isHidden = true
                                }
                            } else {
                                // 块级附件（表格/代码块/图片/块级公式）：填满 Fragment 区域
                                view.frame = fragment.layoutFragmentFrame
                            }
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
        if textStorage.length > 0 {
            layoutText()
        }

        // 内容写入路径会自行 setNeedsDisplay；这里只兜底处理真实尺寸变化。
        // UITableView self-sizing 会反复调用所有子 TextView 的 layoutSubviews，若每次都
        // 标脏全文，流式高度更新期间已经显示的段落会持续清空/重绘，表现为画面闪烁。
        if consumeDisplayBoundsChange(bounds.size) {
            setNeedsDisplay()
        }
    }

    func consumeDisplayBoundsChange(_ size: CGSize) -> Bool {
        guard size.width > 0, size.height > 0 else { return false }
        let changed = abs(size.width - lastDisplayInvalidationBoundsSize.width) > 0.5
            || abs(size.height - lastDisplayInvalidationBoundsSize.height) > 0.5
        guard changed else { return false }
        lastDisplayInvalidationBoundsSize = size
        return true
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        guard let context = UIGraphicsGetCurrentContext() else { return }

        // 不能按 rect 裁剪片段、也不能提前终止枚举：
        // applyLayout 是"先量高、再改约束"，约束要到下一个布局周期才生效，
        // 且 append 打字机起点会把高度显式设成 1pt，所以 draw 期间 bounds 常常
        // 远小于内容高度。据此裁剪会只画出第一个片段。
        var hasFragments = false
        textLayoutManager.enumerateTextLayoutFragments(from: textLayoutManager.documentRange.location, options: [.ensuresLayout]) { fragment in
            hasFragments = true
            fragment.draw(at: fragment.layoutFragmentFrame.origin, in: context)
            return true
        }

        // Fallback: 如果 TextKit 2 没有生成任何片段（但有文本），说明布局引擎在视图隐藏时可能未正确更新
        // 使用 NSAttributedString 直接绘制以确保内容可见
        if !hasFragments, textStorage.length > 0 {
            textStorage.draw(in: rect)
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

        guard offset >= 0 && offset < textStorage.length else { return }

        let attributes = textStorage.attributes(at: offset, effectiveRange: nil)

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

    private struct AssociatedKeys {
        static var lastRevealedIndex = "lastRevealedIndex"  // ⭐️ 新增：追踪上次显示位置
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

    /// 在编辑事务内就地修改 textStorage。
    ///
    /// 给 `textContentStorage.attributedString` 赋值是整篇替换，TextKit 2 会失效全文布局；
    /// 打字机每一步都这么做就退化成 O(n²)。事务内改 storage 只会失效被改动的范围。
    private func editTextStorage(_ body: (NSTextStorage) -> Void) {
        textContentStorage.performEditingTransaction {
            body(textStorage)
        }
    }

    /// 准备打字机效果：将所有文字设为透明，但保留布局占位
    func prepareForTypewriter() {
        guard textStorage.length > 0 else {
            mdLog("[TYPEWRITER] ⚠️ prepareForTypewriter 失败: textStorage 为空")
            return
        }

        // 优先直接持有不可变的 attributedText 作为原文快照（免拷贝）；
        // 极端情况下才回退到拷贝 textStorage。textStorage 在播放期间会被就地增量修改，
        // 而 attributedText 保持不变。
        let attr: NSAttributedString = attributedText ?? NSAttributedString(attributedString: textStorage)

        mdLog("[TYPEWRITER] 🎯 prepareForTypewriter 开始, 文本长度: \(attr.length), 内容: \(attr.string.prefix(50))...")

        // ⭐️ 重置显示位置
        lastRevealedIndex = 0
        cachedOriginalAttributedString = attr
        isAppendingTypewriterText = false

        // 缓存行内公式附件的字符索引（用于打字机期间控制可见性）
        cacheInlineAttachmentIndexes(in: attr)
        setInlineAttachmentRevealLimit(0)

        // ⚡️ 强制触发布局，确保高度和位置在开始打字前是正确的
        // 这能防止在 hidden = false 瞬间因为布局未完成而导致的闪烁或跳动
        layoutIfNeeded()

        if typewriterTextMode == .append {
            isAppendingTypewriterText = true
            setStorageContent(nil)
            // createTextView 可能使用了整段文本的预计算高度。开始 append 播放时必须
            // 丢弃这个最终高度，否则根视图 show 时会先暴露一块尚未显示的空白区域。
            heightConstraint?.constant = 1
            calculatedHeight = 1
            invalidateIntrinsicContentSize()
            textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
            setNeedsDisplay()
            mdLog("[TYPEWRITER] 🎯 prepareForTypewriter 完成 (append)")
            return
        }

        // reveal 模式：整篇先置为透明占位，后续按范围恢复原属性
        let mutable = NSMutableAttributedString(attributedString: attr)
        let fullRange = NSRange(location: 0, length: attr.length)

        // 1. 设置全透明
        mutable.addAttribute(.foregroundColor, value: UIColor.clear, range: fullRange)

        // 2. ⭐️ 核心修复：移除 .link 属性
        // 防止系统（或TextKit）强制渲染链接颜色，导致文字无法隐藏
        mutable.removeAttribute(.link, range: fullRange)

        setStorageContent(mutable)

        // ⭐️ 关键修复：强制 TextKit 2 重新布局，确保透明属性立即生效
        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
        setNeedsDisplay()

        mdLog("[TYPEWRITER] 🎯 prepareForTypewriter 完成")
    }

    /// 缓存行内公式附件的字符索引（打字机期间按揭示进度控制其可见性）
    private func cacheInlineAttachmentIndexes(in attr: NSAttributedString) {
        var indexes: [NSTextAttachment: Int] = [:]
        attr.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attr.length), options: []) { value, range, _ in
            if let attachment = value as? LaTeXAttachment, attachment.isInline {
                indexes[attachment] = range.location
            }
        }
        inlineAttachmentCharacterIndexes = indexes
    }

    private func setInlineAttachmentRevealLimit(_ limit: Int?) {
        inlineAttachmentRevealLimit = limit
        for (attachment, provider) in attachmentProviders {
            guard (attachment as? LaTeXAttachment)?.isInline == true,
                  let view = provider.view else { continue }
            let charIndex = inlineAttachmentCharacterIndexes[attachment] ?? Int.max
            applyInlineAttachmentVisibility(
                to: view,
                attachment: attachment,
                characterIndex: charIndex
            )
        }
    }

    private func applyInlineAttachmentVisibility(
        to view: UIView,
        attachment: NSTextAttachment,
        characterIndex: Int
    ) {
        guard (attachment as? LaTeXAttachment)?.isInline == true else { return }
        if let limit = inlineAttachmentRevealLimit {
            view.isHidden = characterIndex >= limit
        } else {
            view.isHidden = false
        }
    }

    /// 揭示前 N 个字符（支持批量显示）。
    /// - Returns: 本次是否显示了新字符，以及重新测量后高度是否真的改变。
    func revealCharacter(upto index: Int) -> (didReveal: Bool, didChangeHeight: Bool, heightDelta: CGFloat) {
        guard index > 0 else { return (false, false, 0) }

        if typewriterTextMode == .append {
            guard let originalAttr = cachedOriginalAttributedString else {
                return (false, false, 0)
            }

            let length = originalAttr.length
            if index > length { return (false, false, 0) }

            let startIndex = lastRevealedIndex
            let endIndex = index
            guard endIndex > startIndex else { return (false, false, 0) }
            setInlineAttachmentRevealLimit(endIndex)

            let range = NSRange(location: startIndex, length: endIndex - startIndex)
            let segment = originalAttr.attributedSubstring(from: range)

            // 只把新增片段追加进 storage，让 TextKit 2 仅失效末尾布局
            editTextStorage { $0.append(segment) }

            lastRevealedIndex = endIndex

            // ⚠️ 这里必须每次都重新测高，不能按字符数节流。
            //
            // 软折行（word wrap）不产生 "\n"，也不一定正好攒够 N 个字符，但文本一旦
            // 被 append 进 storage，TextKit 就已经把它排成了新的一行。此时若不同步
            // heightConstraint，新行就没有位置：外层 Cell 的 UIView-Encapsulated-Layout-Height
            // 是 required，会把它压掉，直到若干字符之后高度才被补上——表现为
            // 流式输出时"只在折行那一刻"闪一下。reveal 模式没有这个问题，因为它
            // 一开始就按全文布局好，揭示字符不改变高度。
            //
            // 实测（40 字符窄容器，逐帧与独立参考视图比对"当前前缀真正需要的高度"）：
            // 按 20 字符节流时 74 帧中有 56 帧的内容高于报出的高度，最多欠 39pt（约两行）；
            // 每帧测高后该数字为 0。
            //
            // 成本：`revealCharacter` 由 CADisplayLink 驱动，每帧批量揭示多个字符（非每字符
            // 调用一次），因此测高次数只放大约 3 倍。但要注意 `applyLayout` 里的
            // `ensureLayout(for: documentRange)` **并非纯增量**——实测全程播放耗时随文本长度
            // 呈超线性（每翻倍约 3.8x），新旧实现都是 O(n²)，此改动只放大常数、未改变复杂度阶。
            // 超长单条回答（8000 字符以上）的流式尾段仍有可感开销，若日后要优化，
            // 方向是缩小 ensureLayout 的范围而不是恢复字符数节流（那会直接换回视觉闪烁）。
            //
            // 向宿主上报才是真正昂贵的（触发 performBatchUpdates），所以节流放在
            // "高度是否真的变了"这一层——上报频率因此等于折行频率，而不是字符频率。
            let layoutWidth = textContainer.size.width > 0 ? textContainer.size.width : bounds.width
            guard layoutWidth > 0 else {
                setNeedsLayout()
                return (true, false, 0)
            }

            let previousHeight = heightConstraint?.constant ?? calculatedHeight
            applyLayout(width: layoutWidth, force: true)
            let currentHeight = heightConstraint?.constant ?? calculatedHeight
            let heightDelta = currentHeight - previousHeight

            return (true, abs(heightDelta) > 0.5, heightDelta)
        }

        guard let originalAttr = attributedText,
              cachedOriginalAttributedString != nil else {
            mdLog("[TYPEWRITER] ⚠️ revealCharacter 提前返回: attributedText=\(attributedText != nil), prepared=\(cachedOriginalAttributedString != nil), index=\(index)")
            return (false, false, 0)
        }

        let length = originalAttr.length
        if index > length { return (false, false, 0) }

        // ⭐️ 批量支持：从上次位置到当前位置，显示所有字符
        let startIndex = lastRevealedIndex
        let endIndex = index

        // 如果没有新字符需要显示，直接返回
        guard endIndex > startIndex else { return (false, false, 0) }
        setInlineAttachmentRevealLimit(endIndex)

        // 按属性 run 恢复原始属性（含被 prepare 移除的 .link 与被覆盖的前景色）。
        // setAttributes 会整块替换该范围的属性，效果等价于原先逐字符
        // removeAttribute(.foregroundColor) + addAttributes(原属性)，但调用次数
        // 从字符数降为 run 数，且改动就地发生、不再整篇替换 storage。
        let revealedRange = NSRange(location: startIndex, length: endIndex - startIndex)
        editTextStorage { storage in
            originalAttr.enumerateAttributes(in: revealedRange, options: []) { attributes, subrange, _ in
                storage.setAttributes(attributes, range: subrange)
            }
        }

        // 更新上次显示位置
        lastRevealedIndex = endIndex

        // 强制重绘。不做局部脏化：UIKit 会把同一帧内的多次 setNeedsDisplay(rect)
        // 合并成整个 bounds 的一次 draw，省不下来，反而要承担矩形算错就漏画的风险。
        setNeedsDisplay()

        // reveal 模式预先保留完整布局，显示字符不会改变高度。
        return (true, false, 0)
    }
}

// MARK: - NSTextLayoutManagerDelegate
@available(iOS 15.0, *)
extension MarkdownTextViewTK2: NSTextLayoutManagerDelegate {
    /// 接管 TextKit 2 的链接渲染属性。
    /// 系统默认会给 .link 文本加蓝色前景色 + 下划线；通过此代理方法用外部注入的
    /// linkTextAttributes 替换，从而实现对下划线等样式的精确控制。
    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        renderingAttributesForLink link: Any,
        at location: NSTextLocation,
        defaultAttributes renderingAttributes: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any]? {
        return linkTextAttributes.isEmpty ? renderingAttributes : linkTextAttributes
    }
}
