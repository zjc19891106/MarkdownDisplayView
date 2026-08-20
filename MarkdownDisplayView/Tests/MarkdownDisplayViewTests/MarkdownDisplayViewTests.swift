import Testing
import UIKit
@testable import MarkdownDisplayView

@Test func listWrapperPaddingDefaultsToZero() async throws {
    let configuration = MarkdownConfiguration.default

    #expect(configuration.listTopPadding == 0)
    #expect(configuration.listBottomPadding == 0)
}

@Test func blockAppearanceDefaultsPreserveExistingCornerRadii() async throws {
    let configuration = MarkdownConfiguration.default

    #expect(configuration.codeBlockAppearance.cornerRadius == 8)
    #expect(configuration.blockquoteAppearance.cornerRadius == 4)
    #expect(configuration.tableAppearance.cornerRadius == 0)
    #expect(configuration.imageAppearance.cornerRadius == 8)
    #expect(configuration.latexAppearance.cornerRadius == 8)
    #expect(configuration.detailsAppearance.cornerRadius == 6)

    #expect(configuration.codeBlockAppearance.borderWidth == 0)
    #expect(configuration.blockquoteAppearance.borderWidth == 0)
    #expect(configuration.tableAppearance.borderWidth == 0)
    #expect(configuration.imageAppearance.borderWidth == 0)
    #expect(configuration.latexAppearance.borderWidth == 0)
    #expect(configuration.detailsAppearance.borderWidth == 0)
}

@Test func latexTextColorHasAdaptiveDefaults() async throws {
    #expect(MarkdownConfiguration.default.latexTextColor.isEqual(UIColor.label))
    #expect(MarkdownConfiguration.dark.latexTextColor.isEqual(UIColor.white))
}

@available(iOS 15.0, *)
@MainActor
@Test func resetStartsANewMarkdownSnapshotLifecycle() async throws {
    func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("Timed out waiting for the Markdown snapshot to render")
    }

    let view = MarkdownViewTextKit(
        frame: CGRect(x: 0, y: 0, width: 320, height: 640)
    )
    view.enableTypewriterEffect = false

    view.markdown = "# First snapshot\n\nFirst body."
    try await waitUntil {
        view.tableOfContents.map(\.title) == ["First snapshot"]
    }

    view.resetForReuse()
    view.markdown = "# Second snapshot\n\nSecond body."
    try await waitUntil {
        view.tableOfContents.map(\.title) == ["Second snapshot"]
    }

    #expect(view.markdown == "# Second snapshot\n\nSecond body.")
    #expect(view.tableOfContents.map(\.title) == ["Second snapshot"])
    #expect(view.contentStackView.arrangedSubviews.isEmpty == false)
}

@MainActor
@Test func customBlockAppearanceAppliesWithoutChangingViewConstraints() async throws {
    var configuration = MarkdownConfiguration.default
    let borderColor = UIColor(red: 0.22, green: 0.18, blue: 0.72, alpha: 1)
    configuration.codeBlockAppearance = MarkdownBlockAppearance(
        cornerRadius: 14,
        borderWidth: 2,
        borderColor: borderColor
    )
    configuration.blockquoteAppearance = MarkdownBlockAppearance(
        cornerRadius: 10,
        borderWidth: 1,
        borderColor: borderColor
    )

    let markdownView = MarkdownViewTextKit()
    markdownView.configuration = configuration

    let codeBlock = markdownView.createCodeBlockView(
        with: NSAttributedString(string: "let value = 1"),
        width: 320
    )
    #expect(codeBlock.layer.cornerRadius == 14)
    #expect(codeBlock.layer.borderWidth == 2)
    #expect(UIColor(cgColor: try #require(codeBlock.layer.borderColor)).isEqual(borderColor))

    let quote = markdownView.createQuoteView(children: [], width: 320)
    let quoteContainer = try #require(quote.subviews.first)
    #expect(quoteContainer.layer.cornerRadius == 10)
    #expect(quoteContainer.layer.borderWidth == 1)
    #expect(UIColor(cgColor: try #require(quoteContainer.layer.borderColor)).isEqual(borderColor))

    let widthConstraint = codeBlock.constraints.first {
        $0.firstAttribute == .width && $0.relation == .equal
    }
    #expect(widthConstraint?.constant == 320)
}

@available(iOS 15.0, *)
@MainActor
@Test func estimatedBlockWidthsYieldToTheHostLayout() throws {
    let markdownView = MarkdownViewTextKit()
    let estimatedWidth: CGFloat = 277.667

    let list = markdownView.createListView(
        items: [
            ListNodeItem(
                marker: "•",
                children: [.attributedText(NSAttributedString(string: "item"))]
            )
        ],
        width: estimatedWidth,
        level: 1
    )
    let quote = markdownView.createQuoteView(children: [], width: estimatedWidth)
    let thematicBreak = markdownView.createThematicBreakView(width: estimatedWidth)

    let listWidth = try #require(list.constraints.first {
        $0.identifier == MarkdownViewTextKit.listWrapperWidthConstraintIdentifier
    })
    let quoteWidth = try #require(quote.constraints.first {
        $0.firstItem === quote && $0.firstAttribute == .width && $0.relation == .equal
    })
    let thematicBreakWidth = try #require(thematicBreak.constraints.first {
        $0.firstItem === thematicBreak && $0.firstAttribute == .width && $0.relation == .equal
    })

    for constraint in [listWidth, quoteWidth, thematicBreakWidth] {
        #expect(constraint.constant == estimatedWidth)
        #expect(constraint.priority == UILayoutPriority(999))
    }

    // 模拟 Cell 最终宽度与预排版快照有亚像素差异。宿主的 required 宽度应当胜出，
    // 而不是让 UIKit 打断一条 required 快照约束后再做第二次布局。
    // 差值需大于 1 个三倍屏像素，避免测试值本身被 UIKit 像素对齐回估算宽度。
    let hostWidth: CGFloat = 277.25
    for block in [list, quote, thematicBreak] {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: hostWidth, height: 300))
        block.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(block)
        NSLayoutConstraint.activate([
            block.topAnchor.constraint(equalTo: host.topAnchor),
            block.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            block.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])
        host.layoutIfNeeded()

        let hostDelta = abs(block.bounds.width - host.bounds.width)
        let snapshotDelta = abs(block.bounds.width - estimatedWidth)
        #expect(hostDelta <= (1 / UIScreen.main.scale) + 0.001)
        #expect(hostDelta < snapshotDelta)
        #expect(block.hasAmbiguousLayout == false)
    }
}

@available(iOS 15.0, *)
@Test func imageViewNormalizesImageURLsBeforeLoading() async throws {
    let httpURL = try #require(ImageView.normalizedImageURL(from: "http://example.com/photo.png"))
    let bareURL = try #require(ImageView.normalizedImageURL(from: "example.com/photo"))
    let casedExtensionURL = try #require(ImageView.normalizedImageURL(from: "https://example.com/PHOTO.PNG"))

    #expect(httpURL.absoluteString == "https://example.com/photo.png")
    #expect(bareURL.absoluteString == "https://example.com/photo")
    #expect(casedExtensionURL.absoluteString == "https://example.com/PHOTO.PNG")
}

@available(iOS 15.0, *)
@Test func singleHeadingMarkdownStreamsParagraphByParagraph() async throws {
    let buffer = MarkdownStreamBuffer(containerWidth: 320, minModuleLength: 10)
    let markdown = """
    # Title

    Paragraph one is long enough to stream.

    Paragraph two is also long enough.

    """

    let result = buffer.append(markdown)

    #expect(result.completeModules.count == 2)
    #expect(result.completeModules[0] == "# Title\n\nParagraph one is long enough to stream.")
    #expect(result.completeModules[1] == "Paragraph two is also long enough.")
    #expect(result.pendingText.isEmpty)
    #expect(result.hasPendingStructure == false)
}

@available(iOS 15.0, *)
@Test func doubleNewlinesInsideCodeBlocksDoNotCreateBoundaries() async throws {
    let buffer = MarkdownStreamBuffer(containerWidth: 320, minModuleLength: 10)
    let markdown = """
    # Title

    ```swift
    let first = 1

    let second = 2
    ```

    Closing paragraph is outside the code block.

    """

    let result = buffer.append(markdown)

    #expect(result.completeModules.count == 2)
    #expect(result.completeModules[0].contains("let second = 2"))
    #expect(result.completeModules[0].contains("```swift"))
    #expect(result.completeModules[1] == "Closing paragraph is outside the code block.")
    #expect(result.pendingText.isEmpty)
}

@available(iOS 15.0, *)
@Test func rendererPreparesReusableContentWithEstimatedHeight() async throws {
    let renderer = MarkdownRenderer(configuration: .default, containerWidth: 320)
    let prepared = renderer.prepare("""
    # Title

    This is a paragraph with **strong** text.

    - First
    - Second
    """)

    #expect(prepared.elements.isEmpty == false)
    #expect(prepared.estimatedTotalHeight > 0)
    #expect(prepared.preparedWidth == 320)
}

@available(iOS 15.0, *)
@MainActor
@Test func repeatedLayoutAtSameWidthDoesNotRequestAnotherHeightMeasurement() async throws {
    let view = MarkdownViewTextKit()

    #expect(view.consumeLayoutWidthChange(320))
    #expect(view.consumeLayoutWidthChange(320) == false)
    #expect(view.consumeLayoutWidthChange(320.2) == false)
    #expect(view.consumeLayoutWidthChange(321))
}

@available(iOS 15.0, *)
@MainActor
@Test func repeatedTextLayoutAtSameSizeDoesNotInvalidateDisplayAgain() async throws {
    let textView = MarkdownTextViewTK2()

    #expect(textView.consumeDisplayBoundsChange(CGSize(width: 320, height: 44)))
    #expect(textView.consumeDisplayBoundsChange(CGSize(width: 320, height: 44)) == false)
    #expect(textView.consumeDisplayBoundsChange(CGSize(width: 320.2, height: 44.2)) == false)
    #expect(textView.consumeDisplayBoundsChange(CGSize(width: 320, height: 60)))
}

@available(iOS 15.0, *)
@MainActor
@Test func atomicQuoteDoesNotEnqueueEachNestedTextView() async throws {
    let markdownView = MarkdownViewTextKit()
    let quote = markdownView.createQuoteView(children: [], width: 320)
    let nestedText = MarkdownTextViewTK2()
    nestedText.attributedText = NSAttributedString(string: "quoted text")
    quote.addSubview(nestedText)

    #expect(quote.accessibilityIdentifier == "MarkdownAtomicQuote")

    let engine = TypewriterEngine()
    engine.enqueue(view: quote)

    #expect(engine.outstandingTaskCount == 1)
    #expect(nestedText.displayedAttributedString.string == "quoted text")
}

@available(iOS 15.0, *)
@MainActor
@Test func appendTypewriterPreparesAtomicQuoteTextAtItsFinalHeight() async throws {
    func firstTextView(in view: UIView) -> MarkdownTextViewTK2? {
        if let textView = view as? MarkdownTextViewTK2 {
            return textView
        }
        for subview in view.subviews {
            if let textView = firstTextView(in: subview) {
                return textView
            }
        }
        return nil
    }

    func makeQuote(using markdownView: MarkdownViewTextKit) -> UIView {
        let text = NSAttributedString(
            string: "Quoted guidance must remain visible when the whole block fades in.",
            attributes: [
                .font: UIFont.systemFont(ofSize: 16),
                .foregroundColor: UIColor.label,
            ]
        )
        return markdownView.createQuoteView(
            children: [.attributedText(text)],
            width: 220
        )
    }

    var configuration = MarkdownConfiguration.default
    configuration.typewriterTextMode = .append

    let markdownView = MarkdownViewTextKit()
    markdownView.configuration = configuration
    markdownView.enableTypewriterEffect = true

    let rootQuote = makeQuote(using: markdownView)
    let rootTextView = try #require(firstTextView(in: rootQuote))
    let rootEngine = TypewriterEngine()
    rootEngine.enqueue(view: rootQuote)

    #expect(rootEngine.outstandingTaskCount == 1)
    #expect(rootTextView.intrinsicContentSize.height > 1)
    #expect(rootTextView.displayedAttributedString.string.contains("Quoted guidance"))

    // A quote nested inside a list/container reaches TypewriterEngine with
    // isRoot=false, so cover the atomic .block path as well as the root .show path.
    let nestedQuote = makeQuote(using: markdownView)
    let nestedTextView = try #require(firstTextView(in: nestedQuote))
    let parent = UIView()
    parent.addSubview(nestedQuote)
    let nestedEngine = TypewriterEngine()
    nestedEngine.enqueue(view: parent)

    #expect(nestedEngine.outstandingTaskCount == 2)
    #expect(nestedTextView.intrinsicContentSize.height > 1)
    #expect(nestedTextView.displayedAttributedString.string.contains("Quoted guidance"))
}

@available(iOS 15.0, *)
@MainActor
@Test func realStreamingAppendTypewriterKeepsAtomicQuoteTextVisible() async throws {
    func firstTextView(in view: UIView) -> MarkdownTextViewTK2? {
        if let textView = view as? MarkdownTextViewTK2 {
            return textView
        }
        for subview in view.subviews {
            if let textView = firstTextView(in: subview) {
                return textView
            }
        }
        return nil
    }

    var configuration = MarkdownConfiguration.default
    configuration.typewriterTextMode = .append

    let markdownView = MarkdownViewTextKit(
        frame: CGRect(x: 0, y: 0, width: 320, height: 640)
    )
    markdownView.configuration = configuration
    markdownView.enableTypewriterEffect = true
    markdownView.updateTypewriterSpeed(
        charsPerStep: 1_000,
        baseDuration: 0.001,
        elementGapDuration: 0
    )
    markdownView.layoutIfNeeded()
    markdownView.beginRealStreaming()

    let quoteText = "Quoted guidance remains visible after atomic playback."
    for fragment in [
        "> Quoted guidance",
        " remains visible",
        " after atomic playback.",
        "\n\n",
    ] {
        markdownView.appendStreamData(fragment)
    }

    await withCheckedContinuation { continuation in
        markdownView.endRealStreaming {
            continuation.resume()
        }
    }

    let quote = try #require(markdownView.contentStackView.arrangedSubviews.first {
        $0.accessibilityIdentifier == "MarkdownAtomicQuote"
    })
    let textView = try #require(firstTextView(in: quote))

    #expect(markdownView.typewriterEngine.isIdle)
    #expect(textView.displayedAttributedString.string.contains(quoteText))
    #expect(
        textView.intrinsicContentSize.height > 1,
        "atomic quote text must use its final height, actual=\(textView.intrinsicContentSize.height)"
    )
}

@available(iOS 15.0, *)
@MainActor
@Test func tableLayoutReusesAttributesWhileGeometryIsUnchanged() async throws {
    let layout = MarkdownTableLayout()
    layout.columnWidths = [100, 120]
    layout.rowHeights = [44, 60]

    layout.prepare()
    layout.prepare()

    #expect(layout.layoutRebuildCount == 1)
    #expect(layout.collectionViewContentSize == CGSize(width: 220, height: 104))

    layout.rowHeights = [44, 80]
    layout.prepare()
    #expect(layout.layoutRebuildCount == 2)
    #expect(layout.collectionViewContentSize == CGSize(width: 220, height: 124))
}

@available(iOS 15.0, *)
@MainActor
@Test func smartStreamingPreservesOrderWithoutDuplicateViews() async throws {
    let view = MarkdownViewTextKit(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    view.enableTypewriterEffect = false
    view.beginRealStreaming()

    let blocks = [
        "# 目录\n\n1. [第一章](#第一章)\n2. [第二章](#第二章)\n",
        "## 第一章\n\n第一章正文。\n",
        "## 第二章\n\n第二章正文。\n",
    ]
    for block in blocks {
        view.appendStreamData(block)
    }

    await withCheckedContinuation { continuation in
        view.endRealStreaming {
            continuation.resume()
        }
    }

    let headingTitles = view.tableOfContents.map(\.title)
    let headingIDs = view.tableOfContents.map(\.id)
    let viewTags = view.contentStackView.arrangedSubviews.map(\.tag)
    #expect(headingTitles.contains("目录"))
    #expect(headingTitles.contains("第一章"))
    #expect(headingTitles.contains("第二章"))
    #expect(Set(headingIDs).count == headingIDs.count)
    #expect(view.headingViews.count == headingIDs.count)
    #expect(view.tocSectionId == headingIDs.first)
    #expect(view.tocSectionView === view.headingViews[headingIDs[0]])
    #expect(view.oldElements.count == view.contentStackView.arrangedSubviews.count)
    #expect(Set(viewTags).count == viewTags.count)
    for block in blocks {
        #expect(view.markdown.contains(block.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    view.beginRealStreaming()
    view.appendStreamData("# 新目录\n\n新内容。\n")
    await withCheckedContinuation { continuation in
        view.endRealStreaming { continuation.resume() }
    }
    #expect(view.tableOfContents.map(\.title) == ["新目录"])
    #expect(view.imageAttachments.isEmpty)
}

@available(iOS 15.0, *)
@MainActor
@Test func realStreamingAcceptsCharacterSizedNetworkFragmentsAndDrainsFootnotes() async throws {
    let view = MarkdownViewTextKit(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    view.enableTypewriterEffect = false
    view.beginRealStreaming()

    let markdown = """
    # Character Stream

    Content arriving one character at a time.[^1]

    [^1]: Footnote content
    """
    for character in markdown {
        view.appendStreamData(String(character))
    }

    await withCheckedContinuation { continuation in
        view.endRealStreaming { continuation.resume() }
    }

    #expect(view.isRealStreamingMode == false)
    #expect(view.isStreaming == false)
    #expect(view.markdown == markdown)
    #expect(view.markdown.contains("Character Stream"))
    #expect(view.markdown.contains("Footnote content"))
    #expect(view.tableOfContents.map(\.title) == ["Character Stream"])
    #expect(view.contentStackView.arrangedSubviews.last?.accessibilityIdentifier == "FootnoteContainer")
}

@available(iOS 15.0, *)
@MainActor
@Test func appendTypewriterSeparatesCharacterRevealFromHeightChanges() async throws {
    // 软折行（word wrap）不产生 "\n"，也不会正好落在第 N 个字符上。若按字符数节流测高，
    // 折行后的新行会有若干帧拿不到高度，被外层 Cell 的 UIView-Encapsulated-Layout-Height
    // （required）裁掉——这就是流式输出在折行处的闪烁。
    //
    // 因此这里不断言"第几个字符才上报高度"（那是节流实现的细节，换实现就会失效），
    // 而是断言两条不变式：
    //   1. 任何时刻报出的高度，都不得小于当前可见前缀真正需要的高度；
    //   2. 上报仍然是被节流的——必须存在"揭示了字符但高度没变"的帧，
    //      否则说明退化成每帧都通知宿主，会把 performBatchUpdates 打爆。
    let width: CGFloat = 120  // 窄容器，保证这段文本会多次软折行
    let full = NSAttributedString(
        string: String(repeating: "a", count: 40),
        attributes: [.font: UIFont.systemFont(ofSize: 16)]
    )

    // 用独立的参考视图算出各前缀真正需要的高度，作为不依赖被测对象的 ground truth
    let requiredHeights: [CGFloat] = (1...full.length).map { length in
        let probe = MarkdownTextViewTK2()
        probe.attributedText = full.attributedSubstring(from: NSRange(location: 0, length: length))
        probe.applyLayout(width: width, force: true)
        return probe.intrinsicContentSize.height
    }
    // 前提校验：这段文本在该宽度下确实折了行，否则本用例什么也没测到
    #expect(requiredHeights.last! > requiredHeights.first!)

    let textView = MarkdownTextViewTK2()
    textView.typewriterTextMode = .append
    textView.attributedText = full
    textView.textContainer.size = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
    textView.setFixedHeight(1)
    textView.prepareForTypewriter()

    var laggingSteps = 0
    var growthSteps = 0
    var stableSteps = 0

    for length in 1...full.length {
        let result = textView.revealCharacter(upto: length)
        #expect(result.didReveal)

        if textView.intrinsicContentSize.height < requiredHeights[length - 1] {
            laggingSteps += 1
        }

        if result.didChangeHeight {
            #expect(result.heightDelta > 0)
            growthSteps += 1
        } else {
            stableSteps += 1
        }
    }

    #expect(laggingSteps == 0)
    #expect(growthSteps > 0)
    #expect(stableSteps > 0)

    let completedHeight = textView.intrinsicContentSize.height
    textView.applyLayout(width: 1_000, force: true)
    #expect(textView.intrinsicContentSize.height == completedHeight)

    textView.finishAppendTypewriterPlayback()
    textView.applyLayout(width: 1_000, force: true)
    #expect(textView.intrinsicContentSize.height < completedHeight)
}

@available(iOS 15.0, *)
@MainActor
@Test func appendTypewriterDoesNotExposePrecalculatedFinalHeightBeforeTyping() async throws {
    let textView = MarkdownTextViewTK2()
    textView.typewriterTextMode = .append
    textView.attributedText = NSAttributedString(
        string: String(repeating: "precalculated content ", count: 8),
        attributes: [.font: UIFont.systemFont(ofSize: 16)]
    )
    textView.textContainer.size = CGSize(width: 220, height: CGFloat.greatestFiniteMagnitude)
    textView.setFixedHeight(180)

    textView.prepareForTypewriter()

    #expect(textView.intrinsicContentSize.height == 1)
}

@available(iOS 15.0, *)
@MainActor
@Test func stoppingTypewriterReleasesHeightFloorsForCurrentAndQueuedText() async throws {
    func makeTextView(_ text: String) -> MarkdownTextViewTK2 {
        let textView = MarkdownTextViewTK2()
        textView.typewriterTextMode = .append
        textView.attributedText = NSAttributedString(
            string: text,
            attributes: [.font: UIFont.systemFont(ofSize: 16)]
        )
        textView.textContainer.size = CGSize(width: 80, height: CGFloat.greatestFiniteMagnitude)
        textView.setFixedHeight(160)
        return textView
    }

    let currentText = makeTextView(String(repeating: "current text ", count: 12))
    let queuedText = makeTextView(String(repeating: "queued text ", count: 12))
    let engine = TypewriterEngine()
    engine.enqueue(view: currentText)
    engine.enqueue(view: queuedText)
    engine.start()
    engine.stop()

    currentText.applyLayout(width: 1_000, force: true)
    queuedText.applyLayout(width: 1_000, force: true)

    #expect(currentText.intrinsicContentSize.height < 160)
    #expect(queuedText.intrinsicContentSize.height < 160)
    #expect(engine.isIdle)
    #expect(engine.isViewInQueue(currentText) == false)
    #expect(engine.isViewInQueue(queuedText) == false)
}

@available(iOS 15.0, *)
@MainActor
@Test func revealTypewriterRestoresOriginalAttributesRunByRun() async throws {
    let url = try #require(URL(string: "https://example.com"))
    let text = NSMutableAttributedString(
        string: "plain",
        attributes: [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: UIColor.label]
    )
    text.append(NSAttributedString(
        string: "link",
        attributes: [
            .font: UIFont.systemFont(ofSize: 16),
            .foregroundColor: UIColor.systemBlue,
            .link: url
        ]
    ))

    let textView = MarkdownTextViewTK2()
    textView.typewriterTextMode = .reveal
    textView.attributedText = text
    textView.textContainer.size = CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
    textView.prepareForTypewriter()

    // prepare 后整篇透明占位，且 .link 被移除（否则系统会强制渲染链接色，文字藏不住）
    let prepared = textView.displayedAttributedString
    #expect(prepared.length == text.length)
    for index in 0..<prepared.length {
        #expect(prepared.attribute(.foregroundColor, at: index, effectiveRange: nil) as? UIColor == UIColor.clear)
        #expect(prepared.attribute(.link, at: index, effectiveRange: nil) == nil)
    }

    let heightAfterPrepare = textView.intrinsicContentSize.height

    // 揭示范围跨越两个属性 run，两个 run 的原始属性都要按 run 还原
    let revealed = textView.revealCharacter(upto: 7)
    #expect(revealed.didReveal)
    #expect(revealed.didChangeHeight == false)
    #expect(textView.intrinsicContentSize.height == heightAfterPrepare)

    let afterReveal = textView.displayedAttributedString
    #expect(afterReveal.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor == UIColor.label)
    #expect(afterReveal.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? UIColor == UIColor.systemBlue)
    #expect(afterReveal.attribute(.link, at: 6, effectiveRange: nil) as? URL == url)

    // 未揭示部分仍是透明占位
    #expect(afterReveal.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? UIColor == UIColor.clear)
    #expect(afterReveal.attribute(.link, at: 8, effectiveRange: nil) == nil)

    #expect(textView.revealCharacter(upto: 7).didReveal == false)
    #expect(textView.revealCharacter(upto: text.length + 1).didReveal == false)
}

@available(iOS 15.0, *)
@MainActor
@Test func streamingHeightAccumulatorAddsRootsAndTextDeltasWithoutDoubleCounting() async throws {
    var accumulator = StreamingHeightAccumulator()
    accumulator.reset(verticalMargins: 12)

    let firstRoot = UIView()
    let secondRoot = UIView()

    #expect(accumulator.rootBecameVisible(firstRoot, measuredHeight: 20, spacing: 8) == 32)
    #expect(accumulator.rootBecameVisible(firstRoot, measuredHeight: 20, spacing: 8) == 32)
    #expect(accumulator.rootBecameVisible(secondRoot, measuredHeight: 30, spacing: 8) == 70)
    #expect(accumulator.textHeightChanged(delta: 18) == 88)
    #expect(accumulator.textHeightChanged(delta: 0.1) == nil)
    #expect(accumulator.totalHeight == 88)
    accumulator.synchronize(totalHeight: 120)
    #expect(accumulator.textHeightChanged(delta: 10) == 130)
}

@available(iOS 15.0, *)
@MainActor
@Test func smartStreamIncrementalHeightMatchesFinalStackFitting() async throws {
    let view = MarkdownViewTextKit(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    view.enableTypewriterEffect = true
    view.updateTypewriterSpeed(charsPerStep: 1_000, baseDuration: 0.001, elementGapDuration: 0)
    view.layoutIfNeeded()
    view.beginRealStreaming()
    view.appendStreamData("""
    # Height Test

    A paragraph that wraps onto more than one line when rendered in a narrow container.

    - first list item
    - second list item

    > atomic quote content

    """)

    await withCheckedContinuation { continuation in
        view.endRealStreaming { continuation.resume() }
    }

    view.layoutIfNeeded()
    view.contentStackView.layoutIfNeeded()
    let finalFittingHeight = view.contentStackView.systemLayoutSizeFitting(
        CGSize(width: 320, height: UIView.layoutFittingCompressedSize.height),
        withHorizontalFittingPriority: .required,
        verticalFittingPriority: .fittingSizeLevel
    ).height
    #expect(
        abs(view.realStreamHeightAccumulator.totalHeight - finalFittingHeight) < 2,
        "cached=\(view.realStreamHeightAccumulator.totalHeight), final=\(finalFittingHeight)"
    )
}

@available(iOS 15.0, *)
@MainActor
@Test func detailsExpansionSynchronouslyCommitsItsStructuralHeight() async throws {
    func firstSubview<T: UIView>(of type: T.Type, in root: UIView, where predicate: (T) -> Bool) -> T? {
        if let candidate = root as? T, predicate(candidate) { return candidate }
        for subview in root.subviews {
            if let match = firstSubview(of: type, in: subview, where: predicate) {
                return match
            }
        }
        return nil
    }

    func layout(_ scrollView: ScrollableMarkdownViewTextKit) {
        scrollView.setNeedsLayout()
        scrollView.layoutIfNeeded()
        scrollView.markdownView.setNeedsLayout()
        scrollView.markdownView.layoutIfNeeded()
        scrollView.markdownView.contentStackView.layoutIfNeeded()
    }

    func structuralHeight(of markdownView: MarkdownViewTextKit, width: CGFloat) -> CGFloat {
        markdownView.contentStackView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
    }

    let markdown = """
    ## 目录

    1. [第一项](#第一项)
    2. [第二项](#第二项)
    3. [第三项](#第三项)
    4. [第四项](#第四项)
    5. [第五项](#第五项)
    6. [第六项](#第六项)
    7. [第七项](#第七项)
    8. [第八项](#第八项)
    9. [第九项](#第九项)
    10. [第十项](#第十项)
    11. [第十一项](#第十一项)
    12. [第十二项](#第十二项)
    13. [第十三项](#第十三项)
    14. [第十四项](#第十四项)
    15. [CocoaPods（折叠）](#CocoaPods)

    <details>
    <summary>展开结构高度测试</summary>

    ```ruby
    source 'https://github.com/CocoaPods/Specs.git'
    platform :ios, '15.0'

    target 'YourTarget' do
      use_frameworks!
      pod 'MarkdownDisplayView'
    end

    post_install do |installer|
      installer.pods_project.targets.each do |target|
        target.build_configurations.each do |config|
          config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
        end
      end
    end
    ```

    </details>
    """

    let viewportWidth: CGFloat = 390
    let contentWidth = viewportWidth - 32
    let scrollView = ScrollableMarkdownViewTextKit(
        frame: CGRect(x: 0, y: 0, width: viewportWidth, height: 700)
    )
    layout(scrollView)
    let prepared = MarkdownRenderer(
        configuration: scrollView.configuration,
        containerWidth: contentWidth
    ).prepare(markdown)
    scrollView.markdownView.setPreparedContent(prepared)
    layout(scrollView)

    let listWrapper = try #require(scrollView.markdownView.contentStackView.arrangedSubviews.first {
        $0.constraints.contains {
            $0.identifier == MarkdownViewTextKit.listWrapperWidthConstraintIdentifier
        }
    })
    let listStack = try #require(listWrapper.subviews.first as? UIStackView)
    #expect(listStack.arrangedSubviews.count == 15)
    let initialWrapperHeight = listWrapper.bounds.height
    let initialFirstItemHeight = listStack.arrangedSubviews[0].bounds.height
    let initialGap = listStack.arrangedSubviews[1].frame.minY
        - listStack.arrangedSubviews[0].frame.maxY

    // Read intrinsicContentSize first so this test covers the stale-cache path used by
    // ScrollableMarkdownViewTextKit after the initial synchronous preview layout.
    let initiallyCollapsedHeight = scrollView.markdownView.intrinsicContentSize.height
    #expect(
        abs(initiallyCollapsedHeight - structuralHeight(
            of: scrollView.markdownView,
            width: contentWidth
        )) <= 2
    )

    let detailsButton = try #require(firstSubview(of: UIButton.self, in: scrollView.markdownView) {
        $0.configuration?.title?.contains("结构高度测试") == true
    })
    detailsButton.sendActions(for: .touchUpInside)

    // createDetailsView currently defers cacheHeight/onHeightChange by 0.05s. The structural
    // tree is already expanded in this call stack, so intrinsicContentSize must not expose
    // the previous collapsed cache for an intervening frame.
    let expandedStructuralHeight = structuralHeight(
        of: scrollView.markdownView,
        width: contentWidth
    )
    let immediateExpandedIntrinsicHeight = scrollView.markdownView.intrinsicContentSize.height
    #expect(expandedStructuralHeight > initiallyCollapsedHeight + 200)
    #expect(
        abs(immediateExpandedIntrinsicHeight - expandedStructuralHeight) <= 2,
        "expanded structure and intrinsic cache diverged before the deferred callback: collapsed=\(initiallyCollapsedHeight), structural=\(expandedStructuralHeight), intrinsic=\(immediateExpandedIntrinsicHeight)"
    )

    try await Task.sleep(nanoseconds: 300_000_000)
    detailsButton.sendActions(for: .touchUpInside)
    try await Task.sleep(nanoseconds: 300_000_000)

    let collapsedStructuralHeight = structuralHeight(
        of: scrollView.markdownView,
        width: contentWidth
    )
    let collapsedIntrinsicHeight = scrollView.markdownView.intrinsicContentSize.height
    #expect(abs(collapsedIntrinsicHeight - initiallyCollapsedHeight) <= 2)
    #expect(abs(collapsedIntrinsicHeight - collapsedStructuralHeight) <= 2)
    #expect(abs(listWrapper.bounds.height - initialWrapperHeight) <= 1)
    #expect(abs(listStack.arrangedSubviews[0].bounds.height - initialFirstItemHeight) <= 1)
    let collapsedGap = listStack.arrangedSubviews[1].frame.minY
        - listStack.arrangedSubviews[0].frame.maxY
    #expect(abs(collapsedGap - initialGap) <= 1)
}

@available(iOS 15.0, *)
@MainActor
@Test func detailsIncrementalUpdateReusesOuterContainerAndPreservesExpandedState() throws {
    func firstSubview<T: UIView>(of type: T.Type, in root: UIView) -> T? {
        if let match = root as? T { return match }
        for subview in root.subviews {
            if let match = firstSubview(of: type, in: subview) { return match }
        }
        return nil
    }

    let width: CGFloat = 320
    let oldBody = NSAttributedString(
        string: "Original details body",
        attributes: [.font: UIFont.systemFont(ofSize: 16)]
    )
    let newBody = NSAttributedString(
        string: "Updated details body remains expanded",
        attributes: [.font: UIFont.systemFont(ofSize: 16)]
    )
    let oldElement = MarkdownRenderElement.details(
        summary: "Original summary",
        children: [.attributedText(oldBody)]
    )
    let newElement = MarkdownRenderElement.details(
        summary: "Updated summary",
        children: [.attributedText(newBody)]
    )

    let markdownView = MarkdownViewTextKit(
        frame: CGRect(x: 0, y: 0, width: width, height: 600)
    )
    markdownView.updateViews(
        newElements: [oldElement],
        footnotes: [],
        containerWidth: width
    )
    markdownView.layoutIfNeeded()
    markdownView.contentStackView.layoutIfNeeded()

    let originalOuterContainer = try #require(
        markdownView.contentStackView.arrangedSubviews.first
    )
    #expect(originalOuterContainer.accessibilityIdentifier?.hasPrefix("MarkdownAtomicDetails") == true)
    let originalContainerStack = try #require(
        originalOuterContainer.subviews.first(where: { $0 is UIStackView }) as? UIStackView
    )
    let summaryButton = try #require(originalContainerStack.arrangedSubviews.first as? UIButton)
    let originalContentWrapper = try #require(originalContainerStack.arrangedSubviews[safe: 1])
    #expect(originalContentWrapper.isHidden)

    summaryButton.sendActions(for: .touchUpInside)
    #expect(originalContentWrapper.isHidden == false)
    // The production interaction lock intentionally suppresses concurrent stream patches.
    // Clear it here so this test exercises the subsequent incremental reconciliation itself.
    markdownView.isUserInteractingWithDetails = false

    markdownView.updateViews(
        newElements: [newElement],
        footnotes: [],
        containerWidth: width
    )
    markdownView.layoutIfNeeded()

    let updatedOuterContainer = try #require(
        markdownView.contentStackView.arrangedSubviews.first
    )
    #expect(updatedOuterContainer === originalOuterContainer)
    let updatedContainerStack = try #require(
        updatedOuterContainer.subviews.first(where: { $0 is UIStackView }) as? UIStackView
    )
    let updatedContentWrapper = try #require(updatedContainerStack.arrangedSubviews[safe: 1])
    #expect(updatedContentWrapper === originalContentWrapper)
    #expect(updatedContentWrapper.isHidden == false)

    let updatedButton = try #require(updatedContainerStack.arrangedSubviews.first as? UIButton)
    let updatedTitle = updatedButton.configuration?.title ?? updatedButton.currentTitle ?? ""
    #expect(updatedTitle.contains("Updated summary"))
    #expect(updatedTitle.hasPrefix("▼ "))

    let updatedTextView = try #require(firstSubview(of: MarkdownTextViewTK2.self, in: updatedContentWrapper))
    #expect(updatedTextView.displayedAttributedString.string.contains("Updated details body"))
}

@available(iOS 15.0, *)
@MainActor
@Test func collapsingDetailsRestoresSyncPreviewHeightAndDirectoryListGeometry() async throws {
    func firstSubview<T: UIView>(of type: T.Type, in root: UIView, where predicate: (T) -> Bool) -> T? {
        if let candidate = root as? T, predicate(candidate) {
            return candidate
        }
        for subview in root.subviews {
            if let match = firstSubview(of: type, in: subview, where: predicate) {
                return match
            }
        }
        return nil
    }

    func settleLayout(_ scrollView: ScrollableMarkdownViewTextKit) {
        scrollView.setNeedsLayout()
        scrollView.layoutIfNeeded()
        scrollView.markdownView.setNeedsLayout()
        scrollView.markdownView.layoutIfNeeded()
        scrollView.markdownView.contentStackView.setNeedsLayout()
        scrollView.markdownView.contentStackView.layoutIfNeeded()
    }

    struct DirectoryGeometry {
        let rootHeight: CGFloat
        let structuralHeight: CGFloat
        let scrollContentHeight: CGFloat
        let wrapperHeight: CGFloat
        let itemHeights: [CGFloat]
        let interItemGap: CGFloat
    }

    func geometry(
        in scrollView: ScrollableMarkdownViewTextKit,
        listWrapper: UIView,
        listStack: UIStackView,
        settle: Bool = false
    ) -> DirectoryGeometry {
        if settle {
            settleLayout(scrollView)
        }
        let items = listStack.arrangedSubviews
        let gap = items.count >= 2 ? items[1].frame.minY - items[0].frame.maxY : .greatestFiniteMagnitude
        return DirectoryGeometry(
            rootHeight: scrollView.markdownView.intrinsicContentSize.height,
            structuralHeight: scrollView.markdownView.contentStackView.systemLayoutSizeFitting(
                CGSize(
                    width: scrollView.markdownView.bounds.width,
                    height: UIView.layoutFittingCompressedSize.height
                ),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height,
            scrollContentHeight: scrollView.contentSize.height,
            wrapperHeight: listWrapper.bounds.height,
            itemHeights: items.map(\.bounds.height),
            interItemGap: gap
        )
    }

    // 直接使用 Example 屏幕的完整 fixture，避免删减掉与分批渲染、复杂附件或
    // 后续内容高度有关的触发条件。这里只解析测试仓库中的 Swift 多行字面量；
    // 不依赖运行时 bundle 资源，也不修改 Example target。
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let exampleSource = try String(
        contentsOf: repositoryRoot
            .appendingPathComponent("Example/ExampleForMarkdown/ExampleForMarkdown/MarkdownExampleViewController.swift"),
        encoding: .utf8
    )
    let literalStart = try #require(exampleSource.range(of: "let sampleMarkdown = \"\"\"\n"))
    let literalTail = exampleSource[literalStart.upperBound...]
    let literalEnd = try #require(literalTail.range(of: "\n    \"\"\"", options: .backwards))
    let markdown = literalTail[..<literalEnd.lowerBound]
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { line in
            line.hasPrefix("    ") ? String(line.dropFirst(4)) : String(line)
        }
        .joined(separator: "\n")
        .replacingOccurrences(of: "\\\\", with: "\\")
        .replacingOccurrences(of: "\\\"", with: "\"")
        // Images are unrelated to Details geometry and would otherwise make this local
        // layout regression depend on DNS/network timing from the Example's demo URLs.
        .replacingOccurrences(
            of: "!\\[[^\\]]*\\]\\([^)]*\\)",
            with: "[image omitted by layout test]",
            options: .regularExpression
        )

    let viewportWidth: CGFloat = 390
    let scrollView = ScrollableMarkdownViewTextKit(
        frame: CGRect(x: 0, y: 0, width: viewportWidth, height: 700)
    )
    let host = UIViewController()
    host.view.frame = scrollView.bounds
    host.view.addSubview(scrollView)
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        scrollView.topAnchor.constraint(equalTo: host.view.topAnchor),
        scrollView.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
        scrollView.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
        scrollView.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),
    ])
    let window = UIWindow(frame: scrollView.bounds)
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    settleLayout(scrollView)

    // 走 Sync Markdown Preview 使用的真实 markdown setter，并等待后台解析和主线程
    // updateViews 都完成。不能换成直接 createDetailsView，否则测不到根高度缓存与
    // ScrollableMarkdownViewTextKit contentSize 的联动。
    scrollView.markdown = markdown
    for _ in 0..<400 {
        settleLayout(scrollView)
        let hasDetails = firstSubview(of: UIButton.self, in: scrollView.markdownView) {
            $0.configuration?.title?.contains("Podfile 配置代码") == true
        } != nil
        let hasFullDirectory = scrollView.markdownView.contentStackView.arrangedSubviews.contains { root in
            guard root.constraints.contains(where: {
                $0.identifier == MarkdownViewTextKit.listWrapperWidthConstraintIdentifier
            }), let stack = root.subviews.first as? UIStackView else {
                return false
            }
            return stack.arrangedSubviews.count == 15
        }
        let finishedAppendingOffscreenContent = scrollView.markdownView.headingViews.count
            == scrollView.markdownView.tableOfContents.count
            && scrollView.markdownView.tableOfContents.contains { $0.title == "总结" }
            && scrollView.markdownView.placeholderView == nil
        if hasDetails && hasFullDirectory && finishedAppendingOffscreenContent { break }
        try await Task.sleep(nanoseconds: 20_000_000)
    }

    let listWrapper = try #require(scrollView.markdownView.contentStackView.arrangedSubviews.first {
        $0.constraints.contains {
            $0.identifier == MarkdownViewTextKit.listWrapperWidthConstraintIdentifier
        }
    })
    let listStack = try #require(listWrapper.subviews.first as? UIStackView)
    #expect(listStack.arrangedSubviews.count == 15)

    let detailsButton = try #require(firstSubview(of: UIButton.self, in: scrollView.markdownView) {
        $0.configuration?.title?.contains("Podfile 配置代码") == true
    })

    let initiallyCollapsed = geometry(
        in: scrollView,
        listWrapper: listWrapper,
        listStack: listStack,
        settle: true
    )

    let detailsFrame = detailsButton.convert(detailsButton.bounds, to: scrollView)
    scrollView.setContentOffset(
        CGPoint(x: 0, y: max(0, detailsFrame.minY - 80)),
        animated: false
    )
    detailsButton.sendActions(for: .touchUpInside)
    try await Task.sleep(nanoseconds: 400_000_000)
    let expanded = geometry(
        in: scrollView,
        listWrapper: listWrapper,
        listStack: listStack
    )
    #expect(expanded.rootHeight > initiallyCollapsed.rootHeight + 300)
    #expect(expanded.scrollContentHeight > initiallyCollapsed.scrollContentHeight + 300)

    detailsButton.sendActions(for: .touchUpInside)
    // Collapse 动画为 0.2 秒；额外等待一轮布局/高度回调完成。
    try await Task.sleep(nanoseconds: 400_000_000)
    scrollView.backToTableOfContentsSection()
    try await Task.sleep(nanoseconds: 400_000_000)
    let collapsedAgain = geometry(
        in: scrollView,
        listWrapper: listWrapper,
        listStack: listStack
    )
    // The complete Example fixture contains asynchronous image attachments, so its initial
    // root height can legitimately change while the Details interaction is in progress.
    // Compare the collapsed public height with the authoritative current structure instead
    // of treating the earlier image-loading snapshot as immutable.
    #expect(collapsedAgain.rootHeight < expanded.rootHeight - 300)
    #expect(
        abs(collapsedAgain.rootHeight - collapsedAgain.structuralHeight) <= 2,
        "collapsed intrinsic height retained non-structural space: structural=\(collapsedAgain.structuralHeight), intrinsic=\(collapsedAgain.rootHeight)"
    )
    #expect(
        abs(collapsedAgain.scrollContentHeight - (collapsedAgain.rootHeight + 32)) <= 2,
        "scroll contentSize did not follow collapsed intrinsic height: root=\(collapsedAgain.rootHeight), content=\(collapsedAgain.scrollContentHeight)"
    )
    #expect(
        abs(collapsedAgain.wrapperHeight - initiallyCollapsed.wrapperHeight) <= 1,
        "directory wrapper retained expanded space: initial=\(initiallyCollapsed.wrapperHeight), collapsed=\(collapsedAgain.wrapperHeight)"
    )
    #expect(collapsedAgain.itemHeights.count == initiallyCollapsed.itemHeights.count)
    for (initial, collapsed) in zip(initiallyCollapsed.itemHeights, collapsedAgain.itemHeights) {
        #expect(
            abs(collapsed - initial) <= 1,
            "directory item was vertically stretched: initial=\(initial), collapsed=\(collapsed)"
        )
    }
    #expect(
        abs(collapsedAgain.interItemGap - initiallyCollapsed.interItemGap) <= 1,
        "directory item gap was stretched: initial=\(initiallyCollapsed.interItemGap), collapsed=\(collapsedAgain.interItemGap)"
    )
}
