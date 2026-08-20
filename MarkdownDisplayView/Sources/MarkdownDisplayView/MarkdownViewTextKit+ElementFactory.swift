//
//  MarkdownViewTextKit+ElementFactory.swift
//  MarkdownDisplayView
//
//  Mechanical extension split from MarkdownDisplayView.swift.
//

import UIKit
import Foundation
import Combine

@available(iOS 15.0, *)
extension MarkdownViewTextKit {
    func createView(for element: MarkdownRenderElement, containerWidth: CGFloat, suppressTopSpacing: Bool = false, suppressBottomSpacing: Bool = false, precalculatedHeight: CGFloat? = nil) -> UIView {
        switch element {
        case .heading(_, let attributedString):
            let topSpacing = suppressTopSpacing ? 0 : configuration.headingTopSpacing
            let bottomSpacing = suppressBottomSpacing ? 0 : configuration.headingBottomSpacing
            return createTextView(
                with: attributedString,
                width: containerWidth,
                insets: UIEdgeInsets(top: topSpacing, left: 0, bottom: bottomSpacing, right: 0),
                fixedHeight: precalculatedHeight
            )

        case .attributedText(let attributedString):
            if attributedString.length > 0 {
                let isInlineSegment = attributedString.attribute(inlineSegmentAttributeKey, at: 0, effectiveRange: nil) != nil
                let topSpacing = suppressTopSpacing ? 0 : (isInlineSegment ? 0 : configuration.paragraphTopSpacing)
                let bottomSpacing = suppressBottomSpacing ? 0 : (isInlineSegment ? 0 : configuration.paragraphBottomSpacing)
                return createTextView(
                    with: attributedString,
                    width: containerWidth,
                    insets: UIEdgeInsets(top: topSpacing, left: 0, bottom: bottomSpacing, right: 0),
                    fixedHeight: precalculatedHeight
                )
            } else {
                return UIView()
            }

        case .table(let tableData):
            // 使用 NSTextAttachment + UICollectionView 优化表格性能
            let attachment = MarkdownTableAttachment(
                data: tableData,
                config: configuration,
                containerWidth: containerWidth,
                onLinkTap: { [weak self] url in
                    self?.handleLinkTap(url)
                }
            )
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .left
            
            let attrString = NSMutableAttributedString(attachment: attachment)
            attrString.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: attrString.length))

            let view = createTextView(
                with: attrString,
                width: containerWidth,
                fixedHeight: ceil(attachment.totalSize.height + 1)
            )
            view.accessibilityIdentifier = "MarkdownAtomicTable"
            return view

        case .thematicBreak:
            let view = createThematicBreakView(width: containerWidth)
            view.accessibilityIdentifier = "MarkdownAtomicThematicBreak"
            return view
        case .codeBlock(let language, let attributedString):
            // 检查是否有自定义代码块渲染器
            if let lang = language,
               let renderer = MarkdownCustomExtensionManager.shared.codeBlockRenderer(for: lang) {
                let rawCode = attributedString.string
                let view = renderer.renderCodeBlock(code: rawCode, configuration: configuration, containerWidth: containerWidth)
                view.accessibilityIdentifier = "MarkdownAtomicCodeBlock"
                return view
            }
            // 默认代码块渲染：使用 CodeBlockAttachment 支持横向滚动
            let codeAttachment = CodeBlockAttachment(
                code: attributedString,
                configuration: configuration,
                containerWidth: containerWidth,
                language: language
            )

            let codeParagraphStyle = NSMutableParagraphStyle()
            codeParagraphStyle.alignment = .left

            let codeAttrString = NSMutableAttributedString(attachment: codeAttachment)
            codeAttrString.addAttribute(.paragraphStyle, value: codeParagraphStyle, range: NSRange(location: 0, length: codeAttrString.length))

            let view = createTextView(
                with: codeAttrString,
                width: containerWidth,
                fixedHeight: ceil(codeAttachment.bounds.height + 1)
            )
            view.accessibilityIdentifier = "MarkdownAtomicCodeBlock"
            return view
        case .quote(let children, let level):
            return createQuoteView(children: children, width: containerWidth, level: level)

        case .details(let summary, let children):
            return createDetailsView(summary: summary, children: children, width: containerWidth)
        case .image(let source, let altText):
            let topSpacing = suppressTopSpacing ? 0 : 8.0
            let bottomSpacing = suppressBottomSpacing ? 0 : 8.0
            let view = createImageView(source: source, altText: altText, width: containerWidth, topSpacing: topSpacing, bottomSpacing: bottomSpacing)
            view.accessibilityIdentifier = "MarkdownAtomicImage"
            return view
        case .latex(let latex):
            let topSpacing = suppressTopSpacing ? 0 : 8.0
            let bottomSpacing = suppressBottomSpacing ? 0 : 8.0
            return createLatexView(latex: latex, width: containerWidth, topSpacing: topSpacing, bottomSpacing: bottomSpacing)
        case .rawHTML:
            return UIView()
        case .list(items: let list, level: let level):
            return createListView(items: list, width: containerWidth, level: level)
        case .custom(let data):
            let view = createCustomView(data: data, containerWidth: containerWidth)
            view.accessibilityIdentifier = "MarkdownAtomicCustom"
            return view
        }
    }

    // MARK: - Custom View Creation

    func createCustomView(data: CustomElementData, containerWidth: CGFloat) -> UIView {
        mdLog("🔷[MDEXT] createCustomView called: type=\(data.type), raw=\(data.rawText)")
        // 从扩展管理器获取视图提供者
        guard let provider = MarkdownCustomExtensionManager.shared.viewProvider(for: data.type) else {
            mdLog("🔷[MDEXT] ❌ No viewProvider found for type: \(data.type)")
            // 无匹配的视图提供者，返回占位视图
            let placeholder = UILabel()
            placeholder.text = "[\(data.type): \(data.rawText)]"
            placeholder.textColor = .secondaryLabel
            placeholder.font = configuration.bodyFont
            return placeholder
        }

        mdLog("🔷[MDEXT] ✅ viewProvider found, creating view...")
        return provider.createView(
            for: data,
            configuration: configuration,
            containerWidth: containerWidth
        )
    }

    // 2. 实现 createListView
    // MARK: - List View Creation

    static let listWrapperTopConstraintIdentifier = "MarkdownListWrapperTop"
    static let listWrapperBottomConstraintIdentifier = "MarkdownListWrapperBottom"
    static let listWrapperLeadingConstraintIdentifier = "MarkdownListWrapperLeading"
    static let listWrapperWidthConstraintIdentifier = "MarkdownListWrapperWidth"

    func resolvedListTopPadding() -> CGFloat {
        max(0, configuration.listTopPadding)
    }

    func resolvedListBottomPadding() -> CGFloat {
        max(0, configuration.listBottomPadding)
    }

    func updateListWrapperLayoutConstraints(_ wrapper: UIView, width: CGFloat, indent: CGFloat) {
        for constraint in wrapper.constraints {
            switch constraint.identifier {
            case Self.listWrapperTopConstraintIdentifier:
                constraint.constant = resolvedListTopPadding()
            case Self.listWrapperBottomConstraintIdentifier:
                constraint.constant = -resolvedListBottomPadding()
            case Self.listWrapperLeadingConstraintIdentifier:
                constraint.constant = indent
            case Self.listWrapperWidthConstraintIdentifier:
                constraint.constant = width
            default:
                break
            }
        }
    }

    func createListView(items: [ListNodeItem], width: CGFloat, level: Int) -> UIView {
        // 1. 创建主容器（垂直堆叠每个列表项）
        let container = UIStackView()
        container.axis = .vertical
        container.distribution = .fill
        container.spacing = configuration.listItemSpacing // 列表项之间的间距
        container.alignment = .fill
        container.isLayoutMarginsRelativeArrangement = false
        container.layoutMargins = .zero
        container.translatesAutoresizingMaskIntoConstraints = false
        container.setContentHuggingPriority(.required, for: .vertical)
        container.setContentCompressionResistancePriority(.required, for: .vertical)
        applyListDebugStyleIfNeeded(to: container, color: .systemRed)

        // 2. 计算缩进和内容宽度
        // 使用配置项，默认为 20pt
        let indent: CGFloat = configuration.listIndent
        // ⭐️ 核心修复：嵌套列表的缩进应该是相对的，而不是基于层级的绝对累加
        // 因为视图本身已经是嵌套的，每层只需要缩进一个单位即可
        let currentIndent = (level > 1) ? indent : 0

        // 子元素可用的最大宽度 = 总宽度 - 当前缩进 - 标记宽度(估算20) - 间距
        let contentMaxWidth = max(0, width - currentIndent)

        // ⭐️ 预先计算所有标记的最大宽度，确保对齐
        let maxMarkerWidth: CGFloat = {
            var maxWidth: CGFloat = configuration.listMarkerMinWidth  // 最小宽度
            for item in items {
                let markerText = item.marker as NSString
                let size = markerText.size(withAttributes: [.font: configuration.bodyFont])
                maxWidth = max(maxWidth, ceil(size.width) + configuration.listMarkerSpacing)  // 额外加padding
            }
            return maxWidth
        }()

        // 3. 遍历生成每个列表项
        for item in items {
            // 每个列表项是一个水平 Stack：[标记] [内容垂直Stack]
            let itemStack = UIStackView()
            itemStack.axis = .horizontal
            itemStack.alignment = .top // 顶部对齐，防止标记跑到中间
            itemStack.spacing = configuration.listMarkerSpacing
            itemStack.isLayoutMarginsRelativeArrangement = false
            itemStack.layoutMargins = .zero
            itemStack.translatesAutoresizingMaskIntoConstraints = false
            itemStack.setContentHuggingPriority(.required, for: .vertical)
            itemStack.setContentCompressionResistancePriority(.required, for: .vertical)
            applyListDebugStyleIfNeeded(to: itemStack, color: .systemBlue)

            // A. 标记 (Bullet point or Number)
            let markerLabel = UILabel()
            markerLabel.text = item.marker
            markerLabel.font = configuration.bodyFont // 使用正文字体
            markerLabel.textColor = configuration.textColor
            markerLabel.setContentHuggingPriority(.required, for: .horizontal)
            markerLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

            // 使用预计算的最大宽度，确保所有列表项对齐
            markerLabel.widthAnchor.constraint(equalToConstant: maxMarkerWidth).isActive = true
            markerLabel.textAlignment = .right // 数字右对齐更好看
            applyListDebugStyleIfNeeded(to: markerLabel, color: .systemYellow)

            itemStack.addArrangedSubview(markerLabel)

            // B. 内容容器 (垂直堆叠：第一行文本 + 后续的代码块/嵌套列表等)
            let contentStack = UIStackView()
            contentStack.axis = .vertical
            // listItemSpacing 只用于“列表项之间”，项内间距由子元素自身 top/bottom spacing 决定
            contentStack.spacing = 0
            contentStack.alignment = .fill
            contentStack.isLayoutMarginsRelativeArrangement = false
            contentStack.layoutMargins = .zero
            contentStack.translatesAutoresizingMaskIntoConstraints = false
            contentStack.setContentHuggingPriority(.required, for: .vertical)
            contentStack.setContentCompressionResistancePriority(.required, for: .vertical)
            applyListDebugStyleIfNeeded(to: contentStack, color: .systemGreen)

            // ⭐️ 递归核心：遍历 ListItem 的 children 并创建视图
            // 实际内容宽度 = 总宽度 - 标记宽度 - 间距
            let itemContentWidth = contentMaxWidth - maxMarkerWidth - configuration.listMarkerSpacing

            let visibleChildren = visibleListChildren(in: item)
            for (index, childElement) in visibleChildren.enumerated() {
                // 递归调用 createView
                // 如果是列表项的第一个元素，去除顶部间距，以便跟 Marker 对齐
                let isFirst = (index == 0)
                // ⭐️ 列表内的元素，默认去除底部间距，完全由 contentStack.spacing 控制
                let childView = createView(for: childElement, containerWidth: itemContentWidth, suppressTopSpacing: isFirst, suppressBottomSpacing: true)
                applyListDebugStyleIfNeeded(to: childView, color: .systemPink)
                contentStack.addArrangedSubview(childView)
            }

            normalizeListContentStackLayout(contentStack, itemContentWidth: itemContentWidth)
            itemStack.addArrangedSubview(contentStack)
            container.addArrangedSubview(itemStack)
        }

        // 4. 外层包装 (处理缩进)
        let indentWrapper = UIView()
        indentWrapper.translatesAutoresizingMaskIntoConstraints = false
        indentWrapper.setContentHuggingPriority(.required, for: .vertical)
        indentWrapper.setContentCompressionResistancePriority(.required, for: .vertical)
        indentWrapper.addSubview(container)

        // wrapper 本身没有 intrinsicContentSize，必须同时约束顶部和底部，
        // 才能让它的高度严格由列表内容决定。若底部仅使用 lessThanOrEqual，
        // Auto Layout 可以把 wrapper 任意拉高，额外高度会表现为列表后的大段留白，
        // 直到 UIScrollView 因用户滚动再次触发布局才可能被压回真实高度。
        let topConstraint = container.topAnchor.constraint(equalTo: indentWrapper.topAnchor, constant: resolvedListTopPadding())
        topConstraint.identifier = Self.listWrapperTopConstraintIdentifier

        let bottomConstraint = container.bottomAnchor.constraint(equalTo: indentWrapper.bottomAnchor, constant: -resolvedListBottomPadding())
        bottomConstraint.priority = .required
        bottomConstraint.identifier = Self.listWrapperBottomConstraintIdentifier

        let leadingConstraint = container.leadingAnchor.constraint(equalTo: indentWrapper.leadingAnchor, constant: currentIndent)
        leadingConstraint.identifier = Self.listWrapperLeadingConstraintIdentifier

        let widthConstraint = indentWrapper.widthAnchor.constraint(equalToConstant: width)
        // `width` 是解析/预排版阶段的测量快照，Cell 最终宽度可能存在亚像素差异。
        // 保持 999 可稳定内部排版，同时允许外层 StackView 的 required 真实宽度胜出，
        // 避免每个列表模块都触发 unsatisfiable-constraints 恢复布局。
        widthConstraint.priority = UILayoutPriority(999)
        widthConstraint.identifier = Self.listWrapperWidthConstraintIdentifier

        // 使用标准约束替代 pinToEdges
        NSLayoutConstraint.activate([
            topConstraint,
            bottomConstraint,
            container.trailingAnchor.constraint(equalTo: indentWrapper.trailingAnchor),
            // ⭐️ 关键：左边设置缩进
            leadingConstraint,
            
            // 宽度约束，确保 wrap content
            widthConstraint
        ])
        
        return indentWrapper
    }

    func normalizeListContentStackLayout(_ contentStack: UIStackView, itemContentWidth: CGFloat) {
        contentStack.spacing = 0

        // 清理纯不可见文本子视图，避免“看起来一行但 item 高度被撑开”
        for childView in contentStack.arrangedSubviews {
            guard let textView = markdownTextView(in: childView),
                  let attributed = textView.attributedText else { continue }

            let normalized = normalizedAttributedTextForRendering(
                attributed,
                trimLeadingNewlines: true,
                trimTrailingNewlines: true
            )

            if isEffectivelyInvisibleListText(normalized.string) {
                childView.removeFromSuperview()
                continue
            }

            if !attributed.isEqual(normalized) {
                textView.attributedText = normalized
            }
        }

        for childView in contentStack.arrangedSubviews {
            childView.setContentHuggingPriority(.required, for: .vertical)
            childView.setContentCompressionResistancePriority(.required, for: .vertical)
            recursivelyUpdateLayout(for: childView, width: itemContentWidth)
        }
    }

    func markdownTextView(in view: UIView) -> MarkdownTextViewTK2? {
        if let textView = view as? MarkdownTextViewTK2 {
            return textView
        }
        if let textView = view.subviews.first(where: { $0 is MarkdownTextViewTK2 }) as? MarkdownTextViewTK2 {
            return textView
        }
        return nil
    }

    func isSkippableListChildElement(_ element: MarkdownRenderElement) -> Bool {
        guard case .attributedText(let attributedString) = element else { return false }
        return isEffectivelyInvisibleListText(attributedString.string)
    }

    func visibleListChildren(in item: ListNodeItem) -> [MarkdownRenderElement] {
        item.children.compactMap { normalizeListChildElement($0) }
    }

    func normalizeListChildElement(_ element: MarkdownRenderElement) -> MarkdownRenderElement? {
        guard case .attributedText(let attributedString) = element else { return element }

        let normalized = normalizedAttributedTextForRendering(
            attributedString,
            trimLeadingNewlines: true,
            trimTrailingNewlines: true
        )
        guard !isEffectivelyInvisibleListText(normalized.string) else { return nil }
        return .attributedText(normalized)
    }

    func isEffectivelyInvisibleListText(_ text: String) -> Bool {
        text.trimmingCharacters(in: listInvisibleCharacterSet).isEmpty
    }

    var listInvisibleCharacterSet: CharacterSet {
        var set = CharacterSet.whitespacesAndNewlines
        set.formUnion(.controlCharacters)
        set.insert(charactersIn: "\u{200B}\u{200C}\u{200D}\u{FEFF}")
        return set
    }

    var isListLayoutDebugEnabled: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["MD_DEBUG_LIST_LAYOUT"] == "1"
        #else
        return false
        #endif
    }

    func applyListDebugStyleIfNeeded(to view: UIView, color: UIColor) {
        guard isListLayoutDebugEnabled else { return }
        view.backgroundColor = color.withAlphaComponent(0.08)
        view.layer.borderWidth = 0.5
        view.layer.borderColor = color.withAlphaComponent(0.6).cgColor
    }

    /// 创建 LaTeX 公式视图（使用 LaTeXAttachment + ViewProvider 优化）
    func createLatexView(latex: String, width: CGFloat, topSpacing: CGFloat, bottomSpacing: CGFloat) -> UIView {
        let createTime = CFAbsoluteTimeGetCurrent()
        mdLog("[STREAM] 📐 LaTeX 开始创建: \(latex.prefix(50))...")

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        // ⭐️ 标记为原子 Block，包含流式开始时间和创建时间，用于追踪显示延迟
        // 格式: MarkdownAtomicLatex_<streamStartTime>_<createTime>
        container.accessibilityIdentifier = "MarkdownAtomicLatex_\(streamingStartTimestamp)_\(createTime)"

        // ⚡️ 使用 LaTeXAttachment
        let attachmentStart = CFAbsoluteTimeGetCurrent()
        let attachment = LaTeXAttachment(
            latex: latex,
            fontSize: configuration.latexFontSize,
            maxWidth: width - configuration.latexPadding * 2,  // 留出容器padding
            padding: configuration.latexPadding,
            backgroundColor: configuration.latexBackgroundColor,
            textColor: configuration.latexTextColor,
            appearance: configuration.latexAppearance
        )
        mdLog("[STREAM] 📐 LaTeXAttachment 创建耗时: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - attachmentStart) * 1000))ms")

        // 直接使用已解析的 renderResult 创建公式视图，无需经过 TextKit 2 附件管线
        // （原来的做法是建一套 NSTextLayoutManager/NSTextContentStorage 再枚举片段取 ViewProvider，
        //  最终也只是拿到同一个 createScrollableView 产物，纯属冗余）
        let formulaView = LatexMathView.createScrollableView(
            renderResult: attachment.renderResult,
            backgroundColor: attachment.backgroundColor,
            textColor: attachment.textColor,
            appearance: attachment.appearance
        ).view

        formulaView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(formulaView)

        // Attachment 初始化时已经完成唯一一次解析和测量；正常与回退路径共享同一尺寸。
        let formulaSize = attachment.renderResult.displaySize
        mdLog("[STREAM] 📐 复用 LaTeX 渲染尺寸: \(formulaSize)")

        // 设置约束 - 根据对齐方式设置水平约束
        var constraints: [NSLayoutConstraint] = [
            formulaView.topAnchor.constraint(equalTo: container.topAnchor, constant: topSpacing),
            formulaView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -bottomSpacing),
            formulaView.widthAnchor.constraint(equalToConstant: formulaSize.width),
            formulaView.heightAnchor.constraint(equalToConstant: formulaSize.height)
        ]

        // 根据配置的对齐方式添加水平约束
        switch configuration.latexAlignment {
        case .left:
            constraints.append(formulaView.leadingAnchor.constraint(equalTo: container.leadingAnchor))
        case .right:
            constraints.append(formulaView.trailingAnchor.constraint(equalTo: container.trailingAnchor))
        default:  // .center, .justified, .natural
            constraints.append(formulaView.centerXAnchor.constraint(equalTo: container.centerXAnchor))
        }

        NSLayoutConstraint.activate(constraints)

        let totalTime = (CFAbsoluteTimeGetCurrent() - createTime) * 1000
        mdLog("[STREAM] 📐 LaTeX 创建完成，总耗时: \(String(format: "%.1f", totalTime))ms")

        return container
    }

    func createImageView(source: String, altText: String, width: CGFloat, topSpacing: CGFloat, bottomSpacing: CGFloat) -> UIView {
        mdLog("🖼️ [Image] Creating image view for: \(source) (alt: \(altText))")

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let imageView = ImageView(frame: .zero)
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isUserInteractionEnabled = true
        imageView.layer.applyMarkdownBlockAppearance(configuration.imageAppearance)
        container.addSubview(imageView)
        
        // 点击手势
        let tap = UITapGestureRecognizer(target: self, action: #selector(imageViewTapped(_:)))
        imageView.addGestureRecognizer(tap)
        imageView.accessibilityIdentifier = source
        
        // 高度约束 - 提高优先级到 required
        let heightConstraint = imageView.heightAnchor.constraint(equalToConstant: configuration.imagePlaceholderHeight)
        heightConstraint.priority = .required  // 🔧 修复：从 .defaultHigh 改为 .required

        // 宽度约束（用于图片加载后更新）
        let widthConstraint = imageView.widthAnchor.constraint(lessThanOrEqualToConstant: width)
        widthConstraint.priority = .required

        // 🔧 图片居左对齐
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: topSpacing),
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            // ❌ 移除 trailingAnchor，让图片自然宽度，居左显示
            widthConstraint,
            heightConstraint,
        ])

        // 容器尺寸约束
        let containerHeightConstraint = container.heightAnchor.constraint(
            equalTo: imageView.heightAnchor,
            constant: topSpacing + bottomSpacing
        )
        containerHeightConstraint.priority = .required

        let containerWidthConstraint = container.widthAnchor.constraint(equalTo: imageView.widthAnchor)
        containerWidthConstraint.priority = .required

        NSLayoutConstraint.activate([
            containerHeightConstraint,
            containerWidthConstraint,
        ])

        mdLog("🖼️ [Image] Constraints set - width: ≤\(width), height: \(configuration.imagePlaceholderHeight)")
        
        // 用占位图加载
        let placeholderImage = createPlaceholderImage(
            size: CGSize(width: width, height: configuration.imagePlaceholderHeight),
            text: altText
        )
        
        // 使用你的 ImageView 加载方法
        imageView.image(with: source, placeHolder: placeholderImage) { [weak self, weak heightConstraint, weak widthConstraint] image in
            guard let self,
                  let image,
                  let heightConstraint,
                  let widthConstraint,
                  let targetSize = self.applyLoadedImageSize(
                    image.size,
                    maxWidth: width,
                    widthConstraint: widthConstraint,
                    heightConstraint: heightConstraint
                  ) else { return }

            mdLog("🖼️ [Image] Loaded - actual size: \(targetSize.width) × \(targetSize.height)")
        }

        // 设置容器的内容优先级，防止被压缩
        container.setContentHuggingPriority(.required, for: .vertical)
        container.setContentCompressionResistancePriority(.required, for: .vertical)
        container.setContentHuggingPriority(.required, for: .horizontal)
        container.setContentCompressionResistancePriority(.required, for: .horizontal)

        // 调试：延迟打印容器大小
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            mdLog("🖼️ [Image Debug] Container frame: \(container.frame), imageView frame: \(imageView.frame)")
            mdLog("🖼️ [Image Debug] Container bounds: \(container.bounds), imageView bounds: \(imageView.bounds)")
        }

        return container
    }

    /// 提交远程图片的真实尺寸，并把由此产生的结构高度变化合并到下一次布局帧。
    /// 这里只更新约束与根高度，不重新解析 Markdown，也不重建其他渲染元素。
    @discardableResult
    func applyLoadedImageSize(
        _ imageSize: CGSize,
        maxWidth: CGFloat,
        widthConstraint: NSLayoutConstraint,
        heightConstraint: NSLayoutConstraint
    ) -> CGSize? {
        guard imageSize.width.isFinite,
              imageSize.height.isFinite,
              imageSize.width > 0,
              imageSize.height > 0 else { return nil }

        let aspectRatio = imageSize.width / imageSize.height
        var targetWidth = min(imageSize.width, maxWidth)
        var targetHeight = targetWidth / aspectRatio

        if targetHeight > configuration.imageMaxHeight {
            targetHeight = configuration.imageMaxHeight
            targetWidth = targetHeight * aspectRatio
        }

        guard targetWidth.isFinite,
              targetHeight.isFinite,
              targetWidth > 0,
              targetHeight > 0 else { return nil }

        let targetSize = CGSize(width: targetWidth, height: targetHeight)
        let sizeChanged = abs(widthConstraint.constant - targetWidth) > 0.5
            || abs(heightConstraint.constant - targetHeight) > 0.5
        guard sizeChanged else { return targetSize }

        UIView.performWithoutAnimation {
            widthConstraint.constant = targetWidth
            heightConstraint.constant = targetHeight
        }

        // 多张图片可能在同一帧完成。复用现有调度器只做一次压缩测高，避免每张图片
        // 都触发整棵 Markdown 视图布局，同时清掉占位图阶段缓存的根高度。
        scheduleHeightChangeNotification(force: true)
        return targetSize
    }
    
    func createPlaceholderImage(size: CGSize, text: String) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            configuration.imagePlaceholderColor.setFill()
            let rect = CGRect(origin: .zero, size: size)
            UIBezierPath(
                roundedRect: rect,
                cornerRadius: max(0, configuration.imageAppearance.cornerRadius)
            ).fill()
            
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

    @objc private func imageViewTapped(_ gesture: UITapGestureRecognizer) {
        if let source = gesture.view?.accessibilityIdentifier {
            onImageTap?(source)
        }
    }

    func loadImageForView(source: String, into imageView: UIImageView, heightConstraint: NSLayoutConstraint, maxWidth: CGFloat, maxHeight: CGFloat) {
        var urlString = source
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://" + urlString
        }
        
        guard let url = URL(string: urlString) else { return }
        
        ImageLoader.shared.loadImage(from: url)
            .receive(on: DispatchQueue.main)
            .sink { [weak imageView, weak heightConstraint] image in
                guard let imageView = imageView, let image = image else { return }
                
                let imageSize = image.size
                guard imageSize.width > 0 && imageSize.height > 0 else { return }
                
                let aspectRatio = imageSize.width / imageSize.height
                var targetWidth = min(imageSize.width, maxWidth)
                var targetHeight = targetWidth / aspectRatio
                
                if targetHeight > maxHeight {
                    targetHeight = maxHeight
                    targetWidth = targetHeight * aspectRatio
                }
                
                imageView.image = image
                imageView.backgroundColor = .clear
                heightConstraint?.constant = targetHeight
                imageView.widthAnchor.constraint(equalToConstant: targetWidth).isActive = true
            }
            .store(in: &cancellables)
    }
    
    func createCodeBlockView(with attributedString: NSAttributedString, width: CGFloat, fixedHeight: CGFloat? = nil) -> UIView {
        let container = UIView()
        container.backgroundColor = configuration.codeBackgroundColor
        container.layer.applyMarkdownBlockAppearance(configuration.codeBlockAppearance)
        container.layer.masksToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false
        // [CODEBLOCK_DEBUG] 添加标识符，便于调试
        container.accessibilityIdentifier = "CodeBlockContainer"

        let textView = MarkdownTextViewTK2()
        textView.attributedText = attributedString
        textView.typewriterTextMode = .reveal
        textView.typewriterHeightUpdateInterval = configuration.typewriterHeightUpdateInterval
        textView.backgroundColor = .clear
        textView.translatesAutoresizingMaskIntoConstraints = false
        // [CODEBLOCK_DEBUG] 添加标识符
        textView.accessibilityIdentifier = "CodeBlockTextView"

        mdLog("[CODEBLOCK_DEBUG] 🏗️ createCodeBlockView: width=\(width), textLength=\(attributedString.length)")

        // 🔥 核心修复:立即应用布局,计算文本实际可用宽度(减去 padding)
        let padding = configuration.codeBlockPadding
        let codeBlockWidth = max(0, width - padding * 2)
        
        if let fixedHeight = fixedHeight {
            // ⚡️ 使用预计算高度 (减去上下 padding)
            textView.textContainer.size = CGSize(width: codeBlockWidth, height: .greatestFiniteMagnitude)
            textView.setFixedHeight(max(0, fixedHeight - padding * 2))
        } else {
            textView.applyLayout(width: codeBlockWidth, force: true)
        }

        container.addSubview(textView)

        // 🔥 修复：宽度约束优先级降低，避免与父容器冲突
        let widthConstraint = container.widthAnchor.constraint(equalToConstant: width)
        widthConstraint.priority = .defaultHigh  // 优先级 750，可被父容器覆盖

        NSLayoutConstraint.activate([
            widthConstraint,
            textView.topAnchor.constraint(equalTo: container.topAnchor, constant: padding),
            textView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            textView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            textView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -padding),
        ])

        return container
    }
    
}
