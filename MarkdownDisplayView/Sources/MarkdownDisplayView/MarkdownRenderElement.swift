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
    case codeBlock(language: String?, code: NSAttributedString)  // 添加语言信息支持自定义渲染
    case image(source: String, altText: String)
    case latex(String)  // LaTeX 公式
    indirect case details(summary: String, children: [MarkdownRenderElement])
    case rawHTML(String)
    case list(items: [ListNodeItem], level: Int)
    case custom(CustomElementData)  // 自定义扩展元素
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
struct MarkdownFootnote: Equatable {
    let id: String
    let content: String
}

public enum MarkdownTypewriterTextMode: Sendable {
    case reveal
    case append
}

// MARK: - StreamingHapticFeedbackStyle
/// 流式输出震动反馈级别
public enum StreamingHapticFeedbackStyle: Sendable {
    case none           // 不震动
    case light          // 轻微震动
    case medium         // 中等震动
    case heavy          // 强烈震动
    case soft           // 柔和震动 (iOS 13+)
    case rigid          // 刚性震动 (iOS 13+)

    /// 转换为 UIImpactFeedbackGenerator.FeedbackStyle
    @available(iOS 13.0, *)
    public var impactStyle: UIImpactFeedbackGenerator.FeedbackStyle? {
        switch self {
        case .none:
            return nil
        case .light:
            return .light
        case .medium:
            return .medium
        case .heavy:
            return .heavy
        case .soft:
            return .soft
        case .rigid:
            return .rigid
        }
    }
}

// MARK: - SyntaxHighlightColors
/// 代码高亮颜色配置
public struct SyntaxHighlightColors: Sendable {
    public var keyword: UIColor       // 关键字颜色
    public var string: UIColor        // 字符串颜色
    public var number: UIColor        // 数字颜色
    public var comment: UIColor       // 注释颜色
    public var type: UIColor          // 类型颜色
    public var function: UIColor      // 函数颜色
    public var property: UIColor      // 属性颜色
    public var preprocessor: UIColor  // 预处理器颜色

    public init(
        keyword: UIColor,
        string: UIColor,
        number: UIColor,
        comment: UIColor,
        type: UIColor,
        function: UIColor,
        property: UIColor,
        preprocessor: UIColor
    ) {
        self.keyword = keyword
        self.string = string
        self.number = number
        self.comment = comment
        self.type = type
        self.function = function
        self.property = property
        self.preprocessor = preprocessor
    }

    /// Xcode 浅色主题
    public static var xcode: SyntaxHighlightColors {
        SyntaxHighlightColors(
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

    /// Xcode 深色主题
    public static var xcodeDark: SyntaxHighlightColors {
        SyntaxHighlightColors(
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
    public var linkUnderlineEnabled: Bool = true  // 链接是否显示下划线，默认 true
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
    public var tocTextColor: UIColor              // 目录文字颜色

    public var paragraphSpacing: CGFloat
    public var headingSpacing: CGFloat
    public var listIndent: CGFloat
    public var codeBlockPadding: CGFloat
    public var blockquoteIndent: CGFloat
    public var imageMaxHeight: CGFloat
    public var imagePlaceholderHeight: CGFloat
    public var streamMinModuleLength: Int = 50
    public var typewriterTextMode: MarkdownTypewriterTextMode = .reveal
    public var typewriterHeightUpdateInterval: Int = 20
    
    
    public var lineSpacing: CGFloat // 正文行间距
    public var headingTopSpacing: CGFloat       // 标题上方间距（标题与前一个内容之间的距离）
    public var headingBottomSpacing: CGFloat    // 标题下方间距（标题与后一个内容之间的距离）
    public var paragraphTopSpacing: CGFloat     // 普通段落上方间距
    public var paragraphBottomSpacing: CGFloat = 5 // 普通段落下方间距

    // MARK: - LaTeX 公式配置
    public var latexFontSize: CGFloat = 22      // LaTeX 公式字号
    public var latexAlignment: NSTextAlignment = .center  // LaTeX 公式对齐方式（居中/居左/居右）
    public var latexBackgroundColor: UIColor = UIColor.systemGray6.withAlphaComponent(0.5)  // LaTeX 公式背景颜色
    public var latexPadding: CGFloat = 20       // LaTeX 公式内边距

    // MARK: - 引用块配置
    public var blockquoteBackgroundColor: UIColor = UIColor.systemGray6.withAlphaComponent(0.5)  // 引用块背景颜色
    public var blockquoteBarWidth: CGFloat = 4          // 引用块左侧竖线宽度
    public var blockquoteContentSpacing: CGFloat = 8    // 引用块内容间距
    public var blockquoteContentPadding: CGFloat = 12   // 引用块内容内边距

    // MARK: - 表格配置
    public var tableMinColumnWidth: CGFloat = 80        // 表格最小列宽
    public var tableMaxColumnWidth: CGFloat = 200       // 表格最大列宽
    public var tableRowHeight: CGFloat = 44             // 表格行高
    public var tableCellPadding: CGFloat = 16           // 表格单元格内边距（左右各16）
    public var tableSeparatorHeight: CGFloat = 1        // 表格分隔线高度

    // MARK: - 列表配置
    public var listItemSpacing: CGFloat = 4             // 列表项之间的间距
    public var listMarkerMinWidth: CGFloat = 20         // 列表标记最小宽度
    public var listMarkerSpacing: CGFloat = 4           // 列表标记与内容之间的间距

    // MARK: - Details 折叠块配置
    public var detailsSummaryFont: UIFont = .systemFont(ofSize: 14, weight: .medium)  // 折叠块标题字体
    public var detailsSummaryTextColor: UIColor = .systemBlue  // 折叠块标题文字颜色
    public var detailsSummaryMinHeight: CGFloat = 40    // 折叠块标题最小高度
    public var detailsContentPadding: CGFloat = 12      // 折叠块内容内边距
    public var detailsSpacing: CGFloat = 8              // 折叠块内部间距

    // MARK: - 代码高亮配置
    public var syntaxColors: SyntaxHighlightColors = .xcode  // 代码高亮颜色（浅色主题）
    public var syntaxColorsDark: SyntaxHighlightColors = .xcodeDark  // 代码高亮颜色（深色主题）

    // MARK: - 流式输出震动反馈配置
    /// 流式输出时的震动反馈级别，默认为 .none（不震动）
    public var streamingHapticFeedbackStyle: StreamingHapticFeedbackStyle = .none
    /// 震动反馈的最小间隔时间（秒），避免过于频繁的震动，默认 0.05 秒
    public var streamingHapticMinInterval: TimeInterval = 0.05
    
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
            tocTextColor: .systemBlue,                  // 目录文字颜色（默认与链接颜色一致）
            paragraphSpacing: 12,
            headingSpacing: 16,
            listIndent: 12,
            codeBlockPadding: 12,
            blockquoteIndent: 16,
            imageMaxHeight: 400,
            imagePlaceholderHeight: 150,
            streamMinModuleLength: 50,
            typewriterTextMode: .reveal,
            typewriterHeightUpdateInterval: 20,
            lineSpacing: 6,
            headingTopSpacing: 20,                  // 推荐：标题前留大一点空
            headingBottomSpacing: 12,               // 标题后稍小一点
            paragraphTopSpacing: 8,                 // 普通段落前留一点空
            latexFontSize: 22,                      // LaTeX 公式字号
            latexAlignment: .center,                // LaTeX 公式对齐方式
            latexBackgroundColor: UIColor.systemGray6.withAlphaComponent(0.5),  // LaTeX 公式背景颜色
            latexPadding: 20,                       // LaTeX 公式内边距
            // 引用块配置
            blockquoteBackgroundColor: UIColor.systemGray6.withAlphaComponent(0.5),
            blockquoteBarWidth: 4,
            blockquoteContentSpacing: 8,
            blockquoteContentPadding: 12,
            // 表格配置
            tableMinColumnWidth: 80,
            tableMaxColumnWidth: 200,
            tableRowHeight: 44,
            tableCellPadding: 16,
            tableSeparatorHeight: 1,
            // 列表配置
            listItemSpacing: 4,
            listMarkerMinWidth: 20,
            listMarkerSpacing: 4,
            // Details 折叠块配置
            detailsSummaryFont: .systemFont(ofSize: 14, weight: .medium),
            detailsSummaryTextColor: .systemBlue,       // 折叠块标题文字颜色
            detailsSummaryMinHeight: 40,
            detailsContentPadding: 12,
            detailsSpacing: 8,
            // 代码高亮配置
            syntaxColors: .xcode,
            syntaxColorsDark: .xcodeDark
        )
    }

    public static var dark: MarkdownConfiguration {
        var config = MarkdownConfiguration.default
        config.textColor = .white
        config.headingColor = .white
        config.codeBackgroundColor = UIColor(white: 0.15, alpha: 1)
        config.blockquoteTextColor = UIColor(white: 0.7, alpha: 1)
        config.blockquoteBackgroundColor = UIColor(white: 0.15, alpha: 0.5)
        config.tableHeaderBackgroundColor = UIColor(white: 0.2, alpha: 1)
        config.tableAlternateRowBackgroundColor = UIColor(white: 0.15, alpha: 0.5)
        config.imagePlaceholderColor = UIColor(white: 0.2, alpha: 1)
        config.latexBackgroundColor = UIColor(white: 0.15, alpha: 0.5)
        config.syntaxColors = .xcodeDark
        return config
    }
}



public enum StreamingUnit {
    case character  // 字符
    case word       // 词（推荐）
    case sentence   // 句子
}
