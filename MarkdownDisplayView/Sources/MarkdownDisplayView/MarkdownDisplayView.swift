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

struct StreamingHeightAccumulator {
    private var visibleRoots: Set<ObjectIdentifier> = []
    private(set) var totalHeight: CGFloat = 0

    mutating func reset(verticalMargins: CGFloat) {
        visibleRoots.removeAll(keepingCapacity: true)
        totalHeight = max(0, verticalMargins)
    }

    mutating func rootBecameVisible(
        _ root: UIView,
        measuredHeight: CGFloat,
        spacing: CGFloat
    ) -> CGFloat? {
        guard measuredHeight.isFinite, measuredHeight >= 0 else { return nil }
        guard visibleRoots.insert(ObjectIdentifier(root)).inserted else { return totalHeight }
        if visibleRoots.count > 1 { totalHeight += spacing }
        totalHeight += measuredHeight
        return totalHeight
    }

    mutating func textHeightChanged(delta: CGFloat) -> CGFloat? {
        guard delta.isFinite, abs(delta) > 0.5 else { return nil }
        totalHeight = max(0, totalHeight + delta)
        return totalHeight
    }

    mutating func synchronize(totalHeight: CGFloat) {
        guard totalHeight.isFinite else { return }
        self.totalHeight = max(0, totalHeight)
    }
}
// MARK: - MarkdownViewTextKit

/// TextKit 2 版本的 Markdown 渲染视图
@available(iOS 15.0, *)
public final class MarkdownViewTextKit: UIView {

    
    // MARK: - Properties
    
    lazy var typewriterEngine: TypewriterEngine = {
        let engine = TypewriterEngine()
        engine.onComplete = { [weak self] in
            // 队列播放完毕的回调
            mdLog("✅ [Typewriter] All animations completed")
            self?.tryFinishRealStreamDrain()
        }
        // ⚡️ 核心修复：当打字机揭示了新视图（导致高度变化）时，立即通知父视图更新高度
        engine.onLayoutChange = { [weak self] change in
            self?.handleTypewriterLayoutChange(change)
        }
        engine.onOutstandingTaskCountChange = { [weak self] count in
            guard let self else { return }
            self.streamPerformanceDiagnostics.recordTypewriterOutstanding(count)
            if self.realStreamBackpressureActive, count <= self.realStreamTypewriterLowWatermark {
                self.realStreamBackpressureActive = false
                self.scheduleRealStreamRenderPump()
                self.startNextSmartStreamParseIfPossible()
            }
            self.tryFinishRealStreamDrain()
        }
        // ⭐️ 震动反馈：每次输出内容时触发
        engine.onTypewriterStep = { [weak self] in
            guard let self else { return }
            self.triggerHapticFeedback()
            self.onStreamingStep?()
        }
        return engine
    }()

    // 配置开关
    public var enableTypewriterEffect: Bool = true

    public func updateTypewriterSpeed(charsPerStep: Int? = nil,
                                      baseDuration: TimeInterval? = nil,
                                      elementGapDuration: TimeInterval? = nil) {
        typewriterEngine.updateSpeed(
            charsPerStep: charsPerStep,
            baseDuration: baseDuration,
            elementGapDuration: elementGapDuration
        )
    }
    
    public var configuration: MarkdownConfiguration = .default {
        didSet {
            invalidateIntrinsicHeightCache()
            streamBuffer.updateMinModuleLength(configuration.streamMinModuleLength)
            scheduleRerender()
        }
    }
    
    /// 显示一份完整的 Markdown 文档快照。
    ///
    /// 每个渲染生命周期只应设置一次。复用视图显示另一份文档前，请先调用
    /// `resetForReuse()`。实时网络增量不得通过反复设置本属性实现，应使用
    /// `beginRealStreaming(autoScrollBottom:)`、`appendStreamData(_:)` 和
    /// `endRealStreaming(completion:)`。
    ///
    /// 非预期的重复赋值仍会按完整文档重新解析，以保证内容正确，但不提供增量性能保证。
    public var markdown: String = "" {
        didSet {
            // 相同内容重复赋值（例如 UITableView 复用 Cell 再次 configure）不应触发重渲染，
            // 否则会形成“渲染 → 高度通知 → batchUpdate → cellForRowAt → 再次渲染”的反馈环。
            guard oldValue != markdown else { return }
            isDisplayingPreparedStaticContent = false
            preparedStaticEstimatedHeight = nil
            invalidateIntrinsicHeightCache()
            // 🔍 性能监控：记录渲染开始时间
            if !isStreaming {
                renderStartTime = CFAbsoluteTimeGetCurrent()
                mdLog("🔍 [Perf] ========== Markdown Set ==========")
            }
            scheduleRerender()
        }
    }

    var lastPreparedContentSignature: String?

    /// 直接显示由 `MarkdownRenderer.prepare(_:)` 生成的预渲染内容，跳过 Markdown 字符串解析。
    @MainActor
    public func setPreparedContent(_ preparedContent: MarkdownPreparedContent) {
        let signature = "\(preparedContent.preparedWidth)-\(preparedContent.elements.count)-\(preparedContent.estimatedTotalHeight)"
        if signature == lastPreparedContentSignature {
            print("[MarkdownTable] setPreparedContent SKIP \(signature)")
            return
        }
        print("[MarkdownTable] setPreparedContent RENDER \(signature)")
        resetForReuse()
        // 预渲染内容通常是一次性静态展示，不保留 diff 基线以省内存（不重复持有整份富文本）
        retainsDiffBaseline = false
        lastPreparedContentSignature = signature
        isDisplayingPreparedStaticContent = true
        preparedStaticEstimatedHeight = preparedContent.estimatedTotalHeight

        renderStartTime = CFAbsoluteTimeGetCurrent()
        let containerWidth = preparedContent.preparedWidth

        tableOfContents = preparedContent.tableOfContents
        tocSectionId = preparedContent.tocSectionId
        imageAttachments = preparedContent.imageAttachments

        updateViews(
            newElements: preparedContent.elements,
            footnotes: [],
            containerWidth: containerWidth,
            parseDuration: 0,
            perfStartTime: renderStartTime,
            precalculatedTextHeights: preparedContent.fixedTextHeights
        )
    }
    
    public var onLinkTap: ((URL) -> Void)?
    public var onImageTap: ((String) -> Void)?
    public var onHeightChange: ((CGFloat) -> Void)?
    /// TypewriterEngine 每次实际揭示文字或块级内容时触发。
    /// 可用于让外层滚动容器跟随真实播放进度，而不是跟随网络数据到达。
    public var onStreamingStep: (() -> Void)?
    public var onTOCItemTap: ((MarkdownTOCItem) -> Void)?
    let inlineSegmentAttributeKey = NSAttributedString.Key("MarkdownInlineSegment")
    
    public internal(set) var tableOfContents: [MarkdownTOCItem] = []
    
    let contentStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.alignment = .fill
        sv.spacing = 0
        return sv
    }()
    
    var cancellables = Set<AnyCancellable>()
    var imageAttachments: [(attachment: MarkdownImageAttachment, urlString: String)] = []
    var renderWorkItem: DispatchWorkItem?
    var refreshWorkItem: DispatchWorkItem?

    var headingViews: [String: UIView] = [:]
    var oldElements: [MarkdownRenderElement] = []
    /// 是否保留 oldElements 作为下一次全量渲染的 diff 基线。
    /// 静态一次性渲染可置 false 以省内存，代价是下一次重渲染不再复用旧视图。
    public var retainsDiffBaseline = true

    /// 允许宿主显式将已预渲染完成的静态长文档，在
    /// `UITableViewCell` / `UICollectionViewCell` 内也按外层滚动视口挂载。
    /// 默认关闭，保持既有 Cell 渲染与 self-sizing 行为。
    public var allowsStaticViewportRenderingInReusableCell = false

    /// 当前内容是否已由静态视口窗口承载。宿主可用它避免在流式完成后
    /// 又用相同内容的 prepared snapshot 覆盖已经收敛的视图树。
    public var isUsingStaticViewportRendering: Bool {
        !viewportSlots.isEmpty
    }

    // Cell 内视口窗口只接管 `setPreparedContent` 提交的完成态快照。
    // 普通 markdown 和 streaming 路径不得借用该状态，避免行高在解析期抖动。
    var isDisplayingPreparedStaticContent = false
    var preparedStaticEstimatedHeight: CGFloat?

    // 异步渲染队列（串行，避免并发渲染）
    let renderQueue = DispatchQueue(label: "com.markdown.render", qos: .userInitiated)

    // 渲染版本控制（解决竞态问题）
    var renderVersion: Int = 0
    let renderVersionLock = NSLock()
    
    /// Streaming diagnostics and session state
    var streamingStartTimestamp: CFAbsoluteTime = 0  // ⭐️ 流式开始时间戳
    var isStreaming = false  // ✅ 默认非流式模式

    // ⭐️ 新增：用户交互锁定标记，防止流式更新打断点击事件处理
    var isUserInteractingWithDetails: Bool = false

    // 添加属性
    var tocSectionView: UIView?
    var tocSectionId: String?

    // ⚡️ 首屏优化：分批渲染配置
    /// 首屏渲染目标高度（屏幕高度的倍数，默认3屏）
    let firstScreenHeightMultiplier: CGFloat = 3.0
    /// 离屏渲染延迟时间（秒）
    let offscreenRenderDelay: TimeInterval = 0.05
    /// 离屏渲染工作项（用于取消）
    var offscreenRenderWorkItem: DispatchWorkItem?
    /// 占位视图（用于预留离屏内容空间，避免布局跳动）
    var placeholderView: UIView?

    // 静态长文档只保留轻量槽位；昂贵的正文/标题绘制视图按视口装载。
    var viewportSlots: [MarkdownViewportSlotView] = []
    weak var viewportScrollView: UIScrollView?
    var viewportScrollObservation: NSKeyValueObservation?
    var viewportReconcileScheduled = false
    var viewportWindowGeneration = 0
    var viewportContainerWidth: CGFloat = 0
    var viewportLastReconciledBounds: CGRect?
    var viewportElements: [MarkdownRenderElement] = []
    var viewportAnchorAnimationGeneration = 0
    var viewportSuppressesAnchorCorrection = false
    var viewportReusableTextViews: [MarkdownViewportReuseKind: [UIView]] = [:]
    let maximumViewportReusableTextViews = 12
    var viewportParsedFormulaCache: [MarkdownViewportFormulaKey: ParsedFormula] = [:]
    var viewportLatexRenderResultCache: [MarkdownViewportLatexResultKey: LatexRenderResult] = [:]
    var viewportTableLayoutCache: [MarkdownViewportTableLayoutKey: MarkdownTableLayoutResult] = [:]
    var viewportCodeBlockMetricsCache: [NSAttributedString: CodeBlockMetrics] = [:]

    // ⚡️ Performance Monitoring
    var renderCosts: [String: Double] = [:]
    /// 记录渲染开始时间（从设置 markdown 属性开始）
    var renderStartTime: CFAbsoluteTime = 0

    /// 供后台解析使用的容器宽度。
    ///
    /// 必须在主线程调用后取快照传入后台闭包 —— `UIScreen.main.bounds` 是 UIKit 状态，
    /// off-main 读取会触发 Main Thread Checker。
    ///
    /// 刻意不取 `bounds.width`：这些调用点都在流式解析路径上，此时自身可能尚未完成布局，
    /// `bounds.width` 会是未定形的中间值，据此排版会把正文压成每行一两个字。
    func currentContainerWidthForParsing() -> CGFloat {
        dispatchPrecondition(condition: .onQueue(.main))
        return UIScreen.main.bounds.width - 32
    }

    func recordCost(for type: String, duration: Double) {
        renderCosts[type, default: 0] += duration
    }

    func printRenderCosts(totalDuration: Double) {
        guard !renderCosts.isEmpty else { return }
        mdLog("\n--- 📊 UI Render Performance (Total: \(String(format: "%.4f", totalDuration))sÅ) ---")
        let sortedCosts = renderCosts.sorted { $0.value > $1.value }
        for (type, cost) in sortedCosts {
            let percentage = (cost / totalDuration) * 100
            if cost > 0.0005 { // Filter out negligible costs (< 0.5ms)
                mdLog(String(format: "   🔸 %-15@ : %.4fs  (%5.1f%%)", type, cost, percentage))
            }
        }
        mdLog("-----------------------------------------------------")
    }

    /// 是否存在目录区域
    public var hasTableOfContentsSection: Bool {
        return tocSectionView != nil
    }
    
    var autoScrollEnabled: Bool = false

    /// 用户主动上滑离开底部后置为 true，暂停自动滚动直到其手动滑回底部
    var userScrolledAway: Bool = false

    /// 合并多次 token 触发的滚动请求，避免 asyncAfter 堆积
    var autoScrollWorkItem: DispatchWorkItem?

    /// 判定"已贴底"的容差
    static let autoScrollBottomTolerance: CGFloat = 44

    // 流式渲染节流（避免过度渲染）
    var lastStreamRenderTime: TimeInterval = 0
    let streamRenderThrottle: TimeInterval = 0.3  // 300ms 节流（大幅降低CPU占用）

    // MARK: - 流式输出震动反馈
    /// 震动反馈生成器（懒加载，仅在需要时创建）
    var hapticFeedbackGenerator: UIImpactFeedbackGenerator?
    /// 上次震动时间（用于节流）
    var lastHapticFeedbackTime: TimeInterval = 0

    // MARK: - 智能流式缓存（真流式模式）

    /// 流式缓存器实例
    lazy var streamBuffer: MarkdownStreamBuffer = {
        let buffer = MarkdownStreamBuffer(
            containerWidth: bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width - 32,
            minModuleLength: configuration.streamMinModuleLength
        )
        // ⭐️ 移除回调绑定：等待动画现在只在流式开始/结束时控制
        // 避免频繁的状态变化导致 UI 闪烁
        return buffer
    }()

    /// 等待动画视图
    lazy var waitingIndicatorView: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.accessibilityIdentifier = "StreamWaitingIndicator"

        // 创建三点动画视图
        let dotsStack = UIStackView()
        dotsStack.axis = .horizontal
        dotsStack.spacing = 6
        dotsStack.distribution = .equalSpacing
        dotsStack.translatesAutoresizingMaskIntoConstraints = false

        for i in 0..<3 {
            let dot = UIView()
            dot.backgroundColor = UIColor.systemGray3
            dot.layer.cornerRadius = 4
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.tag = 100 + i
            dotsStack.addArrangedSubview(dot)

            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 8),
                dot.heightAnchor.constraint(equalToConstant: 8)
            ])
        }

        container.addSubview(dotsStack)
        NSLayoutConstraint.activate([
            dotsStack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            dotsStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.heightAnchor.constraint(equalToConstant: 30)
        ])

        container.isHidden = true
        return container
    }()

    /// 等待动画定时器
    var waitingAnimationTimer: Timer?

    /// 是否正在显示等待动画
    var isShowingWaitingIndicator: Bool = false

    /// ⭐️ 等待检测定时器（检测 TypewriterEngine 空闲且无新数据到达）
    var waitingDetectionTimer: Timer?

    /// ⭐️ 上次收到数据的时间戳
    var lastDataReceivedTime: CFAbsoluteTime = 0

    /// ⭐️ 等待动画显示延迟（秒）- TypewriterEngine 空闲多久后显示等待动画
    let waitingIndicatorDelay: TimeInterval = 0.5

    // MARK: - Real streaming state

    var isRealStreamingMode = false
    var realStreamParsedElementCount = 0
    struct PendingRealStreamElement {
        var element: MarkdownRenderElement
        let globalIndex: Int
        let moduleSequence: Int
    }
    var pendingRealStreamElements = TypewriterPendingQueue<PendingRealStreamElement>()
    var realStreamRenderPumpScheduled = false
    var realStreamRenderGeneration = 0
    var realStreamParseInFlightCount = 0
    struct PendingSmartStreamModule {
        let text: String
        let renderVersion: Int
        let renderGeneration: Int
        let sequence: Int
    }
    var pendingSmartStreamModules = TypewriterPendingQueue<PendingSmartStreamModule>()
    var smartStreamParseActive = false
    var realStreamDrainCompletion: (() -> Void)?
    var isEndingRealStream = false
    var realStreamBackpressureActive = false
    let realStreamTypewriterHighWatermark = 24
    let realStreamTypewriterLowWatermark = 12
    let realStreamFrameBudget: CFTimeInterval = 0.004
    var realStreamNextModuleSequence = 0
    let streamPerformanceDiagnostics = MarkdownStreamPerformanceDiagnostics()

    var heightNotificationScheduled = false
    var pendingForcedHeightNotification = false
    var lastHeightNotificationTimestamp: CFTimeInterval = 0
    var lastLayoutWidthForHeightMeasurement: CGFloat = 0

    /// 宿主显式告知的内容宽度，用于在首次布局之前正确测高。
    ///
    /// 不设置时，`heightMeasurementWidth` 在 `bounds.width == 0`（刚出队、尚未布局的 Cell）
    /// 会退回到整屏宽度做估算，算出的高度明显偏矮；等首次 layoutSubviews 拿到真实宽度后
    /// 又要重新测一次并补发通知，于是 UITableView 会**分两趟**应用行高——
    /// 表现为 Cell 先长高一截、紧接着被重刷一次。宿主若已知最终宽度（例如固定比例的气泡），
    /// 在 configure 时设进来即可让首轮就算准，第二趟补刷不再发生。
    public var preferredMeasurementWidth: CGFloat? {
        didSet {
            guard oldValue != preferredMeasurementWidth else { return }
            invalidateIntrinsicHeightCache()
            invalidateIntrinsicContentSize()
        }
    }
    var realStreamHeightAccumulator = StreamingHeightAccumulator()
    var pendingKnownStreamingHeight: CGFloat?
    var pendingRequiresFullHeightMeasurement = false
    var heightNotificationGeneration = 0
    var cachedIntrinsicHeightWidth: CGFloat?
    var cachedIntrinsicHeight: CGFloat?
    var intrinsicHeightMeasurementCount = 0
    var heightNotificationClock: () -> CFTimeInterval = { CACurrentMediaTime() }
    var heightNotificationScheduler: (TimeInterval, @escaping () -> Void) -> Void = { delay, action in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
    }

    // MARK: - Height reporting state

    var lastReportedHeight: CGFloat = 0

    /// `resetForReuse()` 之后、首次测到正高度之前，屏蔽向宿主上报 0 高度。
    ///
    /// 重置会清空 `contentStackView`，此时测高必然是 0，而 `notifyHeightChange` 里
    /// 那条「瞬时 0」保护要求 `hasVisibleContent == true` 才生效，空栈刚好绕过它，
    /// 于是 `onHeightChange?(0)` 外泄。宿主（如 UITableView 的自适应行高）收到 0 会
    /// 立刻发起一轮行高重算 → 可见 Cell 重建 → 再次 reset → 再报 0，形成自激环。
    /// 这个 0 是纯粹的中间态：内容随后就会重渲染并报出真实高度，宿主不需要看到它。
    var suppressesZeroHeightNotification = false

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
        // 取消待执行的 work item，避免析构后还有异步回调进来
        renderWorkItem?.cancel()
        refreshWorkItem?.cancel()
        autoScrollWorkItem?.cancel()
        offscreenRenderWorkItem?.cancel()
        viewportScrollObservation?.invalidate()

        // 停掉 RunLoop 上的重复定时器。Timer.scheduledTimer 会被 RunLoop 强持有，
        // 视图释放后不 invalidate 会一直空转（waitingDetectionTimer 不会自失效）。
        waitingDetectionTimer?.invalidate()
        waitingAnimationTimer?.invalidate()

        // 清空流式待处理队列，尽早释放未播完的元素/文本
        pendingRealStreamElements.removeAll()
        pendingSmartStreamModules.removeAll()

        // 取消在途订阅（图片加载等）
        cancellables.removeAll()
    }

    public convenience init(markdown: String, configuration: MarkdownConfiguration = .default) {
        self.init(frame: .zero)
        self.configuration = configuration
        self.markdown = markdown
        scheduleRerender()
    }
    
    func setupUI() {
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

        guard let sv = findParentScrollView() else { return }

        let frame = view.convert(view.bounds, to: sv)
        let targetY = max(0, frame.origin.y - 12)
        let maxY = max(0, sv.contentSize.height - sv.bounds.height + sv.contentInset.bottom)

        scrollToViewportAnchorIfNeeded(
            view,
            in: sv,
            targetY: min(targetY, maxY)
        )
    }

    /// 查找父级 ScrollView（用于滚动位置补偿等）
    func findParentScrollView() -> UIScrollView? {
        var superview = self.superview
        while superview != nil {
            if let sv = superview as? UIScrollView {
                return sv
            }
            superview = superview?.superview
        }
        return nil
    }

    /// 判断是否嵌入在可复用的列表单元格中（UITableView/UICollectionView）
    func isEmbeddedInReusableCell() -> Bool {
        var superview = self.superview
        while let view = superview {
            if view is UITableViewCell || view is UICollectionViewCell {
                return true
            }
            superview = view.superview
        }
        return false
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
        
        scrollToViewportAnchorIfNeeded(view, in: sv, targetY: clampedY)
    }
    
    /// 手动播放视图的打字机动画（例如用于目录 TOC）
    /// - Parameter view: 需要动画显示的视图
    public func playTypewriterAnimation(for view: UIView) {
        guard enableTypewriterEffect else {
            view.isHidden = false
            return
        }
        
        // 1. 先隐藏视图，防止闪烁
        view.isHidden = true
        
        // 2. 加入打字机队列
        typewriterEngine.enqueue(view: view, isRoot: true)
        
        // 3. 启动引擎
        typewriterEngine.start()
    }
    
    public func generateTOCView() -> UIView {
        // 1. 准备整段富文本
        let tocTotalAttrString = NSMutableAttributedString()
        
        for (index, item) in tableOfContents.enumerated() {
            // 文本内容
            let itemText = "• " + item.title + (index < tableOfContents.count - 1 ? "\n" : "")
            let attrString = NSMutableAttributedString(string: itemText)
            let range = NSRange(location: 0, length: attrString.length)
            
            // 基础样式
            attrString.addAttribute(.font, value: configuration.bodyFont, range: range)
            attrString.addAttribute(.foregroundColor, value: configuration.tocTextColor, range: range)
            
            // 链接 (Fake Link) - 确保 ID 被正确编码
            if let encodedId = item.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
               let url = URL(string: "toc://\(encodedId)") {
                attrString.addAttribute(.link, value: url, range: range)
                // 显式控制下划线：TextKit 2 对 .link 属性有默认下划线行为，必须用 0 明确关闭
                attrString.addAttribute(
                    .underlineStyle,
                    value: configuration.linkUnderlineEnabled ? NSUnderlineStyle.single.rawValue : 0,
                    range: range
                )
            }
            
            // 缩进样式
            let indent = CGFloat(item.level - 1) * 20.0
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.headIndent = indent + 15 // 悬挂缩进
            paragraphStyle.firstLineHeadIndent = indent
            paragraphStyle.paragraphSpacing = 6 // 行间距
            attrString.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
            
            tocTotalAttrString.append(attrString)
        }
        
        // 2. 创建单个 TextView
        let containerWidth = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width - 32
        let tocContainer = createTextView(
            with: tocTotalAttrString,
            width: containerWidth,
            insets: UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        )
        
        // 3. 绑定点击事件
        if let textView = tocContainer.subviews.first(where: { $0 is MarkdownTextViewTK2 }) as? MarkdownTextViewTK2 {
            textView.onLinkTap = { [weak self] url in
                if url.scheme == "toc" {
                    // 解码 ID 并跳转
                    let encodedId = url.absoluteString.replacingOccurrences(of: "toc://", with: "")
                    if let id = encodedId.removingPercentEncoding,
                       let targetItem = self?.tableOfContents.first(where: { $0.id == id }) {
                        self?.onTOCItemTap?(targetItem)
                        self?.scrollToTOCItem(targetItem)
                    }
                } else {
                    self?.onLinkTap?(url)
                }
            }
        }
        
        return tocContainer
    }
    
    @objc private func tocItemTapped(_ sender: UIButton) {
        let index = sender.tag
        guard index < tableOfContents.count else { return }
        let item = tableOfContents[index]
        onTOCItemTap?(item)
        scrollToTOCItem(item)
    }
    
}
