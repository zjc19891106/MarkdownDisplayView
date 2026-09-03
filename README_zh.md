*[English](README.md) | 中文*

# MarkdownDisplayView

一个基于 TextKit 2 的 iOS UIKit **高性能纯原生** Markdown 渲染组件，**内置 100% 原生 LaTeX 数理公式与化学式（无机/有机）排版引擎**，支持样式配置、后台解析、增量 UI 更新和实时 AI/SSE 流式输出。

- **100% 纯原生（Zero-WebView）**：内置自研 LaTeX 递归下降解析器与 CoreGraphics/CoreText 几何排版引擎，零 Web 容器开销，秒开无延迟。
- **独家化学式支持**：支持无机化学方程式（`\ce` 自动上下标/价态/平衡）与有机化学结构式（`\chemfig` 原生矢量绘制苯环/芳香环/TNT/甲苯等取代基）。
- **极佳内存控制**：示例长文档16kb（包含大部分样式），全文加载滑动内存 iPhone 14 Pro 上仅 60~70MB。
- **AI 流式毫秒级渲染**：长文档字符随机长度按顺序裁切模拟流式，峰值内存 140 多 MB，停止流式后降回 70MB 左右；真实 AI 对话 4 轮后稳定在 40MB 左右。
- **内置 20 款 KaTeX 矢量字体**：自动动态注册学术字体，智能区分数学斜体与运算符正体，字形质感媲美印刷出版物。

> 🚀 **面向 AI 对话与文档页面：既可渲染完整 Markdown，也可持续追加 AI/SSE 增量，在数理化学术场景下具备极致的原生性能与排版表现。**

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
| 渲染架构 | TextKit 2、后台解析、首屏优先与增量 UI 更新，100% 原生渲染无 WebView 依赖 |
| AI/SSE 流式 | 安全模块缓冲、顺序增量、打字机输出、高度缓存和可选震动，复杂理科公式流式零闪烁 |
| 🧮 纯原生 LaTeX 与化学式 | **自研数学排版引擎**，内置 20 款 KaTeX 字体；支持微积分/矩阵/分段方程、无机化学方程式（`\ce`）及有机苯环结构式（`\chemfig`） |
| Markdown 规范 | 标题、列表、表格、引用、图片、LaTeX 公式、脚注、折叠块和可横向滚动代码块 |
| 代码高亮 | 内置 20+ 种常用语言高亮 |
| 导航 | 自动目录、标题跳转与文档内锚点 |
| 样式与主题 | 字体、颜色、间距、明暗预设与块级外观（公式/代码块均跟随主题） |
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

#### 🧮 纯原生 LaTeX 与化学公式语法

组件内置 100% 原生自研的 LaTeX 词法与语法解析器（`LatexLexer` + `LatexParser`），通过 CoreGraphics / CoreText 矢量几何排版引擎与内置 20 款 KaTeX 学术字体进行毫秒级排版，**完全不依赖任何 Web 容器或 JS 引擎**。

##### 1. 公式基础形式

- **行内公式** — 用单个美元符号 `$...$` 包裹，随正文在段落、标题、表格单元格、引用块和列表项中内联显示：
  ```markdown
  能量为 $E=mc^2$，动量为 $p=mv$。
  ```
- **行间公式** — 用双美元符号 `$$...$$` 包裹，以全宽块级形式居中显示，超宽时自动支持单手势横向平滑滚动：
  ```markdown
  $$
  \int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
  $$
  ```
- **围栏公式** — ```` ```math ```` 围栏渲染为行间公式；```` ```latex ```` 围栏保持代码源码，避免文档示例被误渲染。

> 💡 反引号（行内代码）内的 `$...$` 保持字面量，不会被当作公式误解析。

##### 2. 高等数学与物理公式支持

- **微积分、极限与求和**：
  ```markdown
  $$\lim_{x \to 0} \frac{\sin x}{x} = 1, \quad \sum_{i=0}^{n} i^2 = \frac{n(n+1)(2n+1)}{6}$$
  ```
- **矩阵（Matrix）与分支方程组（Cases）**：
  ```markdown
  $$\begin{bmatrix} 1 & x & x^2 \\ 0 & 1 & 2x \\ 0 & 0 & 2 \end{bmatrix}, \quad f(x) = \begin{cases} x^2 & x > 0 \\ -x & x \le 0 \end{cases}$$
  ```
- **动态伸缩括号与根号**：`\left( \frac{a}{b} \right)`、`\sqrt[n]{x}` 自适应包裹内部高度。
- **物理矢量、重音与装饰符**：`\mathbf{F} = m \vec{a}`、`\hat{v} = \frac{\dot{r}}{|r|}`、`\boxed{\bar{v}}`。

##### 3. 无机化学方程式支持（`\ce{...}`）

原生支持 mhchem 标准语法，自动处理分子式下标、离子价态上标与化学平衡：
- **经典反应方程式**：
  ```markdown
  $$\ce{2H2 + O2 -> 2H2O}$$
  $$\ce{2C8H18 + 25O2 -> 16CO2 + 18H2O}$$
  ```
- **离子反应与沉淀/气体符号**：
  ```markdown
  $$\ce{Cu^2+ + 2OH- -> Cu(OH)2 v}$$
  $$\ce{[Ag(NH3)2]+ + OH- -> AgOH v + 2NH3}$$
  ```
- **化学平衡与带反应条件的长箭头**：
  ```markdown
  $$\ce{N2 + 3H2 <=>[high T][high P] 2NH3}$$
  $$C_2H_5OH + CH_3COOH \xrightarrow{\text{conc. } H_2SO_4} CH_3COOC_2H_5 + H_2O$$
  ```

##### 4. 有机化学结构式支持（`\chemfig{...}`）

全网罕见的 **iOS 原生 CoreGraphics 矢量绘制化学结构式**，支持芳香环与复杂取代基的空间排布：
- **基础苯环与凯库勒式**：
  ```markdown
  $$\chemfig{**6(------)}$$
  $$\chemfig{*6(-=-=-=)}$$
  ```
- **甲苯、苯酚与三硝基甲苯 (TNT) 取代基空间绘制**：
  ```markdown
  $$\chemfig{**6(---(-OH)---)}$$
  $$\chemfig{**6(---(-CH_3)---)}$$
  $$\chemfig{**6(-NO_2-(-CH_3)-NO_2--NO_2-)}$$
  ```
- **完整有机化学反应方程式（结构式 + 反应符号混排）**：
  ```markdown
  $$\chemfig{**6(---(-CH_3)---)} + 3HNO_3 \longrightarrow \chemfig{**6(-NO_2-(-CH_3)-NO_2--NO_2-)} + 3H_2O$$
  ```

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

> 📖 更多历史版本更新记录，请参阅 [CHANGELOG.md](CHANGELOG.md)。

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

- 提交 [GitHub Issue](https://github.com/zjc19891106/MarkdownDisplayView/issues) 或 [Pull Request](https://github.com/zjc19891106/MarkdownDisplayView/pulls)
- 发送邮件至：984065974@qq.com 或 luomobancheng@gmail.com
- QQ 群 
  ![QQ群](./Communication/qq.jpeg) 

---

**如果觉得这个项目有帮助，请给个 Star ⭐️ 支持一下！**
