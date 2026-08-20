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

    /// 公式的默认前景色
    let textColor: UIColor

    /// 圆角与边框外观，不参与公式测量。
    let appearance: MarkdownBlockAppearance

    /// 测量和绘制全链路共享的唯一渲染结果。
    let renderResult: LatexRenderResult

    /// 是否为行内公式（行内时按行片段宽度缩放、按 inlineCapHeight 垂直对齐，块级时整行显示）
    let isInline: Bool

    /// 行内公式垂直居中参照的正文 capHeight。块级公式忽略此值。
    let inlineCapHeight: CGFloat

    /// 缓存的 ViewProvider 实例（避免重复创建）
    private weak var cachedViewProvider: LaTeXAttachmentViewProvider?

    /// 初始化 LaTeX 附件
    /// - Parameters:
    ///   - latex: LaTeX 公式字符串
    ///   - fontSize: 字体大小
    ///   - maxWidth: 最大宽度
    ///   - padding: 内边距
    ///   - backgroundColor: 背景颜色
    public convenience init(
        latex: String,
        fontSize: CGFloat = 22,
        maxWidth: CGFloat,
        padding: CGFloat = 20,
        backgroundColor: UIColor = UIColor.systemGray6.withAlphaComponent(0.5),
        textColor: UIColor = .label,
        appearance: MarkdownBlockAppearance = MarkdownBlockAppearance(cornerRadius: 8),
        isInline: Bool = false,
        inlineCapHeight: CGFloat = 0
    ) {
        let calcStart = CFAbsoluteTimeGetCurrent()
        let renderResult = LatexRenderResult.parse(
            latex: latex,
            fontSize: fontSize,
            padding: padding,
            maxWidth: maxWidth
        )
        mdLog("[STREAM] 📐📐📐 LaTeXAttachment 解析与尺寸计算耗时: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - calcStart) * 1000))ms")
        self.init(
            latex: latex,
            fontSize: fontSize,
            maxWidth: maxWidth,
            padding: padding,
            backgroundColor: backgroundColor,
            textColor: textColor,
            appearance: appearance,
            renderResult: renderResult,
            isInline: isInline,
            inlineCapHeight: inlineCapHeight
        )
    }

    init(
        latex: String,
        fontSize: CGFloat,
        maxWidth: CGFloat,
        padding: CGFloat,
        backgroundColor: UIColor,
        textColor: UIColor = .label,
        appearance: MarkdownBlockAppearance = MarkdownBlockAppearance(cornerRadius: 8),
        renderResult: LatexRenderResult,
        isInline: Bool = false,
        inlineCapHeight: CGFloat = 0
    ) {
        let initStart = CFAbsoluteTimeGetCurrent()
        mdLog("[STREAM] 📐📐📐 LaTeXAttachment 初始化开始: \(latex.prefix(40))...")

        self.latex = latex
        self.fontSize = fontSize
        self.maxWidth = maxWidth
        self.padding = padding
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.appearance = appearance
        self.renderResult = renderResult
        self.isInline = isInline
        self.inlineCapHeight = inlineCapHeight

        super.init(data: nil, ofType: nil)

        // Set an empty image to prevent the default placeholder icon from appearing
        self.image = UIImage()

        // ⚡️ 注册 ViewProvider 类
        self.lineLayoutPadding = 0

        mdLog("[STREAM] 📐📐📐 LaTeXAttachment 初始化完成，总耗时: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - initStart) * 1000))ms")
    }

    /// 提供自定义 ViewProvider（缓存实例避免重复创建）
    public override func viewProvider(
        for parentView: UIView?,
        location: any NSTextLocation,
        textContainer: NSTextContainer?
    ) -> NSTextAttachmentViewProvider? {
        // ⚡️ 如果已有缓存实例，直接返回
        if let cached = cachedViewProvider {
            return cached
        }

        // 创建新实例并缓存
        let provider = LaTeXAttachmentViewProvider(
            textAttachment: self,
            parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager,
            location: location
        )
        cachedViewProvider = provider
        return provider
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
        if isInline {
            // 行内公式：宽度按实际行片段宽度（嵌套容器内是子容器宽度）裁剪，超出则等比缩放
            var size = renderResult.contentSize
            let availableWidth = max(1, lineFrag.width)
            if size.width > availableWidth {
                let scale = availableWidth / size.width
                size = CGSize(width: availableWidth, height: size.height * scale)
            }
            // 垂直居中：以正文 capHeight 为参照，使公式视觉中心与文字对齐
            let originY = (inlineCapHeight - size.height) / 2
            return CGRect(x: 0, y: originY, width: size.width, height: size.height)
        }
        // 块级公式：整行显示（origin.y = 0，附件底边贴基线）
        return CGRect(origin: .zero, size: renderResult.displaySize)
    }
}

/// LaTeX 附件视图提供者
@available(iOS 15.0, *)
public final class LaTeXAttachmentViewProvider: NSTextAttachmentViewProvider {

    /// 标记视图是否已经创建过
    private var isViewLoaded = false

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
        let loadStart = CFAbsoluteTimeGetCurrent()

        // ⚡️ 如果已经加载过，直接返回（避免重复创建）
        if isViewLoaded {
            mdLog("[STREAM] 📐📐📐 loadView() 已缓存，跳过创建")
            return
        }

        guard let attachment = textAttachment as? LaTeXAttachment else {
            super.loadView()
            return
        }

        mdLog("[STREAM] 📐📐📐 loadView() 开始创建公式视图: \(attachment.latex.prefix(30))...")

        // 直接复用 Attachment 初始化时的解析树和尺寸，不再解析或重新测量。
        let viewStart = CFAbsoluteTimeGetCurrent()
        let (formulaView, _) = LatexMathView.createScrollableView(
            renderResult: attachment.renderResult,
            backgroundColor: attachment.backgroundColor,
            textColor: attachment.textColor,
            appearance: attachment.appearance
        )
        mdLog("[STREAM] 📐📐📐 loadView 视图创建耗时: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - viewStart) * 1000))ms")

        // ⚡️ 设置明确的 frame（NSTextAttachmentViewProvider 需要）
        formulaView.frame = CGRect(origin: .zero, size: attachment.renderResult.displaySize)

        // 设置视图并标记已加载
        self.view = formulaView
        isViewLoaded = true

        mdLog("[STREAM] 📐📐📐 loadView() 完成，总耗时: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - loadStart) * 1000))ms")
    }

    
}
