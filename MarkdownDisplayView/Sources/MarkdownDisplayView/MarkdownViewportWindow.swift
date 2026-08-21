//
//  MarkdownViewportWindow.swift
//  MarkdownDisplayView
//
//  Keeps lightweight document geometry resident while mounting expensive
//  drawing views only near the enclosing scroll view's viewport.
//

import UIKit
import Foundation

@available(iOS 15.0, *)
enum MarkdownViewportReuseKind: Hashable {
    case heading
    case paragraph
    case inlineParagraph
}

@available(iOS 15.0, *)
struct MarkdownViewportFormulaKey: Hashable {
    let latex: String
    let fontSize: CGFloat
}

@available(iOS 15.0, *)
struct MarkdownViewportLatexResultKey: Hashable {
    let formula: MarkdownViewportFormulaKey
    let padding: CGFloat
    let maxWidth: CGFloat
}

@available(iOS 15.0, *)
struct MarkdownViewportTableLayoutKey: Hashable {
    let headers: [NSAttributedString]
    let rows: [[NSAttributedString]]
    let columnAlignments: [NSTextAlignment?]
    let containerWidth: CGFloat
    let minColumnWidth: CGFloat
    let maxColumnWidth: CGFloat
    let cellPadding: CGFloat
    let cellVerticalPadding: CGFloat
    let rowHeight: CGFloat
    let separatorHeight: CGFloat
}

@available(iOS 15.0, *)
enum MarkdownViewportPreparedBlock {
    case latex(LatexRenderResult)
    case table(MarkdownTableLayoutResult)
    case codeBlock(CodeBlockMetrics)
}

@available(iOS 15.0, *)
struct MarkdownViewportPreservedSlotState {
    let horizontalContentOffsets: [String: CGFloat]
}

@available(iOS 15.0, *)
final class MarkdownViewportSlotView: UIView {
    let elementIndex: Int
    let element: MarkdownRenderElement
    let reuseKind: MarkdownViewportReuseKind?
    var fixedTextHeight: CGFloat?
    var preparedBlock: MarkdownViewportPreparedBlock?
    var horizontalContentOffsets: [String: CGFloat]

    private(set) var contentView: UIView?
    private(set) var cachedHeight: CGFloat
    private(set) var hasMeasuredContentHeight = false
    private var heightConstraint: NSLayoutConstraint!

    init(
        elementIndex: Int,
        element: MarkdownRenderElement,
        estimatedHeight: CGFloat,
        fixedTextHeight: CGFloat?,
        preparedBlock: MarkdownViewportPreparedBlock? = nil,
        horizontalContentOffsets: [String: CGFloat] = [:],
        hasMeasuredContentHeight: Bool = false,
        reuseKind: MarkdownViewportReuseKind? = nil
    ) {
        self.elementIndex = elementIndex
        self.element = element
        self.fixedTextHeight = fixedTextHeight
        self.preparedBlock = preparedBlock
        self.horizontalContentOffsets = horizontalContentOffsets
        self.reuseKind = reuseKind
        self.cachedHeight = max(1, estimatedHeight)
        self.hasMeasuredContentHeight = hasMeasuredContentHeight
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isAccessibilityElement = false

        heightConstraint = heightAnchor.constraint(equalToConstant: cachedHeight)
        heightConstraint.priority = .required
        heightConstraint.isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @discardableResult
    func install(_ view: UIView, measuredHeight: CGFloat) -> CGFloat {
        let oldHeight = cachedHeight
        contentView?.removeFromSuperview()

        cachedHeight = max(1, measuredHeight)
        hasMeasuredContentHeight = true
        heightConstraint.constant = cachedHeight
        contentView = view

        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        return cachedHeight - oldHeight
    }

    func uninstall() -> UIView? {
        guard let contentView else { return nil }
        self.contentView = nil
        contentView.removeFromSuperview()
        heightConstraint.constant = cachedHeight
        return contentView
    }

    @discardableResult
    func updateCachedHeight(_ height: CGFloat) -> CGFloat {
        let oldHeight = cachedHeight
        cachedHeight = max(1, height)
        heightConstraint.constant = cachedHeight
        return cachedHeight - oldHeight
    }

    func invalidateMeasuredContentHeight() {
        hasMeasuredContentHeight = false
    }
}

@available(iOS 15.0, *)
extension MarkdownViewTextKit {
    func shouldUseStaticViewportWindow(for elements: [MarkdownRenderElement]) -> Bool {
        let embeddedInReusableCell = isEmbeddedInReusableCell()
        guard let hostScrollView = viewportHostScrollView() else { return false }
        guard !isStreaming,
              !isRealStreamingMode,
              elements.count > 5,
              !embeddedInReusableCell || (
                allowsStaticViewportRenderingInReusableCell
                    && isDisplayingPreparedStaticContent
                    && reusableCellDocumentExceedsViewportThreshold(in: hostScrollView)
              ) else {
            return false
        }
        return elements.contains(where: isViewportVirtualizableElement)
    }

    /// 视口窗口应该观察承载文档的纵向滚动宿主。Cell 内优先返回
    /// UITableView / UICollectionView，避免将表格或代码块的横向滚动视图
    /// 误当成文档视口。
    func viewportHostScrollView() -> UIScrollView? {
        var nearestScrollView: UIScrollView?
        var crossedReusableCellBoundary = false
        var superview = superview
        while let current = superview {
            if current is UITableViewCell || current is UICollectionViewCell {
                crossedReusableCellBoundary = true
            }
            // ScrollableMarkdownViewTextKit 或业务自己的纵向 scroll view 若位于
            // MarkdownView 与 Cell 之间，它才是直接文档视口。
            if !crossedReusableCellBoundary, let scrollView = current as? UIScrollView {
                return scrollView
            }
            if let tableView = current as? UITableView { return tableView }
            if let collectionView = current as? UICollectionView { return collectionView }
            if nearestScrollView == nil, let scrollView = current as? UIScrollView {
                nearestScrollView = scrollView
            }
            superview = current.superview
        }
        return nearestScrollView
    }

    func reusableCellDocumentExceedsViewportThreshold(in scrollView: UIScrollView) -> Bool {
        guard let estimatedHeight = preparedStaticEstimatedHeight,
              estimatedHeight.isFinite else { return false }
        // loadRect 本身覆盖当前屏前后各一屏。文档不足三屏时几乎无法
        // 回收内容，启用槽位与 KVO 只会增加 CPU 和对象数。
        let minimumHeight = max(1_800, max(1, scrollView.bounds.height) * 3)
        return estimatedHeight >= minimumHeight
    }

    func isViewportVirtualizableElement(_ element: MarkdownRenderElement) -> Bool {
        switch element {
        case .attributedText(let text):
            return text.length > 0
        case .heading, .latex, .table:
            return true
        case .codeBlock(let language, _):
            guard let language else { return true }
            // 自定义 renderer 可能维护播放、选择或业务状态，不能按默认代码块销毁。
            return MarkdownCustomExtensionManager.shared.codeBlockRenderer(for: language) == nil
        case .list(let items, _):
            return items.allSatisfy { item in
                item.children.allSatisfy(isViewportSafeListChild)
            }
        case .quote(let children, _):
            return children.allSatisfy(isViewportSafeCompositeChild)
        default:
            return false
        }
    }

    func isViewportSafeCompositeChild(_ element: MarkdownRenderElement) -> Bool {
        switch element {
        case .custom, .details:
            // 这两类允许调用方持有任意交互状态；没有通用序列化协议时保留 identity。
            return false
        case .codeBlock(let language, _):
            guard let language else { return true }
            return MarkdownCustomExtensionManager.shared.codeBlockRenderer(for: language) == nil
        case .list(let items, _):
            return items.allSatisfy { item in
                item.children.allSatisfy(isViewportSafeListChild)
            }
        case .quote(let children, _):
            return children.allSatisfy(isViewportSafeCompositeChild)
        default:
            return true
        }
    }

    func isViewportSafeListChild(_ element: MarkdownRenderElement) -> Bool {
        // List item 的真实高度是 max(marker, content)。异步图片缩到 marker 以下时，
        // 裸图片 delta 不再等于 item delta；在引入 item 级状态前保留这类列表 identity。
        guard !viewportElementHasDynamicHeight(element) else { return false }
        return isViewportSafeCompositeChild(element)
    }

    func viewportElementHasDynamicHeight(_ element: MarkdownRenderElement) -> Bool {
        switch element {
        case .image:
            return true
        case .attributedText(let text):
            return text.containsAttachments(in: NSRange(location: 0, length: text.length))
        case .list(let items, _):
            return items.contains { item in
                item.children.contains(where: viewportElementHasDynamicHeight)
            }
        case .quote(let children, _):
            return children.contains(where: viewportElementHasDynamicHeight)
        default:
            return false
        }
    }

    func updateViewportWindowViews(
        elements: [MarkdownRenderElement],
        footnotes: [MarkdownFootnote],
        containerWidth: CGFloat,
        startTime: CFAbsoluteTime,
        perfStartTime: CFAbsoluteTime,
        precalculatedTextHeights: [CGFloat?]?
    ) {
        let preservedSlotStates = reusableViewportSlotStates(
            for: elements,
            containerWidth: containerWidth
        )
        let reusableAtomicViews = reusableViewportAtomicViews(for: elements)
        teardownViewportWindow()
        contentStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        headingViews.removeAll(keepingCapacity: true)
        tocSectionView = nil

        viewportContainerWidth = containerWidth
        lastLayoutWidthForHeightMeasurement = containerWidth
        viewportWindowGeneration += 1

        let hostScrollView = viewportHostScrollView()
        let viewportHeight = max(
            UIScreen.main.bounds.height,
            hostScrollView?.bounds.height ?? 0
        )
        // 普通长文从顶部预热两屏；Cell 可能被恢复到一条超高消息的中部，
        // 此时直接预热 table 当前视口附近，避免先分配文档顶部 backing
        // 并在下一帧才补齐当前内容。
        let fallbackInitialLoadRect = CGRect(
            x: 0,
            y: 0,
            width: containerWidth,
            height: viewportHeight * 2
        )
        let initialLoadRect: CGRect
        if isEmbeddedInReusableCell(),
           window != nil,
           let hostScrollView {
            let visibleRect = hostScrollView.convert(hostScrollView.bounds, to: self)
            initialLoadRect = visibleRect.height > 0
                ? visibleRect.insetBy(dx: 0, dy: -visibleRect.height)
                : fallbackInitialLoadRect
        } else {
            initialLoadRect = fallbackInitialLoadRect
        }
        var estimatedDocumentY: CGFloat = 0

        for (index, element) in elements.enumerated() {
            let precalculatedHeight = precalculatedTextHeights?[safe: index] ?? nil
            let preservedState = preservedSlotStates[index]
            // 每次文档提交都按当前 configuration 重建纯几何；只在同一静态
            // snapshot 的滚动挂载之间复用，避免主题/字号变化后沿用旧尺寸。
            let preparedBlock = prepareViewportBlock(
                for: element,
                containerWidth: containerWidth
            )
            let fixedTextHeight = fixedViewportTextHeight(
                for: element,
                containerWidth: containerWidth,
                precalculatedTextHeight: precalculatedHeight
            )
            let estimatedHeight = estimatedViewportSlotHeight(
                for: element,
                containerWidth: containerWidth,
                precalculatedTextHeight: fixedTextHeight ?? precalculatedHeight,
                preparedBlock: preparedBlock
            )
            if isViewportVirtualizableElement(element) {
                let slot = MarkdownViewportSlotView(
                    elementIndex: index,
                    element: element,
                    estimatedHeight: estimatedHeight,
                    fixedTextHeight: fixedTextHeight,
                    preparedBlock: preparedBlock,
                    horizontalContentOffsets: preservedState?.horizontalContentOffsets ?? [:],
                    reuseKind: viewportReuseKind(for: element)
                )
                viewportSlots.append(slot)
                contentStackView.addArrangedSubview(slot)

                if case .heading(let id, _) = element {
                    headingViews[id] = slot
                    if id == tocSectionId { tocSectionView = slot }
                }

                let estimatedFrame = CGRect(
                    x: 0,
                    y: estimatedDocumentY,
                    width: containerWidth,
                    height: slot.cachedHeight
                )
                if estimatedFrame.intersects(initialLoadRect) {
                    mountViewportSlot(slot)
                }
                estimatedDocumentY += slot.cachedHeight
            } else {
                let view = reusableAtomicViews[index] ?? createView(
                    for: element,
                    containerWidth: containerWidth,
                    precalculatedHeight: precalculatedHeight
                )
                contentStackView.addArrangedSubview(view)
                estimatedDocumentY += estimatedHeight
            }
        }

        // 视口路径每次重建轻量槽位，不参与旧的视图 diff；避免额外保留一份元素数组。
        oldElements = []
        viewportElements = elements
        updateFootnotes(footnotes, width: containerWidth, newElementCount: elements.count)
        loadImages()
        invalidateIntrinsicContentSize()
        notifyHeightChange(force: true)

        refreshViewportObservationIfNeeded()
        if isEmbeddedInReusableCell(), window != nil {
            // Cell 可在非顶部位置被恢复或批量更新后重建。同步对齐一次
            // 真实 table viewport，避免一帧空白；正常滚动仍由异步 reconcile 节流。
            layoutIfNeeded()
            contentStackView.layoutIfNeeded()
            viewportLastReconciledBounds = nil
            reconcileViewportWindow()
        } else {
            scheduleViewportReconcile()
        }

        if perfStartTime > 0 {
            let firstFrameTime = (CFAbsoluteTimeGetCurrent() - perfStartTime) * 1000
            let renderTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            mdLog("[Viewport] first frame: \(String(format: "%.1f", firstFrameTime))ms, render: \(String(format: "%.1f", renderTime))ms, slots=\(viewportSlots.count)")
        }
    }

    /// 真流式完全 drain 后，将已经正确显示的整棵视图树原地收敛为静态
    /// viewport slots。当前视口附近的 root view 直接换父视图，保留 TextKit /
    /// CALayer identity；离屏 root 立即释放或收入有界文本池。
    ///
    /// - Returns: 是否执行了 promotion。短内容、未 opt-in 的 Cell 继续保持原流式 UI。
    @discardableResult
    func promoteCompletedStreamToViewportWindow(
        elements: [MarkdownRenderElement],
        footnotes: [MarkdownFootnote],
        containerWidth: CGFloat
    ) -> Bool {
        guard elements.count > 5,
              elements.contains(where: isViewportVirtualizableElement),
              let hostScrollView = viewportHostScrollView() else { return false }

        contentStackView.setNeedsLayout()
        contentStackView.layoutIfNeeded()
        let structuralHeight = max(
            realStreamHeightAccumulator.totalHeight,
            contentStackView.bounds.height,
            contentStackView.arrangedSubviews.reduce(CGFloat.zero) {
                $0 + max($1.frame.height, $1.bounds.height)
            }
        )
        let minimumHeight = max(1_800, max(1, hostScrollView.bounds.height) * 3)
        if isEmbeddedInReusableCell() {
            guard allowsStaticViewportRenderingInReusableCell,
                  structuralHeight >= minimumHeight else { return false }
        } else {
            guard structuralHeight >= minimumHeight else { return false }
        }

        let existingRoots = contentStackView.arrangedSubviews
        var rootsByIndex: [Int: UIView] = [:]
        for root in existingRoots {
            let index = root.tag - 1000
            guard elements.indices.contains(index) else { continue }
            rootsByIndex[index] = root
        }

        let viewport = hostScrollView.convert(hostScrollView.bounds, to: self)
        let keepRect = viewport.height > 0
            ? viewport.insetBy(dx: 0, dy: -viewport.height * 1.5)
            : CGRect(x: 0, y: 0, width: containerWidth, height: minimumHeight)
        var captured: [Int: (view: UIView, frame: CGRect, height: CGFloat)] = [:]
        var fallbackDocumentY: CGFloat = 0
        for index in elements.indices {
            guard let root = rootsByIndex[index] else { continue }
            root.isHidden = false
            root.alpha = 1
            root.setNeedsLayout()
            root.layoutIfNeeded()
            let laidOutFrame = root.convert(root.bounds, to: self)
            let fallback = estimatedViewportSlotHeight(
                for: elements[index],
                containerWidth: containerWidth,
                precalculatedTextHeight: nil
            )
            let height: CGFloat
            if laidOutFrame.height.isFinite, laidOutFrame.height > 0.5 {
                height = laidOutFrame.height
            } else {
                height = measuredViewportContentHeight(
                    root,
                    width: containerWidth,
                    fallback: fallback
                )
            }
            let verifiedHeight = max(1, height)
            let frame: CGRect
            if laidOutFrame.height > 0.5 {
                frame = laidOutFrame
                fallbackDocumentY = laidOutFrame.maxY
            } else {
                // Self-sizing Cell 在 batch update 的过渡帧可能已有最终高度约束，
                // 但 root frame 尚未提交。按流式顺序累加已验证高度，仍能正确
                // 判断当前 table viewport，避免将可见 root 误回收造成空白。
                frame = CGRect(
                    x: 0,
                    y: fallbackDocumentY,
                    width: containerWidth,
                    height: verifiedHeight
                )
                fallbackDocumentY = frame.maxY
            }
            captured[index] = (root, frame, verifiedHeight)
        }

        let oldSuppressesAnchorCorrection = viewportSuppressesAnchorCorrection
        viewportSuppressesAnchorCorrection = true
        defer { viewportSuppressesAnchorCorrection = oldSuppressesAnchorCorrection }

        teardownViewportWindow()
        existingRoots.forEach { $0.removeFromSuperview() }
        headingViews.removeAll(keepingCapacity: true)
        tocSectionView = nil
        viewportContainerWidth = containerWidth
        lastLayoutWidthForHeightMeasurement = containerWidth
        viewportWindowGeneration += 1

        var retainedRootIDs = Set<ObjectIdentifier>()
        UIView.performWithoutAnimation {
            for (index, element) in elements.enumerated() {
                let existing = captured[index]
                let verifiedHeight = existing?.height ?? estimatedViewportSlotHeight(
                    for: element,
                    containerWidth: containerWidth,
                    precalculatedTextHeight: nil
                )

                if isViewportVirtualizableElement(element) {
                    let fixedTextHeight = completedStreamFixedTextHeight(
                        for: element,
                        existingRoot: existing?.view,
                        containerWidth: containerWidth
                    )
                    let slot = MarkdownViewportSlotView(
                        elementIndex: index,
                        element: element,
                        estimatedHeight: verifiedHeight,
                        fixedTextHeight: fixedTextHeight,
                        hasMeasuredContentHeight: existing != nil,
                        reuseKind: viewportReuseKind(for: element)
                    )
                    viewportSlots.append(slot)
                    contentStackView.addArrangedSubview(slot)

                    if case .heading(let id, _) = element {
                        headingViews[id] = slot
                        if id == tocSectionId { tocSectionView = slot }
                    }

                    guard let existing else { continue }
                    retainedRootIDs.insert(ObjectIdentifier(existing.view))
                    if existing.frame.intersects(keepRect) {
                        slot.install(existing.view, measuredHeight: verifiedHeight)
                    } else if let kind = slot.reuseKind,
                              markdownTextView(in: existing.view) != nil {
                        prepareViewportContentForReuse(existing.view)
                        existing.view.isHidden = true
                        enqueueViewportTextView(existing.view, for: kind)
                    } else {
                        prepareViewportContentForRemoval(existing.view)
                    }
                } else {
                    let view = existing?.view ?? createView(
                        for: element,
                        containerWidth: containerWidth
                    )
                    retainedRootIDs.insert(ObjectIdentifier(view))
                    contentStackView.addArrangedSubview(view)
                    if case .heading(let id, _) = element {
                        headingViews[id] = view
                        if id == tocSectionId { tocSectionView = view }
                    }
                }
            }
        }

        // 异常重复流式 element 或旧等待视图不应被新槽位间接保留。
        for root in existingRoots where !retainedRootIDs.contains(ObjectIdentifier(root)) {
            prepareViewportContentForRemoval(root)
        }

        trimViewportTextViewPool()
        oldElements.removeAll(keepingCapacity: false)
        viewportElements = elements
        isDisplayingPreparedStaticContent = true
        preparedStaticEstimatedHeight = structuralHeight
        updateFootnotes(footnotes, width: containerWidth, newElementCount: elements.count)
        loadImages()
        invalidateIntrinsicHeightCache()
        invalidateIntrinsicContentSize()
        contentStackView.setNeedsLayout()
        contentStackView.layoutIfNeeded()
        preparedStaticEstimatedHeight = max(
            structuralHeight,
            contentStackView.systemLayoutSizeFitting(
                CGSize(width: containerWidth, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
        )

        refreshViewportObservationIfNeeded()
        viewportLastReconciledBounds = nil
        reconcileViewportWindow()
        mdLog("[Viewport] promoted completed stream: elements=\(elements.count), slots=\(viewportSlots.count)")
        return true
    }

    func completedStreamFixedTextHeight(
        for element: MarkdownRenderElement,
        existingRoot: UIView?,
        containerWidth: CGFloat
    ) -> CGFloat? {
        // 只有不含动态 attachment 的文本能固定高度。该高度属于内层
        // MarkdownTextViewTK2，不能使用包含 paragraph/heading insets 的 root 高度，
        // 否则重建 wrapper 时会再叠加一次上下间距。
        guard let measuredFallback = fixedViewportTextHeight(
            for: element,
            containerWidth: containerWidth,
            precalculatedTextHeight: nil
        ) else { return nil }

        if let existingRoot,
           let textView = markdownTextView(in: existingRoot) {
            textView.layoutIfNeeded()
            let displayedHeight = max(textView.bounds.height, textView.frame.height)
            if displayedHeight.isFinite, displayedHeight > 0.5 {
                return ceil(displayedHeight)
            }
        }
        return measuredFallback
    }

    func leaveViewportWindowForLegacyRendering() {
        guard !viewportSlots.isEmpty else { return }
        teardownViewportWindow()
        contentStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        oldElements.removeAll(keepingCapacity: false)
        headingViews.removeAll(keepingCapacity: true)
        tocSectionView = nil
    }

    func reusableViewportSlotStates(
        for newElements: [MarkdownRenderElement],
        containerWidth: CGFloat
    ) -> [Int: MarkdownViewportPreservedSlotState] {
        guard abs(viewportContainerWidth - containerWidth) < 0.5 else { return [:] }

        var states: [Int: MarkdownViewportPreservedSlotState] = [:]
        for slot in viewportSlots {
            guard let newElement = newElements[safe: slot.elementIndex],
                  newElement == slot.element else {
                continue
            }
            captureViewportInteractionState(from: slot)
            states[slot.elementIndex] = MarkdownViewportPreservedSlotState(
                horizontalContentOffsets: slot.horizontalContentOffsets
            )
        }
        return states
    }

    func viewportLatexRenderResult(
        latex: String,
        containerWidth: CGFloat
    ) -> LatexRenderResult {
        let formulaKey = MarkdownViewportFormulaKey(
            latex: latex,
            fontSize: configuration.latexFontSize
        )
        let maxWidth = max(1, containerWidth - configuration.latexPadding * 2)
        let resultKey = MarkdownViewportLatexResultKey(
            formula: formulaKey,
            padding: configuration.latexPadding,
            maxWidth: maxWidth
        )

        if let cached = viewportLatexRenderResultCache[resultKey] {
            return cached
        }

        let formula: ParsedFormula
        if let cached = viewportParsedFormulaCache[formulaKey] {
            formula = cached
        } else {
            formula = ParsedFormula.parse(
                latex: latex,
                fontSize: configuration.latexFontSize
            )
            viewportParsedFormulaCache[formulaKey] = formula
        }

        let result = LatexRenderResult(
            formula: formula,
            padding: configuration.latexPadding,
            maxWidth: maxWidth
        )
        viewportLatexRenderResultCache[resultKey] = result
        return result
    }

    func prepareViewportBlock(
        for element: MarkdownRenderElement,
        containerWidth: CGFloat
    ) -> MarkdownViewportPreparedBlock? {
        switch element {
        case .latex(let latex):
            return .latex(viewportLatexRenderResult(
                latex: latex,
                containerWidth: containerWidth
            ))
        case .table(let data):
            return .table(viewportTableLayout(
                data: data,
                containerWidth: containerWidth
            ))
        case .codeBlock(let language, let code):
            if let language,
               MarkdownCustomExtensionManager.shared.codeBlockRenderer(for: language) != nil {
                return nil
            }
            return .codeBlock(viewportCodeBlockMetrics(for: code))
        default:
            return nil
        }
    }

    func viewportTableLayout(
        data: MarkdownTableData,
        containerWidth: CGFloat
    ) -> MarkdownTableLayoutResult {
        let key = MarkdownViewportTableLayoutKey(
            headers: data.headers,
            rows: data.rows,
            columnAlignments: data.columnAlignments,
            containerWidth: containerWidth,
            minColumnWidth: configuration.tableMinColumnWidth,
            maxColumnWidth: configuration.tableMaxColumnWidth,
            cellPadding: configuration.tableCellPadding,
            cellVerticalPadding: configuration.tableCellVerticalPadding,
            rowHeight: configuration.tableRowHeight,
            separatorHeight: configuration.tableSeparatorHeight
        )
        if let cached = viewportTableLayoutCache[key] {
            return cached
        }
        let result = MarkdownTableLayoutCalculator.calculate(
            data: data,
            config: configuration,
            containerWidth: containerWidth
        )
        viewportTableLayoutCache[key] = result
        return result
    }

    func viewportCodeBlockMetrics(for code: NSAttributedString) -> CodeBlockMetrics {
        if let cached = viewportCodeBlockMetricsCache[code] {
            return cached
        }
        let metrics = CodeBlockMetrics.calculate(for: code)
        viewportCodeBlockMetricsCache[code] = metrics
        return metrics
    }

    /// 非虚拟原子块保持原有 UIView identity，避免 Details、自定义扩展等交互状态丢失。
    func reusableViewportAtomicViews(
        for newElements: [MarkdownRenderElement]
    ) -> [Int: UIView] {
        guard viewportElements.count <= contentStackView.arrangedSubviews.count else {
            return [:]
        }

        var result: [Int: UIView] = [:]
        for index in newElements.indices where index < viewportElements.count {
            let element = newElements[index]
            guard !isViewportVirtualizableElement(element),
                  element == viewportElements[index],
                  let view = contentStackView.arrangedSubviews[safe: index],
                  !(view is MarkdownViewportSlotView) else {
                continue
            }
            result[index] = view
        }
        return result
    }

    func refreshViewportObservationIfNeeded() {
        guard !viewportSlots.isEmpty else {
            viewportScrollObservation?.invalidate()
            viewportScrollObservation = nil
            viewportScrollView = nil
            return
        }

        let scrollView = viewportHostScrollView()
        guard viewportScrollView !== scrollView else { return }

        viewportScrollObservation?.invalidate()
        viewportScrollObservation = nil
        viewportScrollView = scrollView

        guard let scrollView else { return }
        viewportScrollObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            self?.scheduleViewportReconcile()
        }
    }

    func scheduleViewportReconcile() {
        guard !viewportSlots.isEmpty, !viewportReconcileScheduled else { return }
        viewportReconcileScheduled = true
        let generation = viewportWindowGeneration

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.viewportReconcileScheduled = false
            guard generation == self.viewportWindowGeneration else { return }
            self.reconcileViewportWindow()
        }
    }

    func reconcileViewportWindow() {
        guard !viewportSlots.isEmpty else { return }
        refreshViewportObservationIfNeeded()
        guard let scrollView = viewportScrollView, window != nil else { return }

        let viewport = scrollView.convert(scrollView.bounds, to: self)
        guard viewport.height > 0 else { return }

        // Overscan 足够覆盖小幅滚动；跨过约 1/4 屏才重新扫描槽位，避免每个
        // contentOffset 回调都遍历全文，同时快速跳转仍会立即命中。
        if let lastViewport = viewportLastReconciledBounds,
           abs(viewport.minY - lastViewport.minY) < viewport.height * 0.25,
           abs(viewport.height - lastViewport.height) < 0.5 {
            return
        }
        viewportLastReconciledBounds = viewport

        // 只有跨过节流阈值才强制解析槽位几何，避免每个 contentOffset 回调都
        // 把 Auto Layout 拉进滚动热路径。
        layoutIfNeeded()
        contentStackView.layoutIfNeeded()

        let loadRect = viewport.insetBy(dx: 0, dy: -viewport.height)
        let keepRect = viewport.insetBy(dx: 0, dy: -viewport.height * 1.5)
        var heightDeltaAboveViewport: CGFloat = 0
        var geometryChanged = false
        let slotFrames = viewportSlots.map { slot in
            (slot: slot, frame: slot.convert(slot.bounds, to: self))
        }

        // 必须先回收再挂载：快速跳转或反向滚动时也能在同一帧复用旧的
        // TextKit/CALayer identity，而不是先创建一批新 backing store。
        for item in slotFrames where item.slot.contentView != nil {
            if !item.frame.intersects(keepRect) {
                recycleViewportSlot(item.slot)
            }
        }

        for item in slotFrames where item.slot.contentView == nil && item.frame.intersects(loadRect) {
            let oldHeight = item.slot.cachedHeight
            mountViewportSlot(item.slot)
            let delta = item.slot.cachedHeight - oldHeight
            if abs(delta) > 0.5 {
                geometryChanged = true
                if item.frame.maxY <= viewport.minY {
                    heightDeltaAboveViewport += delta
                }
            }
        }
        trimViewportTextViewPool()

        if geometryChanged {
            contentStackView.setNeedsLayout()
            contentStackView.layoutIfNeeded()
            invalidateIntrinsicHeightCache()
            invalidateIntrinsicContentSize()
            scheduleHeightChangeNotification()

            if abs(heightDeltaAboveViewport) > 0.5,
               !viewportSuppressesAnchorCorrection,
               !isEmbeddedInReusableCell() {
                var offset = scrollView.contentOffset
                offset.y += heightDeltaAboveViewport
                scrollView.setContentOffset(offset, animated: false)
            }
        }
    }

    func mountViewportSlot(_ slot: MarkdownViewportSlotView) {
        guard slot.contentView == nil else { return }
        let view: UIView
        if let kind = slot.reuseKind,
           let reusableView = dequeueViewportTextView(for: kind),
           configureViewportTextView(reusableView, for: slot) {
            view = reusableView
        } else {
            view = createViewportContentView(for: slot)
        }
        let measuredHeight: CGFloat
        if slot.fixedTextHeight != nil || slot.preparedBlock != nil {
            // 纯文本槽位与 TextView 使用同一份 fixedTextHeight，挂载不会改变
            // 文档几何；公式/表格/默认代码也已有精确测量结果。避免滚动时
            // 为这些 wrapper 再跑一遍 Auto Layout fitting。
            measuredHeight = slot.cachedHeight
        } else if slot.reuseKind == nil,
                  slot.hasMeasuredContentHeight,
                  !viewportElementHasDynamicHeight(slot.element) {
            // 列表/引用首次挂载后已有真实高度；无异步图片时重建结构不会改变几何。
            measuredHeight = slot.cachedHeight
        } else {
            // 行内公式/图片的附件尺寸可能与 boundingRect 估算不同，且图片加载后
            // 还会变化；这类少数段落保留 TextKit + Auto Layout 精确测量。
            measuredHeight = measuredViewportContentHeight(
                view,
                width: viewportContainerWidth,
                fallback: slot.cachedHeight
            )
        }
        slot.install(view, measuredHeight: measuredHeight)
        slot.setNeedsLayout()
        slot.layoutIfNeeded()
        restoreViewportInteractionState(to: slot)
    }

    func createViewportContentView(for slot: MarkdownViewportSlotView) -> UIView {
        switch (slot.element, slot.preparedBlock) {
        case (.latex(let latex), .latex(let result)):
            return createLatexView(
                latex: latex,
                width: viewportContainerWidth,
                topSpacing: 8,
                bottomSpacing: 8,
                renderResult: result
            )
        case (.table(let data), .table(let result)):
            return createTableView(
                data: data,
                width: viewportContainerWidth,
                layoutResult: result
            )
        case (.codeBlock(let language, let code), .codeBlock(let metrics)):
            return createCodeBlockView(
                language: language,
                code: code,
                width: viewportContainerWidth,
                metrics: metrics
            )
        default:
            return createView(
                for: slot.element,
                containerWidth: viewportContainerWidth,
                precalculatedHeight: slot.fixedTextHeight
            )
        }
    }

    func recycleViewportSlot(_ slot: MarkdownViewportSlotView) {
        guard slot.contentView != nil else { return }
        captureViewportInteractionState(from: slot)
        guard let content = slot.uninstall() else { return }

        if let kind = slot.reuseKind,
           markdownTextView(in: content) != nil {
            prepareViewportContentForReuse(content)
            content.isHidden = true
            enqueueViewportTextView(content, for: kind)
        } else {
            // 表格、公式、代码块、列表和引用不跨元素复用 UIView。离屏后立即
            // 释放它们的附件视图与 backing store，只保留轻量几何和交互状态。
            prepareViewportContentForRemoval(content)
        }
    }

    func horizontalViewportScrollViews(in root: UIView) -> [(path: String, view: UIScrollView)] {
        var result: [(path: String, view: UIScrollView)] = []

        func visit(_ view: UIView, path: String) {
            if let scrollView = view as? UIScrollView,
               scrollView.contentSize.width > scrollView.bounds.width + 0.5 {
                result.append((path, scrollView))
            }
            for (index, subview) in view.subviews.enumerated() {
                let childPath = path.isEmpty ? String(index) : "\(path).\(index)"
                visit(subview, path: childPath)
            }
        }

        visit(root, path: "root")
        return result
    }

    func captureViewportInteractionState(from slot: MarkdownViewportSlotView) {
        guard let content = slot.contentView else { return }
        content.setNeedsLayout()
        content.layoutIfNeeded()
        slot.horizontalContentOffsets = Dictionary(
            uniqueKeysWithValues: horizontalViewportScrollViews(in: content).map {
                ($0.path, $0.view.contentOffset.x)
            }
        )
    }

    func restoreHorizontalViewportOffset(
        _ preservedX: CGFloat,
        to scrollView: UIScrollView
    ) {
        let minX = -scrollView.adjustedContentInset.left
        let maxX = max(
            minX,
            scrollView.contentSize.width
                - scrollView.bounds.width
                + scrollView.adjustedContentInset.right
        )
        let x = min(max(preservedX, minX), maxX)
        scrollView.setContentOffset(
            CGPoint(x: x, y: scrollView.contentOffset.y),
            animated: false
        )
    }

    func restoreViewportInteractionState(to slot: MarkdownViewportSlotView) {
        guard let content = slot.contentView,
              !slot.horizontalContentOffsets.isEmpty else { return }

        content.layoutIfNeeded()
        for item in horizontalViewportScrollViews(in: content) {
            guard let preservedX = slot.horizontalContentOffsets[item.path] else { continue }
            restoreHorizontalViewportOffset(preservedX, to: item.view)
        }
    }

    func configureViewportTextView(
        _ view: UIView,
        for slot: MarkdownViewportSlotView
    ) -> Bool {
        guard let textView = markdownTextView(in: view) else { return false }

        let attributedText: NSAttributedString
        switch slot.element {
        case .heading(_, let text), .attributedText(let text):
            attributedText = text
        default:
            return false
        }

        configureTextView(
            textView,
            with: attributedText,
            width: viewportContainerWidth,
            fixedHeight: slot.fixedTextHeight
        )
        view.isHidden = false
        view.alpha = 1
        return true
    }

    func dequeueViewportTextView(for kind: MarkdownViewportReuseKind) -> UIView? {
        guard var views = viewportReusableTextViews[kind], let view = views.popLast() else {
            return nil
        }
        if views.isEmpty {
            viewportReusableTextViews.removeValue(forKey: kind)
        } else {
            viewportReusableTextViews[kind] = views
        }
        return view
    }

    func enqueueViewportTextView(_ view: UIView, for kind: MarkdownViewportReuseKind) {
        viewportReusableTextViews[kind, default: []].append(view)
    }

    func trimViewportTextViewPool() {
        var remainingCapacity = maximumViewportReusableTextViews
        let retentionOrder: [MarkdownViewportReuseKind] = [
            .paragraph,
            .heading,
            .inlineParagraph,
        ]

        for kind in retentionOrder {
            guard var views = viewportReusableTextViews[kind] else { continue }
            if views.count > remainingCapacity {
                views.removeFirst(views.count - remainingCapacity)
            }
            remainingCapacity -= views.count
            if views.isEmpty {
                viewportReusableTextViews.removeValue(forKey: kind)
            } else {
                viewportReusableTextViews[kind] = views
            }
        }
    }

    func measuredViewportContentHeight(_ view: UIView, width: CGFloat, fallback: CGFloat) -> CGFloat {
        guard width > 0 else { return fallback }
        let size = view.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        guard size.height.isFinite, size.height > 0 else { return fallback }
        return ceil(size.height)
    }

    func prepareViewportContentForRemoval(_ view: UIView) {
        if let textView = view as? MarkdownTextViewTK2 {
            textView.prepareForViewportReuse()
        }
        view.subviews.forEach(prepareViewportContentForRemoval)
        view.layer.contents = nil
        view.frame.size = .zero
        view.bounds.size = .zero
    }

    func prepareViewportContentForReuse(_ view: UIView) {
        if let textView = view as? MarkdownTextViewTK2 {
            // 保留有限数量 layer 的 backing identity，后续重绘直接复用；真正离开
            // 文档或超出 idle pool 上限时才释放 layer contents。
            textView.prepareForViewportReuse(preservingLayerContents: true)
        }
        view.subviews.forEach(prepareViewportContentForReuse)
    }

    func remeasureMountedViewportSlots() {
        guard !viewportSlots.isEmpty else { return }
        let scrollView = viewportScrollView ?? viewportHostScrollView()
        let viewport = scrollView.map { $0.convert($0.bounds, to: self) }
        var heightDeltaAboveViewport: CGFloat = 0

        for slot in viewportSlots {
            guard let content = slot.contentView else { continue }
            let oldFrame = slot.convert(slot.bounds, to: self)
            if slot.reuseKind != nil,
               slot.fixedTextHeight == nil,
               let textView = markdownTextView(in: content) {
                textView.applyLayout(width: viewportContainerWidth, force: true)
                content.layoutIfNeeded()
            }
            let height = measuredViewportContentHeight(
                content,
                width: viewportContainerWidth,
                fallback: slot.cachedHeight
            )
            let delta = slot.updateCachedHeight(height)
            if let viewport, oldFrame.maxY <= viewport.minY {
                heightDeltaAboveViewport += delta
            }
        }

        guard abs(heightDeltaAboveViewport) > 0.5,
              let scrollView,
              !viewportSuppressesAnchorCorrection,
              !isEmbeddedInReusableCell() else { return }
        contentStackView.setNeedsLayout()
        contentStackView.layoutIfNeeded()
        var offset = scrollView.contentOffset
        offset.y += heightDeltaAboveViewport
        scrollView.setContentOffset(offset, animated: false)
        viewportLastReconciledBounds = nil
    }

    @discardableResult
    func applyViewportDescendantHeightDelta(
        _ delta: CGFloat,
        from descendant: UIView
    ) -> Bool {
        guard abs(delta) > 0.5 else { return false }

        var ancestor: UIView? = descendant
        while let current = ancestor, !(current is MarkdownViewportSlotView) {
            ancestor = current.superview
        }
        guard let slot = ancestor as? MarkdownViewportSlotView,
              slot.contentView != nil else { return false }

        let scrollView = viewportScrollView ?? viewportHostScrollView()
        let viewport = scrollView.map { $0.convert($0.bounds, to: self) }
        let oldFrame = slot.convert(slot.bounds, to: self)
        let appliedDelta = slot.updateCachedHeight(slot.cachedHeight + delta)
        contentStackView.setNeedsLayout()
        invalidateIntrinsicHeightCache()
        invalidateIntrinsicContentSize()
        viewportLastReconciledBounds = nil
        contentStackView.layoutIfNeeded()

        if let scrollView,
           let viewport,
           oldFrame.maxY <= viewport.minY,
           !viewportSuppressesAnchorCorrection,
           !isEmbeddedInReusableCell() {
            scrollView.setNeedsLayout()
            scrollView.layoutIfNeeded()
            var offset = scrollView.contentOffset
            offset.y += appliedDelta
            scrollView.setContentOffset(offset, animated: false)
        }
        scheduleHeightChangeNotification(force: true)
        return true
    }

    func scrollToViewportAnchorIfNeeded(
        _ view: UIView,
        in scrollView: UIScrollView,
        targetY: CGFloat
    ) {
        guard view is MarkdownViewportSlotView else {
            scrollView.setContentOffset(CGPoint(x: 0, y: targetY), animated: true)
            return
        }

        // 动画期间允许继续物化内容，但暂缓非动画 offset 补偿，避免中途取消跳转；
        // 动画完成后再按目标槽位的最终几何做一次精确校正。
        viewportAnchorAnimationGeneration += 1
        let generation = viewportAnchorAnimationGeneration
        viewportSuppressesAnchorCorrection = true

        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]
        ) {
            scrollView.contentOffset = CGPoint(x: 0, y: targetY)
        } completion: { [weak self, weak scrollView, weak view] finished in
            guard let self,
                  let scrollView,
                  let view,
                  generation == self.viewportAnchorAnimationGeneration else { return }

            self.viewportSuppressesAnchorCorrection = false
            guard finished, !scrollView.isDragging, !scrollView.isTracking else { return }

            self.viewportLastReconciledBounds = nil
            self.reconcileViewportWindow()
            self.contentStackView.layoutIfNeeded()

            let correctedFrame = view.convert(view.bounds, to: scrollView)
            let correctedMaxY = max(
                0,
                scrollView.contentSize.height
                    - scrollView.bounds.height
                    + scrollView.contentInset.bottom
            )
            let correctedY = min(max(0, correctedFrame.origin.y - 12), correctedMaxY)
            scrollView.setContentOffset(CGPoint(x: 0, y: correctedY), animated: false)
        }
    }

    func relayoutViewportSlotsForWidthChange(to width: CGFloat) {
        guard !viewportSlots.isEmpty, width > 0 else { return }
        viewportContainerWidth = width
        viewportLastReconciledBounds = nil
        viewportLatexRenderResultCache.removeAll(keepingCapacity: true)
        viewportTableLayoutCache.removeAll(keepingCapacity: true)

        for slot in viewportSlots {
            slot.invalidateMeasuredContentHeight()
            slot.preparedBlock = prepareViewportBlock(
                for: slot.element,
                containerWidth: width
            )
            slot.fixedTextHeight = fixedViewportTextHeight(
                for: slot.element,
                containerWidth: width,
                precalculatedTextHeight: nil
            )
            let estimatedHeight = estimatedViewportSlotHeight(
                for: slot.element,
                containerWidth: width,
                precalculatedTextHeight: slot.fixedTextHeight,
                preparedBlock: slot.preparedBlock
            )
            guard let content = slot.contentView else {
                slot.updateCachedHeight(estimatedHeight)
                continue
            }

            if slot.reuseKind != nil {
                _ = configureViewportTextView(content, for: slot)
                let height: CGFloat
                if slot.fixedTextHeight != nil {
                    height = estimatedHeight
                } else {
                    height = measuredViewportContentHeight(
                        content,
                        width: width,
                        fallback: estimatedHeight
                    )
                }
                slot.updateCachedHeight(height)
            } else {
                captureViewportInteractionState(from: slot)
                if let removed = slot.uninstall() {
                    prepareViewportContentForRemoval(removed)
                }
                slot.updateCachedHeight(estimatedHeight)
                mountViewportSlot(slot)
            }
        }

        invalidateIntrinsicHeightCache()
        invalidateIntrinsicContentSize()
        scheduleViewportReconcile()
    }

    func estimatedViewportSlotHeight(
        for element: MarkdownRenderElement,
        containerWidth: CGFloat,
        precalculatedTextHeight: CGFloat?,
        preparedBlock: MarkdownViewportPreparedBlock? = nil,
        suppressTopSpacing: Bool = false,
        suppressBottomSpacing: Bool = false
    ) -> CGFloat {
        switch element {
        case .heading(_, let attributedText):
            let textHeight = precalculatedTextHeight ?? measuredStaticTextHeight(
                attributedText,
                containerWidth: containerWidth
            )
            return ceil(
                textHeight
                    + (suppressTopSpacing ? 0 : configuration.headingTopSpacing)
                    + (suppressBottomSpacing ? 0 : configuration.headingBottomSpacing)
            )
        case .attributedText(let attributedText):
            let isInlineSegment = attributedText.length > 0
                && attributedText.attribute(
                    inlineSegmentAttributeKey,
                    at: 0,
                    effectiveRange: nil
                ) != nil
            let textHeight = precalculatedTextHeight ?? measuredStaticTextHeight(
                attributedText,
                containerWidth: containerWidth
            )
            return ceil(
                textHeight
                    + (suppressTopSpacing || isInlineSegment ? 0 : configuration.paragraphTopSpacing)
                    + (suppressBottomSpacing || isInlineSegment ? 0 : configuration.paragraphBottomSpacing)
            )
        case .latex(let latex):
            let result: LatexRenderResult
            if case .latex(let prepared) = preparedBlock {
                result = prepared
            } else {
                result = viewportLatexRenderResult(
                    latex: latex,
                    containerWidth: containerWidth
                )
            }
            return ceil(
                result.displaySize.height
                    + (suppressTopSpacing ? 0 : 8)
                    + (suppressBottomSpacing ? 0 : 8)
            )
        case .table(let data):
            let result: MarkdownTableLayoutResult
            if case .table(let prepared) = preparedBlock {
                result = prepared
            } else {
                result = viewportTableLayout(
                    data: data,
                    containerWidth: containerWidth
                )
            }
            return ceil(result.totalSize.height + 1)
        case .codeBlock(let language, let code):
            if let language,
               MarkdownCustomExtensionManager.shared.codeBlockRenderer(for: language) != nil {
                return estimateElementHeight(element, containerWidth: containerWidth)
            }
            let metrics: CodeBlockMetrics
            if case .codeBlock(let prepared) = preparedBlock {
                metrics = prepared
            } else {
                metrics = viewportCodeBlockMetrics(for: code)
            }
            return ceil(metrics.attachmentHeight + 1)
        case .quote(let children, let level):
            let leftIndent: CGFloat = level > 1 ? 20 : 0
            let contentPadding = configuration.blockquoteContentPadding
            let horizontalPadding = leftIndent
                + configuration.blockquoteBarWidth
                + contentPadding
                + contentPadding / 1.5
            let contentWidth = max(1, containerWidth - horizontalPadding)
            let childrenHeight = children.reduce(CGFloat.zero) { total, child in
                total + estimatedViewportSlotHeight(
                    for: child,
                    containerWidth: contentWidth,
                    precalculatedTextHeight: nil
                )
            }
            let interItemSpacing = configuration.blockquoteContentSpacing
                * CGFloat(max(0, children.count - 1))
            return ceil(
                4
                    + configuration.blockquoteContentSpacing * 2
                    + childrenHeight
                    + interItemSpacing
            )
        case .list(let items, let level):
            let currentIndent = level > 1 ? configuration.listIndent : 0
            let contentMaxWidth = max(1, containerWidth - currentIndent)
            let markerWidth = items.reduce(configuration.listMarkerMinWidth) { width, item in
                let markerSize = (item.marker as NSString).size(
                    withAttributes: [.font: configuration.bodyFont]
                )
                return max(
                    width,
                    ceil(markerSize.width) + configuration.listMarkerSpacing
                )
            }
            let itemContentWidth = max(
                1,
                contentMaxWidth - markerWidth - configuration.listMarkerSpacing
            )
            let itemsHeight = items.reduce(CGFloat.zero) { total, item in
                let visibleChildren = visibleListChildren(in: item)
                let contentHeight = visibleChildren.enumerated().reduce(CGFloat.zero) {
                    subtotal, pair in
                    subtotal + estimatedViewportSlotHeight(
                        for: pair.element,
                        containerWidth: itemContentWidth,
                        precalculatedTextHeight: nil,
                        suppressTopSpacing: pair.offset == 0,
                        suppressBottomSpacing: true
                    )
                }
                return total + max(configuration.bodyFont.lineHeight, contentHeight)
            }
            let interItemSpacing = configuration.listItemSpacing
                * CGFloat(max(0, items.count - 1))
            return ceil(
                resolvedListTopPadding()
                    + itemsHeight
                    + interItemSpacing
                    + resolvedListBottomPadding()
            )
        case .image:
            return configuration.imagePlaceholderHeight
                + (suppressTopSpacing ? 0 : 8)
                + (suppressBottomSpacing ? 0 : 8)
        default:
            return estimateElementHeight(element, containerWidth: containerWidth)
        }
    }

    func fixedViewportTextHeight(
        for element: MarkdownRenderElement,
        containerWidth: CGFloat,
        precalculatedTextHeight: CGFloat?
    ) -> CGFloat? {
        let text: NSAttributedString
        switch element {
        case .heading(_, let attributedText) where attributedText.length > 0:
            text = attributedText
        case .attributedText(let attributedText) where attributedText.length > 0:
            text = attributedText
        default:
            return nil
        }

        guard !text.containsAttachments(in: NSRange(location: 0, length: text.length)) else {
            return nil
        }
        if let precalculatedTextHeight, precalculatedTextHeight > 0 {
            return precalculatedTextHeight
        }
        return measuredStaticTextHeight(text, containerWidth: containerWidth)
    }

    func viewportReuseKind(for element: MarkdownRenderElement) -> MarkdownViewportReuseKind? {
        switch element {
        case .heading:
            return .heading
        case .attributedText(let text) where text.length > 0:
            let isInline = text.attribute(
                inlineSegmentAttributeKey,
                at: 0,
                effectiveRange: nil
            ) != nil
            return isInline ? .inlineParagraph : .paragraph
        default:
            return nil
        }
    }

    func measuredStaticTextHeight(
        _ attributedText: NSAttributedString,
        containerWidth: CGFloat
    ) -> CGFloat {
        let normalized = normalizedAttributedTextForRendering(attributedText)
        let size = normalized.boundingRect(
            with: CGSize(width: containerWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).size
        // 与 MarkdownTextViewTK2.applyLayout 的像素取整和 1pt safety buffer 一致。
        return ceil(size.height + 1)
    }

    func teardownViewportWindow() {
        viewportWindowGeneration += 1
        viewportReconcileScheduled = false
        viewportScrollObservation?.invalidate()
        viewportScrollObservation = nil
        viewportScrollView = nil
        viewportLastReconciledBounds = nil
        viewportAnchorAnimationGeneration += 1
        viewportSuppressesAnchorCorrection = false

        for slot in viewportSlots {
            if let content = slot.uninstall() {
                prepareViewportContentForRemoval(content)
            }
        }
        for content in viewportReusableTextViews.values.joined() {
            prepareViewportContentForRemoval(content)
        }
        viewportReusableTextViews.removeAll(keepingCapacity: false)
        viewportSlots.removeAll(keepingCapacity: false)
        viewportParsedFormulaCache.removeAll(keepingCapacity: false)
        viewportLatexRenderResultCache.removeAll(keepingCapacity: false)
        viewportTableLayoutCache.removeAll(keepingCapacity: false)
        viewportCodeBlockMetricsCache.removeAll(keepingCapacity: false)
        viewportContainerWidth = 0
        viewportElements.removeAll(keepingCapacity: false)
    }
}
