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
final class MermaidWebView: UIView, WKNavigationDelegate, WKScriptMessageHandler {

    private var webView: WKWebView!
    private let code: String

    private var heightConstraint: NSLayoutConstraint?
    private var lastReportedHeight: CGFloat = 0
    private var maxHeightForToken: CGFloat = 0
    private var renderToken = UUID()

    init(code: String, frame: CGRect) {
        self.code = code
        super.init(frame: frame)

        let contentController = WKUserContentController()
        contentController.add(self, name: "mermaidHeight")

        let script = WKUserScript(
            source: Self.heightObserverScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        contentController.addUserScript(script)

        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        config.userContentController = contentController

        webView = WKWebView(frame: .zero, configuration: config)

        translatesAutoresizingMaskIntoConstraints = false
        setupUI(initialHeight: frame.size.height)
        loadMermaid()
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "mermaidHeight")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: heightConstraint?.constant ?? 0)
    }

    private func setupUI(initialHeight: CGFloat) {
        backgroundColor = .systemBackground
        layer.cornerRadius = 8
        clipsToBounds = true

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        addSubview(webView)

        let constraint = heightAnchor.constraint(equalToConstant: max(1, initialHeight))
        constraint.priority = .required
        constraint.isActive = true
        heightConstraint = constraint

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func loadMermaid() {
        renderToken = UUID()
        maxHeightForToken = 0
        let html = generateMermaidHTML(code: code)
        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let token = renderToken
        requestHeightPoll(token: token, attempt: 0)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "mermaidHeight" else { return }
        guard let height = message.body as? Double else { return }
        applyHeight(CGFloat(height))
    }

    private func requestHeightPoll(token: UUID, attempt: Int) {
        guard token == renderToken else { return }
        let script = "window.__mdv_getHeight ? window.__mdv_getHeight() : 0"
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self else { return }
            applyHeight(CGFloat((result as? Double) ?? 0))

            if attempt < 6 {
                let delay = 0.08 + Double(attempt) * 0.12
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.requestHeightPoll(token: token, attempt: attempt + 1)
                }
            }
        }
    }

    private func applyHeight(_ height: CGFloat) {
        let adjustedHeight = max(1, ceil(height) + 16)
        if adjustedHeight <= maxHeightForToken + 1 {
            return
        }
        maxHeightForToken = adjustedHeight

        guard abs(adjustedHeight - lastReportedHeight) > 1 else { return }
        lastReportedHeight = adjustedHeight
        heightConstraint?.constant = adjustedHeight
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        layoutIfNeeded()
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
                html, body {
                    margin: 0;
                    padding: 0;
                    background-color: transparent;
                    overflow: hidden;
                }
                body {
                    padding: 8px;
                    box-sizing: border-box;
                    text-align: center;
                }
                .mermaid {
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    display: inline-block;
                }
                svg {
                    display: block;
                }
                @media (prefers-color-scheme: dark) {
                    body { background-color: transparent; }
                }
            </style>
        </head>
        <body>
            <div class="mermaid">\(escapedCode)</div>
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

    private static let heightObserverScript = """
    (function() {
      function calcHeight() {
        try {
          var svg = document.querySelector('svg');
          if (svg) {
            var r = svg.getBoundingClientRect();
            if (r && r.height) {
              return r.bottom;
            }
          }

          var docEl = document.documentElement;
          var body = document.body;
          var h1 = Math.max(docEl ? docEl.scrollHeight : 0, body ? body.scrollHeight : 0);
          var h2 = Math.max(docEl ? docEl.offsetHeight : 0, body ? body.offsetHeight : 0);
          return Math.max(h1, h2);
        } catch (e) {
          return 0;
        }
      }

      window.__mdv_getHeight = function() { return calcHeight(); };

      function post() {
        var h = calcHeight();
        if (h && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mermaidHeight) {
          window.webkit.messageHandlers.mermaidHeight.postMessage(h);
        }
      }

      window.addEventListener('load', function() {
        setTimeout(post, 120);
        setTimeout(post, 260);
        setTimeout(post, 520);
      });

      try {
        var obs = new MutationObserver(function() { post(); });
        obs.observe(document.body, { childList: true, subtree: true, attributes: true });
      } catch (e) {}

      try {
        var ro = new ResizeObserver(function() { post(); });
        ro.observe(document.body);
      } catch (e) {}
    })();
    """
}


// MARK: - Convenience Registration

public extension MarkdownCustomExtensionManager {

    /// 注册 Mermaid 渲染器
    func registerMermaidRenderer() {
        register(codeBlockRenderer: MermaidRenderer())
        print("✅ [Mermaid] Mermaid renderer registered")
    }
}
