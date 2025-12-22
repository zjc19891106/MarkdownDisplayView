//
//  LaTeXAttachment.swift
//  MarkdownDisplayView
//
//  Created by AI Assistant on 12/19/25.
//

import UIKit

/// LaTeX 公式附件，用于在 TextKit 2 中显示数学公式
@available(iOS 15.0, *)
public final class LaTeXAttachment: NSTextAttachment {

    /// LaTeX 公式内容
    let latex: String

    /// 字体大小
    let fontSize: CGFloat

    /// 容器最大宽度（用于滚动）
    let maxWidth: CGFloat

    /// 内边距
    let padding: CGFloat

    /// 背景颜色
    let backgroundColor: UIColor

    /// 公式视图的计算尺寸
    private var calculatedSize: CGSize = .zero

    /// 初始化 LaTeX 附件
    /// - Parameters:
    ///   - latex: LaTeX 公式字符串
    ///   - fontSize: 字体大小
    ///   - maxWidth: 最大宽度
    ///   - padding: 内边距
    ///   - backgroundColor: 背景颜色
    public init(
        latex: String,
        fontSize: CGFloat = 22,
        maxWidth: CGFloat,
        padding: CGFloat = 20,
        backgroundColor: UIColor = UIColor.systemGray6.withAlphaComponent(0.5)
    ) {
        self.latex = latex
        self.fontSize = fontSize
        self.maxWidth = maxWidth
        self.padding = padding
        self.backgroundColor = backgroundColor

        super.init(data: nil, ofType: nil)

        // 计算公式尺寸
        self.calculatedSize = LatexMathView.calculateSize(
            latex: latex,
            fontSize: fontSize,
            padding: padding
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 返回附件的边界
    public override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        // 返回独立一行的尺寸
        let width = min(calculatedSize.width, maxWidth)
        let height = calculatedSize.height

        return CGRect(x: 0, y: 0, width: width, height: height)
    }
}

/// LaTeX 附件视图提供者
@available(iOS 15.0, *)
public final class LaTeXAttachmentViewProvider: NSTextAttachmentViewProvider {

    override public init(
        textAttachment: NSTextAttachment,
        parentView: UIView?,
        textLayoutManager: NSTextLayoutManager?,
        location: NSTextLocation
    ) {
        super.init(
            textAttachment: textAttachment,
            parentView: parentView,
            textLayoutManager: textLayoutManager,
            location: location
        )
    }

    /// 加载视图
    override public func loadView() {
        super.loadView()
        tracksTextAttachmentViewBounds = true
        guard let attachment = textAttachment as? LaTeXAttachment else {
            self.view = UIView()
            return
        }

        // 使用 LatexMathView 的 createScrollableView 方法创建视图
        let formulaView = LatexMathView.createScrollableView(
            latex: attachment.latex,
            fontSize: attachment.fontSize,
            maxWidth: attachment.maxWidth,
            padding: attachment.padding,
            backgroundColor: attachment.backgroundColor
        )

        // 设置视图属性
        formulaView.translatesAutoresizingMaskIntoConstraints = false
        
        self.view = formulaView
    }

    
}
