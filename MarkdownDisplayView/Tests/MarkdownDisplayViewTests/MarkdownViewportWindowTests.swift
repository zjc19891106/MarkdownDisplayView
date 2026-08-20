import Testing
import UIKit
@testable import MarkdownDisplayView

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
@Test func viewportOptimizationDoesNotReplaceStreamingOrReusableCellRendering() {
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
