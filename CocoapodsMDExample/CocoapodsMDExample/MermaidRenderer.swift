//
//  MermaidRenderer.swift
//  CocoapodsMDExample
//
//  Mermaid 图表渲染器示例
//  演示如何实现自定义代码块渲染器
//

import UIKit
import WebKit
import MarkdownDisplayKit

// MARK: - Mermaid Renderer

/// Mermaid 图表渲染器
/// 使用 WKWebView 渲染 Mermaid 语法的图表
public final class MermaidRenderer: MarkdownCodeBlockRenderer {

    public let supportedLanguage = "mermaid"

    public init() {}

    public func renderCodeBlock(
        code: String,
        configuration: MarkdownConfiguration,
        containerWidth: CGFloat
    ) -> UIView {
        let size = calculateSize(code: code, configuration: configuration, containerWidth: containerWidth)
        let view = MermaidWebView(code: code, frame: CGRect(origin: .zero, size: size))
        return view
    }

    public func calculateSize(
        code: String,
        configuration: MarkdownConfiguration,
        containerWidth: CGFloat
    ) -> CGSize {
        let width = containerWidth - 32
        let estimatedHeight = estimateDiagramHeight(code: code, width: width)
        return CGSize(width: width, height: estimatedHeight)
    }

    /// 根据图表类型和内容估算高度
    private func estimateDiagramHeight(code: String, width: CGFloat) -> CGFloat {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = code.components(separatedBy: .newlines)

        // 检测图表类型
        if trimmedCode.hasPrefix("graph") || trimmedCode.hasPrefix("flowchart") {
            // 流程图：统计节点数量
            let nodeCount = countFlowchartNodes(in: code)
            // 每个节点约 80px 高度，加上连接线间距
            return max(300, CGFloat(nodeCount) * 80 + 60)
        }

        if trimmedCode.hasPrefix("mindmap") {
            // 思维导图：横向展开，高度相对固定
            let maxDepth = countMindmapMaxDepth(in: code)
            // 每层约 40px，基础高度 180
            return max(280, CGFloat(maxDepth) * 40 + 180)
        }

        if trimmedCode.hasPrefix("sequenceDiagram") {
            // 时序图：根据参与者和消息数估算
            let messageCount = code.components(separatedBy: "->").count +
                               code.components(separatedBy: "->>").count
            return max(300, CGFloat(messageCount) * 40 + 100)
        }

        if trimmedCode.hasPrefix("classDiagram") {
            // 类图：根据类数量估算
            let classCount = code.components(separatedBy: "class ").count - 1
            return max(300, CGFloat(max(classCount, lines.count)) * 50 + 100)
        }

        if trimmedCode.hasPrefix("gantt") {
            // 甘特图：根据任务数估算
            let taskLines = lines.filter { $0.contains(":") }.count
            return max(250, CGFloat(taskLines) * 35 + 100)
        }

        // 默认：根据行数估算，最小 250，最大 600
        return min(600, max(250, CGFloat(lines.count) * 40 + 80))
    }

    /// 统计流程图节点数量
    private func countFlowchartNodes(in code: String) -> Int {
        // 统计连接符数量作为节点估算依据
        let arrows = ["-->", "---", "-.->", "==>", "--o", "--x"]
        var count = 0
        for arrow in arrows {
            count += code.components(separatedBy: arrow).count - 1
        }
        // 节点数约为连接数 + 1，但至少有起始和结束
        return max(3, count + 1)
    }

    /// 统计思维导图最大层级深度
    private func countMindmapMaxDepth(in code: String) -> Int {
        let lines = code.components(separatedBy: .newlines)
        var maxDepth = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed == "mindmap" { continue }

            // 计算缩进深度（每 2 个空格为一层）
            let leadingSpaces = line.prefix(while: { $0 == " " }).count
            let depth = leadingSpaces / 2
            maxDepth = max(maxDepth, depth)
        }

        return max(2, maxDepth)
    }
}

// MARK: - Mermaid WebView

/// Mermaid 渲染视图
final class MermaidWebView: UIView, WKNavigationDelegate {

    private let webView: WKWebView
    private let code: String
    private let preferredSize: CGSize

    init(code: String, frame: CGRect) {
        self.code = code
        self.preferredSize = frame.size

        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        self.webView = WKWebView(frame: .zero, configuration: config)

        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        setupUI()
        loadMermaid()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        return preferredSize
    }

    private func setupUI() {
        backgroundColor = .systemBackground
        layer.cornerRadius = 8
        clipsToBounds = true

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        addSubview(webView)

        // 高度约束
        heightAnchor.constraint(equalToConstant: preferredSize.height).isActive = true

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func loadMermaid() {
        let html = generateMermaidHTML(code: code)
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func generateMermaidHTML(code: String) -> String {
        // 转义代码中的特殊字符
        let escapedCode = code
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
            <style>
                body {
                    margin: 0;
                    padding: 8px;
                    display: flex;
                    justify-content: center;
                    align-items: flex-start;
                    box-sizing: border-box;
                    background-color: transparent;
                }
                .mermaid {
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                }
                /* 深色模式支持 */
                @media (prefers-color-scheme: dark) {
                    body { background-color: transparent; }
                }
            </style>
        </head>
        <body>
            <div class="mermaid">
            \(escapedCode)
            </div>
            <script>
                mermaid.initialize({
                    startOnLoad: true,
                    theme: window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'default',
                    securityLevel: 'loose'
                });
            </script>
        </body>
        </html>
        """
    }
}

// MARK: - Convenience Registration

public extension MarkdownCustomExtensionManager {

    /// 注册 Mermaid 渲染器
    func registerMermaidRenderer() {
        register(codeBlockRenderer: MermaidRenderer())
        print("✅ [Mermaid] Mermaid renderer registered")
    }
}
