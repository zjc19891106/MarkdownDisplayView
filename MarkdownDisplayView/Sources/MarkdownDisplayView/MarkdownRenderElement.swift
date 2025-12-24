//
//  File.swift
//  MyLibrary
//
//  Created by 朱继超 on 12/15/25.
//

import Foundation
import UIKit

/// 表格数据
public struct MarkdownTableData: Equatable {
    var headers: [NSAttributedString]
    var rows: [[NSAttributedString]]
}

public struct ListNodeItem: Equatable {
    let marker: String // 例如 "1." 或 "•"
    let children: [MarkdownRenderElement] // 递归包含其他元素
    
    public static func == (lhs: ListNodeItem, rhs: ListNodeItem) -> Bool {
        return lhs.marker == rhs.marker && lhs.children == rhs.children
    }
}

public enum MarkdownRenderElement: Equatable {
    case attributedText(NSAttributedString)
    case table(MarkdownTableData)
    case heading(id: String, text: NSAttributedString)
    indirect case quote(children: [MarkdownRenderElement], level: Int)  // 支持嵌套块级元素
    case thematicBreak
    case codeBlock(NSAttributedString)
    case image(source: String, altText: String)
    case latex(String)  // LaTeX 公式
    indirect case details(summary: String, children: [MarkdownRenderElement])
    case rawHTML(String)
    case list(items: [ListNodeItem], level: Int)
}

// MARK: - MarkdownTOCItemTK2

/// 目录项
public struct MarkdownTOCItem {
    public let level: Int
    public let title: String
    public let id: String
}

// MARK: - MarkdownFootnoteTK2

/// 脚注数据
struct MarkdownFootnote {
    let id: String
    let content: String
}

// MARK: - MarkdownConfiguration
public struct MarkdownConfiguration: Sendable {
    
    public var bodyFont: UIFont
    public var h1Font: UIFont
    public var h2Font: UIFont
    public var h3Font: UIFont
    public var h4Font: UIFont
    public var h5Font: UIFont
    public var h6Font: UIFont
    public var codeFont: UIFont
    public var blockquoteFont: UIFont
    
    public var textColor: UIColor
    public var headingColor: UIColor
    public var linkColor: UIColor
    public var codeTextColor: UIColor
    public var codeBackgroundColor: UIColor
    public var blockquoteTextColor: UIColor
    public var blockquoteBarColor: UIColor
    public var tableBorderColor: UIColor
    public var tableHeaderBackgroundColor: UIColor
    public var tableRowBackgroundColor: UIColor
    public var tableAlternateRowBackgroundColor: UIColor
    public var horizontalRuleColor: UIColor
    public var imagePlaceholderColor: UIColor
    public var footnoteColor: UIColor
    
    public var paragraphSpacing: CGFloat
    public var headingSpacing: CGFloat
    public var listIndent: CGFloat
    public var codeBlockPadding: CGFloat
    public var blockquoteIndent: CGFloat
    public var imageMaxHeight: CGFloat
    public var imagePlaceholderHeight: CGFloat
    
    
    public var headingTopSpacing: CGFloat       // 标题上方间距（标题与前一个内容之间的距离）
    public var headingBottomSpacing: CGFloat    // 标题下方间距（标题与后一个内容之间的距离）
    public var paragraphTopSpacing: CGFloat     // 普通段落上方间距
    public var paragraphBottomSpacing: CGFloat = 5 // 普通段落下方间距
    
    public static var `default`: MarkdownConfiguration {
        MarkdownConfiguration(
            bodyFont: .systemFont(ofSize: 16),
            h1Font: .systemFont(ofSize: 28, weight: .bold),
            h2Font: .systemFont(ofSize: 24, weight: .bold),
            h3Font: .systemFont(ofSize: 20, weight: .semibold),
            h4Font: .systemFont(ofSize: 18, weight: .semibold),
            h5Font: .systemFont(ofSize: 16, weight: .medium),
            h6Font: .systemFont(ofSize: 14, weight: .medium),
            codeFont: .monospacedSystemFont(ofSize: 14, weight: .regular),
            blockquoteFont: .italicSystemFont(ofSize: 16),
            textColor: .label,
            headingColor: .label,
            linkColor: .systemBlue,
            codeTextColor: .label,
            codeBackgroundColor: UIColor.systemGray6,
            blockquoteTextColor: .secondaryLabel,
            blockquoteBarColor: .systemGray3,
            tableBorderColor: .systemGray4,
            tableHeaderBackgroundColor: UIColor.systemGray5,
            tableRowBackgroundColor: .clear,
            tableAlternateRowBackgroundColor: UIColor.systemGray6.withAlphaComponent(0.5),
            horizontalRuleColor: .systemGray4,
            imagePlaceholderColor: UIColor.systemGray5,
            footnoteColor: .secondaryLabel,
            paragraphSpacing: 12,
            headingSpacing: 16,
            listIndent: 12,
            codeBlockPadding: 12,
            blockquoteIndent: 16,
            imageMaxHeight: 400,
            imagePlaceholderHeight: 150,
            headingTopSpacing: 20,                  // 推荐：标题前留大一点空
            headingBottomSpacing: 12,               // 标题后稍小一点
            paragraphTopSpacing: 8,                 // 普通段落前留一点空
        )
    }
    
    public static var dark: MarkdownConfiguration {
        var config = MarkdownConfiguration.default
        config.textColor = .white
        config.headingColor = .white
        config.codeBackgroundColor = UIColor(white: 0.15, alpha: 1)
        config.blockquoteTextColor = UIColor(white: 0.7, alpha: 1)
        config.tableHeaderBackgroundColor = UIColor(white: 0.2, alpha: 1)
        config.tableAlternateRowBackgroundColor = UIColor(white: 0.15, alpha: 0.5)
        config.imagePlaceholderColor = UIColor(white: 0.2, alpha: 1)
        return config
    }
}



public enum StreamingUnit {
    case character  // 字符
    case word       // 词（推荐）
    case sentence   // 句子
}
