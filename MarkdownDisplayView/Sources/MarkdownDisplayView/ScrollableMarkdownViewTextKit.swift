//
//  ScrollableMarkdownViewTextKit.swift
//  MarkdownDisplayView
//
//  Created by 朱继超 on 12/15/25.
//

import UIKit

// MARK: - ScrollableMarkdownViewTextKit

@available(iOS 15.0, *)
public final class ScrollableMarkdownViewTextKit: UIScrollView {
    
    public let markdownView = MarkdownViewTextKit()
    
    public var markdown: String {
        get { markdownView.markdown }
        set { markdownView.markdown = newValue }
    }
    
    public var configuration: MarkdownConfiguration {
        get { markdownView.configuration }
        set { markdownView.configuration = newValue }
    }
    
    public var onLinkTap: ((URL) -> Void)? {
        get { markdownView.onLinkTap }
        set { markdownView.onLinkTap = newValue }
    }
    
    public var onImageTap: ((String) -> Void)? {
        get { markdownView.onImageTap }
        set { markdownView.onImageTap = newValue }
    }
    
    public var onTOCItemTap: ((MarkdownTOCItem) -> Void)? {
        get { markdownView.onTOCItemTap }
        set { markdownView.onTOCItemTap = newValue }
    }
    
    public var tableOfContents: [MarkdownTOCItem] {
        return markdownView.tableOfContents
    }
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        addSubview(markdownView)
        markdownView.translatesAutoresizingMaskIntoConstraints = false
        markdownView.setContentHuggingPriority(.required, for: .vertical)
        markdownView.setContentCompressionResistancePriority(.required, for: .vertical)

        NSLayoutConstraint.activate([
            markdownView.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor, constant: 16),
            markdownView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor, constant: 16),
            markdownView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor, constant: -16),
            markdownView.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor, constant: -16),
            markdownView.widthAnchor.constraint(equalTo: frameLayoutGuide.widthAnchor, constant: -32),
        ])
    }
    
    public func scrollToTOCItem(_ item: MarkdownTOCItem) {
        markdownView.scrollToTOCItem(item)
    }
    
    public func generateTOCView() -> UIView {
        return markdownView.generateTOCView()
    }
    
    /// 滚动到底部
    public func scrollToBottom(animated: Bool = true) {
        let bottomOffset = CGPoint(
            x: 0,
            y: max(0, contentSize.height - bounds.height + contentInset.bottom)
        )
        setContentOffset(bottomOffset, animated: animated)
    }

    /// 滚动到顶部（返回目录）
    public func scrollToTop(animated: Bool = true) {
        setContentOffset(CGPoint(x: 0, y: -contentInset.top), animated: animated)
    }

    /// 流式渲染时是否自动滚动
    public var autoScrollOnStreaming: Bool = true
    
    /// 跳转到文档内的目录区域
    public func backToTableOfContentsSection() {
        markdownView.backToTableOfContentsSection()
    }
    
    /// 是否存在目录区域
    public var hasTableOfContentsSection: Bool {
        return markdownView.hasTableOfContentsSection
    }
}

//MARK: - streaming extension
extension ScrollableMarkdownViewTextKit {
    // 在 ScrollableMarkdownViewTextKt 中添加
    public func startStreaming(_ text: String, unit: StreamingUnit = .word, unitsPerChunk: Int = 2, interval: TimeInterval = 0.05, autoScrollBottom: Bool = true) {
        autoScrollOnStreaming = autoScrollBottom
        markdownView.startStreaming(text, unit: unit, unitsPerChunk: unitsPerChunk, interval: interval, autoScrollBottom: autoScrollBottom)
    }

    public func stopStreaming() {
        markdownView.stopStreaming()
    }

    public func finishStreaming() {
        markdownView.finishStreaming()
    }

    // MARK: - 真流式 API（Real Streaming）

    /// 开始真流式模式
    /// - Parameters:
    ///   - autoScrollBottom: 是否自动滚动到底部
    ///   - onComplete: 流式完成回调
    public func beginRealStreaming(autoScrollBottom: Bool = true, onComplete: (() -> Void)? = nil) {
        autoScrollOnStreaming = autoScrollBottom
        markdownView.beginRealStreaming(autoScrollBottom: autoScrollBottom, onComplete: onComplete)
    }

    /// 追加一个完整的 Markdown 块
    /// - Parameter block: 完整的 Markdown 块（如标题+内容、段落、代码块等）
    /// - Note: 每个块应该是完整的 Markdown 结构，不会在语法中间截断
    public func appendBlock(_ block: String) {
        markdownView.appendBlock(block)
    }

    /// 结束真流式模式
    public func endRealStreaming() {
        markdownView.endRealStreaming()
    }

    // 返回目录按钮点击
    @objc func backToTOCTapped() {
        if markdownView.hasTableOfContentsSection {
            markdownView.backToTableOfContentsSection()
        } else {
            // 没有目录区域，可以滚动到顶部或提示
            markdownView.scrollToTop()
        }
    }
}
