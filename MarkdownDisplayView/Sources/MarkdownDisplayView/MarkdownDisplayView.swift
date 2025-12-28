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

// MARK: - MarkdownViewTextKit

/// TextKit 2 版本的 Markdown 渲染视图
@available(iOS 15.0, *)
public final class MarkdownViewTextKit: UIView {
    
    // MARK: - Properties
    
    public var configuration: MarkdownConfiguration = .default {
        didSet { scheduleRerender() }
    }
    
    public var markdown: String = "" {
        didSet {
            // 🔍 性能监控：记录渲染开始时间
            if !isStreaming {
                renderStartTime = CFAbsoluteTimeGetCurrent()
                print("🔍 [Perf] ========== Markdown Set ==========")
            }
            scheduleRerender()
        }
    }
    
    public var onLinkTap: ((URL) -> Void)?
    public var onImageTap: ((String) -> Void)?
    public var onHeightChange: ((CGFloat) -> Void)?
    public var onTOCItemTap: ((MarkdownTOCItem) -> Void)?
    // 🆕 新增：用于暂存流式输出结束时的回调
    private var onStreamComplete: (() -> Void)?
    // 新增属性来存储原子区间
    private var streamAtomicRanges: [NSRange] = []
    // ⚡️ 性能优化：原子区间起始位置索引（O(1)查找）
    private var atomicRangeStartSet: Set<Int> = []
    
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
    private var isStreaming = false  // ✅ 默认非流式模式 

    private var streamTokens: [String] = []
    private var streamTokenIndex: Int = 0
    private var currentStreamingUnit: StreamingUnit = .word

    // ⭐️ 新增：暂停显示控制
    private var isPausedForDisplay: Bool = false

    // ⭐️ 新增：用户交互锁定标记，防止流式更新打断点击事件处理
    private var isUserInteractingWithDetails: Bool = false

    // ⚠️ 视图复用缓存已禁用（会导致内容错位问题）
    // 原因：基于内容hash的缓存策略会导致不同位置的相似内容被错误复用
    // private var viewCache: [String: UIView] = [:]
    // private let maxCacheSize: Int = 100
    
    // 添加属性
    private var tocSectionView: UIView?
    private var tocSectionId: String?
    
    // 脚注优化缓存
    private var currentFootnotes: [MarkdownFootnote] = []
    private var cachedFootnoteView: UIView?

    // ⚡️ 首屏优化：分批渲染配置
    /// 首屏渲染目标高度（屏幕高度的倍数，默认3屏）
    private let firstScreenHeightMultiplier: CGFloat = 3.0
    /// 离屏渲染延迟时间（秒）
    private let offscreenRenderDelay: TimeInterval = 0.05
    /// 离屏渲染工作项（用于取消）
    private var offscreenRenderWorkItem: DispatchWorkItem?
    /// 占位视图（用于预留离屏内容空间，避免布局跳动）
    private var placeholderView: UIView?

    // ⚡️ Performance Monitoring
    private var renderCosts: [String: Double] = [:]
    /// 记录渲染开始时间（从设置 markdown 属性开始）
    private var renderStartTime: CFAbsoluteTime = 0

    // MARK: - 增量解析缓存（流式渲染性能优化）

    /// 解析缓存结构体
    private struct ParseCache {
        var lastParsedLength: Int = 0                    // 上次解析到的字符位置
        var cachedElements: [MarkdownRenderElement] = [] // 已解析的元素
        var cachedFootnotes: [MarkdownFootnote] = []     // 已解析的脚注
        var cachedAttachments: [(attachment: MarkdownImageAttachment, urlString: String)] = []
        var cachedTOCItems: [MarkdownTOCItem] = []
        var tocSectionId: String? = nil
    }

    /// 解析缓存实例
    private var parseCache = ParseCache()

    /// 缓存的容器宽度（用于检测宽度变化）
    private var cachedContainerWidth: CGFloat = 0

    /// 配置哈希值（用于检测配置变化）
    private var configurationHash: Int = 0

    // MARK: - 预解析流式显示（方案B - 进度百分比映射）

    /// 预解析的所有元素
    private var streamParsedElements: [MarkdownRenderElement] = []

    /// 已显示的元素数量
    private var streamDisplayedCount: Int = 0

    /// 预解析的脚注
    private var streamParsedFootnotes: [MarkdownFootnote] = []

    /// 预解析的附件
    private var streamParsedAttachments: [(attachment: MarkdownImageAttachment, urlString: String)] = []

    /// 预解析是否完成
    private var streamPreParseCompleted: Bool = false

    /// 流式文本总长度
    private var streamTotalTextLength: Int = 0

    private func recordCost(for type: String, duration: Double) {
        renderCosts[type, default: 0] += duration
    }

    private func printRenderCosts(totalDuration: Double) {
        guard !renderCosts.isEmpty else { return }
        print("\n--- 📊 UI Render Performance (Total: \(String(format: "%.4f", totalDuration))sÅ) ---")
        let sortedCosts = renderCosts.sorted { $0.value > $1.value }
        for (type, cost) in sortedCosts {
            let percentage = (cost / totalDuration) * 100
            if cost > 0.0005 { // Filter out negligible costs (< 0.5ms)
                print(String(format: "   🔸 %-15@ : %.4fs  (%5.1f%%)", type, cost, percentage))
            }
        }
        print("-----------------------------------------------------")
    }

    /// 是否存在目录区域
    public var hasTableOfContentsSection: Bool {
        return tocSectionView != nil
    }
    
    private var autoScrollEnabled: Bool = false

    // 流式渲染节流（避免过度渲染）
    private var lastStreamRenderTime: TimeInterval = 0
    private let streamRenderThrottle: TimeInterval = 0.3  // 300ms 节流（大幅降低CPU占用）

    // MARK: - Initialization

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    deinit {
        // ⚡️ 取消待执行的离屏渲染任务
        offscreenRenderWorkItem?.cancel()
        // ⚡️ 移除内存警告监听
        NotificationCenter.default.removeObserver(self)
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

        // ⚡️ 监听内存警告，清理视图缓存
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    @objc private func handleMemoryWarning() {
        clearViewCache()
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

    /// 判断两个元素是否完全相等（用于嵌套复用检查）
    private func elementsAreEqual(_ old: MarkdownRenderElement, _ new: MarkdownRenderElement) -> Bool {
        switch (old, new) {
        case (.latex(let oldLatex), .latex(let newLatex)):
            return oldLatex == newLatex

        case (.attributedText(let oldText), .attributedText(let newText)):
            return oldText == newText

        case (.heading(let oldId, let oldText), .heading(let newId, let newText)):
            return oldId == newId && oldText == newText

        case (.codeBlock(let oldCode), .codeBlock(let newCode)):
            return oldCode == newCode

        case (.image(let oldSrc, let oldAlt), .image(let newSrc, let newAlt)):
            return oldSrc == newSrc && oldAlt == newAlt

        case (.thematicBreak, .thematicBreak):
            return true

        case (.rawHTML(let oldHTML), .rawHTML(let newHTML)):
            return oldHTML == newHTML

        // ⚡️ 嵌套结构的深度比较
        case (.quote(let oldChildren, let oldLevel), .quote(let newChildren, let newLevel)):
            guard oldLevel == newLevel, oldChildren.count == newChildren.count else { return false }
            for (oldChild, newChild) in zip(oldChildren, newChildren) {
                if !elementsAreEqual(oldChild, newChild) { return false }
            }
            return true

        case (.list(let oldItems, let oldLevel), .list(let newItems, let newLevel)):
            guard oldLevel == newLevel, oldItems.count == newItems.count else { return false }
            for (oldItem, newItem) in zip(oldItems, newItems) {
                guard oldItem.marker == newItem.marker,
                      oldItem.children.count == newItem.children.count else { return false }
                for (oldChild, newChild) in zip(oldItem.children, newItem.children) {
                    if !elementsAreEqual(oldChild, newChild) { return false }
                }
            }
            return true

        case (.details(let oldSummary, let oldChildren), .details(let newSummary, let newChildren)):
            guard oldSummary == newSummary, oldChildren.count == newChildren.count else { return false }
            for (oldChild, newChild) in zip(oldChildren, newChildren) {
                if !elementsAreEqual(oldChild, newChild) { return false }
            }
            return true

        case (.table(let oldData), .table(let newData)):
            // 简单比较行列数
            return oldData.headers.count == newData.headers.count &&
                   oldData.rows.count == newData.rows.count

        default:
            return false  // 类型不匹配
        }
    }

    /// ⭐️ 判断元素是否可以复用（不需要删除重建）
    private func canReuseElement(old: MarkdownRenderElement, new: MarkdownRenderElement) -> Bool {
        switch (old, new) {
        case (.attributedText, .attributedText):
            return true  // 文本类型相同，可以原地更新
        case (.heading, .heading):
            return true  // 标题类型相同，即使ID不同也可以更新
        case (.latex(let oldLatex), .latex(let newLatex)):
            // print("🔍 [canReuseElement] LaTeX: old=\(oldLatex.prefix(20))... new=\(newLatex.prefix(20))... → true")
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
            return true  // 表格现在使用 CollectionView，支持原地更新
        case (.details, .details):
            return true   // 允许复用 Details 视图，以保持展开/收起状态
        case (.list(_, let oldLevel), .list(_, let newLevel)):
            return oldLevel == newLevel  // 层级相同可复用
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

        // ⚡️ Quote 子元素复用优化（避免重复创建嵌套公式）
        case (.quote(let oldChildren, let oldLevel), .quote(let newChildren, let newLevel)):
            // 层级不同，需要重建
            if oldLevel != newLevel {
                print("⚠️ [Quote] Level changed: \(oldLevel) → \(newLevel), rebuilding")
                return false
            }

            // 1. 验证视图结构 (Quote: outerContainer -> container -> contentStack)
            guard let outerContainer = view as? UIView,
                  outerContainer.subviews.count > 0,
                  let container = outerContainer.subviews.first,
                  let contentStack = container.subviews.first(where: { $0 is UIStackView }) as? UIStackView
            else {
                print("⚠️ [Quote] View structure validation failed, rebuilding. view type: \(type(of: view)), subviews: \(view.subviews.count)")
                return false
            }

            // 2. 计算内容宽度 (Quote padding: leftIndent + 4 + 12 + 8)
            let leftIndent: CGFloat = (oldLevel > 1) ? 20 : 0
            let padding = leftIndent + 4 + 12 + 8
            let contentWidth = max(0, containerWidth - padding)

            // 3. Diff & Patch 子视图（类似 Details 的实现）
            var newSubviews: [UIView] = []
            var consumedOldIndices = Set<Int>()
            var searchStart = 0
            let existingSubviews = contentStack.arrangedSubviews

            for (childIndex, newChild) in newChildren.enumerated() {
                var foundIndex = -1
                let searchEnd = min(searchStart + 5, oldChildren.count)

                // 在窗口范围内查找可复用的视图
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
                    // 找到可复用的视图
                    consumedOldIndices.insert(foundIndex)
                    if foundIndex == searchStart { searchStart += 1 }
                    newSubviews.append(existingSubviews[foundIndex])
                } else {
                    // 创建新视图
                    let newView = createView(for: newChild, containerWidth: contentWidth)
                    newSubviews.append(newView)
                }
            }

            // 4. Reconcile Subviews
            for (index, subview) in newSubviews.enumerated() {
                if index < contentStack.arrangedSubviews.count {
                    let current = contentStack.arrangedSubviews[index]
                    if current != subview {
                        contentStack.insertArrangedSubview(subview, at: index)
                    }
                } else {
                    contentStack.addArrangedSubview(subview)
                }
            }

            // 移除多余的旧视图
            while contentStack.arrangedSubviews.count > newSubviews.count {
                contentStack.arrangedSubviews.last?.removeFromSuperview()
            }

            return true

        case (.table(let oldData), .table(let newData)):
            if oldData == newData { return true }
            
            // Re-create attachment with new data
            let attachment = MarkdownTableAttachment(
                data: newData,
                config: configuration,
                containerWidth: containerWidth
            )
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .left
            
            let attrString = NSMutableAttributedString(attachment: attachment)
            attrString.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: attrString.length))
            
            // Find and update TextView
            if let textView = view as? MarkdownTextViewTK2 {
                textView.attributedText = attrString
                textView.applyLayout(width: containerWidth, force: true)
                return true
            } else if let textView = view.subviews.first(where: { $0 is MarkdownTextViewTK2 }) as? MarkdownTextViewTK2 {
                textView.attributedText = attrString
                textView.applyLayout(width: containerWidth, force: true)
                return true
            }
            return false

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
            
            for (childIndex, newChild) in newChildren.enumerated() {
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
                    // 创建新视图
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
            
        case (.latex(let oldLatex), .latex(let newLatex)):
             // ⚡️ 性能优化：如果 LaTeX 内容没有变化，直接复用，避免 TextKit2 重新创建 ViewProvider
             if oldLatex == newLatex {
                 return true
             }
             // 如果内容变了（流式更新中比较少见，除非公式本身在变），目前没有原地更新逻辑，返回 false 触发重建
             return false
            
        case (.thematicBreak, .thematicBreak):
            return true

        // ⚡️ List 子元素复用优化（支持流式增量更新）
        case (.list(let oldItems, let oldLevel), .list(let newItems, let newLevel)):
            // 层级不同，需要重建
            if oldLevel != newLevel {
                print("⚠️ [List] Level changed: \(oldLevel) → \(newLevel), rebuilding")
                return false
            }

            // ⚡️ 允许 items 数量不同（流式渲染场景）
            // 只要新增的 items，其他部分可以复用
            print("♻️ [List] Updating list: oldItems=\(oldItems.count) → newItems=\(newItems.count)")

            // 1. 验证视图结构 (List: indentWrapper (UIView) -> container (UIStackView))
            // ⚠️ 注意：createListView 返回的是 indentWrapper，不是 container！
            guard view.subviews.count > 0,
                  let container = view.subviews.first as? UIStackView else {
                let firstSubviewType = view.subviews.first.map { "\(type(of: $0))" } ?? "nil"
                print("⚠️ [List] View structure validation failed, view type: \(type(of: view)), subviews: \(view.subviews.count), first subview: \(firstSubviewType)")
                return false
            }

            // 2. 计算内容宽度和标记宽度
            let indent: CGFloat = configuration.listIndent
            let currentIndent = (oldLevel > 1) ? indent : 0
            let contentMaxWidth = max(0, containerWidth - currentIndent)

            // 预计算最大标记宽度
            let maxMarkerWidth: CGFloat = {
                var maxWidth: CGFloat = 20
                for item in newItems {
                    let markerText = item.marker as NSString
                    let size = markerText.size(withAttributes: [.font: configuration.bodyFont])
                    maxWidth = max(maxWidth, ceil(size.width) + 4)
                }
                return maxWidth
            }()

            let itemContentWidth = contentMaxWidth - maxMarkerWidth - 4

            // 3. Diff & Patch 列表项
            let existingItemViews = container.arrangedSubviews
            var needsReconcile = false

            for (itemIndex, newItem) in newItems.enumerated() {
                if itemIndex < oldItems.count && itemIndex < existingItemViews.count {
                    // 尝试复用现有列表项
                    let oldItem = oldItems[itemIndex]

                    if oldItem.marker == newItem.marker,
                       oldItem.children.count == newItem.children.count {
                        // 检查子元素是否完全相同
                        var allChildrenMatch = true
                        for (oldChild, newChild) in zip(oldItem.children, newItem.children) {
                            if !elementsAreEqual(oldChild, newChild) {
                                allChildrenMatch = false
                                break
                            }
                        }

                        if allChildrenMatch {
                            // 完全相同，直接复用，无需操作
                            continue
                        } else {
                            // 子元素不同，尝试更新
                            if let itemStack = existingItemViews[itemIndex] as? UIStackView,
                               itemStack.arrangedSubviews.count >= 2,
                               let contentStack = itemStack.arrangedSubviews[1] as? UIStackView {

                                var newChildViews: [UIView] = []
                                let existingChildViews = contentStack.arrangedSubviews

                                for (childIndex, newChild) in newItem.children.enumerated() {
                                    if childIndex < oldItem.children.count,
                                       childIndex < existingChildViews.count {
                                        let oldChild = oldItem.children[childIndex]
                                        if canReuseElement(old: oldChild, new: newChild) {
                                            let childView = existingChildViews[childIndex]
                                            if updateViewInPlace(childView, old: oldChild, new: newChild, containerWidth: itemContentWidth) {
                                                newChildViews.append(childView)
                                                continue
                                            }
                                        }
                                    }
                                    // 创建新子视图
                                    let isFirst = (childIndex == 0)
                                    let childView = createView(for: newChild, containerWidth: itemContentWidth, suppressTopSpacing: isFirst, suppressBottomSpacing: true)
                                    newChildViews.append(childView)
                                }

                                // Reconcile 子视图
                                for (index, subview) in newChildViews.enumerated() {
                                    if index < contentStack.arrangedSubviews.count {
                                        let current = contentStack.arrangedSubviews[index]
                                        if current != subview {
                                            contentStack.insertArrangedSubview(subview, at: index)
                                        }
                                    } else {
                                        contentStack.addArrangedSubview(subview)
                                    }
                                }

                                while contentStack.arrangedSubviews.count > newChildViews.count {
                                    contentStack.arrangedSubviews.last?.removeFromSuperview()
                                }

                                continue
                            } else {
                                // 视图结构不符合预期，需要重建此项
                                needsReconcile = true
                                break
                            }
                        }
                    } else {
                        // marker 或子元素数量不同，需要重建此项
                        needsReconcile = true
                        break
                    }
                } else {
                    // ⚡️ 新增的列表项：创建新视图并添加
                    let itemStack = UIStackView()
                    itemStack.axis = .horizontal
                    itemStack.alignment = .top
                    itemStack.spacing = 4
                    itemStack.translatesAutoresizingMaskIntoConstraints = false

                    // 标记
                    let markerLabel = UILabel()
                    markerLabel.text = newItem.marker
                    markerLabel.font = configuration.bodyFont
                    markerLabel.textColor = configuration.textColor
                    markerLabel.setContentHuggingPriority(.required, for: .horizontal)
                    markerLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
                    markerLabel.widthAnchor.constraint(equalToConstant: maxMarkerWidth).isActive = true
                    markerLabel.textAlignment = .right
                    itemStack.addArrangedSubview(markerLabel)

                    // 内容容器
                    let contentStack = UIStackView()
                    contentStack.axis = .vertical
                    contentStack.spacing = 4
                    contentStack.alignment = .fill
                    contentStack.translatesAutoresizingMaskIntoConstraints = false

                    for (childIndex, childElement) in newItem.children.enumerated() {
                        let isFirst = (childIndex == 0)
                        let childView = createView(for: childElement, containerWidth: itemContentWidth, suppressTopSpacing: isFirst, suppressBottomSpacing: true)
                        contentStack.addArrangedSubview(childView)
                    }

                    itemStack.addArrangedSubview(contentStack)
                    container.addArrangedSubview(itemStack)
                }
            }

            // 如果出现需要重建的情况，返回 false 触发完整重建
            if needsReconcile {
                print("⚠️ [List] needsReconcile=true, triggering full rebuild")
                return false
            }

            // 移除多余的旧列表项
            while container.arrangedSubviews.count > newItems.count {
                container.arrangedSubviews.last?.removeFromSuperview()
            }

            print("✅ [List] Successfully updated, reused existing views")
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
        // ⚡️ 取消待执行的离屏渲染任务（因为内容已变更）
        offscreenRenderWorkItem?.cancel()

        // ⚡️ 移除占位视图（如果存在）
        if let placeholder = placeholderView {
            placeholder.removeFromSuperview()
            placeholderView = nil
        }

        if isStreaming {
            // ⚡️ 流式模式：如果预解析完成，只更新显示（不解析）
            if streamPreParseCompleted {
                // 预解析已完成，直接更新流式显示
                updateStreamDisplay()
            } else {
                // 预解析未完成，等待（正常情况下不会走到这里）
                print("⏳ [Stream] Waiting for pre-parse to complete...")
            }
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.performRender()
        }
        renderWorkItem = workItem

        // 🔍 性能监控：打印调度延迟
        if renderStartTime > 0 {
            let elapsed = (CFAbsoluteTimeGetCurrent() - renderStartTime) * 1000
            print("🔍 [Perf] scheduleRerender: +\(String(format: "%.1f", elapsed))ms (delay 16ms)")
        }

        // 延迟执行以合并多次快速更新
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016, execute: workItem)
    }

    // MARK: - 预解析流式显示核心函数

    /// 基于当前字符进度更新流式显示（简化版：百分比映射 + 节流）
    private func updateStreamDisplay() {
        guard streamPreParseCompleted else { return }
        guard streamTotalTextLength > 0 else { return }
        guard !streamParsedElements.isEmpty else { return }

        let currentLength = (markdown as NSString).length
        let containerWidth = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width - 32

        // 简单百分比映射（避免字符估算误差）
        let progress = Double(currentLength) / Double(streamTotalTextLength)
        var targetIndex = Int(Double(streamParsedElements.count) * progress)

        // 确保至少显示1个，最多显示全部
        targetIndex = max(1, min(streamParsedElements.count, targetIndex))

        var hasChanges = false

        // 显示新增的元素
        if targetIndex > streamDisplayedCount {
            print("📺 [Stream] Showing elements \(streamDisplayedCount)..<\(targetIndex)")
            for i in streamDisplayedCount..<targetIndex {
                let element = streamParsedElements[i]
                print("  ├─ Element[\(i)]: \(elementTypeString(element))")
                let view = createView(for: element, containerWidth: containerWidth)
                view.tag = 1000 + i
                contentStackView.addArrangedSubview(view)

                // 注册 heading
                if case .heading(let id, _) = element {
                    headingViews[id] = view
                    if id == tocSectionId { tocSectionView = view }
                }
            }

            streamDisplayedCount = targetIndex
            oldElements = Array(streamParsedElements.prefix(streamDisplayedCount))
            hasChanges = true
        }

        // ⚡️ 流式结束时，显示所有剩余元素 + 脚注
        if currentLength >= streamTotalTextLength {
            // 显示剩余元素
            if streamDisplayedCount < streamParsedElements.count {
                print("🎬 [Stream Complete] Showing remaining \(streamParsedElements.count - streamDisplayedCount) elements")

                for i in streamDisplayedCount..<streamParsedElements.count {
                    let element = streamParsedElements[i]
                    let view = createView(for: element, containerWidth: containerWidth)
                    view.tag = 1000 + i
                    contentStackView.addArrangedSubview(view)

                    if case .heading(let id, _) = element {
                        headingViews[id] = view
                        if id == tocSectionId { tocSectionView = view }
                    }
                }

                streamDisplayedCount = streamParsedElements.count
                oldElements = streamParsedElements
                hasChanges = true
            }

            // 显示脚注（延迟100ms确保所有元素都已显示）
            if !streamParsedFootnotes.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self = self else { return }
                    let currentViewCount = self.contentStackView.arrangedSubviews.count

                    // 只有在还没有脚注时才添加
                    if currentViewCount == self.streamParsedElements.count {
                        print("📝 [Stream Complete] Showing \(self.streamParsedFootnotes.count) footnotes")
                        self.updateFootnotes(self.streamParsedFootnotes, width: containerWidth, newElementCount: self.streamParsedElements.count)
                        self.notifyHeightChange()
                    }
                }
            }
        }

        if hasChanges {
            notifyHeightChange()
        }
    }


    // MARK: - 增量解析优化

    /// 判断是否需要清空缓存并重新全量解析（仅用于非流式场景）
    private func shouldInvalidateCache(newMarkdown: String, containerWidth: CGFloat) -> Bool {
        // 1. 内容变短（用户删除内容）
        if (newMarkdown as NSString).length < parseCache.lastParsedLength {
            return true
        }

        // 2. 宽度变化超过1pt（影响表格/代码块布局）
        if abs(containerWidth - cachedContainerWidth) > 1.0 {
            return true
        }

        // 3. 缓存为空（首次渲染）
        if parseCache.lastParsedLength == 0 {
            return true
        }

        return false
    }

    /// 执行增量解析（仅解析新增内容）
    private func performIncrementalParse(
        fullText: String,
        config: MarkdownConfiguration,
        containerWidth: CGFloat,
        perfStartTime: CFAbsoluteTime
    ) {
        let newLength = (fullText as NSString).length
        let lastParsedLength = parseCache.lastParsedLength

        // 1️⃣ 计算上下文窗口（向前回溯，处理跨行结构如列表、引用块）
        // ⚡️ 性能优化：减小窗口避免过度解析（500 → 100）
        let contextWindowSize = 100  // 回溯100字符（足够捕获列表/引用块前缀）
        let parseStartIndex = max(0, lastParsedLength - contextWindowSize)

        // 2️⃣ 提取需要解析的片段
        let nsText = fullText as NSString
        let incrementalRange = NSRange(location: parseStartIndex, length: newLength - parseStartIndex)
        let incrementalText = nsText.substring(with: incrementalRange)

        let deltaSize = newLength - lastParsedLength
        let parseSize = incrementalText.count
        print("⚡️ [Incremental] Range: \(parseStartIndex)..\(newLength) | Delta: \(deltaSize) chars | Parse: \(parseSize) chars (window: \(contextWindowSize))")
        print("⚡️ [Incremental] Cache: \(parseCache.cachedElements.count) elements, \(lastParsedLength) chars")

        // 3️⃣ 异步解析增量内容
        renderQueue.async { [weak self] in
            guard let self else { return }

            let parseStart = CFAbsoluteTimeGetCurrent()

            // 预处理脚注
            let (processedIncremental, newFootnotes) = self.preprocessFootnotes(incrementalText)

            // 解析增量内容
            let renderer = MarkdownRenderer(configuration: config, containerWidth: containerWidth)
            let (incrementalElements, newAttachments, newTOCItems, newTocId) = renderer.render(processedIncremental)

            let parseEnd = CFAbsoluteTimeGetCurrent()
            let parseDuration = parseEnd - parseStart

            print("⚡️ [Incremental] Parse completed: \(incrementalElements.count) elements in \(String(format: "%.1f", parseDuration * 1000))ms")

            // 4️⃣ 回到主线程合并结果
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                self.mergeIncrementalResults(
                    incrementalElements: incrementalElements,
                    contextWindowSize: contextWindowSize,
                    newFootnotes: newFootnotes,
                    newAttachments: newAttachments,
                    newTOCItems: newTOCItems,
                    newTocId: newTocId,
                    newLength: newLength,
                    containerWidth: containerWidth,
                    perfStartTime: perfStartTime,
                    parseDuration: parseDuration
                )
            }
        }
    }

    /// 智能合并增量解析结果
    private func mergeIncrementalResults(
        incrementalElements: [MarkdownRenderElement],
        contextWindowSize: Int,
        newFootnotes: [MarkdownFootnote],
        newAttachments: [(attachment: MarkdownImageAttachment, urlString: String)],
        newTOCItems: [MarkdownTOCItem],
        newTocId: String?,
        newLength: Int,
        containerWidth: CGFloat,
        perfStartTime: CFAbsoluteTime,
        parseDuration: Double
    ) {
        // 🧩 合并策略：
        // ⚡️ 性能优化：流式渲染时不移除任何视图，只追加真正新增的元素

        let oldElementCount = parseCache.cachedElements.count

        // 1️⃣ 增量解析返回的元素包含：上下文窗口元素 + 新增元素
        // 我们需要跳过上下文窗口内的元素（已经渲染过了）

        // 计算上下文窗口可能对应的元素数量（保守估计1-2个）
        let contextOverlapEstimate = min(2, parseCache.cachedElements.count)

        // 2️⃣ 只追加真正新增的元素（跳过上下文重叠部分）
        let trueNewElements = incrementalElements.count > contextOverlapEstimate
            ? Array(incrementalElements.dropFirst(contextOverlapEstimate))
            : []

        print("⚡️ [Incremental] Parsed \(incrementalElements.count) elements, skipping \(contextOverlapEstimate) overlap, adding \(trueNewElements.count) new")

        // 3️⃣ 追加新元素到缓存
        parseCache.cachedElements.append(contentsOf: trueNewElements)

        // 4️⃣ 只为真正新增的元素创建视图（避免重复创建）
        for element in trueNewElements {
            let view = createView(for: element, containerWidth: containerWidth)
            contentStackView.addArrangedSubview(view)
        }

        print("⚡️ [Incremental] Total elements: \(parseCache.cachedElements.count), views: \(contentStackView.arrangedSubviews.count)")

        // 4️⃣ 合并其他数据
        parseCache.cachedFootnotes = newFootnotes
        parseCache.cachedAttachments.append(contentsOf: newAttachments)

        if !newTOCItems.isEmpty {
            parseCache.cachedTOCItems.append(contentsOf: newTOCItems)
        }
        parseCache.tocSectionId = newTocId ?? parseCache.tocSectionId
        parseCache.lastParsedLength = newLength

        // 5️⃣ 更新全局状态
        self.imageAttachments = parseCache.cachedAttachments
        self.tableOfContents = parseCache.cachedTOCItems
        self.tocSectionId = parseCache.tocSectionId

        // 6️⃣ 更新 oldElements 用于下次Diff（如果需要全量渲染）
        self.oldElements = parseCache.cachedElements

        // 7️⃣ 通知高度变化
        notifyHeightChange()
    }

    private func performRender() {
        let markdownText = markdown
        let config = configuration
        let containerWidth = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width - 32

        // 🔍 性能监控：performRender 开始
        if renderStartTime > 0 {
            let elapsed = (CFAbsoluteTimeGetCurrent() - renderStartTime) * 1000
            print("🔍 [Perf] performRender start: +\(String(format: "%.1f", elapsed))ms")
        }

        let perfStartTime = renderStartTime // 捕获性能监控起始时间

        // ⚡️ 增量解析优化：判断是否可以使用增量解析
        // 节流已在 scheduleRerender 层面完成（150ms），这里只关心是否需要缓存失效
        if shouldInvalidateCache(newMarkdown: markdownText, containerWidth: containerWidth) {
            // 🔄 全量解析模式（首次渲染、删除内容、宽度变化）
            print("🔄 [Full Parse] Cache invalidated, performing full parse")

            // 清空缓存
            parseCache = ParseCache()
            cachedContainerWidth = containerWidth

            // 执行全量解析
            performFullParse(
                markdownText: markdownText,
                config: config,
                containerWidth: containerWidth,
                perfStartTime: perfStartTime
            )
        } else {
            // ⚡️ 增量解析模式（流式追加 + 非流式但有缓存）
            let mode = isStreaming ? "Streaming incremental" : "Incremental"
            print("⚡️ [\(mode) Parse] Parsing delta only (throttled by scheduleRerender)")

            performIncrementalParse(
                fullText: markdownText,
                config: config,
                containerWidth: containerWidth,
                perfStartTime: perfStartTime
            )
        }
    }

    /// 执行全量解析（原有逻辑保持不变）
    private func performFullParse(
        markdownText: String,
        config: MarkdownConfiguration,
        containerWidth: CGFloat,
        perfStartTime: CFAbsoluteTime
    ) {
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
            let parseDuration = endTime - startTime

            // 🔍 性能监控：解析完成
            if !self.isStreaming && perfStartTime > 0 {
                let elapsed = (CFAbsoluteTimeGetCurrent() - perfStartTime) * 1000
                print("🔍 [Perf] Parsing complete: +\(String(format: "%.1f", elapsed))ms (parse took \(String(format: "%.1f", parseDuration * 1000))ms)")
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

                // ⚡️ 更新缓存（为下次增量解析做准备）
                self.parseCache.lastParsedLength = (markdownText as NSString).length
                self.parseCache.cachedElements = newElements
                self.parseCache.cachedFootnotes = footnotes
                self.parseCache.cachedAttachments = attachments
                self.parseCache.cachedTOCItems = tocItems
                self.parseCache.tocSectionId = tocSectionId

                // 🔍 性能监控：开始UI渲染
                if !self.isStreaming && perfStartTime > 0 {
                    let elapsed = (CFAbsoluteTimeGetCurrent() - perfStartTime) * 1000
                    print("🔍 [Perf] updateViews start: +\(String(format: "%.1f", elapsed))ms")
                }

                self.updateViews(newElements: newElements, footnotes: footnotes, containerWidth: containerWidth, parseDuration: parseDuration, perfStartTime: perfStartTime)
            }
        }
    }
    
    private func updateViews(newElements: [MarkdownRenderElement], footnotes: [MarkdownFootnote], containerWidth: CGFloat, parseDuration: Double = 0, perfStartTime: CFAbsoluteTime = 0) {
        let startTime = CFAbsoluteTimeGetCurrent()
        renderCosts = [:] // Reset performance counters

        // Record Parsing Time
        recordCost(for: "1. Parsing", duration: parseDuration)

        // ⚡️ 首屏优化：判断是否启用分批渲染
        // 条件：非流式模式 + 元素数量 > 5（避免过少内容也分批）
        let shouldUseBatchRendering = !isStreaming && newElements.count > 5

        // 🔍 诊断日志
        if perfStartTime > 0 {
            print("🔍 [Perf] updateViews: isStreaming=\(isStreaming), elementCount=\(newElements.count), shouldBatch=\(shouldUseBatchRendering)")
        }

        if shouldUseBatchRendering {
            // 🎯 阶段1: 逐个渲染直到达到目标高度（2屏）
            let targetHeight = UIScreen.main.bounds.height * firstScreenHeightMultiplier
            let firstScreenCutoff = calculateFirstScreenCutoff(
                elements: newElements,
                targetHeight: targetHeight,
                containerWidth: containerWidth
            )

            guard firstScreenCutoff < newElements.count else {
                // 所有元素都在首屏范围内，直接全部渲染
                updateViewsInternal(
                    newElements: newElements,
                    footnotes: footnotes,
                    containerWidth: containerWidth,
                    parseDuration: parseDuration,
                    startTime: startTime,
                    isBatchFirstScreen: false,
                    perfStartTime: perfStartTime
                )
                return
            }

            print("⚡️ [FirstScreen] Rendering \(firstScreenCutoff)/\(newElements.count) elements (~\(Int(targetHeight))pt)")

            // 渲染首屏元素
            let firstScreenElements = Array(newElements.prefix(firstScreenCutoff))
            let offscreenElements = Array(newElements.dropFirst(firstScreenCutoff))

            updateViewsInternal(
                newElements: firstScreenElements,
                footnotes: [], // 首屏暂不渲染脚注
                containerWidth: containerWidth,
                parseDuration: parseDuration,
                startTime: startTime,
                isBatchFirstScreen: true,
                perfStartTime: perfStartTime
            )

            // ⚡️ 添加占位视图，预留离屏内容空间，避免布局跳动
            let baseEstimatedHeight = offscreenElements.reduce(CGFloat(0)) { total, element in
                total + estimateElementHeight(element, containerWidth: containerWidth)
            }

            // ⚡️ 增加 10% 缓冲，确保预留空间足够（高度估算可能偏低）
            let estimatedOffscreenHeight = baseEstimatedHeight * 1.1

            print("📦 [Placeholder] Creating placeholder: base=\(String(format: "%.1f", baseEstimatedHeight))pt, buffered=\(String(format: "%.1f", estimatedOffscreenHeight))pt (+10%)")

            // 创建占位视图
            placeholderView?.removeFromSuperview()
            let placeholder = UIView()
            placeholder.backgroundColor = .clear
            placeholder.translatesAutoresizingMaskIntoConstraints = false
            contentStackView.addArrangedSubview(placeholder)

            NSLayoutConstraint.activate([
                placeholder.heightAnchor.constraint(equalToConstant: estimatedOffscreenHeight)
            ])

            placeholderView = placeholder

            // 强制立即布局，确保占位视图生效
            contentStackView.layoutIfNeeded()

            // ⚡️ 现在通知父视图完整高度（首屏内容 + 占位视图）
            print("🎬 [FirstScreen] Calling notifyHeightChange() after adding placeholder")
            notifyHeightChange()

            // 🎯 阶段2: 延迟渲染离屏元素
            offscreenRenderWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }

                let offscreenStartTime = CFAbsoluteTimeGetCurrent()
                print("⚡️ [Offscreen] Rendering remaining \(newElements.count - firstScreenCutoff) elements")
                print("🎬 [Offscreen] Calling updateViewsInternal() with total \(newElements.count) elements")

                // ⚡️ 移除占位视图
                if let placeholder = self.placeholderView {
                    print("📦 [Placeholder] Removing placeholder before offscreen rendering")
                    placeholder.removeFromSuperview()
                    self.placeholderView = nil
                }

                // 渲染完整元素列表（Diff会复用首屏已创建的视图）
                self.updateViewsInternal(
                    newElements: newElements,
                    footnotes: footnotes,
                    containerWidth: containerWidth,
                    parseDuration: parseDuration,
                    startTime: offscreenStartTime,
                    isBatchFirstScreen: false,
                    perfStartTime: 0 // 离屏渲染不需要性能监控
                )

                print("⚡️ [Offscreen] Completed in \((CFAbsoluteTimeGetCurrent() - offscreenStartTime) * 1000)ms")
            }
            offscreenRenderWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + offscreenRenderDelay, execute: workItem)

            return
        }

        // 常规渲染（流式模式或元素数量较少）
        if perfStartTime > 0 {
            print("🔍 [Perf] Using regular rendering (no batch)")
        }
        updateViewsInternal(
            newElements: newElements,
            footnotes: footnotes,
            containerWidth: containerWidth,
            parseDuration: parseDuration,
            startTime: startTime,
            isBatchFirstScreen: false,
            perfStartTime: perfStartTime
        )
    }

    /// 计算首屏应该渲染到第几个元素（基于高度）
    private func calculateFirstScreenCutoff(
        elements: [MarkdownRenderElement],
        targetHeight: CGFloat,
        containerWidth: CGFloat
    ) -> Int {
        var accumulatedHeight: CGFloat = 0
        var cutoffIndex = elements.count

        for (index, element) in elements.enumerated() {
            // 估算元素高度（快速估算，不创建实际视图）
            let estimatedHeight = estimateElementHeight(element, containerWidth: containerWidth)
            accumulatedHeight += estimatedHeight

            if accumulatedHeight >= targetHeight {
                cutoffIndex = max(3, index + 1) // 至少渲染3个元素
                break
            }
        }

        return cutoffIndex
    }

    /// 快速估算元素高度（不创建视图）
    private func estimateElementHeight(_ element: MarkdownRenderElement, containerWidth: CGFloat) -> CGFloat {
        switch element {
        case .attributedText(let text):
            // 文本：使用boundingRect估算
            let size = text.boundingRect(
                with: CGSize(width: containerWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).size
            return ceil(size.height) + configuration.paragraphSpacing

        case .heading:
            return 40 + configuration.headingSpacing

        case .quote(let children, _):
            // 引用：递归估算子元素 + padding
            let childrenHeight = children.reduce(0) { $0 + estimateElementHeight($1, containerWidth: containerWidth - 40) }
            return childrenHeight + 20

        case .codeBlock(let text):
            let lines = text.string.components(separatedBy: .newlines).count
            return CGFloat(lines) * 18 + 32

        case .table(let data):
            // 表格：行数 * 估算行高
            let rowCount = data.rows.count + 1 // +1 for header
            return CGFloat(rowCount) * 44 + 20

        case .list(let items, _):
            // 列表：子项数量 * 估算高度
            return CGFloat(items.count) * 30

        case .thematicBreak:
            return 24

        case .image:
            return configuration.imagePlaceholderHeight

        case .latex:
            return 60

        case .details(let _, let children):
            // 折叠块：只算summary高度（内容默认折叠）
            return 44

        case .rawHTML:
            return 100
        }
    }

    /// 实际的视图更新逻辑（支持分批渲染）
    private func updateViewsInternal(
        newElements: [MarkdownRenderElement],
        footnotes: [MarkdownFootnote],
        containerWidth: CGFloat,
        parseDuration: Double,
        startTime: Double,
        isBatchFirstScreen: Bool,
        perfStartTime: CFAbsoluteTime
    ) {
        var newSubviews: [UIView] = []
        var consumedOldIndices = Set<Int>()
        var searchStart = 0
        
        // --- 1. 智能 Diff & Patch ---
        for (newIndex, newElement) in newElements.enumerated() {
            var foundIndex = -1

            // 🔍 追踪嵌套元素
            let isNested = { () -> Bool in
                switch newElement {
                case .quote, .list, .details: return true
                default: return false
                }
            }()

            // 设置搜索窗口（例如向后看5个元素），处理插入/删除造成的索引偏移
            let searchEnd = min(searchStart + 5, oldElements.count)

            if isNested {
               // print("🔍 [Diff] Searching for nested element at newIndex=\(newIndex), searchStart=\(searchStart), searchEnd=\(searchEnd)")
            }

            for i in searchStart..<searchEnd {
                if consumedOldIndices.contains(i) { continue }

                let oldElement = oldElements[i]

                // 1. 检查类型是否兼容
                if canReuseElement(old: oldElement, new: newElement) {
                    if isNested {
                       // print("  → Found reusable element at oldIndex=\(i), attempting updateViewInPlace...")
                    }

                    // 2. 尝试执行更新 (如果 LaTeX 模式改变，这里会返回 false)
                    // ⏱ Measure Update Time
                    let updateStart = CFAbsoluteTimeGetCurrent()
                    if let candidateView = contentStackView.arrangedSubviews[safe: i],
                       updateViewInPlace(candidateView, old: oldElement, new: newElement, containerWidth: containerWidth) {
                        
                        recordCost(for: "Update \(elementTypeString(newElement))", duration: CFAbsoluteTimeGetCurrent() - updateStart)
                        
                        foundIndex = i
                        if isNested {
                           // print("  ✅ updateViewInPlace succeeded, reusing view at index \(i)")
                        }
                        break
                    } else {
                        // Update failed, count cost anyway
                         recordCost(for: "UpdateFail \(elementTypeString(newElement))", duration: CFAbsoluteTimeGetCurrent() - updateStart)
                        if isNested {
                           // print("  ❌ updateViewInPlace failed or view not found")
                        }
                    }
                } else if isNested {
                   // print("  → oldElement at \(i) cannot be reused (type mismatch)")
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
                if isNested {
                   // print("  ⚠️ No reusable view found, creating NEW nested view")
                }
                
                // ⏱ Measure Creation Time
                let createStart = CFAbsoluteTimeGetCurrent()
                let newView = createView(for: newElement, containerWidth: containerWidth)
                recordCost(for: "Create \(elementTypeString(newElement))", duration: CFAbsoluteTimeGetCurrent() - createStart)
                
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
        
        let reconcileStart = CFAbsoluteTimeGetCurrent()
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
        recordCost(for: "StackReconcile", duration: CFAbsoluteTimeGetCurrent() - reconcileStart)
        
        // --- 4. 脚注处理 ---
        // ⚡️ 流式渲染时跳过脚注，等流式完成后再渲染
        if !isStreaming {
            let footnoteStart = CFAbsoluteTimeGetCurrent()
            updateFootnotes(footnotes, width: containerWidth, newElementCount: newElements.count)
            recordCost(for: "UpdateFootnotes", duration: CFAbsoluteTimeGetCurrent() - footnoteStart)
        }

        finishUpdate(newElements: newElements, startTime: startTime, isBatchFirstScreen: isBatchFirstScreen, perfStartTime: perfStartTime)
    }

    // Helper to get element type name
    private func elementTypeString(_ element: MarkdownRenderElement) -> String {
        switch element {
        case .attributedText: return "Text"
        case .heading: return "Heading"
        case .quote: return "Quote"
        case .codeBlock: return "CodeBlock"
        case .table: return "Table"
        case .thematicBreak: return "Rule"
        case .image: return "Image"
        case .latex: return "LaTeX"
        case .details: return "Details"
        case .list: return "List"
        case .rawHTML: return "HTML"
        }
    }

    private func updateFootnotes(_ footnotes: [MarkdownFootnote], width: CGFloat, newElementCount: Int) {
        // ⚡️ 使用无动画更新，避免闪烁
        UIView.performWithoutAnimation {
            // 此时 contentStackView 的 subviews 数量应该是 newElementCount (如果不含脚注)
            // 先移除旧的脚注视图（如果存在）
            if contentStackView.arrangedSubviews.count > newElementCount {
                contentStackView.arrangedSubviews.last?.removeFromSuperview()
            }

            // 立即添加新的脚注视图（在同一个动画块中，避免中间状态显示）
            if !footnotes.isEmpty {
                let footnoteView = createFootnoteView(footnotes: footnotes, width: width)
                contentStackView.addArrangedSubview(footnoteView)

                // 强制立即布局，避免延迟
                footnoteView.layoutIfNeeded()
            }
        }
    }

    private func finishUpdate(newElements: [MarkdownRenderElement], startTime: Double, isBatchFirstScreen: Bool, perfStartTime: CFAbsoluteTime) {
        oldElements = newElements

        // ⚡️ 首屏优化：首屏阶段跳过耗时操作，等离屏渲染完成后再执行
        if !isBatchFirstScreen {
            loadImages()
            invalidateIntrinsicContentSize()
            print("🎬 [Regular/Offscreen] Calling notifyHeightChange() after rendering \(newElements.count) elements")
            notifyHeightChange()

            // 🔍 性能监控：打印首帧时间（常规渲染模式）
            if perfStartTime > 0 {
                let firstFrameTime = (CFAbsoluteTimeGetCurrent() - perfStartTime) * 1000
                let renderTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                print("🎯 [FIRST FRAME] Total: \(String(format: "%.1f", firstFrameTime))ms | Render: \(String(format: "%.1f", renderTime))ms (regular)")
                print("🔍 [Perf] ========================================")
            }
        } else {
            // 首屏阶段：只更新布局，但不通知高度（等添加占位视图后再通知）
            invalidateIntrinsicContentSize()

            // 🔍 性能监控：打印首帧时间（分批渲染首屏）
            if perfStartTime > 0 {
                let firstFrameTime = (CFAbsoluteTimeGetCurrent() - perfStartTime) * 1000
                let renderTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                print("🎯 [FIRST FRAME] Total: \(String(format: "%.1f", firstFrameTime))ms | Render: \(String(format: "%.1f", renderTime))ms (batched)")
                print("🔍 [Perf] ========================================")
            }

            // ⚠️ 注意：首屏不调用 notifyHeightChange()，等占位视图添加后再通知
        }

//        let endTime = CFAbsoluteTimeGetCurrent()
//        let totalDuration = endTime - startTime
//
//        // Only print if it took noticeable time (e.g. > 10ms)
//        if totalDuration > 0.01 && !isBatchFirstScreen {
//             printRenderCosts(totalDuration: totalDuration)
//        }
    }

    // MARK: - ⚠️ 视图复用优化（已禁用）

    /// 生成元素的唯一ID用于缓存（已禁用，保留代码供参考）
    @available(*, deprecated, message: "缓存策略会导致内容错位，已禁用")
    private func generateElementID(_ element: MarkdownRenderElement, width: CGFloat) -> String {
        let widthKey = Int(width) // 宽度作为key的一部分

        switch element {
        case .attributedText(let text):
            // 使用文本内容的hash + 长度
            let textHash = text.string.prefix(100).hashValue  // 只取前100字符的hash
            return "text_\(textHash)_\(text.length)_\(widthKey)"

        case .heading(let id, let text):
            return "heading_\(id)_\(text.length)_\(widthKey)"

        case .quote(let children, let level):
            // ⚡️ 修复：quote 是递归的，使用 children 数量作为 key
            return "quote_\(level)_\(children.count)_\(widthKey)"

        case .codeBlock(let text):
            let codeHash = text.string.prefix(100).hashValue
            return "code_\(codeHash)_\(text.length)_\(widthKey)"

        case .table(let data):
            return "table_\(data.headers.count)_\(data.rows.count)_\(widthKey)"

        case .thematicBreak:
            return "hr_\(widthKey)"

        case .image(let source, _):
            return "img_\(source.hashValue)_\(widthKey)"

        case .latex(let formula):
            let formulaHash = formula.prefix(50).hashValue
            return "latex_\(formulaHash)_\(widthKey)"

        case .details(let summary, let children):
            return "details_\(summary.hashValue)_\(children.count)_\(widthKey)"

        case .list(let items, let level):
            // ⚡️ 新增：list case
            return "list_\(items.count)_\(level)_\(widthKey)"

        case .rawHTML:
            return "html_\(widthKey)"
        }
    }

    /// 清理视图缓存（已禁用）
    private func clearViewCache() {
        // ⚠️ 缓存已禁用，无需清理
        // viewCache.removeAll()

        // ⚡️ 清理预渲染的脚注缓存
        cachedFootnoteView = nil
    }

    private func createView(for element: MarkdownRenderElement, containerWidth: CGFloat, suppressTopSpacing: Bool = false, suppressBottomSpacing: Bool = false, precalculatedHeight: CGFloat? = nil) -> UIView {
        // ⚠️ 缓存已禁用，直接创建视图
        // 原因：缓存策略会导致内容错位问题
        return createViewInternal(for: element, containerWidth: containerWidth, suppressTopSpacing: suppressTopSpacing, suppressBottomSpacing: suppressBottomSpacing, precalculatedHeight: precalculatedHeight)
    }

    /// 实际创建视图的内部方法（原createView逻辑）
    private func createViewInternal(for element: MarkdownRenderElement, containerWidth: CGFloat, suppressTopSpacing: Bool = false, suppressBottomSpacing: Bool = false, precalculatedHeight: CGFloat? = nil) -> UIView {
        switch element {
        case .heading(_, let attributedString):
            let topSpacing = suppressTopSpacing ? 0 : configuration.headingTopSpacing
            let bottomSpacing = suppressBottomSpacing ? 0 : configuration.headingBottomSpacing
            return createTextView(
                with: attributedString,
                width: containerWidth,
                insets: UIEdgeInsets(top: topSpacing, left: 0, bottom: bottomSpacing, right: 0),
                fixedHeight: precalculatedHeight
            )

        case .attributedText(let attributedString):
            if attributedString.length > 0 {
                let topSpacing = suppressTopSpacing ? 0 : configuration.paragraphTopSpacing
                let bottomSpacing = suppressBottomSpacing ? 0 : configuration.paragraphBottomSpacing
                return createTextView(
                    with: attributedString,
                    width: containerWidth,
                    insets: UIEdgeInsets(top: topSpacing, left: 0, bottom: bottomSpacing, right: 0),
                    fixedHeight: precalculatedHeight
                )
            } else {
                return UIView()
            }

        case .table(let tableData):
            // 使用 NSTextAttachment + UICollectionView 优化表格性能
            let attachment = MarkdownTableAttachment(
                data: tableData,
                config: configuration,
                containerWidth: containerWidth
            )
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .left
            
            let attrString = NSMutableAttributedString(attachment: attachment)
            attrString.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: attrString.length))
            
            return createTextView(with: attrString, width: containerWidth)

        case .thematicBreak:
            return createThematicBreakView(width: containerWidth)
        case .codeBlock(let attributedString):
            return createCodeBlockView(with: attributedString, width: containerWidth, fixedHeight: precalculatedHeight)
        case .quote(let children, let level):
            return createQuoteView(children: children, width: containerWidth, level: level)

        case .details(let summary, let children):
            return createDetailsView(summary: summary, children: children, width: containerWidth)
        case .image(let source, let altText):
            let topSpacing = suppressTopSpacing ? 0 : 8.0
            let bottomSpacing = suppressBottomSpacing ? 0 : 8.0
            return createImageView(source: source, altText: altText, width: containerWidth, topSpacing: topSpacing, bottomSpacing: bottomSpacing)
        case .latex(let latex):
            let topSpacing = suppressTopSpacing ? 0 : 8.0
            let bottomSpacing = suppressBottomSpacing ? 0 : 8.0
            return createLatexView(latex: latex, width: containerWidth, topSpacing: topSpacing, bottomSpacing: bottomSpacing)
        case .rawHTML:
            return UIView()
        case .list(items: let list, level: let level):
            return createListView(items: list, width: containerWidth, level: level)
        }
    }
    
    // 2. 实现 createListView
    // MARK: - List View Creation

    private func createListView(items: [ListNodeItem], width: CGFloat, level: Int) -> UIView {
        // 1. 创建主容器（垂直堆叠每个列表项）
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 4 // 列表项之间的间距 (Reduced from 8)
        container.alignment = .fill
        container.translatesAutoresizingMaskIntoConstraints = false

        // 2. 计算缩进和内容宽度
        // 使用配置项，默认为 20pt
        let indent: CGFloat = configuration.listIndent
        // ⭐️ 核心修复：嵌套列表的缩进应该是相对的，而不是基于层级的绝对累加
        // 因为视图本身已经是嵌套的，每层只需要缩进一个单位即可
        let currentIndent = (level > 1) ? indent : 0
        
        // 子元素可用的最大宽度 = 总宽度 - 当前缩进 - 标记宽度(估算20) - 间距
        let contentMaxWidth = max(0, width - currentIndent)

        // ⭐️ 预先计算所有标记的最大宽度，确保对齐
        let maxMarkerWidth: CGFloat = {
            var maxWidth: CGFloat = 20  // 最小宽度
            for item in items {
                let markerText = item.marker as NSString
                let size = markerText.size(withAttributes: [.font: configuration.bodyFont])
                maxWidth = max(maxWidth, ceil(size.width) + 4)  // 额外加4pt作为padding
            }
            return maxWidth
        }()

        // 3. 遍历生成每个列表项
        for item in items {
            // 每个列表项是一个水平 Stack：[标记] [内容垂直Stack]
            let itemStack = UIStackView()
            itemStack.axis = .horizontal
            itemStack.alignment = .top // 顶部对齐，防止标记跑到中间
            itemStack.spacing = 4 // (Reduced from 6)
            itemStack.translatesAutoresizingMaskIntoConstraints = false
            
            // A. 标记 (Bullet point or Number)
            let markerLabel = UILabel()
            markerLabel.text = item.marker
            markerLabel.font = configuration.bodyFont // 使用正文字体
            markerLabel.textColor = configuration.textColor
            markerLabel.setContentHuggingPriority(.required, for: .horizontal)
            markerLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

            // 使用预计算的最大宽度，确保所有列表项对齐
            markerLabel.widthAnchor.constraint(equalToConstant: maxMarkerWidth).isActive = true
            markerLabel.textAlignment = .right // 数字右对齐更好看
            
            itemStack.addArrangedSubview(markerLabel)
            
            // B. 内容容器 (垂直堆叠：第一行文本 + 后续的代码块/嵌套列表等)
            let contentStack = UIStackView()
            contentStack.axis = .vertical
            contentStack.spacing = 4 // (Reduced from 6)
            contentStack.alignment = .fill
            contentStack.translatesAutoresizingMaskIntoConstraints = false
            
            // ⭐️ 递归核心：遍历 ListItem 的 children 并创建视图
            // 实际内容宽度 = 总宽度 - 标记宽度 - 间距
            let itemContentWidth = contentMaxWidth - maxMarkerWidth - 4
            
            for (index, childElement) in item.children.enumerated() {
                // 递归调用 createView
                // 如果是列表项的第一个元素，去除顶部间距，以便跟 Marker 对齐
                let isFirst = (index == 0)
                // ⭐️ 列表内的元素，默认去除底部间距，完全由 contentStack.spacing 控制
                let childView = createView(for: childElement, containerWidth: itemContentWidth, suppressTopSpacing: isFirst, suppressBottomSpacing: true)
                contentStack.addArrangedSubview(childView)
            }
            
            itemStack.addArrangedSubview(contentStack)
            container.addArrangedSubview(itemStack)
        }
        
        // 4. 外层包装 (处理缩进)
        let indentWrapper = UIView()
        indentWrapper.translatesAutoresizingMaskIntoConstraints = false
        indentWrapper.addSubview(container)
        
        // 使用标准约束替代 pinToEdges
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: indentWrapper.topAnchor),
            container.bottomAnchor.constraint(equalTo: indentWrapper.bottomAnchor),
            container.trailingAnchor.constraint(equalTo: indentWrapper.trailingAnchor),
            // ⭐️ 关键：左边设置缩进
            container.leadingAnchor.constraint(equalTo: indentWrapper.leadingAnchor, constant: currentIndent),
            
            // 宽度约束，确保 wrap content
            indentWrapper.widthAnchor.constraint(equalToConstant: width)
        ])
        
        return indentWrapper
    }
    /// 创建 LaTeX 公式视图（使用 LaTeXAttachment + ViewProvider 优化）
    private func createLatexView(latex: String, width: CGFloat, topSpacing: CGFloat, bottomSpacing: CGFloat) -> UIView {

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // ⚡️ 使用 LaTeXAttachment
        let attachment = LaTeXAttachment(
            latex: latex,
            fontSize: 22,
            maxWidth: width - 40,  // 留出容器padding
            padding: 20,
            backgroundColor: UIColor.systemGray6.withAlphaComponent(0.5)
        )

        // 创建专用的 TextKit2 TextView 来渲染附件
        let textLayoutManager = NSTextLayoutManager()
        let textContentStorage = NSTextContentStorage()
        let textContainer = NSTextContainer(size: CGSize(width: width, height: 0))

        textContentStorage.addTextLayoutManager(textLayoutManager)
        textLayoutManager.textContainer = textContainer
        textContainer.lineFragmentPadding = 0
        textContainer.widthTracksTextView = false

        // 创建包含附件的富文本
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attachmentString = NSMutableAttributedString(attachment: attachment)
        attachmentString.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: attachmentString.length))

        textContentStorage.attributedString = attachmentString

        // 创建渲染视图
        let textView = UIView()
        textView.translatesAutoresizingMaskIntoConstraints = false

        // 让 TextKit2 在这个视图中渲染
        textLayoutManager.textViewportLayoutController.layoutViewport()

        // 从 textLayoutManager 获取已渲染的附件视图
        var attachmentView: UIView?
        textLayoutManager.enumerateTextLayoutFragments(from: textLayoutManager.documentRange.location, options: [.ensuresLayout]) { layoutFragment in
            // 遍历 layoutFragment 中的 textAttachment
            layoutFragment.textLineFragments.forEach { lineFragment in
                lineFragment.attributedString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: lineFragment.attributedString.length)) { value, range, stop in
                    if let attachment = value as? NSTextAttachment {
                        // 尝试获取附件的 ViewProvider
                        if let viewProvider = attachment.viewProvider(for: textView, location: layoutFragment.rangeInElement.location, textContainer: textContainer) {
                            viewProvider.loadView()
                            if let view = viewProvider.view {
                                attachmentView = view
                                stop.pointee = true
                            }
                        }
                    }
                }
            }
            return !((attachmentView != nil))
        }

        // 如果通过 ViewProvider 获取到了视图，使用它；否则回退到直接创建
        let formulaView: UIView
        if let view = attachmentView {
            formulaView = view
        } else {
            // 回退方案：直接创建
            formulaView = LatexMathView.createScrollableView(
                latex: latex,
                fontSize: 22,
                maxWidth: width - 40,
                padding: 20,
                backgroundColor: UIColor.systemGray6.withAlphaComponent(0.5)
            )
        }

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
            formulaView.topAnchor.constraint(equalTo: container.topAnchor, constant: topSpacing),
            formulaView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            formulaView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -bottomSpacing),
            formulaView.widthAnchor.constraint(equalToConstant: min(formulaSize.width, width)),
            formulaView.heightAnchor.constraint(equalToConstant: formulaSize.height)
        ])

        return container
    }

    private func createImageView(source: String, altText: String, width: CGFloat, topSpacing: CGFloat, bottomSpacing: CGFloat) -> UIView {
        print("🖼️ [Image] Creating image view for: \(source) (alt: \(altText))")

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
        
        // 高度约束 - 提高优先级到 required
        let heightConstraint = imageView.heightAnchor.constraint(equalToConstant: configuration.imagePlaceholderHeight)
        heightConstraint.priority = .required  // 🔧 修复：从 .defaultHigh 改为 .required

        // 宽度约束（用于图片加载后更新）
        let widthConstraint = imageView.widthAnchor.constraint(lessThanOrEqualToConstant: width)
        widthConstraint.priority = .required

        // 🔧 图片居左对齐
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: topSpacing),
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            // ❌ 移除 trailingAnchor，让图片自然宽度，居左显示
            widthConstraint,
            heightConstraint,
        ])

        // 容器尺寸约束
        let containerHeightConstraint = container.heightAnchor.constraint(
            equalTo: imageView.heightAnchor,
            constant: topSpacing + bottomSpacing
        )
        containerHeightConstraint.priority = .required

        let containerWidthConstraint = container.widthAnchor.constraint(equalTo: imageView.widthAnchor)
        containerWidthConstraint.priority = .required

        NSLayoutConstraint.activate([
            containerHeightConstraint,
            containerWidthConstraint,
        ])

        print("🖼️ [Image] Constraints set - width: ≤\(width), height: \(configuration.imagePlaceholderHeight)")
        
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

            // 更新约束（lessThanOrEqualToConstant 只需要更新 constant）
            widthConstraint?.constant = targetWidth
            heightConstraint?.constant = targetHeight

            print("🖼️ [Image] Loaded - actual size: \(targetWidth) × \(targetHeight)")
        }

        // 设置容器的内容优先级，防止被压缩
        container.setContentHuggingPriority(.required, for: .vertical)
        container.setContentCompressionResistancePriority(.required, for: .vertical)
        container.setContentHuggingPriority(.required, for: .horizontal)
        container.setContentCompressionResistancePriority(.required, for: .horizontal)

        // 调试：延迟打印容器大小
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("🖼️ [Image Debug] Container frame: \(container.frame), imageView frame: \(imageView.frame)")
            print("🖼️ [Image Debug] Container bounds: \(container.bounds), imageView bounds: \(imageView.bounds)")
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
    
    private func createCodeBlockView(with attributedString: NSAttributedString, width: CGFloat, fixedHeight: CGFloat? = nil) -> UIView {
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
        
        if let fixedHeight = fixedHeight {
            // ⚡️ 使用预计算高度 (减去上下 padding 24)
            textView.textContainer.size = CGSize(width: codeBlockWidth, height: .greatestFiniteMagnitude)
            textView.setFixedHeight(max(0, fixedHeight - 24))
        } else {
            textView.applyLayout(width: codeBlockWidth, force: true)
        }

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
            insets: UIEdgeInsets = .zero,
            fixedHeight: CGFloat? = nil
        ) -> UIView {
            // ✂️ Trim trailing newlines to prevent extra vertical space
            let mutableAttrString = NSMutableAttributedString(attributedString: attributedString)
            while mutableAttrString.string.hasSuffix("\n") {
                mutableAttrString.deleteCharacters(in: NSRange(location: mutableAttrString.length - 1, length: 1))
            }

            let container = UIView()
            container.translatesAutoresizingMaskIntoConstraints = false
            
            let textView = MarkdownTextViewTK2()
            textView.attributedText = mutableAttrString
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
                if let fixedHeight = fixedHeight {
                    // ⚡️ 使用预计算高度，跳过主线程布局计算
                    textView.textContainer.size = CGSize(width: contentWidth, height: .greatestFiniteMagnitude)
                    textView.setFixedHeight(fixedHeight)
                } else {
                    textView.applyLayout(width: contentWidth, force: true)
                }
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
    
    /// 创建引用块视图 - 支持嵌套块级元素（表格、代码块、子列表等）
    private func createQuoteView(children: [MarkdownRenderElement], width: CGFloat, level: Int = 1) -> UIView {
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

        // 创建内容 StackView - 支持垂直堆叠多个子元素
        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentStack)

        // 每层应用固定的缩进增量，而不是累积值
        // Level 1: 0pt, Level 2+: 20pt (相对于父级)
        let leftIndent: CGFloat = (level > 1) ? 20 : 0

        // 计算子元素可用宽度
        let padding = leftIndent + 4 + 12 + 8  // leftIndent + barWidth + contentLeading + contentTrailing
        let contentWidth = max(0, width - padding)

        // 递归创建子视图
        for child in children {
            let childView = createView(for: child, containerWidth: contentWidth)
            contentStack.addArrangedSubview(childView)
        }

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

            contentStack.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            contentStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            contentStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
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
        // 外层容器，添加上下间距
        let outerContainer = UIView()
        outerContainer.translatesAutoresizingMaskIntoConstraints = false

        // 🔧 设置容器的内容优先级，防止被压缩（类似图片修复）
        outerContainer.setContentHuggingPriority(.required, for: .vertical)
        outerContainer.setContentCompressionResistancePriority(.required, for: .vertical)

        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 8  // 增加间距，避免贴太近
        container.alignment = .fill
        container.distribution = .fill
        container.translatesAutoresizingMaskIntoConstraints = false

        // 🔧 StackView也设置抗压缩优先级
        container.setContentHuggingPriority(.required, for: .vertical)
        container.setContentCompressionResistancePriority(.required, for: .vertical)

        outerContainer.addSubview(container)

        let summaryButton = UIButton(type: .system)

        // 使用 UIButton.Configuration 设置样式
        var buttonConfig = UIButton.Configuration.plain()
        buttonConfig.title = "▶ " + summary
        buttonConfig.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        buttonConfig.background.backgroundColor = configuration.codeBackgroundColor.withAlphaComponent(0.3)
        buttonConfig.background.cornerRadius = 6
        buttonConfig.baseForegroundColor = configuration.linkColor
        buttonConfig.titleAlignment = .leading

        summaryButton.configuration = buttonConfig
        summaryButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        summaryButton.contentHorizontalAlignment = .left
        summaryButton.isUserInteractionEnabled = true  // 确保可点击
        summaryButton.setContentHuggingPriority(.required, for: .vertical)
        summaryButton.setContentCompressionResistancePriority(.required, for: .vertical)

        // 🔧 核心修复：为按钮添加明确的最小高度约束，防止被压缩到0
        summaryButton.translatesAutoresizingMaskIntoConstraints = false
        let buttonHeightConstraint = summaryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 40)
        buttonHeightConstraint.priority = .required
        buttonHeightConstraint.isActive = true

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

                // 更新按钮标题（使用 configuration）
                var config = btn.configuration
                config?.title = (willShow ? "▼ " : "▶ ") + summary
                btn.configuration = config

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

        // 添加外层容器约束，添加上下间距（8pt）
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: outerContainer.topAnchor, constant: 8),
            container.leadingAnchor.constraint(equalTo: outerContainer.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: outerContainer.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: outerContainer.bottomAnchor, constant: -8)
        ])

        // 🔍 调试日志：监控Details视图布局
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("🔍 [Details Debug] outerContainer frame: \(outerContainer.frame)")
            print("🔍 [Details Debug] container frame: \(container.frame)")
            print("🔍 [Details Debug] summaryButton frame: \(summaryButton.frame)")
            print("🔍 [Details Debug] summaryButton isUserInteractionEnabled: \(summaryButton.isUserInteractionEnabled)")
            print("🔍 [Details Debug] container isUserInteractionEnabled: \(container.isUserInteractionEnabled)")
            print("🔍 [Details Debug] outerContainer isUserInteractionEnabled: \(outerContainer.isUserInteractionEnabled)")
        }

        return outerContainer
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
        stackView.spacing = 8
        stackView.alignment = .leading // 使用 .leading 允许分隔线宽度自定义
        stackView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stackView)
        
        // 1. 分隔线
        let separator = UIView()
        separator.backgroundColor = configuration.horizontalRuleColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(separator)
        
        NSLayoutConstraint.activate([
            separator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
            separator.widthAnchor.constraint(equalToConstant: width * 0.3)
        ])
        
        // 2. 合并所有脚注到一个 AttributedString (性能优化：O(N) Views -> O(1) View)
        let allFootnotesText = NSMutableAttributedString()
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = 6 // 脚注之间的间距
        paragraphStyle.lineHeightMultiple = 1.1
        
        for (index, footnote) in footnotes.enumerated() {
            // 添加换行 (除第一个外)
            if index > 0 {
                allFootnotesText.append(NSAttributedString(string: "\n"))
            }
            
            // ID: ⁽1⁾
            let idText = NSAttributedString(
                string: "⁽\(footnote.id)⁾ ",
                attributes: [
                    .font: UIFont.systemFont(ofSize: configuration.bodyFont.pointSize - 2),
                    .foregroundColor: configuration.linkColor,
                    .baselineOffset: 3,
                    .paragraphStyle: paragraphStyle
                ])
            allFootnotesText.append(idText)
            
            // Content
            let contentText = NSAttributedString(
                string: footnote.content,
                attributes: [
                    .font: UIFont.systemFont(ofSize: configuration.bodyFont.pointSize - 2),
                    .foregroundColor: configuration.textColor.withAlphaComponent(0.8),
                    .paragraphStyle: paragraphStyle
                ])
            allFootnotesText.append(contentText)
        }
        
        // 3. 创建唯一的 TextView
        // 注意：我们显式传递 width 确保 createTextView 内部正确计算布局
        let textView = createTextView(
            with: allFootnotesText,
            width: width,
            insets: UIEdgeInsets(top: 8, left: 0, bottom: 16, right: 0)
        )
        
        // 确保 TextView 占满全宽 (因为 StackView 是 .leading 对齐)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.widthAnchor.constraint(equalToConstant: width).isActive = true
        
        stackView.addArrangedSubview(textView)
        
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
        // Optimization: Fast check for footnote syntax markers.
        // If neither definition marker nor reference marker exists, skip regex entirely.
        if !text.contains("[^") {
            return (text, [])
        }
        
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
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            recordCost(for: "Layout Calculation", duration: CFAbsoluteTimeGetCurrent() - start)
        }

        // ⭐️ 强制 StackView 立即更新布局
        if force {
            self.contentStackView.invalidateIntrinsicContentSize()
        }
        self.contentStackView.layoutIfNeeded()

        // Revert optimization: Use systemLayoutSizeFitting to ensure correct height calculation
        // bounds.height can be unreliable during rapid updates or initial layout
        let size = self.contentStackView.systemLayoutSizeFitting(
            CGSize(width: self.bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )

        let newHeight = size.height

        // 🔍 诊断日志：打印高度变化
        let heightDiff = newHeight - lastReportedHeight
        print("🔍 [Height] Current: \(String(format: "%.1f", newHeight))pt | Last: \(String(format: "%.1f", lastReportedHeight))pt | Diff: \(String(format: "%.1f", heightDiff))pt | Force: \(force)")

        // 只有高度变化超过阈值才通知，避免浮点数误差导致的死循环
        // 如果 force 为 true，忽略防抖检查
        if force || abs(newHeight - lastReportedHeight) > 9.0 {
            print("📏 [Height] ✅ Notifying parent: \(String(format: "%.1f", lastReportedHeight)) -> \(String(format: "%.1f", newHeight))")
            lastReportedHeight = newHeight
            self.onHeightChange?(newHeight)
        } else {
            print("📏 [Height] ⚠️ Skipped notification (diff < 9.0pt)")
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

            // ⚡️ 初始化流式显示状态
            streamPreParseCompleted = false
            streamDisplayedCount = 0
            streamParsedElements = []
            streamTotalTextLength = text.count  // 保存总长度

            print("🚀 [Pre-Parse] Starting pre-parse for \(text.count) characters...")

            // 1️⃣ 后台预解析完整文本
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }

                let fullText = text
                let parseStartTime = CFAbsoluteTimeGetCurrent()

                // 预处理脚注
                let (processedMarkdown, footnotes) = self.preprocessFootnotes(fullText)

                // 解析完整文本
                let config = self.configuration
                let containerWidth = UIScreen.main.bounds.width - 32
                let renderer = MarkdownRenderer(configuration: config, containerWidth: containerWidth)
                let (elements, attachments, tocItems, tocId) = renderer.render(processedMarkdown)

                let parseDuration = CFAbsoluteTimeGetCurrent() - parseStartTime
                print("✅ [Pre-Parse] Completed: \(elements.count) elements in \(String(format: "%.1f", parseDuration * 1000))ms")

                // 2️⃣ 回到主线程保存结果
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }

                    self.streamParsedElements = elements
                    self.streamParsedFootnotes = footnotes
                    self.streamParsedAttachments = attachments
                    self.tableOfContents = tocItems
                    self.tocSectionId = tocId
                    self.imageAttachments = attachments
                    self.streamPreParseCompleted = true

                    print("💾 [Pre-Parse] Cached \(elements.count) elements, ready for streaming display")

                    // 3️⃣ 开始流式追加文本（不解析，只更新显示）
                    self.startTokenStreaming(text, unit: unit, unitsPerChunk: unitsPerChunk, interval: interval, onStart: onStart)
                }
            }
        }

        /// 开始流式追加token（预解析后调用）
        private func startTokenStreaming(
            _ text: String,
            unit: StreamingUnit,
            unitsPerChunk: Int,
            interval: TimeInterval,
            onStart: (() -> Void)?
        ) {
            // 分词 + 原子区间计算
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }

                let fullText = text
                let tokens = self.tokenize(fullText, unit: unit)
                
                // 🔥 新增：预计算所有需要整体输出的 Range
                let atomicRanges = self.calculateAtomicRanges(in: fullText)
                
                DispatchQueue.main.async {
                    guard self.isStreaming else { return }

                    // 准备开始
                    self.currentStreamingUnit = unit
                    self.markdown = ""
                    onStart?()

                    self.streamFullText = fullText
                    self.streamTokens = tokens
                    self.streamAtomicRanges = atomicRanges // 保存区间
                    // ⚡️ 构建原子区间起始位置索引（O(1)查找优化）
                    self.atomicRangeStartSet = Set(atomicRanges.map { $0.location })
                    self.streamTokenIndex = 0

                    // ⚡️ 立即在后台预渲染脚注（离屏），避免流式完成时的闪烁
                    self.prerenderFootnotesInBackground(fullText: fullText)

                    // 启动 Timer
                    self.streamTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                         self?.appendNextTokensAtomic(count: unitsPerChunk)
                    }
                }
            }
        }
    
    // MARK: - Dynamic Streaming Updates

    /// Appends new text to the streaming buffer without interrupting current rendering.
    /// - Parameter text: The new text chunk to append (e.g. from network).
    public func appendStreamingContent(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isStreaming else { return }
            self.appendStreamingState(newChunk: text)
        }
    }

    /// Updates the streaming buffer with new full text.
    /// Use this if the stream source provides the full accumulated text.
    /// - Parameter text: The new full text.
    public func updateStreamingContent(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isStreaming else { return }
            self.updateStreamingState(newFullText: text)
        }
    }

    private func appendStreamingState(newChunk: String) {
        let unit = self.currentStreamingUnit
        // Capture current state to avoid threading issues
        let currentFullText = self.streamFullText
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // 1. Tokenize ONLY the new chunk (Optimization)
            let newTokens = self.tokenize(newChunk, unit: unit)
            
            // 2. Update Full Text
            let newFullText = currentFullText + newChunk
            
            // 3. Recalculate Atomic Ranges (Still need full scan for correctness of nested/late-closing tags)
            // Note: This is O(N) but much faster than O(N) tokenization + String allocation
            let newAtomicRanges = self.calculateAtomicRanges(in: newFullText)
            
            DispatchQueue.main.async {
                guard self.isStreaming else { return }

                self.streamFullText = newFullText
                self.streamTokens.append(contentsOf: newTokens)
                self.streamAtomicRanges = newAtomicRanges
                // ⚡️ 同步更新原子区间起始位置索引
                self.atomicRangeStartSet = Set(newAtomicRanges.map { $0.location })

                // No need to adjust streamTokenIndex for append mode
                // as we are just adding to the end.
            }
        }
    }

    private func updateStreamingState(newFullText: String) {
        let unit = self.currentStreamingUnit
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let newTokens = self.tokenize(newFullText, unit: unit)
            let newAtomicRanges = self.calculateAtomicRanges(in: newFullText)
            
            DispatchQueue.main.async {
                guard self.isStreaming else { return }

                // Determine where we are relative to the new tokens
                let currentMarkdownCount = self.markdown.count

                self.streamFullText = newFullText
                self.streamTokens = newTokens
                self.streamAtomicRanges = newAtomicRanges
                // ⚡️ 同步更新原子区间起始位置索引
                self.atomicRangeStartSet = Set(newAtomicRanges.map { $0.location })
                
                var accumulatedLength = 0
                var newIndex = 0
                var partialTokenSuffix: String? = nil
                
                for (i, token) in newTokens.enumerated() {
                    let tokenLen = token.count
                    let tokenEnd = accumulatedLength + tokenLen
                    
                    if tokenEnd > currentMarkdownCount {
                        if accumulatedLength < currentMarkdownCount {
                             // Overlap: token started before cursor but ends after
                             let overlap = currentMarkdownCount - accumulatedLength
                             partialTokenSuffix = String(token.dropFirst(overlap))
                             newIndex = i + 1
                        } else {
                             // Next token starts at or after cursor
                             newIndex = i
                        }
                        break
                    }
                    accumulatedLength += tokenLen
                    
                    // Exact match boundary
                    if tokenEnd == currentMarkdownCount {
                        newIndex = i + 1
                        break
                    }
                }
                
                if let suffix = partialTokenSuffix {
                    self.markdown += suffix
                }
                
                self.streamTokenIndex = newIndex
            }
        }
    }
    
    /// 智能追加 Token，支持原子区间跳跃
        private func appendNextTokensAtomic(count: Int) {
            guard streamTokenIndex < streamTokens.count else {
                // ⚡️ 流式渲染完成
                // 1. 先停止 Timer
                stopStreaming()

                // 2. 立即设置为非流式模式（关键！）
                isStreaming = false

                // 3. 渲染脚注（此时 isStreaming = false，不会被跳过）
                renderFootnotesAfterStreaming()

                // 4. 触发完成回调
                onStreamComplete?()
                onStreamComplete = nil

                return
            }
            
            // 当前 Markdown 的长度（光标位置）
            let currentLength = (markdown as NSString).length

            // 1. 检查当前光标是否位于某个原子区间的"起点"
            // ⚡️ 性能优化：先用 O(1) 的 Set 查找，再用 O(N) 的数组查找具体 range
            if atomicRangeStartSet.contains(currentLength),
               let atomicRange = streamAtomicRanges.first(where: { $0.location == currentLength }) {
                
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
                
                // 🛑 二次检查：在普通追加的过程中，会不会"误入"原子区间的内部？
                // 现在的逻辑是：如果普通追加的 token 开始位置正好是原子区间的起点，我们应该停止普通追加，
                // 留给下一次 Timer tick 去处理上面的 "if let atomicRange" 逻辑。
                let nextCursor = currentLength + (nextChunk as NSString).length
                // ⚡️ 性能优化：用 O(1) 的 Set 查找替代 O(N) 的数组遍历
                if atomicRangeStartSet.contains(nextCursor) {
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
    
    /// 流式渲染完成后渲染脚注
    private func renderFootnotesAfterStreaming() {
        // ⚠️ 必须在主线程调用
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.renderFootnotesAfterStreaming()
            }
            return
        }

        // ⚡️ 优先使用预渲染的缓存视图（避免重新创建导致的闪烁）
        if let cachedView = cachedFootnoteView {
            print("🔖 [Footnotes] Using prerendered cached view (instant add)")

            // ⚡️ 正确计算元素数量
            let elementCount = oldElements.count

            // 使用无动画直接添加预渲染的视图
            UIView.performWithoutAnimation {
                // 移除旧脚注（如果有）
                if contentStackView.arrangedSubviews.count > elementCount {
                    contentStackView.arrangedSubviews.last?.removeFromSuperview()
                }

                // 直接添加缓存的视图
                contentStackView.addArrangedSubview(cachedView)
                cachedView.layoutIfNeeded()
            }

            // 清理缓存
            cachedFootnoteView = nil
            print("✅ [Footnotes] Cached view added, no flicker")
            return
        }

        // ⚠️ 降级方案：如果没有缓存（不应该发生），回退到常规渲染
        print("⚠️ [Footnotes] No cached view, falling back to regular rendering")

        // 重新解析脚注
        let (_, footnotes) = preprocessFootnotes(markdown)
        guard !footnotes.isEmpty else { return }

        // ⚡️ 正确计算元素数量
        let elementCount = oldElements.count
        let containerWidth = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width - 32

        print("🔖 [Footnotes] Rendering \(footnotes.count) footnote(s) after streaming (elementCount=\(elementCount))")
        updateFootnotes(footnotes, width: containerWidth, newElementCount: elementCount)
    }

    /// ⚡️ 在后台预渲染脚注视图（流式开始时调用，避免流式完成时的闪烁）
    private func prerenderFootnotesInBackground(fullText: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // 解析脚注
            let (_, footnotes) = self.preprocessFootnotes(fullText)
            guard !footnotes.isEmpty else {
                print("🔖 [Footnotes] No footnotes to prerender")
                return
            }

            print("🔖 [Footnotes] Prerendering \(footnotes.count) footnote(s) in background")

            // 获取容器宽度
            let containerWidth = DispatchQueue.main.sync {
                self.bounds.width > 0 ? self.bounds.width : UIScreen.main.bounds.width - 32
            }

            // 在后台创建脚注视图（离屏渲染）
            let footnoteView = self.createFootnoteView(footnotes: footnotes, width: containerWidth)

            // 缓存预渲染的视图
            DispatchQueue.main.async {
                self.cachedFootnoteView = footnoteView
                print("✅ [Footnotes] Prerendering completed, cached view ready")
            }
        }
    }

    /// 停止流式渲染
    public func stopStreaming() {
        streamTimer?.invalidate()
        streamTimer = nil
        isPausedForDisplay = false  // 重置暂停状态
        // ⚡️ 流式结束，清理视图缓存
        clearViewCache()
    }

    /// 立即显示全部内容
    public func finishStreaming() {
        stopStreaming()
        markdown = streamFullText
        isStreaming = false
        // ⚡️ 结束流式后渲染脚注
        renderFootnotesAfterStreaming()
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
            // 1. 先设置为非流式模式
            isStreaming = false
            // 2. 渲染脚注（此时 isStreaming = false）
            renderFootnotesAfterStreaming()
            // 3. 触发完成回调
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
