import Testing
import UIKit
@testable import MarkdownDisplayView

private final class FixedIntrinsicHeightView: UIView {
    private let fixedHeight: CGFloat

    init(height: CGFloat) {
        fixedHeight = height
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: fixedHeight)
    }
}

@available(iOS 15.0, *)
@MainActor
@Test func viewportSlotKeepsDocumentGeometryAfterContentIsRemoved() throws {
    let element = MarkdownRenderElement.attributedText(NSAttributedString(string: "正文"))
    let slot = MarkdownViewportSlotView(
        elementIndex: 0,
        element: element,
        estimatedHeight: 40,
        fixedTextHeight: nil
    )
    let content = UIView()

    slot.install(content, measuredHeight: 96)
    #expect(slot.cachedHeight == 96)
    #expect(slot.contentView === content)

    let removed = try #require(slot.uninstall())
    #expect(removed === content)
    #expect(slot.contentView == nil)
    #expect(slot.cachedHeight == 96)
    #expect(slot.constraints.contains { constraint in
        constraint.firstItem === slot
            && constraint.firstAttribute == .height
            && constraint.constant == 96
    })
}

@available(iOS 15.0, *)
@MainActor
@Test func longStaticDocumentOnlyMountsTextNearTheViewport() {
    let viewportSize = CGSize(width: 390, height: 600)
    let host = UIViewController()
    host.view.frame = CGRect(origin: .zero, size: viewportSize)

    let scrollView = ScrollableMarkdownViewTextKit(frame: host.view.bounds)
    host.view.addSubview(scrollView)
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        scrollView.topAnchor.constraint(equalTo: host.view.topAnchor),
        scrollView.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
        scrollView.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
        scrollView.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),
    ])

    let window = UIWindow(frame: host.view.bounds)
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    host.view.layoutIfNeeded()
    let paragraph = NSAttributedString(
        string: Array(repeating: "这是一段用于验证视口渲染的正文。", count: 18).joined(),
        attributes: [.font: UIFont.systemFont(ofSize: 17)]
    )
    let elements = (0..<80).map { index in
        MarkdownRenderElement.attributedText(
            NSMutableAttributedString(string: "\(index) ").appending(paragraph)
        )
    }

    let markdownView = scrollView.markdownView
    markdownView.updateViews(
        newElements: elements,
        footnotes: [],
        containerWidth: viewportSize.width - 32
    )
    host.view.layoutIfNeeded()
    markdownView.reconcileViewportWindow()

    let initiallyMounted = markdownView.viewportSlots.filter { $0.contentView != nil }.count
    #expect(markdownView.viewportSlots.count == elements.count)
    #expect(initiallyMounted > 0)
    #expect(initiallyMounted < elements.count)
    #expect(markdownView.viewportSlots.first?.contentView != nil)

    let bottomOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)
    scrollView.setContentOffset(CGPoint(x: 0, y: bottomOffset), animated: false)
    host.view.layoutIfNeeded()
    markdownView.reconcileViewportWindow()

    #expect(markdownView.viewportSlots.first?.contentView == nil)
    #expect(markdownView.viewportSlots.last?.contentView != nil)
    #expect(markdownView.viewportSlots.filter { $0.contentView != nil }.count < elements.count)
    #expect(markdownView.viewportSlots.allSatisfy { $0.fixedTextHeight != nil })
}

@available(iOS 15.0, *)
@MainActor
@Test func viewportReusesTextViewsWhenScrollingBackAcrossTheDocument() {
    let viewportSize = CGSize(width: 390, height: 600)
    let host = UIViewController()
    host.view.frame = CGRect(origin: .zero, size: viewportSize)
    let scrollView = ScrollableMarkdownViewTextKit(frame: host.view.bounds)
    host.view.addSubview(scrollView)

    let window = UIWindow(frame: host.view.bounds)
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    let paragraph = NSAttributedString(
        string: Array(repeating: "复用同一批 TextKit 视图，避免滚动累计 backing store。", count: 12).joined(),
        attributes: [.font: UIFont.systemFont(ofSize: 17)]
    )
    let elements = (0..<80).map { index in
        MarkdownRenderElement.attributedText(
            NSMutableAttributedString(string: "\(index) ").appending(paragraph)
        )
    }

    host.view.layoutIfNeeded()
    let markdownView = scrollView.markdownView
    markdownView.updateViews(
        newElements: elements,
        footnotes: [],
        containerWidth: viewportSize.width - 32
    )
    host.view.layoutIfNeeded()
    markdownView.reconcileViewportWindow()

    let initialViews = Set(
        markdownView.viewportSlots.compactMap(\.contentView).map(ObjectIdentifier.init)
    )
    #expect(!initialViews.isEmpty)

    scrollView.setContentOffset(
        CGPoint(x: 0, y: max(0, scrollView.contentSize.height - scrollView.bounds.height)),
        animated: false
    )
    markdownView.viewportLastReconciledBounds = nil
    markdownView.reconcileViewportWindow()
    let bottomViews = Set(
        markdownView.viewportSlots.compactMap(\.contentView).map(ObjectIdentifier.init)
    )
    let lastContent = markdownView.viewportSlots.last?.contentView
    let lastText = lastContent.flatMap(markdownView.markdownTextView(in:))

    #expect(!bottomViews.isDisjoint(with: initialViews))
    #expect(lastText?.displayedAttributedString.string.hasPrefix("79 ") == true)

    scrollView.setContentOffset(.zero, animated: false)
    markdownView.viewportLastReconciledBounds = nil
    markdownView.reconcileViewportWindow()
    let returnedViews = Set(
        markdownView.viewportSlots.compactMap(\.contentView).map(ObjectIdentifier.init)
    )
    let firstContent = markdownView.viewportSlots.first?.contentView
    let firstText = firstContent.flatMap(markdownView.markdownTextView(in:))

    #expect(returnedViews.isSubset(of: initialViews.union(bottomViews)))
    #expect(firstText?.displayedAttributedString.string.hasPrefix("0 ") == true)
    #expect(
        markdownView.viewportReusableTextViews.values.reduce(0) { $0 + $1.count }
            <= markdownView.maximumViewportReusableTextViews
    )
}

@available(iOS 15.0, *)
@MainActor
@Test func reusableCellViewportRequiresPreparedLongContentAndExplicitOptIn() {
    let elements = (0..<8).map {
        MarkdownRenderElement.attributedText(NSAttributedString(string: "paragraph \($0)"))
    }

    let scrollView = UIScrollView()
    let markdownView = MarkdownViewTextKit()
    scrollView.addSubview(markdownView)

    markdownView.isStreaming = true
    #expect(!markdownView.shouldUseStaticViewportWindow(for: elements))

    markdownView.isStreaming = false
    let cell = UITableViewCell()
    markdownView.removeFromSuperview()
    cell.contentView.addSubview(markdownView)
    scrollView.addSubview(cell)
    #expect(!markdownView.shouldUseStaticViewportWindow(for: elements))

    markdownView.allowsStaticViewportRenderingInReusableCell = true
    #expect(!markdownView.shouldUseStaticViewportWindow(for: elements))

    markdownView.isDisplayingPreparedStaticContent = true
    markdownView.preparedStaticEstimatedHeight = 1_799
    #expect(!markdownView.shouldUseStaticViewportWindow(for: elements))

    markdownView.preparedStaticEstimatedHeight = 2_400
    #expect(markdownView.shouldUseStaticViewportWindow(for: elements))

    markdownView.isStreaming = true
    #expect(!markdownView.shouldUseStaticViewportWindow(for: elements))

    markdownView.isStreaming = false
    markdownView.resetForReuse()
    #expect(markdownView.allowsStaticViewportRenderingInReusableCell)
    #expect(!markdownView.isDisplayingPreparedStaticContent)
    #expect(!markdownView.shouldUseStaticViewportWindow(for: elements))
}

@available(iOS 15.0, *)
@MainActor
@Test func completedStreamPromotionPreservesVisibleRootsAndReleasesDistantRoots() throws {
    let viewportSize = CGSize(width: 390, height: 600)
    let documentHeight: CGFloat = 4_000
    let host = UIViewController()
    host.view.frame = CGRect(origin: .zero, size: viewportSize)

    let scrollView = UIScrollView(frame: host.view.bounds)
    scrollView.contentSize = CGSize(width: viewportSize.width, height: documentHeight)
    host.view.addSubview(scrollView)

    let markdownView = MarkdownViewTextKit(frame: CGRect(
        x: 0,
        y: 0,
        width: viewportSize.width,
        height: documentHeight
    ))
    scrollView.addSubview(markdownView)

    let elements = (0..<20).map { index in
        let body = Array(repeating: "root \(index) keeps verified stream geometry ", count: 18).joined()
        return MarkdownRenderElement.attributedText(NSAttributedString(string: body))
    }
    var originalRoots: [UIView] = []
    for index in elements.indices {
        let root = FixedIntrinsicHeightView(height: 200)
        root.translatesAutoresizingMaskIntoConstraints = false
        root.tag = 1000 + index
        markdownView.contentStackView.addArrangedSubview(root)
        originalRoots.append(root)
    }
    markdownView.realStreamHeightAccumulator.synchronize(totalHeight: documentHeight)

    let window = UIWindow(frame: host.view.bounds)
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    scrollView.contentOffset = .zero
    host.view.layoutIfNeeded()
    markdownView.layoutIfNeeded()
    markdownView.contentStackView.layoutIfNeeded()

    let visibleRoot = originalRoots[0]
    let promoted = markdownView.promoteCompletedStreamToViewportWindow(
        elements: elements,
        footnotes: [],
        containerWidth: viewportSize.width
    )

    #expect(promoted)
    #expect(markdownView.viewportSlots.count == elements.count)
    #expect(markdownView.viewportSlots[0].contentView === visibleRoot)
    #expect(markdownView.viewportSlots.last?.contentView == nil)
    #expect(markdownView.viewportSlots.allSatisfy { abs($0.cachedHeight - 200) < 0.5 })
    #expect(abs(markdownView.viewportSlots.reduce(0) { $0 + $1.cachedHeight } - documentHeight) < 0.5)
    #expect(markdownView.viewportElements == elements)
    #expect(markdownView.oldElements.isEmpty)
    #expect(markdownView.isDisplayingPreparedStaticContent)
}

@available(iOS 15.0, *)
@MainActor
@Test func viewportEstimateMatchesMaterializedParagraphHeight() {
    let markdownView = MarkdownViewTextKit()
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.paragraphSpacing = 12
    let element = MarkdownRenderElement.attributedText(
        NSAttributedString(
            string: Array(repeating: "同一段正文必须使用一致的几何估算。", count: 12).joined(),
            attributes: [
                .font: UIFont.systemFont(ofSize: 17),
                .paragraphStyle: paragraphStyle,
            ]
        )
    )
    let width: CGFloat = 358
    let estimated = markdownView.estimatedViewportSlotHeight(
        for: element,
        containerWidth: width,
        precalculatedTextHeight: nil
    )
    let materialized = markdownView.createView(for: element, containerWidth: width)
    let measured = markdownView.measuredViewportContentHeight(
        materialized,
        width: width,
        fallback: 0
    )

    #expect(abs(estimated - measured) <= 2, "estimated=\(estimated), measured=\(measured)")
}

@available(iOS 15.0, *)
@MainActor
@Test func viewportAttachmentTextKeepsDynamicTextKitMeasurement() {
    let markdownView = MarkdownViewTextKit()
    let attachment = NSTextAttachment()
    attachment.bounds = CGRect(x: 0, y: 0, width: 80, height: 64)
    let text = NSMutableAttributedString(string: "附件前 ")
    text.append(NSAttributedString(attachment: attachment))
    text.append(NSAttributedString(string: " 附件后"))

    let fixedHeight = markdownView.fixedViewportTextHeight(
        for: .attributedText(text),
        containerWidth: 358,
        precalculatedTextHeight: nil
    )

    #expect(fixedHeight == nil)
}

@available(iOS 15.0, *)
@MainActor
@Test func complexBlocksOnlyStayMaterializedNearTheViewport() throws {
    let viewportSize = CGSize(width: 390, height: 600)
    let host = UIViewController()
    host.view.frame = CGRect(origin: .zero, size: viewportSize)
    let scrollView = ScrollableMarkdownViewTextKit(frame: host.view.bounds)
    host.view.addSubview(scrollView)

    let window = UIWindow(frame: host.view.bounds)
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    let body = NSAttributedString(
        string: "复杂块内部正文",
        attributes: [.font: UIFont.systemFont(ofSize: 17)]
    )
    let table = MarkdownTableData(
        headers: [NSAttributedString(string: "列 1"), NSAttributedString(string: "列 2")],
        rows: [[NSAttributedString(string: "A"), NSAttributedString(string: "B")]]
    )
    let blockPattern: [MarkdownRenderElement] = [
        .latex("x^2 + y^2 = z^2"),
        .table(table),
        .codeBlock(
            language: nil,
            code: NSAttributedString(
                string: "let value = Array(repeating: 1, count: 100)",
                attributes: [.font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)]
            )
        ),
        .list(items: [ListNodeItem(marker: "•", children: [.attributedText(body)])], level: 1),
        .quote(children: [.attributedText(body)], level: 1),
    ]
    let elements = (0..<15).flatMap { _ in blockPattern }

    host.view.layoutIfNeeded()
    let markdownView = scrollView.markdownView
    markdownView.updateViews(
        newElements: elements,
        footnotes: [],
        containerWidth: viewportSize.width - 32
    )
    host.view.layoutIfNeeded()
    markdownView.reconcileViewportWindow()

    #expect(markdownView.viewportSlots.count == elements.count)
    #expect(markdownView.viewportSlots.allSatisfy { $0.reuseKind == nil })
    #expect(markdownView.viewportSlots.first?.contentView != nil)
    #expect(markdownView.viewportSlots.last?.contentView == nil)

    scrollView.setContentOffset(
        CGPoint(x: 0, y: max(0, scrollView.contentSize.height - scrollView.bounds.height)),
        animated: false
    )
    markdownView.viewportLastReconciledBounds = nil
    host.view.layoutIfNeeded()
    markdownView.reconcileViewportWindow()

    #expect(markdownView.viewportSlots.first?.contentView == nil)
    #expect(markdownView.viewportSlots.last?.contentView != nil)
    #expect(markdownView.viewportSlots.filter { $0.contentView != nil }.count < elements.count)
    #expect(markdownView.viewportReusableTextViews.values.reduce(0) { $0 + $1.count } == 0)
}

@available(iOS 15.0, *)
@MainActor
@Test func complexBlockRebuildRestoresHorizontalScrollPosition() throws {
    let markdownView = MarkdownViewTextKit()
    let element = MarkdownRenderElement.codeBlock(
        language: nil,
        code: NSAttributedString(string: "a very long code line")
    )
    let slot = MarkdownViewportSlotView(
        elementIndex: 0,
        element: element,
        estimatedHeight: 80,
        fixedTextHeight: nil
    )
    slot.frame = CGRect(x: 0, y: 0, width: 300, height: 80)

    func makeContent() -> (UIView, UIScrollView) {
        let content = UIView(frame: slot.bounds)
        let horizontal = UIScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 80))
        horizontal.contentSize = CGSize(width: 900, height: 80)
        content.addSubview(horizontal)
        return (content, horizontal)
    }

    let first = makeContent()
    slot.install(first.0, measuredHeight: 80)
    slot.layoutIfNeeded()
    first.1.contentOffset.x = 137
    markdownView.captureViewportInteractionState(from: slot)
    _ = try #require(slot.uninstall())

    let rebuilt = makeContent()
    slot.install(rebuilt.0, measuredHeight: 80)
    slot.layoutIfNeeded()
    markdownView.restoreViewportInteractionState(to: slot)

    #expect(abs(rebuilt.1.contentOffset.x - 137) < 0.5)
}

@available(iOS 15.0, *)
@MainActor
@Test func horizontalOffsetsUseStableSubviewPathsWhenScrollabilityChanges() throws {
    let markdownView = MarkdownViewTextKit()
    let slot = MarkdownViewportSlotView(
        elementIndex: 0,
        element: .quote(children: [], level: 1),
        estimatedHeight: 80,
        fixedTextHeight: nil
    )
    slot.frame = CGRect(x: 0, y: 0, width: 300, height: 80)

    func makeRoot(firstIsScrollable: Bool) -> (UIView, UIScrollView, UIScrollView) {
        let root = UIView(frame: slot.bounds)
        let first = UIScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 40))
        first.contentSize = CGSize(width: firstIsScrollable ? 900 : 300, height: 40)
        let second = UIScrollView(frame: CGRect(x: 0, y: 40, width: 300, height: 40))
        second.contentSize = CGSize(width: 900, height: 40)
        root.addSubview(first)
        root.addSubview(second)
        return (root, first, second)
    }

    let original = makeRoot(firstIsScrollable: true)
    slot.install(original.0, measuredHeight: 80)
    slot.layoutIfNeeded()
    original.1.contentOffset.x = 41
    original.2.contentOffset.x = 173
    markdownView.captureViewportInteractionState(from: slot)
    _ = try #require(slot.uninstall())

    let rebuilt = makeRoot(firstIsScrollable: false)
    slot.install(rebuilt.0, measuredHeight: 80)
    slot.layoutIfNeeded()
    markdownView.restoreViewportInteractionState(to: slot)

    #expect(abs(rebuilt.1.contentOffset.x) < 0.5)
    #expect(abs(rebuilt.2.contentOffset.x - 173) < 0.5)
}

@available(iOS 15.0, *)
@MainActor
@Test func recycledComplexBlockDoesNotStayRetainedByItsSlot() throws {
    let markdownView = MarkdownViewTextKit()
    let width: CGFloat = 358
    markdownView.viewportContainerWidth = width
    let element = MarkdownRenderElement.latex("x^2 + y^2")
    let prepared = try #require(markdownView.prepareViewportBlock(
        for: element,
        containerWidth: width
    ))
    let slot = MarkdownViewportSlotView(
        elementIndex: 0,
        element: element,
        estimatedHeight: 80,
        fixedTextHeight: nil,
        preparedBlock: prepared
    )
    weak var releasedContent: UIView?

    autoreleasepool {
        markdownView.mountViewportSlot(slot)
        releasedContent = slot.contentView
        markdownView.recycleViewportSlot(slot)
    }

    #expect(slot.contentView == nil)
    #expect(releasedContent == nil)
}

@available(iOS 15.0, *)
@MainActor
@Test func nestedImageLoadRemeasuresItsVirtualizedQuoteSlot() async throws {
    let viewportSize = CGSize(width: 390, height: 600)
    let host = UIViewController()
    host.view.frame = CGRect(origin: .zero, size: viewportSize)
    let scrollView = ScrollableMarkdownViewTextKit(frame: host.view.bounds)
    host.view.addSubview(scrollView)

    let window = UIWindow(frame: host.view.bounds)
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    let text = NSAttributedString(
        string: "用于开启静态视口路径的正文",
        attributes: [.font: UIFont.systemFont(ofSize: 17)]
    )
    let quote = MarkdownRenderElement.quote(
        children: [.image(source: "https://example.invalid/image.png", altText: "占位图")],
        level: 1
    )
    let elements: [MarkdownRenderElement] = [quote]
        + (0..<6).map { _ in .attributedText(text) }

    host.view.layoutIfNeeded()
    let markdownView = scrollView.markdownView
    markdownView.updateViews(
        newElements: elements,
        footnotes: [],
        containerWidth: viewportSize.width - 32
    )
    host.view.layoutIfNeeded()

    let quoteSlot = try #require(
        markdownView.viewportSlots.first { $0.elementIndex == 0 }
    )
    let quoteContent = try #require(quoteSlot.contentView)
    let imageView = try #require(firstSubview(of: ImageView.self, in: quoteContent))
    let heightConstraint = try #require(imageView.constraints.first { constraint in
        constraint.firstItem === imageView
            && constraint.firstAttribute == .height
            && constraint.relation == .equal
    })
    let widthConstraint = try #require(imageView.constraints.first { constraint in
        constraint.firstItem === imageView
            && constraint.firstAttribute == .width
            && constraint.relation == .lessThanOrEqual
    })
    let oldHeight = quoteSlot.cachedHeight
    let imageWidth = widthConstraint.constant

    _ = markdownView.applyLoadedImageSize(
        CGSize(width: imageWidth, height: 350),
        maxWidth: imageWidth,
        widthConstraint: widthConstraint,
        heightConstraint: heightConstraint
    )
    try await Task.sleep(nanoseconds: 100_000_000)
    host.view.layoutIfNeeded()

    #expect(quoteSlot.cachedHeight > oldHeight + 100)
}

@available(iOS 15.0, *)
@MainActor
@Test func preparedComplexBlockGeometryMatchesMaterializedViews() throws {
    let markdownView = MarkdownViewTextKit()
    let width: CGFloat = 358
    markdownView.viewportContainerWidth = width

    let latex = "\\frac{a+b}{c+d}"
    let latexElement = MarkdownRenderElement.latex(latex)
    let latexPrepared = try #require(markdownView.prepareViewportBlock(
        for: latexElement,
        containerWidth: width
    ))
    let latexSlot = MarkdownViewportSlotView(
        elementIndex: 0,
        element: latexElement,
        estimatedHeight: 1,
        fixedTextHeight: nil,
        preparedBlock: latexPrepared
    )
    let latexView = markdownView.createViewportContentView(for: latexSlot)
    let latexEstimate = markdownView.estimatedViewportSlotHeight(
        for: latexElement,
        containerWidth: width,
        precalculatedTextHeight: nil,
        preparedBlock: latexPrepared
    )
    let latexMeasured = markdownView.measuredViewportContentHeight(
        latexView,
        width: width,
        fallback: 0
    )

    let tableData = MarkdownTableData(
        headers: [NSAttributedString(string: "Header")],
        rows: [[NSAttributedString(string: "Cell")]]
    )
    let tableElement = MarkdownRenderElement.table(tableData)
    let tablePrepared = try #require(markdownView.prepareViewportBlock(
        for: tableElement,
        containerWidth: width
    ))
    let tableSlot = MarkdownViewportSlotView(
        elementIndex: 1,
        element: tableElement,
        estimatedHeight: 1,
        fixedTextHeight: nil,
        preparedBlock: tablePrepared
    )
    let tableView = markdownView.createViewportContentView(for: tableSlot)
    let tableEstimate = markdownView.estimatedViewportSlotHeight(
        for: tableElement,
        containerWidth: width,
        precalculatedTextHeight: nil,
        preparedBlock: tablePrepared
    )
    let tableMeasured = markdownView.measuredViewportContentHeight(
        tableView,
        width: width,
        fallback: 0
    )

    let code = NSAttributedString(
        string: "let answer = 42",
        attributes: [.font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)]
    )
    let codeElement = MarkdownRenderElement.codeBlock(language: nil, code: code)
    let codePrepared = try #require(markdownView.prepareViewportBlock(
        for: codeElement,
        containerWidth: width
    ))
    let codeSlot = MarkdownViewportSlotView(
        elementIndex: 2,
        element: codeElement,
        estimatedHeight: 1,
        fixedTextHeight: nil,
        preparedBlock: codePrepared
    )
    let codeView = markdownView.createViewportContentView(for: codeSlot)
    let codeEstimate = markdownView.estimatedViewportSlotHeight(
        for: codeElement,
        containerWidth: width,
        precalculatedTextHeight: nil,
        preparedBlock: codePrepared
    )
    let codeMeasured = markdownView.measuredViewportContentHeight(
        codeView,
        width: width,
        fallback: 0
    )

    #expect(abs(latexEstimate - latexMeasured) <= 1)
    #expect(abs(tableEstimate - tableMeasured) <= 1)
    #expect(abs(codeEstimate - codeMeasured) <= 1)
    #expect(markdownView.viewportParsedFormulaCache.count == 1)
    #expect(markdownView.viewportLatexRenderResultCache.count == 1)
}

@available(iOS 15.0, *)
@MainActor
@Test func tableLayoutUsesTheWidestMalformedRow() {
    let markdownView = MarkdownViewTextKit()
    let data = MarkdownTableData(
        headers: [NSAttributedString(string: "Only header")],
        rows: [[
            NSAttributedString(string: "A"),
            NSAttributedString(string: "B"),
            NSAttributedString(string: "C"),
        ]]
    )

    let result = MarkdownTableLayoutCalculator.calculate(
        data: data,
        config: markdownView.configuration,
        containerWidth: 358
    )

    #expect(result.columnWidths.count == 3)
}

@available(iOS 15.0, *)
@MainActor
@Test func compositeBlocksKeepIdentityWhenTheyContainInteractiveDetails() {
    let markdownView = MarkdownViewTextKit()
    let details = MarkdownRenderElement.details(
        summary: "交互状态",
        children: [.attributedText(NSAttributedString(string: "展开内容"))]
    )
    let list = MarkdownRenderElement.list(
        items: [ListNodeItem(marker: "•", children: [details])],
        level: 1
    )
    let quote = MarkdownRenderElement.quote(children: [details], level: 1)

    #expect(!markdownView.isViewportVirtualizableElement(list))
    #expect(!markdownView.isViewportVirtualizableElement(quote))
}

@available(iOS 15.0, *)
@MainActor
@Test func listsWithDynamicImagesKeepTheirMarkerHeightSemantics() {
    let markdownView = MarkdownViewTextKit()
    let list = MarkdownRenderElement.list(
        items: [ListNodeItem(
            marker: "•",
            children: [.image(source: "https://example.invalid/small.png", altText: "小图")]
        )],
        level: 1
    )

    #expect(!markdownView.isViewportVirtualizableElement(list))
}

@available(iOS 15.0, *)
@MainActor
@Test func rawHTMLEstimateMatchesItsCurrentZeroHeightRenderer() {
    let markdownView = MarkdownViewTextKit()
    let element = MarkdownRenderElement.rawHTML("<span>unsupported</span>")

    #expect(markdownView.estimateElementHeight(element, containerWidth: 358) == 0)
    #expect(markdownView.estimatedViewportSlotHeight(
        for: element,
        containerWidth: 358,
        precalculatedTextHeight: nil
    ) == 0)
}

@available(iOS 15.0, *)
@MainActor
@Test func viewportRerenderReusesUnchangedInteractiveBlocks() throws {
    let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
    let markdownView = MarkdownViewTextKit(frame: CGRect(x: 0, y: 0, width: 358, height: 600))
    scrollView.addSubview(markdownView)

    let text = NSAttributedString(
        string: "普通正文",
        attributes: [.font: UIFont.systemFont(ofSize: 17)]
    )
    let details = MarkdownRenderElement.details(
        summary: "保持展开状态",
        children: [.attributedText(text)]
    )
    let elements: [MarkdownRenderElement] = [
        .attributedText(text),
        .attributedText(text),
        .attributedText(text),
        details,
        .attributedText(text),
        .attributedText(text),
        .attributedText(text),
    ]

    markdownView.updateViews(newElements: elements, footnotes: [], containerWidth: 358)
    let originalDetailsView = try #require(markdownView.contentStackView.arrangedSubviews[safe: 3])
    let button = try #require(firstSubview(of: UIButton.self, in: originalDetailsView))
    button.sendActions(for: .touchUpInside)
    markdownView.isUserInteractingWithDetails = false

    markdownView.updateViews(newElements: elements, footnotes: [], containerWidth: 358)
    let reusedDetailsView = try #require(markdownView.contentStackView.arrangedSubviews[safe: 3])

    #expect(reusedDetailsView === originalDetailsView)
}

@available(iOS 15.0, *)
@MainActor
@Test func viewportTOCJumpLandsOnAnUnmountedHeading() async throws {
    let viewportSize = CGSize(width: 390, height: 600)
    let host = UIViewController()
    host.view.frame = CGRect(origin: .zero, size: viewportSize)
    let scrollView = ScrollableMarkdownViewTextKit(frame: host.view.bounds)
    host.view.addSubview(scrollView)

    let window = UIWindow(frame: host.view.bounds)
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    let body = NSAttributedString(
        string: Array(repeating: "用于拉开标题距离的正文。", count: 20).joined(),
        attributes: [.font: UIFont.systemFont(ofSize: 17)]
    )
    var elements: [MarkdownRenderElement] = []
    for index in 0..<30 {
        elements.append(.heading(
            id: "heading-\(index)",
            text: NSAttributedString(
                string: "标题 \(index)",
                attributes: [.font: UIFont.boldSystemFont(ofSize: 22)]
            )
        ))
        elements.append(.attributedText(body))
    }

    host.view.layoutIfNeeded()
    scrollView.markdownView.updateViews(
        newElements: elements,
        footnotes: [],
        containerWidth: viewportSize.width - 32
    )
    host.view.layoutIfNeeded()

    let targetID = "heading-20"
    let targetSlot = try #require(
        scrollView.markdownView.headingViews[targetID] as? MarkdownViewportSlotView
    )
    #expect(targetSlot.contentView == nil)

    scrollView.markdownView.scrollToTOCItem(
        MarkdownTOCItem(level: 2, title: "标题 20", id: targetID)
    )
    try await Task.sleep(nanoseconds: 400_000_000)
    host.view.layoutIfNeeded()

    let headingTop = targetSlot.convert(targetSlot.bounds, to: window).minY
    let viewportTop = scrollView.convert(scrollView.bounds, to: window).minY
    #expect(targetSlot.contentView != nil)
    #expect(abs(headingTop - viewportTop - 12) <= 4)
}

@MainActor
private func firstSubview<T: UIView>(of type: T.Type, in root: UIView) -> T? {
    if let match = root as? T { return match }
    for subview in root.subviews {
        if let match = firstSubview(of: type, in: subview) { return match }
    }
    return nil
}

private extension NSMutableAttributedString {
    @discardableResult
    func appending(_ attributedString: NSAttributedString) -> NSMutableAttributedString {
        append(attributedString)
        return self
    }
}
