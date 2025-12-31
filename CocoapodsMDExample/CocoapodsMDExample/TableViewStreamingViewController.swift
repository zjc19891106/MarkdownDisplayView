//
//  TableViewStreamingViewController.swift
//  CocoapodsMDExample
//
//  Created by Claude on 12/22/25.
//

import UIKit
import MarkdownDisplayKit

struct ChatMessage {
    let id = UUID()
    var content: String
    let isUser: Bool
    
    // 状态控制
    var isStreaming: Bool = false // 是否正在打字
    var isLoading: Bool = false   // 是否正在思考(网络请求中)
}

// MARK: - Cell

class TypingIndicatorView: UIView {
    private let stackView = UIStackView()
    private var dots: [UIView] = []
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
            stackView.axis = .horizontal
            stackView.spacing = 4
            stackView.distribution = .fillEqually
            stackView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stackView)
            
            // 创建3个点
            for _ in 0..<3 {
                let dot = UIView()
                dot.backgroundColor = .systemGray2
                dot.layer.cornerRadius = 3
                dot.translatesAutoresizingMaskIntoConstraints = false
                // 点的大小保持 6x6
                dot.heightAnchor.constraint(equalToConstant: 6).isActive = true
                dot.widthAnchor.constraint(equalToConstant: 6).isActive = true
                dots.append(dot)
                stackView.addArrangedSubview(dot)
            }
            
            // 关键修改：移除 width=30 的强约束，改用自适应
            // 关键修改：减小内部 Padding，避免和 Cell 外部的 20pt 高度冲突
            NSLayoutConstraint.activate([
                stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
                stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
                // 将内部间距改为 0，由外部 Cell 控制整体大小
                stackView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
                stackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
                stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
                stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
            ])
            
            startAnimating()
        }
    
    func startAnimating() {
        for (index, dot) in dots.enumerated() {
            // 简单的关键帧动画，实现波浪效果
            UIView.animate(withDuration: 0.6, delay: Double(index) * 0.2, options: [.repeat, .autoreverse], animations: {
                dot.alpha = 0.3
                dot.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
            }, completion: { _ in
                dot.alpha = 1.0
                dot.transform = .identity
            })
        }
    }
    
    func stopAnimating() {
        dots.forEach { $0.layer.removeAllAnimations() }
    }
}


class ChatMarkdownCell: UITableViewCell {

    // MARK: - UI Components
    private let markdownView = MarkdownViewTextKit()
    private let typingIndicator = TypingIndicatorView() // 确保你有这个类
    private let bgView = UIView()
    // 新增：记录上一次通知的高度，防止重复通知
    private var lastReportedHeight: CGFloat = 0

    // MARK: - Callbacks
    var onContentHeightChanged: (() -> Void)?

    // ⭐️ 用户交互回调（当用户点击目录、链接等元素时通知外部）
    var onUserInteraction: (() -> Void)?

    // ⭐️ 方案C优化版：暂停状态（简化，由 MarkdownViewTextKit 管理内部状态）
    private var isPaused: Bool = false

    // MARK: - 流式状态标记
    private var isCurrentlyStreaming: Bool = false

    // 暴露只读属性给外部
    var isStreaming: Bool {
        return isCurrentlyStreaming
    }
    
    // MARK: - Constraints Groups
    // 1. 对齐约束 (控制左右)
    private var alignConstraints: [NSLayoutConstraint] = []
    // 2. Loading 模式下的约束 (只由 TypingIndicator 撑开高度)
    private var loadingConstraints: [NSLayoutConstraint] = []
    // 3. 内容 模式下的约束 (只由 MarkdownView 撑开高度)
    private var contentConstraints: [NSLayoutConstraint] = []
    
    // MARK: - Init
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    // MARK: - Setup UI
    private func setupUI() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        
        // --- 添加视图 ---
        bgView.translatesAutoresizingMaskIntoConstraints = false
        bgView.layer.cornerRadius = 16 // 圆角稍微大一点好看
        bgView.layer.cornerCurve = .continuous
        contentView.addSubview(bgView)
        
        markdownView.translatesAutoresizingMaskIntoConstraints = false
        markdownView.backgroundColor = .clear
        markdownView.onHeightChange = { [weak self] newHeight in
            guard let self = self else { return }

            // ⭐️ 核心修复 1：防抖检测
            // 只有当高度变化超过 0.5pt 时才通知 VC，避免因为浮点数微小差异导致无效刷新
            if abs(newHeight - self.lastReportedHeight) > 0.5 {
                self.lastReportedHeight = newHeight
                self.onContentHeightChanged?()
            }
        }
        bgView.addSubview(markdownView)

        // ⭐️ 关键修复：设置正确的优先级，让 MarkdownView 能撑开 bgView
        markdownView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        markdownView.setContentCompressionResistancePriority(.required, for: .horizontal)  // 必须能撑开
        markdownView.setContentHuggingPriority(.required, for: .vertical)
        markdownView.setContentCompressionResistancePriority(.required, for: .vertical)
        typingIndicator.translatesAutoresizingMaskIntoConstraints = false
        bgView.addSubview(typingIndicator)
        
        // --- 1. 基础约束 (始终激活) ---
                let bgTop = bgView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6)
                let bgBottom = bgView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6)
                
                // ⭐️ 修复核心：增加最小尺寸保护
                // 无论里面有没有字，气泡至少要有 40x40 的大小，防止塌陷成“细长条”
                let minWidth = bgView.widthAnchor.constraint(greaterThanOrEqualToConstant: 44)
                let minHeight = bgView.heightAnchor.constraint(greaterThanOrEqualToConstant: 40)
        // ⭐️ 移除最大宽度约束，改用 alignConstraints 中的固定宽度
        // 避免约束冲突

        NSLayoutConstraint.activate([
            bgTop,
            bgBottom,
            minWidth,
            minHeight
        ])
        // --- 2. 准备对齐约束 (不激活，configure时切换) ---
        // ⭐️ 修复：使用固定宽度，确保有足够空间显示内容
        let aiLeading = bgView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
        let aiWidth = bgView.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.85, constant: -16)
        aiWidth.priority = .required

        let userTrailing = bgView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        let userWidth = bgView.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.85, constant: -16)
        userWidth.priority = .required

        alignConstraints = [
            aiLeading,     // [0] AI: leading
            aiWidth,       // [1] AI: width
            userTrailing,  // [2] User: trailing
            userWidth      // [3] User: width
        ]
        
        // --- 3. 准备 内容模式 约束 (不激活) ---
        // 只有在显示文本时，才激活这组，让文字撑开气泡
        contentConstraints = [
            markdownView.topAnchor.constraint(equalTo: bgView.topAnchor, constant: 12),
            markdownView.bottomAnchor.constraint(equalTo: bgView.bottomAnchor, constant: -12),
            markdownView.leadingAnchor.constraint(equalTo: bgView.leadingAnchor, constant: 16),
            markdownView.trailingAnchor.constraint(equalTo: bgView.trailingAnchor, constant: -16)
        ]
        
        // --- 4. 准备 Loading模式 约束 (不激活) ---
        // 只有在Loading时，才激活这组，让动画撑开气泡
        loadingConstraints = [
            typingIndicator.topAnchor.constraint(equalTo: bgView.topAnchor, constant: 12),
            typingIndicator.bottomAnchor.constraint(equalTo: bgView.bottomAnchor, constant: -12),
            typingIndicator.centerXAnchor.constraint(equalTo: bgView.centerXAnchor),
            typingIndicator.heightAnchor.constraint(equalToConstant: 26), // 动画固定高度
            typingIndicator.widthAnchor.constraint(equalToConstant: 40),  // 动画固定宽度
            // 增加一个最小宽度，防止气泡太圆太小
            bgView.widthAnchor.constraint(greaterThanOrEqualToConstant: 60)
        ]

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
    
    override func layoutSubviews() {
        super.layoutSubviews()

     
    }
    
    // MARK: - Configuration (修复核心)
    func configure(with message: ChatMessage) {

        // 1. 设置左右对齐颜色
        // ⭐️ 修复：只在颜色需要改变时才设置，避免触发 scheduleRerender
        let targetColor: UIColor = message.isUser ? .white : .label
        if markdownView.configuration.textColor != targetColor {
            markdownView.configuration.textColor = targetColor
        }

        if message.isUser {
            // 用户消息：右对齐 + 固定宽度
            alignConstraints[0].isActive = false  // AI leading
            alignConstraints[1].isActive = false  // AI width
            alignConstraints[2].isActive = true   // User trailing
            alignConstraints[3].isActive = true   // User width
            bgView.backgroundColor = .systemBlue
        } else {
            // AI 消息：左对齐 + 固定宽度
            alignConstraints[0].isActive = true   // AI leading
            alignConstraints[1].isActive = true   // AI width
            alignConstraints[2].isActive = false  // User trailing
            alignConstraints[3].isActive = false  // User width
            bgView.backgroundColor = UIColor(red: 242/255, green: 242/255, blue: 247/255, alpha: 1) // 系统灰
        }

        // 2. 彻底解决冲突：二选一激活约束
        if message.isLoading {
            // [模式 A: Loading]

            // 步骤1: 停止并隐藏 Markdown
            markdownView.isHidden = true
            markdownView.markdown = ""

            // 步骤2: 显示 Loading
            typingIndicator.isHidden = false
            typingIndicator.startAnimating()

            // 步骤3: 切换约束 (先 deactivate 再 activate，防止冲突报错)
            NSLayoutConstraint.deactivate(contentConstraints) // 松开 Markdown 的手
            NSLayoutConstraint.activate(loadingConstraints)   // 让 Loading 接管气泡高度

        } else {
            // [模式 B: 内容展示] (包括用户消息)

            // 步骤1: 隐藏 Loading
            typingIndicator.stopAnimating()
            typingIndicator.isHidden = true

            // 步骤2: 显示 Markdown
            markdownView.isHidden = false

            // 步骤3: 切换约束
            NSLayoutConstraint.deactivate(loadingConstraints) // 松开 Loading 的手
            NSLayoutConstraint.activate(contentConstraints)   // 让 Markdown 接管气泡高度

            // 步骤4: 赋值
            // ⭐️ 修复：只有非流式状态且内容不同时才设置，避免重复渲染导致卡顿
            if !message.isStreaming && markdownView.markdown != message.content {
                markdownView.markdown = message.content
            }
        }
    }
    
    // 修改方法签名，增加 onStart 回调参数
    func startStreaming(text: String, onStart: (() -> Void)? = nil, completion: @escaping () -> Void) {

        // 重置暂停状态
        isPaused = false

        // ⭐️ 标记为流式状态
        isCurrentlyStreaming = true

        markdownView.startStreaming(
            text,
            unit: .character,
            unitsPerChunk: 4,
            interval: 0.06,
            autoScrollBottom: false,

            // 🟢 onStart: 后台算完了，马上要出字了
            onStart: { [weak self] in
                guard let self = self else { return }

                // 1. 执行原有的 UI 切换逻辑
                self.typingIndicator.isHidden = true
                self.typingIndicator.stopAnimating()
                self.markdownView.isHidden = false
                NSLayoutConstraint.deactivate(self.loadingConstraints)
                NSLayoutConstraint.activate(self.contentConstraints)
                self.layoutIfNeeded()

                // 2. 🔥 通知外部：我真的开始了
                onStart?()
            },

            onComplete: { [weak self] in
                // ⭐️ 流式结束，清除标记
                self?.isCurrentlyStreaming = false
                completion()
            }
        )
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
    
    func stopStreaming() {
        markdownView.stopStreaming()
        // ⭐️ 停止时清除流式标记
        isCurrentlyStreaming = false
    }

    // MARK: - 真流式 API

    /// 开始真流式模式
    func beginRealStreaming(onStart: (() -> Void)? = nil, completion: @escaping () -> Void) {
        // 重置状态
        isPaused = false
        isCurrentlyStreaming = true

        markdownView.beginRealStreaming(autoScrollBottom: false) { [weak self] in
            self?.isCurrentlyStreaming = false
            completion()
        }

        // 立即执行 UI 切换
        typingIndicator.isHidden = true
        typingIndicator.stopAnimating()
        markdownView.isHidden = false
        NSLayoutConstraint.deactivate(loadingConstraints)
        NSLayoutConstraint.activate(contentConstraints)
        layoutIfNeeded()

        onStart?()
    }

    /// 追加一个 Markdown 块
    func appendBlock(_ block: String) {
        markdownView.appendBlock(block)
    }

    /// 结束真流式
    func endRealStreaming() {
        markdownView.endRealStreaming()
        isCurrentlyStreaming = false
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        typingIndicator.stopAnimating()
        onContentHeightChanged = nil
        // ⭐️ 重置流式标记
        isCurrentlyStreaming = false

        // ⭐️ 重置暂停状态
        isPaused = false

        // 复用时重置为默认状态 (假设是内容模式)
        markdownView.isHidden = false
        typingIndicator.isHidden = true
        NSLayoutConstraint.deactivate(loadingConstraints)
        NSLayoutConstraint.activate(contentConstraints)
    }
}

class TableViewStreamingViewController: UIViewController {

    private let tableView = UITableView()
    private let inputContainer = UIView() // 模拟底部输入框区域
    private var messages: [ChatMessage] = []

    // 模拟长文本
    private let demoMarkdown = sampleMarkdown

    // ⭐️ 自动滚动控制
    private var shouldAutoScroll: Bool = true  // 是否应该自动滚动
    private let autoScrollThreshold: CGFloat = 100  // 距离底部多少时认为"在底部"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupTableView()
        setupInputArea()
        
        // 初始欢迎语
        messages.append(ChatMessage(content: "你好！请点击下方按钮开始测试。", isUser: false))
    }
    
    private func setupTableView() {
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.separatorStyle = .none
        tableView.register(ChatMarkdownCell.self, forCellReuseIdentifier: "ChatCell")
        tableView.dataSource = self
        tableView.delegate = self
        // 关键：估算高度，虽然 TextKit2 计算很准，但这就够了
        tableView.estimatedRowHeight = 100
        tableView.rowHeight = UITableView.automaticDimension
        tableView.setContentHuggingPriority(.required, for: .vertical)
        tableView.setContentCompressionResistancePriority(.required, for: .vertical)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor,constant: 100),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60) // 留出输入框位置
        ])
        
        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Close", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        closeButton.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        
        let stopButton = UIButton(type: .system)
        stopButton.setTitle("Stop", for: .normal)
        stopButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        stopButton.addTarget(self, action: #selector(stopStreaming), for: .touchUpInside)
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stopButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            
            stopButton.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            stopButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stopButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }
    
    @objc private func dismissSelf() {
        self.dismiss(animated: true, completion: nil)
    }
    
    @objc private func stopStreaming() {
        // 停止真流式
        stopRealStream()

        // 停止当前正在流式输出的消息
        for (index, msg) in messages.enumerated() {
            if msg.isStreaming {
                messages[index].isStreaming = false
                self.isSending = true
                // 这里假设 Cell 还在屏幕上，可以直接获取并停止
                let indexPath = IndexPath(row: index, section: 0)
                if let cell = tableView.cellForRow(at: indexPath) as? ChatMarkdownCell {
                    cell.stopStreaming()
                }
                break
            }
        }
    }
    
    private func setupInputArea() {
        // 假流式按钮
        let button = UIButton(type: .system)
        button.setTitle("假流式", for: .normal)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 20
        button.addTarget(self, action: #selector(handleSend), for: .touchUpInside)

        view.addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false

        // 真流式按钮
        let realStreamButton = UIButton(type: .system)
        realStreamButton.setTitle("真流式", for: .normal)
        realStreamButton.backgroundColor = .systemGreen
        realStreamButton.setTitleColor(.white, for: .normal)
        realStreamButton.layer.cornerRadius = 20
        realStreamButton.addTarget(self, action: #selector(handleRealStreamSend), for: .touchUpInside)

        view.addSubview(realStreamButton)
        realStreamButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            button.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            button.trailingAnchor.constraint(equalTo: view.centerXAnchor, constant: -10),
            button.widthAnchor.constraint(equalToConstant: 100),
            button.heightAnchor.constraint(equalToConstant: 44),

            realStreamButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            realStreamButton.leadingAnchor.constraint(equalTo: view.centerXAnchor, constant: 10),
            realStreamButton.widthAnchor.constraint(equalToConstant: 100),
            realStreamButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    
    // 在 ChatViewController 类中

    // MARK: - Markdown 分割工具

    /// 按章节标题分割 Markdown 内容
    /// - Parameter markdown: 完整的 Markdown 文本
    /// - Returns: 分割后的块数组，每个块是一个完整的章节
    private func splitMarkdownBySection(_ markdown: String) -> [String] {
        var blocks: [String] = []
        var currentBlock = ""

        let lines = markdown.components(separatedBy: "\n")

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // 检测是否是标题行（# 或 ## 开头）
            let isHeading = trimmedLine.hasPrefix("# ") ||
                            trimmedLine.hasPrefix("## ") ||
                            trimmedLine.hasPrefix("### ")

            if isHeading && !currentBlock.isEmpty {
                // 遇到新标题，保存当前块
                blocks.append(currentBlock)
                currentBlock = line + "\n"
            } else {
                // 继续累积当前块
                currentBlock += line + "\n"
            }
        }

        // 保存最后一个块
        if !currentBlock.isEmpty {
            blocks.append(currentBlock)
        }

        print("📦 [RealStream] Split markdown into \(blocks.count) blocks")
        return blocks
    }

    // MARK: - 真流式发送

    /// 当前真流式的定时器
    private var realStreamTimer: Timer?
    /// 当前真流式的块索引
    private var realStreamBlockIndex: Int = 0
    /// 当前真流式的块数组
    private var realStreamBlocks: [String] = []
    /// 当前真流式的 Cell
    private weak var realStreamCell: ChatMarkdownCell?
    /// 当前真流式的 IndexPath
    private var realStreamIndexPath: IndexPath?

    @objc private func handleRealStreamSend() {
        guard !isSending else { return }
        isSending = true

        let userText = "请用真流式给我写一段 Markdown。"
        let aiResponseText = demoMarkdown

        // 1. 用户消息
        let userMsg = ChatMessage(content: userText, isUser: true)
        messages.append(userMsg)
        insertRowAndScroll(animated: true)

        // 2. 插入 Bot Loading
        let botMsg = ChatMessage(content: "", isUser: false, isStreaming: false, isLoading: true)
        messages.append(botMsg)
        let botIndexPath = IndexPath(row: messages.count - 1, section: 0)
        tableView.insertRows(at: [botIndexPath], with: .bottom)
        scrollToBottom(animated: true)

        // 3. 模拟网络延迟后开始真流式
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }

            // 分割 Markdown 内容
            self.realStreamBlocks = self.splitMarkdownBySection(aiResponseText)
            self.realStreamBlockIndex = 0
            self.realStreamIndexPath = botIndexPath

            // 更新数据源状态
            self.messages[botIndexPath.row].isLoading = false
            self.messages[botIndexPath.row].isStreaming = true
            self.messages[botIndexPath.row].content = ""

            // 获取 Cell
            if let cell = self.tableView.cellForRow(at: botIndexPath) as? ChatMarkdownCell {
                self.realStreamCell = cell

                // 绑定高度回调
                cell.onContentHeightChanged = { [weak self, weak cell] in
                    guard let self = self, let cell = cell else { return }
                    UIView.performWithoutAnimation {
                        self.tableView.performBatchUpdates(nil, completion: nil)
                    }
                    if cell.isStreaming {
                        self.scrollToBottom(animated: false)
                    }
                }

                // 开始真流式
                cell.beginRealStreaming(
                    onStart: { [weak self] in
                        self?.messages[botIndexPath.row].isLoading = false
                        self?.messages[botIndexPath.row].isStreaming = true
                        self?.isSending = false
                    },
                    completion: { [weak self] in
                        guard let self = self else { return }
                        self.messages[botIndexPath.row].content = aiResponseText
                        self.messages[botIndexPath.row].isStreaming = false
                        self.isSending = true
                        print("✅ [RealStream] Streaming completed!")
                    }
                )

                // 启动定时器，模拟网络数据分块到达
                self.startRealStreamTimer()
            } else {
                // Cell 不可见，直接显示最终结果
                self.messages[botIndexPath.row].content = aiResponseText
                self.messages[botIndexPath.row].isStreaming = false
                self.isSending = true
                self.tableView.reloadRows(at: [botIndexPath], with: .none)
            }
        }
    }

    /// 启动真流式定时器
    private func startRealStreamTimer() {
        // 每 0.3 秒发送一个块，模拟网络数据到达
        realStreamTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            if self.realStreamBlockIndex < self.realStreamBlocks.count {
                let block = self.realStreamBlocks[self.realStreamBlockIndex]
                self.realStreamCell?.appendBlock(block)
                print("📤 [RealStream] Sent block \(self.realStreamBlockIndex + 1)/\(self.realStreamBlocks.count)")
                self.realStreamBlockIndex += 1
            } else {
                // 所有块发送完毕
                timer.invalidate()
                self.realStreamTimer = nil
                self.realStreamCell?.endRealStreaming()
                print("🏁 [RealStream] All blocks sent, ending stream")
            }
        }
    }

    /// 停止真流式
    private func stopRealStream() {
        realStreamTimer?.invalidate()
        realStreamTimer = nil
        realStreamCell?.endRealStreaming()
    }

    @objc private func handleSend() {
            guard !isSending else { return }
            isSending = true
            
            let userText = "请给我写一段 Markdown。"
            let aiResponseText = demoMarkdown // 假设这是那个长文本
            
            // 1. 用户消息... (省略)
            let userMsg = ChatMessage(content: userText, isUser: true)
            messages.append(userMsg)
            insertRowAndScroll(animated: true)
            
            // 2. 插入 Bot Loading... (省略)
            var botMsg = ChatMessage(content: "", isUser: false, isStreaming: false, isLoading: true)
            messages.append(botMsg)
            let botIndexPath = IndexPath(row: messages.count - 1, section: 0)
            tableView.insertRows(at: [botIndexPath], with: .bottom)
            scrollToBottom(animated: true)
            
            // 3. 模拟网络请求
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self = self else { return }
                self.isSending = false
                
                // --- 更新数据源状态 ---
                self.messages[botIndexPath.row].isLoading = false
                self.messages[botIndexPath.row].isStreaming = true
                self.messages[botIndexPath.row].content = ""
                self.isSending = false
                
                // --- 获取 Cell ---
                if let cell = self.tableView.cellForRow(at: botIndexPath) as? ChatMarkdownCell {
                    
                    // ❌ 删掉这行！不要调用 configure！
                    // cell.configure(with: self.messages[botIndexPath.row])
                    // 原因：调用 configure 会立即隐藏 Loading 动画，导致接下来的几秒钟白屏。
                    // 我们现在的策略是：保持当前 UI (Loading状态) 不变，直接 startStreaming。
                    
                    // 绑定高度回调

                    cell.onContentHeightChanged = { [weak self, weak cell] in
                        guard let self = self, let cell = cell else { return }

                        // ⭐️ 核心修复 2：去除隐式动画
                        // performBatchUpdates 默认带有动画，高频调用会导致闪烁。
                        // 使用 performWithoutAnimation 强制关闭动画，使高度变化平滑。
                        UIView.performWithoutAnimation {
                            self.tableView.performBatchUpdates(nil, completion: nil)
                        }

                        // ⭐️ 关键修复：只在流式输出期间才自动滚动
                        if cell.isStreaming {
                            self.isSending = false
                            self.scrollToBottom(animated: false)
                        }
                    }
                    
                    // 开始流式输出 (Cell 内部会在准备好后自动切换 UI)
                            cell.startStreaming(
                                text: aiResponseText,
                                // ✅ 新增：在回调里才更新状态
                                onStart: { [weak self] in
                                    // 只有当 Cell 真的准备好显示文字时，才告诉数据源“加载结束”
                                    // 这样在那 4 秒预处理期间，UI 依然保持 Loading 状态
                                    self?.messages[botIndexPath.row].isLoading = false
                                    self?.messages[botIndexPath.row].isStreaming = true
                                    self?.messages[botIndexPath.row].content = ""
                                    self?.isSending = false
                                },
                                completion: { [weak self] in
                                    self?.messages[botIndexPath.row].content = aiResponseText
                                    self?.messages[botIndexPath.row].isStreaming = false
                                    self?.isSending = true
                                }
                            )
                } else {
                    // 如果 Cell 不可见，直接刷新显示最终结果
                    self.messages[botIndexPath.row].content = aiResponseText
                    self.messages[botIndexPath.row].isStreaming = false
                    self.isSending = true
                    self.tableView.reloadRows(at: [botIndexPath], with: .none)
                }
            }
        }

    // 辅助方法：插入并滚动
    private func insertRowAndScroll(animated: Bool) {
        let indexPath = IndexPath(row: messages.count - 1, section: 0)
        tableView.insertRows(at: [indexPath], with: .bottom)
        scrollToBottom(animated: animated)
    }

//    private func scrollToBottom(animated: Bool) {
//        guard !messages.isEmpty else { return }
//        let indexPath = IndexPath(row: messages.count - 1, section: 0)
//        tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
//    }

    // 简单的防连点标记
    private var isSending = false
    
    private func startBotResponse() {
        // 1. 先插入一个内容为空的 Bot 消息
        // isStreaming = true 告诉 Cell 不要直接渲染 content，而是等我们手动调用 stream
        let botMsg = ChatMessage(content: "", isUser: false, isStreaming: true)
        messages.append(botMsg)
        
        let indexPath = IndexPath(row: messages.count - 1, section: 0)
        tableView.insertRows(at: [indexPath], with: .fade)
        scrollToBottom(animated: true)
        
        // 2. 获取刚才插入的 Cell 实例
        // 注意：必须 layout 之后才能拿到 cell，否则可能为 nil
        tableView.layoutIfNeeded()
        
        guard let cell = tableView.cellForRow(at: indexPath) as? ChatMarkdownCell else { return }
        
        // 3. 配置高度变化回调
        cell.onContentHeightChanged = { [weak self, weak cell] in
            guard let self = self, let cell = cell else { return }

            // ⭐️ 核心逻辑：通知 TableView 高度变了，请重新布局
            // 使用 performBatchUpdates(nil) 不会 reload cell，只会平滑调整高度
            self.tableView.performBatchUpdates(nil, completion: nil)

            // ⭐️ 关键修复：只在流式输出期间才自动滚动
            // 用户交互（折叠/展开）不应该触发滚动
            if cell.isStreaming {
                self.scrollToBottom(animated: false)
            }
        }
        
        // 4. 开始流式输出
        // 实际开发中，这里你会监听网络 socket/SSE 的数据包，不断调用 markdownView.append()
        // 这里使用工具类自带的模拟器
        cell.startStreaming(text: demoMarkdown) { [weak self] in
            // 完成后更新数据源，标记不再 streaming
            self?.messages[indexPath.row].content = self?.demoMarkdown ?? ""
            self?.messages[indexPath.row].isStreaming = false
            self?.isSending = false
        }
        
        // 为了确保模型数据同步（如果 Cell 复用导致数据丢失），
        // 理想情况下你应该在 socket 收到 chunk 时同时更新 messages[index].content
    }
    
    private func insertRowAndScroll() {
        let indexPath = IndexPath(row: messages.count - 1, section: 0)
        tableView.insertRows(at: [indexPath], with: .bottom)
        scrollToBottom(animated: true)
    }
    
    private func scrollToBottom(animated: Bool) {
        // ⭐️ 关键修复：只有当允许自动滚动时才执行
        guard !messages.isEmpty, shouldAutoScroll else { return }

        let indexPath = IndexPath(row: messages.count - 1, section: 0)

        // 稍微做一点防抖，防止高频调用
        DispatchQueue.main.async {
            self.tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
        }
    }
}

// MARK: - DataSource & Delegate
extension TableViewStreamingViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ChatCell", for: indexPath) as! ChatMarkdownCell
        let msg = messages[indexPath.row]
        cell.configure(with: msg)

        // ⭐️ 设置用户交互回调：当用户点击目录、链接等元素时，停止自动滚动
        cell.onUserInteraction = { [weak self] in
            self?.shouldAutoScroll = false
        }

        return cell
    }

    // MARK: - 滚动控制

    /// 用户开始拖动时触发
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // 用户主动滚动时，检查是否在底部
        checkIfAtBottom(scrollView)
    }

    /// 滚动过程中持续触发
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // 持续检查是否在底部
        checkIfAtBottom(scrollView)
    }

    /// 检查是否在底部
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
        // 找到正在流式输出的消息
        guard let streamingIndex = messages.firstIndex(where: { $0.isStreaming }) else {
            return
        }

        let indexPath = IndexPath(row: streamingIndex, section: 0)
        guard let cell = tableView.cellForRow(at: indexPath) as? ChatMarkdownCell else {
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
