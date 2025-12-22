//
//  TableViewStreamingViewController.swift
//  ExampleForMarkdown
//
//  Created by Claude on 12/22/25.
//

import UIKit
import MarkdownDisplayView

/// 在 UITableViewCell 中实现流式打字机效果的示例（优化版）
class TableViewStreamingViewController: UIViewController {

    // MARK: - Properties

    private var messages: [ChatMessage] = []
    private var currentStreamingIndexPath: IndexPath?

    // 滚动节流
    private var scrollThrottleTimer: Timer?
    private var lastScrollTime: TimeInterval = 0
    private let scrollThrottleInterval: TimeInterval = 0.05 // 50ms节流

    // ⭐️ 自动滚动控制
    private var shouldAutoScroll: Bool = true
    private let autoScrollThreshold: CGFloat = 100 // 距离底部100pt内认为在底部

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.delegate = self
        tv.dataSource = self
        tv.separatorStyle = .none
        tv.backgroundColor = .systemBackground
        tv.register(MarkdownMessageCell.self, forCellReuseIdentifier: "MarkdownMessageCell")
        tv.estimatedRowHeight = 100
        tv.rowHeight = UITableView.automaticDimension
        tv.translatesAutoresizingMaskIntoConstraints = false
        // 关键：禁用自动调整，避免跳动
        if #available(iOS 15.0, *) {
            tv.sectionHeaderTopPadding = 0
        }
        return tv
    }()

    private lazy var toolBar: UIView = {
        let view = UIView()
        view.backgroundColor = .systemGray6
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var startButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("开始演示", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.addTarget(self, action: #selector(startDemo), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var clearButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("清空", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.addTarget(self, action: #selector(clearMessages), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        DispatchQueue.global().async {
            FontLoader.ensureFontsRegistered()
        }
        setupUI()
    }

    deinit {
        scrollThrottleTimer?.invalidate()
    }

    // MARK: - Setup

    private func setupUI() {
        title = "TableView 流式打字机"
        view.backgroundColor = .systemBackground

        // 添加初始提示消息
        addWelcomeMessage()

        // 关闭按钮
        let closeButton = UIButton(type: .system)
        closeButton.setTitle("关闭", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        closeButton.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        view.addSubview(tableView)
        view.addSubview(toolBar)
        toolBar.addSubview(startButton)
        toolBar.addSubview(clearButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            tableView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: toolBar.topAnchor),

            toolBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            toolBar.heightAnchor.constraint(equalToConstant: 60),

            startButton.centerYAnchor.constraint(equalTo: toolBar.centerYAnchor),
            startButton.leadingAnchor.constraint(equalTo: toolBar.leadingAnchor, constant: 20),

            clearButton.centerYAnchor.constraint(equalTo: toolBar.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: toolBar.trailingAnchor, constant: -20),
        ])
    }

    // MARK: - Actions

    private func addWelcomeMessage() {
        let welcomeText = """
        👋 **欢迎使用流式打字机演示**

        点击下方「开始演示」按钮体验丝滑流畅的效果。

        ✨ 特性：
        - 类似 Claude.ai 的打字机效果
        - 平滑滚动，无抖动
        - 支持完整 Markdown 语法
        """
        let welcomeMessage = ChatMessage(content: welcomeText, isUser: false)
        messages.append(welcomeMessage)
        tableView.reloadData()
    }

    @objc private func dismissSelf() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func startDemo() {
        startButton.isEnabled = false

        // 添加用户消息
        let userMessage = ChatMessage(content: "请给我介绍一下 Markdown 的常用语法", isUser: true)
        messages.append(userMessage)
        tableView.reloadData()
        scrollToBottom(animated: true)

        // 立即添加 AI 回复
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.startAIResponse()
        }
    }

    @objc private func clearMessages() {
        messages.removeAll()
        currentStreamingIndexPath = nil
        scrollThrottleTimer?.invalidate()
        scrollThrottleTimer = nil
        tableView.reloadData()
        startButton.isEnabled = true

        // 重新添加欢迎消息
        addWelcomeMessage()
    }

    private func startAIResponse() {
        let aiMessage = ChatMessage(content: demoMarkdown, isUser: false, isStreaming: true)
        messages.append(aiMessage)

        let indexPath = IndexPath(row: messages.count - 1, section: 0)
        currentStreamingIndexPath = indexPath

        tableView.insertRows(at: [indexPath], with: .none)
        scrollToBottom(animated: false)

        // 启动滚动节流定时器
        startScrollThrottle()

        // 立即开始流式渲染
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self,
                  let cell = self.tableView.cellForRow(at: indexPath) as? MarkdownMessageCell else {
                return
            }

            cell.startStreaming(text: demoMarkdown, onComplete: { [weak self] in
                self?.finishStreaming(at: indexPath)
            })
        }
    }

    private func finishStreaming(at indexPath: IndexPath) {
        messages[indexPath.row].isStreaming = false
        currentStreamingIndexPath = nil
        startButton.isEnabled = true

        // 停止滚动节流
        scrollThrottleTimer?.invalidate()
        scrollThrottleTimer = nil
    }

    // MARK: - 滚动优化

    private func startScrollThrottle() {
        scrollThrottleTimer?.invalidate()
        scrollThrottleTimer = Timer.scheduledTimer(withTimeInterval: scrollThrottleInterval, repeats: true) { [weak self] _ in
            self?.performThrottledScroll()
        }
    }

    private func performThrottledScroll() {
        guard let indexPath = currentStreamingIndexPath,
              indexPath.row == messages.count - 1 else {
            return
        }

        // 平滑滚动到底部
        let contentHeight = tableView.contentSize.height
        let tableHeight = tableView.bounds.height
        let bottomInset = tableView.contentInset.bottom

        if contentHeight > tableHeight {
            let targetY = contentHeight - tableHeight + bottomInset
            let currentY = tableView.contentOffset.y

            // 只在需要时滚动，避免不必要的抖动
            if targetY > currentY + 5 {
                tableView.setContentOffset(CGPoint(x: 0, y: targetY), animated: false)
            }
        }
    }

    private func scrollToBottom(animated: Bool) {
        guard !messages.isEmpty, shouldAutoScroll else { return }
        let indexPath = IndexPath(row: messages.count - 1, section: 0)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
    }
}

// MARK: - UITableViewDataSource

extension TableViewStreamingViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MarkdownMessageCell", for: indexPath) as! MarkdownMessageCell
        let message = messages[indexPath.row]
        cell.configure(with: message)

        // ⭐️ 设置用户交互回调：当用户点击目录、链接等元素时，停止自动滚动
        cell.onUserInteraction = { [weak self] in
            self?.shouldAutoScroll = false
        }

        return cell
    }
}

// MARK: - UITableViewDelegate

extension TableViewStreamingViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }

    // MARK: - 滚动检测（实现用户向上滚动时停止自动滚动）

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // 用户开始手动滚动时，检查是否在底部
        checkIfAtBottom(scrollView)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // 滚动过程中持续检查位置
        checkIfAtBottom(scrollView)
    }

    private func checkIfAtBottom(_ scrollView: UIScrollView) {
        let contentHeight = scrollView.contentSize.height
        let scrollViewHeight = scrollView.bounds.height
        let contentOffsetY = scrollView.contentOffset.y
        let bottomInset = scrollView.contentInset.bottom

        // 计算距离底部的距离
        let distanceFromBottom = contentHeight - contentOffsetY - scrollViewHeight + bottomInset

        // ⭐️ 方案C：检测 shouldAutoScroll 的变化
        let wasAutoScroll = shouldAutoScroll
        shouldAutoScroll = distanceFromBottom <= autoScrollThreshold

        // ⭐️ 当状态变化时，通知正在流式的 Cell
        if wasAutoScroll != shouldAutoScroll {
            handleAutoScrollStateChange()
        }
    }

    // ⭐️ 方案C：处理自动滚动状态变化
    private func handleAutoScrollStateChange() {
        guard let indexPath = currentStreamingIndexPath,
              let cell = tableView.cellForRow(at: indexPath) as? MarkdownMessageCell else {
            return
        }

        if shouldAutoScroll {
            // 用户滚回底部 → 恢复渲染
            cell.resumeRendering()
        } else {
            // 用户向上滚动 → 暂停渲染
            cell.pauseRendering()
        }
    }
}

// MARK: - MarkdownMessageCell（优化版）

class MarkdownMessageCell: UITableViewCell {

    // MARK: - Properties

    private let bubbleView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let markdownView: MarkdownViewTextKit = {
        let view = MarkdownViewTextKit()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!

    // ⭐️ 用户交互回调（当用户点击目录、链接等元素时通知外部）
    var onUserInteraction: (() -> Void)?

    // ⭐️ 方案C优化版：暂停状态（简化，由 MarkdownViewTextKit 管理内部状态）
    private var isPaused: Bool = false

    // MARK: - Initialization

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    // MARK: - Setup

    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none

        contentView.addSubview(bubbleView)
        bubbleView.addSubview(markdownView)

        leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
        trailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            markdownView.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 12),
            markdownView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            markdownView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            markdownView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -12),
        ])

        // ⭐️ 设置用户交互回调
        setupUserInteractionCallbacks()
    }

    private func setupUserInteractionCallbacks() {
        // 目录点击
        markdownView.onTOCItemTap = { [weak self] _ in
            self?.onUserInteraction?()
        }

        // 链接点击
        markdownView.onLinkTap = { [weak self] url in
            self?.onUserInteraction?()
            UIApplication.shared.open(url)
        }

        // 图片点击
        markdownView.onImageTap = { [weak self] _ in
            self?.onUserInteraction?()
        }
    }

    // MARK: - Configuration

    func configure(with message: ChatMessage) {
        if message.isUser {
            // 用户消息：右对齐，蓝色背景
            leadingConstraint.isActive = false
            trailingConstraint.isActive = true
            bubbleView.backgroundColor = .systemBlue.withAlphaComponent(0.2)

            var config = MarkdownConfiguration.default
            config.textColor = .label
            markdownView.configuration = config
        } else {
            // AI 消息：左对齐，灰色背景
            leadingConstraint.isActive = true
            trailingConstraint.isActive = false
            bubbleView.backgroundColor = .systemGray6

            markdownView.configuration = .default
        }

        // 如果不是流式模式，直接设置内容
        if !message.isStreaming {
            markdownView.markdown = message.content
        }
    }

    func startStreaming(text: String, onComplete: (() -> Void)?) {
        // 重置暂停状态
        isPaused = false

        // 极致流畅的参数设置
        markdownView.startStreaming(
            text,
            unit: .character,        // 按字符流式，最流畅
            unitsPerChunk: 5,        // 每次5个字符
            interval: 0.015,         // 15ms间隔
            autoScrollBottom: false
        )

        // 计算完成时间
        let estimatedDuration = Double(text.count) * 0.003
        DispatchQueue.main.asyncAfter(deadline: .now() + estimatedDuration) {
            onComplete?()
        }
    }

    // ⭐️ 方案C优化版：暂停渲染（使用 MarkdownViewTextKit 新 API）
    func pauseRendering() {
        guard !isPaused else { return }
        isPaused = true

        // ⭐️ 使用新 API：暂停显示但保留状态
        markdownView.pauseDisplayUpdates()
    }

    // ⭐️ 方案C优化版：恢复渲染（使用 MarkdownViewTextKit 新 API）
    func resumeRendering() {
        guard isPaused else { return }
        isPaused = false

        // ⭐️ 使用新 API：直接显示完整文本，无需重新解析
        markdownView.resumeDisplayUpdates()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        markdownView.stopStreaming()
        markdownView.markdown = ""

        // ⭐️ 重置暂停状态
        isPaused = false
    }
}

// MARK: - ChatMessage Model

struct ChatMessage {
    let content: String
    let isUser: Bool
    var isStreaming: Bool = false
}

// MARK: - Demo Markdown

let demoMarkdown = """
# Markdown 常用语法介绍

Markdown 是一种轻量级标记语言，非常适合用于编写文档和笔记。

## 1. 标题

使用 `#` 符号表示标题，一个 `#` 是一级标题，两个 `##` 是二级标题，以此类推。

## 2. 文本格式

- **粗体**：使用 `**文字**` 或 `__文字__`
- *斜体*：使用 `*文字*` 或 `_文字_`
- ~~删除线~~：使用 `~~文字~~`
- `行内代码`：使用反引号包裹

## 3. 列表

### 无序列表
- 项目一
- 项目二
  - 子项目 2.1
  - 子项目 2.2

### 有序列表
1. 第一步
2. 第二步
3. 第三步

## 4. 代码块

```swift
func greet(name: String) {
    print("Hello, \\(name)!")
}
```

## 5. 引用

> 这是一段引用文本。
> 可以包含多行内容。

## 6. 链接和图片

- 链接：[Apple](https://www.apple.com)
- 图片：![示例](https://example.com/image.png)

## 7. 表格

| 功能 | 语法 | 示例 |
|------|------|------|
| 粗体 | `**text**` | **粗体** |
| 斜体 | `*text*` | *斜体* |
| 代码 | `` `text` `` | `code` |

---

希望这个介绍对你有帮助！✨
"""
