import Testing
import UIKit
@testable import MarkdownDisplayView

private func renderedText(
    _ markdown: String,
    style: MarkdownSoftBreakStyle,
    containerWidth: CGFloat = 320
) -> NSAttributedString {
    var configuration = MarkdownConfiguration.default
    configuration.softBreakStyle = style

    let renderer = MarkdownRenderer(configuration: configuration, containerWidth: containerWidth)
    let result = renderer.render(markdown)

    let text = NSMutableAttributedString()
    for element in result.elements {
        if case .attributedText(let part) = element {
            text.append(part)
        }
    }
    return text
}

private let softBreakSample = """
ご覧いただけます。
ワンポイントアドバイス：
"""

@available(iOS 15.0, *)
@MainActor
@Test func softBreakAsSpaceKeepsCommonMarkBehaviour() {
    let text = renderedText(softBreakSample, style: .space).string

    #expect(text.hasPrefix("ご覧いただけます。 ワンポイントアドバイス："))
    #expect(!text.contains("\u{2028}"))
}

@available(iOS 15.0, *)
@MainActor
@Test func softBreakAsLineBreakSplitsLineWithoutSplittingParagraph() {
    let text = renderedText(softBreakSample, style: .lineBreak).string

    #expect(text.hasPrefix("ご覧いただけます。\u{2028}ワンポイントアドバイス："))
    // 段落内不得出现 \n，否则 TextKit 会在断点处补 paragraphSpacing
    #expect(text.dropLast().firstIndex(of: "\n") == nil)
}

@available(iOS 15.0, *)
@MainActor
@Test func softBreakAsParagraphBreakEmitsNewline() {
    let text = renderedText(softBreakSample, style: .paragraphBreak).string

    #expect(text.hasPrefix("ご覧いただけます。\nワンポイントアドバイス："))
}

@available(iOS 15.0, *)
@MainActor
@Test func latinSoftBreakStillJoinsWithSpaceInDefaultStyle() {
    // 源码按列宽硬折行的长文：合并后不能把单词粘在一起
    let text = renderedText("the author wrapped\nat eighty columns", style: .space).string

    #expect(text.hasPrefix("the author wrapped at eighty columns"))
}

@available(iOS 15.0, *)
@MainActor
@Test func hardLineBreakStaysNewlineInEveryStyle() {
    let markdown = "first line  \nsecond line"

    for style in [MarkdownSoftBreakStyle.space, .lineBreak, .paragraphBreak] {
        let text = renderedText(markdown, style: style).string
        #expect(text.hasPrefix("first line\nsecond line"), "hard break must survive \(style)")
    }
}

@available(iOS 15.0, *)
@MainActor
@Test func codeBlockIsUnaffectedBySoftBreakStyle() {
    let markdown = """
    ```swift
    let a = 1
    let b = 2
    ```
    """

    var configuration = MarkdownConfiguration.default
    configuration.softBreakStyle = .lineBreak
    let renderer = MarkdownRenderer(configuration: configuration, containerWidth: 320)

    guard case .codeBlock(_, let code)? = renderer.render(markdown).elements.first else {
        Issue.record("A fenced block must stay a code block")
        return
    }
    #expect(code.string.contains("let a = 1\nlet b = 2"))
    #expect(!code.string.contains("\u{2028}"))
}

@available(iOS 15.0, *)
@MainActor
@Test func lineBreakStyleMeasuresTallerThanSpaceStyle() {
    // 必须宽到 `.space` 合并后仍是一行，否则两种模式都折成两行，测不出差异
    let width: CGFloat = 600
    let options: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
    let bounds = CGSize(width: width, height: .greatestFiniteMagnitude)

    let spaced = renderedText(softBreakSample, style: .space, containerWidth: width)
        .boundingRect(with: bounds, options: options, context: nil).height
    let broken = renderedText(softBreakSample, style: .lineBreak, containerWidth: width)
        .boundingRect(with: bounds, options: options, context: nil).height

    // 同一段文字，软换行后多占一行
    #expect(broken > spaced)
}
