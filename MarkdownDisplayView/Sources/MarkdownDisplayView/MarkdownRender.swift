//
//  MarkdownRender.swift
//  MarkdownDisplayView
//
//  Created by 朱继超 on 12/15/25.
//

import UIKit

/// 协议抽象，隔离 swift-markdown 依赖
public protocol MarkdownParserProtocol {
    func parseAndRender(_ markdown: String) -> (
        elements: [MarkdownRenderElement],
        imageAttachments: [(attachment: MarkdownImageAttachment, urlString: String)],
        tableOfContents: [MarkdownTOCItem],
        tocSectionId: String?
    )
}

/// Markdown 预渲染结果，可在后台提前生成后交给 `MarkdownViewTextKit` 直接显示。
public struct MarkdownPreparedContent {
    public let elements: [MarkdownRenderElement]
    public let imageAttachments: [(attachment: MarkdownImageAttachment, urlString: String)]
    public let tableOfContents: [MarkdownTOCItem]
    public let tocSectionId: String?
    public let preparedWidth: CGFloat
    public let estimatedElementHeights: [CGFloat]
    public let estimatedTotalHeight: CGFloat

    let fixedTextHeights: [CGFloat?]

    init(
        elements: [MarkdownRenderElement],
        imageAttachments: [(attachment: MarkdownImageAttachment, urlString: String)],
        tableOfContents: [MarkdownTOCItem],
        tocSectionId: String?,
        preparedWidth: CGFloat,
        estimatedElementHeights: [CGFloat],
        fixedTextHeights: [CGFloat?]
    ) {
        self.elements = elements
        self.imageAttachments = imageAttachments
        self.tableOfContents = tableOfContents
        self.tocSectionId = tocSectionId
        self.preparedWidth = preparedWidth
        self.estimatedElementHeights = estimatedElementHeights
        self.estimatedTotalHeight = estimatedElementHeights.reduce(0, +)
        self.fixedTextHeights = fixedTextHeights
    }
}


/// 外部可见的主渲染器，不直接依赖 swift-markdown
public final class MarkdownRenderer {

    private let configuration: MarkdownConfiguration
    private let containerWidth: CGFloat
    private let parser: MarkdownParserProtocol

    /// 占位符前缀（使用不会被 Markdown 解析的格式）
    private static let placeholderPrefix = "CUSTOMEXT"
    private static let placeholderSuffix = "ENDEXT"

    public init(configuration: MarkdownConfiguration = MarkdownConfiguration.default,
                containerWidth: CGFloat) {
        self.configuration = configuration
        self.containerWidth = containerWidth
        self.parser = MarkdownParser(configuration: configuration, containerWidth: containerWidth)
    }

    /// 外部调用入口：传入 Markdown 字符串
    public func render(_ markdown: String) -> (
        elements: [MarkdownRenderElement],
        imageAttachments: [(attachment: MarkdownImageAttachment, urlString: String)],
        tableOfContents: [MarkdownTOCItem],
        tocSectionId: String?
    ) {
        // 1. 预处理：修复常见坏格式（如表格中断）
        let normalizedMarkdown = configuration.autoFixMalformedTables
            ? normalizeMalformedTables(in: markdown)
            : markdown

        // 2. 预处理：识别自定义语法并替换为占位符
        let (preprocessedMarkdown, customDataMap) = preprocessCustomSyntax(in: normalizedMarkdown)

        // 3. 解析预处理后的 Markdown
        var result = parser.parseAndRender(preprocessedMarkdown)

        // 🔷 调试：打印解析后的元素，查找占位符
        // 整段守卫而非仅守卫 mdLog：循环本身是 elements × placeholders 的全文 contains，
        // release 下必须完全跳过
        #if DEBUG
        if mdVerboseLoggingEnabled {
            mdLog("🔷[MDEXT] ===== Parsed Elements (looking for placeholders) =====")
            for (idx, element) in result.elements.enumerated() {
                switch element {
                case .attributedText(let attr):
                    let text = attr.string
                    for placeholder in customDataMap.keys {
                        if text.contains(placeholder) {
                            mdLog("🔷[MDEXT] 📍 Element[\(idx)] attributedText CONTAINS '\(placeholder)'")
                            mdLog("🔷[MDEXT]    Full text: '\(text.replacingOccurrences(of: "\n", with: "⏎"))'")
                        }
                    }
                case .heading(_, let attr):
                    let text = attr.string
                    for placeholder in customDataMap.keys {
                        if text.contains(placeholder) {
                            mdLog("🔷[MDEXT] 📍 Element[\(idx)] heading CONTAINS '\(placeholder)'")
                        }
                    }
                default:
                    break
                }
            }
            mdLog("🔷[MDEXT] ===== End Parsed Elements =====")
        }
        #endif

        // 4. 后处理：将占位符替换为自定义元素
        if !customDataMap.isEmpty {
            result.elements = restoreCustomElements(in: result.elements, customDataMap: customDataMap)
        }

        return result
    }

    /// 预处理 Markdown，生成可复用的渲染元素和按当前宽度估算的高度。
    public func prepare(_ markdown: String) -> MarkdownPreparedContent {
        let result = render(markdown)
        let estimates = result.elements.map { estimateElementHeight($0, containerWidth: containerWidth) }

        return MarkdownPreparedContent(
            elements: result.elements,
            imageAttachments: result.imageAttachments,
            tableOfContents: result.tableOfContents,
            tocSectionId: result.tocSectionId,
            preparedWidth: containerWidth,
            estimatedElementHeights: estimates.map(\.totalHeight),
            fixedTextHeights: estimates.map(\.fixedTextHeight)
        )
    }

    private func estimateElementHeight(
        _ element: MarkdownRenderElement,
        containerWidth: CGFloat
    ) -> (totalHeight: CGFloat, fixedTextHeight: CGFloat?) {
        switch element {
        case .attributedText(let text):
            let size = text.boundingRect(
                with: CGSize(width: containerWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).size
            let textHeight = ceil(size.height)
            return (
                textHeight + configuration.paragraphSpacing + configuration.paragraphTopSpacing + configuration.paragraphBottomSpacing,
                textHeight
            )

        case .heading(_, let text):
            let size = text.boundingRect(
                with: CGSize(width: containerWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).size
            let textHeight = ceil(size.height)
            return (
                textHeight + configuration.headingTopSpacing + configuration.headingBottomSpacing,
                textHeight
            )

        case .quote(let children, _):
            let childrenHeight = children.reduce(CGFloat(0)) {
                $0 + estimateElementHeight($1, containerWidth: containerWidth - 40).totalHeight
            }
            return (childrenHeight + 24, nil)

        case .codeBlock(_, let code):
            let lines = code.string.components(separatedBy: .newlines).count
            return (CGFloat(lines) * 20 + 40, nil)

        case .table(let data):
            let tableResult = MarkdownTableLayoutCalculator.calculate(
                data: data,
                config: configuration,
                containerWidth: containerWidth
            )
            return (tableResult.totalSize.height, nil)

        case .list(let items, _):
            var totalHeight: CGFloat = 0
            for item in items {
                if item.children.isEmpty {
                    totalHeight += 28
                } else {
                    totalHeight += item.children.reduce(CGFloat(0)) {
                        $0 + estimateElementHeight($1, containerWidth: containerWidth - 32).totalHeight
                    }
                }
            }
            return (max(totalHeight, CGFloat(items.count) * 28), nil)

        case .thematicBreak:
            return (24, nil)

        case .image:
            return (configuration.imagePlaceholderHeight + 16, nil)

        case .latex:
            return (80, nil)

        case .details:
            return (56, nil)

        case .rawHTML:
            return (100, nil)

        case .custom(let data):
            if let provider = MarkdownCustomExtensionManager.shared.viewProvider(for: data.type) {
                return (provider.calculateSize(for: data, configuration: configuration, containerWidth: containerWidth).height, nil)
            }
            return (100, nil)
        }
    }

    // MARK: - 预处理：占位符替换策略

    /// 修复常见的表格断裂输入：
    /// 1) 表头后插入孤立 `|` 行
    /// 2) 表格内部被误插入空行
    /// 仅在普通 Markdown 上生效，不处理 fenced code block 内文本。
    private func normalizeMalformedTables(in markdown: String) -> String {
        let lines = markdown.components(separatedBy: .newlines)
        guard lines.count > 2 else { return markdown }

        var normalized: [String] = []
        var index = 0
        var activeFenceMarker: Character?

        while index < lines.count {
            let line = lines[index]

            if let fenceMarker = codeFenceMarker(in: line) {
                if activeFenceMarker == nil {
                    activeFenceMarker = fenceMarker
                } else if activeFenceMarker == fenceMarker {
                    activeFenceMarker = nil
                }
                normalized.append(line)
                index += 1
                continue
            }

            if activeFenceMarker != nil {
                normalized.append(line)
                index += 1
                continue
            }

            if index + 1 < lines.count,
               isLikelyTableRow(lines[index]),
               isTableSeparatorRow(lines[index + 1]) {
                normalized.append(lines[index])
                normalized.append(lines[index + 1])
                index += 2

                while index < lines.count {
                    let currentLine = lines[index]
                    let trimmed = currentLine.trimmingCharacters(in: .whitespaces)

                    // 修复孤立的 `|` 行
                    if isStandalonePipeLine(trimmed) {
                        index += 1
                        continue
                    }

                    if trimmed.isEmpty {
                        // 如果后续还是表格行，则认为这是误插入空行，跳过
                        if let nextNonEmpty = nextNonEmptyLineIndex(in: lines, from: index + 1),
                           isLikelyTableRow(lines[nextNonEmpty]) {
                            index += 1
                            continue
                        }
                        // 否则视为表格结束，保留空行
                        normalized.append(currentLine)
                        index += 1
                        break
                    }

                    if isLikelyTableRow(currentLine) {
                        normalized.append(currentLine)
                        index += 1
                        continue
                    }

                    // 非表格行，表格结束
                    normalized.append(currentLine)
                    index += 1
                    break
                }
                continue
            }

            normalized.append(line)
            index += 1
        }

        return normalized.joined(separator: "\n")
    }

    private func codeFenceMarker(in line: String) -> Character? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let fenceCount = trimmed.prefix { $0 == first }.count
        return fenceCount >= 3 ? first : nil
    }

    private func isLikelyTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.contains("|") else { return false }

        let cells = trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let nonEmptyCellCount = cells.filter { !$0.isEmpty }.count
        return nonEmptyCellCount >= 2
    }

    private func isTableSeparatorRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return false }

        let cells = trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard cells.count >= 2 else { return false }
        return cells.allSatisfy { isTableSeparatorCell($0) }
    }

    private func isTableSeparatorCell(_ cell: String) -> Bool {
        let stripped = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        guard stripped.count >= 3 else { return false }
        return stripped.allSatisfy { $0 == "-" }
    }

    private func isStandalonePipeLine(_ trimmedLine: String) -> Bool {
        guard !trimmedLine.isEmpty, trimmedLine.contains("|") else { return false }
        return trimmedLine.allSatisfy { $0 == "|" || $0.isWhitespace }
    }

    private func nextNonEmptyLineIndex(in lines: [String], from start: Int) -> Int? {
        guard start < lines.count else { return nil }
        for idx in start..<lines.count {
            if !lines[idx].trimmingCharacters(in: .whitespaces).isEmpty {
                return idx
            }
        }
        return nil
    }

    /// 预处理：扫描自定义语法，替换为占位符
    private func preprocessCustomSyntax(in markdown: String) -> (String, [String: CustomElementData]) {
        let customMatches = MarkdownCustomExtensionManager.shared.preprocessCustomElements(in: markdown)
        mdLog("🔷[MDEXT] preprocessCustomSyntax: found \(customMatches.count) custom matches")
        guard !customMatches.isEmpty else { return (markdown, [:]) }

        var processedMarkdown = markdown
        var customDataMap: [String: CustomElementData] = [:]

        // 从后往前替换，避免位置偏移问题
        let sortedMatches = customMatches.sorted { $0.range.location > $1.range.location }

        for (index, (range, data)) in sortedMatches.enumerated() {
            let placeholder = "\(Self.placeholderPrefix)\(index)\(Self.placeholderSuffix)"
            customDataMap[placeholder] = data
            mdLog("🔷[MDEXT] placeholder[\(index)]: '\(placeholder)' -> type=\(data.type), raw=\(data.rawText), NSRange=\(range)")

            if let swiftRange = Range(range, in: processedMarkdown) {
                let originalText = String(processedMarkdown[swiftRange])
                processedMarkdown.replaceSubrange(swiftRange, with: placeholder)
                mdLog("🔷[MDEXT] ✅ replaced '\(originalText)' with '\(placeholder)'")
            } else {
                mdLog("🔷[MDEXT] ❌ FAILED to convert NSRange to Range!")
            }
        }

        // 打印替换后 markdown 中占位符周围的内容
        for (placeholder, _) in customDataMap {
            if let range = processedMarkdown.range(of: placeholder) {
                let start = processedMarkdown.index(range.lowerBound, offsetBy: -30, limitedBy: processedMarkdown.startIndex) ?? processedMarkdown.startIndex
                let end = processedMarkdown.index(range.upperBound, offsetBy: 30, limitedBy: processedMarkdown.endIndex) ?? processedMarkdown.endIndex
                let context = String(processedMarkdown[start..<end]).replacingOccurrences(of: "\n", with: "⏎")
                mdLog("🔷[MDEXT] context for '\(placeholder)': ...\(context)...")
            }
        }

        return (processedMarkdown, customDataMap)
    }

    /// 后处理：将占位符替换为自定义元素
    private func restoreCustomElements(
        in elements: [MarkdownRenderElement],
        customDataMap: [String: CustomElementData]
    ) -> [MarkdownRenderElement] {
        mdLog("🔷[MDEXT] restoreCustomElements: \(elements.count) elements, \(customDataMap.count) placeholders")
        var newElements: [MarkdownRenderElement] = []

        for element in elements {
            switch element {
            case .attributedText(let attrString):
                let text = attrString.string
                mdLog("🔷[MDEXT] checking attributedText: '\(text.prefix(50))...'")

                // 查找文本中位置最靠前的占位符
                var foundPlaceholder: (placeholder: String, data: CustomElementData, position: Int)? = nil
                for (placeholder, data) in customDataMap {
                    if let range = text.range(of: placeholder) {
                        let position = text.distance(from: text.startIndex, to: range.lowerBound)
                        if foundPlaceholder == nil || position < foundPlaceholder!.position {
                            foundPlaceholder = (placeholder, data, position)
                        }
                    }
                }

                if let found = foundPlaceholder {
                    mdLog("🔷[MDEXT] ✅ FOUND placeholder '\(found.placeholder)' at position \(found.position)")
                    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    mdLog("🔷[MDEXT] trimmedText='\(trimmedText.prefix(80))...', placeholder='\(found.placeholder)'")

                    // 如果整段只有占位符，直接替换为自定义元素
                    if trimmedText == found.placeholder {
                        mdLog("🔷[MDEXT] ✅ replacing entire text with .custom element")
                        newElements.append(.custom(found.data))
                    } else {
                        mdLog("🔷[MDEXT] 🔀 splitting text around placeholder...")
                        // 拆分：前文本 + 自定义元素 + 后文本
                        if let placeholderRange = text.range(of: found.placeholder) {
                            let beforeText = String(text[..<placeholderRange.lowerBound])
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            let afterText = String(text[placeholderRange.upperBound...])
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            mdLog("🔷[MDEXT] beforeText='\(beforeText.prefix(30))', afterText='\(afterText.prefix(30))'")

                            if !beforeText.isEmpty {
                                let beforeAttr = NSAttributedString(string: beforeText, attributes: [
                                    .font: configuration.bodyFont,
                                    .foregroundColor: configuration.textColor
                                ])
                                newElements.append(.attributedText(beforeAttr))
                            }

                            mdLog("🔷[MDEXT] ✅ appending .custom element after split")
                            newElements.append(.custom(found.data))

                            // 递归处理 afterText，因为可能还有其他占位符
                            if !afterText.isEmpty {
                                let afterAttr = NSAttributedString(string: afterText, attributes: [
                                    .font: configuration.bodyFont,
                                    .foregroundColor: configuration.textColor
                                ])
                                // 递归调用以处理剩余占位符
                                let processedAfter = restoreCustomElements(
                                    in: [.attributedText(afterAttr)],
                                    customDataMap: customDataMap
                                )
                                newElements.append(contentsOf: processedAfter)
                            }
                        } else {
                            mdLog("🔷[MDEXT] ❌ placeholderRange not found!")
                            newElements.append(element)
                        }
                    }
                } else {
                    newElements.append(element)
                }

            case .quote(let children, let level):
                let processedChildren = restoreCustomElements(in: children, customDataMap: customDataMap)
                newElements.append(.quote(children: processedChildren, level: level))

            case .details(let summary, let children):
                let processedChildren = restoreCustomElements(in: children, customDataMap: customDataMap)
                newElements.append(.details(summary: summary, children: processedChildren))

            case .list(let items, let level):
                let processedItems = items.map { item in
                    ListNodeItem(
                        marker: item.marker,
                        children: restoreCustomElements(in: item.children, customDataMap: customDataMap)
                    )
                }
                newElements.append(.list(items: processedItems, level: level))

            default:
                newElements.append(element)
            }
        }

        return newElements
    }
}
