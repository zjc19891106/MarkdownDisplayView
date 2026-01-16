//
//  CrashReproViewController.swift
//  CocoapodsMDExample
//
//  Created by 朱继超 on 12/19/25.
//

import UIKit
import MarkdownDisplayKit

final class CrashReproViewController: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .plain)
    private var messages: [String] = []
    private var cachedHeights: [Int: CGFloat] = [:]
    private var heightCalculator: MarkdownHeightCalculator?
    private let cellVerticalPadding: CGFloat = 24
    private let heightSafetyPadding: CGFloat = 8
    private let firstRowExtraPadding: CGFloat = 12
    private var visibleRowCount: Int = 0
    private var nextIndexToMeasure: Int = 0

    private lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("关闭", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupTableView()
        setupCloseButton()
        heightCalculator = MarkdownHeightCalculator(hostView: view)
        prepareMessages()
    }

    private func setupTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.estimatedRowHeight = 120
        tableView.rowHeight = UITableView.automaticDimension
        tableView.register(MarkdownHistoryCell.self, forCellReuseIdentifier: MarkdownHistoryCell.reuseIdentifier)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 44),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupCloseButton() {
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    private func prepareMessages() {
        let baseTableArray = ["""
            # 安装方案
            
            
            ## 方案 1: GitHub 直接安装 (最快)
            
            `npm install -g github:zjc19891106/easeim-mcp-server`
            
            或指定分支/tag
            
            `npm install -g github:zjc19891106/easeim-mcp-server#v1.0.0`
            
            
            ---
            ## 方案 2: 手动配置路径 (零发布)
            
            用户克隆repo或者下载源码
            git clone https://github.com/zjc19891106/easeim-mcp-server
            cd easeim-mcp-server/EMIntegrationAssistant/easeim-mcp-server/ && npm install && npm run build
            
            ## 配置 Claude（使用绝对路径）
            ```Json
            {
              "mcpServers": {
                "easeim":{
                  "command": "node",
                  "args": ["/Path/easeim-mcp-server/EMIntegrationAssistant/easeim-mcp-server/dist/index.js"]
                }
              }
            }
            ```
            """
        ,
        """
            # MCP 工具列表（19 个）

            ### 基础工具（10 个）

            | 工具 | 描述 |
            |------|------|
            | `lookup_error` | 查询错误码含义、原因和解决方案 |
            | `search_api` | 搜索 API 文档，支持平台/层级过滤 |
            | `search_source` | 搜索 UIKit 源码，支持组件过滤 |
            | `get_guide` | 获取集成指南和最佳实践 |
            | `diagnose` | 根据症状诊断错误原因 |
            | `read_doc` | 读取完整 API 文档 |
            | `read_source` | 读取源码文件（支持行范围） |
            | `list_config_options` | 列出 Appearance 配置项 |
            | `get_extension_points` | 获取可继承类和协议 |
            | `get_config_usage` | 查询配置项的使用详情 |
           """
                              ,
        """
            # 智能化工具（4 个）

            | 工具 | 描述 |
            |------|------|
            | `smart_assist` | 🧠 自然语言智能助手，**支持上下文感知**，自动理解意图和连续性问题 |
            | `generate_code` | 📝 代码生成器，生成完整代码模板 |
            | `explain_class` | 📖 类解释器，说明继承关系和用法 |
            | `list_scenarios` | 📋 列出所有支持的开发场景 |
          """,
                              """
# 1. 数据处理与索引生成
- ✅ 文档索引生成脚本
  - 解析 49 个 API 模块文档
  - 提取 99 个错误码（包含描述、原因、解决方案）
  - 生成 56 个 API 快速索引
  - 索引大小：113 KB

- ✅ 源码索引生成脚本
  - 解析 3 个 UIKit 组件
  - 处理 326 个 Swift 源文件
  - 提取 2605 个代码符号（类、方法、属性等）
  - 索引大小：862 KB
""",
                              """
# 2. MCP Server 核心功能
- ✅ 搜索引擎
  - `DocSearch` - 文档搜索引擎（支持 API、错误码、模块搜索）
  - `SourceSearch` - 源码搜索引擎（支持类、方法、属性搜索）

- ✅ MCP Tools（14 个工具）
  1. `lookup_error` - 错误码查询
  2. `search_api` - API 搜索（支持中英文）
  3. `search_source` - 源码搜索（支持按组件过滤）
  4. `get_guide` - 获取集成指南
  5. `diagnose` - 问题诊断（根据症状匹配错误码）
  6. `read_doc` - 读取完整文档
  7. `read_source` - 读取源码文件
  8. `list_config_options` - 列出 UIKit 配置项 (New!)
  9. `get_extension_points` - 获取 UIKit 扩展点 (New!)
  10. `get_config_usage` - 查询配置项使用情况 (New!)
  11. `smart_assist` - 🧠 智能助手 (New!)
  12. `generate_code` - 📝 代码生成器 (New!)
  13. `explain_class` - 📖 类解释器 (New!)
  14. `list_scenarios` - 📋 场景列表 (New!)
""", """
# 3. 项目配置与文档
- ✅ TypeScript 配置
- ✅ npm 包配置
- ✅ 完整的 README 文档
- ✅ Claude Code 配置示例
- ✅ 项目结构清晰
"""
        ]
        messages = baseTableArray
        cachedHeights.removeAll()
        visibleRowCount = 0
        nextIndexToMeasure = 0
        tableView.reloadData()
        precomputeHeightsSequentially()
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func precomputeHeightsSequentially() {
        guard let calculator = heightCalculator else { return }
        let width = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        let contentWidth = width - 32

        guard nextIndexToMeasure < messages.count else { return }
        let index = nextIndexToMeasure
        let markdown = messages[index]
        nextIndexToMeasure += 1

        calculator.height(for: markdown, width: contentWidth, configuration: .default) { [weak self] height in
            guard let self else { return }
            let extraPadding = index == 0 ? self.firstRowExtraPadding : 0
            self.cachedHeights[index] = height + self.cellVerticalPadding + self.heightSafetyPadding + extraPadding
            self.visibleRowCount += 1
            let indexPath = IndexPath(row: index, section: 0)
            if self.visibleRowCount == 1 {
                self.tableView.insertRows(at: [indexPath], with: .none)
            } else {
                self.tableView.insertRows(at: [indexPath], with: .none)
            }
            self.precomputeHeightsSequentially()
        }
    }
}

extension CrashReproViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visibleRowCount
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: MarkdownHistoryCell.reuseIdentifier,
            for: indexPath
        ) as? MarkdownHistoryCell else {
            return UITableViewCell(style: .default, reuseIdentifier: "fallback")
        }
        let height = cachedHeights[indexPath.row]
        cell.configure(markdown: messages[indexPath.row], height: height)
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if let height = cachedHeights[indexPath.row] {
            return height
        }
        return tableView.estimatedRowHeight
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let markdownCell = cell as? MarkdownHistoryCell else { return }
        let contentWidth = tableView.bounds.width - 32
        let extraPadding = indexPath.row == 0 ? firstRowExtraPadding : 0
        let measured = markdownCell.measuredHeight(forWidth: contentWidth) + cellVerticalPadding + extraPadding
        if let cached = cachedHeights[indexPath.row] {
            if abs(cached - measured) > 2 {
                cachedHeights[indexPath.row] = measured
                tableView.beginUpdates()
                tableView.endUpdates()
            }
        } else {
            cachedHeights[indexPath.row] = measured
            tableView.beginUpdates()
            tableView.endUpdates()
        }
    }
}

final class MarkdownHistoryCell: UITableViewCell {
    static let reuseIdentifier = "MarkdownHistoryCell"
    private static let estimatedContentHeight: CGFloat = 120 - 24

    private let markdownView = MarkdownViewTextKit()
    private var heightConstraint: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        contentView.clipsToBounds = true
        markdownView.enableTypewriterEffect = false
        contentView.addSubview(markdownView)
        markdownView.translatesAutoresizingMaskIntoConstraints = false
        markdownView.clipsToBounds = true

        heightConstraint = markdownView.heightAnchor.constraint(equalToConstant: 0)
        heightConstraint?.priority = .required

        NSLayoutConstraint.activate([
            markdownView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            markdownView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            markdownView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            markdownView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            heightConstraint ?? markdownView.heightAnchor.constraint(equalToConstant: 0)
        ])

    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(markdown: String, height: CGFloat?) {
        if let height {
            heightConstraint?.constant = height - 24
        } else {
            heightConstraint?.constant = Self.estimatedContentHeight
        }
        markdownView.markdown = markdown
    }

    func measuredHeight(forWidth width: CGFloat) -> CGFloat {
        layoutIfNeeded()
        let size = markdownView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        )
        return max(size.height, markdownView.bounds.height)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        markdownView.resetForReuse()
        heightConstraint?.constant = Self.estimatedContentHeight
    }
}

final class MarkdownHeightCalculator {
    private struct Task {
        let key: String
        let markdown: String
        let width: CGFloat
        let configuration: MarkdownConfiguration
        let completion: (CGFloat) -> Void
    }

    private let sizingView = MarkdownViewTextKit()
    private let containerView = UIView()
    private var widthConstraint: NSLayoutConstraint?
    private var pendingTasks: [Task] = []
    private var isMeasuring = false
    private var cache: [String: CGFloat] = [:]
    private var token: Int = 0
    private var timeoutWorkItem: DispatchWorkItem?

    init(hostView: UIView) {
        containerView.isHidden = true
        containerView.isUserInteractionEnabled = false
        containerView.translatesAutoresizingMaskIntoConstraints = false
        hostView.addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: hostView.topAnchor, constant: -10000),
            containerView.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
            containerView.heightAnchor.constraint(equalToConstant: 1)
        ])

        sizingView.translatesAutoresizingMaskIntoConstraints = false
        sizingView.enableTypewriterEffect = false
        containerView.addSubview(sizingView)
        widthConstraint = sizingView.widthAnchor.constraint(equalToConstant: hostView.bounds.width)
        widthConstraint?.priority = .required

        NSLayoutConstraint.activate([
            sizingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            sizingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            sizingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            widthConstraint ?? sizingView.widthAnchor.constraint(equalToConstant: hostView.bounds.width)
        ])
    }

    func height(
        for markdown: String,
        width: CGFloat,
        configuration: MarkdownConfiguration,
        completion: @escaping (CGFloat) -> Void
    ) {
        let key = Self.makeKey(markdown: markdown, width: width, configuration: configuration)
        if let cached = cache[key] {
            completion(cached)
            return
        }

        let task = Task(
            key: key,
            markdown: markdown,
            width: width,
            configuration: configuration,
            completion: completion
        )
        pendingTasks.append(task)
        startNextIfNeeded()
    }

    private func startNextIfNeeded() {
        guard !isMeasuring, !pendingTasks.isEmpty else { return }
        isMeasuring = true
        let task = pendingTasks.removeFirst()
        token += 1
        let currentToken = token

        sizingView.configuration = task.configuration
        widthConstraint?.constant = task.width
        containerView.layoutIfNeeded()

        timeoutWorkItem?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard currentToken == self.token else { return }
            let fallbackHeight = self.sizingView.systemLayoutSizeFitting(
                CGSize(width: task.width, height: UIView.layoutFittingCompressedSize.height)
            ).height
            let finalHeight = max(1, fallbackHeight)
            self.cache[task.key] = finalHeight
            task.completion(finalHeight)
            self.isMeasuring = false
            self.startNextIfNeeded()
        }
        timeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: timeout)

        sizingView.onHeightChange = { [weak self] height in
            guard let self else { return }
            guard currentToken == self.token else { return }
            let fittingHeight = self.sizingView.systemLayoutSizeFitting(
                CGSize(width: task.width, height: UIView.layoutFittingCompressedSize.height)
            ).height
            let finalHeight = max(height, fittingHeight, 1)
            self.cache[task.key] = finalHeight
            task.completion(finalHeight)
            self.timeoutWorkItem?.cancel()
            self.isMeasuring = false
            self.startNextIfNeeded()
        }
        sizingView.markdown = task.markdown
    }

    private static func makeKey(
        markdown: String,
        width: CGFloat,
        configuration: MarkdownConfiguration
    ) -> String {
        let fontSignature = "\(configuration.bodyFont.pointSize)-\(configuration.codeFont.pointSize)-\(configuration.headingSpacing)-\(configuration.paragraphSpacing)"
        let colorSignature = "\(configuration.textColor.description)-\(configuration.codeBackgroundColor.description)"
        return "\(markdown.hashValue)|\(width)|\(fontSignature)|\(colorSignature)"
    }
}
