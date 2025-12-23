//
//  MarkdownDisplayView.swift
//  MarkdownDisplayView
//
//  Created by 朱继超 on 12/15/25.
//

import UIKit
import Foundation
import Combine
import NaturalLanguage

// MARK: - TextKit2 TextView

/// 使用 TextKit 2 的自定义 TextView
@available(iOS 15.0, *)
class MarkdownTextViewTK2: UIView {
    
    private let textLayoutManager: NSTextLayoutManager
    private let textContentStorage: NSTextContentStorage
    private let textContainer: NSTextContainer
    
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
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
            return
        }

        // 1. 更新 TextKit 存储
        textContentStorage.attributedString = attributedText
        
        // 2. 标记需要重绘 (但不立即触发布局，等待外部显式调用 applyLayout 或 layoutSubviews)
        // 这里的关键是：不要使用 bounds.width 进行猜测性布局，防止"旧宽度"导致的高度跳变
        setNeedsDisplay()
    }

    private func layoutText() {
        // ⭐️ 修复 1: 增加防抖检查。
        // 如果宽度没有实质性变化（比如布局循环中微小的浮点误差），或者是 0，
        // 就不要重新触发昂贵的 TextKit 布局，防止覆盖掉外部递归计算出的正确宽度。
        if bounds.width > 0 && abs(bounds.width - textContainer.size.width) > 0.5 {
            applyLayout(width: bounds.width, force: false)
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

// MARK: - MarkdownViewTextKit

/// TextKit 2 版本的 Markdown 渲染视图
@available(iOS 15.0, *)
public final class MarkdownViewTextKit: UIView {
    
    // MARK: - Properties
    
    public var configuration: MarkdownConfiguration = .default {
        didSet { scheduleRerender() }
    }
    
    public var markdown: String = "" {
        didSet { scheduleRerender() }
    }
    
    public var onLinkTap: ((URL) -> Void)?
    public var onImageTap: ((String) -> Void)?
    public var onHeightChange: ((CGFloat) -> Void)?
    public var onTOCItemTap: ((MarkdownTOCItem) -> Void)?
    // 🆕 新增：用于暂存流式输出结束时的回调
    private var onStreamComplete: (() -> Void)?
    // 新增属性来存储原子区间
    private var streamAtomicRanges: [NSRange] = []
    
    public private(set) var tableOfContents: [MarkdownTOCItem] = []
    
    private let contentStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.alignment = .fill
        sv.spacing = 0
        return sv
    }()
    
    private var cancellables = Set<AnyCancellable>()
    private var imageAttachments: [(attachment: MarkdownImageAttachment, urlString: String)] = []
    private var renderWorkItem: DispatchWorkItem?
    private var refreshWorkItem: DispatchWorkItem?

    private var headingViews: [String: UIView] = [:]
    private var oldElements: [MarkdownRenderElement] = []

    // 异步渲染队列（串行，避免并发渲染）
    private let renderQueue = DispatchQueue(label: "com.markdown.render", qos: .userInitiated)

    // 渲染版本控制（解决竞态问题）
    private var renderVersion: Int = 0
    private let renderVersionLock = NSLock()
    
    /// About streaming
    private var streamTimer: Timer?
    private var streamFullText: String = ""
    private var streamCurrentIndex: Int = 0
    private var isStreaming = true {
        didSet {
            if !isStreaming {
                
            }
        }
    }

    private var streamTokens: [String] = []
    private var streamTokenIndex: Int = 0

    // ⭐️ 新增：暂停显示控制
    private var isPausedForDisplay: Bool = false
    
    // ⭐️ 新增：用户交互锁定标记，防止流式更新打断点击事件处理
    private var isUserInteractingWithDetails: Bool = false
    
    // 添加属性
    private var tocSectionView: UIView?
    private var tocSectionId: String?


    /// 是否存在目录区域
    public var hasTableOfContentsSection: Bool {
        return tocSectionView != nil
    }
    
    private var autoScrollEnabled: Bool = false

    // 流式渲染节流（避免过度渲染）
    private var lastStreamRenderTime: TimeInterval = 0
    private let streamRenderThrottle: TimeInterval = 0.05  // 50ms 节流

    // MARK: - Initialization

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    public convenience init(markdown: String, configuration: MarkdownConfiguration = .default) {
        self.init(frame: .zero)
        self.configuration = configuration
        self.markdown = markdown
        scheduleRerender()
    }
    
    private func setupUI() {
        addSubview(contentStackView)
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    
    // MARK: - Public Methods
    
    /// 跳转到文档内的目录区域
    public func backToTableOfContentsSection() {
        guard let view = tocSectionView else { return }
        
        var scrollView: UIScrollView?
        var superview = self.superview
        while superview != nil {
            if let sv = superview as? UIScrollView {
                scrollView = sv
                break
            }
            superview = superview?.superview
        }
        
        guard let sv = scrollView else { return }
        
        let frame = view.convert(view.bounds, to: sv)
        let targetY = max(0, frame.origin.y - 12)
        let maxY = max(0, sv.contentSize.height - sv.bounds.height + sv.contentInset.bottom)
        
        sv.setContentOffset(CGPoint(x: 0, y: min(targetY, maxY)), animated: true)
    }
    
    public func scrollToTOCItem(_ item: MarkdownTOCItem) {
        guard let view = headingViews[item.id] else { return }
        
        var scrollView: UIScrollView?
        var superview = self.superview
        while superview != nil {
            if let sv = superview as? UIScrollView {
                scrollView = sv
                break
            }
            superview = superview?.superview
        }
        
        guard let sv = scrollView else { return }
        
        let frame = view.convert(view.bounds, to: sv)
        let targetY = frame.origin.y - 12
        let maxY = max(0, sv.contentSize.height - sv.bounds.height + sv.contentInset.bottom)
        let clampedY = min(max(0, targetY), maxY)
        
        sv.setContentOffset(CGPoint(x: 0, y: clampedY), animated: true)
    }
    
    public func generateTOCView() -> UIView {
        let tocStackView = UIStackView()
        tocStackView.axis = .vertical
        tocStackView.spacing = 8
        tocStackView.alignment = .leading
        
        for item in tableOfContents {
            let button = UIButton(type: .system)
            let indent = String(repeating: "    ", count: item.level - 1)
            button.setTitle("\(indent)• \(item.title)", for: .normal)
            button.titleLabel?.font = configuration.bodyFont
            button.contentHorizontalAlignment = .left
            button.tag = tableOfContents.firstIndex(where: { $0.id == item.id }) ?? 0
            button.addTarget(self, action: #selector(tocItemTapped(_:)), for: .touchUpInside)
            tocStackView.addArrangedSubview(button)
        }
        
        return tocStackView
    }
    
    @objc private func tocItemTapped(_ sender: UIButton) {
        let index = sender.tag
        guard index < tableOfContents.count else { return }
        let item = tableOfContents[index]
        onTOCItemTap?(item)
        scrollToTOCItem(item)
    }
    
    // MARK: - Rendering

    /// ⭐️ 判断元素是否可以复用（不需要删除重建）
    private func canReuseElement(old: MarkdownRenderElement, new: MarkdownRenderElement) -> Bool {
        switch (old, new) {
        case (.attributedText, .attributedText):
            return true  // 文本类型相同，可以原地更新
        case (.heading, .heading):
            return true  // 标题类型相同，即使ID不同也可以更新
        case (.latex, .latex):
            return true  // LaTeX类型相同，即使内容不同也可以更新
        case (.codeBlock, .codeBlock):
            return true  // 代码块可以原地更新
        case (.quote(_, let oldLevel), .quote(_, let newLevel)):
            return oldLevel == newLevel  // 层级相同可复用
        case (.image, .image):
            return true  // 图片类型相同，可以重新加载
        case (.thematicBreak, .thematicBreak):
            return true
        case (.table, .table):
            return false  // 表格比较复杂，暂时不复用
        case (.details, .details):
            return true   // 允许复用 Details 视图，以保持展开/收起状态
        default:
            return false  // 类型不同，不可复用
        }
    }

    /// ⭐️ 尝试原地更新元素
    /// - Returns: 是否更新成功。如果返回 false，说明视图结构不兼容（例如 LaTeX 需要变更为滚动视图），需要重建。
    private func updateViewInPlace(_ view: UIView, old: MarkdownRenderElement, new: MarkdownRenderElement, containerWidth: CGFloat) -> Bool {
        // print("[MarkdownDisplayView] 🔧 updateViewInPlace: old=\(old), new=\(new)")

        switch (old, new) {
        case (.attributedText(_), .attributedText(let newText)):
            // 查找 TextKit2 TextView
            var textView: MarkdownTextViewTK2?
            if let tv = view as? MarkdownTextViewTK2 {
                textView = tv
            } else if let tv = view.subviews.first(where: { $0 is MarkdownTextViewTK2 }) as? MarkdownTextViewTK2 {
                textView = tv
            }

            if let textView = textView {
                if textView.attributedText != newText {
                    // 1. 更新文本
                    textView.attributedText = newText
                    textView.linkTextAttributes = [
                        .foregroundColor: configuration.linkColor,
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                    ]
                    
                    // ⭐️ 核心修复：显式指定 containerWidth 进行布局计算
                    // 之前的 didSet 逻辑使用的是 textView.bounds.width，这可能是旧的或者错误的（例如 Cell 复用时）
                    // 导致计算出的高度不匹配当前的实际宽度要求 -> 文字被截断
                    textView.applyLayout(width: containerWidth, force: true)
                }
                return true
            }

        case (.heading(let oldId, _), .heading(let newId, let newText)):
            // 更新 ID 映射
            if oldId != newId {
                if let mappedView = headingViews[oldId], mappedView == view {
                    headingViews.removeValue(forKey: oldId)
                    headingViews[newId] = view
                    if tocSectionId == oldId {
                        tocSectionId = newId
                    }
                }
            }
            
            // 更新文本并强制布局
            if let textView = view as? MarkdownTextViewTK2 {
                if textView.attributedText != newText {
                    textView.attributedText = newText
                    textView.applyLayout(width: containerWidth, force: true)
                }
            } else if let textView = view.subviews.first(where: { $0 is MarkdownTextViewTK2 }) as? MarkdownTextViewTK2 {
                if textView.attributedText != newText {
                    textView.attributedText = newText
                    textView.applyLayout(width: containerWidth, force: true)
                }
            }
            return true

        case (.codeBlock(_), .codeBlock(let newText)):
            if let textView = view.subviews.first(where: { $0 is MarkdownTextViewTK2 }) as? MarkdownTextViewTK2 {
                if textView.attributedText != newText {
                    textView.attributedText = newText
                    // CodeBlock padding: leading 12 + trailing 12 = 24
                    let codeBlockWidth = max(0, containerWidth - 24)
                    textView.applyLayout(width: codeBlockWidth, force: true)
                }
            }
            return true

        case (.quote(_, let oldLevel), .quote(let newText, let newLevel)):
            if oldLevel == newLevel,
               let textView = view.subviews.first?.subviews.first(where: { $0 is MarkdownTextViewTK2 }) as? MarkdownTextViewTK2 {
                if textView.attributedText != newText {
                    textView.attributedText = newText
                    // Quote padding calculation:
                    // Outer container leading: (level - 1) * 20
                    // Bar width: 4
                    // TextView leading offset from bar: 12
                    // TextView trailing offset: 8
                    // Total reduction = ((level - 1) * 20) + 4 + 12 + 8
                    let indent = CGFloat(oldLevel - 1) * 20
                    let padding = indent + 4 + 12 + 8
                    let quoteWidth = max(0, containerWidth - padding)
                    textView.applyLayout(width: quoteWidth, force: true)
                }
                return true
            }

        case (.latex, .latex(let newLatex)):
            // LaTeX 特殊处理：检查是否需要切换 Scroll/Non-Scroll 模式
            
            // 1. 计算新内容需要的尺寸
            let newSize = LatexMathView.calculateSize(latex: newLatex, fontSize: 22, padding: 20)
            let needsScroll = newSize.width > containerWidth
            
            // 2. 检查当前视图结构
            let isCurrentScrollView = view.subviews.first is UIScrollView
            
            // 3. 如果模式不匹配，返回 false (请求重建)
            if needsScroll != isCurrentScrollView {
                return false
            }
            
            // 4. 模式匹配，执行更新
            var mathView: LatexMathView?
            var scrollView: UIScrollView?
            
            if let v = view.subviews.first(where: { $0 is LatexMathView }) as? LatexMathView {
                mathView = v
            } else if let sv = view.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView,
                      let v = sv.subviews.first(where: { $0 is LatexMathView }) as? LatexMathView {
                scrollView = sv
                mathView = v
            }
            
            if let mathView = mathView {
                mathView.latex = newLatex
                if let scrollView = scrollView {
                    scrollView.contentSize = newSize
                    mathView.frame = CGRect(origin: .zero, size: newSize)
                }
                return true
            }

        case (.details(let oldSummary, let oldChildren), .details(let newSummary, let newChildren)):
            // 🛑 如果用户正在交互，跳过本次 Details 的更新，防止状态重置/冲突
            if isUserInteractingWithDetails {
                return true
            }

            // 1. 验证视图结构 (支持 Content Wrapper 结构)
            guard let containerStack = view as? UIStackView,
                  containerStack.arrangedSubviews.count >= 2,
                  let summaryButton = containerStack.arrangedSubviews[0] as? UIButton,
                  let contentWrapper = containerStack.arrangedSubviews[1] as? UIView,
                  let contentContainer = contentWrapper.subviews.first as? UIStackView
            else { return false }
            
            // 2. 更新 Summary
            // 保持当前的展开状态符号 (基于 wrapper 可见性)
            let isExpanded = !contentWrapper.isHidden
            let prefix = isExpanded ? "▼ " : "▶ "
            if oldSummary != newSummary {
                summaryButton.setTitle(prefix + newSummary, for: .normal)
            }
            
            // 3. 更新 Children (Diff & Patch)
            // 计算内容宽度 (Details padding: 12+12 = 24)
            let contentWidth = max(0, containerWidth - 24)
            
            var newSubviews: [UIView] = []
            var consumedOldIndices = Set<Int>()
            var searchStart = 0
            let existingSubviews = contentContainer.arrangedSubviews
            
            for newChild in newChildren {
                var foundIndex = -1
                let searchEnd = min(searchStart + 5, oldChildren.count)
                
                for i in searchStart..<searchEnd {
                    if consumedOldIndices.contains(i) { continue }
                    if i >= existingSubviews.count { continue }
                    
                    let oldChild = oldChildren[i]
                    if canReuseElement(old: oldChild, new: newChild) {
                        let candidateView = existingSubviews[i]
                        if updateViewInPlace(candidateView, old: oldChild, new: newChild, containerWidth: contentWidth) {
                            foundIndex = i
                            break
                        }
                    }
                }
                
                if foundIndex != -1 {
                    consumedOldIndices.insert(foundIndex)
                    if foundIndex == searchStart { searchStart += 1 }
                    newSubviews.append(existingSubviews[foundIndex])
                } else {
                    let newView = createView(for: newChild, containerWidth: contentWidth)
                    newSubviews.append(newView)
                }
            }
            
            // Reconcile Subviews
            for (index, subview) in newSubviews.enumerated() {
                if index < contentContainer.arrangedSubviews.count {
                    let current = contentContainer.arrangedSubviews[index]
                    if current != subview {
                        contentContainer.insertArrangedSubview(subview, at: index)
                    }
                } else {
                    contentContainer.addArrangedSubview(subview)
                }
            }
            
            while contentContainer.arrangedSubviews.count > newSubviews.count {
                contentContainer.arrangedSubviews.last?.removeFromSuperview()
            }
            
            // 如果当前是展开状态，强制子视图重新布局
            if isExpanded {
                 for subview in contentContainer.arrangedSubviews {
                     recursivelyUpdateLayout(for: subview, width: contentWidth)
                 }
            }
            
            return true

        case (.image(let oldSrc, _), .image(let newSrc, _)):
            if oldSrc != newSrc {
                if let imageView = view.subviews.first(where: { $0 is ImageView }) as? ImageView {
                    imageView.image(with: newSrc, placeHolder: imageView.image)
                    imageView.accessibilityIdentifier = newSrc
                }
            }
            return true
            
        case (.thematicBreak, .thematicBreak):
            return true

        default:
            break
        }
        
        return false
    }
    
    private func scheduleRerender() {
        // ⭐️ 如果暂停显示，跳过渲染
        guard !isPausedForDisplay else { return }

        renderWorkItem?.cancel()

        if isStreaming {
            // 流式模式：节流渲染，避免过度
            let now = CACurrentMediaTime()
            let timeSinceLastRender = now - lastStreamRenderTime

            if timeSinceLastRender >= streamRenderThrottle {
                // 距离上次渲染已超过节流时间，立即渲染
                lastStreamRenderTime = now
                performRender()
            } else {
                // 还在节流期内，延迟到节流时间后渲染
                let delay = streamRenderThrottle - timeSinceLastRender
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self = self, self.isStreaming else { return }
                    self.lastStreamRenderTime = CACurrentMediaTime()
                    self.performRender()
                }
                renderWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
            }
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.performRender()
        }
        renderWorkItem = workItem

        // 延迟执行以合并多次快速更新
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016, execute: workItem)
    }
    
    private func performRender() {
        let markdownText = markdown
        let config = configuration
        let containerWidth = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width - 32

        // 增加渲染版本号（线程安全）
        renderVersionLock.lock()
        renderVersion += 1
        let currentVersion = renderVersion
        renderVersionLock.unlock()

        renderQueue.async { [weak self] in
            guard let self else { return }

            let startTime = CFAbsoluteTimeGetCurrent()

            // 预处理脚注
            let (processedMarkdown, footnotes) = self.preprocessFootnotes(markdownText)

            // 直接渲染，获取所有需要的返回
            let renderer = MarkdownRenderer(configuration: config, containerWidth: containerWidth)
            let (newElements, attachments, tocItems, tocSectionId) = renderer.render(processedMarkdown)

            let endTime = CFAbsoluteTimeGetCurrent()
            if !isStreaming {
                print("[MarkdownDisplayView] parse took \(endTime - startTime) seconds")
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                // ⭐️ 关键：只使用最新版本的渲染结果
                self.renderVersionLock.lock()
                let isLatestVersion = currentVersion == self.renderVersion
                self.renderVersionLock.unlock()

                guard isLatestVersion else {
                    print("[MarkdownDisplayView] 丢弃旧版本渲染结果 (version \(currentVersion))")
                    return
                }

                self.tableOfContents = tocItems
                self.tocSectionId = tocSectionId
                self.imageAttachments = attachments
                self.updateViews(newElements: newElements, footnotes: footnotes, containerWidth: containerWidth)
            }
        }
    }
    
    private func updateViews(newElements: [MarkdownRenderElement], footnotes: [MarkdownFootnote], containerWidth: CGFloat) {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        var newSubviews: [UIView] = []
        var consumedOldIndices = Set<Int>()
        var searchStart = 0
        
        // --- 1. 智能 Diff & Patch ---
        for newElement in newElements {
            var foundIndex = -1
            
            // 设置搜索窗口（例如向后看5个元素），处理插入/删除造成的索引偏移
            let searchEnd = min(searchStart + 5, oldElements.count)
            
            for i in searchStart..<searchEnd {
                if consumedOldIndices.contains(i) { continue }
                
                let oldElement = oldElements[i]
                
                // 1. 检查类型是否兼容
                if canReuseElement(old: oldElement, new: newElement) {
                    // 2. 尝试执行更新 (如果 LaTeX 模式改变，这里会返回 false)
                    if let candidateView = contentStackView.arrangedSubviews[safe: i],
                       updateViewInPlace(candidateView, old: oldElement, new: newElement, containerWidth: containerWidth) {
                        foundIndex = i
                        break
                    }
                }
            }
            
            if foundIndex != -1 {
                // ✅ 复用成功
                consumedOldIndices.insert(foundIndex)
                // 优化：如果刚好是当前搜索起点，推进起点
                if foundIndex == searchStart { searchStart += 1 }
                
                if let view = contentStackView.arrangedSubviews[safe: foundIndex] {
                    newSubviews.append(view)
                }
            } else {
                // 🆕 无法复用，创建新视图
                let newView = createView(for: newElement, containerWidth: containerWidth)
                newSubviews.append(newView)
                
                // 注册目录
                if case .heading(let id, _) = newElement {
                    headingViews[id] = newView
                    if id == tocSectionId {
                        tocSectionView = newView
                    }
                }
            }
        }
        
        // --- 2. 协调 StackView (Reconcile) ---
        // 此时 newSubviews 包含了正确的视图顺序（复用的 + 新建的）
        // 我们需要把 contentStackView 调整成 newSubviews 的样子
        
        for (index, view) in newSubviews.enumerated() {
            if index < contentStackView.arrangedSubviews.count {
                let currentView = contentStackView.arrangedSubviews[index]
                
                if currentView != view {
                    // 视图位置不对，插入正确视图（UIStackView 会自动移动已存在的视图）
                    contentStackView.insertArrangedSubview(view, at: index)
                }
                // 如果 currentView == view，说明位置正确，无需操作
            } else {
                // 追加新视图
                contentStackView.addArrangedSubview(view)
            }
        }
        
        // --- 3. 清理多余视图 ---
        while contentStackView.arrangedSubviews.count > newSubviews.count {
            contentStackView.arrangedSubviews.last?.removeFromSuperview()
        }
        
        // --- 4. 脚注处理 ---
        updateFootnotes(footnotes, width: containerWidth, newElementCount: newElements.count)
        
        finishUpdate(newElements: newElements, startTime: startTime)
    }

    private func updateFootnotes(_ footnotes: [MarkdownFootnote], width: CGFloat, newElementCount: Int) {
        // 此时 contentStackView 的 subviews 数量应该是 newElementCount (如果不含脚注)
        // 先移除旧的脚注视图（如果存在）
        // 简单的逻辑：如果当前 subviews 数量 > newElementCount，说明最后那个是脚注，删掉
        if contentStackView.arrangedSubviews.count > newElementCount {
             contentStackView.arrangedSubviews.last?.removeFromSuperview()
        }
        
        if !footnotes.isEmpty {
            let footnoteView = createFootnoteView(footnotes: footnotes, width: width)
            contentStackView.addArrangedSubview(footnoteView)
        }
    }
    
    private func finishUpdate(newElements: [MarkdownRenderElement], startTime: Double) {
        oldElements = newElements
        loadImages()
        invalidateIntrinsicContentSize()
        notifyHeightChange()
        
        // let endTime = CFAbsoluteTimeGetCurrent()
        // print("[MarkdownDisplayView] UI update took \(endTime - startTime) seconds")
    }
    
    private func createView(for element: MarkdownRenderElement, containerWidth: CGFloat) -> UIView {
        switch element {
        case .heading(_, let attributedString):
            return createTextView(
                with: attributedString,
                width: containerWidth,
                insets: UIEdgeInsets(top: configuration.headingTopSpacing, left: 0, bottom: configuration.headingBottomSpacing, right: 0)
            )

        case .attributedText(let attributedString):
            if attributedString.length > 0 {
                return createTextView(
                    with: attributedString,
                    width: containerWidth,
                    insets: UIEdgeInsets(top: configuration.paragraphTopSpacing, left: 0, bottom: configuration.paragraphBottomSpacing, right: 0)
                )
            } else {
                return UIView()
            }

        case .table(let tableData):
            return createTableView(with: tableData, containerWidth: containerWidth)

        case .thematicBreak:
            return createThematicBreakView(width: containerWidth)
        case .codeBlock(let attributedString):
            return createCodeBlockView(with: attributedString, width: containerWidth)
        case .quote(let attributedString, let level):
            return createQuoteView(with: attributedString, width: containerWidth, level: level)

        case .details(let summary, let children):
            return createDetailsView(summary: summary, children: children, width: containerWidth)
        case .image(let source, let altText):
            return createImageView(source: source, altText: altText, width: containerWidth)
        case .latex(let latex):
            return createLatexView(latex: latex, width: containerWidth)
        case .rawHTML:
            return UIView()
        }
    }
    
    /// 创建 LaTeX 公式视图
    private func createLatexView(latex: String, width: CGFloat) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // 使用 LatexMathView.createScrollableView 创建公式视图
        let formulaView = LatexMathView.createScrollableView(
            latex: latex,
            fontSize: 22,
            maxWidth: width,
            padding: 20,
            backgroundColor: UIColor.systemGray6.withAlphaComponent(0.5)
        )

        formulaView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(formulaView)

        // 获取公式视图的实际尺寸
        let formulaSize = LatexMathView.calculateSize(
            latex: latex,
            fontSize: 22,
            padding: 20
        )

        // 设置约束
        NSLayoutConstraint.activate([
            formulaView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            formulaView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            formulaView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            formulaView.widthAnchor.constraint(equalToConstant: min(formulaSize.width, width)),
            formulaView.heightAnchor.constraint(equalToConstant: formulaSize.height)
        ])

        return container
    }

    private func createImageView(source: String, altText: String, width: CGFloat) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let imageView = ImageView(frame: .zero)
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isUserInteractionEnabled = true
        imageView.layer.cornerRadius = 8
        container.addSubview(imageView)
        
        // 点击手势
        let tap = UITapGestureRecognizer(target: self, action: #selector(imageViewTapped(_:)))
        imageView.addGestureRecognizer(tap)
        imageView.accessibilityIdentifier = source
        
        // 高度约束
        let heightConstraint = imageView.heightAnchor.constraint(equalToConstant: configuration.imagePlaceholderHeight)
        heightConstraint.priority = .defaultHigh
        
        // 宽度约束（用于图片加载后更新）
        let widthConstraint = imageView.widthAnchor.constraint(equalToConstant: width)
        widthConstraint.priority = .defaultHigh
        
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            widthConstraint,
            heightConstraint,
        ])
        
        // 用占位图加载
        let placeholderImage = createPlaceholderImage(
            size: CGSize(width: width, height: configuration.imagePlaceholderHeight),
            text: altText
        )
        
        // 使用你的 ImageView 加载方法
        imageView.image(with: source, placeHolder: placeholderImage) { [weak heightConstraint, weak widthConstraint] image in
            guard let image = image else { return }
            
            let imageSize = image.size
            guard imageSize.width > 0 && imageSize.height > 0 else { return }
            
            let aspectRatio = imageSize.width / imageSize.height
            var targetWidth = min(imageSize.width, width)
             var targetHeight = targetWidth / aspectRatio
            
            if targetHeight > self.configuration.imageMaxHeight {
                targetHeight = self.configuration.imageMaxHeight
                targetWidth = targetHeight * aspectRatio
            }
            
            widthConstraint?.constant = targetWidth
            heightConstraint?.constant = targetHeight
        }
        
        return container
    }
    
    private func createPlaceholderImage(size: CGSize, text: String) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            configuration.imagePlaceholderColor.setFill()
            let rect = CGRect(origin: .zero, size: size)
            UIBezierPath(roundedRect: rect, cornerRadius: 8).fill()
            
            let iconSize: CGFloat = 40
            let iconRect = CGRect(
                x: (size.width - iconSize) / 2,
                y: (size.height - iconSize) / 2 - 15,
                width: iconSize,
                height: iconSize
            )
            
            let iconConfig = UIImage.SymbolConfiguration(pointSize: 36, weight: .light)
            if let icon = UIImage(systemName: "photo", withConfiguration: iconConfig) {
                UIColor.secondaryLabel.setFill()
                icon.draw(in: iconRect)
            }
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13),
                .foregroundColor: UIColor.secondaryLabel,
                .paragraphStyle: paragraphStyle,
            ]
            
            let displayText = text.isEmpty ? "Loading..." : text
            let textRect = CGRect(x: 16, y: (size.height + iconSize) / 2 - 5, width: size.width - 32, height: 20)
            displayText.draw(in: textRect, withAttributes: attributes)
        }
    }

    @objc private func imageViewTapped(_ gesture: UITapGestureRecognizer) {
        if let source = gesture.view?.accessibilityIdentifier {
            onImageTap?(source)
        }
    }

    private func loadImageForView(source: String, into imageView: UIImageView, heightConstraint: NSLayoutConstraint, maxWidth: CGFloat, maxHeight: CGFloat) {
        var urlString = source
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://" + urlString
        }
        
        guard let url = URL(string: urlString) else { return }
        
        ImageLoader.shared.loadImage(from: url)
            .receive(on: DispatchQueue.main)
            .sink { [weak imageView, weak heightConstraint] image in
                guard let imageView = imageView, let image = image else { return }
                
                let imageSize = image.size
                guard imageSize.width > 0 && imageSize.height > 0 else { return }
                
                let aspectRatio = imageSize.width / imageSize.height
                var targetWidth = min(imageSize.width, maxWidth)
                var targetHeight = targetWidth / aspectRatio
                
                if targetHeight > maxHeight {
                    targetHeight = maxHeight
                    targetWidth = targetHeight * aspectRatio
                }
                
                imageView.image = image
                imageView.backgroundColor = .clear
                heightConstraint?.constant = targetHeight
                imageView.widthAnchor.constraint(equalToConstant: targetWidth).isActive = true
            }
            .store(in: &cancellables)
    }
    
    private func createCodeBlockView(with attributedString: NSAttributedString, width: CGFloat) -> UIView {
        let container = UIView()
        container.backgroundColor = configuration.codeBackgroundColor
        container.layer.cornerRadius = 8
        container.layer.masksToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false

        let textView = MarkdownTextViewTK2()
        textView.attributedText = attributedString
        textView.backgroundColor = .clear
        textView.translatesAutoresizingMaskIntoConstraints = false

        // 🔥 核心修复:立即应用布局,计算文本实际可用宽度(减去 padding)
        let codeBlockWidth = max(0, width - 24)  // left 12 + right 12
        textView.applyLayout(width: codeBlockWidth, force: true)

        container.addSubview(textView)

        // 🔥 修复：宽度约束优先级降低，避免与父容器冲突
        let widthConstraint = container.widthAnchor.constraint(equalToConstant: width)
        widthConstraint.priority = .defaultHigh  // 优先级 750，可被父容器覆盖

        NSLayoutConstraint.activate([
            widthConstraint,
            textView.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            textView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            textView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])

        return container
    }
    
    // MARK: - Text View Creation (修复版)
        
        private func createTextView(
            with attributedString: NSAttributedString,
            width: CGFloat,
            insets: UIEdgeInsets = .zero
        ) -> UIView {
            let container = UIView()
            container.translatesAutoresizingMaskIntoConstraints = false
            
            let textView = MarkdownTextViewTK2()
            textView.attributedText = attributedString
            textView.linkTextAttributes = [
                .foregroundColor: configuration.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]
            textView.onLinkTap = { [weak self] url in
                self?.handleLinkTap(url)
            }
            textView.onImageTap = { [weak self] urlString in
                self?.onImageTap?(urlString)
            }
            textView.translatesAutoresizingMaskIntoConstraints = false
            
            // 🔥 核心修复：立即应用布局
            // 计算文本实际可用的宽度（减去内边距）
            let contentWidth = width - insets.left - insets.right
            if contentWidth > 0 {
                textView.applyLayout(width: contentWidth, force: true)
            }
            
            container.addSubview(textView)
            
            NSLayoutConstraint.activate([
                textView.topAnchor.constraint(equalTo: container.topAnchor, constant: insets.top),
                textView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: insets.left),
                textView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -insets.right),
                textView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -insets.bottom),
            ])
            
            // 保持垂直方向的抗压缩优先级，防止被压缩
            container.setContentHuggingPriority(.required, for: .vertical)
            container.setContentCompressionResistancePriority(.required, for: .vertical)
            
            return container
        }
    
    private func handleLinkTap(_ url: URL) {
        // 检查是否是内部锚点链接
        if url.scheme == nil || url.scheme == "markdown" {
            var fragment = url.fragment ?? url.absoluteString.replacingOccurrences(of: "#", with: "")
            
            if let decoded = fragment.removingPercentEncoding {
                fragment = decoded
            }
            
            if !fragment.isEmpty {
                if headingViews[fragment] != nil {
                    scrollToTOCItem(MarkdownTOCItem(level: 1, title: "", id: fragment))
                    return
                }
                
                if let item = tableOfContents.first(where: {
                    $0.title.contains(fragment) || fragment.contains($0.title)
                }) {
                    scrollToTOCItem(item)
                    return
                }
            }
        }
        
        onLinkTap?(url)
    }
    
    // MARK: - Quote View
    
    private func createQuoteView(with attributedString: NSAttributedString, width: CGFloat, level: Int = 1) -> UIView {
        let outerContainer = UIView()
        outerContainer.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.backgroundColor = UIColor.systemGray6.withAlphaComponent(0.5)
        container.layer.cornerRadius = 4
        container.translatesAutoresizingMaskIntoConstraints = false
        outerContainer.addSubview(container)

        // 左侧竖线
        let bar = UIView()
        bar.backgroundColor = configuration.blockquoteBarColor
        bar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bar)

        let textView = MarkdownTextViewTK2()
        textView.attributedText = attributedString
        textView.translatesAutoresizingMaskIntoConstraints = false

        // 🔥 核心修复:立即应用布局,计算引用块文本实际可用宽度
        // Quote padding: 左缩进 + 竖线 + 文本左边距 + 文本右边距
        let indent = CGFloat(level - 1) * 20
        let padding = indent + 4 + 12 + 8  // outerIndent + barWidth + textLeading + textTrailing
        let quoteWidth = max(0, width - padding)
        textView.applyLayout(width: quoteWidth, force: true)

        container.addSubview(textView)

        // 根据层级计算左边距
        let leftIndent = CGFloat(level - 1) * 20

        NSLayoutConstraint.activate([
            outerContainer.widthAnchor.constraint(equalToConstant: width),
            container.topAnchor.constraint(equalTo: outerContainer.topAnchor, constant: 4),
            container.leadingAnchor.constraint(equalTo: outerContainer.leadingAnchor, constant: leftIndent),
            container.trailingAnchor.constraint(equalTo: outerContainer.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: outerContainer.bottomAnchor),

            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.topAnchor.constraint(equalTo: container.topAnchor),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bar.widthAnchor.constraint(equalToConstant: 4),

            textView.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            textView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            textView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])

        return outerContainer
    }
    
    // MARK: - Thematic Break View
    
    private func createThematicBreakView(width: CGFloat) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let lineView = UIView()
        lineView.backgroundColor = configuration.horizontalRuleColor
        lineView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(lineView)
        
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 24),
            container.widthAnchor.constraint(equalToConstant: width),
            lineView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            lineView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            lineView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            lineView.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
        ])
        
        return container
    }
    
    // MARK: - Details View
    
    private func createDetailsView(
        summary: String,
        children: [MarkdownRenderElement],
        width: CGFloat
    ) -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 0
        container.alignment = .fill
        container.distribution = .fill
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let summaryButton = UIButton(type: .system)
        summaryButton.setTitle("▶ " + summary, for: .normal)
        summaryButton.setTitleColor(configuration.linkColor, for: .normal)
        summaryButton.contentHorizontalAlignment = .left
        summaryButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
//        summaryButton.backgroundColor = configuration.codeBackgroundColor
        summaryButton.layer.cornerRadius = 6
        summaryButton.configuration?.contentInsets = .init(top: 8, leading: 12, bottom: 20, trailing: 12)
        summaryButton.setContentHuggingPriority(.required, for: .vertical)
        summaryButton.setContentCompressionResistancePriority(.required, for: .vertical)
        container.addArrangedSubview(summaryButton)
        
        // Wrapper View (Plain UIView to handle hiding cleanly)
        let contentWrapper = UIView()
        contentWrapper.isHidden = true
        contentWrapper.translatesAutoresizingMaskIntoConstraints = false
        contentWrapper.backgroundColor = configuration.codeBackgroundColor
        contentWrapper.layer.cornerRadius = 6
        contentWrapper.layer.masksToBounds = true
        container.addArrangedSubview(contentWrapper)

        let contentContainer = UIStackView()
        contentContainer.axis = .vertical
        contentContainer.spacing = 0
        contentContainer.alignment = .fill
        contentContainer.distribution = .fill
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.layoutMargins = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        contentContainer.isLayoutMarginsRelativeArrangement = true
        contentWrapper.addSubview(contentContainer)
        
        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: contentWrapper.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: contentWrapper.bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: contentWrapper.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: contentWrapper.trailingAnchor)
        ])

        // 🔥 修复：正确计算内容宽度
        // layoutMargins 是 left: 12, right: 12，所以需要减去 24
        let contentWidth = width - 24
        for child in children {
            let childView = createView(for: child, containerWidth: contentWidth)
            if let textView = childView as? MarkdownTextViewTK2,
               textView.attributedText?.length == 0 {
                continue
            }
            contentContainer.addArrangedSubview(childView)
        }
        
        summaryButton.addAction(
            UIAction { [weak self, weak contentWrapper, weak contentContainer, weak summaryButton, weak container] _ in
                guard let self = self,
                      let wrapper = contentWrapper,
                      let content = contentContainer,
                      let btn = summaryButton,
                      let containerWrapper = container
                else { return }
                
                // 🔒 锁定流式更新，防止状态覆盖
                self.isUserInteractingWithDetails = true
                // 1秒后自动解锁，防止永久死锁
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.isUserInteractingWithDetails = false
                }
                
                let willShow = wrapper.isHidden

                // 1. 更新可见性状态
                wrapper.isHidden = !willShow
                wrapper.alpha = willShow ? 1 : 0
                btn.setTitle((willShow ? "▼ " : "▶ ") + summary, for: .normal)

                // 2. 核心修复逻辑
                if willShow {
                    // [Expand Flow]
                    
                    // 恢复子视图优先级
                    content.arrangedSubviews.forEach {
                        $0.isHidden = false
                        $0.setContentCompressionResistancePriority(.required, for: .vertical)
                    }
                    
                    // A. 强制布局
                    wrapper.layoutIfNeeded()
                    content.layoutIfNeeded()

                    // B. 计算实际可用宽度
                    let containerWidth = self.bounds.width > 0 ? self.bounds.width : UIScreen.main.bounds.width - 32
                    let contentWidth = containerWidth - 24 

                    // C. 递归强制更新所有子视图的布局
                    for subview in content.arrangedSubviews {
                        self.recursivelyUpdateLayout(for: subview, width: contentWidth)
                    }
                    
                    // D. 再次强制布局
                    content.layoutIfNeeded()
                    wrapper.layoutIfNeeded()
                    containerWrapper.layoutIfNeeded()
                    
                } else {
                    // [Collapse Flow]
                    
                    // 隐藏子视图 & 降低优先级
                    content.arrangedSubviews.forEach {
                        $0.isHidden = true
                        $0.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
                    }
                    
                    // A. 强制布局
                    content.layoutIfNeeded()
                    wrapper.layoutIfNeeded()
                    
                    // Force invalidation
                    content.invalidateIntrinsicContentSize()
                    wrapper.invalidateIntrinsicContentSize()
                    
                    // B. 强制外层容器布局
                    containerWrapper.layoutIfNeeded()
                }

                // 3. 通知外部 (TableView) 更新
                self.setNeedsLayout()
                self.layoutIfNeeded()
                self.invalidateIntrinsicContentSize()
                
                // 🔥 终极修复：不再依赖 systemLayoutSizeFitting，而是直接计算 StackView 的实际高度
                // 延迟一小段时间等待布局引擎稳定
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    // 强制再次刷新布局
                    self.contentStackView.layoutIfNeeded()
                    
                    // 手动计算高度：遍历所有子视图的 frame
                    var totalHeight: CGFloat = 0
                    for subview in self.contentStackView.arrangedSubviews {
                        if !subview.isHidden {
                            totalHeight += subview.frame.height
                        }
                    }
                    // 加上 spacing
                    let visibleCount = self.contentStackView.arrangedSubviews.filter { !$0.isHidden }.count
                    if visibleCount > 1 {
                        totalHeight += CGFloat(visibleCount - 1) * self.contentStackView.spacing
                    }
                    // 加上 insets (如果有)
                    totalHeight += self.contentStackView.layoutMargins.top + self.contentStackView.layoutMargins.bottom
                    
                    // 强制通知
                    self.lastReportedHeight = totalHeight
                    self.onHeightChange?(totalHeight)
                }
                
            }, for: .touchUpInside)
        
        return container
    }
    
    // 递归查找并更新 MarkdownTextViewTK2 布局
    private func recursivelyUpdateLayout(for view: UIView, width: CGFloat) {
        var currentWidth = width
        
        // 1. 如果遇到 StackView 且启用了 margins，减去 margins (处理嵌套 Details)
        if let stackView = view as? UIStackView, stackView.isLayoutMarginsRelativeArrangement {
            currentWidth = max(0, currentWidth - stackView.layoutMargins.left - stackView.layoutMargins.right)
        }
        
        // 2. 如果是 TextKit2 视图，直接应用布局
        if let textView = view as? MarkdownTextViewTK2 {
            // 优先使用实际宽度（更准确，支持多级嵌套），防止 layout 尚未完成时的 0 宽
            if textView.bounds.width > 1.0 {
                textView.applyLayout(width: textView.bounds.width, force: true)
                return
            }
            
            // Fallback: 使用递归传递下来的 calculated width
            // 需要结合 textView 自身的容器 padding 逻辑
            var availableWidth = currentWidth
            if let superview = textView.superview {
                // CodeBlock container
                if superview.layer.cornerRadius == 8 {
                    availableWidth = max(0, currentWidth - 24)
                } 
                // Quote container
                else if superview.subviews.contains(where: { $0.backgroundColor == configuration.blockquoteBarColor }) {
                    // 简化的 Quote padding 计算
                    let padding: CGFloat = 4 + 12 + 8
                    availableWidth = max(0, currentWidth - padding)
                }
            }
            
            textView.applyLayout(width: availableWidth, force: true)
            return
        }
        
        // 3. 递归查找子视图
        for subview in view.subviews {
            recursivelyUpdateLayout(for: subview, width: currentWidth)
        }
    }

    /// 强制重绘容器内的所有 TextKit2 视图
    private func forceRedrawVisibleTextViews(in view: UIView) {
        if let textView = view as? MarkdownTextViewTK2 {
            textView.setNeedsDisplay()
        }
        
        for subview in view.subviews {
            forceRedrawVisibleTextViews(in: subview)
        }
    }
    
    // MARK: - Table View
    
    private func createTableView(with tableData: MarkdownTableData, containerWidth: CGFloat) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        
        let tableStackView = UIStackView()
        tableStackView.axis = .vertical
        tableStackView.spacing = 0
        tableStackView.distribution = .fill
        tableStackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(tableStackView)
        
        // 计算列宽
        let columnCount = max(tableData.headers.count, tableData.rows.first?.count ?? 0)
        var columnWidths: [CGFloat] = Array(repeating: 80, count: columnCount)
        
        for (index, header) in tableData.headers.enumerated() {
            let width = header.boundingRect(
                with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 44),
                options: [.usesLineFragmentOrigin],
                context: nil
            ).width + 32
            columnWidths[index] = max(columnWidths[index], width)
        }
        
        for row in tableData.rows {
            for (index, cell) in row.enumerated() where index < columnCount {
                let width = cell.boundingRect(
                    with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 44),
                    options: [.usesLineFragmentOrigin],
                    context: nil
                ).width + 32
                columnWidths[index] = max(columnWidths[index], width)
            }
        }
        
        columnWidths = columnWidths.map { min($0, 200) }
        let totalWidth = columnWidths.reduce(0, +)
        
        // 表头行
        let headerRow = createTableRow(cells: tableData.headers, columnWidths: columnWidths, isHeader: true)
        tableStackView.addArrangedSubview(headerRow)
        
        // 分隔线
        let separator = UIView()
        separator.backgroundColor = configuration.tableBorderColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        tableStackView.addArrangedSubview(separator)
        
        // 数据行
        for (index, row) in tableData.rows.enumerated() {
            let rowView = createTableRow(cells: row, columnWidths: columnWidths, isHeader: false)
            if index % 2 == 1 {
                rowView.backgroundColor = configuration.tableAlternateRowBackgroundColor
            }
            tableStackView.addArrangedSubview(rowView)
        }
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            
            tableStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            tableStackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            tableStackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            tableStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            tableStackView.widthAnchor.constraint(equalToConstant: totalWidth),
        ])
        
        let rowHeight: CGFloat = 44
        let tableHeight = rowHeight * CGFloat(tableData.rows.count + 1) + 1
        container.heightAnchor.constraint(equalToConstant: tableHeight).isActive = true
        
        return container
    }
    
    private func createTableRow(
        cells: [NSAttributedString],
        columnWidths: [CGFloat],
        isHeader: Bool
    ) -> UIView {
        let rowStack = UIStackView()
        rowStack.axis = .horizontal
        rowStack.spacing = 0
        rowStack.distribution = .fill
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        
        if isHeader {
            rowStack.backgroundColor = configuration.tableHeaderBackgroundColor
        }
        
        for (index, cell) in cells.enumerated() {
            let cellView = UIView()
            cellView.translatesAutoresizingMaskIntoConstraints = false
            
            let label = UILabel()
            label.attributedText = cell
            label.numberOfLines = 0
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            
            if isHeader {
                label.font = UIFont.systemFont(ofSize: configuration.bodyFont.pointSize, weight: .semibold)
            }
            
            cellView.addSubview(label)
            
            if index < cells.count - 1 {
                let border = UIView()
                border.backgroundColor = configuration.tableBorderColor.withAlphaComponent(0.3)
                border.translatesAutoresizingMaskIntoConstraints = false
                cellView.addSubview(border)
                
                NSLayoutConstraint.activate([
                    border.topAnchor.constraint(equalTo: cellView.topAnchor, constant: 8),
                    border.bottomAnchor.constraint(equalTo: cellView.bottomAnchor, constant: -8),
                    border.trailingAnchor.constraint(equalTo: cellView.trailingAnchor),
                    border.widthAnchor.constraint(equalToConstant: 0.5),
                ])
            }
            
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: cellView.topAnchor, constant: 10),
                label.bottomAnchor.constraint(equalTo: cellView.bottomAnchor, constant: -10),
                label.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 12),
                label.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -12),
            ])
            
            let width = index < columnWidths.count ? columnWidths[index] : 80
            cellView.widthAnchor.constraint(equalToConstant: width).isActive = true
            
            rowStack.addArrangedSubview(cellView)
        }
        
        rowStack.heightAnchor.constraint(equalToConstant: 44).isActive = true
        
        return rowStack
    }
    
    // MARK: - Footnote View
    
    private func createFootnoteView(footnotes: [MarkdownFootnote], width: CGFloat) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 0
        stackView.alignment = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stackView)
        
        // 分隔线
        let separator = UIView()
        separator.backgroundColor = configuration.horizontalRuleColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(separator)
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        separator.widthAnchor.constraint(equalToConstant: width * 0.3).isActive = true
        
        // 间距
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
        stackView.addArrangedSubview(spacer)
        
        // 脚注列表
        for footnote in footnotes {
            let attributedText = NSMutableAttributedString()
            
            let idText = NSAttributedString(
                string: "⁽\(footnote.id)⁾ ",
                attributes: [
                    .font: UIFont.systemFont(ofSize: configuration.bodyFont.pointSize - 2),
                    .foregroundColor: configuration.linkColor,
                    .baselineOffset: 4,
                ])
            attributedText.append(idText)
            
            let contentText = NSAttributedString(
                string: footnote.content,
                attributes: [
                    .font: UIFont.systemFont(ofSize: configuration.bodyFont.pointSize - 2),
                    .foregroundColor: configuration.textColor.withAlphaComponent(0.8),
                ])
            attributedText.append(contentText)
            
            let textView = createTextView(
                with: attributedText,
                width: width,
                insets: UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
            )
            stackView.addArrangedSubview(textView)
        }
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        
        return container
    }
    
    // MARK: - Footnote Preprocessing
    
    private func preprocessFootnotes(_ text: String) -> (String, [MarkdownFootnote]) {
        var processedText = text
        var footnotes: [MarkdownFootnote] = []
        
        let definitionPattern = #"\[\^([^\]]+)\]:\s*(.+)$"#
        if let regex = try? NSRegularExpression(pattern: definitionPattern, options: .anchorsMatchLines) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            
            for match in matches.reversed() {
                if let idRange = Range(match.range(at: 1), in: text),
                   let contentRange = Range(match.range(at: 2), in: text),
                   let fullRange = Range(match.range, in: text) {
                    let id = String(text[idRange])
                    let content = String(text[contentRange])
                    footnotes.insert(MarkdownFootnote(id: id, content: content), at: 0)
                    processedText = processedText.replacingCharacters(in: fullRange, with: "")
                }
            }
        }
        
        let referencePattern = #"\[\^([^\]]+)\]"#
        if let regex = try? NSRegularExpression(pattern: referencePattern, options: []) {
            let matches = regex.matches(in: processedText, range: NSRange(processedText.startIndex..., in: processedText))
            
            for match in matches.reversed() {
                if let idRange = Range(match.range(at: 1), in: processedText),
                   let fullRange = Range(match.range, in: processedText) {
                    let id = String(processedText[idRange])
                    let replacement = "⁽\(id)⁾"
                    processedText = processedText.replacingCharacters(in: fullRange, with: replacement)
                }
            }
        }
        
        return (processedText, footnotes)
    }
    
    // MARK: - Image Loading
    
    private func loadImages() {
        for (attachment, urlString) in imageAttachments {
            loadImage(urlString: urlString, into: attachment)
        }
    }
    
    private func loadImage(urlString: String, into attachment: MarkdownImageAttachment) {
        var processedURLString = urlString
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            processedURLString = "https://" + urlString
        }
        
        guard let url = URL(string: processedURLString) else { return }
        
        ImageLoader.shared.loadImage(from: url)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] image in
                guard let self = self, let image = image else { return }
                
                let imageSize = image.size
                var targetSize = CGSize(width: 100, height: 100)
                
                if imageSize.width > 0 && imageSize.height > 0 {
                    let aspectRatio = ceilf(Float(imageSize.width / imageSize.height))
                    var targetWidth = imageSize.width
                    var targetHeight = imageSize.height
                    
                    // 按宽度缩放
                    if attachment.maxWidth > 0 && targetWidth > attachment.maxWidth {
                        targetWidth = attachment.maxWidth
                        targetHeight = targetWidth / CGFloat(aspectRatio)
                    }
                    
                    // 按高度缩放
                    if attachment.maxHeight > 0 && targetHeight > attachment.maxHeight {
                        targetHeight = attachment.maxHeight
                        targetWidth = targetHeight * CGFloat(aspectRatio)
                    }
                    
                    targetSize = CGSize(width: ceil(targetWidth), height: ceil(targetHeight))
                }
                
                // 直接生成缩放后的图片
                let renderer = UIGraphicsImageRenderer(size: targetSize)
                let scaledImage = renderer.image { _ in
                    image.draw(in: CGRect(origin: .zero, size: targetSize))
                }
                
                attachment.bounds = CGRect(origin: .zero, size: targetSize)
                attachment.image = scaledImage
                
                self.refreshWorkItem?.cancel()
                let workItem = DispatchWorkItem { [weak self] in
                    self?.refreshTextViews()
                }
                self.refreshWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
            }
            .store(in: &cancellables)
    }
    
    private func refreshTextViews() {
        for container in contentStackView.arrangedSubviews {
            for childView in container.subviews {
                if let textView = childView as? MarkdownTextViewTK2 {
                    textView.setNeedsDisplay()
                }
            }
        }
        
        invalidateIntrinsicContentSize()
        notifyHeightChange()
    }
    
    // 记录上次报告的高度，用于防抖和避免死循环
    private var lastReportedHeight: CGFloat = 0
    
    private func notifyHeightChange(force: Bool = false) {
        // ⭐️ 强制 StackView 立即更新布局
        if force {
            self.contentStackView.invalidateIntrinsicContentSize()
        }
        self.contentStackView.layoutIfNeeded()
        
        let size = self.contentStackView.systemLayoutSizeFitting(
            CGSize(width: self.bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        
        let newHeight = size.height
        
        // 只有高度变化超过阈值才通知，避免浮点数误差导致的死循环
        // 如果 force 为 true，忽略防抖检查
        if force || abs(newHeight - lastReportedHeight) > 0.5 {
            // print("[MarkdownDisplayView] 📏 Height Changed: \(lastReportedHeight) -> \(newHeight)")
            lastReportedHeight = newHeight
            self.onHeightChange?(newHeight)
        }
    }
    
    public override var intrinsicContentSize: CGSize {
        let size = contentStackView.systemLayoutSizeFitting(
            CGSize(
                width: bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width - 32,
                height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: UIView.noIntrinsicMetric, height: size.height)
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        // ⭐️ 关键修复：在布局完成后检查高度是否需要修正
        // 这解决了"初始宽度不准导致高度计算错误"的问题（Chicken & Egg problem）
        // 通过对比 lastReportedHeight，我们只在真正需要时触发更新，从而避免死循环
        notifyHeightChange()
    }
    
    //MARK: - streaming method
    /// 计算需要原子化输出的区间（公式、图片、链接）
        private func calculateAtomicRanges(in text: String) -> [NSRange] {
            var ranges: [NSRange] = []
            let nsString = text as NSString
            
            // 定义正则表达式模式
            // 1. 块级公式 $$...$$ (允许换行 (?s))
            let blockMathPattern = "(?s)\\$\\$.*?\\$\\$"
            // 2. 行内公式 $...$ (不允许换行)
            let inlineMathPattern = "\\$[^\\n\\$]+?\\$"
            // 3. 图片 ![alt](url)
            let imagePattern = "!\\[.*?\\]\\(.*?\\)"
            // 4. 链接 [text](url) - 如果你也希望链接整体出现，加上这个
            let linkPattern = "\\[.*?\\]\\(.*?\\)"
            
            // 合并正则 (注意顺序，块级优先于行内)
            // 这里为了演示，把链接也加上去了，你可以根据需要注释掉 linkPattern
            let patterns = [blockMathPattern, inlineMathPattern, imagePattern,linkPattern]
            
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
                    for match in matches {
                        ranges.append(match.range)
                    }
                }
            }
            
            // 排序并合并重叠区间（虽然正则通常分开写，但为了保险）
            ranges.sort { $0.location < $1.location }
            
            return ranges
        }
    // 增加 onStart 参数：通知外部“分词完成，马上开始喷字”
    // 方法签名中增加 onStart 和 onComplete
    public func startStreaming(
            _ text: String,
            unit: StreamingUnit = .word,
            unitsPerChunk: Int = 1,
            interval: TimeInterval = 0.05,
            autoScrollBottom: Bool = false,
            onStart: (() -> Void)? = nil,
            onComplete: (() -> Void)? = nil
        ) {
            autoScrollEnabled = autoScrollBottom
            stopStreaming()
            isStreaming = true
            self.onStreamComplete = onComplete
            // 1. 后台处理：分词 + 原子区间计算
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                let fullText = text
                let tokens = self.tokenize(fullText, unit: unit)
                
                // 🔥 新增：预计算所有需要整体输出的 Range
                let atomicRanges = self.calculateAtomicRanges(in: fullText)
                
                DispatchQueue.main.async {
                    guard self.isStreaming else { return }
                    
                    // 准备开始
                    self.markdown = ""
                    onStart?()
                    
                    self.streamFullText = fullText
                    self.streamTokens = tokens
                    self.streamAtomicRanges = atomicRanges // 保存区间
                    self.streamTokenIndex = 0
                    
                    // 启动 Timer
                    self.streamTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                        self?.appendNextTokensAtomic(count: unitsPerChunk) // 🔥 改用新的 append 方法
                    }
                }
            }
        }
    
    /// 智能追加 Token，支持原子区间跳跃
        private func appendNextTokensAtomic(count: Int) {
            guard streamTokenIndex < streamTokens.count else {
                stopStreaming()
                // 2. 🔥 触发完成回调 (修复点)
                onStreamComplete?()
                
                // 3. 清空回调防止重复调用（可选，视逻辑而定）
                onStreamComplete = nil
                // 触发完成回调（如果有）
                // 注意：之前的代码这里可能漏了 onComplete 的触发，建议补上
                return
            }
            
            // 当前 Markdown 的长度（光标位置）
            let currentLength = (markdown as NSString).length
            
            // 1. 检查当前光标是否位于某个原子区间的“起点”
            // 我们需要找到一个 range，使得 range.location == currentLength
            if let atomicRange = streamAtomicRanges.first(where: { $0.location == currentLength }) {
                
                // 🎯 命中原子区间！
                // 直接截取这整个区间的内容
                let fullTextInfo = streamFullText as NSString
                // 确保 range 不越界（理论上预计算的不会越界，但安全第一）
                if atomicRange.upperBound <= fullTextInfo.length {
                    let chunk = fullTextInfo.substring(with: atomicRange)
                    
                    // 一次性追加整个公式/图片字符串
                    markdown += chunk
                    
                    // ⏩ 关键：我们需要更新 streamTokenIndex，跳过这些 token
                    // 因为 tokens 是碎片化的，我们需要计算跳过了多少字符
                    var skippedLength = 0
                    let targetLength = atomicRange.length
                    
                    // 向前推进 token index，直到跳过的字符总数 >= 原子区间的长度
                    while streamTokenIndex < streamTokens.count {
                        let tokenLen = streamTokens[streamTokenIndex].count
                        skippedLength += tokenLen
                        streamTokenIndex += 1
                        
                        if skippedLength >= targetLength {
                            break
                        }
                    }
                    
                    // 处理自动滚动
                    handleAutoScroll()
                    return // 本次 Tick 结束，等待下一次 Timer
                }
            }
            
            // 2. 如果没有命中原子区间，走普通逻辑
            var nextChunk = ""
            var tokensAdded = 0
            
            // 循环取出 count 个 token
            while streamTokenIndex < streamTokens.count && tokensAdded < count {
                let token = streamTokens[streamTokenIndex]
                
                // 🛑 二次检查：在普通追加的过程中，会不会“误入”原子区间的内部？
                // 现在的逻辑是：如果普通追加的 token 开始位置正好是原子区间的起点，我们应该停止普通追加，
                // 留给下一次 Timer tick 去处理上面的 "if let atomicRange" 逻辑。
                let nextCursor = currentLength + (nextChunk as NSString).length
                if streamAtomicRanges.contains(where: { $0.location == nextCursor }) {
                    // 撞到了原子区间的门口，立即停止，把机会留给下一次循环处理整体输出
                    break
                }
                
                nextChunk += token
                streamTokenIndex += 1
                tokensAdded += 1
            }
            
            markdown += nextChunk
            handleAutoScroll()
        }
        
        private func handleAutoScroll() {
            if autoScrollEnabled {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.scrollToBottom(animated: false)
                }
            }
        }

    private func tokenize(_ text: String, unit: StreamingUnit) -> [String] {
        switch unit {
        case .character:
            return text.map { String($0) }
            
        case .word, .sentence:
            let nlUnit: NLTokenUnit = unit == .word ? .word : .sentence
            var tokens: [String] = []
            
            let tokenizer = NLTokenizer(unit: nlUnit)
            tokenizer.string = text
            
            var lastEnd = text.startIndex
            
            tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
                if lastEnd < range.lowerBound {
                    tokens.append(String(text[lastEnd..<range.lowerBound]))
                }
                tokens.append(String(text[range]))
                lastEnd = range.upperBound
                return true
            }
            
            if lastEnd < text.endIndex {
                tokens.append(String(text[lastEnd..<text.endIndex]))
            }
            
            return tokens
        }
    }

    /// 追加下一批 token
    private func appendNextTokens(count: Int) {
        guard streamTokenIndex < streamTokens.count else {
            stopStreaming()
            return
        }
        
        let endIndex = min(streamTokenIndex + count, streamTokens.count)
        let chunk = streamTokens[streamTokenIndex..<endIndex].joined()
        
        markdown += chunk
        streamTokenIndex = endIndex
        
        // 自动滚动到底部
        if autoScrollEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.scrollToBottom(animated: false)
            }
        }
    }
    
    /// 停止流式渲染
    public func stopStreaming() {
        streamTimer?.invalidate()
        streamTimer = nil
        isPausedForDisplay = false  // 重置暂停状态
    }

    /// 立即显示全部内容
    public func finishStreaming() {
        stopStreaming()
        markdown = streamFullText
        isStreaming = false
    }

    // MARK: - ⭐️ 暂停/恢复显示 API

    /// 暂停显示更新（停止 UI 刷新，但保留流式状态）
    /// 适用场景：用户滚动到上方阅读时，避免底部流式输出导致的 UI 闪烁
    public func pauseDisplayUpdates() {
        guard isStreaming, !isPausedForDisplay else { return }

        isPausedForDisplay = true
        // 停止 Timer，避免继续追加 token
        streamTimer?.invalidate()
        streamTimer = nil
        // 注意：不设置 isStreaming = false，保留流式状态
    }

    /// 恢复显示更新（10倍速追赶）
    /// 快速流式输出剩余内容，避免一次性渲染卡顿
    public func resumeDisplayUpdates() {
        guard isStreaming, isPausedForDisplay else { return }

        isPausedForDisplay = false

        // ⭐️ 计算剩余内容
        let remainingTokens = streamTokens.count - streamTokenIndex

        if remainingTokens <= 0 {
            // 已经全部输出完毕
            isStreaming = false
            onStreamComplete?()
            onStreamComplete = nil
            return
        }

        // ⭐️ 10倍速追赶（150ms间隔，50个token/次）
        // 相比暂停前的 15ms/5token，这是 10 倍速
        let catchUpChunkSize = 50
        let catchUpInterval: TimeInterval = 0.15

        streamTimer = Timer.scheduledTimer(withTimeInterval: catchUpInterval, repeats: true) { [weak self] _ in
            self?.appendNextTokensAtomic(count: catchUpChunkSize)
        }
    }

    private func appendNextChunk(chunkSize: Int) {
        guard streamCurrentIndex < streamFullText.count else {
            stopStreaming()
            return
        }
        
        var endIndex = min(streamCurrentIndex + chunkSize, streamFullText.count)
        
        // 尝试在空格或换行处断开，更自然
        let searchEnd = min(endIndex + 10, streamFullText.count)
        let startIdx = streamFullText.index(streamFullText.startIndex, offsetBy: endIndex)
        let searchIdx = streamFullText.index(streamFullText.startIndex, offsetBy: searchEnd)
        let searchRange = startIdx..<searchIdx
        
        if let spaceRange = streamFullText.range(of: " ", range: searchRange) {
            endIndex = streamFullText.distance(from: streamFullText.startIndex, to: spaceRange.lowerBound) + 1
        }
        
        let index = streamFullText.index(streamFullText.startIndex, offsetBy: endIndex)
        markdown = String(streamFullText[..<index])
        streamCurrentIndex = endIndex
    }
    
    /// 滚动到底部
    public func scrollToBottom(animated: Bool = true) {
        var scrollView: UIScrollView?
        var superview = self.superview
        while superview != nil {
            if let sv = superview as? UIScrollView {
                scrollView = sv
                break
            }
            superview = superview?.superview
        }
        
        guard let sv = scrollView else { return }
        
        let bottomOffset = CGPoint(
            x: 0,
            y: max(0, sv.contentSize.height - sv.bounds.height + sv.contentInset.bottom)
        )
        sv.setContentOffset(bottomOffset, animated: animated)
    }
    
    /// 滚动到顶部
    public func scrollToTop(animated: Bool = true) {
        var scrollView: UIScrollView?
        var superview = self.superview
        while superview != nil {
            if let sv = superview as? UIScrollView {
                scrollView = sv
                break
            }
            superview = superview?.superview
        }
        
        guard let sv = scrollView else { return }
        sv.setContentOffset(CGPoint(x: 0, y: -sv.contentInset.top), animated: animated)
    }
    
}
