//
//  CodeBlockAttachment.swift
//  MarkdownDisplayView
//
//  Created by AI Assistant on 2/6/26.
//

import UIKit

// MARK: - Code Block Attachment

struct CodeBlockMetrics {
    let contentWidth: CGFloat
    let contentHeight: CGFloat
    let attachmentHeight: CGFloat

    static func calculate(for code: NSAttributedString, padding: CGFloat = 12) -> CodeBlockMetrics {
        let size = code.boundingRect(
            with: CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).size
        let contentWidth = ceil(size.width)
        let contentHeight = ceil(size.height)
        return CodeBlockMetrics(
            contentWidth: contentWidth,
            contentHeight: contentHeight,
            attachmentHeight: contentHeight + padding * 2
        )
    }
}

/// 代码块附件，用于在 TextKit 2 中显示支持横向滚动的代码块
@available(iOS 15.0, *)
final class CodeBlockAttachment: NSTextAttachment {

    /// 代码的富文本（含语法高亮）
    let code: NSAttributedString

    /// Markdown 配置
    let configuration: MarkdownConfiguration

    /// 容器最大宽度
    let containerWidth: CGFloat

    /// 代码语言标识
    let language: String?

    /// 代码不换行时的实际内容宽度
    let contentWidth: CGFloat

    /// 代码不换行时的实际内容高度
    let contentHeight: CGFloat

    /// 内边距
    private let padding: CGFloat = 12

    /// 缓存的 ViewProvider
    private weak var cachedViewProvider: CodeBlockAttachmentViewProvider?

    init(
        code: NSAttributedString,
        configuration: MarkdownConfiguration,
        containerWidth: CGFloat,
        language: String? = nil,
        metrics: CodeBlockMetrics? = nil
    ) {
        self.code = code
        self.configuration = configuration
        self.containerWidth = containerWidth
        self.language = language

        // 计算代码不换行时的实际尺寸（宽度无限大，不换行）
        let resolvedMetrics = metrics ?? CodeBlockMetrics.calculate(for: code)
        self.contentWidth = resolvedMetrics.contentWidth
        self.contentHeight = resolvedMetrics.contentHeight

        super.init(data: nil, ofType: nil)

        // 防止默认占位图标
        self.image = UIImage()

        // 设置 attachment bounds：宽度 = 容器宽度，高度 = 内容高度 + 上下 padding
        let totalHeight = resolvedMetrics.attachmentHeight
        self.bounds = CGRect(origin: .zero, size: CGSize(width: containerWidth, height: totalHeight))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewProvider(
        for parentView: UIView?,
        location: any NSTextLocation,
        textContainer: NSTextContainer?
    ) -> NSTextAttachmentViewProvider? {
        if let cached = cachedViewProvider {
            return cached
        }
        let provider = CodeBlockAttachmentViewProvider(
            textAttachment: self,
            parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager,
            location: location
        )
        cachedViewProvider = provider
        return provider
    }
}

// MARK: - Code Block Attachment View Provider

/// 代码块附件视图提供者，创建支持横向滚动的代码块视图
@available(iOS 15.0, *)
final class CodeBlockAttachmentViewProvider: NSTextAttachmentViewProvider {

    private var isViewLoaded = false

    override func loadView() {
        if isViewLoaded { return }

        guard let attachment = textAttachment as? CodeBlockAttachment else {
            super.loadView()
            return
        }

        let padding: CGFloat = 12
        let containerWidth = attachment.containerWidth
        let codeContentWidth = attachment.contentWidth
        let codeContentHeight = attachment.contentHeight
        let totalHeight = codeContentHeight + padding * 2

        // 1. 外层容器（圆角 + 背景色）
        let container = UIView(frame: CGRect(
            x: 0, y: 0,
            width: containerWidth,
            height: totalHeight
        ))
        container.backgroundColor = attachment.configuration.codeBackgroundColor
        container.layer.applyMarkdownBlockAppearance(attachment.configuration.codeBlockAppearance)
        container.layer.masksToBounds = true

        // 2. 水平滚动视图
        let scrollView = UIScrollView(frame: CGRect(
            x: padding, y: padding,
            width: containerWidth - padding * 2,
            height: codeContentHeight
        ))
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.backgroundColor = .clear

        // contentSize：宽度取代码实际宽度和可视宽度的较大值
        let scrollContentWidth = max(codeContentWidth, containerWidth - padding * 2)
        scrollView.contentSize = CGSize(width: scrollContentWidth, height: codeContentHeight)

        // 3. 代码文本视图（不换行，使用实际内容宽度）
        let textView = MarkdownTextViewTK2()
        textView.attributedText = attachment.code
        textView.typewriterTextMode = .reveal
        textView.backgroundColor = .clear
        textView.frame = CGRect(
            x: 0, y: 0,
            width: scrollContentWidth,
            height: codeContentHeight
        )
        // 使用不换行的宽度进行布局
        textView.textContainer.size = CGSize(
            width: scrollContentWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.setFixedHeight(codeContentHeight)

        scrollView.addSubview(textView)
        container.addSubview(scrollView)

        self.view = container
        isViewLoaded = true
    }
}
