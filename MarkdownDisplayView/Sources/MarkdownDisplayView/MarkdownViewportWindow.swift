//
//  MarkdownViewportWindow.swift
//  MarkdownDisplayView
//
//  Keeps lightweight document geometry resident while mounting expensive
//  text drawing views only near the enclosing scroll view's viewport.
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
final class MarkdownViewportSlotView: UIView {
    let elementIndex: Int
    let element: MarkdownRenderElement
    let reuseKind: MarkdownViewportReuseKind?
    var fixedTextHeight: CGFloat?

    private(set) var contentView: UIView?
    private(set) var cachedHeight: CGFloat
    private var heightConstraint: NSLayoutConstraint!

    init(
        elementIndex: Int,
        element: MarkdownRenderElement,
        estimatedHeight: CGFloat,
        fixedTextHeight: CGFloat?,
        reuseKind: MarkdownViewportReuseKind? = nil
    ) {
        self.elementIndex = elementIndex
        self.element = element
        self.fixedTextHeight = fixedTextHeight
        self.reuseKind = reuseKind
        self.cachedHeight = max(1, estimatedHeight)
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
}

@available(iOS 15.0, *)
extension MarkdownViewTextKit {
    func shouldUseStaticViewportWindow(for elements: [MarkdownRenderElement]) -> Bool {
        guard !isStreaming,
              !isRealStreamingMode,
              elements.count > 5,
              !isEmbeddedInReusableCell(),
              findParentScrollView() != nil else {
            return false
        }
        return elements.contains(where: isViewportVirtualizableElement)
    }

    func isViewportVirtualizableElement(_ element: MarkdownRenderElement) -> Bool {
        switch element {
        case .attributedText(let text):
            return text.length > 0
        case .heading:
            return true
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
        let reusableAtomicViews = reusableViewportAtomicViews(for: elements)
        teardownViewportWindow()
        contentStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        headingViews.removeAll(keepingCapacity: true)
        tocSectionView = nil

        viewportContainerWidth = containerWidth
        viewportWindowGeneration += 1

        let viewportHeight = max(
            UIScreen.main.bounds.height,
            findParentScrollView()?.bounds.height ?? 0
        )
        // 首屏只预热当前屏 + 下一屏。后续内容由固定视图池循环承载，避免
        // 一开始就为 3 屏正文分配 CALayer backing store。
        let initialMaterializedHeight = viewportHeight * 2
        var estimatedDocumentY: CGFloat = 0

        for (index, element) in elements.enumerated() {
            let precalculatedHeight = precalculatedTextHeights?[safe: index] ?? nil
            let fixedTextHeight = fixedViewportTextHeight(
                for: element,
                containerWidth: containerWidth,
                precalculatedTextHeight: precalculatedHeight
            )
            let estimatedHeight = estimatedViewportSlotHeight(
                for: element,
                containerWidth: containerWidth,
                precalculatedTextHeight: fixedTextHeight ?? precalculatedHeight
            )
            if isViewportVirtualizableElement(element) {
                let slot = MarkdownViewportSlotView(
                    elementIndex: index,
                    element: element,
                    estimatedHeight: estimatedHeight,
                    fixedTextHeight: fixedTextHeight,
                    reuseKind: viewportReuseKind(for: element)
                )
                viewportSlots.append(slot)
                contentStackView.addArrangedSubview(slot)

                if case .heading(let id, _) = element {
                    headingViews[id] = slot
                    if id == tocSectionId { tocSectionView = slot }
                }

                if estimatedDocumentY <= initialMaterializedHeight {
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
        scheduleViewportReconcile()

        if perfStartTime > 0 {
            let firstFrameTime = (CFAbsoluteTimeGetCurrent() - perfStartTime) * 1000
            let renderTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            mdLog("[Viewport] first frame: \(String(format: "%.1f", firstFrameTime))ms, render: \(String(format: "%.1f", renderTime))ms, slots=\(viewportSlots.count)")
        }
    }

    func leaveViewportWindowForLegacyRendering() {
        guard !viewportSlots.isEmpty else { return }
        teardownViewportWindow()
        contentStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        oldElements.removeAll(keepingCapacity: false)
        headingViews.removeAll(keepingCapacity: true)
        tocSectionView = nil
    }

    /// 非虚拟原子块保持原有 UIView identity，避免 Details 展开状态、表格横向位置等丢失。
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

        let scrollView = findParentScrollView()
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

            if abs(heightDeltaAboveViewport) > 0.5, !viewportSuppressesAnchorCorrection {
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
            view = createView(
                for: slot.element,
                containerWidth: viewportContainerWidth,
                precalculatedHeight: slot.fixedTextHeight
            )
        }
        let measuredHeight: CGFloat
        if slot.fixedTextHeight != nil {
            // 纯文本槽位与 TextView 使用同一份 fixedTextHeight，挂载不会改变
            // 文档几何；避免滚动时为每个 wrapper 再跑一遍 Auto Layout fitting。
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
    }

    func recycleViewportSlot(_ slot: MarkdownViewportSlotView) {
        guard let content = slot.uninstall() else { return }
        prepareViewportContentForReuse(content)
        guard let kind = slot.reuseKind,
              markdownTextView(in: content) != nil else { return }
        content.isHidden = true
        enqueueViewportTextView(content, for: kind)
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
        let scrollView = viewportScrollView ?? findParentScrollView()
        let viewport = scrollView.map { $0.convert($0.bounds, to: self) }
        var heightDeltaAboveViewport: CGFloat = 0

        for slot in viewportSlots {
            guard let content = slot.contentView else { continue }
            let oldFrame = slot.convert(slot.bounds, to: self)
            if slot.fixedTextHeight == nil,
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
              !viewportSuppressesAnchorCorrection else { return }
        contentStackView.setNeedsLayout()
        contentStackView.layoutIfNeeded()
        var offset = scrollView.contentOffset
        offset.y += heightDeltaAboveViewport
        scrollView.setContentOffset(offset, animated: false)
        viewportLastReconciledBounds = nil
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

        for slot in viewportSlots {
            slot.fixedTextHeight = fixedViewportTextHeight(
                for: slot.element,
                containerWidth: width,
                precalculatedTextHeight: nil
            )
            guard let content = slot.contentView else {
                slot.updateCachedHeight(
                    estimatedViewportSlotHeight(
                        for: slot.element,
                        containerWidth: width,
                        precalculatedTextHeight: slot.fixedTextHeight
                    )
                )
                continue
            }

            _ = configureViewportTextView(content, for: slot)
            let height: CGFloat
            if slot.fixedTextHeight != nil {
                height = estimatedViewportSlotHeight(
                    for: slot.element,
                    containerWidth: width,
                    precalculatedTextHeight: slot.fixedTextHeight
                )
            } else {
                height = measuredViewportContentHeight(
                    content,
                    width: width,
                    fallback: slot.cachedHeight
                )
            }
            slot.updateCachedHeight(height)
        }

        invalidateIntrinsicHeightCache()
        invalidateIntrinsicContentSize()
        scheduleViewportReconcile()
    }

    func estimatedViewportSlotHeight(
        for element: MarkdownRenderElement,
        containerWidth: CGFloat,
        precalculatedTextHeight: CGFloat?
    ) -> CGFloat {
        switch element {
        case .heading(_, let attributedText):
            let textHeight = precalculatedTextHeight ?? measuredStaticTextHeight(
                attributedText,
                containerWidth: containerWidth
            )
            return ceil(
                textHeight
                    + configuration.headingTopSpacing
                    + configuration.headingBottomSpacing
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
                    + (isInlineSegment ? 0 : configuration.paragraphTopSpacing)
                    + (isInlineSegment ? 0 : configuration.paragraphBottomSpacing)
            )
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
        viewportContainerWidth = 0
        viewportElements.removeAll(keepingCapacity: false)
    }
}
