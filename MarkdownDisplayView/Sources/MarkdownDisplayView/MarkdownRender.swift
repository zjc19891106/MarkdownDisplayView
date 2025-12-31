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
        // 1. 预处理：识别自定义语法并替换为占位符
        let (preprocessedMarkdown, customDataMap) = preprocessCustomSyntax(in: markdown)

        // 2. 解析预处理后的 Markdown
        var result = parser.parseAndRender(preprocessedMarkdown)

        // 🔷 调试：打印解析后的元素，查找占位符
        print("🔷[MDEXT] ===== Parsed Elements (looking for placeholders) =====")
        for (idx, element) in result.elements.enumerated() {
            switch element {
            case .attributedText(let attr):
                let text = attr.string
                for placeholder in customDataMap.keys {
                    if text.contains(placeholder) {
                        print("🔷[MDEXT] 📍 Element[\(idx)] attributedText CONTAINS '\(placeholder)'")
                        print("🔷[MDEXT]    Full text: '\(text.replacingOccurrences(of: "\n", with: "⏎"))'")
                    }
                }
            case .heading(let id, let attr):
                let text = attr.string
                for placeholder in customDataMap.keys {
                    if text.contains(placeholder) {
                        print("🔷[MDEXT] 📍 Element[\(idx)] heading CONTAINS '\(placeholder)'")
                    }
                }
            default:
                break
            }
        }
        print("🔷[MDEXT] ===== End Parsed Elements =====")

        // 3. 后处理：将占位符替换为自定义元素
        if !customDataMap.isEmpty {
            result.elements = restoreCustomElements(in: result.elements, customDataMap: customDataMap)
        }

        return result
    }

    // MARK: - 预处理：占位符替换策略

    /// 预处理：扫描自定义语法，替换为占位符
    private func preprocessCustomSyntax(in markdown: String) -> (String, [String: CustomElementData]) {
        let customMatches = MarkdownCustomExtensionManager.shared.preprocessCustomElements(in: markdown)
        print("🔷[MDEXT] preprocessCustomSyntax: found \(customMatches.count) custom matches")
        guard !customMatches.isEmpty else { return (markdown, [:]) }

        var processedMarkdown = markdown
        var customDataMap: [String: CustomElementData] = [:]

        // 从后往前替换，避免位置偏移问题
        let sortedMatches = customMatches.sorted { $0.range.location > $1.range.location }

        for (index, (range, data)) in sortedMatches.enumerated() {
            let placeholder = "\(Self.placeholderPrefix)\(index)\(Self.placeholderSuffix)"
            customDataMap[placeholder] = data
            print("🔷[MDEXT] placeholder[\(index)]: '\(placeholder)' -> type=\(data.type), raw=\(data.rawText), NSRange=\(range)")

            if let swiftRange = Range(range, in: processedMarkdown) {
                let originalText = String(processedMarkdown[swiftRange])
                processedMarkdown.replaceSubrange(swiftRange, with: placeholder)
                print("🔷[MDEXT] ✅ replaced '\(originalText)' with '\(placeholder)'")
            } else {
                print("🔷[MDEXT] ❌ FAILED to convert NSRange to Range!")
            }
        }

        // 打印替换后 markdown 中占位符周围的内容
        for (placeholder, _) in customDataMap {
            if let range = processedMarkdown.range(of: placeholder) {
                let start = processedMarkdown.index(range.lowerBound, offsetBy: -30, limitedBy: processedMarkdown.startIndex) ?? processedMarkdown.startIndex
                let end = processedMarkdown.index(range.upperBound, offsetBy: 30, limitedBy: processedMarkdown.endIndex) ?? processedMarkdown.endIndex
                let context = String(processedMarkdown[start..<end]).replacingOccurrences(of: "\n", with: "⏎")
                print("🔷[MDEXT] context for '\(placeholder)': ...\(context)...")
            }
        }

        return (processedMarkdown, customDataMap)
    }

    /// 后处理：将占位符替换为自定义元素
    private func restoreCustomElements(
        in elements: [MarkdownRenderElement],
        customDataMap: [String: CustomElementData]
    ) -> [MarkdownRenderElement] {
        print("🔷[MDEXT] restoreCustomElements: \(elements.count) elements, \(customDataMap.count) placeholders")
        var newElements: [MarkdownRenderElement] = []

        for element in elements {
            switch element {
            case .attributedText(let attrString):
                let text = attrString.string
                print("🔷[MDEXT] checking attributedText: '\(text.prefix(50))...'")

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
                    print("🔷[MDEXT] ✅ FOUND placeholder '\(found.placeholder)' at position \(found.position)")
                    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    print("🔷[MDEXT] trimmedText='\(trimmedText.prefix(80))...', placeholder='\(found.placeholder)'")

                    // 如果整段只有占位符，直接替换为自定义元素
                    if trimmedText == found.placeholder {
                        print("🔷[MDEXT] ✅ replacing entire text with .custom element")
                        newElements.append(.custom(found.data))
                    } else {
                        print("🔷[MDEXT] 🔀 splitting text around placeholder...")
                        // 拆分：前文本 + 自定义元素 + 后文本
                        if let placeholderRange = text.range(of: found.placeholder) {
                            let beforeText = String(text[..<placeholderRange.lowerBound])
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            let afterText = String(text[placeholderRange.upperBound...])
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            print("🔷[MDEXT] beforeText='\(beforeText.prefix(30))', afterText='\(afterText.prefix(30))'")

                            if !beforeText.isEmpty {
                                let beforeAttr = NSAttributedString(string: beforeText, attributes: [
                                    .font: configuration.bodyFont,
                                    .foregroundColor: configuration.textColor
                                ])
                                newElements.append(.attributedText(beforeAttr))
                            }

                            print("🔷[MDEXT] ✅ appending .custom element after split")
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
                            print("🔷[MDEXT] ❌ placeholderRange not found!")
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
