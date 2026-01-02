//
//  MarkdownParser.swift
//  MarkdownDisplayKit
//
//  Created by 朱继超 on 12/17/25.
//

import UIKit
import Markdown  // 只在这里引入 swift-markdown

// MARK: - 增量解析结果
/// 增量解析返回的结果
public struct IncrementalParseResult {
    /// 安全解析到的字符位置（后续增量解析从此位置继续）
    public let safePosition: Int
    /// 新增的渲染元素
    public let newElements: [MarkdownRenderElement]
    /// 需要替换的旧元素数量（从末尾开始，用于回溯修正）
    public let replaceCount: Int
    /// 是否有未完成的结构（代码块、表格、LaTeX等未闭合）
    public let hasPendingStructure: Bool
    /// 未完成结构的类型（用于调试）
    public let pendingType: PendingStructureType?
    /// 图片附件
    public let imageAttachments: [(attachment: MarkdownImageAttachment, urlString: String)]
    /// TOC 项目
    public let tocItems: [MarkdownTOCItem]
}

/// 未完成结构类型
public enum PendingStructureType: String {
    case codeBlock = "CodeBlock"      // ``` 未闭合
    case latexBlock = "LaTeX"         // $$ 未闭合
    case table = "Table"              // 表格未结束
    case list = "List"                // 列表可能未完成
    case quote = "Quote"              // 引用块可能未完成
}

/// 内部实现类，包含所有 swift-markdown 相关逻辑
final class MarkdownParser: MarkdownParserProtocol {

    private let configuration: MarkdownConfiguration
    private let containerWidth: CGFloat

    private var listDepth = 0
    private var quoteDepth = 0  // 引用块嵌套深度
    private var orderedListCounters: [Int] = []
    private var isInBlockquote = false
    private var isInCodeBlock = false
    private var isTableHeader = false
    private var headingIndex = 0

    private var imageAttachments: [(attachment: MarkdownImageAttachment, urlString: String)] = []

    private var elements: [MarkdownRenderElement] = []
    private var currentTextBuffer = NSMutableAttributedString()

    private static var regexCache: [String: NSRegularExpression] = [:]
    private static let regexLock = NSLock()

    private var isInTable = false

    private var detectedTOCSectionId: String? = nil

    init(configuration: MarkdownConfiguration, containerWidth: CGFloat) {
        self.configuration = configuration
        self.containerWidth = containerWidth
    }

    // MARK: - 增量解析核心方法

    /// 增量解析 Markdown 文本
    /// - Parameters:
    ///   - fullText: 完整的 Markdown 文本（包含新追加的内容）
    ///   - lastSafePosition: 上次安全解析到的位置
    ///   - previousElementCount: 之前已解析的元素数量
    ///   - contextWindowSize: 回溯的上下文窗口大小（字符数）
    /// - Returns: 增量解析结果
    func parseIncremental(
        fullText: String,
        lastSafePosition: Int,
        previousElementCount: Int,
        contextWindowSize: Int = 200
    ) -> IncrementalParseResult {
        let nsText = fullText as NSString
        let fullLength = nsText.length

        // 1. 检测当前文本是否有未完成的结构
        let pendingInfo = detectPendingStructure(in: fullText)

        // 2. 查找安全断点（从末尾向前搜索）
        let safePosition = findSafeBreakpoint(
            in: fullText,
            from: lastSafePosition,
            to: fullLength,
            pendingInfo: pendingInfo
        )

        // 3. 计算需要解析的范围
        // 回溯策略：从 lastSafePosition 向前回溯 contextWindowSize，确保捕获跨行结构
        let parseStart = max(0, lastSafePosition - contextWindowSize)
        let parseEnd = safePosition

        // 如果没有新内容需要解析
        if parseEnd <= parseStart {
            return IncrementalParseResult(
                safePosition: lastSafePosition,
                newElements: [],
                replaceCount: 0,
                hasPendingStructure: pendingInfo != nil,
                pendingType: pendingInfo,
                imageAttachments: [],
                tocItems: []
            )
        }

        // 4. 提取需要解析的片段
        let parseRange = NSRange(location: parseStart, length: parseEnd - parseStart)
        let textToparse = nsText.substring(with: parseRange)

        // 5. 执行解析
        let document = Document(parsing: textToparse)
        let (parsedElements, attachments) = render(document)
        let (tocItems, _) = extractHeadings(from: document)

        // 6. 计算需要替换的旧元素数量
        // 由于回溯了 contextWindowSize，可能需要替换一些旧元素
        let replaceCount = estimateReplaceCount(
            previousElementCount: previousElementCount,
            contextWindowSize: contextWindowSize,
            parseStart: parseStart,
            lastSafePosition: lastSafePosition
        )

        return IncrementalParseResult(
            safePosition: safePosition,
            newElements: parsedElements,
            replaceCount: replaceCount,
            hasPendingStructure: pendingInfo != nil,
            pendingType: pendingInfo,
            imageAttachments: attachments,
            tocItems: tocItems
        )
    }

    /// 检测文本中是否有未完成的结构
    private func detectPendingStructure(in text: String) -> PendingStructureType? {
        let nsText = text as NSString

        // 1. 检测未闭合的代码块 ```
        let codeBlockPattern = "```"
        var codeBlockCount = 0
        var searchRange = NSRange(location: 0, length: nsText.length)

        while searchRange.location < nsText.length {
            let foundRange = nsText.range(of: codeBlockPattern, options: [], range: searchRange)
            if foundRange.location == NSNotFound { break }
            codeBlockCount += 1
            searchRange.location = foundRange.location + foundRange.length
            searchRange.length = nsText.length - searchRange.location
        }

        if codeBlockCount % 2 != 0 {
            return .codeBlock
        }

        // 2. 检测未闭合的 LaTeX 块 $$
        let latexBlockPattern = "$$"
        var latexBlockCount = 0
        searchRange = NSRange(location: 0, length: nsText.length)

        while searchRange.location < nsText.length {
            let foundRange = nsText.range(of: latexBlockPattern, options: [], range: searchRange)
            if foundRange.location == NSNotFound { break }
            latexBlockCount += 1
            searchRange.location = foundRange.location + foundRange.length
            searchRange.length = nsText.length - searchRange.location
        }

        if latexBlockCount % 2 != 0 {
            return .latexBlock
        }

        // 3. 检测未完成的表格（末尾以 | 开头但无空行结束）
        let lines = text.components(separatedBy: .newlines)
        if let lastNonEmptyLine = lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            if lastNonEmptyLine.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                // 检查是否是表格行
                if lastNonEmptyLine.contains("|") && !text.hasSuffix("\n\n") {
                    return .table
                }
            }
        }

        // 4. 检测末尾是否是列表或引用块（可能未完成）
        if let lastLine = lines.last?.trimmingCharacters(in: .whitespaces) {
            // 列表项
            if lastLine.hasPrefix("- ") || lastLine.hasPrefix("* ") ||
               lastLine.hasPrefix("+ ") || lastLine.first?.isNumber == true {
                if !text.hasSuffix("\n") {
                    return .list
                }
            }
            // 引用块
            if lastLine.hasPrefix(">") && !text.hasSuffix("\n\n") {
                return .quote
            }
        }

        return nil
    }

    /// 查找安全断点位置
    private func findSafeBreakpoint(
        in text: String,
        from: Int,
        to: Int,
        pendingInfo: PendingStructureType?
    ) -> Int {
        let nsText = text as NSString

        // 如果有未完成的结构，需要找到该结构开始的位置
        if let pending = pendingInfo {
            switch pending {
            case .codeBlock:
                // 找到最后一个未闭合的 ``` 的位置
                if let lastCodeBlockStart = findLastUnmatchedCodeBlock(in: text) {
                    return lastCodeBlockStart
                }
            case .latexBlock:
                // 找到最后一个未闭合的 $$ 的位置
                if let lastLatexStart = findLastUnmatchedLatex(in: text) {
                    return lastLatexStart
                }
            case .table:
                // 找到表格开始的位置（最后一个空行之后）
                if let tableStart = findTableStart(in: text) {
                    return tableStart
                }
            case .list, .quote:
                // 找到最后一个空行之后的位置
                if let lastEmptyLine = findLastEmptyLinePosition(in: text) {
                    return lastEmptyLine
                }
            }
        }

        // 没有未完成的结构，返回文本末尾
        // 但如果末尾不是换行符，回退到最后一个完整行
        if !text.hasSuffix("\n") {
            if let lastNewline = text.lastIndex(of: "\n") {
                return text.distance(from: text.startIndex, to: lastNewline) + 1
            }
        }

        return to
    }

    /// 找到最后一个未匹配的代码块开始位置
    private func findLastUnmatchedCodeBlock(in text: String) -> Int? {
        let pattern = "```"
        var positions: [Int] = []
        var searchStart = text.startIndex

        while let range = text.range(of: pattern, range: searchStart..<text.endIndex) {
            let position = text.distance(from: text.startIndex, to: range.lowerBound)
            positions.append(position)
            searchStart = range.upperBound
        }

        // 奇数个 ```，返回最后一个的位置
        if positions.count % 2 != 0, let last = positions.last {
            return last
        }
        return nil
    }

    /// 找到最后一个未匹配的 LaTeX 块开始位置
    private func findLastUnmatchedLatex(in text: String) -> Int? {
        let pattern = "$$"
        var positions: [Int] = []
        var searchStart = text.startIndex

        while let range = text.range(of: pattern, range: searchStart..<text.endIndex) {
            let position = text.distance(from: text.startIndex, to: range.lowerBound)
            positions.append(position)
            searchStart = range.upperBound
        }

        if positions.count % 2 != 0, let last = positions.last {
            return last
        }
        return nil
    }

    /// 找到表格开始的位置
    private func findTableStart(in text: String) -> Int? {
        let lines = text.components(separatedBy: .newlines)
        var currentPosition = 0
        var tableStartPosition: Int? = nil

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                // 空行，重置表格开始位置
                tableStartPosition = nil
            } else if trimmed.hasPrefix("|") && trimmed.contains("|") {
                // 表格行
                if tableStartPosition == nil {
                    tableStartPosition = currentPosition
                }
            } else {
                // 非表格行，重置
                tableStartPosition = nil
            }

            currentPosition += line.count + (index < lines.count - 1 ? 1 : 0) // +1 for newline
        }

        return tableStartPosition
    }

    /// 找到最后一个空行之后的位置
    private func findLastEmptyLinePosition(in text: String) -> Int? {
        let nsText = text as NSString
        let pattern = "\n\n"
        let range = nsText.range(of: pattern, options: .backwards)

        if range.location != NSNotFound {
            return range.location + range.length
        }
        return nil
    }

    /// 估算需要替换的旧元素数量
    private func estimateReplaceCount(
        previousElementCount: Int,
        contextWindowSize: Int,
        parseStart: Int,
        lastSafePosition: Int
    ) -> Int {
        // 如果回溯了（parseStart < lastSafePosition），可能需要替换一些元素
        if parseStart < lastSafePosition {
            // 保守估计：每 100 个字符约对应 1 个元素
            let backtrackChars = lastSafePosition - parseStart
            let estimatedElements = max(1, backtrackChars / 100)
            return min(estimatedElements, previousElementCount)
        }
        return 0
    }
    
    func parseAndRender(_ markdown: String) -> (
        elements: [MarkdownRenderElement],
        imageAttachments: [(attachment: MarkdownImageAttachment, urlString: String)],
        tableOfContents: [MarkdownTOCItem],
        tocSectionId: String?
    ) {
        
        let document = Document(parsing: markdown)
        
        // 提取 TOC 和自动目录区域 ID
        let (tocItems, tocId) = extractHeadings(from: document)
        
        // 渲染元素
        let (elements, attachments) = render(document)
        
        return (elements, attachments, tocItems, tocId)
    }
    
    private func render(_ document: Document) -> (
        elements: [MarkdownRenderElement],
        imageAttachments: [(attachment: MarkdownImageAttachment, urlString: String)]
    ) {
        imageAttachments = []
        elements = []
        currentTextBuffer = NSMutableAttributedString()
        
        for child in document.children {
            renderBlock(child)
        }
        
        flushTextBuffer()
        
        let groupedElements = groupDetailsElements(elements)
        
        return (groupedElements, imageAttachments)
    }
    
    // 下面是原来 MarkdownRenderer 中所有私有方法的完整实现
    // （直接复制你提供的原始代码中从 cachedRegex 开始到最后的所有内容）
    
    private func cachedRegex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        let key = "\(pattern)-\(options.rawValue)"
        
        Self.regexLock.lock()
        defer { Self.regexLock.unlock() }
        
        if let cached = Self.regexCache[key] {
            return cached
        }
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        
        Self.regexCache[key] = regex
        return regex
    }
    
    private func groupDetailsElements(_ elements: [MarkdownRenderElement]) -> [MarkdownRenderElement] {
        var result: [MarkdownRenderElement] = []
        var stack: [(summary: String, children: [MarkdownRenderElement])] = []
        
        let openPattern = "<details>\\s*<summary>(.*?)</summary>"
        let closePattern = "</details>"
        
        let openRegex = try? NSRegularExpression(pattern: openPattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
        let closeRegex = try? NSRegularExpression(pattern: closePattern, options: [.caseInsensitive])
        
        for element in elements {
            var processed = false
            
            if case .rawHTML(let html) = element {
                let nsString = html as NSString
                let range = NSRange(location: 0, length: nsString.length)
                
                if let regex = openRegex,
                   let match = regex.firstMatch(in: html, options: [], range: range) {
                    let summaryRange = match.range(at: 1)
                    let summary = nsString.substring(with: summaryRange).trimmingCharacters(in: .whitespacesAndNewlines)
                    stack.append((summary: summary, children: []))
                    processed = true
                } else if let regex = closeRegex,
                          regex.firstMatch(in: html, options: [], range: range) != nil {
                    if let last = stack.popLast() {
                        let detailsElement = MarkdownRenderElement.details(summary: last.summary, children: last.children)
                        if stack.isEmpty {
                            result.append(detailsElement)
                        } else {
                            stack[stack.count - 1].children.append(detailsElement)
                        }
                    }
                    processed = true
                }
            }
            
            if !processed {
                if stack.isEmpty {
                    result.append(element)
                } else {
                    stack[stack.count - 1].children.append(element)
                }
            }
        }
        
        for item in stack {
            result.append(.rawHTML("<details><summary>\(item.summary)</summary>"))
            result.append(contentsOf: item.children)
        }
        
        return result
    }
    
    // MARK: - Block Level
    
    private func renderBlock(_ markup: any Markup) {
        switch markup {
        case let table as Table:
            flushTextBuffer()
            elements.append(.table(renderTableData(table)))
            currentTextBuffer.append(NSAttributedString(string: "\n"))
            
        case let heading as Heading:
            flushTextBuffer()
            let id = "heading-\(headingIndex)"
            headingIndex += 1
            elements.append(.heading(id: id, text: renderHeading(heading)))
            
        case let paragraph as Paragraph:
            // 检测段落中是否包含 LaTeX 公式
            let paragraphText = paragraph.plainText
            if paragraphText.contains("$$") || paragraphText.contains("$") {
                renderParagraphWithLatex(paragraph)
            } else {
                currentTextBuffer.append(renderParagraph(paragraph))
            }
            
        case let codeBlock as CodeBlock:
            flushTextBuffer()

            let rawCode = codeBlock.code.trimmingCharacters(in: .whitespacesAndNewlines)
            let lang = codeBlock.language?.lowercased()

            // Check if it's a LaTeX block (wrapped in $$ or language is math/latex)
            if rawCode.hasPrefix("$$") && rawCode.hasSuffix("$$") && rawCode.count >= 4 {
                let startIndex = rawCode.index(rawCode.startIndex, offsetBy: 2)
                let endIndex = rawCode.index(rawCode.endIndex, offsetBy: -2)
                let latex = String(rawCode[startIndex..<endIndex])
                elements.append(.latex(latex))
            } else if lang == "math" || lang == "latex" {
                 elements.append(.latex(codeBlock.code))
            } else {
                // 传递语言信息以支持自定义代码块渲染器
                elements.append(.codeBlock(language: lang, code: renderCodeBlock(codeBlock)))
            }
            
        case let blockQuote as BlockQuote:
            flushTextBuffer()
            // 使用 captureElements 捕获引用块内部的所有子元素
            quoteDepth += 1
            let children = captureElements {
                for child in blockQuote.children {
                    renderBlock(child)
                }
            }
            let currentLevel = quoteDepth
            quoteDepth -= 1
            elements.append(.quote(children: children, level: currentLevel))
            
        case let unorderedList as UnorderedList:
            flushTextBuffer()
            listDepth += 1
            let items = renderListItems(unorderedList.listItems)
            let currentLevel = listDepth
            listDepth -= 1
            elements.append(.list(items: items, level: currentLevel))

        case let orderedList as OrderedList:
            flushTextBuffer()
            listDepth += 1
            orderedListCounters.append(Int(orderedList.startIndex))
            let items = renderListItems(orderedList.listItems, isOrdered: true)
            let currentLevel = listDepth
            orderedListCounters.removeLast()
            listDepth -= 1
            elements.append(.list(items: items, level: currentLevel))
            
        case _ as ThematicBreak:
            flushTextBuffer()
            elements.append(.thematicBreak)
            
        case let htmlBlock as HTMLBlock:
            currentTextBuffer.append(renderHTMLBlock(htmlBlock))
        case let image as Markdown.Image:
            flushTextBuffer()
            if let source = image.source, !source.isEmpty {
                elements.append(.image(source: source, altText: image.plainText))
            }
        default:
            for child in markup.children {
                renderBlock(child)
            }
        }
    }
    
    private func flushTextBuffer() {
        if currentTextBuffer.length > 0 {
            elements.append(.attributedText(currentTextBuffer))
            currentTextBuffer = NSMutableAttributedString()
        }
    }

    // MARK: - Core Capture Logic (核心捕获逻辑)

    /// 劫持渲染输出流，捕获闭包期间生成的元素
    /// 用于实现列表项和引用块的嵌套渲染
    private func captureElements(action: () -> Void) -> [MarkdownRenderElement] {
        // 1. 先把当前缓存的纯文本 flush 到原来的 elements 里
        flushTextBuffer()

        // 2. 备份原来的 elements
        let originalElements = self.elements
        // 3. 创建一个新的容器
        self.elements = []

        // 4. 执行渲染逻辑 (这里面调用的 renderBlock 会把东西加到 self.elements)
        action()

        // 5. 再次 flush (确保闭包最后遗留的文本被提交)
        flushTextBuffer()

        // 6. 获取捕获到的 children
        let capturedChildren = self.elements

        // 7. 恢复原来的环境
        self.elements = originalElements

        return capturedChildren
    }

    // MARK: - Table Data
    
    private func renderTableData(_ table: Table) -> MarkdownTableData {
        var headers: [NSAttributedString] = []
        var rows: [[NSAttributedString]] = []
        
        isInTable = true  // 添加这行
        
        isTableHeader = true
        for cell in table.head.cells {
            headers.append(renderTableCellContent(cell))
        }
        isTableHeader = false
        
        for row in table.body.rows {
            var rowCells: [NSAttributedString] = []
            for cell in row.cells {
                rowCells.append(renderTableCellContent(cell))
            }
            rows.append(rowCells)
        }
        
        isInTable = false  // 添加这行
        
        return MarkdownTableData(headers: headers, rows: rows)
    }
    
    private func renderTableCellContent(_ cell: Table.Cell) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in cell.children {
            result.append(renderMarkup(child))
        }
        
        let font = isTableHeader
            ? UIFont.systemFont(ofSize: configuration.bodyFont.pointSize, weight: .semibold)
            : configuration.bodyFont
        
        if result.length > 0 {
            result.addAttribute(.font, value: font, range: NSRange(location: 0, length: result.length))
        }
        
        return result
    }
    
    // MARK: - Inline Rendering
    
    private func renderMarkup(_ markup: any Markup) -> NSMutableAttributedString {
        switch markup {
        case let text as Text:
            return renderText(text)
        case let strong as Strong:
            return renderStrong(strong)
        case let emphasis as Emphasis:
            return renderEmphasis(emphasis)
        case let strikethrough as Strikethrough:
            return renderStrikethrough(strikethrough)
        case let link as Link:
            return renderLink(link)
        case let image as Image:
            // 表格内的图片语法作为文本显示，不渲染成图片元素
            if isInTable {
                let altText = image.plainText.isEmpty ? "" : image.plainText
                let source = image.source ?? ""
                let text = "![\(altText)](\(source))"
                return NSMutableAttributedString(
                    string: text,
                    attributes: [
                        .font: configuration.bodyFont,
                        .foregroundColor: configuration.textColor,
                    ])
            }
            
            flushTextBuffer()
            if let source = image.source, !source.isEmpty {
                elements.append(.image(source: source, altText: image.plainText))
            }
            return NSMutableAttributedString()
        case let inlineCode as InlineCode:
            return renderInlineCode(inlineCode)
        case _ as SoftBreak:
            return renderSoftBreak()
        case _ as LineBreak:
            return renderLineBreak()
        case let inlineHTML as InlineHTML:
            return renderInlineHTML(inlineHTML)
            // 添加这两个 case！
        case let unorderedList as UnorderedList:
            return renderUnorderedList(unorderedList)
        case let orderedList as OrderedList:
            return renderOrderedList(orderedList)
        case let paragraph as Paragraph:
            return renderParagraph(paragraph)
        default:
            return renderChildren(of: markup)
        }
    }
    
    private func renderChildren(of markup: any Markup) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for child in markup.children {
            result.append(renderMarkup(child))
        }
        return result
    }
    
    // MARK: - Headings
    
    private func renderHeading(_ heading: Heading) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        
        let font: UIFont
        switch heading.level {
        case 1: font = configuration.h1Font
        case 2: font = configuration.h2Font
        case 3: font = configuration.h3Font
        case 4: font = configuration.h4Font
        case 5: font = configuration.h5Font
        default: font = configuration.h6Font
        }
        
        for child in heading.children {
            result.append(renderMarkup(child))
        }
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = 3
        paragraphStyle.lineHeightMultiple = 1.2
        paragraphStyle.lineSpacing = 4
        
        let range = NSRange(location: 0, length: result.length)
        result.addAttributes([
            .font: font,
            .foregroundColor: configuration.headingColor,
            .paragraphStyle: paragraphStyle,
        ], range: range)
        
        return result
    }
    
    // MARK: - Paragraph
    
    private func renderParagraph(_ paragraph: Paragraph) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        
        for child in paragraph.children {
            result.append(renderMarkup(child))
        }
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        
        // 只有不在列表中时才添加段落间距
        if listDepth == 0 {
            paragraphStyle.paragraphSpacing = configuration.paragraphSpacing
        }
        
        if isInBlockquote {
            paragraphStyle.firstLineHeadIndent = configuration.blockquoteIndent
            paragraphStyle.headIndent = configuration.blockquoteIndent
        }
        
        let range = NSRange(location: 0, length: result.length)
        if range.length > 0 {
            result.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        }
        
        // 段落末尾添加换行
        if result.length == 0 || !result.string.hasSuffix("\n") {
            result.append(NSAttributedString(string: "\n"))
        }
        
        return result
    }

    /// 处理包含 LaTeX 公式的段落
    private func renderParagraphWithLatex(_ paragraph: Paragraph) {
        let paragraphText = paragraph.plainText

        // 正则表达式匹配 $$...$$ 和 $...$
        let displayPattern = #"\$\$(.+?)\$\$"#
        let inlinePattern = #"\$(.+?)\$"#

        guard let displayRegex = cachedRegex(displayPattern, options: [.dotMatchesLineSeparators]) else {
            // 如果正则失败，回退到普通渲染
            currentTextBuffer.append(renderParagraph(paragraph))
            return
        }

        // 查找所有块级公式 ($$...$$)
        let matches = displayRegex.matches(
            in: paragraphText,
            range: NSRange(paragraphText.startIndex..., in: paragraphText)
        )

        if matches.isEmpty {
            // 没有块级公式，使用普通渲染
            currentTextBuffer.append(renderParagraph(paragraph))
            return
        }

        // 分割段落
        var lastIndex = paragraphText.startIndex

        for match in matches {
            // 提取公式内容
            guard let latexRange = Range(match.range(at: 1), in: paragraphText) else { continue }
            let latex = String(paragraphText[latexRange])

            // 提取公式前的文本
            let fullMatchRange = Range(match.range, in: paragraphText)!
            let beforeText = String(paragraphText[lastIndex..<fullMatchRange.lowerBound])

            // 渲染公式前的文本
            if !beforeText.isEmpty {
                let beforeAttr = NSMutableAttributedString(
                    string: beforeText,
                    attributes: defaultTextAttributes
                )
                currentTextBuffer.append(beforeAttr)
            }

            // Flush 当前 buffer 并添加 LaTeX 元素
            flushTextBuffer()
            elements.append(.latex(latex))

            lastIndex = fullMatchRange.upperBound
        }

        // 处理最后一个公式后的文本
        let remainingText = String(paragraphText[lastIndex...])
        if !remainingText.isEmpty {
            let remainingAttr = NSMutableAttributedString(
                string: remainingText + "\n",
                attributes: defaultTextAttributes
            )
            currentTextBuffer.append(remainingAttr)
        }
    }

    // MARK: - Text
    
    // 在 MarkdownRendererTK2 中添加缓存的 attributes
    private lazy var defaultTextAttributes: [NSAttributedString.Key: Any] = {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        return [
            .font: configuration.bodyFont,
            .foregroundColor: configuration.textColor,
            .paragraphStyle: paragraphStyle
        ]
    }()

    private lazy var blockquoteTextAttributes: [NSAttributedString.Key: Any] = {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        return [
            .font: configuration.bodyFont,
            .foregroundColor: configuration.blockquoteTextColor,
            .paragraphStyle: paragraphStyle
        ]
    }()

    private func renderText(_ text: Text) -> NSMutableAttributedString {
        let textString = text.string
        let attributes = isInBlockquote ? blockquoteTextAttributes : defaultTextAttributes

        return NSMutableAttributedString(string: textString, attributes: attributes)
    }

    /// 处理文本中的 HTML 标签
    
    // MARK: - Strong
    
    private func renderStrong(_ strong: Strong) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for child in strong.children {
            result.append(renderMarkup(child))
        }
        
        let range = NSRange(location: 0, length: result.length)
        if result.length > 0,
           let currentFont = result.attribute(.font, at: 0, effectiveRange: nil) as? UIFont {
            let boldFont = UIFont.systemFont(ofSize: currentFont.pointSize, weight: .bold)
            result.addAttribute(.font, value: boldFont, range: range)
        }
        
        return result
    }
    
    // MARK: - Emphasis
    
    private func renderEmphasis(_ emphasis: Emphasis) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for child in emphasis.children {
            result.append(renderMarkup(child))
        }
        
        let range = NSRange(location: 0, length: result.length)
        if result.length > 0,
           let currentFont = result.attribute(.font, at: 0, effectiveRange: nil) as? UIFont {
            let italicFont = UIFont.italicSystemFont(ofSize: currentFont.pointSize)
            result.addAttribute(.font, value: italicFont, range: range)
        }
        
        return result
    }
    
    // MARK: - Strikethrough
    
    private func renderStrikethrough(_ strikethrough: Strikethrough) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for child in strikethrough.children {
            result.append(renderMarkup(child))
        }
        
        let range = NSRange(location: 0, length: result.length)
        result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        
        return result
    }
    
    // MARK: - Link
    
    private func renderLink(_ link: Link) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for child in link.children {
            result.append(renderMarkup(child))
        }
        
        let range = NSRange(location: 0, length: result.length)
        result.addAttributes([
            .foregroundColor: configuration.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ], range: range)
        
        if let destination = link.destination {
            if let url = URL(string: destination) {
                result.addAttribute(.link, value: url, range: range)
            } else if let encoded = destination.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
                      let url = URL(string: encoded) {
                result.addAttribute(.link, value: url, range: range)
            }
        }
        
        return result
    }
    
    // MARK: - Image
    
    private func renderImage(_ image: Image) -> NSMutableAttributedString {
        // 图片现在作为独立元素处理，这里不再返回 attachment
        return NSMutableAttributedString()
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
    
    // MARK: - Inline Code
    
    private func renderInlineCode(_ inlineCode: InlineCode) -> NSMutableAttributedString {
        let text = " \(inlineCode.code) "
        return NSMutableAttributedString(
            string: text,
            attributes: [
                .font: configuration.codeFont,
                .foregroundColor: configuration.codeTextColor,
                .backgroundColor: configuration.codeBackgroundColor,
            ])
    }
    
    // MARK: - Code Block

    private func renderCodeBlock(_ codeBlock: CodeBlock) -> NSMutableAttributedString {
        isInCodeBlock = true
        defer { isInCodeBlock = false }

        let code = codeBlock.code.trimmingCharacters(in: .newlines)
        let language = codeBlock.language

        // [CODEBLOCK_DEBUG] 追踪代码块解析
        print("[CODEBLOCK_DEBUG] 🔍 renderCodeBlock: lang=\(language ?? "nil"), codeLength=\(code.count), codePreview=\(code.prefix(50).replacingOccurrences(of: "\n", with: "⏎"))")

        // 应用语法高亮
        let highlightedCode = applySyntaxHighlighting(to: code, language: language)
        let result = NSMutableAttributedString(attributedString: highlightedCode)

        // [CODEBLOCK_DEBUG] 追踪高亮后长度
        print("[CODEBLOCK_DEBUG] 🔍 renderCodeBlock: highlightedLength=\(result.length)")

        // 添加段落样式
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: result.length))

        return result
    }

    // MARK: - Lists

    /// 通用的列表项渲染方法 - 生成 [ListNodeItem] 支持嵌套
    private func renderListItems(_ listItems: LazyMapSequence<MarkupChildren, ListItem>, isOrdered: Bool = false) -> [ListNodeItem] {
        var items: [ListNodeItem] = []
        var index = orderedListCounters.last ?? 1

        for itemMarkup in listItems {
            // 1. 决定标记符 (Marker)
            let marker: String
            if let checkbox = itemMarkup.checkbox {
                marker = checkbox == .checked ? "☑" : "☐"
            } else if isOrdered {
                marker = "\(index)."
                index += 1
            } else {
                // 无序列表，根据深度决定符号
                let bullets = ["•", "◦", "▪", "▫"]
                marker = bullets[min(listDepth - 1, bullets.count - 1)]
            }

            // 2. 捕获列表项的内容（关键！支持嵌套表格、代码块等）
            let children = captureElements {
                for child in itemMarkup.children {
                    renderBlock(child)
                }
            }

            items.append(ListNodeItem(marker: marker, children: children))

            // 更新有序列表计数器
            if isOrdered && !orderedListCounters.isEmpty {
                orderedListCounters[orderedListCounters.count - 1] = index
            }
        }

        return items
    }

    private func renderUnorderedList(_ unorderedList: UnorderedList) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        listDepth += 1
        
        for item in unorderedList.listItems {
            result.append(renderListItem(item))
        }
        
        listDepth -= 1
        
        // 只在最外层列表后添加额外换行
        if listDepth == 0 {
            result.append(NSAttributedString(string: "\n"))
        }
        
        return result
    }

    private func renderOrderedList(_ orderedList: OrderedList) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        listDepth += 1
        orderedListCounters.append(Int(orderedList.startIndex))
        
        for item in orderedList.listItems {
            result.append(renderListItem(item))
            orderedListCounters[orderedListCounters.count - 1] += 1
        }
        
        orderedListCounters.removeLast()
        listDepth -= 1
        
        // 只在最外层列表后添加额外换行
        if listDepth == 0 {
            result.append(NSAttributedString(string: "\n"))
        }
        
        return result
    }
    
    private func renderListItem(_ listItem: ListItem) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        
        let indent = String(repeating: "    ", count: listDepth - 1)
        var bullet: String
        
        if let checkbox = listItem.checkbox {
            bullet = checkbox == .checked ? "☑" : "☐"
        } else if orderedListCounters.isEmpty {
            let bullets = ["•", "◦", "▪", "▫"]
            bullet = bullets[min(listDepth - 1, bullets.count - 1)]
        } else {
            bullet = "\(orderedListCounters.last ?? 1)."
        }
        
        let prefix = "\(indent)\(bullet) "
        result.append(
            NSAttributedString(
                string: prefix,
                attributes: [
                    .font: configuration.bodyFont,
                    .foregroundColor: configuration.textColor,
                ]))
        
        // 分开处理：先处理非列表内容，再处理子列表
        var hasAddedContent = false
        
        for child in listItem.children {
            if child is UnorderedList || child is OrderedList {
                // 子列表：确保前面有换行，然后递归渲染
                if hasAddedContent && !result.string.hasSuffix("\n") {
                    result.append(NSAttributedString(string: "\n"))
                }
                // 递归渲染子列表（renderUnorderedList/renderOrderedList 会增加 listDepth）
                result.append(renderMarkup(child))
            } else {
                // 非列表内容（段落等）
                let childResult = renderMarkup(child)
                // 移除末尾多余换行
                while childResult.string.hasSuffix("\n\n") {
                    childResult.deleteCharacters(in: NSRange(location: childResult.length - 1, length: 1))
                }
                // 移除单个末尾换行（列表项内的段落不需要额外换行）
                if childResult.string.hasSuffix("\n") {
                    childResult.deleteCharacters(in: NSRange(location: childResult.length - 1, length: 1))
                }
                result.append(childResult)
                hasAddedContent = true
            }
        }
        
        // 列表项结尾换行
        if !result.string.hasSuffix("\n") {
            result.append(NSAttributedString(string: "\n"))
        }
        
        return result
    }
    
    // MARK: - Breaks
    
    private func renderSoftBreak() -> NSMutableAttributedString {
        return NSMutableAttributedString(string: " ")
    }
    
    private func renderLineBreak() -> NSMutableAttributedString {
        return NSMutableAttributedString(string: "\n")
    }
    
    // MARK: - HTML
    
    private func renderHTMLBlock(_ html: HTMLBlock) -> NSMutableAttributedString {
        flushTextBuffer()
        elements.append(.rawHTML(html.rawHTML))
        return NSMutableAttributedString()
    }
    
    private func renderInlineHTML(_ html: InlineHTML) -> NSMutableAttributedString {
        let htmlString = html.rawHTML

        

        // 降级: 显示为代码样式
        return NSMutableAttributedString(
            string: htmlString,
            attributes: [
                .font: configuration.codeFont,
                .foregroundColor: UIColor.secondaryLabel,
            ])
    }
    
    // MARK: - Syntax Highlighting

    private func applySyntaxHighlighting(to code: String, language: String?) -> NSAttributedString {
        let result = NSMutableAttributedString(string: code)
        let fullRange = NSRange(location: 0, length: result.length)
        
        // 基础样式
        result.addAttributes([
            .font: configuration.codeFont,
            .foregroundColor: configuration.codeTextColor,
        ], range: fullRange)
        
        let lang = language?.lowercased() ?? ""
        
        // Xcode 风格颜色
        let colors = SyntaxColors.xcode
        
        // 根据语言应用高亮
        switch lang {
        case "swift":
            highlightSwift(result, colors: colors)
        case "objc", "objective-c", "objectivec", "oc":
            highlightObjC(result, colors: colors)
        case "java", "kotlin":
            highlightJava(result, colors: colors)
        case "javascript", "js", "typescript", "ts":
            highlightJavaScript(result, colors: colors)
        case "python", "py":
            highlightPython(result, colors: colors)
        case "ruby", "rb":
            highlightRuby(result, colors: colors)
        case "go", "golang":
            highlightGo(result, colors: colors)
        case "rust", "rs":
            highlightRust(result, colors: colors)
        case "c", "cpp", "c++", "h", "hpp":
            highlightCpp(result, colors: colors)
        case "json":
            highlightJSON(result, colors: colors)
        case "html", "xml":
            highlightHTML(result, colors: colors)
        case "css", "scss", "sass":
            highlightCSS(result, colors: colors)
        case "sql":
            highlightSQL(result, colors: colors)
        case "shell", "bash", "sh", "zsh":
            highlightShell(result, colors: colors)
        case "yaml", "yml":
            highlightYAML(result, colors: colors)
        default:
            // 通用高亮
            highlightGeneric(result, colors: colors)
        }
        
        return result
    }

    // Xcode 风格配色
    private struct SyntaxColors {
        let keyword: UIColor
        let string: UIColor
        let number: UIColor
        let comment: UIColor
        let type: UIColor
        let function: UIColor
        let property: UIColor
        let preprocessor: UIColor
        
        static var xcode: SyntaxColors {
            return SyntaxColors(
                keyword: UIColor(red: 0.78, green: 0.24, blue: 0.59, alpha: 1.0),      // 紫红色 #C73E95
                string: UIColor(red: 0.84, green: 0.19, blue: 0.16, alpha: 1.0),       // 红色 #D63129
                number: UIColor(red: 0.11, green: 0.27, blue: 0.53, alpha: 1.0),       // 深蓝色 #1C4587
                comment: UIColor(red: 0.42, green: 0.47, blue: 0.50, alpha: 1.0),      // 灰色 #6B787F
                type: UIColor(red: 0.11, green: 0.43, blue: 0.55, alpha: 1.0),         // 青色 #1C6E8C
                function: UIColor(red: 0.26, green: 0.40, blue: 0.55, alpha: 1.0),     // 蓝色 #42668C
                property: UIColor(red: 0.26, green: 0.40, blue: 0.55, alpha: 1.0),     // 蓝色
                preprocessor: UIColor(red: 0.54, green: 0.36, blue: 0.20, alpha: 1.0)  // 棕色 #8A5C33
            )
        }
        
        static var xcodeDark: SyntaxColors {
            return SyntaxColors(
                keyword: UIColor(red: 0.99, green: 0.42, blue: 0.64, alpha: 1.0),      // 粉色 #FC6BA3
                string: UIColor(red: 0.99, green: 0.42, blue: 0.36, alpha: 1.0),       // 橙红 #FC6B5C
                number: UIColor(red: 0.82, green: 0.75, blue: 0.50, alpha: 1.0),       // 黄色 #D1BF80
                comment: UIColor(red: 0.51, green: 0.55, blue: 0.52, alpha: 1.0),      // 灰绿 #828C85
                type: UIColor(red: 0.39, green: 0.80, blue: 0.79, alpha: 1.0),         // 青色 #63CCC9
                function: UIColor(red: 0.40, green: 0.72, blue: 0.89, alpha: 1.0),     // 浅蓝 #66B8E3
                property: UIColor(red: 0.40, green: 0.72, blue: 0.89, alpha: 1.0),
                preprocessor: UIColor(red: 0.99, green: 0.65, blue: 0.40, alpha: 1.0)  // 橙色 #FCA666
            )
        }
    }

    private func applyPattern(_ pattern: String, to attrString: NSMutableAttributedString, color: UIColor, options: NSRegularExpression.Options = []) {
        guard let regex = cachedRegex(pattern, options: options) else { return }
        let range = NSRange(location: 0, length: attrString.length)
        regex.enumerateMatches(in: attrString.string, options: [], range: range) { match, _, _ in
            if let matchRange = match?.range {
                attrString.addAttribute(.foregroundColor, value: color, range: matchRange)
            }
        }
    }

    private func applyPatternGroup(_ pattern: String, to attrString: NSMutableAttributedString, color: UIColor, groupIndex: Int = 1) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let range = NSRange(location: 0, length: attrString.length)
        regex.enumerateMatches(in: attrString.string, options: [], range: range) { match, _, _ in
            if let matchRange = match?.range(at: groupIndex), matchRange.location != NSNotFound {
                attrString.addAttribute(.foregroundColor, value: color, range: matchRange)
            }
        }
    }

    // MARK: - Language Specific Highlighting

    private func highlightSwift(_ attrString: NSMutableAttributedString, colors: SyntaxColors) {
        let keywords = [
            "import", "class", "struct", "enum", "protocol", "extension", "func", "var", "let",
            "if", "else", "guard", "switch", "case", "default", "for", "while", "repeat",
            "return", "break", "continue", "throw", "throws", "rethrows", "try", "catch",
            "public", "private", "internal", "fileprivate", "open", "static", "final",
            "override", "mutating", "nonmutating", "weak", "unowned", "lazy", "dynamic",
            "self", "Self", "super", "nil", "true", "false", "as", "is", "in", "where",
            "init", "deinit", "get", "set", "willSet", "didSet", "subscript", "typealias",
            "associatedtype", "inout", "some", "any", "async", "await", "actor", "nonisolated",
            "@escaping", "@autoclosure", "@MainActor", "@Published", "@State", "@Binding",
            "@ObservedObject", "@EnvironmentObject", "@Environment", "@available", "@objc"
        ]
        applyPattern("\\b(" + keywords.joined(separator: "|") + ")\\b", to: attrString, color: colors.keyword)
        
        // 类型（大写开头）
        applyPattern("\\b([A-Z][a-zA-Z0-9_]*)\\b", to: attrString, color: colors.type)
        
        // 字符串
        applyPattern("\"\"\"[\\s\\S]*?\"\"\"", to: attrString, color: colors.string)
        applyPattern("\"(?:[^\"\\\\]|\\\\.)*\"", to: attrString, color: colors.string)
        
        // 数字
        applyPattern("\\b\\d+\\.?\\d*\\b", to: attrString, color: colors.number)
        
        // 注释（最后处理，覆盖其他）
        applyPattern("//.*$", to: attrString, color: colors.comment, options: .anchorsMatchLines)
        applyPattern("/\\*[\\s\\S]*?\\*/", to: attrString, color: colors.comment)
    }

    private func highlightObjC(_ attrString: NSMutableAttributedString, colors: SyntaxColors) {
        let keywords = [
            "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue",
            "return", "goto", "typedef", "struct", "enum", "union", "sizeof", "static", "extern",
            "const", "volatile", "register", "auto", "void", "char", "short", "int", "long",
            "float", "double", "signed", "unsigned", "bool", "true", "false", "nil", "NULL",
            "self", "super", "YES", "NO", "id", "Class", "SEL", "IMP", "BOOL",
            "@interface", "@implementation", "@end", "@protocol", "@optional", "@required",
            "@property", "@synthesize", "@dynamic", "@class", "@public", "@private", "@protected",
            "@try", "@catch", "@finally", "@throw", "@selector", "@encode", "@synchronized",
            "nonatomic", "atomic", "strong", "weak", "copy", "assign", "retain", "readonly", "readwrite"
        ]
        applyPattern("\\b(" + keywords.joined(separator: "|") + ")\\b|(@\\w+)", to: attrString, color: colors.keyword)
        
        // 类型
        applyPattern("\\b(NS|UI|CG|CF|CA)[A-Z][a-zA-Z0-9_]*\\b", to: attrString, color: colors.type)
        
        // 字符串
        applyPattern("@?\"(?:[^\"\\\\]|\\\\.)*\"", to: attrString, color: colors.string)
        
        // 数字
        applyPattern("\\b\\d+\\.?\\d*[fFlL]?\\b", to: attrString, color: colors.number)
        
        // 预处理
        applyPattern("^\\s*#\\w+.*$", to: attrString, color: colors.preprocessor, options: .anchorsMatchLines)
        
        // 注释
        applyPattern("//.*$", to: attrString, color: colors.comment, options: .anchorsMatchLines)
        applyPattern("/\\*[\\s\\S]*?\\*/", to: attrString, color: colors.comment)
    }

    private func highlightJavaScript(_ attrString: NSMutableAttributedString, colors: SyntaxColors) {
        let keywords = [
            "var", "let", "const", "function", "return", "if", "else", "for", "while", "do",
            "switch", "case", "default", "break", "continue", "try", "catch", "finally", "throw",
            "new", "delete", "typeof", "instanceof", "in", "of", "this", "super", "class",
            "extends", "static", "get", "set", "import", "export", "from", "as", "default",
            "async", "await", "yield", "true", "false", "null", "undefined", "NaN", "Infinity",
            "void", "with", "debugger", "arguments", "eval"
        ]
        applyPattern("\\b(" + keywords.joined(separator: "|") + ")\\b", to: attrString, color: colors.keyword)
        
        // 函数调用
        applyPatternGroup("\\b([a-zA-Z_][a-zA-Z0-9_]*)\\s*\\(", to: attrString, color: colors.function)
        
        // 字符串
        applyPattern("`[^`]*`", to: attrString, color: colors.string)
        applyPattern("\"(?:[^\"\\\\]|\\\\.)*\"", to: attrString, color: colors.string)
        applyPattern("'(?:[^'\\\\]|\\\\.)*'", to: attrString, color: colors.string)
        
        // 数字
        applyPattern("\\b\\d+\\.?\\d*\\b", to: attrString, color: colors.number)
        
        // 注释
        applyPattern("//.*$", to: attrString, color: colors.comment, options: .anchorsMatchLines)
        applyPattern("/\\*[\\s\\S]*?\\*/", to: attrString, color: colors.comment)
    }

    private func highlightPython(_ attrString: NSMutableAttributedString, colors: SyntaxColors) {
        let keywords = [
            "def", "class", "if", "elif", "else", "for", "while", "try", "except", "finally",
            "with", "as", "import", "from", "return", "yield", "raise", "pass", "break",
            "continue", "in", "not", "and", "or", "is", "lambda", "global", "nonlocal",
            "True", "False", "None", "self", "cls", "async", "await", "assert", "del"
        ]
        applyPattern("\\b(" + keywords.joined(separator: "|") + ")\\b", to: attrString, color: colors.keyword)
        
        // 装饰器
        applyPattern("@\\w+", to: attrString, color: colors.preprocessor)
        
        // 函数定义
        applyPatternGroup("\\bdef\\s+([a-zA-Z_][a-zA-Z0-9_]*)", to: attrString, color: colors.function)
        
        // 字符串
        applyPattern("\"\"\"[\\s\\S]*?\"\"\"", to: attrString, color: colors.string)
        applyPattern("'''[\\s\\S]*?'''", to: attrString, color: colors.string)
        applyPattern("f?\"(?:[^\"\\\\]|\\\\.)*\"", to: attrString, color: colors.string)
        applyPattern("f?'(?:[^'\\\\]|\\\\.)*'", to: attrString, color: colors.string)
        
        // 数字
        applyPattern("\\b\\d+\\.?\\d*\\b", to: attrString, color: colors.number)
        
        // 注释
        applyPattern("#.*$", to: attrString, color: colors.comment, options: .anchorsMatchLines)
    }

    private func highlightJava(_ attrString: NSMutableAttributedString, colors: SyntaxColors) {
        let keywords = [
            "public", "private", "protected", "class", "interface", "enum", "extends", "implements",
            "static", "final", "abstract", "synchronized", "volatile", "transient", "native",
            "void", "boolean", "byte", "char", "short", "int", "long", "float", "double",
            "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue",
            "return", "throw", "throws", "try", "catch", "finally", "new", "this", "super",
            "null", "true", "false", "instanceof", "import", "package", "assert"
        ]
        applyPattern("\\b(" + keywords.joined(separator: "|") + ")\\b", to: attrString, color: colors.keyword)
        
        // 注解
        applyPattern("@\\w+", to: attrString, color: colors.preprocessor)
        
        // 类型
        applyPattern("\\b([A-Z][a-zA-Z0-9_]*)\\b", to: attrString, color: colors.type)
        
        // 字符串
        applyPattern("\"(?:[^\"\\\\]|\\\\.)*\"", to: attrString, color: colors.string)
        
        // 数字
        applyPattern("\\b\\d+\\.?\\d*[fFdDlL]?\\b", to: attrString, color: colors.number)
        
        // 注释
        applyPattern("//.*$", to: attrString, color: colors.comment, options: .anchorsMatchLines)
        applyPattern("/\\*[\\s\\S]*?\\*/", to: attrString, color: colors.comment)
    }

    private func highlightGo(_ attrString: NSMutableAttributedString, colors: SyntaxColors) {
        let keywords = [
            "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough",
            "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range",
            "return", "select", "struct", "switch", "type", "var", "true", "false", "nil", "iota",
            "int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint16", "uint32", "uint64",
            "float32", "float64", "complex64", "complex128", "byte", "rune", "string", "bool", "error"
        ]
        applyPattern("\\b(" + keywords.joined(separator: "|") + ")\\b", to: attrString, color: colors.keyword)
        
        // 字符串
        applyPattern("`[^`]*`", to: attrString, color: colors.string)
        applyPattern("\"(?:[^\"\\\\]|\\\\.)*\"", to: attrString, color: colors.string)
        
        // 数字
        applyPattern("\\b\\d+\\.?\\d*\\b", to: attrString, color: colors.number)
        
        // 注释
        applyPattern("//.*$", to: attrString, color: colors.comment, options: .anchorsMatchLines)
        applyPattern("/\\*[\\s\\S]*?\\*/", to: attrString, color: colors.comment)
    }

    private func highlightRust(_ attrString: NSMutableAttributedString, colors: SyntaxColors) {
        let keywords = [
            "as", "break", "const", "continue", "crate", "else", "enum", "extern", "false", "fn",
            "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref",
            "return", "self", "Self", "static", "struct", "super", "trait", "true", "type", "unsafe",
            "use", "where", "while", "async", "await", "dyn", "abstract", "become", "box", "do",
            "final", "macro", "override", "priv", "typeof", "unsized", "virtual", "yield"
        ]
        applyPattern("\\b(" + keywords.joined(separator: "|") + ")\\b", to: attrString, color: colors.keyword)
        
        // 类型
        applyPattern("\\b([A-Z][a-zA-Z0-9_]*)\\b", to: attrString, color: colors.type)
        
        // 宏
        applyPattern("\\b\\w+!", to: attrString, color: colors.preprocessor)
        
        // 字符串
        applyPattern("\"(?:[^\"\\\\]|\\\\.)*\"", to: attrString, color: colors.string)
        
        // 数字
        applyPattern("\\b\\d+\\.?\\d*\\b", to: attrString, color: colors.number)
        
        // 注释
        applyPattern("//.*$", to: attrString, color: colors.comment, options: .anchorsMatchLines)
        applyPattern("/\\*[\\s\\S]*?\\*/", to: attrString, color: colors.comment)
    }

    private func highlightCpp(_ attrString: NSMutableAttributedString, colors: SyntaxColors) {
        let keywords = [
            "auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else",
            "enum", "extern", "float", "for", "goto", "if", "int", "long", "register", "return",
            "short", "signed", "sizeof", "static", "struct", "switch", "typedef", "union", "unsigned",
            "void", "volatile", "while", "class", "public", "private", "protected", "virtual",
            "template", "typename", "namespace", "using", "new", "delete", "this", "throw", "try",
            "catch", "const_cast", "dynamic_cast", "reinterpret_cast", "static_cast", "true", "false",
            "nullptr", "inline", "explicit", "friend", "mutable", "operator", "override", "final"
        ]
        applyPattern("\\b(" + keywords.joined(separator: "|") + ")\\b", to: attrString, color: colors.keyword)
        
        // 预处理
        applyPattern("^\\s*#\\w+.*$", to: attrString, color: colors.preprocessor, options: .anchorsMatchLines)
        
        // 字符串
        applyPattern("\"(?:[^\"\\\\]|\\\\.)*\"", to: attrString, color: colors.string)
        
        // 数字
        applyPattern("\\b\\d+\\.?\\d*[fFlLuU]*\\b", to: attrString, color: colors.number)
        
        // 注释
        applyPattern("//.*$", to: attrString, color: colors.comment, options: .anchorsMatchLines)
        applyPattern("/\\*[\\s\\S]*?\\*/", to: attrString, color: colors.comment)
    }

    private func highlightRuby(_ attrString: NSMutableAttributedString, colors: SyntaxColors) {
        let keywords = [
            "def", "class", "module", "end", "if", "elsif", "else", "unless", "case", "when",
            "while", "until", "for", "do", "begin", "rescue", "ensure", "raise", "return",
            "break", "next", "redo", "retry", "yield", "self", "super", "nil", "true", "false",
            "and", "or", "not", "in", "then", "alias", "defined?", "require", "require_relative",
            "include", "extend", "attr_reader", "attr_writer", "attr_accessor", "private", "public", "protected"
        ]
        applyPattern("\\b(" + keywords.joined(separator: "|") + ")\\b", to: attrString, color: colors.keyword)
        
        // 符号
        applyPattern(":\\w+", to: attrString, color: colors.string)
        
        // 字符串
        applyPattern("\"(?:[^\"\\\\]|\\\\.)*\"", to: attrString, color: colors.string)
        applyPattern("'(?:[^'\\\\]|\\\\.)*'", to: attrString, color: colors.string)
        
        // 数字
        applyPattern("\\b\\d+\\.?\\d*\\b", to: attrString, color: colors.number)
        
        // 注释
        applyPattern("#.*$", to: attrString, color: colors.comment, options: .anchorsMatchLines)
    }

    private func highlightJSON(_ attrString: NSMutableAttributedString, colors: SyntaxColors) {
        // 键
        applyPattern("\"[^\"]+\"\\s*:", to: attrString, color: colors.property)
        
        // 字符串值
        applyPattern(":\\s*\"[^\"]*\"", to: attrString, color: colors.string)
        
        // 布尔和 null
        applyPattern("\\b(true|false|null)\\b", to: attrString, color: colors.keyword)
        
        // 数字
        applyPattern("\\b-?\\d+\\.?\\d*([eE][+-]?\\d+)?\\b", to: attrString, color: colors.number)
    }

    private func highlightHTML(_ attrString: NSMutableAttributedString, colors: SyntaxColors) {
        // 标签
        applyPattern("</?\\w+", to: attrString, color: colors.keyword)
        applyPattern("/?>", to: attrString, color: colors.keyword)
        
        // 属性名
        applyPattern("\\b\\w+(?==)", to: attrString, color: colors.property)
        
        // 属性值
        applyPattern("\"[^\"]*\"", to: attrString, color: colors.string)
        applyPattern("'[^']*'", to: attrString, color: colors.string)
        
        // 注释
        applyPattern("<!--[\\s\\S]*?-->", to: attrString, color: colors.comment)
    }

    private func highlightCSS(_ attrString: NSMutableAttributedString, colors: SyntaxColors) {
        // 选择器
        applyPattern("[.#]?[a-zA-Z_][a-zA-Z0-9_-]*\\s*\\{", to: attrString, color: colors.keyword)
        
        // 属性
        applyPattern("\\b[a-z-]+(?=\\s*:)", to: attrString, color: colors.property)
        
        // 值
        applyPattern(":\\s*[^;]+", to: attrString, color: colors.string)
        
        // 数字
        applyPattern("\\b\\d+\\.?\\d*(px|em|rem|%|vh|vw)?\\b", to: attrString, color: colors.number)
        
        // 注释
        applyPattern("/\\*[\\s\\S]*?\\*/", to: attrString, color: colors.comment)
    }

    private func highlightSQL(_ attrString: NSMutableAttributedString, colors: SyntaxColors) {
        let keywords = [
            "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "IN", "LIKE", "BETWEEN", "IS", "NULL",
            "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "DROP",
            "ALTER", "ADD", "INDEX", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "JOIN", "LEFT",
            "RIGHT", "INNER", "OUTER", "ON", "AS", "ORDER", "BY", "ASC", "DESC", "GROUP", "HAVING",
            "LIMIT", "OFFSET", "UNION", "ALL", "DISTINCT", "COUNT", "SUM", "AVG", "MAX", "MIN",
            "select", "from", "where", "and", "or", "not", "in", "like", "between", "is", "null",
            "insert", "into", "values", "update", "set", "delete", "create", "table", "drop",
            "alter", "add", "index", "primary", "key", "foreign", "references", "join", "left",
            "right", "inner", "outer", "on", "as", "order", "by", "asc", "desc", "group", "having",
            "limit", "offset", "union", "all", "distinct", "count", "sum", "avg", "max", "min"
        ]
        applyPattern("\\b(" + keywords.joined(separator: "|") + ")\\b", to: attrString, color: colors.keyword)
        
        // 字符串
        applyPattern("'[^']*'", to: attrString, color: colors.string)
        
        // 数字
        applyPattern("\\b\\d+\\.?\\d*\\b", to: attrString, color: colors.number)
        
        // 注释
        applyPattern("--.*$", to: attrString, color: colors.comment, options: .anchorsMatchLines)
        applyPattern("/\\*[\\s\\S]*?\\*/", to: attrString, color: colors.comment)
    }

    private func highlightShell(_ attrString: NSMutableAttributedString, colors: SyntaxColors) {
        let keywords = [
            "if", "then", "else", "elif", "fi", "case", "esac", "for", "while", "until", "do", "done",
            "in", "function", "return", "exit", "break", "continue", "export", "local", "readonly",
            "shift", "unset", "set", "source", "alias", "cd", "echo", "printf", "read", "eval", "exec",
            "true", "false", "test"
        ]
        applyPattern("\\b(" + keywords.joined(separator: "|") + ")\\b", to: attrString, color: colors.keyword)
        
        // 变量
        applyPattern("\\$\\{?\\w+\\}?", to: attrString, color: colors.property)
        
        // 字符串
        applyPattern("\"(?:[^\"\\\\]|\\\\.)*\"", to: attrString, color: colors.string)
        applyPattern("'[^']*'", to: attrString, color: colors.string)
        
        // 注释
        applyPattern("#.*$", to: attrString, color: colors.comment, options: .anchorsMatchLines)
    }

    private func highlightYAML(_ attrString: NSMutableAttributedString, colors: SyntaxColors) {
        // 键
        applyPattern("^\\s*[\\w-]+(?=\\s*:)", to: attrString, color: colors.property, options: .anchorsMatchLines)
        
        // 布尔和 null
        applyPattern("\\b(true|false|yes|no|null|~)\\b", to: attrString, color: colors.keyword)
        
        // 字符串
        applyPattern("\"[^\"]*\"", to: attrString, color: colors.string)
        applyPattern("'[^']*'", to: attrString, color: colors.string)
        
        // 数字
        applyPattern("\\b\\d+\\.?\\d*\\b", to: attrString, color: colors.number)
        
        // 注释
        applyPattern("#.*$", to: attrString, color: colors.comment, options: .anchorsMatchLines)
    }

    private func highlightGeneric(_ attrString: NSMutableAttributedString, colors: SyntaxColors) {
        // 通用关键词
        let keywords = [
            "if", "else", "for", "while", "do", "switch", "case", "break", "continue", "return",
            "function", "class", "public", "private", "static", "const", "var", "let", "new",
            "true", "false", "null", "nil", "void", "int", "string", "bool", "float", "double"
        ]
        applyPattern("\\b(" + keywords.joined(separator: "|") + ")\\b", to: attrString, color: colors.keyword)
        
        // 字符串
        applyPattern("\"(?:[^\"\\\\]|\\\\.)*\"", to: attrString, color: colors.string)
        applyPattern("'(?:[^'\\\\]|\\\\.)*'", to: attrString, color: colors.string)
        
        // 数字
        applyPattern("\\b\\d+\\.?\\d*\\b", to: attrString, color: colors.number)
        
        // 注释
        applyPattern("//.*$", to: attrString, color: colors.comment, options: .anchorsMatchLines)
        applyPattern("#.*$", to: attrString, color: colors.comment, options: .anchorsMatchLines)
        applyPattern("/\\*[\\s\\S]*?\\*/", to: attrString, color: colors.comment)
    }
    
    func extractHeadings(from document: Document) -> (items: [MarkdownTOCItem], tocSectionId: String?) {
        var items: [MarkdownTOCItem] = []
        var index = 0
        detectedTOCSectionId = nil  // 重置

        extractHeadingsRecursive(from: document, index: &index, items: &items)

        return (items, detectedTOCSectionId)
    }

    private func extractHeadingsRecursive(from markup: any Markup, index: inout Int, items: inout [MarkdownTOCItem]) {
        if let heading = markup as? Heading {
            let title = heading.plainText
            let id = "heading-\(index)"
            
            // 检测是否是“目录”标题
            let tocKeywords = ["目录", "table of contents", "toc", "contents", "索引"]
            let lowerTitle = title.lowercased()
            if tocKeywords.contains(where: { lowerTitle.contains($0) }) {
                detectedTOCSectionId = id  // 记录下来
            }
            
            items.append(MarkdownTOCItem(level: heading.level, title: title, id: id))
            index += 1
        }
        
        for child in markup.children {
            extractHeadingsRecursive(from: child, index: &index, items: &items)
        }
    }
}
