*[English](README.md) | 中文*

# MarkdownDisplayView

一个基于 TextKit 2 的 iOS UIKit Markdown 高性能渲染组件，支持样式配置、后台解析、增量 UI 更新和实时 AI/SSE 流式输出。

- 示例长文档16kb（包含大部分样式），全文加载滑动内存iPhone 14Pro上仅60~70MB

- 示例长文档16kb字符随机长度按顺序裁切模拟流式，峰值内存140多MB，停止流式后内存降回70MB左右，且可继续追加流式输出。

- 历史文档优化只存前后两屏layer，滚动时会降低内存，50MB左右

- 真实AI模型调用对话4轮次后还保持40MB左右，滚动时会降低内存，跟模型流式时内存会略微上升，流式完毕后变成静态页面，内存降低.

> 🚀 **面向 AI 对话与文档页面：既可渲染完整 Markdown，也可持续追加 AI/SSE 增量，并支持样式、打字机效果与震动反馈配置。**

## 目录

| 概览 | 使用 | 项目 |
|------|------|------|
| [Demo 效果](#demo-效果) | [快速开始](#快速开始) | [完整示例](#完整示例) |
| [特性](#特性) | [自定义配置](#自定义配置) | [性能优化](#性能优化) |
| [系统要求](#系统要求) | [目录功能](#目录功能) | [故障排除](#故障排除) |
| [安装](#安装) | [支持的 Markdown 语法](#支持的-markdown-语法) | [更新日志](#更新日志) |
| | [高级用法](#高级用法) | [贡献](#贡献) · [许可证](#许可证) |
| | [自定义扩展](#自定义扩展) | [作者](#作者) · [致谢](#致谢) · [联系方式](#联系方式) |

## Demo 效果

### 正常渲染（整页秒开）

![Normal Rendering](./Effects/normal.gif)

### 流式渲染

- 真实 AI/SSE 分片流式

![Streaming Rendering](./Effects/streaming.gif)

- 与AI大模型对话

需要运行真实 AI 对话 Demo 时，请在示例 target 中创建不纳入版本控制的 `Config.local.json`。

<details>
<summary>展开查看 Config.local.json 结构</summary>

```json
{
  "host": "https://api.deepseek.com",
  "path": "/chat/completions",
  "apiKey": "replace-with-your-api-key",
  "model": "deepseek-chat",
  "systemPrompt": "You are a helpful assistant.",
  "temperature": 0.7,
  "stream": true,
  "timeoutSeconds": 30
}
```

</details>

![AIChat](./Effects/ChatWithAIModel.gif)

## 特性

| 能力 | 说明 |
|------|------|
| 渲染 | TextKit 2、后台解析、首屏优先与增量 UI 更新 |
| AI/SSE 流式 | 安全模块缓冲、顺序增量、打字机输出、高度缓存和可选震动 |
| Markdown | 标题、列表、表格、引用、图片、LaTeX、脚注、折叠块和可横向滚动代码块 |
| 代码高亮 | 内置 20+ 种常用语言高亮 |
| 导航 | 自动目录、标题跳转与文档内锚点 |
| 样式 | 字体、颜色、间距、明暗预设与块级外观 |
| 扩展 | 自定义解析器、视图提供者、事件处理器和代码块渲染器 |
| 回调 | 链接、图片、目录、高度和流式步骤事件 |

## 系统要求

| 项目 | 要求 |
|------|------|
| 最低系统 | iOS 15.0+ |
| Swift 工具链 | Swift 5.9+ |
| Xcode | 库使用 Xcode 15.0+；仓库内示例工程采用 Xcode 26 项目格式 |

## 安装

| 包管理器 | 依赖名称 | 导入模块 |
|----------|----------|----------|
| Swift Package Manager | `MarkdownDisplayView` | `import MarkdownDisplayView` |
| CocoaPods | `MarkdownDisplayKit` | `import MarkdownDisplayKit` |

<details>
<summary>展开查看安装步骤与命令</summary>

### Swift Package Manager

#### 方式一:Xcode 添加

1. 在 Xcode 中打开你的项目
2. 选择 `File` → `Add Package Dependencies...`
3. 输入仓库 URL:`https://github.com/zjc19891106/MarkdownDisplayView.git`
4. 选择版本并点击 `Add Package`

#### 方式二:Package.swift

在 `Package.swift` 中添加依赖:

```swift
dependencies: [
    .package(url: "https://github.com/zjc19891106/MarkdownDisplayView.git", from: "2.1.1")
]
```

Swift Package Manager 会自动解析 `swift-markdown` 和 `Kingfisher`。

然后在 target 中添加:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "MarkdownDisplayView", package: "MarkdownDisplayView")
    ]
)
```

### CocoaPods

在你的 `Podfile` 中添加以下内容:

```ruby

pod 'MarkdownDisplayKit', '~> 2.1.1'
```

然后运行:

```bash
pod install
```

**说明**：`MarkdownDisplayKit.podspec` 已声明 `AppleSwiftMDWrapper` 作为 Markdown 解析依赖，并声明 `Kingfisher (~> 8.9.0)` 作为图片加载依赖，执行 `pod install` 时会自动解析。

</details>

## 快速开始

### 基础用法

Swift Package Manager 使用 `import MarkdownDisplayView`；CocoaPods 的相同 API 通过 `import MarkdownDisplayKit` 暴露。

```swift
import UIKit
import MarkdownDisplayView

let markdownView = ScrollableMarkdownViewTextKit()
markdownView.configuration = .default
markdownView.markdown = "# 你好\n\n使用 TextKit 2 渲染 **Markdown**。"
```

将 `markdownView` 加入视图层级并像普通 `UIScrollView` 一样设置约束即可。完整可运行布局请参考 [`MarkdownExampleViewController.swift`](Example/ExampleForMarkdown/ExampleForMarkdown/MarkdownExampleViewController.swift)。

<details>
<summary>展开查看链接与图片回调示例</summary>

### 设置链接点击回调

```swift
markdownView.onLinkTap = { url in
    if UIApplication.shared.canOpenURL(url) {
        UIApplication.shared.open(url)
    }
}
```

### 设置图片点击回调

```swift
markdownView.onImageTap = { imageURL in
    print("图片被点击：\(imageURL)")
    // 可以在此处实现图片预览功能
}
```

</details>

## 自定义配置

### 使用预设主题

<details>
<summary>展开查看预设主题代码</summary>

```swift
// 使用默认浅色主题
markdownView.configuration = .default

// 使用深色主题
markdownView.configuration = .dark
```

</details>

### 自定义配置

<details>
<summary>展开查看完整配置示例</summary>

```swift
var config = MarkdownConfiguration.default

// 自定义字体
config.bodyFont = .systemFont(ofSize: 17)
config.h1Font = .systemFont(ofSize: 32, weight: .bold)
config.codeFont = .monospacedSystemFont(ofSize: 15, weight: .regular)

// 自定义颜色
config.textColor = .label
config.linkColor = .systemBlue
config.linkUnderlineEnabled = false    // 关闭链接下划线
config.codeBackgroundColor = .systemGray6
config.blockquoteTextColor = .secondaryLabel

// 自定义间距
config.paragraphSpacing = 16
config.headingTopSpacing = 20
config.headingBottomSpacing = 12
config.imageMaxHeight = 500
config.lineSpacing = MarkdownLineSpacingConfiguration(
    body: 6,
    heading: 8,
    quote: 6,
    codeBlock: 4
)

// 应用配置
markdownView.configuration = config
```

</details>

### 配置参考

以下列出常用公开配置；当前版本的完整定义请以 [`MarkdownConfiguration`](MarkdownDisplayView/Sources/MarkdownDisplayView/MarkdownRenderElement.swift) 源码为准。

<details>
<summary>展开查看配置属性</summary>

#### 字体配置

```swift
public var bodyFont: UIFont              // 正文字体
public var h1Font: UIFont                // H1 标题字体
public var h2Font: UIFont                // H2 标题字体
public var h3Font: UIFont                // H3 标题字体
public var h4Font: UIFont                // H4 标题字体
public var h5Font: UIFont                // H5 标题字体
public var h6Font: UIFont                // H6 标题字体
public var codeFont: UIFont              // 代码字体
public var blockquoteFont: UIFont        // 引用字体
```

#### 颜色配置

```swift
public var textColor: UIColor                          // 文本颜色
public var headingColor: UIColor                       // 标题颜色
public var linkColor: UIColor                          // 链接颜色
public var linkUnderlineEnabled: Bool                  // 链接是否显示下划线（默认 true）
public var codeTextColor: UIColor                      // 代码文本颜色
public var codeBackgroundColor: UIColor                // 代码背景色
public var blockquoteTextColor: UIColor                // 引用文本颜色
public var blockquoteBarColor: UIColor                 // 引用边框颜色
public var tableBorderColor: UIColor                   // 表格边框颜色
public var tableHeaderBackgroundColor: UIColor         // 表头背景色
public var tableRowBackgroundColor: UIColor            // 表格行背景色
public var tableAlternateRowBackgroundColor: UIColor   // 表格交替行背景色
public var horizontalRuleColor: UIColor                // 分隔线颜色
public var imagePlaceholderColor: UIColor              // 图片占位符颜色
public var footnoteColor: UIColor                      // 脚注颜色
public var tocTextColor: UIColor                       // 目录文字颜色
public var detailsSummaryTextColor: UIColor            // 折叠块标题文字颜色
```

#### 间距配置

```swift
public var paragraphSpacing: CGFloat       // 段落间距
public var headingTopSpacing: CGFloat      // 标题前间距
public var headingBottomSpacing: CGFloat   // 标题后间距
public var paragraphTopSpacing: CGFloat    // 段落前间距
public var paragraphBottomSpacing: CGFloat // 段落后间距
public var listIndent: CGFloat             // 列表缩进
public var blockquoteIndent: CGFloat       // 引用缩进
public var imageMaxHeight: CGFloat         // 图片最大高度
public var imagePlaceholderHeight: CGFloat // 图片占位符高度
```

#### 行间距配置

```swift
public var lineSpacing: MarkdownLineSpacingConfiguration // 分角色行间距配置

public struct MarkdownLineSpacingConfiguration {
    public var body: CGFloat
    public var heading: CGFloat
    public var quote: CGFloat
    public var codeBlock: CGFloat
}
```

#### LaTeX 公式配置

```swift
public var latexFontSize: CGFloat          // LaTeX 公式字号（默认: 22）
public var latexAlignment: NSTextAlignment // LaTeX 公式对齐方式（.left, .center, .right）
public var latexTextColor: UIColor         // 公式字形与线条的默认颜色
public var latexBackgroundColor: UIColor   // LaTeX 公式背景颜色
public var latexPadding: CGFloat           // LaTeX 公式内边距（默认: 20）
```

#### LaTeX 公式语法

支持两种公式形式：

- **行内公式** — 用单个美元符号 `$...$` 包裹，随正文在段落、标题、表格单元格、引用块和列表项中内联显示：

  ```markdown
  能量为 $E=mc^2$，动量为 $p=mv$。
  ```

- **行间公式** — 用双美元符号 `$$...$$` 包裹，以全宽居中的块级形式显示：

  ```markdown
  $$
  \int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
  $$
  ```

- **围栏公式** — `math` 围栏渲染为行间公式；`latex` 围栏保持源码，避免文档示例被误当公式。

> 反引号（行内代码）内的 `$...$` 保持字面量，不会被当作公式。

#### 引用块配置

```swift
public var blockquoteBackgroundColor: UIColor  // 引用块背景颜色
public var blockquoteBarWidth: CGFloat         // 引用块左侧竖线宽度（默认: 4）
public var blockquoteContentSpacing: CGFloat   // 引用块内容间距（默认: 8）
public var blockquoteContentPadding: CGFloat   // 引用块内容内边距（默认: 12）
```

#### 表格配置

```swift
public var tableMinColumnWidth: CGFloat    // 表格最小列宽（默认: 80）
public var tableMaxColumnWidth: CGFloat    // 表格最大列宽（默认: 200）
public var tableRowHeight: CGFloat         // 表格行高（默认: 44）
public var tableCellPadding: CGFloat       // 表格单元格内边距（默认: 16）
public var tableSeparatorHeight: CGFloat   // 表格分隔线高度（默认: 1）
public var autoFixMalformedTables: Bool    // 自动修正常见异常表格文本（默认: true）
```

#### 列表配置

```swift
public var listItemSpacing: CGFloat        // 列表项间距（默认: 4）
public var listMarkerMinWidth: CGFloat     // 列表标记最小宽度（默认: 20）
public var listMarkerSpacing: CGFloat      // 列表标记与内容间距（默认: 4）
public var listTopPadding: CGFloat         // 整个列表顶部内边距（默认: 0）
public var listBottomPadding: CGFloat      // 整个列表底部内边距（默认: 0）
```

#### 折叠块（Details）配置

```swift
public var detailsSummaryFont: UIFont          // 折叠块标题字体
public var detailsSummaryTextColor: UIColor    // 折叠块标题文字颜色
public var detailsSummaryMinHeight: CGFloat    // 折叠块标题最小高度（默认: 40）
public var detailsContentPadding: CGFloat      // 折叠块内容内边距（默认: 12）
public var detailsSpacing: CGFloat             // 折叠块内部间距（默认: 8）
```

#### 代码高亮配置

```swift
public var syntaxColors: SyntaxHighlightColors // 当前使用的高亮颜色；`.dark` 会设置为 `.xcodeDark`

// SyntaxHighlightColors 结构体
public struct SyntaxHighlightColors {
    public var keyword: UIColor       // 关键字颜色
    public var string: UIColor        // 字符串颜色
    public var number: UIColor        // 数字颜色
    public var comment: UIColor       // 注释颜色
    public var type: UIColor          // 类型颜色
    public var function: UIColor      // 函数颜色
    public var property: UIColor      // 属性颜色
    public var preprocessor: UIColor  // 预处理器颜色

    public static var xcode: SyntaxHighlightColors      // Xcode 浅色主题
    public static var xcodeDark: SyntaxHighlightColors  // Xcode 深色主题
}
```

#### 流式输出震动反馈配置

```swift
public var streamingHapticFeedbackStyle: StreamingHapticFeedbackStyle  // 震动反馈级别（默认: .none）
public var streamingHapticMinInterval: TimeInterval                    // 震动最小间隔时间（默认: 0.05 秒）

// StreamingHapticFeedbackStyle 枚举
public enum StreamingHapticFeedbackStyle {
    case none    // 不震动（默认）
    case light   // 轻微震动
    case medium  // 中等震动
    case heavy   // 强烈震动
    case soft    // 柔和震动 (iOS 13+)
    case rigid   // 刚性震动 (iOS 13+)
}

// 使用示例
var config = MarkdownConfiguration.default
config.streamingHapticFeedbackStyle = .light  // 启用轻微震动
config.streamingHapticMinInterval = 0.05      // 50ms 最小间隔
markdownView.configuration = config
```

</details>

## 目录功能

<details>
<summary>展开查看目录 API 用法</summary>

### 获取自动生成的目录

Markdown 解析是异步的。请在渲染产生高度回调后，或后续用户操作中读取/展示目录，不要在设置 `markdown` 后立即读取。

```swift
// Markdown 内容会自动解析标题生成目录
let tocItems = markdownView.tableOfContents

for item in tocItems {
    print("Level \(item.level): \(item.title)")
}
```

### 生成目录视图

```swift
// 自动生成可点击的目录视图
let tocView = markdownView.generateTOCView()
view.addSubview(tocView)
NSLayoutConstraint.activate([
    tocView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
    tocView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
    tocView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
])
```

### 监听或主动触发目录导航

```swift
// 内置目录项会在此回调返回后自动滚动。
markdownView.onTOCItemTap = { item in
    print("选中目录项：\(item.title)")
}

// 从自定义 UI 主动跳转。
if let item = markdownView.tableOfContents.first {
    markdownView.scrollToTOCItem(item)
}
```

</details>

## 支持的 Markdown 语法

| 分类 | 支持形式 |
|------|----------|
| 标题 | 使用 `#` 到 `######` 的 H1–H6 |
| 文本 | 粗体、斜体、粗斜体、删除线和行内代码 |
| 列表 | 有序、无序、嵌套和任务列表 |
| 链接与图片 | 行内链接、远程图片、文档内锚点和点击回调 |
| 引用 | 多行与嵌套引用，可包含富块级内容 |
| 代码 | 行内与围栏代码块，20+ 种语言高亮及横向滚动 |
| 表格 | GFM 管道表格、列对齐和流式异常表格修复 |
| 数学公式 | 行内 `$…$`、块级 `$$…$$` 及 `math` / `latex` 围栏 |
| 文档辅助 | 分隔线、脚注和 HTML 风格 `details` / `summary` 折叠区 |

完整渲染语法目录请查看 [`MarkdownExampleViewController.swift`](Example/ExampleForMarkdown/ExampleForMarkdown/MarkdownExampleViewController.swift)。

## 完整示例

| 工程 | 集成方式 | 覆盖内容 |
|------|----------|----------|
| [`ExampleForMarkdown`](Example/ExampleForMarkdown/) | Swift Package Manager | 语法目录、主题、回调、AI 对话/流式、历史缓存，以及 Video、Mermaid、ECharts |
| [`CocoapodsMDExample`](CocoapodsMDExample/) | CocoaPods | 通过 `MarkdownDisplayKit` 展示等价 UIKit 用法与自定义扩展 |

使用 `open Example/ExampleForMarkdown/ExampleForMarkdown.xcodeproj` 打开 SPM 示例工程。

## 性能优化

| 策略 | 行为 |
|------|------|
| 后台解析 | 解析与准备工作进入专用渲染队列，UIKit 更新回到主线程 |
| 增量更新 | Diff/追加路径只更新受影响内容，并优先处理首屏 |
| 图片管线 | Kingfisher 异步加载并复用内存/磁盘缓存 |
| 工作缓存 | 复用语法正则、预渲染内容和同宽度高度测量 |
| 流式预算 | 顺序解析、UI 工作与打字机播放使用有界队列和背压 |

## 高级用法

<details>
<summary>展开查看核心视图、预渲染、Cell 与流式指南</summary>

### 直接使用核心视图（无滚动）

```swift
let markdownView = MarkdownViewTextKit()
// 需要自己管理滚动容器
```

### 在聊天或历史 Cell 中复用预渲染结果

持久化时仍以原始 Markdown 作为数据源。对于已经结束流式输出的稳定消息，可以在后台队列生成渲染结果，并按照消息标识、Markdown 内容、容器宽度和样式版本缓存在内存中：

```swift
let source = message.markdown
let width = markdownWidth
let renderConfiguration = configuration

DispatchQueue.global(qos: .userInitiated).async {
    let renderer = MarkdownRenderer(
        configuration: renderConfiguration,
        containerWidth: width
    )
    let prepared = renderer.prepare(source)

    DispatchQueue.main.async {
        markdownView.setPreparedContent(prepared)
    }
}
```

`setPreparedContent(_:)` 会跳过 Markdown 解析、渲染元素生成和第一次高度预估。Markdown 内容、宽度或配置变化后需要重新生成。`MarkdownPreparedContent` 适合作为内存渲染缓存；持久化聊天历史时仍应保存原始 Markdown，不建议把它直接归档为长期存储格式。

当历史中有几十甚至上百篇长文档时，不要在进入页面时一次性预渲染全部内容。应通过 `UITableViewDataSourcePrefetching` 只准备可见区域附近的行，在快速滚动或宽度变化后取消过期任务，并同时设置 `NSCache.countLimit` 和 `totalCostLimit`，让富文本渲染结果可以在内存压力下被淘汰。

示例控制器会让短 Markdown 继续走普通渲染；长文缓存未命中时显示轻量加载指示，并且只提交一次预渲染，避免同一份内容同时进行普通解析和缓存预解析。

可见区域预取、有界渲染缓存和 Table 行高缓存可参考 [`AIChatViewController.swift`](Example/ExampleForMarkdown/ExampleForMarkdown/AIChatViewController.swift) 与 [`HistoryMDViewController.swift`](Example/ExampleForMarkdown/ExampleForMarkdown/HistoryMDViewController.swift)。

### 监听高度变化

```swift
let markdownView = MarkdownViewTextKit()

markdownView.onHeightChange = { newHeight in
    print("内容高度变化为: \(newHeight)")
}
```

### 使用带滚动的视图（推荐）

`ScrollableMarkdownViewTextKit` 就是快速开始与示例工程使用的封装。它内部持有 `MarkdownViewTextKit`，提供滚动能力，并转发 `markdown`、`configuration`、链接/图片/目录回调及目录导航 API。完整可运行设置请参考 [`MarkdownExampleViewController.swift`](Example/ExampleForMarkdown/ExampleForMarkdown/MarkdownExampleViewController.swift#L14)。

### 实时流式 Markdown（LLM/SSE）

当 AI 模型或 SSE 连接持续返回字符串分片时，请在主线程调用三个真实流式 API：响应开始前开启一次流式模式，按到达顺序追加每个解码后的 content delta，并在服务端发送完成事件或连接正常结束后收尾。请直接传递真实分片，不要先拼成完整 Markdown 再回放。

```swift
@MainActor
func streamDidStart(_ view: MarkdownViewTextKit) {
    view.beginRealStreaming()
}

@MainActor
func streamDidReceive(_ delta: String, in view: MarkdownViewTextKit) {
    view.appendStreamData(delta)
}

@MainActor
func streamDidFinish(_ view: MarkdownViewTextKit) {
    view.endRealStreaming()
}
```

两个 `StreamingMarkdownController` 示例会定时发送本地分片，仅用于代替网络回调。生产环境应在 `URLSession`/SSE 客户端收到 delta 时直接调用同一组 API。

用于 Table/Collection Cell 的 AI 对话流式推荐配置：

```swift
var config = MarkdownConfiguration.default
config.typewriterTextMode = .append
config.typewriterHeightUpdateInterval = 20
config.streamMinModuleLength = 10
config.streamingHapticFeedbackStyle = .medium
config.latexAlignment = .left
scrollableMarkdownView.markdownView.configuration = config
```

**核心特性**：
- **智能缓冲**：自动缓冲未完成的 Markdown 结构（未闭合的代码块、表格、LaTeX 公式）
- **纯文本识别**：内部流式缓冲器会识别不含 Markdown 标记的内容
- **纯文本更快输出**：对于没有 Markdown 标记的纯文本，模块允许在 `\n` 边界提交，不再必须等待 `\n\n`
- **安全 Markdown 边界**：优先提交完整标题模块，标题不足时回退到段落边界；代码围栏等未闭合结构会继续留在缓冲区
- **增量渲染**：完整模块立即渲染，未完成内容继续缓冲等待
- **打字机效果**：渲染内容平滑的逐字显示动画

</details>

## 自定义扩展

核心库支持自定义扩展，可接入业务自己的 Markdown 语法与渲染方式。

### 示例位置与能力

自定义扩展实现位于示例工程中，不会随 `MarkdownDisplayView` 库 target 自动注册。两个 Demo 包含相同的实现：

- Swift Package 示例：[`Example/ExampleForMarkdown/ExampleForMarkdown`](Example/ExampleForMarkdown/ExampleForMarkdown/)
- CocoaPods 示例：[`CocoapodsMDExample/CocoapodsMDExample`](CocoapodsMDExample/CocoapodsMDExample/)
- 注册入口：[`AppDelegate.swift`](Example/ExampleForMarkdown/ExampleForMarkdown/AppDelegate.swift)
- 完整 Markdown 用法：[`MarkdownExampleViewController.swift`](Example/ExampleForMarkdown/ExampleForMarkdown/MarkdownExampleViewController.swift) 中的“十二、自定义样式测试”

| 示例 | 扩展方式 | 语法 | 当前能力 |
|------|----------|------|----------|
| 视频 | `MarkdownCustomParser` + `MarkdownCustomViewProvider` + `MarkdownCustomActionHandler` | `[video:文件名]` | 缩略图、时长、QuickLook 播放，支持 `.mov`、`.mp4`、`.m4v` |
| Mermaid | `MarkdownCodeBlockRenderer` | `` ```mermaid `` | 流程图、时序图、类图、状态图、甘特图、思维导图 |
| ECharts | `MarkdownCustomParser` + `MarkdownCustomViewProvider` | `<echarts height="320">JSON</echarts>` | 柱状图、饼图、折线图、散点图、堆叠面积图、K 线图、直方图、关系图、热力图 |

对应源码：

- [`MarkdownVideoExtension.swift`](Example/ExampleForMarkdown/ExampleForMarkdown/MarkdownVideoExtension.swift)
- [`MermaidRenderer.swift`](Example/ExampleForMarkdown/ExampleForMarkdown/MermaidRenderer.swift)
- [`MarkdownEChartsExtension.swift`](Example/ExampleForMarkdown/ExampleForMarkdown/MarkdownEChartsExtension.swift)

<details>
<summary>展开查看扩展注册与语法示例</summary>

### 视频自定义扩展示例

在 `AppDelegate` 中注册视频扩展：

> `registerVideoExtension()` 由 Demo 的 [`MarkdownVideoExtension.swift`](Example/ExampleForMarkdown/ExampleForMarkdown/MarkdownVideoExtension.swift) 定义；业务工程调用前需要复制并加入该实现。

下面使用 Swift Package Manager 的模块名；CocoaPods 工程应改为 `import MarkdownDisplayKit`。

```swift
import MarkdownDisplayView

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    // 注册视频扩展
    MarkdownCustomExtensionManager.shared.registerVideoExtension()
    return true
}
```

**语法**: `[video:文件名]`

```markdown
## 视频演示

[video:video]

支持格式: .mov, .mp4, .m4v
```

引用的视频文件必须存在于 App Bundle。仓库示例包含 `video.mov`，因此 `[video:video]` 可直接运行。

**功能特性**:
- 自动生成视频缩略图
- 显示视频时长
- 点击使用 QuickLook 播放

### 代码块渲染器

除了行内语法扩展，还支持自定义代码块渲染器，用于渲染特定语言的代码块：

#### Mermaid 图表渲染器示例

完整可运行的 `WKWebView` 实现位于 [`MermaidRenderer.swift`](Example/ExampleForMarkdown/ExampleForMarkdown/MermaidRenderer.swift)。它实现 `MarkdownCodeBlockRenderer`，负责估算图表尺寸、加载 Mermaid.js，并把实际高度变化回传给 Markdown 视图。

#### 注册代码块渲染器

```swift
let manager = MarkdownCustomExtensionManager.shared
manager.register(codeBlockRenderer: MermaidRenderer())
```

同一 Demo 源文件还提供了便捷方法 `registerMermaidRenderer()`；该方法不属于 SDK target。

**支持的图表类型**（通过 Mermaid.js）：
- 流程图 (flowchart/graph)
- 时序图 (sequenceDiagram)
- 类图 (classDiagram)
- 状态图 (stateDiagram)
- 甘特图 (gantt)
- 思维导图 (mindmap)

### ECharts 自定义标签示例

ECharts 示例使用 HTML 风格标签，但底层仍由 `MarkdownCustomParser` 识别，并通过 `MarkdownCustomViewProvider` 返回 `WKWebView`，不会开启通用 HTML 或任意 `<script>` 渲染。

在 `AppDelegate` 中注册：

> `registerEChartsExtension()` 由 Demo 的 [`MarkdownEChartsExtension.swift`](Example/ExampleForMarkdown/ExampleForMarkdown/MarkdownEChartsExtension.swift) 定义；业务工程调用前需要复制并加入该实现。

```swift
MarkdownCustomExtensionManager.shared.registerEChartsExtension()
```

传入纯 JSON 格式的 ECharts `option`：

```markdown
<echarts height="320">
{
  "xAxis": { "type": "category", "data": ["周一", "周二", "周三"] },
  "yAxis": { "type": "value" },
  "series": [{ "type": "bar", "data": [120, 200, 150] }]
}
</echarts>
```

`height` 可选，默认 320pt，示例会将高度限制在 220～640pt。配置必须是 JSON 对象，不支持 JavaScript 函数；非法 JSON、脚本加载失败或渲染失败时会显示错误提示。当前 Demo 展示：

- 柱状图、饼图、折线图、散点图
- 堆叠面积图、K 线图、直方图
- 关系图、热力图

ECharts 和 Mermaid 示例通过 CDN 加载脚本，首次展示需要网络。如产品要求完全离线，可将固定版本的 JavaScript 文件加入 App Bundle，并在对应 Demo Renderer 中改为加载本地资源。

</details>

## 故障排除

| 现象 | 处理方式 |
|------|----------|
| macOS `swift build` 提示找不到 UIKit | 该包仅支持 iOS，请在 Xcode 中选择 iOS 模拟器或设备目标构建 |
| Markdown 图片无法显示 | 确认 URL 可访问并优先使用 HTTPS；必须使用 HTTP 时，仅添加所需域名的 ATS 例外 |

## Demo 主题与块级外观（1.9.9）

`ExampleForMarkdown` 的 **Theme Gallery** 提供四套仅属于 Demo 的主题：

| 主题 | 风格 | 界面模式 |
|------|------|----------|
| 暖纸张 | Editorial | 浅色 |
| 鼠尾草 | Calm | 浅色 |
| 深海代码 | Code | 深色 |
| 暮紫夜色 | Art | 深色 |

选择主题后，Demo 会通过 `UserDefaults` 保存选择，并把同一份配置应用到 Markdown 预览、AI Chat/历史、长历史列表、TableView Streaming 和智能流式示例中。

在示例 App 首页进入 **Theme Gallery**，选择一张主题卡片，再进入上述任一页面即可查看效果。主题持久化由 Demo 内部的 `MarkdownDemoThemeStore` 实现，它不是 SDK 的全局主题单例。页面会在创建时读取当前主题，因此如果切换主题时目标页面已经打开，需要重新进入该页面刷新配置。

四套主题的完整定义位于 [`MarkdownThemeGalleryViewController.swift`](Example/ExampleForMarkdown/ExampleForMarkdown/MarkdownThemeGalleryViewController.swift)。业务 App 可以沿用相同思路：在自己的状态或 `UserDefaults` 中保存主题选择，生成一份完整的 `MarkdownConfiguration`，再赋给所有需要保持一致的 Markdown 视图。

### 创建主题配置

颜色和块级容器外观可以分别配置。`MarkdownBlockAppearance` 仅通过 `CALayer` 绘制圆角和边框，不会修改约束、内边距、测量高度或滚动范围。

<details>
<summary>展开查看完整主题配置</summary>

```swift
var configuration = MarkdownConfiguration.default

// 文字与块面颜色
configuration.textColor = .label
configuration.headingColor = .label
configuration.linkColor = .systemIndigo
configuration.codeTextColor = .label
configuration.codeBackgroundColor = .secondarySystemBackground
configuration.blockquoteTextColor = .label
configuration.blockquoteBarColor = .systemIndigo
configuration.blockquoteBackgroundColor = .secondarySystemBackground
configuration.tableBorderColor = .separator
configuration.tableHeaderBackgroundColor = .systemIndigo.withAlphaComponent(0.12)
configuration.tableRowBackgroundColor = .systemBackground
configuration.tableAlternateRowBackgroundColor = .secondarySystemBackground

// 公式字形/线条颜色与公式背景
configuration.latexTextColor = .label
configuration.latexBackgroundColor = .secondarySystemBackground

// 仅影响视觉的块级外观
configuration.codeBlockAppearance = MarkdownBlockAppearance(
    cornerRadius: 14,
    borderWidth: 1,
    borderColor: .separator
)
configuration.blockquoteAppearance = MarkdownBlockAppearance(
    cornerRadius: 12,
    borderWidth: 1,
    borderColor: .separator
)
configuration.tableAppearance = MarkdownBlockAppearance(
    cornerRadius: 12,
    borderWidth: 1,
    borderColor: .separator
)
configuration.imageAppearance = MarkdownBlockAppearance(
    cornerRadius: 14 // 图片边框按需开启
)
configuration.latexAppearance = MarkdownBlockAppearance(
    cornerRadius: 12,
    borderWidth: 1,
    borderColor: .separator
)
configuration.detailsAppearance = MarkdownBlockAppearance(
    cornerRadius: 12,
    borderWidth: 1,
    borderColor: .separator
)

markdownView.configuration = configuration
```

</details>

`latexTextColor` 控制公式字形、分数线和根号等绘制线条的默认颜色；公式内显式声明的 LaTeX `\color{...}` 仍然优先。图片主题默认只保留圆角、不显示边框；只有业务确实需要图片描边时，再设置 `borderWidth` 与 `borderColor`。

### 保持预渲染配置一致

<details>
<summary>展开查看预渲染主题同步方式</summary>

页面使用 `MarkdownRenderer.prepare(_:)` 时，需要给 Renderer 和最终展示视图传入同一份配置，避免缓存或预渲染内容残留另一套主题的颜色。

```swift
let renderer = MarkdownRenderer(
    configuration: configuration,
    containerWidth: contentWidth
)
let preparedContent = renderer.prepare(markdown)

markdownView.configuration = configuration
markdownView.setPreparedContent(preparedContent)
```

</details>

## 更新日志

### 2.1.8 (2026-08-20)

- 🪟 **静态文档视口虚拟化** - 长静态文档不再提前创建所有根文本视图，改为轻量几何槽 + 有界 TextKit 宿主复用 + 视口生命周期钩子：只保留可见视图的 backing store，滚动时释放离屏视图，内存不应再随滚动累积（真机滚动后的内存平台期尚未验证）。流式与可复用 Cell 渲染保持原有路径。
- 🧱 **复杂块的背衬存储预算有界化** - 视口虚拟化扩展到 LaTeX 公式、表格、默认代码块与安全的列表/引用组合：释放离屏复杂视图的 CALayer backing store，同时保留测量几何与横向交互状态。自定义渲染器、details 块与含动态尺寸图片的列表保持视图身份（状态暂无法通用重建）。
- 📉 **去除冗余全文拷贝** - 真流式不再保留一份重复的全文字符串，以流式缓存为全文唯一来源，并在流结束后释放。
- 🧹 **deinit 清理补全** - 视图析构时停掉自己的 RunLoop 定时器（打字机引擎的 display link 随其一起释放）、取消待执行 work item、清空流式待处理队列、取消在途订阅，关闭页面后不再有空转定时器或残留未播内容。
- 🧱 **可选释放 diff 基线** - `retainsDiffBaseline` 让静态一次性渲染（如 `setPreparedContent`）不再保留全量元素列表，避免重复持有富文本；静态示例页已启用。
- ⚡ **块级 LaTeX 渲染提速** - 块级公式直接用解析结果创建视图，去掉每个公式冗余的 TextKit 2 布局管线。
- 🐛 **修复 AI Chat URLSession 保留环** - 聊天流会话在结束与析构时 invalidate 其 `URLSession`，每次聊完不再泄漏一对会话对象。

### 2.1.2 (2026-08-19)

- ➗ **行内 LaTeX 全面支持** - 行内 `$...$` 现在会在段落、标题、表格单元格、引用块和列表项中作为行内附件渲染；块级 `$$...$$` 保持块级显示。超宽行内公式会缩放到行宽，不再被裁切。
- 🛡 **行内代码不再被误判为公式** - 反引号内的 `$...$` 保持字面量，`latex` 围栏保持源码（只有 `math` 渲染为公式），文档示例不再被误读为公式。新增 `\dfrac` / `\tfrac` 分数别名。
- 📐 **CommonMark 围栏代码块识别** - 智能流式缓存现在遵循 CommonMark 围栏规则：≤3 个前导空格、≥3 个反引号或波浪线、闭围栏需匹配字符与长度（含波浪线围栏）。
- 📊 **表格与代码布局配置生效** - `tableMinColumnWidth`、`tableMaxColumnWidth`、`tableRowHeight`、`tableCellPadding`、`tableSeparatorHeight`、`codeBlockPadding` 现在真正生效（此前为硬编码），并新增 `tableCellVerticalPadding` 控制单元格垂直内边距。`headingSpacing` 已废弃，改用 `headingTopSpacing` / `headingBottomSpacing`。
- 🖼 **行内图片顺序** - 行内图片保持其在段落中的位置，不再被提前到文本之前。
- 🧱 **折叠块展开与快照安全渲染** - 折叠块展开/收起不再丢内容更新，完整文档渲染保持正确并兼容快照安全布局。

### 2.1.1 (2026-08-18)

- 📏 **首次测高即准确** - 新增 `preferredMeasurementWidth`，宿主可在首次布局前告知最终内容宽度，Cell 首轮测高即正确，避免「先长高、再重刷」的两趟行高应用。
- ✨ **Append 打字机折行不再闪烁** - Append 打字机改为每帧测高，不再按字符数节流。软折行产生的新行立即获得高度，消除折行边界闪烁；对宿主的通知仍按「高度是否真正变化」节流，`typewriterHeightUpdateInterval` 已废弃、不再影响渲染。
- 📏 **流式增量高度阈值下调** - 真流式增量路径改为任意超过 0.5pt 的增长都上报宿主（原为 9pt），Cell 的 required 布局高度实时跟随内容，不再裁切正在打字的文字。
- 🧱 **快照宽度让位于宿主布局** - 列表包裹、引用块、分隔线宽度约束改为 999 优先级，预排版快照宽度让位于宿主真实宽度，避免 unsatisfiable-constraints 恢复布局。
- 🐛 **修复 0 高度反馈环** - `resetForReuse()` 后抑制空内容阶段的 0 高度上报，消除「渲染 → 高度回调 → batch 更新 → cell 复用」的自激环。
- 🧱 **Append 模式下原子引用/详情文本** - 引用块、详情块的子文本在整块揭示前先按最终高度排版，避免 Append 打字机播放期间文字被裁掉。
- 🧪 **回归测试覆盖** - 新增亚 9pt 流式增长上报、块宽度让位于宿主布局、Append 流式下原子引用文本可见性等用例。
- 🖥 **示例：HTML/JS 代码预览** - 示例 App 新增 HTML/JS 代码块预览渲染器与演示样例。

### 2.0.0 (2026-08-13)

- 🤖 **AI 对话联网搜索与工具调用** - AI Chat 示例接入 DeepSeek 的 function calling，内置 `web_search` 工具：当模型需要训练数据之外的信息时会发起搜索，示例执行真实联网搜索（默认 Bing，另支持 Tavily、DuckDuckGo、Bocha），将结果回传并流式输出最终答案；搜索失败优雅降级，多轮工具调用上下文（`reasoning_content`）跨轮持久化。
- 🗣 **AI 对话复制与朗读底部操作** - 每条消息 Cell 底部新增「复制全部内容」和「朗读/停止」按钮，朗读基于 SpeechKit（`AVSpeechSynthesizer`）。
- 🧠 **Thinking 模式参数** - AI Chat 示例透传本地配置中的 `thinking` 与 `reasoning_effort`，并在使用工具时正确回传 `reasoning_content`。
- 📊 **表格横向滚动更流畅** - 表格 Cell 复用时不再整段拷贝富文本，集合布局只返回可见行列而非全量过滤，并开启横向锁定减少手势冲突。
- 🐛 **修复自适高约束冲突** - 列表包裹、分隔线、引用块的宽度约束改为较低优先级，消除聊天/历史 Cell 中的 unsatisfiable-constraints 警告。
- 🐛 **修复重复渲染反馈环** - 赋值相同 Markdown 或预渲染内容不再触发整篇重渲染，Cell 复用也不再重置上次上报高度，消除「渲染 → 高度回调 → batch 更新 → cell 复用」的循环。

### 1.9.9 (2026-08-06)

- 🎨 **四套 Demo 主题与主题画廊** - 新增暖纸张、鼠尾草、深海代码和暮紫夜色四套主题预览，通过 Demo 自有的 `UserDefaults` 持久化选择，并统一覆盖 Markdown 预览、AI Chat/历史、长历史列表、TableView Streaming 与智能流式示例。
- 🧱 **块级外观可配置** - 为代码块、引用块、表格、图片、LaTeX 和详情块新增圆角与边框配置；这些设置仅作用于 `CALayer`，不参与高度测量，也不会改变滚动范围。
- ➗ **公式渲染跟随主题** - 新增 `latexTextColor`，让公式字形和绘制线条随主题切换，同时保留公式内显式 LaTeX `\color{...}` 的优先级。
- 🔄 **预渲染样式保持一致** - Demo 页面为 `MarkdownRenderer` 和 Markdown 视图注入同一份主题配置，避免 AI Chat/历史缓存内容使用过期主题颜色。
- 🖼 **更干净的图片默认外观** - Demo 主题保留图片圆角但默认关闭图片边框；边框能力仍作为可选外观配置提供。

### 1.9.8 (2026-08-04)

- 🚀 **带背压的智能流式管线** - SmartBuffer 现在增量释放安全的完整前缀，在后台串行解析模块，并按照单帧预算和 Typewriter 高低水位控制视图创建。即使解析速度超过播放速度，输入顺序、UI 顺序和最终 drain 完成条件仍保持确定性。
- ⚡ **基于 DisplayLink 的打字机调度** - 用 30 FPS `CADisplayLink` 时间线替换递归延迟 tick；标点延迟按 UTF-16 坐标预计算，待处理任务通过 O(1) FIFO head 消费，单帧追赶多个逻辑 step 时最多执行一次 reveal/布局回调。
- 📏 **增量高度缓存** - 流式高度根据 root 首次可见和文本高度 delta 增长，不再反复 fitting 整棵 `UIStackView`；相同宽度的 intrinsic size 读取直接命中缓存，高度通知统一合并，结构变化仍安全回退到完整校准。
- ✨ **稳定渲染，避免重复重绘闪烁** - TextKit 视图只在真实 bounds 变化时失效绘制；智能流式 TableView 更新串行合并，并保证结束时最终 flush，避免重叠的 self-sizing batch 反复重绘已展示内容。
- 🧱 **富文本块布局工作量有界** - 表格复用稳定布局几何，引用块按原子模块展示，只有真实宽度变化才触发布局测高失效；随着文档增长，表格、引用等富文本不再放大全文布局开销。
- 🔒 **模块与自定义扩展处理确定化** - 完整模块保持全局顺序和文档级标题 ID；fenced code 与 opaque 自定义块跨 chunk 时保持完整，自定义流式标签继续通过 `streamingBlockTagName` 显式启用。
- 🧹 **智能流式 API 与示例收敛** - 智能流式统一使用 `beginRealStreaming()`、`appendStreamData(_:)` 和 `endRealStreaming(completion:)`；删除预切块 `appendBlock` 路径及未使用的流式示例控件。
- 📊 **可选性能诊断与回归覆盖** - 新增通过 `MD_STREAM_PERF_LOG=1` / `MD_STREAM_PERF_ONLY=1` 开启的 `[MDPERF]` 聚合诊断，并覆盖 Unicode 标点、emoji 边界、FIFO 顺序、背压、重绘去重、高度缓存和最终 drain。合并基线已通过 68 项 iOS Simulator 测试以及 SwiftPM/CocoaPods 示例构建。

<details>
<summary>展开查看 1.8.9 及更早版本记录</summary>

### 1.8.9 (2026-07-31)

- 🔒 **自定义扩展注册表线程安全** - Parser、ViewProvider、ActionHandler 与代码块 Renderer 的注册和读取现已加锁；第三方 Parser 回调在锁外执行，避免重入死锁。
- 🖼 **统一使用 Kingfisher 图片管线** - 删除重复的自研内存/磁盘图片缓存，图片加载、缓存命中和请求取消统一交由 Kingfisher 处理。
- ⚡ **LaTeX 公式真正单次解析** - 公式只解析一次，并由尺寸测量、Attachment 布局和视图创建共享同一个渲染结果，无需引入人为唯一 ID。
- 🧩 **Markdown 渲染器模块化拆分** - 将超长的 `MarkdownDisplayView.swift` 拆分为职责清晰的 `MarkdownViewTextKit` Extension 文件，同时保持公开 API 和既有渲染行为不变。

### 1.8.6 (2026-07-31)

- 🐛 **修复首次进入时折叠模块前大段留白** - 长有序列表不再在后续标题或 `<details>` 折叠模块前产生整屏空白；列表 wrapper 改为严格跟随真实内容高度，避免被 Auto Layout 任意纵向拉伸。
- 📏 **无需用户滑动即可同步延迟布局** - 离屏元素追加完成后，Markdown 最终高度会主动沿外层 ScrollView 的 `contentLayoutGuide` 和 `contentSize` 完成同步，不再依赖用户先滑动一次触发布局刷新。
- 📍 **追加式渲染保持当前滚动位置** - 延迟内容追加在当前视口下方时，不再把全部新增高度错误累加到 `contentOffset`，避免首次渲染期间发生错误跳转或被旧滚动范围截断。

### 1.8.5 (2026-07-30)

- ⚡ **流式缓存器增量扫描** - `MarkdownStreamBuffer.append()` 由每次全文重扫改为只扫描未提交尾部，消除 O(n²) 开销，长文本流式输入实测提速 1.6~3.8 倍；补齐 chunk 边界无关性差分测试锁定行为不变量。
- ⚡ **TextKit 2 增量排版与测高** - 打字机逐字追加不再整篇替换 attributedString，改为事务内增量修改；测高改用 `usageBoundsForTextContainer`，消除流式追加场景下的 O(n²) 卡顿。
- ⚡ **LaTeX 公式解析去重** - 单个公式的重复解析从 6 次降到 1 次，`LatexMathView` 内容未变时短路跳过。
- 🐛 **修复回归审查合入后的三处渲染缺陷** - 恢复容器宽度取值语义、修复 `draw(_:)` 脏矩形裁剪导致内容截断、离屏占位替换新增淡入过渡，避免闪烁。
- 🐛 **消除后台线程 UIKit 访问** - 统一在主线程读取容器宽度快照后再进入后台解析，规避潜在崩溃风险。
- 🐛 **流式自动滚动优化** - 增加用户接管判定与节流，用户上滑回看历史内容时不再被强制拽回底部。
- ⚡ **打字机看门狗改为常驻 Timer** - 避免每步重建 Timer，且在 `.common` RunLoop mode 下滚动期间仍可正常兜底。
- ⚡ **正则缓存覆盖补全** - 详情块与代码高亮的正则匹配统一走已有的 `cachedRegex`。
- 🧹 **代码清理** - 删除全仓库零调用的增量解析死代码；251 处调试日志加 `#if DEBUG` 守卫，降低 Release 包的日志开销。
- ✨ **AI 对话示例增强** - CocoaPods/SPM 示例新增聊天历史记录能力，并优化交互细节。

### 1.8.1 (2026-07-15)

- 📏 **Append 打字机高度稳定性** - 字符揭示与高度重测解耦，仅在高度真正变化时触发布局回调，减少流式播放时的行高抖动。
- 🧱 **不再预暴露最终空白高度** - Append 模式在开始打字前会丢弃预计算的最终高度，避免 Cell 先闪出大块空白，高度只随可见文本增长。
- 🔒 **播放期高度下限** - Append 打字机播放期间禁止因临时宽度修正而回缩高度，避免气泡上下跳动；播放完成或引擎 stop 后释放下限，宽屏重排仍可正常收敛。
- 🧪 **流式布局测试** - 新增字符揭示/高度解耦、播放前高度重置、完成/停止后释放高度下限等覆盖用例。

### 1.8.0 (2026-07-14)

- 🌊 **真流式渲染稳定性修复** - 开始真流式输出时会取消并失效尚未完成的普通渲染任务，避免旧解析结果回写并覆盖正在运行的打字机界面。
- 🧱 **原子块级内容整块显示** - 表格、代码块、图片、LaTeX、详情块、分隔线和自定义视图会按最终高度整块显示，不再从临时 `1pt` 占位高度逐步撑开。
- 📜 **聊天自动跟随与行高修复** - SPM 与 CocoaPods 的 AI 聊天示例会合并行高更新，在布局变化后持续跟随流式消息，并在用户浏览历史消息时暂停自动滚动。
- ✨ **减少流式 Cell 闪烁** - 离屏增量不再反复 reload Cell，复用后的流式 Cell 会从累计内容继续输出，并等待打字机队列真正播放完毕后再切换为静态展示。

### 1.7.8 (2026-05-26)

- 🖼 **Kingfisher 图片加载** - `ImageView.swift` 中的 Markdown 图片加载与缓存切换为 Kingfisher 8.9.0。
- 📦 **依赖对齐** - `Package.swift` 与 `MarkdownDisplayKit.podspec` 同步声明 Kingfisher，SPM 和 CocoaPods 使用同一个图片库。
- 🧪 **示例更新** - `ExampleForMarkdown` 和 `CocoapodsMDExample` 的图片视图已更新为 Kingfisher 加载实现。

### 1.7.5 (2026-05-15)

- 🚀 **预渲染内容渲染入口** - 新增 `MarkdownRenderer.prepare(_:)` 与 `MarkdownViewTextKit.setPreparedContent(_:)`，业务侧可提前解析长 Markdown，并复用生成好的渲染元素。
- 📏 **预计算高度快速路径** - 预渲染结果携带元素高度估算，在宽度已知时文本/标题视图可跳过首次 TextKit 高度计算。
- 🧪 **历史长 Markdown 示例优化** - `CocoapodsMDExample` 中的历史消息页面改为后台预渲染长 Markdown，并使用缓存行高，降低首次滑动卡顿。
- 🐛 **历史消息空白修复** - 移除过大的初始行高占位，并修正高度回调设置顺序，确保真实测量高度能正确替换估算高度。

### 1.7.4 (2026-04-10)

- 📏 **高度测量稳定性修复** - 加固 `notifyHeightChange`：增加宽度兜底、基于 frame 的高度回退，以及临时 `0` 高度抑制，避免初始布局或快速更新时出现 `0 ↔ 实际高度` 来回跳变。
- 🌊 **段落级流式切分回退** - 当标题数量不足以用于模块切分时，真流式模式现在会按段落边界输出单标题或无标题 Markdown，同时跳过 fenced code block 内部的空段切分。
- 📐 **整个列表头尾内边距** - 新增 `listTopPadding` 和 `listBottomPadding`，支持为整个列表 wrapper 配置顶部/底部间距，而不改变每个列表项自身布局。

### 1.7.2 (2026-04-04)

- ➕ **新增 `isPlainText()` 检测** - 在 `MarkdownStreamBuffer` 中新增 `isPlainText()`，用于识别非 Markdown 内容。
- ⚡ **纯文本流式输出加速** - 对于没有 Markdown 标记的纯文本，模块可在 `\n` 边界提交，不再强制等待 `\n\n`，以更快触发打字机输出。
- ✅ **Markdown 输出行为保持不变** - Markdown 内容仍然等待 `\n\n` 段落边界后提交。

### 1.7.1 (2026-04-03)

- 🐛 **有序列表高度一致性修复** - 修复部分 Stack/ReUse 场景下“第一个有序列表项高度被异常拉高、与后续项不一致”的问题。
- 🧱 **列表布局约束加固** - 调整列表外层约束（`bottom <=`）并增强垂直方向 hugging/compression 优先级，避免额外高度被首项吸收。
- 🧹 **列表内容归一化清理** - 增加列表不可见文本节点清理（首尾换行、零宽字符、控制/空白字符），避免“幽灵高度”撑开列表项。

### 1.7.0 (2026-04-03)

- 📊 **Markdown 表格列对齐支持** - 新增 `:---`、`:---:`、`---:` 对齐语法解析，并按列应用左/中/右对齐。
- 🛠 **异常表格自动修复** - 新增 `autoFixMalformedTables`（默认 `true`），自动修正常见异常输出（孤立 `|`、表格块内误空行）。
- ✍️ **行间距配置化** - 新增 `lineSpacing` 配置（`body`、`heading`、`quote`、`codeBlock`），替代固定行间距常量。
- 🔗 **表格链接点击回调** - 表格 cell 保持 `UILabel`（滚动性能更优），通过 cell 点击识别链接并复用 `onLinkTap` 回调链路。
- 🐛 **触摸路由修复** - 修复外层 TextKit 点击手势可能抢占表格附件触摸，导致表格链接点击不生效的问题。
- ⚠️ **配置项收敛** - 移除表格文本对齐覆盖配置项；表格文本对齐以 Markdown 语法为准（默认左对齐）。

### 1.6.9 (2026-03-17)

- 🔗 **链接下划线可配置** - 新增 `linkUnderlineEnabled` 配置项，支持控制链接是否显示下划线
  - `MarkdownConfiguration` 新增属性 `linkUnderlineEnabled: Bool`（默认值 `true`）
  - 同时作用于 Markdown 行内链接（`[文字](url)`）和目录导航链接
  - **根因修复**：实现 `NSTextLayoutManagerDelegate.renderingAttributesForLink(_:at:defaultAttributes:)` 代理方法，正确拦截 TextKit 2 内置链接渲染管线——此前该管线会完全忽略 `NSAttributedString` 中设置的 `underlineStyle` 属性

### 1.6.8 (2026-02-06)

- 📜 **代码块横向滚动** - 代码块现支持横向滚动，可查看完整的长代码行
  - 采用 `NSTextAttachmentViewProvider` 模式实现，与 LaTeX 公式和表格的渲染架构保持一致
  - 新增 `CodeBlockAttachment` 和 `CodeBlockAttachmentViewProvider` 类处理代码块渲染
  - 代码文本不再换行，用户可通过横向滚动查看完整代码内容
  - 保留原有的语法高亮、背景色和圆角样式

### 1.6.2 (2026-02-05)

- 📳 **震动反馈时机优化** - 震动反馈现与 TypewriterEngine 输出节奏精确同步
  - 文字震动：仅在 `revealCharacter` 实际显示新字符时触发
  - 块级震动：在块级元素（图片、LaTeX 等）动画完成时触发
  - 移除容器视图（`.show`）和小元素（`.label`）的不必要震动
  - 震动不再在数据到达时触发，而是在内容实际显示时触发

### 1.6.1 (2026-02-02)

- 📳 **流式输出震动反馈** - 新增流式输出时的震动反馈支持，提升用户交互体验
  - 新增 `StreamingHapticFeedbackStyle` 枚举，支持多种震动级别：`.none`、`.light`、`.medium`、`.heavy`、`.soft`、`.rigid`
  - 新增配置项 `streamingHapticFeedbackStyle`（震动反馈强度）和 `streamingHapticMinInterval`（震动最小间隔）
  - 震动反馈跟随真实流式管线（`appendStreamData`）展示的内容

### 1.6.0 (2026-01-30)

- 🎨 **全面配置项支持** - 新增所有 Markdown 元素的详细配置：
  - **LaTeX 公式**：`latexFontSize`、`latexAlignment`（居左/居中/居右）、`latexBackgroundColor`、`latexPadding`
  - **引用块**：`blockquoteBackgroundColor`、`blockquoteBarWidth`、`blockquoteContentSpacing`、`blockquoteContentPadding`
  - **表格**：`tableMinColumnWidth`、`tableMaxColumnWidth`、`tableRowHeight`、`tableCellPadding`、`tableSeparatorHeight`
  - **列表**：`listItemSpacing`、`listMarkerMinWidth`、`listMarkerSpacing`
  - **折叠块**：`detailsSummaryFont`、`detailsSummaryTextColor`、`detailsSummaryMinHeight`、`detailsContentPadding`、`detailsSpacing`
  - **代码高亮**：`syntaxColors`、`syntaxColorsDark`，支持 `SyntaxHighlightColors` 结构体（关键字、字符串、数字、注释、类型、函数、属性、预处理器）
  - **目录**：`tocTextColor`
- 🐛 **Bug 修复** - `tableRowBackgroundColor` 现已正确应用于表格行
- 📝 **文档更新** - 更新 README 完善所有配置选项文档

### 1.5.9 (2026-01-26)

- 🚀 **打字机追加模式** - 新增 `.append` 模式，并对高度更新节流，减少 Cell 流式输出时的布局跳变
- ⚙️ **流式配置项** - 提供 `typewriterTextMode`、`typewriterHeightUpdateInterval`、`streamMinModuleLength`
- 🧹 **内存清理** - 增加缓存清理与 Mermaid WebView 释放逻辑，降低页面退出后的驻留内存
- 🧪 **示例更新** - AI 对话流式 LaTeX 规范化更安全（忽略代码区域），并给出推荐配置

### 1.5.8 (2026-01-23)

- 📝 **文档更新** - 更新 README 内容
- 🐛 **SPM 修复** - 修复 Swift Package Manager 示例在模拟器上的编译问题

### 1.5.2 (2026-01-08)

- 🐛 **崩溃修复** - 串行化 `swift-markdown` 解析，避免并发渲染触发 `cmark_parser_attach_syntax_extension` 崩溃
- 🧹 **复用安全** - 新增 `resetForReuse()` 清理内部缓存与状态，适配 `UITableViewCell` 复用场景
- 🧪 **示例更新** - 增加崩溃复现页面与表格场景的逐条插入演示

### 1.5.1 (2026-01-07)

- 🐛 **Bug 修复** - 修复流式渲染处理 Unicode 字符（emoji、中日韩字符）时可能崩溃的问题
  - `MarkdownStreamBuffer.extractModule`: 使用 `limitedBy` 安全获取字符串索引，防止越界崩溃
  - `TypewriterEngine.calculateDelay`: 使用安全索引获取字符，防止计算特殊字符延迟时崩溃

### 1.5.0 (2026-01-04)

- 🚀 **真流式渲染支持** - 新增 `MarkdownStreamBuffer` 智能流式缓冲器，支持网络/LLM API 实时流式渲染
  - 智能模块检测：自动识别完整的 Markdown 块（标题、代码块、表格、LaTeX 公式）
  - 未闭合结构处理：等待闭合标签后再渲染（如未闭合的 ``` 或 $$）
  - 增量渲染：完整模块立即渲染，未完成内容继续缓冲
- 💫 **智能等待动画** - 真流式模式下，当 TypewriterEngine 队列为空且网络数据未到达时，自动显示等待动画
- 🏗️ **代码重构** - 将 `MarkdownTextViewTK2`、`MarkdownStreamBuffer` 和 `TypewriterEngine` 提取到独立文件，提升代码可维护性
- 🐛 **流式修复** - 多项真流式模式稳定性和渲染问题修复

### 1.4.1 (2026-01-02)

- 🐛 **Bug 修复** - 修复真流式模式下代码块分块到达时无法正确渲染的问题

### 1.4.0 (2025-12-31)

- 🚀 **秒开优化** - 大幅优化加载速度，首屏渲染极速完成
- ⚡ **CPU 优化** - 流式模式下增加嵌套样式展示后，CPU 使用率大幅降低（iPhone 17 Pro 模拟器峰值 < 56%，平均 30%）
- 🔌 **自定义扩展增强** - 新增代码块渲染器协议 `MarkdownCodeBlockRenderer`，支持 Mermaid 等图表渲染
- 🎨 **Mermaid 支持** - 示例项目新增 Mermaid 图表渲染器，支持流程图、思维导图等

### 1.0.0 (2025-12-15)

- 🎉 首次发布
- ✅ 完整 Markdown 语法支持
- ✅ 20+ 种语言代码高亮
- ✅ 自动目录生成
- ✅ 深色模式支持
- ✅ 高性能异步渲染

</details>

## 贡献

欢迎提交 Issue 和 Pull Request！

在提交 PR 前，请确保：

- 代码通过编译
- 遵循现有代码风格
- 添加必要的测试

## 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件。

## 作者

MarkdownDisplayView 由 [@zjc19891106](https://github.com/zjc19891106) 创建和维护。
如果觉得这个库帮到你的忙节省了你的时间，可以考虑支持一下我，感谢所有打赏支持我的朋友们，这里就不一一点名了！您的支持有助于作者的长期维护与改进。

- 支持作者
- WeChat
  ![](Support/wechat.jpg)
- AliPay
  ![](Support/alipay.jpg)
- Paypal
  ![](Support/paypal.png)

## 致谢

- [swift-markdown](https://github.com/swiftlang/swift-markdown) - Markdown 解析库
- [Kingfisher](https://github.com/onevcat/Kingfisher) - 图片加载与缓存库
- [KaTeX](https://github.com/KaTeX/KaTeX) - 数学公式渲染字体
- Apple TextKit 2 - 高性能文本渲染框架
- Gemini3 Pro&Claude&Grok&GPT
- 所有贡献者和使用者
- 所有给我提供建议和反馈的朋友们


## 联系方式

如有问题或建议，请通过以下方式联系：

- 提交 [GitHub Issue](https://github.com/zjc19891106/MarkdownDisplayView/issues)
- 发送邮件至：984065974@qq.com 或 luomobancheng@gmail.com

- QQ 群 
![QQ群](./Communication/qq.jpeg) 

- Telegram
![Telegram](./Communication/telegram.jpeg)

- Discord
![Discord](./Communication/discord.jpeg)

---

**如果觉得这个项目有帮助，请给个 Star ⭐️ 支持一下！**
