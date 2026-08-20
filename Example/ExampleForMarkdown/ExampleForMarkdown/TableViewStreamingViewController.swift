//
//  TableViewStreamingViewController.swift
//  CocoapodsMDExample
//
//  Created by Claude on 12/22/25.
//

import UIKit
import MarkdownDisplayView

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

    func apply(color: UIColor) {
        dots.forEach { $0.backgroundColor = color }
    }
}


class ChatMarkdownCell: UITableViewCell {

    // MARK: - UI Components
    private let markdownView = MarkdownViewTextKit()
    private let typingIndicator = TypingIndicatorView() // 确保你有这个类
    private let bgView = UIView()
    private var appliedThemeRawValue: Int?
    // 新增：记录上一次通知的高度，防止重复通知
    private var lastReportedHeight: CGFloat = 0

    // MARK: - Callbacks
    var onContentHeightChanged: (() -> Void)?

    // ⭐️ 用户交互回调（当用户点击目录、链接等元素时通知外部）
    var onUserInteraction: (() -> Void)?

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
    func configure(with message: ChatMessage, theme: MarkdownDemoTheme?) {

        // 1. 设置左右对齐颜色
        // ⭐️ 修复：只在颜色需要改变时才设置，避免触发 scheduleRerender
        if let theme {
            if appliedThemeRawValue != theme.rawValue {
                markdownView.configuration = theme.makeConfiguration()
                appliedThemeRawValue = theme.rawValue
            }
            bgView.layer.borderWidth = 1
            bgView.layer.borderColor = (message.isUser ? theme.accentColor : theme.borderColor).cgColor
            typingIndicator.apply(color: theme.accentColor)
        } else {
            let targetColor: UIColor = message.isUser ? .white : .label
            if markdownView.configuration.textColor != targetColor {
                markdownView.configuration.textColor = targetColor
            }
            bgView.layer.borderWidth = 0
        }

        if message.isUser {
            // 用户消息：右对齐 + 固定宽度
            alignConstraints[0].isActive = false  // AI leading
            alignConstraints[1].isActive = false  // AI width
            alignConstraints[2].isActive = true   // User trailing
            alignConstraints[3].isActive = true   // User width
            bgView.backgroundColor = theme.map {
                $0.accentColor.withAlphaComponent($0.interfaceStyle == .dark ? 0.26 : 0.14)
            } ?? .systemBlue
        } else {
            // AI 消息：左对齐 + 固定宽度
            alignConstraints[0].isActive = true   // AI leading
            alignConstraints[1].isActive = true   // AI width
            alignConstraints[2].isActive = false  // User trailing
            alignConstraints[3].isActive = false  // User width
            bgView.backgroundColor = theme?.panelColor
                ?? UIColor(red: 242/255, green: 242/255, blue: 247/255, alpha: 1) // 系统灰
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
                // 静态消息：一次性渲染，不保留 diff 基线以省内存
                markdownView.retainsDiffBaseline = false
                markdownView.markdown = message.content
            }
        }
    }
    
    // MARK: - 智能流式 API

    /// 智能流式完成回调（保存以便后续调用）
    private var realStreamCompletion: (() -> Void)?

    /// 开始智能流式模式
    /// - Parameters:
    ///   - onStart: 开始回调
    ///   - completion: 完成回调
    func beginRealStreaming(onStart: (() -> Void)? = nil, completion: @escaping () -> Void) {
        isCurrentlyStreaming = true
        realStreamCompletion = completion
        lastReportedHeight = 0

        // ⚠️ 注意：不在 onComplete 中设置 isCurrentlyStreaming = false
        // 因为 endRealStreaming 调用时 TypewriterEngine 可能还在显示内容
        // 我们在 endRealStreaming 中手动处理完成逻辑
        markdownView.beginRealStreaming(autoScrollBottom: false)

        // 立即执行 UI 切换
        typingIndicator.isHidden = true
        typingIndicator.stopAnimating()
        markdownView.isHidden = false
        NSLayoutConstraint.deactivate(loadingConstraints)
        NSLayoutConstraint.activate(contentConstraints)
        layoutIfNeeded()

        onStart?()
    }

    /// ⭐️ 追加流式数据（智能缓存模式）
    /// 让 MarkdownStreamBuffer 自动检测完整模块
    func appendStreamData(_ data: String) {
        markdownView.appendStreamData(data)
    }

    /// 结束智能流式
    func endRealStreaming() {
        // ⭐️ 使用 completion 回调替代固定延迟
        // 确保在 TypewriterEngine 完全结束后才触发完成逻辑
        markdownView.endRealStreaming { [weak self] in
            guard let self = self else { return }
            self.isCurrentlyStreaming = false
            self.realStreamCompletion?()
            self.realStreamCompletion = nil
            print("[FOOTNOTE_DEBUG] 🔴 Cell.endRealStreaming completion called")
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        typingIndicator.stopAnimating()
        markdownView.resetForReuse()
        onContentHeightChanged = nil
        lastReportedHeight = 0
        // ⭐️ 重置流式标记
        isCurrentlyStreaming = false

        // 复用时重置为默认状态 (假设是内容模式)
        markdownView.isHidden = false
        typingIndicator.isHidden = true
        NSLayoutConstraint.deactivate(loadingConstraints)
        NSLayoutConstraint.activate(contentConstraints)
    }
}

class TableViewStreamingViewController: UIViewController {

    private let tableView = UITableView()
    private let selectedTheme = MarkdownDemoThemeStore.selectedTheme
    private let inputContainer = UIView() // 模拟底部输入框区域
    private var messages: [ChatMessage] = []

    // 模拟长文本
    private let demoMarkdown = sampleMarkdown

    // ⭐️ 自动滚动控制
    private var shouldAutoScroll: Bool = true  // 是否应该自动滚动
    private let autoScrollThreshold: CGFloat = 100  // 距离底部多少时认为"在底部"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if let selectedTheme {
            overrideUserInterfaceStyle = selectedTheme.interfaceStyle
        }
        view.backgroundColor = .systemBackground
        setupTableView()
        setupInputArea()
        applySelectedTheme()
        
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
        closeButton.tintColor = selectedTheme?.accentColor ?? .systemBlue
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        
        let stopButton = UIButton(type: .system)
        stopButton.setTitle("Stop", for: .normal)
        stopButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        stopButton.addTarget(self, action: #selector(stopStreaming), for: .touchUpInside)
        stopButton.tintColor = selectedTheme?.accentColor ?? .systemBlue
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
        print("[FOOTNOTE_DEBUG] ⛔️ stopStreaming button pressed!")
        // 停止真流式
        stopRealStream()

        // 停止当前正在流式输出的消息
        for (index, msg) in messages.enumerated() {
            if msg.isStreaming {
                messages[index].isStreaming = false
                self.isSending = true
                break
            }
        }
    }
    
    private func setupInputArea() {
        // ⭐️ 新增：智能流式按钮（使用 SmartBuffer 自动检测模块）
        let smartStreamButton = UIButton(type: .system)
        smartStreamButton.setTitle("智能流式", for: .normal)
        smartStreamButton.backgroundColor = selectedTheme?.accentColor ?? .systemOrange
        smartStreamButton.setTitleColor(selectedTheme?.canvasColor ?? .white, for: .normal)
        smartStreamButton.layer.cornerRadius = 20
        smartStreamButton.addTarget(self, action: #selector(handleSmartStreamSend), for: .touchUpInside)

        view.addSubview(smartStreamButton)
        smartStreamButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // 智能流式按钮
            smartStreamButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            smartStreamButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            smartStreamButton.widthAnchor.constraint(equalToConstant: 80),
            smartStreamButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func applySelectedTheme() {
        guard let theme = selectedTheme else { return }
        view.backgroundColor = theme.canvasColor
        tableView.backgroundColor = theme.canvasColor
        tableView.indicatorStyle = theme.interfaceStyle == .dark ? .white : .black
        inputContainer.backgroundColor = theme.panelColor
    }
    
    /// 当前智能流式的 Cell
    private weak var realStreamCell: ChatMarkdownCell?
    /// 当前智能流式的 IndexPath
    private var realStreamIndexPath: IndexPath?

    /// 停止当前智能流式
    private func stopRealStream() {
        print("[FOOTNOTE_DEBUG] ⛔️ stopRealStream called!")
        smartStreamTimer?.invalidate()
        smartStreamTimer = nil
        flushSmartStreamLayoutUpdate()
        realStreamCell?.endRealStreaming()
    }

    // MARK: - ⭐️ 智能流式（SmartBuffer 模式）

    /// 智能流式定时器
    private var smartStreamTimer: Timer?
    /// 智能流式当前字符索引
    private var smartStreamCharIndex: Int = 0
    /// 智能流式完整文本
    private var smartStreamFullText: String = ""
    private var isSmartStreamLayoutUpdateInFlight = false
    private var needsSmartStreamLayoutUpdate = false
    private static let streamPerfLoggingEnabled: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.environment["MD_STREAM_PERF_LOG"] == "1"
        #else
        false
        #endif
    }()
    private var streamPerfHostWindowStart = CACurrentMediaTime()
    private var streamPerfHostRequests = 0
    private var streamPerfHostCoalesced = 0
    private var streamPerfHostBatches = 0
    private var streamPerfHostBatchTotalMS = 0.0
    private var streamPerfHostBatchMaxMS = 0.0

    /// 处理智能流式发送（模拟逐字符到达，测试 SmartBuffer）
    @objc private func handleSmartStreamSend() {
        guard !isSending else { return }
        isSending = true
        resetSmartStreamHostPerformanceLog()
        flushSmartStreamLayoutUpdate(force: false)

        let userText = "请用智能流式给我写一段 Markdown。"
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

        // 3. 模拟网络延迟后开始智能流式
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }

            // 初始化智能流式状态
            self.smartStreamFullText = aiResponseText
            self.smartStreamCharIndex = 0
            self.realStreamIndexPath = botIndexPath

            // 更新数据源状态
            self.messages[botIndexPath.row].isLoading = false
            self.messages[botIndexPath.row].isStreaming = true
            self.messages[botIndexPath.row].content = ""

            // 获取 Cell
            if let cell = self.tableView.cellForRow(at: botIndexPath) as? ChatMarkdownCell {
                self.realStreamCell = cell

                // 绑定高度回调
                cell.onContentHeightChanged = { [weak self] in
                    self?.scheduleSmartStreamLayoutUpdate()
                }

                // StreamBuffer 会自动识别完整 Markdown 模块。
                cell.beginRealStreaming(
                    onStart: { [weak self] in
                        self?.messages[botIndexPath.row].isLoading = false
                        self?.messages[botIndexPath.row].isStreaming = true
                        self?.isSending = false
                    },
                    completion: { [weak self] in
                        guard let self = self else { return }
                        self.flushSmartStreamLayoutUpdate()
                        self.messages[botIndexPath.row].content = aiResponseText
                        self.messages[botIndexPath.row].isStreaming = false
                        self.isSending = true
                        print("✅ [SmartStream] Streaming completed!")
                    }
                )

                // 启动定时器，模拟网络数据逐字符到达
                self.startSmartStreamTimer()
            } else {
                // Cell 不可见，直接显示最终结果
                self.messages[botIndexPath.row].content = aiResponseText
                self.messages[botIndexPath.row].isStreaming = false
                self.isSending = true
                self.tableView.reloadRows(at: [botIndexPath], with: .none)
            }
        }
    }

    /// ⭐️ 是否已经触发过网络卡顿模拟
    private var hasSimulatedNetworkStall: Bool = false

    /// 启动智能流式定时器（模拟逐字符/逐块网络数据到达）
    private func startSmartStreamTimer() {
        print("[SmartStream] ⏰ Starting smart stream timer, fullText.count=\(smartStreamFullText.count)")
        hasSimulatedNetworkStall = false  // 重置标记
        startActualSmartStreamTimer()
    }

    /// Markdown 已在显示帧内合并增量高度。宿主立即开始 self-sizing，只在上一个
    /// batch 尚未结束时合并后续请求，避免再增加一层 20Hz 延迟暴露旧 Cell 高度。
    private func scheduleSmartStreamLayoutUpdate() {
        requestSmartStreamLayoutUpdate()
    }

    private func flushSmartStreamLayoutUpdate(force: Bool = true) {
        guard force
                || needsSmartStreamLayoutUpdate
                || isSmartStreamLayoutUpdateInFlight else { return }
        requestSmartStreamLayoutUpdate()
    }

    private func requestSmartStreamLayoutUpdate() {
        recordSmartStreamHostRequest(
            coalesced: isSmartStreamLayoutUpdateInFlight
        )
        needsSmartStreamLayoutUpdate = true
        guard !isSmartStreamLayoutUpdateInFlight else { return }
        performSmartStreamLayoutUpdate()
    }

    private func performSmartStreamLayoutUpdate() {
        guard needsSmartStreamLayoutUpdate, !isSmartStreamLayoutUpdateInFlight else { return }

        needsSmartStreamLayoutUpdate = false
        isSmartStreamLayoutUpdateInFlight = true
        let batchStart = CACurrentMediaTime()

        let previousOffset = tableView.contentOffset
        let indexPath = realStreamIndexPath
        let shouldFollowStream = indexPath.map {
            $0.row < messages.count && messages[$0.row].isStreaming && shouldAutoScroll
        } ?? false

        UIView.performWithoutAnimation {
            tableView.performBatchUpdates(nil) { [weak self] _ in
                guard let self else { return }
                self.isSmartStreamLayoutUpdateInFlight = false
                self.recordSmartStreamHostBatch(durationMS: (CACurrentMediaTime() - batchStart) * 1000)

                if shouldFollowStream, let indexPath, indexPath.row < self.messages.count {
                    self.tableView.scrollToRow(at: indexPath, at: .bottom, animated: false)
                } else {
                    self.tableView.setContentOffset(previousOffset, animated: false)
                }

                if self.needsSmartStreamLayoutUpdate {
                    self.requestSmartStreamLayoutUpdate()
                }
            }
        }
    }

    private func resetSmartStreamHostPerformanceLog() {
        guard Self.streamPerfLoggingEnabled else { return }
        streamPerfHostWindowStart = CACurrentMediaTime()
        streamPerfHostRequests = 0
        streamPerfHostCoalesced = 0
        streamPerfHostBatches = 0
        streamPerfHostBatchTotalMS = 0
        streamPerfHostBatchMaxMS = 0
    }

    private func recordSmartStreamHostRequest(coalesced: Bool) {
        guard Self.streamPerfLoggingEnabled else { return }
        streamPerfHostRequests += 1
        if coalesced { streamPerfHostCoalesced += 1 }
        reportSmartStreamHostPerformanceIfNeeded()
    }

    private func recordSmartStreamHostBatch(durationMS: Double) {
        guard Self.streamPerfLoggingEnabled else { return }
        streamPerfHostBatches += 1
        streamPerfHostBatchTotalMS += durationMS
        streamPerfHostBatchMaxMS = max(streamPerfHostBatchMaxMS, durationMS)
        reportSmartStreamHostPerformanceIfNeeded()
    }

    private func reportSmartStreamHostPerformanceIfNeeded() {
        let now = CACurrentMediaTime()
        guard now - streamPerfHostWindowStart >= 1 else { return }
        let cellHeight = realStreamCell?.bounds.height ?? 0
        print("[MDPERF][HOST] scope=window window=\(String(format: "%.1f", now - streamPerfHostWindowStart))s requests=\(streamPerfHostRequests) coalesced=\(streamPerfHostCoalesced) batches=\(streamPerfHostBatches) batchLatencyMS=\(String(format: "%.1f", streamPerfHostBatchTotalMS))/\(String(format: "%.1f", streamPerfHostBatchMaxMS)) cellHeight=\(String(format: "%.1f", cellHeight)) contentHeight=\(String(format: "%.1f", tableView.contentSize.height))")
        streamPerfHostWindowStart = now
        streamPerfHostRequests = 0
        streamPerfHostCoalesced = 0
        streamPerfHostBatches = 0
        streamPerfHostBatchTotalMS = 0
        streamPerfHostBatchMaxMS = 0
    }

    /// 实际的智能流式定时器
    private func startActualSmartStreamTimer() {
        // ⭐️ 关键区别：不预分割，而是模拟随机大小的数据块到达
        // 这样可以真正测试 SmartBuffer 的模块检测能力
        smartStreamTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            let fullText = self.smartStreamFullText
            let currentIndex = self.smartStreamCharIndex

            if currentIndex < fullText.count {
                // ⭐️ 模拟网络卡顿：当进度到达 10% 时，暂停 4 秒（只触发一次）
                // 10% 时队列任务较少，4 秒足够消耗完，能看到等待动画
                let progress = Double(currentIndex) / Double(fullText.count)
                if !self.hasSimulatedNetworkStall && progress >= 0.1 {
                    self.hasSimulatedNetworkStall = true  // 标记已触发
                    print("[SmartStream] ⏳ Simulating 4s network stall at 10% progress...")
                    timer.invalidate()
                    self.smartStreamTimer = nil

                    // 4 秒后恢复
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
                        guard let self = self else { return }
                        print("[SmartStream] ⏳ Network recovered, resuming...")
                        self.startActualSmartStreamTimer()
                    }
                    return
                }

                // 随机发送 10-50 个字符，模拟网络数据包大小不一
                let chunkSize = Int.random(in: 10...50)
                let endIndex = min(currentIndex + chunkSize, fullText.count)

                let startIdx = fullText.index(fullText.startIndex, offsetBy: currentIndex)
                let endIdx = fullText.index(fullText.startIndex, offsetBy: endIndex)
                let chunk = String(fullText[startIdx..<endIdx])

                // 将网络 chunk 直接交给 StreamBuffer。
                // 让 SmartBuffer 自动检测完整模块
                self.realStreamCell?.appendStreamData(chunk)
                print("📤 [SmartStream] Sent chunk: \(chunk.count) chars, progress: \(Int(progress * 100))%")

                self.smartStreamCharIndex = endIndex
            } else {
                // 所有数据发送完毕
                print("[SmartStream] ⏰ Timer ending, calling endRealStreaming")
                timer.invalidate()
                self.smartStreamTimer = nil
                self.realStreamCell?.endRealStreaming()
                print("🏁 [SmartStream] All data sent, ending stream")
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
        cell.configure(with: msg, theme: selectedTheme)

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

        shouldAutoScroll = distanceFromBottom <= autoScrollThreshold
    }
}
