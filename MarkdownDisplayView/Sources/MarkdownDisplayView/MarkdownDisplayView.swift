//
//  MarkdownDisplayView.swift
//  MarkdownDisplayView
//
//  Created by 朱继超 on 12/15/25.
//

import UIKit
import Foundation
import Combine
import NaturalLanguage

// MARK: - TextKit2 TextView

/// 使用 TextKit 2 的自定义 TextView
@available(iOS 15.0, *)
final class MarkdownTextViewTK2: UIView {
    
    private let textLayoutManager: NSTextLayoutManager
    private let textContentStorage: NSTextContentStorage
    private let textContainer: NSTextContainer
    
    var attributedText: NSAttributedString? {
        didSet {
            updateContent()
        }
    }
    
    var linkTextAttributes: [NSAttributedString.Key: Any] = [:]
    var onLinkTap: ((URL) -> Void)?
    var onImageTap: ((String) -> Void)?
    
    private var calculatedHeight: CGFloat = 0
    
    override init(frame: CGRect) {
        textContentStorage = NSTextContentStorage()
        textLayoutManager = NSTextLayoutManager()
        textContainer = NSTextContainer()
        
        super.init(frame: frame)
        
        setupTextKit2()
        setupGestures()
    }
    
    required init?(coder: NSCoder) {
        textContentStorage = NSTextContentStorage()
        textLayoutManager = NSTextLayoutManager()
        textContainer = NSTextContainer()
        
        super.init(coder: coder)
        
        setupTextKit2()
        setupGestures()
    }
    
    private func setupTextKit2() {
        textContentStorage.addTextLayoutManager(textLayoutManager)
        textLayoutManager.textContainer = textContainer
        textContainer.lineFragmentPadding = 0
        textContainer.widthTracksTextView = false  // 改为 false
        textContainer.heightTracksTextView = false
        
        // 添加这行，防止内容被拉伸
        textContainer.lineBreakMode = .byWordWrapping
        backgroundColor = .clear
        isUserInteractionEnabled = true
            
        // 设置 contentMode 防止拉伸
        contentMode = .topLeft
    }
    
    private func setupGestures() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tapGesture)
    }
    
    private func updateContent() {
        guard let attributedText = attributedText else {
            textContentStorage.attributedString = nil
            calculatedHeight = 0
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
            return
        }
        
        textContentStorage.attributedString = attributedText
        layoutText()
    }
    
    private func layoutText() {
        let width = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width - 32
        textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        
        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
        
        var height: CGFloat = 0
        textLayoutManager.enumerateTextLayoutFragments(from: textLayoutManager.documentRange.location, options: [.ensuresLayout]) { fragment in
            let fragmentFrame = fragment.layoutFragmentFrame
            height = max(height, fragmentFrame.maxY)
            return true
        }
        
        calculatedHeight = height
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
    }
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: calculatedHeight)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        if textContentStorage.attributedString != nil {
            layoutText()
        }
    }
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        textLayoutManager.enumerateTextLayoutFragments(from: textLayoutManager.documentRange.location, options: [.ensuresLayout]) { fragment in
            fragment.draw(at: fragment.layoutFragmentFrame.origin, in: context)
            return true
        }
    }
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        
        // 使用 textLayoutManager 获取点击位置的文本位置
        guard let textLayoutFragment = textLayoutManager.textLayoutFragment(for: location) else {
            return
        }
        
        // 将点击坐标转换为 fragment 内的相对坐标
        let locationInFragment = CGPoint(
            x: location.x - textLayoutFragment.layoutFragmentFrame.origin.x,
            y: location.y - textLayoutFragment.layoutFragmentFrame.origin.y
        )
        
        // 获取点击位置对应的文本位置
        var caretLocation: NSTextLocation?
        textLayoutFragment.textLineFragments.forEach { lineFragment in
            let lineFrame = lineFragment.typographicBounds
            let adjustedLineFrame = CGRect(
                x: lineFrame.origin.x,
                y: lineFrame.origin.y,
                width: lineFrame.width,
                height: lineFrame.height
            )
            
            if adjustedLineFrame.contains(locationInFragment) {
                let characterIndex = lineFragment.characterIndex(for: locationInFragment)
                if characterIndex != NSNotFound,
                   let textRange = textLayoutFragment.textElement?.elementRange,
                   let startLocation = textRange.location as? NSTextLocation {
                    caretLocation = textLayoutManager.location(startLocation, offsetBy: characterIndex)
                }
            }
        }
        
        guard let location = caretLocation else { return }
        
        // 计算在整个文档中的偏移量
        let offset = textLayoutManager.offset(from: textLayoutManager.documentRange.location, to: location)
        
        guard let attributedText = textContentStorage.attributedString,
              offset >= 0 && offset < attributedText.length else {
            return
        }
        
        let attributes = attributedText.attributes(at: offset, effectiveRange: nil)
        
        // 处理图片点击
        if let attachment = attributes[.attachment] as? MarkdownImageAttachment,
           let urlString = attachment.imageURL {
            onImageTap?(urlString)
            return
        }
        
        // 处理链接点击
        if let url = attributes[.link] as? URL {
            onLinkTap?(url)
        }
    }
}

// MARK: - MarkdownViewTextKit

/// TextKit 2 版本的 Markdown 渲染视图
@available(iOS 15.0, *)
public final class MarkdownViewTextKit: UIView {
    
    // MARK: - Properties
    
    public var configuration: MarkdownConfiguration = .default {
        didSet { scheduleRerender() }
    }
    
    public var markdown: String = "" {
        didSet { scheduleRerender() }
    }
    
    public var onLinkTap: ((URL) -> Void)?
    public var onImageTap: ((String) -> Void)?
    public var onHeightChange: ((CGFloat) -> Void)?
    public var onTOCItemTap: ((MarkdownTOCItem) -> Void)?
    
    public private(set) var tableOfContents: [MarkdownTOCItem] = []
    
    private let contentStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.alignment = .fill
        sv.spacing = 0
        return sv
    }()
    
    private var cancellables = Set<AnyCancellable>()
    private var imageAttachments: [(attachment: MarkdownImageAttachment, urlString: String)] = []
    private var renderWorkItem: DispatchWorkItem?
    private var refreshWorkItem: DispatchWorkItem?
    
    private var headingViews: [String: UIView] = [:]
    private var oldElements: [MarkdownRenderElement] = []
    
    // 异步渲染队列
    private let renderQueue = DispatchQueue(label: "com.markdown.render", qos: .userInitiated)
    
    /// About streaming
    private var streamTimer: Timer?
    private var streamFullText: String = ""
    private var streamCurrentIndex: Int = 0
    private var isStreaming = true
    
    private var streamTokens: [String] = []
    private var streamTokenIndex: Int = 0
    
    // 添加属性
    private var tocSectionView: UIView?
    private var tocSectionId: String?


    /// 是否存在目录区域
    public var hasTableOfContentsSection: Bool {
        return tocSectionView != nil
    }
    
    private var autoScrollEnabled: Bool = false
    // MARK: - Initialization
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    public convenience init(markdown: String, configuration: MarkdownConfiguration = .default) {
        self.init(frame: .zero)
        self.configuration = configuration
        self.markdown = markdown
        scheduleRerender()
    }
    
    private func setupUI() {
        addSubview(contentStackView)
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    
    // MARK: - Public Methods
    
    /// 跳转到文档内的目录区域
    public func backToTableOfContentsSection() {
        guard let view = tocSectionView else { return }
        
        var scrollView: UIScrollView?
        var superview = self.superview
        while superview != nil {
            if let sv = superview as? UIScrollView {
                scrollView = sv
                break
            }
            superview = superview?.superview
        }
        
        guard let sv = scrollView else { return }
        
        let frame = view.convert(view.bounds, to: sv)
        let targetY = max(0, frame.origin.y - 12)
        let maxY = max(0, sv.contentSize.height - sv.bounds.height + sv.contentInset.bottom)
        
        sv.setContentOffset(CGPoint(x: 0, y: min(targetY, maxY)), animated: true)
    }
    
    public func scrollToTOCItem(_ item: MarkdownTOCItem) {
        guard let view = headingViews[item.id] else { return }
        
        var scrollView: UIScrollView?
        var superview = self.superview
        while superview != nil {
            if let sv = superview as? UIScrollView {
                scrollView = sv
                break
            }
            superview = superview?.superview
        }
        
        guard let sv = scrollView else { return }
        
        let frame = view.convert(view.bounds, to: sv)
        let targetY = frame.origin.y - 12
        let maxY = max(0, sv.contentSize.height - sv.bounds.height + sv.contentInset.bottom)
        let clampedY = min(max(0, targetY), maxY)
        
        sv.setContentOffset(CGPoint(x: 0, y: clampedY), animated: true)
    }
    
    public func generateTOCView() -> UIView {
        let tocStackView = UIStackView()
        tocStackView.axis = .vertical
        tocStackView.spacing = 8
        tocStackView.alignment = .leading
        
        for item in tableOfContents {
            let button = UIButton(type: .system)
            let indent = String(repeating: "    ", count: item.level - 1)
            button.setTitle("\(indent)• \(item.title)", for: .normal)
            button.titleLabel?.font = configuration.bodyFont
            button.contentHorizontalAlignment = .left
            button.tag = tableOfContents.firstIndex(where: { $0.id == item.id }) ?? 0
            button.addTarget(self, action: #selector(tocItemTapped(_:)), for: .touchUpInside)
            tocStackView.addArrangedSubview(button)
        }
        
        return tocStackView
    }
    
    @objc private func tocItemTapped(_ sender: UIButton) {
        let index = sender.tag
        guard index < tableOfContents.count else { return }
        let item = tableOfContents[index]
        onTOCItemTap?(item)
        scrollToTOCItem(item)
    }
    
    // MARK: - Rendering
    
    private func scheduleRerender() {
        renderWorkItem?.cancel()
        
        if isStreaming {
            // 流式模式直接渲染，不延迟
            performRender()
            return
        }
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.performRender()
        }
        renderWorkItem = workItem
        
        // 延迟执行以合并多次快速更新
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016, execute: workItem)
    }
    
    private func performRender() {
        let markdownText = markdown
        let config = configuration
        let containerWidth = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width - 32
        
        renderQueue.async { [weak self] in
            guard let self else { return }
            
            let startTime = CFAbsoluteTimeGetCurrent()
            
            // 预处理脚注
            let (processedMarkdown, footnotes) = self.preprocessFootnotes(markdownText)
            
            // 直接渲染，获取所有需要的返回
            let renderer = MarkdownRenderer(configuration: config, containerWidth: containerWidth)
            let (newElements, attachments, tocItems, tocSectionId) = renderer.render(processedMarkdown)
            
            let endTime = CFAbsoluteTimeGetCurrent()
            print("[MarkdownDisplayView] parse took \(endTime - startTime) seconds")
            
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                
                self.tableOfContents = tocItems
                self.tocSectionId = tocSectionId  // ← 这里就是你需要的！用于后续滚动
                self.imageAttachments = attachments
                self.updateViews(newElements: newElements, footnotes: footnotes, containerWidth: containerWidth)
            }
        }
    }
    
    private func updateViews(newElements: [MarkdownRenderElement], footnotes: [MarkdownFootnote], containerWidth: CGFloat) {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Diff 算法找公共前缀
        var prefixLength = 0
        let minCount = min(oldElements.count, newElements.count)
        
        while prefixLength < minCount {
            if oldElements[prefixLength] == newElements[prefixLength] {
                prefixLength += 1
            } else {
                break
            }
        }
        
        // 检查是否可以原地更新
        var updateInPlace = false
        if prefixLength < oldElements.count && prefixLength < newElements.count {
            let oldItem = oldElements[prefixLength]
            let newItem = newElements[prefixLength]
            
            switch (oldItem, newItem) {
            case (.attributedText(_), .attributedText(let newText)):
                if let textView = contentStackView.arrangedSubviews[safe: prefixLength] as? MarkdownTextViewTK2 {
                    textView.attributedText = newText
                    textView.linkTextAttributes = [
                        .foregroundColor: configuration.linkColor,
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                    ]
                    updateInPlace = true
                }
                
            case (.heading(let oldId, _), .heading(let newId, let newText)):
                if oldId == newId,
                   let textView = contentStackView.arrangedSubviews[safe: prefixLength] as? MarkdownTextViewTK2 {
                    textView.attributedText = newText
                    updateInPlace = true
                }
                
            case (.thematicBreak, .thematicBreak):
                updateInPlace = true
                
            case (.quote(_, let oldLevel), .quote(let newText, let newLevel)):
                if oldLevel == newLevel,
                   let quoteView = contentStackView.arrangedSubviews[safe: prefixLength],
                   let textView = quoteView.subviews.first?.subviews.first(where: { $0 is MarkdownTextViewTK2 }) as? MarkdownTextViewTK2 {
                    textView.attributedText = newText
                    updateInPlace = true
                }
                
            default:
                break
            }
        }
        
        // 更新视图
        let removeStartIndex = updateInPlace ? prefixLength + 1 : prefixLength
        
        if removeStartIndex < contentStackView.arrangedSubviews.count {
            let viewsToRemove = Array(contentStackView.arrangedSubviews[removeStartIndex...])
            viewsToRemove.forEach { $0.removeFromSuperview() }
        }
        
        // 重建 headingViews 映射
        var keptHeadings: [String: UIView] = [:]
        for i in 0..<removeStartIndex {
            if i < oldElements.count {
                if case .heading(let id, _) = oldElements[i] {
                    if let view = contentStackView.arrangedSubviews[safe: i] {
                        keptHeadings[id] = view
                    }
                }
            }
        }
        headingViews = keptHeadings
        
        // 添加新视图
        let addStartIndex = updateInPlace ? prefixLength + 1 : prefixLength
        
        for i in addStartIndex..<newElements.count {
            let element = newElements[i]
            let view = createView(for: element, containerWidth: containerWidth)
            
            if let textView = view as? MarkdownTextViewTK2,
               textView.attributedText?.length == 0 {
                continue
            }
            
            contentStackView.addArrangedSubview(view)
            
            if case .heading(let id, _) = element {
                headingViews[id] = view
                // 记录目录区域视图
                if id == tocSectionId {
                    tocSectionView = view
                }
            }
        }
        
        // 处理脚注
        if contentStackView.arrangedSubviews.count > newElements.count {
            contentStackView.arrangedSubviews.last?.removeFromSuperview()
        }
        
        if !footnotes.isEmpty {
            let footnoteView = createFootnoteView(footnotes: footnotes, width: containerWidth)
            contentStackView.addArrangedSubview(footnoteView)
        }
        
        oldElements = newElements
        
        loadImages()
        invalidateIntrinsicContentSize()
        notifyHeightChange()
        
        let endTime = CFAbsoluteTimeGetCurrent()
        print("[MarkdownDisplayView] UI update took \(endTime - startTime) seconds")
    }
    
    private func createView(for element: MarkdownRenderElement, containerWidth: CGFloat) -> UIView {
        switch element {
        case .heading(_, let attributedString):
            return createTextView(
                with: attributedString,
                width: containerWidth,
                insets: UIEdgeInsets(top: configuration.headingTopSpacing, left: 0, bottom: configuration.headingBottomSpacing, right: 0)
            )
            
        case .attributedText(let attributedString):
            if attributedString.length > 0 {
                return createTextView(
                    with: attributedString,
                    width: containerWidth,
                    insets: UIEdgeInsets(top: configuration.paragraphTopSpacing, left: 0, bottom: configuration.paragraphBottomSpacing, right: 0)
                )
            } else {
                return UIView()
            }
            
        case .table(let tableData):
            return createTableView(with: tableData, containerWidth: containerWidth)
            
        case .thematicBreak:
            return createThematicBreakView(width: containerWidth)
        case .codeBlock(let attributedString):
            return createCodeBlockView(with: attributedString, width: containerWidth)
        case .quote(let attributedString, let level):
            return createQuoteView(with: attributedString, width: containerWidth, level: level)
            
        case .details(let summary, let children):
            return createDetailsView(summary: summary, children: children, width: containerWidth)
        case .image(let source, let altText):
            return createImageView(source: source, altText: altText, width: containerWidth)
        case .rawHTML:
            return UIView()
        }
    }
    
    private func createImageView(source: String, altText: String, width: CGFloat) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let imageView = ImageView(frame: .zero)
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isUserInteractionEnabled = true
        imageView.layer.cornerRadius = 8
        container.addSubview(imageView)
        
        // 点击手势
        let tap = UITapGestureRecognizer(target: self, action: #selector(imageViewTapped(_:)))
        imageView.addGestureRecognizer(tap)
        imageView.accessibilityIdentifier = source
        
        // 高度约束
        let heightConstraint = imageView.heightAnchor.constraint(equalToConstant: configuration.imagePlaceholderHeight)
        heightConstraint.priority = .defaultHigh
        
        // 宽度约束（用于图片加载后更新）
        let widthConstraint = imageView.widthAnchor.constraint(equalToConstant: width)
        widthConstraint.priority = .defaultHigh
        
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            widthConstraint,
            heightConstraint,
        ])
        
        // 用占位图加载
        let placeholderImage = createPlaceholderImage(
            size: CGSize(width: width, height: configuration.imagePlaceholderHeight),
            text: altText
        )
        
        // 使用你的 ImageView 加载方法
        imageView.image(with: source, placeHolder: placeholderImage) { [weak heightConstraint, weak widthConstraint] image in
            guard let image = image else { return }
            
            let imageSize = image.size
            guard imageSize.width > 0 && imageSize.height > 0 else { return }
            
            let aspectRatio = imageSize.width / imageSize.height
            var targetWidth = min(imageSize.width, width)
            var targetHeight = targetWidth / aspectRatio
            
            if targetHeight > self.configuration.imageMaxHeight {
                targetHeight = self.configuration.imageMaxHeight
                targetWidth = targetHeight * aspectRatio
            }
            
            widthConstraint?.constant = targetWidth
            heightConstraint?.constant = targetHeight
        }
        
        return container
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

    @objc private func imageViewTapped(_ gesture: UITapGestureRecognizer) {
        if let source = gesture.view?.accessibilityIdentifier {
            onImageTap?(source)
        }
    }

    private func loadImageForView(source: String, into imageView: UIImageView, heightConstraint: NSLayoutConstraint, maxWidth: CGFloat, maxHeight: CGFloat) {
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
    
    private func createCodeBlockView(with attributedString: NSAttributedString, width: CGFloat) -> UIView {
        let container = UIView()
        container.backgroundColor = configuration.codeBackgroundColor
        container.layer.cornerRadius = 8
        container.layer.masksToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let textView = MarkdownTextViewTK2()
        textView.attributedText = attributedString
        textView.backgroundColor = .clear
        textView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(textView)
        
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: width),
            textView.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            textView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            textView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])
        
        return container
    }
    
    // MARK: - Text View Creation
    
    private func createTextView(
        with attributedString: NSAttributedString,
        width: CGFloat,
        insets: UIEdgeInsets = .zero
    ) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let textView = MarkdownTextViewTK2()
        textView.attributedText = attributedString
        textView.linkTextAttributes = [
            .foregroundColor: configuration.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        textView.onLinkTap = { [weak self] url in
            self?.handleLinkTap(url)
        }
        textView.onImageTap = { [weak self] urlString in
            self?.onImageTap?(urlString)
        }
        textView.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(textView)
        
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: container.topAnchor, constant: insets.top),
            textView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: insets.left),
            textView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -insets.right),
            textView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -insets.bottom),
        ])
        
        container.setContentHuggingPriority(.required, for: .vertical)
        container.setContentCompressionResistancePriority(.required, for: .vertical)
        
        return container
    }
    
    private func handleLinkTap(_ url: URL) {
        // 检查是否是内部锚点链接
        if url.scheme == nil || url.scheme == "markdown" {
            var fragment = url.fragment ?? url.absoluteString.replacingOccurrences(of: "#", with: "")
            
            if let decoded = fragment.removingPercentEncoding {
                fragment = decoded
            }
            
            if !fragment.isEmpty {
                if headingViews[fragment] != nil {
                    scrollToTOCItem(MarkdownTOCItem(level: 1, title: "", id: fragment))
                    return
                }
                
                if let item = tableOfContents.first(where: {
                    $0.title.contains(fragment) || fragment.contains($0.title)
                }) {
                    scrollToTOCItem(item)
                    return
                }
            }
        }
        
        onLinkTap?(url)
    }
    
    // MARK: - Quote View
    
    private func createQuoteView(with attributedString: NSAttributedString, width: CGFloat, level: Int = 1) -> UIView {
        let outerContainer = UIView()
        outerContainer.translatesAutoresizingMaskIntoConstraints = false
        
        let container = UIView()
        container.backgroundColor = UIColor.systemGray6.withAlphaComponent(0.5)
        container.layer.cornerRadius = 4
        container.translatesAutoresizingMaskIntoConstraints = false
        outerContainer.addSubview(container)
        
        // 左侧竖线
        let bar = UIView()
        bar.backgroundColor = configuration.blockquoteBarColor
        bar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bar)
        
        let textView = MarkdownTextViewTK2()
        textView.attributedText = attributedString
        textView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(textView)
        
        // 根据层级计算左边距
        let leftIndent = CGFloat(level - 1) * 20
        
        NSLayoutConstraint.activate([
            outerContainer.widthAnchor.constraint(equalToConstant: width),
            container.topAnchor.constraint(equalTo: outerContainer.topAnchor, constant: level == 1 ? 8 : 4),
            container.leadingAnchor.constraint(equalTo: outerContainer.leadingAnchor, constant: leftIndent),
            container.trailingAnchor.constraint(equalTo: outerContainer.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: outerContainer.bottomAnchor),
            
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.topAnchor.constraint(equalTo: container.topAnchor),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bar.widthAnchor.constraint(equalToConstant: 4),
            
            textView.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            textView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            textView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])
        
        return outerContainer
    }
    
    // MARK: - Thematic Break View
    
    private func createThematicBreakView(width: CGFloat) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let lineView = UIView()
        lineView.backgroundColor = configuration.horizontalRuleColor
        lineView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(lineView)
        
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 24),
            container.widthAnchor.constraint(equalToConstant: width),
            lineView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            lineView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            lineView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            lineView.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
        ])
        
        return container
    }
    
    // MARK: - Details View
    
    private func createDetailsView(
        summary: String,
        children: [MarkdownRenderElement],
        width: CGFloat
    ) -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 4
        container.alignment = .fill
        container.distribution = .fill  // 添加这行
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let summaryButton = UIButton(type: .system)
        summaryButton.setTitle("▶ " + summary, for: .normal)
        summaryButton.setTitleColor(configuration.linkColor, for: .normal)
        summaryButton.contentHorizontalAlignment = .left
        summaryButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
//        summaryButton.backgroundColor = configuration.codeBackgroundColor
        summaryButton.layer.cornerRadius = 6
        summaryButton.configuration?.contentInsets = .init(top: 8, leading: 12, bottom: 8, trailing: 12)
        summaryButton.setContentHuggingPriority(.required, for: .vertical)
        summaryButton.setContentCompressionResistancePriority(.required, for: .vertical)
        container.addArrangedSubview(summaryButton)
        
        let contentContainer = UIStackView()
        contentContainer.axis = .vertical
        contentContainer.spacing = 0
        contentContainer.alignment = .fill
        contentContainer.distribution = .fill  // 添加这行
        contentContainer.isHidden = true
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.layoutMargins = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        contentContainer.isLayoutMarginsRelativeArrangement = true
        contentContainer.backgroundColor = configuration.codeBackgroundColor
        contentContainer.layer.cornerRadius = 6
        contentContainer.layer.masksToBounds = true
        container.addArrangedSubview(contentContainer)
        
        let contentWidth = width - 16
        for child in children {
            let childView = createView(for: child, containerWidth: contentWidth)
            if let textView = childView as? MarkdownTextViewTK2,
               textView.attributedText?.length == 0 {
                continue
            }
            contentContainer.addArrangedSubview(childView)
        }
        
        summaryButton.addAction(
            UIAction { [weak self, weak contentContainer, weak summaryButton] _ in
                guard let self = self,
                      let content = contentContainer,
                      let btn = summaryButton
                else { return }
                
                let willShow = content.isHidden
                
                // 先更新状态，不用动画
                content.isHidden = !willShow
                content.alpha = willShow ? 1 : 0
                btn.setTitle((willShow ? "▼ " : "▶ ") + summary, for: .normal)
                
                // 直接更新布局
                self.setNeedsLayout()
                self.layoutIfNeeded()
                self.invalidateIntrinsicContentSize()
                self.notifyHeightChange()
                
            }, for: .touchUpInside)
        
        return container
    }
    
    // MARK: - Table View
    
    private func createTableView(with tableData: MarkdownTableData, containerWidth: CGFloat) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        
        let tableStackView = UIStackView()
        tableStackView.axis = .vertical
        tableStackView.spacing = 0
        tableStackView.distribution = .fill
        tableStackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(tableStackView)
        
        // 计算列宽
        let columnCount = max(tableData.headers.count, tableData.rows.first?.count ?? 0)
        var columnWidths: [CGFloat] = Array(repeating: 80, count: columnCount)
        
        for (index, header) in tableData.headers.enumerated() {
            let width = header.boundingRect(
                with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 44),
                options: [.usesLineFragmentOrigin],
                context: nil
            ).width + 32
            columnWidths[index] = max(columnWidths[index], width)
        }
        
        for row in tableData.rows {
            for (index, cell) in row.enumerated() where index < columnCount {
                let width = cell.boundingRect(
                    with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 44),
                    options: [.usesLineFragmentOrigin],
                    context: nil
                ).width + 32
                columnWidths[index] = max(columnWidths[index], width)
            }
        }
        
        columnWidths = columnWidths.map { min($0, 200) }
        let totalWidth = columnWidths.reduce(0, +)
        
        // 表头行
        let headerRow = createTableRow(cells: tableData.headers, columnWidths: columnWidths, isHeader: true)
        tableStackView.addArrangedSubview(headerRow)
        
        // 分隔线
        let separator = UIView()
        separator.backgroundColor = configuration.tableBorderColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        tableStackView.addArrangedSubview(separator)
        
        // 数据行
        for (index, row) in tableData.rows.enumerated() {
            let rowView = createTableRow(cells: row, columnWidths: columnWidths, isHeader: false)
            if index % 2 == 1 {
                rowView.backgroundColor = configuration.tableAlternateRowBackgroundColor
            }
            tableStackView.addArrangedSubview(rowView)
        }
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            
            tableStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            tableStackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            tableStackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            tableStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            tableStackView.widthAnchor.constraint(equalToConstant: totalWidth),
        ])
        
        let rowHeight: CGFloat = 44
        let tableHeight = rowHeight * CGFloat(tableData.rows.count + 1) + 1
        container.heightAnchor.constraint(equalToConstant: tableHeight).isActive = true
        
        return container
    }
    
    private func createTableRow(
        cells: [NSAttributedString],
        columnWidths: [CGFloat],
        isHeader: Bool
    ) -> UIView {
        let rowStack = UIStackView()
        rowStack.axis = .horizontal
        rowStack.spacing = 0
        rowStack.distribution = .fill
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        
        if isHeader {
            rowStack.backgroundColor = configuration.tableHeaderBackgroundColor
        }
        
        for (index, cell) in cells.enumerated() {
            let cellView = UIView()
            cellView.translatesAutoresizingMaskIntoConstraints = false
            
            let label = UILabel()
            label.attributedText = cell
            label.numberOfLines = 0
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            
            if isHeader {
                label.font = UIFont.systemFont(ofSize: configuration.bodyFont.pointSize, weight: .semibold)
            }
            
            cellView.addSubview(label)
            
            if index < cells.count - 1 {
                let border = UIView()
                border.backgroundColor = configuration.tableBorderColor.withAlphaComponent(0.3)
                border.translatesAutoresizingMaskIntoConstraints = false
                cellView.addSubview(border)
                
                NSLayoutConstraint.activate([
                    border.topAnchor.constraint(equalTo: cellView.topAnchor, constant: 8),
                    border.bottomAnchor.constraint(equalTo: cellView.bottomAnchor, constant: -8),
                    border.trailingAnchor.constraint(equalTo: cellView.trailingAnchor),
                    border.widthAnchor.constraint(equalToConstant: 0.5),
                ])
            }
            
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: cellView.topAnchor, constant: 10),
                label.bottomAnchor.constraint(equalTo: cellView.bottomAnchor, constant: -10),
                label.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 12),
                label.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -12),
            ])
            
            let width = index < columnWidths.count ? columnWidths[index] : 80
            cellView.widthAnchor.constraint(equalToConstant: width).isActive = true
            
            rowStack.addArrangedSubview(cellView)
        }
        
        rowStack.heightAnchor.constraint(equalToConstant: 44).isActive = true
        
        return rowStack
    }
    
    // MARK: - Footnote View
    
    private func createFootnoteView(footnotes: [MarkdownFootnote], width: CGFloat) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 0
        stackView.alignment = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stackView)
        
        // 分隔线
        let separator = UIView()
        separator.backgroundColor = configuration.horizontalRuleColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(separator)
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        separator.widthAnchor.constraint(equalToConstant: width * 0.3).isActive = true
        
        // 间距
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
        stackView.addArrangedSubview(spacer)
        
        // 脚注列表
        for footnote in footnotes {
            let attributedText = NSMutableAttributedString()
            
            let idText = NSAttributedString(
                string: "⁽\(footnote.id)⁾ ",
                attributes: [
                    .font: UIFont.systemFont(ofSize: configuration.bodyFont.pointSize - 2),
                    .foregroundColor: configuration.linkColor,
                    .baselineOffset: 4,
                ])
            attributedText.append(idText)
            
            let contentText = NSAttributedString(
                string: footnote.content,
                attributes: [
                    .font: UIFont.systemFont(ofSize: configuration.bodyFont.pointSize - 2),
                    .foregroundColor: configuration.textColor.withAlphaComponent(0.8),
                ])
            attributedText.append(contentText)
            
            let textView = createTextView(
                with: attributedText,
                width: width,
                insets: UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
            )
            stackView.addArrangedSubview(textView)
        }
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        
        return container
    }
    
    // MARK: - Footnote Preprocessing
    
    private func preprocessFootnotes(_ text: String) -> (String, [MarkdownFootnote]) {
        var processedText = text
        var footnotes: [MarkdownFootnote] = []
        
        let definitionPattern = #"\[\^([^\]]+)\]:\s*(.+)$"#
        if let regex = try? NSRegularExpression(pattern: definitionPattern, options: .anchorsMatchLines) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            
            for match in matches.reversed() {
                if let idRange = Range(match.range(at: 1), in: text),
                   let contentRange = Range(match.range(at: 2), in: text),
                   let fullRange = Range(match.range, in: text) {
                    let id = String(text[idRange])
                    let content = String(text[contentRange])
                    footnotes.insert(MarkdownFootnote(id: id, content: content), at: 0)
                    processedText = processedText.replacingCharacters(in: fullRange, with: "")
                }
            }
        }
        
        let referencePattern = #"\[\^([^\]]+)\]"#
        if let regex = try? NSRegularExpression(pattern: referencePattern, options: []) {
            let matches = regex.matches(in: processedText, range: NSRange(processedText.startIndex..., in: processedText))
            
            for match in matches.reversed() {
                if let idRange = Range(match.range(at: 1), in: processedText),
                   let fullRange = Range(match.range, in: processedText) {
                    let id = String(processedText[idRange])
                    let replacement = "⁽\(id)⁾"
                    processedText = processedText.replacingCharacters(in: fullRange, with: replacement)
                }
            }
        }
        
        return (processedText, footnotes)
    }
    
    // MARK: - Image Loading
    
    private func loadImages() {
        for (attachment, urlString) in imageAttachments {
            loadImage(urlString: urlString, into: attachment)
        }
    }
    
    private func loadImage(urlString: String, into attachment: MarkdownImageAttachment) {
        var processedURLString = urlString
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            processedURLString = "https://" + urlString
        }
        
        guard let url = URL(string: processedURLString) else { return }
        
        ImageLoader.shared.loadImage(from: url)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] image in
                guard let self = self, let image = image else { return }
                
                let imageSize = image.size
                var targetSize = CGSize(width: 100, height: 100)
                
                if imageSize.width > 0 && imageSize.height > 0 {
                    let aspectRatio = ceilf(Float(imageSize.width / imageSize.height))
                    var targetWidth = imageSize.width
                    var targetHeight = imageSize.height
                    
                    // 按宽度缩放
                    if attachment.maxWidth > 0 && targetWidth > attachment.maxWidth {
                        targetWidth = attachment.maxWidth
                        targetHeight = targetWidth / CGFloat(aspectRatio)
                    }
                    
                    // 按高度缩放
                    if attachment.maxHeight > 0 && targetHeight > attachment.maxHeight {
                        targetHeight = attachment.maxHeight
                        targetWidth = targetHeight * CGFloat(aspectRatio)
                    }
                    
                    targetSize = CGSize(width: ceil(targetWidth), height: ceil(targetHeight))
                }
                
                // 直接生成缩放后的图片
                let renderer = UIGraphicsImageRenderer(size: targetSize)
                let scaledImage = renderer.image { _ in
                    image.draw(in: CGRect(origin: .zero, size: targetSize))
                }
                
                attachment.bounds = CGRect(origin: .zero, size: targetSize)
                attachment.image = scaledImage
                
                self.refreshWorkItem?.cancel()
                let workItem = DispatchWorkItem { [weak self] in
                    self?.refreshTextViews()
                }
                self.refreshWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
            }
            .store(in: &cancellables)
    }
    
    private func refreshTextViews() {
        for container in contentStackView.arrangedSubviews {
            for childView in container.subviews {
                if let textView = childView as? MarkdownTextViewTK2 {
                    textView.setNeedsDisplay()
                }
            }
        }
        
        invalidateIntrinsicContentSize()
        notifyHeightChange()
    }
    
    private func notifyHeightChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let size = self.contentStackView.systemLayoutSizeFitting(
                CGSize(width: self.bounds.width, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            )
            self.onHeightChange?(size.height)
        }
    }
    
    public override var intrinsicContentSize: CGSize {
        let size = contentStackView.systemLayoutSizeFitting(
            CGSize(
                width: bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width - 32,
                height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: UIView.noIntrinsicMetric, height: size.height)
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        invalidateIntrinsicContentSize()
    }
    
    //MARK: - streaming method

    public func startStreaming(_ text: String, unit: StreamingUnit = .word, unitsPerChunk: Int = 1, interval: TimeInterval = 0.05, autoScrollBottom: Bool = false) {
        autoScrollEnabled = autoScrollBottom
        stopStreaming()
        isStreaming = true
        
        streamFullText = text
        streamTokens = tokenize(text, unit: unit)
        streamTokenIndex = 0
        markdown = ""
        
        streamTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.appendNextTokens(count: unitsPerChunk)
        }
    }

    private func tokenize(_ text: String, unit: StreamingUnit) -> [String] {
        switch unit {
        case .character:
            return text.map { String($0) }
            
        case .word, .sentence:
            let nlUnit: NLTokenUnit = unit == .word ? .word : .sentence
            var tokens: [String] = []
            
            let tokenizer = NLTokenizer(unit: nlUnit)
            tokenizer.string = text
            
            var lastEnd = text.startIndex
            
            tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
                if lastEnd < range.lowerBound {
                    tokens.append(String(text[lastEnd..<range.lowerBound]))
                }
                tokens.append(String(text[range]))
                lastEnd = range.upperBound
                return true
            }
            
            if lastEnd < text.endIndex {
                tokens.append(String(text[lastEnd..<text.endIndex]))
            }
            
            return tokens
        }
    }

    /// 追加下一批 token
    private func appendNextTokens(count: Int) {
        guard streamTokenIndex < streamTokens.count else {
            stopStreaming()
            return
        }
        
        let endIndex = min(streamTokenIndex + count, streamTokens.count)
        let chunk = streamTokens[streamTokenIndex..<endIndex].joined()
        
        markdown += chunk
        streamTokenIndex = endIndex
        
        // 自动滚动到底部
        if autoScrollEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.scrollToBottom(animated: false)
            }
        }
    }
    
    /// 停止流式渲染
    public func stopStreaming() {
        streamTimer?.invalidate()
        streamTimer = nil
        isStreaming = false
    }

    /// 立即显示全部内容
    public func finishStreaming() {
        stopStreaming()
        markdown = streamFullText
        isStreaming = false
    }

    private func appendNextChunk(chunkSize: Int) {
        guard streamCurrentIndex < streamFullText.count else {
            stopStreaming()
            return
        }
        
        var endIndex = min(streamCurrentIndex + chunkSize, streamFullText.count)
        
        // 尝试在空格或换行处断开，更自然
        let searchEnd = min(endIndex + 10, streamFullText.count)
        let startIdx = streamFullText.index(streamFullText.startIndex, offsetBy: endIndex)
        let searchIdx = streamFullText.index(streamFullText.startIndex, offsetBy: searchEnd)
        let searchRange = startIdx..<searchIdx
        
        if let spaceRange = streamFullText.range(of: " ", range: searchRange) {
            endIndex = streamFullText.distance(from: streamFullText.startIndex, to: spaceRange.lowerBound) + 1
        }
        
        let index = streamFullText.index(streamFullText.startIndex, offsetBy: endIndex)
        markdown = String(streamFullText[..<index])
        streamCurrentIndex = endIndex
    }
    
    /// 滚动到底部
    public func scrollToBottom(animated: Bool = true) {
        var scrollView: UIScrollView?
        var superview = self.superview
        while superview != nil {
            if let sv = superview as? UIScrollView {
                scrollView = sv
                break
            }
            superview = superview?.superview
        }
        
        guard let sv = scrollView else { return }
        
        let bottomOffset = CGPoint(
            x: 0,
            y: max(0, sv.contentSize.height - sv.bounds.height + sv.contentInset.bottom)
        )
        sv.setContentOffset(bottomOffset, animated: animated)
    }
    
    /// 滚动到顶部
    public func scrollToTop(animated: Bool = true) {
        var scrollView: UIScrollView?
        var superview = self.superview
        while superview != nil {
            if let sv = superview as? UIScrollView {
                scrollView = sv
                break
            }
            superview = superview?.superview
        }
        
        guard let sv = scrollView else { return }
        sv.setContentOffset(CGPoint(x: 0, y: -sv.contentInset.top), animated: animated)
    }
    
}
