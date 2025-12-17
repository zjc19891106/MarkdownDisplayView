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
        return parser.parseAndRender(markdown)
    }
}
