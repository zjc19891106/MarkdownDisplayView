# MarkdownDisplayView

一个功能强大的 iOS Markdown 渲染组件，基于 TextKit 2 构建，提供流畅的渲染性能和丰富的自定义选项。同时也支持流式渲染md格式。

## 效果展示

## Demo Effects

### Normal Rendering

![Normal Rendering](./Effects/normal.gif)

### Streaming Rendering

![Streaming Rendering](./Effects/streaming.gif)

## ✨ 特性

- 🚀 **高性能渲染** - 基于 TextKit 2，支持异步渲染和增量更新，流式渲染等，示例全部加载示例md内容渲染时间首次270ms左右,再次渲染120ms左右,MarkdownView库渲染同样内容超过400ms
- 🎨 **完整 Markdown 支持** - 标题、列表、表格、代码块、引用、图片等
- 🌈 **语法高亮** - 支持 20+ 种编程语言的代码高亮（Swift、Python、JavaScript 等）
- 📑 **自动目录** - 自动提取标题生成可交互目录
- 🎯 **高度可定制** - 字体、颜色、间距等全方位配置
- 🔗 **事件回调** - 链接点击、图片点击、目录导航
- 📱 **iOS 原生** - 使用 UIKit 和 TextKit 2 构建，性能优异
- 🌓 **深色模式** - 内置浅色和深色主题配置

## 📋 系统要求

- iOS 15.0+(TextKit2 要求)
- Swift 5.9+
- Xcode 16.0+

## 📦 安装

### Swift Package Manager

#### 方式一:Xcode 添加

1. 在 Xcode 中打开你的项目
2. 选择 `File` → `Add Package Dependencies...`
3. 输入仓库 URL:`https://github.com/你的用户名/MarkdownDisplayView.git`
4. 选择版本并点击 `Add Package`

#### 方式二:Package.swift

在 `Package.swift` 中添加依赖:

```swift
dependencies: [
    .package(url: "https://github.com/你的用户名/MarkdownDisplayView.git", from: "1.0.0")
]
```

然后在 target 中添加:

```swift
.target(
    name: "YourTarget",
    dependencies: ["MarkdownDisplayView"]
)
```

### CocoaPods

在你的 `Podfile` 中添加以下内容:

```ruby

pod 'MarkdownDisplayKit'
```

然后运行:

```bash
pod install
```

## 🚀 快速开始

### 基础用法

```swift
import UIKit
import MarkdownDisplayView

class ViewController: UIViewController {

    private let markdownView = ScrollableMarkdownViewTextKit()

    override func viewDidLoad() {
        super.viewDidLoad()

        // 添加到视图层级
        view.addSubview(markdownView)
        markdownView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            markdownView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            markdownView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            markdownView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            markdownView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // 设置 Markdown 内容
        markdownView.markdown = """
        # 欢迎使用 MarkdownDisplayView

        这是一个**功能强大**的 Markdown 渲染组件。

        ## 主要特性
        - 支持完整的 Markdown 语法
        - 代码语法高亮
        - 自动生成目录
        - 图片异步加载

        ### 代码示例

        ```swift
        let message = "Hello, World!"
        print(message)
        ```

        [访问 GitHub](https://github.com)
        """
    }
}
```

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

## 🎨 自定义配置

### 使用预设主题

```swift
// 使用默认浅色主题
markdownView.configuration = .default

// 使用深色主题
markdownView.configuration = .dark
```

### 自定义配置

```swift
var config = MarkdownConfiguration.default

// 自定义字体
config.bodyFont = .systemFont(ofSize: 17)
config.h1Font = .systemFont(ofSize: 32, weight: .bold)
config.codeFont = .monospacedSystemFont(ofSize: 15, weight: .regular)

// 自定义颜色
config.textColor = .label
config.linkColor = .systemBlue
config.codeBackgroundColor = .systemGray6
config.blockquoteTextColor = .secondaryLabel

// 自定义间距
config.paragraphSpacing = 16
config.headingSpacing = 20
config.imageMaxHeight = 500

// 应用配置
markdownView.configuration = config
```

### 完整配置选项

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
public var codeTextColor: UIColor                      // 代码文本颜色
public var codeBackgroundColor: UIColor                // 代码背景色
public var blockquoteTextColor: UIColor                // 引用文本颜色
public var blockquoteBarColor: UIColor                 // 引用边框颜色
public var tableBorderColor: UIColor                   // 表格边框颜色
public var tableHeaderBackgroundColor: UIColor         // 表头背景色
public var tableAlternateRowBackgroundColor: UIColor   // 表格交替行背景色
public var horizontalRuleColor: UIColor                // 分隔线颜色
public var imagePlaceholderColor: UIColor              // 图片占位符颜色
```

#### 间距配置

```swift
public var paragraphSpacing: CGFloat       // 段落间距
public var headingSpacing: CGFloat         // 标题间距
public var listIndent: CGFloat             // 列表缩进
public var codeBlockPadding: CGFloat       // 代码块内边距
public var blockquoteIndent: CGFloat       // 引用缩进
public var imageMaxHeight: CGFloat         // 图片最大高度
public var imagePlaceholderHeight: CGFloat // 图片占位符高度
```

## 📑 目录功能

### 获取自动生成的目录

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

// 添加到界面
view.addSubview(tocView)
```

### 滚动到指定标题

```swift
// 点击目录项时滚动到对应位置
markdownView.onTOCItemTap = { item in
    markdownView.scrollToTOCItem(item)
}
```

## 🎯 支持的 Markdown 语法

### 标题

```markdown
# H1 一级标题
## H2 二级标题
### H3 三级标题
#### H4 四级标题
##### H5 五级标题
###### H6 六级标题
```

### 文本格式

```markdown
**粗体文本**
*斜体文本*
***粗斜体***
~~删除线~~
`行内代码`
```

### 列表

#### 无序列表

```markdown
- 项目 1
- 项目 2
  - 嵌套项目 2.1
  - 嵌套项目 2.2
```

#### 有序列表

```markdown
1. 第一项
2. 第二项
   1. 嵌套 2.1
   2. 嵌套 2.2
```

#### 任务列表

```markdown
- [x] 已完成任务
- [ ] 待完成任务
```

### 链接和图片

```markdown
[链接文本](https://example.com)
![图片描述](https://example.com/image.png)
```

### 引用

```markdown
> 这是一段引用文本
> 可以包含多行
>> 支持嵌套引用
```

### 代码块

支持语法高亮的编程语言：

- Swift、Objective-C
- JavaScript、TypeScript、Python、Ruby
- Java、Kotlin、Go、Rust
- C、C++、Shell、SQL
- HTML、CSS、JSON、YAML
- 以及更多...

````markdown
```swift
func greet(name: String) -> String {
    return "Hello, \(name)!"
}
print(greet(name: "World"))
```
````

### 表格

```markdown
| 列1 | 列2 | 列3 |
|-----|-----|-----|
| A1  | B1  | C1  |
| A2  | B2  | C2  |
```

### 分隔线

```markdown
---
***
___
```

### 折叠区域（Details）

```html
<details>
<summary>点击展开</summary>

这里是折叠的内容
可以包含任何 Markdown 语法

</details>
```

### 脚注

```markdown
这是一段文本[^1]

[^1]: 这是脚注内容
```

## 📱 完整示例

查看 `Example/ExampleForMarkdown` 目录下的完整示例项目，包含：

- 所有 Markdown 语法的渲染效果
- 自定义配置示例
- 事件回调处理
- 性能测试

运行示例项目：

```bash
cd Example/ExampleForMarkdown
open ExampleForMarkdown.xcodeproj
```

## ⚡️ 性能优化

- **异步渲染** - Markdown 解析和渲染在后台队列执行，不阻塞主线程
- **增量更新** - 使用 Diff 算法，只更新变化的部分
- **图片懒加载** - 图片异步加载，带缓存机制
- **正则缓存** - 语法高亮正则表达式缓存复用
- **视图复用** - 高效的视图更新策略

## 🔧 高级用法

### 直接使用核心视图（无滚动）

```swift
let markdownView = MarkdownViewTextKit()
// 需要自己管理滚动容器
```

### 监听高度变化

```swift
let markdownView = MarkdownViewTextKit()

markdownView.onHeightChange = { newHeight in
    print("内容高度变化为: \(newHeight)")
    // 可用于动态调整容器高度
}
// 设置链接点击回调
markdownView.onLinkTap = { [weak self] url in
    // 处理链接点击
    if UIApplication.shared.canOpenURL(url) {
        UIApplication.shared.open(url)
    }
}
markdownView.onImageTap = { imageURL in
    //获取图片,如果已经加载出来
    _ = ImageCacheManager.shared.image(for: imageURL)
}
markdownView.onTOCItemTap = { item in
    print("title:\(item.title), level:\(item.level), id:\(item.id)")
}
```

### 使用带滚动的视图（推荐）

```swift
let scrollableView = ScrollableMarkdownViewTextKit()
view.addSubview(scrollableMarkdownView)

scrollableMarkdownView.translatesAutoresizingMaskIntoConstraints = false

NSLayoutConstraint.activate([
    scrollableMarkdownView.topAnchor.constraint(
                equalTo: view.topAnchor, constant: 88),
    scrollableMarkdownView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
    scrollableMarkdownView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    scrollableMarkdownView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
])
// 内置 UIScrollView，自动处理滚动
scrollableMarkdownView.onLinkTap = { [weak self] url in
    // 处理链接点击
    if UIApplication.shared.canOpenURL(url) {
        UIApplication.shared.open(url)
    }
}
scrollableMarkdownView.onImageTap = { imageURL in
    //获取图片,如果已经加载出来
    _ = ImageCacheManager.shared.image(for: imageURL)
}
scrollableMarkdownView.onTOCItemTap = { item in
    print("title:\(item.title), level:\(item.level), id:\(item.id)")
}
scrollableMarkdownView.markdown = sampleMarkdown
//返回目录
scrollableMarkdownView.backToTableOfContentsSection()
```

### 流式Readme展示

- 其他与上面滚动markdown view一致

```Swift
    //不一致是显示内容
    private func loadSampleMarkdown() {
        // 流式渲染（打字机效果）
        scrollableMarkdownView.startStreaming(
            sampleMarkdown,
            unit: .word,
            unitsPerChunk: 2,
            interval: 0.1,
        )
    }

    // 如果需要立即显示全部（比如用户点击跳过）
    @objc private func skipButtonTapped() {
        scrollableMarkdownView.markdownView.finishStreaming()
    }
```

## 🐛 故障排除

### 1. 编译错误：找不到 UIKit

**问题**：在 macOS 上使用 `swift build` 编译失败

**解决方案**：此库仅支持 iOS 平台，必须在 Xcode 中针对 iOS 模拟器或设备进行构建

### 2. 图片不显示

**问题**：Markdown 中的图片无法显示

**原因**：

- 图片 URL 无效或无法访问
- 网络权限未配置

**解决方案**：

- 检查 Info.plist 中的网络权限配置
- 使用有效的图片 URL

### 3. Swift 并发警告

**问题**：出现 Sendable 相关警告

**解决方案**：库已使用 Swift 5.9 构建，避免严格并发检查

## 📝 更新日志

### 1.0.0 (2025-12-15)

- 🎉 首次发布
- ✅ 完整 Markdown 语法支持
- ✅ 20+ 种语言代码高亮
- ✅ 自动目录生成
- ✅ 深色模式支持
- ✅ 高性能异步渲染

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

在提交 PR 前，请确保：

- 代码通过编译
- 遵循现有代码风格
- 添加必要的测试

## 📄 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件。

## 👨‍💻 作者

MarkdownDisplayView 由 [@zjc19891106](https://github.com/zjc19891106) 创建和维护。

- 支持作者
- WeChat
  ![](Support/wechat.jpg)
- AliPay
  ![](Support/alipay.jpg)
- Paypal

  ![](Support/paypal.png)

## 🙏 致谢

- [swift-markdown](https://github.com/swiftlang/swift-markdown) - Markdown 解析库
- Apple TextKit 2 - 高性能文本渲染框架
- Gemini3 Pro&Claude&Grok&GPT 
- 所有贡献者和使用者

## 📮 联系方式

如有问题或建议，请通过以下方式联系：

- 提交 [GitHub Issue](https://github.com/zjc19891106/MarkdownDisplayView/issues)
- 发送邮件至：984065974@qq.com 或 luomobancheng@gmail.com

---

**如果觉得这个项目有帮助，请给个 Star ⭐️ 支持一下！**
