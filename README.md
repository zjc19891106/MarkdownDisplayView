*English | [中文](README_zh.md)*

# MarkdownDisplayView

A UIKit Markdown renderer for iOS built on TextKit 2, with configurable styles, background parsing, incremental UI updates, and real-time AI/SSE streaming.

> 🚀 **Designed for AI chat and document screens: render complete Markdown or append live AI/SSE deltas with configurable styling, typewriter output, and haptic feedback.**

## Contents

| Overview | Usage | Project |
|----------|-------|---------|
| [Demo Effects](#demo-effects) | [Quick Start](#quick-start) | [Complete Example](#complete-example) |
| [Features](#features) | [Custom Configuration](#custom-configuration) | [Performance Optimization](#performance-optimization) |
| [Requirements](#requirements) | [Table of Contents](#table-of-contents) | [Troubleshooting](#troubleshooting) |
| [Installation](#installation) | [Supported Markdown Syntax](#supported-markdown-syntax) | [Changelog](#changelog) |
| | [Advanced Usage](#advanced-usage) | [Contributing](#contributing) · [License](#license) |
| | [Custom Extensions](#custom-extensions) | [Author](#author) · [Acknowledgments](#acknowledgments) · [Contact](#contact) |

## Demo Effects

### Normal Rendering
![Normal Rendering](./Effects/normal.gif)

### Streaming Rendering
- Real AI/SSE chunk streaming

![Streaming Rendering](./Effects/streaming.gif)

- Chat with AI model

Create an untracked `Config.local.json` in the example target when you want to run the real AI chat demo.

<details>
<summary>Show Config.local.json structure</summary>

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

## Features

| Capability | What it provides |
|------------|------------------|
| Rendering | TextKit 2, background parsing, first-screen-first and incremental UI updates |
| AI/SSE streaming | Safe module buffering, ordered deltas, typewriter output, height caching, and optional haptics |
| Markdown | Headings, lists, tables, blockquotes, images, LaTeX, footnotes, details, and horizontally scrollable code blocks |
| Code highlighting | Built-in highlighting for 20+ common languages |
| Navigation | Generated table of contents, heading navigation, and internal anchors |
| Styling | Fonts, colors, spacing, light/dark presets, and block appearance |
| Extensions | Custom parsers, view providers, action handlers, and fenced-code renderers |
| Callbacks | Link, image, TOC, height, and streaming-step events |

## Requirements

| Item | Requirement |
|------|-------------|
| Deployment target | iOS 15.0+ |
| Swift tools | Swift 5.9+ |
| Xcode | Xcode 15.0+ for the package; the checked-in example project uses the Xcode 26 project format |

## Installation

| Package manager | Dependency name | Import |
|-----------------|-----------------|--------|
| Swift Package Manager | `MarkdownDisplayView` | `import MarkdownDisplayView` |
| CocoaPods | `MarkdownDisplayKit` | `import MarkdownDisplayKit` |

<details>
<summary>Show installation steps and commands</summary>

### Swift Package Manager
#### Method 1: Add via Xcode
1. Open your project in Xcode.
2. Choose `File` → `Add Package Dependencies...`
3. Enter the repository URL: `https://github.com/zjc19891106/MarkdownDisplayView.git`
4. Select the version and click `Add Package`.

#### Method 2: In Package.swift
Add the dependency in `Package.swift`:
```swift
dependencies: [
    .package(url: "https://github.com/zjc19891106/MarkdownDisplayView.git", from: "2.1.1")
]
```

Then add the library product to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "MarkdownDisplayView", package: "MarkdownDisplayView")
    ]
)
```

Swift Package Manager resolves `swift-markdown` and `Kingfisher` automatically.

### CocoaPods
Add the following lines to your `Podfile`:

```ruby
pod 'MarkdownDisplayKit', '~> 2.1.1'
```

Then run:

```bash
pod install
```

**Note**: `MarkdownDisplayKit.podspec` declares `AppleSwiftMDWrapper` for Markdown parsing and `Kingfisher (~> 8.9.0)` for image loading, so CocoaPods resolves those dependencies during `pod install`.

</details>

## Quick Start

### Basic Usage

Use `import MarkdownDisplayView` with Swift Package Manager. CocoaPods exposes the same API through `import MarkdownDisplayKit`.

```swift
import UIKit
import MarkdownDisplayView

let markdownView = ScrollableMarkdownViewTextKit()
markdownView.configuration = .default
markdownView.markdown = "# Hello\n\nRender **Markdown** with TextKit 2."
```

Add `markdownView` to your view hierarchy and constrain it like any other `UIScrollView`. See the working layout in [`MarkdownExampleViewController.swift`](Example/ExampleForMarkdown/ExampleForMarkdown/MarkdownExampleViewController.swift).

<details>
<summary>Show link and image callback examples</summary>

### Handle Link Taps

```swift
markdownView.onLinkTap = { url in
    if UIApplication.shared.canOpenURL(url) {
        UIApplication.shared.open(url)
    }
}
```

### Handle Image Taps

```swift
markdownView.onImageTap = { imageURL in
    print("Image tapped: \(imageURL)")
    // You can implement image preview functionality here
}
```

</details>

## Custom Configuration

### Using Preset Themes

<details>
<summary>Show preset theme code</summary>

```swift
// Use default light theme
markdownView.configuration = .default

// Use dark theme
markdownView.configuration = .dark
```

</details>

### Custom Configuration

<details>
<summary>Show a complete configuration example</summary>

```swift
var config = MarkdownConfiguration.default

// Custom fonts
config.bodyFont = .systemFont(ofSize: 17)
config.h1Font = .systemFont(ofSize: 32, weight: .bold)
config.codeFont = .monospacedSystemFont(ofSize: 15, weight: .regular)

// Custom colors
config.textColor = .label
config.linkColor = .systemBlue
config.linkUnderlineEnabled = false    // Disable link underline
config.codeBackgroundColor = .systemGray6
config.blockquoteTextColor = .secondaryLabel

// Custom spacing
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

// Apply configuration
markdownView.configuration = config
```

</details>

### Configuration Reference

The following list highlights commonly used public options. Treat [`MarkdownConfiguration`](MarkdownDisplayView/Sources/MarkdownDisplayView/MarkdownRenderElement.swift) as the complete source of truth for the current release.

<details>
<summary>Show configuration properties</summary>

#### Font Configuration

```swift
public var bodyFont: UIFont              // Body font
public var h1Font: UIFont                // H1 heading font
public var h2Font: UIFont                // H2 heading font
public var h3Font: UIFont                // H3 heading font
public var h4Font: UIFont                // H4 heading font
public var h5Font: UIFont                // H5 heading font
public var h6Font: UIFont                // H6 heading font
public var codeFont: UIFont              // Code font
public var blockquoteFont: UIFont        // Blockquote font
```

#### Color Configuration

```swift
public var textColor: UIColor                          // Text color
public var headingColor: UIColor                       // Heading color
public var linkColor: UIColor                          // Link color
public var linkUnderlineEnabled: Bool                  // Whether links display underline (default: true)
public var codeTextColor: UIColor                      // Code text color
public var codeBackgroundColor: UIColor                // Code background color
public var blockquoteTextColor: UIColor                // Blockquote text color
public var blockquoteBarColor: UIColor                 // Blockquote border color
public var tableBorderColor: UIColor                   // Table border color
public var tableHeaderBackgroundColor: UIColor         // Table header background
public var tableRowBackgroundColor: UIColor            // Table row background
public var tableAlternateRowBackgroundColor: UIColor   // Table alternate row background
public var horizontalRuleColor: UIColor                // Horizontal rule color
public var imagePlaceholderColor: UIColor              // Image placeholder color
public var footnoteColor: UIColor                      // Footnote color
public var tocTextColor: UIColor                       // TOC text color
public var detailsSummaryTextColor: UIColor            // Details summary text color
```

#### Spacing Configuration

```swift
public var paragraphSpacing: CGFloat       // Paragraph spacing
public var headingTopSpacing: CGFloat      // Space before headings
public var headingBottomSpacing: CGFloat   // Space after headings
public var paragraphTopSpacing: CGFloat    // Space before paragraphs
public var paragraphBottomSpacing: CGFloat // Space after paragraphs
public var listIndent: CGFloat             // List indentation
public var blockquoteIndent: CGFloat       // Blockquote indentation
public var imageMaxHeight: CGFloat         // Maximum image height
public var imagePlaceholderHeight: CGFloat // Image placeholder height
```

#### Line Spacing Configuration

```swift
public var lineSpacing: MarkdownLineSpacingConfiguration // Role-based line spacing config

public struct MarkdownLineSpacingConfiguration {
    public var body: CGFloat
    public var heading: CGFloat
    public var quote: CGFloat
    public var codeBlock: CGFloat
}
```

#### LaTeX Formula Configuration

```swift
public var latexFontSize: CGFloat          // LaTeX formula font size (default: 22)
public var latexAlignment: NSTextAlignment // LaTeX formula alignment (.left, .center, .right)
public var latexTextColor: UIColor         // Default formula glyph and rule color
public var latexBackgroundColor: UIColor   // LaTeX formula background color
public var latexPadding: CGFloat           // LaTeX formula padding (default: 20)
```

#### LaTeX Formula Syntax

Two formula forms are supported:

- **Inline math** — wrap in single dollars `$...$`; it flows inline inside paragraphs, headings, table cells, blockquotes, and list items:

  ```markdown
  Energy is $E=mc^2$ and momentum is $p=mv$.
  ```

- **Display math** — wrap in double dollars `$$...$$`; it renders as a full-width, centered block:

  ```markdown
  $$
  \int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
  $$
  ```

- **Fenced math** — a `math` fence renders a display formula; a `latex` fence stays source code so documentation examples are not executed.

> `$...$` inside backticks (inline code) stays literal and is never treated as math.

#### Blockquote Configuration

```swift
public var blockquoteBackgroundColor: UIColor  // Blockquote background color
public var blockquoteBarWidth: CGFloat         // Blockquote left bar width (default: 4)
public var blockquoteContentSpacing: CGFloat   // Blockquote content spacing (default: 8)
public var blockquoteContentPadding: CGFloat   // Blockquote content padding (default: 12)
```

#### Table Configuration

```swift
public var tableMinColumnWidth: CGFloat    // Table minimum column width (default: 80)
public var tableMaxColumnWidth: CGFloat    // Table maximum column width (default: 200)
public var tableRowHeight: CGFloat         // Table row height (default: 44)
public var tableCellPadding: CGFloat       // Table cell padding (default: 16)
public var tableSeparatorHeight: CGFloat   // Table separator height (default: 1)
public var autoFixMalformedTables: Bool    // Auto-fix malformed table text from streaming/LLM output (default: true)
```

#### List Configuration

```swift
public var listItemSpacing: CGFloat        // List item spacing (default: 4)
public var listMarkerMinWidth: CGFloat     // List marker minimum width (default: 20)
public var listMarkerSpacing: CGFloat      // List marker to content spacing (default: 4)
public var listTopPadding: CGFloat         // Whole-list top padding (default: 0)
public var listBottomPadding: CGFloat      // Whole-list bottom padding (default: 0)
```

#### Details (Collapsible) Configuration

```swift
public var detailsSummaryFont: UIFont          // Details summary font
public var detailsSummaryTextColor: UIColor    // Details summary text color
public var detailsSummaryMinHeight: CGFloat    // Details summary minimum height (default: 40)
public var detailsContentPadding: CGFloat      // Details content padding (default: 12)
public var detailsSpacing: CGFloat             // Details internal spacing (default: 8)
```

#### Syntax Highlighting Configuration

```swift
public var syntaxColors: SyntaxHighlightColors // Active syntax-highlighting colors; `.dark` assigns `.xcodeDark`

// SyntaxHighlightColors structure
public struct SyntaxHighlightColors {
    public var keyword: UIColor       // Keyword color
    public var string: UIColor        // String color
    public var number: UIColor        // Number color
    public var comment: UIColor       // Comment color
    public var type: UIColor          // Type color
    public var function: UIColor      // Function color
    public var property: UIColor      // Property color
    public var preprocessor: UIColor  // Preprocessor color

    public static var xcode: SyntaxHighlightColors      // Xcode light theme
    public static var xcodeDark: SyntaxHighlightColors  // Xcode dark theme
}
```

#### Streaming Haptic Feedback Configuration

```swift
public var streamingHapticFeedbackStyle: StreamingHapticFeedbackStyle  // Haptic feedback style (default: .none)
public var streamingHapticMinInterval: TimeInterval                    // Minimum interval between haptics (default: 0.05s)

// StreamingHapticFeedbackStyle enum
public enum StreamingHapticFeedbackStyle {
    case none    // No haptic feedback (default)
    case light   // Light haptic feedback
    case medium  // Medium haptic feedback
    case heavy   // Heavy haptic feedback
    case soft    // Soft haptic feedback (iOS 13+)
    case rigid   // Rigid haptic feedback (iOS 13+)
}

// Usage example
var config = MarkdownConfiguration.default
config.streamingHapticFeedbackStyle = .light  // Enable light haptic feedback
config.streamingHapticMinInterval = 0.05      // 50ms minimum interval
markdownView.configuration = config
```

</details>

## Table of Contents

<details>
<summary>Show TOC API usage</summary>

### Get Auto-Generated TOC

Markdown parsing is asynchronous. Read or present the TOC after rendering has produced a height callback, or from a later user action—not immediately after assigning `markdown`.

```swift
// Markdown content automatically parses headings to generate TOC
let tocItems = markdownView.tableOfContents

for item in tocItems {
    print("Level \(item.level): \(item.title)")
}
```

### Generate TOC View

```swift
// Automatically generate clickable TOC view
let tocView = markdownView.generateTOCView()
view.addSubview(tocView)
NSLayoutConstraint.activate([
    tocView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
    tocView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
    tocView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
])
```

### Observe or Trigger TOC Navigation

```swift
// Generated TOC entries automatically scroll after this callback returns.
markdownView.onTOCItemTap = { item in
    print("Selected TOC item: \(item.title)")
}

// Navigate manually from your own UI.
if let item = markdownView.tableOfContents.first {
    markdownView.scrollToTOCItem(item)
}
```

</details>

## Supported Markdown Syntax

| Category | Supported forms |
|----------|-----------------|
| Headings | H1–H6 with `#` through `######` |
| Text | Bold, italic, bold-italic, strikethrough, and inline code |
| Lists | Ordered, unordered, nested, and task lists |
| Links and images | Inline links, remote images, internal anchors, and tap callbacks |
| Blockquotes | Multi-line and nested quotes, including rich child blocks |
| Code | Inline and fenced blocks; 20+ highlighted languages and horizontal scrolling |
| Tables | GFM pipe tables, column alignment, and malformed-stream repair |
| Math | Inline `$…$`, display `$$…$$`, and fenced `math` / `latex` blocks |
| Document helpers | Horizontal rules, footnotes, and HTML-style `details` / `summary` sections |

The complete rendered syntax catalog lives in [`MarkdownExampleViewController.swift`](Example/ExampleForMarkdown/ExampleForMarkdown/MarkdownExampleViewController.swift).

## Complete Example

| Project | Integration | Coverage |
|---------|-------------|----------|
| [`ExampleForMarkdown`](Example/ExampleForMarkdown/) | Swift Package Manager | Syntax catalog, themes, callbacks, AI chat/streaming, history/cache demos, Video, Mermaid, and ECharts |
| [`CocoapodsMDExample`](CocoapodsMDExample/) | CocoaPods | Equivalent UIKit usage and custom-extension examples through `MarkdownDisplayKit` |

Open the SPM example with `open Example/ExampleForMarkdown/ExampleForMarkdown.xcodeproj`.

## Performance Optimization

| Strategy | Behavior |
|----------|----------|
| Background parsing | Parsing and preparation use a dedicated render queue; UIKit updates return to the main thread |
| Incremental updates | Diff/append paths update only affected content and prioritize the first screen |
| Image pipeline | Kingfisher loads asynchronously and reuses memory/disk caches |
| Cached work | Syntax regexes, prepared content, and same-width height measurements are reused |
| Streaming budgets | Ordered parsing, UI work, and typewriter playback apply bounded queues/backpressure |

## Advanced Usage

<details>
<summary>Show core view, prepared-content, cell, and streaming guidance</summary>

### Using Core View Directly (Without Scrolling)

```swift
let markdownView = MarkdownViewTextKit()
// You need to manage the scroll container yourself
```

### Reusing Prepared Content in Chat or History Cells

Persist the original Markdown as the source of truth. For stable, non-streaming messages, prepare the rendered content on a background queue and keep it in an in-memory cache keyed by message identity, Markdown content, container width, and style version:

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

`setPreparedContent(_:)` skips Markdown parsing, render-element creation, and the first height-estimation pass. Rebuild the prepared content after the Markdown, width, or configuration changes. `MarkdownPreparedContent` is intended as an in-memory render cache; store the original Markdown rather than archiving it as the durable history format.

For tens or hundreds of long documents, do not prepare the complete history eagerly. Use `UITableViewDataSourcePrefetching` to prepare only rows near the visible range, cancel obsolete work after fast scrolling or width changes, and use `NSCache` with both `countLimit` and `totalCostLimit` so prepared attributed strings can be evicted under memory pressure.

The example controllers use the normal render path for short Markdown and show a lightweight loading indicator while a cache-missed long document is prepared once, avoiding simultaneous normal parsing and cache preparation for the same content.

See [`AIChatViewController.swift`](Example/ExampleForMarkdown/ExampleForMarkdown/AIChatViewController.swift) and [`HistoryMDViewController.swift`](Example/ExampleForMarkdown/ExampleForMarkdown/HistoryMDViewController.swift) for visible-range prefetching, bounded prepared-content caches, and cached table-row estimates.

### Monitor Height Changes

```swift
let markdownView = MarkdownViewTextKit()

markdownView.onHeightChange = { newHeight in
    print("Content height changed to: \(newHeight)")
}
```

### Using Scrollable View (Recommended)

`ScrollableMarkdownViewTextKit` is the wrapper used by the quick start and the example app. It owns a `MarkdownViewTextKit`, supplies scrolling, and forwards `markdown`, `configuration`, link/image/TOC callbacks, and TOC navigation APIs. See the verified setup in [`MarkdownExampleViewController.swift`](Example/ExampleForMarkdown/ExampleForMarkdown/MarkdownExampleViewController.swift#L14).

### Real-Time Streaming Markdown (LLM/SSE)

Use the real streaming API when an AI model or SSE connection delivers text fragments over time. Call all three methods on the main thread: start the stream once, append every decoded content delta in arrival order, and end it only after the server signals completion. Pass through the original chunk boundaries instead of assembling and replaying a complete Markdown document.

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

The two `StreamingMarkdownController` demos schedule local chunks only to stand in for network callbacks. Production code should call the same three methods directly from its `URLSession`/SSE client as deltas arrive.

Recommended configuration for streaming AI chat in table/collection cells:

```swift
var config = MarkdownConfiguration.default
config.typewriterTextMode = .append
config.typewriterHeightUpdateInterval = 20
config.streamMinModuleLength = 10
config.streamingHapticFeedbackStyle = .medium
config.latexAlignment = .left
scrollableMarkdownView.markdownView.configuration = config
```

**Key Features**:
- **Smart Buffering**: Automatically buffers incomplete Markdown structures (unclosed code blocks, tables, LaTeX)
- **Plain-Text Detection**: the internal stream buffer detects content without Markdown markers
- **Faster Plain Text Streaming**: For plain text without Markdown markers, module submission can happen at `\n` boundaries instead of strictly waiting for `\n\n`
- **Safe Markdown Boundaries**: complete headings are emitted first; paragraph boundaries are used as a fallback while fenced or otherwise incomplete structures remain buffered
- **Incremental Rendering**: Renders complete modules immediately while buffering incomplete content
- **Typewriter Effect**: Smooth character-by-character animation for rendered content

</details>

## Custom Extensions

The core library supports custom extensions for app-specific Markdown syntax and rendering.

### Example Locations and Capabilities

The custom extension implementations live in the example projects and are not registered automatically by the `MarkdownDisplayView` library target. Both demos contain the same implementations:

- Swift Package example: [`Example/ExampleForMarkdown/ExampleForMarkdown`](Example/ExampleForMarkdown/ExampleForMarkdown/)
- CocoaPods example: [`CocoapodsMDExample/CocoapodsMDExample`](CocoapodsMDExample/CocoapodsMDExample/)
- Registration entry point: [`AppDelegate.swift`](Example/ExampleForMarkdown/ExampleForMarkdown/AppDelegate.swift)
- Complete Markdown usage: the “Custom Style Tests” section in [`MarkdownExampleViewController.swift`](Example/ExampleForMarkdown/ExampleForMarkdown/MarkdownExampleViewController.swift)

| Example | Extension mechanism | Syntax | Current capabilities |
|---------|---------------------|--------|----------------------|
| Video | `MarkdownCustomParser` + `MarkdownCustomViewProvider` + `MarkdownCustomActionHandler` | `[video:filename]` | Thumbnail, duration, QuickLook playback; supports `.mov`, `.mp4`, and `.m4v` |
| Mermaid | `MarkdownCodeBlockRenderer` | `` ```mermaid `` | Flowcharts, sequence diagrams, class diagrams, state diagrams, Gantt charts, and mind maps |
| ECharts | `MarkdownCustomParser` + `MarkdownCustomViewProvider` | `<echarts height="320">JSON</echarts>` | Bar, pie, line, scatter, stacked area, candlestick, histogram, graph, and heatmap examples |

Source files:

- [`MarkdownVideoExtension.swift`](Example/ExampleForMarkdown/ExampleForMarkdown/MarkdownVideoExtension.swift)
- [`MermaidRenderer.swift`](Example/ExampleForMarkdown/ExampleForMarkdown/MermaidRenderer.swift)
- [`MarkdownEChartsExtension.swift`](Example/ExampleForMarkdown/ExampleForMarkdown/MarkdownEChartsExtension.swift)

<details>
<summary>Show extension registration and syntax examples</summary>

### Video Custom Extension Example

Register the video extension in `AppDelegate`:

> `registerVideoExtension()` is defined by the demo's [`MarkdownVideoExtension.swift`](Example/ExampleForMarkdown/ExampleForMarkdown/MarkdownVideoExtension.swift); copy that implementation into your app before calling it.

The snippet below uses the Swift Package Manager module name; CocoaPods apps should use `import MarkdownDisplayKit`.

```swift
import MarkdownDisplayView

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    // Register video extension
    MarkdownCustomExtensionManager.shared.registerVideoExtension()
    return true
}
```

**Syntax**: `[video:filename]`

```markdown
## Video Demo

[video:video]

Supported formats: .mov, .mp4, .m4v
```

The referenced file must exist in the app bundle. The checked-in demo includes `video.mov`, so `[video:video]` works as written.

**Features**:
- Auto-generates video thumbnail
- Displays video duration
- Click to play with QuickLook

### Code Block Renderers

In addition to inline syntax extensions, you can also create custom code block renderers for specific languages:

#### Mermaid Diagram Renderer Example

The complete, runnable `WKWebView` implementation is [`MermaidRenderer.swift`](Example/ExampleForMarkdown/ExampleForMarkdown/MermaidRenderer.swift). It implements `MarkdownCodeBlockRenderer`, calculates the diagram size, loads Mermaid.js, and reports rendered height changes back to the Markdown view.

#### Register Code Block Renderer

```swift
let manager = MarkdownCustomExtensionManager.shared
manager.register(codeBlockRenderer: MermaidRenderer())
```

The demo also exposes `registerMermaidRenderer()` as a convenience method in that same source file; it is not part of the SDK target.

**Supported Diagram Types** (via Mermaid.js):
- Flowchart (flowchart/graph)
- Sequence Diagram (sequenceDiagram)
- Class Diagram (classDiagram)
- State Diagram (stateDiagram)
- Gantt Chart (gantt)
- Mind Map (mindmap)

### ECharts Custom Tag Example

The ECharts example uses an HTML-style tag, but it is still recognized by `MarkdownCustomParser` and rendered by a `MarkdownCustomViewProvider` that returns a `WKWebView`. It does not enable general-purpose HTML or arbitrary `<script>` rendering.

Register it in `AppDelegate`:

> `registerEChartsExtension()` is defined by the demo's [`MarkdownEChartsExtension.swift`](Example/ExampleForMarkdown/ExampleForMarkdown/MarkdownEChartsExtension.swift); copy that implementation into your app before calling it.

```swift
MarkdownCustomExtensionManager.shared.registerEChartsExtension()
```

Pass an ECharts `option` as pure JSON:

```markdown
<echarts height="320">
{
  "xAxis": { "type": "category", "data": ["Mon", "Tue", "Wed"] },
  "yAxis": { "type": "value" },
  "series": [{ "type": "bar", "data": [120, 200, 150] }]
}
</echarts>
```

`height` is optional and defaults to 320pt; the example clamps it to 220–640pt. The configuration must be a JSON object and cannot contain JavaScript functions. Invalid JSON, script loading failures, and rendering failures produce a visible error message. The current demos cover:

- Bar, pie, line, and scatter charts
- Stacked area, candlestick, and histogram charts
- Graph and heatmap charts

The ECharts and Mermaid examples load their scripts from a CDN, so the first render requires network access. For fully offline products, bundle a fixed JavaScript version with the app and update the corresponding demo renderer to load the local resource.

</details>

## Troubleshooting

| Symptom | Resolution |
|---------|------------|
| `Cannot find UIKit` from macOS `swift build` | The package is iOS-only; build with an iOS Simulator or device destination in Xcode |
| A Markdown image does not load | Verify the URL is reachable and uses HTTPS; if HTTP is unavoidable, add only the required domain-specific ATS exception |

## Demo Themes and Block Appearance (1.9.9)

The `ExampleForMarkdown` app includes four Demo-only themes:

| Theme | Character | Interface style |
|-------|-----------|-----------------|
| Parchment | Editorial | Light |
| Sage | Calm | Light |
| Midnight | Code | Dark |
| Plum | Art | Dark |

Selecting a theme stores the choice in `UserDefaults` and reuses the same configuration in the Markdown preview, AI Chat/history, long-history, TableView Streaming, and smart-streaming examples.

Open **Theme Gallery** from the example app, select a theme card, and then enter any of the pages above to inspect the result. Theme persistence is implemented only by the Demo's `MarkdownDemoThemeStore`; it is not a global SDK singleton. Pages read the selected theme when they are created, so reopen an already visible page after changing the theme.

The complete theme definitions are available in [`MarkdownThemeGalleryViewController.swift`](Example/ExampleForMarkdown/ExampleForMarkdown/MarkdownThemeGalleryViewController.swift). Product apps can use the same pattern: keep the selected theme in app state, create one complete `MarkdownConfiguration`, and assign it to every Markdown view that should share the theme.

### Build a Theme

Colors and block surfaces can be configured independently. `MarkdownBlockAppearance` draws its corner radius and border with `CALayer`; it does not change constraints, padding, measured height, or the scroll range.

<details>
<summary>Show the complete theme configuration</summary>

```swift
var configuration = MarkdownConfiguration.default

// Text and surface colors
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

// Formula glyphs/rules and formula surface
configuration.latexTextColor = .label
configuration.latexBackgroundColor = .secondarySystemBackground

// Visual-only block appearance
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
    cornerRadius: 14 // Image borders remain opt-in.
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

`latexTextColor` is the default color for formula glyphs and fraction/radical rules. An explicit LaTeX `\color{...}` command still takes precedence. Image themes default to rounded corners without a border; set `borderWidth` and `borderColor` only when a product specifically needs an image outline.

### Keep Prepared Content in Sync

<details>
<summary>Show prepared-content theme synchronization</summary>

When a screen uses `MarkdownRenderer.prepare(_:)`, give the renderer and the destination view the same configuration. This prevents cached/prepared content from retaining colors from another theme.

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

## Changelog

### 2.1.8 (2026-08-20)

- 🪟 **Viewport Virtualization for Static Documents** - Long static documents no longer create every root text layer up front. Lightweight geometry slots, bounded TextKit host reuse, accurate attachment measurement, and viewport-aware lifecycle hooks keep only the visible views' backing stores resident and release offscreen ones as you scroll, so scrolling should no longer accumulate memory (real-device plateau verification still pending). Streaming and reusable-cell rendering keep their existing paths.
- 🧱 **Bounded Backing-Store Budget for Complex Blocks** - The viewport virtualization now also covers LaTeX formulas, tables, default code blocks, and safe list/quote composites: offscreen complex views' CALayer backing stores are released while measured geometry and horizontal interaction state are preserved. Custom renderers, details blocks, and lists with dynamically sized images retain view identity (state cannot yet be reconstructed generically).
- 📉 **Redundant Full-Text Copies Removed** - Real streaming no longer keeps a duplicate full-text string; the stream buffer is the single source of the accumulated text and is released when streaming ends.
- 🧹 **Complete deinit Cleanup** - The view now invalidates its run-loop timers on dealloc (the typewriter engine's display link is released with it), cancels pending work items, clears pending streaming queues, and cancels in-flight subscriptions, so closing a page no longer leaves timers spinning or queues holding unplayed content.
- 🧱 **Optional Diff-Baseline Release** - `retainsDiffBaseline` lets static one-shot renders (e.g. `setPreparedContent`) skip retaining the full element list, avoiding a duplicate attributed-text copy; static demo pages opt in.
- ⚡ **Faster Block LaTeX Rendering** - Block formulas are created directly from the parsed render result, dropping the redundant per-formula TextKit 2 layout pipeline.
- 🐛 **AI Chat URLSession Retain Cycle Fixed** - The chat stream session now invalidates its `URLSession` on completion and in `deinit`, so each finished chat no longer leaks a session pair.

### 2.1.2 (2026-08-19)

- ➗ **Inline LaTeX in Every Inline Context** - Inline `$...$` now renders as an inline attachment inside paragraphs, headings, table cells, blockquotes, and list items; display `$$...$$` stays block-level. Oversized inline formulas scale to fit the line width instead of being clipped.
- 🛡 **Inline Code Is Not Math** - `$...$` inside backticks stays literal, and a fenced `latex` block is kept as source code (only `math` renders as a formula), so documentation examples are no longer misread as math. Added `\dfrac` / `\tfrac` fraction aliases.
- 📐 **CommonMark Fenced-Code Detection** - The smart-stream buffer now follows CommonMark fence rules: ≤3 leading spaces, ≥3 backticks or tildes, and the closing fence must match the opening character and length (tilde fences included).
- 📊 **Table & Code Layout Configs Now Effective** - `tableMinColumnWidth`, `tableMaxColumnWidth`, `tableRowHeight`, `tableCellPadding`, `tableSeparatorHeight`, and `codeBlockPadding` now actually take effect (previously hardcoded), and a new `tableCellVerticalPadding` controls vertical cell padding. `headingSpacing` is deprecated in favor of `headingTopSpacing` / `headingBottomSpacing`.
- 🖼 **Inline Image Ordering** - Inline images keep their position inside a paragraph instead of being hoisted before the surrounding text.
- 🧱 **Details Expand & Snapshot-Safe Rendering** - Details expand/collapse no longer drops content updates, and complete-document rendering stays correct while keeping snapshot-safe layout.

### 2.1.1 (2026-08-18)

- 📏 **First-Pass Cell Height Accuracy** - Added `preferredMeasurementWidth` so hosts can supply the final content width before the first layout pass. Cell height is now correct on the first measurement instead of being applied in two passes (grow, then re-layout).
- ✨ **Flicker-Free Append Typewriter Wrapping** - The append typewriter now remeasures height every frame instead of every N characters. Soft-wrapped new lines get their height immediately, eliminating the flash at wrap boundaries. Host notifications remain throttled by actual height change; `typewriterHeightUpdateInterval` is deprecated and no longer affects rendering.
- 📏 **Incremental Streaming Height Threshold** - The real-streaming incremental path now notifies the host on any growth above 0.5pt (down from 9pt), so the cell's required layout height follows the content instead of clipping text until it crosses a threshold.
- 🧱 **Snapshot Width Yields to Host Layout** - List wrapper, blockquote, and thematic-break width constraints now use 999 priority, so pre-layout snapshot widths give way to the host's real width and avoid unsatisfiable-constraint recovery layouts.
- 🐛 **Zero-Height Feedback Loop Fixed** - After `resetForReuse()`, transient zero heights are suppressed until real content is rendered, breaking the render → height-callback → batch-update → cell-reuse loop.
- 🧱 **Atomic Quote/Details Text in Append Mode** - Quote and details descendants are now laid out at their final height before the whole block is revealed, keeping their text visible during append typewriter playback.
- 🧪 **Regression Coverage** - Added tests for sub-9pt streaming growth reporting, block width yielding to host layout, and atomic quote text visibility during append streaming.
- 🖥 **Example: HTML/JS Code Preview** - Added an HTML/JS code-block preview renderer and demo sample to the example app.

### 2.0.0 (2026-08-13)

- 🤖 **AI Chat Web Search & Tool Calls** - The AI Chat examples now call DeepSeek's function-calling API with a built-in `web_search` tool. When the model needs information beyond its training data it requests a search, the demo performs a real web search (Bing by default; Tavily, DuckDuckGo, and Bocha also supported), feeds the results back, and streams the final answer. Search failures degrade gracefully, and multi-turn tool-call context (`reasoning_content`) is persisted across turns.
- 🗣 **AI Chat Copy & Read-Aloud Footer** - Each chat cell now offers footer actions to copy the full message and to read it aloud or stop playback via SpeechKit (`AVSpeechSynthesizer`).
- 🧠 **Thinking Mode Parameters** - The AI Chat examples forward `thinking` and `reasoning_effort` from the local configuration and correctly pass `reasoning_content` back when tools are used.
- 📊 **Faster Table Horizontal Scrolling** - Table cells no longer rebuild a full attributed-string copy on every reuse, the collection layout returns only the visible rows/columns instead of filtering every cell, and horizontal scrolling is direction-locked to avoid gesture conflicts.
- 🐛 **Fixed Self-Sizing Constraint Conflicts** - List wrapper, thematic break, and blockquote width constraints now use a lower priority, eliminating unsatisfiable-constraint warnings in table-based chat/history cells.
- 🐛 **Fixed Re-render Feedback Loop** - Assigning identical Markdown or prepared content no longer triggers a full re-render, and cell reuse no longer resets the last reported height, removing the render → height-callback → batch-update → cell-reuse loop in streaming and history screens.

### 1.9.9 (2026-08-06)

- 🎨 **Four Demo Themes and Theme Gallery** - Added Parchment, Sage, Midnight, and Plum theme previews, with Demo-only `UserDefaults` persistence and consistent selection across the Markdown preview, AI Chat/history, long-history, TableView Streaming, and smart-streaming examples.
- 🧱 **Configurable Block Appearance** - Added corner-radius and border configuration for code blocks, blockquotes, tables, images, LaTeX, and details blocks. These `CALayer`-only settings do not participate in height measurement or change the scroll range.
- ➗ **Theme-Aware Formula Rendering** - Added `latexTextColor` so formula glyphs and drawing rules follow the selected theme while explicit LaTeX `\color{...}` values continue to take precedence.
- 🔄 **Consistent Prepared-Content Styling** - Demo screens now pass the selected configuration to both `MarkdownRenderer` and their Markdown views, preventing cached chat/history content from using stale theme colors.
- 🖼 **Cleaner Image Defaults** - Demo themes keep image rounding but leave image borders disabled by default; borders remain available as an opt-in appearance setting.

### 1.9.8 (2026-08-04)

- 🚀 **Backpressured Smart-Streaming Pipeline** - SmartBuffer now releases safe completed prefixes incrementally, parses modules serially off the main thread, and applies view creation under per-frame and Typewriter high/low-watermark budgets. Input order, UI order, and drain completion remain deterministic even when parsing outruns playback.
- ⚡ **Display-Link Typewriter Scheduling** - Replaced recursive delayed ticks with a 30 FPS `CADisplayLink` timeline. Punctuation delays are precomputed in UTF-16 coordinates, pending work uses an O(1) FIFO head, and a catch-up frame performs at most one reveal/layout callback.
- 📏 **Incremental Height Cache** - Streaming height now grows from known root visibility and text deltas instead of repeatedly fitting the complete `UIStackView`. Same-width intrinsic-size reads are cached, height notifications are coalesced, and structural changes still fall back to full reconciliation.
- ✨ **Stable Rendering Without Repaint Flashes** - TextKit views only invalidate drawing when their real bounds change. Smart-stream table updates are serialized/coalesced with a guaranteed final flush, preventing overlapping self-sizing batches from repainting already displayed content.
- 🧱 **Bounded Rich-Block Layout Work** - Tables reuse stable geometry, quotes are revealed as atomic blocks, and layout-driven height invalidation only runs after an actual width change. Rich Markdown no longer amplifies full-document layout work as the stream grows.
- 🔒 **Deterministic Module and Extension Handling** - Complete modules preserve global ordering and document-wide heading IDs. Fenced code and opaque custom blocks remain intact across chunk boundaries, and custom streaming tags stay explicitly opt-in through `streamingBlockTagName`.
- 🧹 **Smart-Streaming API and Demo Cleanup** - Smart-stream usage is consolidated around `beginRealStreaming()`, `appendStreamData(_:)`, and `endRealStreaming(completion:)`; the pre-split `appendBlock` path and unused streaming demo controls were removed.
- 📊 **Opt-In Performance Diagnostics and Regression Coverage** - Added `[MDPERF]` aggregate diagnostics via `MD_STREAM_PERF_LOG=1` / `MD_STREAM_PERF_ONLY=1`, plus coverage for Unicode punctuation, emoji boundaries, FIFO ordering, backpressure, redraw deduplication, height caching, and final drain behavior. The merged baseline passed 68 iOS Simulator tests and SwiftPM/CocoaPods example builds.

<details>
<summary>Show release notes for 1.8.9 and earlier</summary>

### 1.8.9 (2026-07-31)

- 🔒 **Thread-Safe Custom Extension Registry** - Parser, view-provider, action-handler, and code-block-renderer registration and lookup are now synchronized. Third-party parser callbacks execute outside the registry lock to avoid re-entrant deadlocks.
- 🖼 **Unified Kingfisher Image Pipeline** - Removed the redundant in-house memory/disk image cache and routed loading, caching, request cancellation, and cache hits through Kingfisher.
- ⚡ **Single-Pass LaTeX Rendering** - A formula is parsed once into a reusable render result shared by measurement, attachment layout, and view creation, eliminating duplicate parse work without introducing artificial IDs.
- 🧩 **Modularized Markdown Renderer** - Split the monolithic `MarkdownDisplayView.swift` into focused `MarkdownViewTextKit` extension files while preserving the public API and existing rendering behavior.

### 1.8.6 (2026-07-31)

- 🐛 **Fixed Initial Details-Block Whitespace** - Long ordered lists no longer leave a large blank area before the following heading or collapsible `<details>` block when a Markdown screen first appears. The list wrapper is now constrained to its actual content height instead of being allowed to stretch vertically.
- 📏 **Synchronized Deferred Layout Without User Interaction** - After off-screen elements are appended, the Markdown view now propagates its final height through the outer scroll view's `contentLayoutGuide` and `contentSize`; users no longer need to swipe once to correct the layout.
- 📍 **Preserved Scroll Position During Append-Only Rendering** - Deferred elements appended below the current viewport no longer add their entire height to `contentOffset`, preventing incorrect jumps and stale-offset clamping during the first render.

### 1.8.5 (2026-07-30)

- ⚡ **Incremental Stream Buffer Scanning** - `MarkdownStreamBuffer.append()` now scans only the uncommitted tail instead of rescanning the full accumulated text, eliminating O(n²) growth; measured 1.6x-3.8x speedup on long streaming input. Added chunk-boundary-independence differential tests to lock the behavior invariant.
- ⚡ **TextKit 2 Incremental Layout & Height Measurement** - Typewriter append no longer replaces the whole attributed string per character; edits happen incrementally within an editing transaction. Height measurement now uses `usageBoundsForTextContainer`, removing the O(n²) bottleneck during streaming append.
- ⚡ **LaTeX Formula Parse Deduplication** - Reduced repeated parsing of a single formula from 6 times to 1; `LatexMathView` now short-circuits when content is unchanged.
- 🐛 **Fixed Three Rendering Regressions Surfaced After Code Review Merge** - Restored correct container width semantics, fixed content truncation caused by `draw(_:)` dirty-rect clipping, and added a fade-in transition when off-screen placeholders are replaced to avoid flicker.
- 🐛 **Eliminated Background-Thread UIKit Access** - Container width is now snapshotted on the main thread before background parsing begins, removing a potential crash risk.
- 🐛 **Streaming Auto-Scroll Improvements** - Added user takeover detection and throttling so scrolling back to read history is no longer forced back to the bottom.
- ⚡ **Typewriter Watchdog Uses a Persistent Timer** - Avoids rebuilding a Timer on every step, and stays reliable during scrolling via `.common` RunLoop mode.
- ⚡ **Regex Cache Coverage** - Details block and code-highlighting regex matching now consistently use the existing `cachedRegex`.
- 🧹 **Code Cleanup** - Removed dead incremental-parsing code with zero call sites across the repo; gated 251 debug log statements behind `#if DEBUG` to reduce release-build logging overhead.
- ✨ **Enhanced AI Chat Examples** - CocoaPods/SPM examples now include chat history support with refined interaction details.

### 1.8.1 (2026-07-15)

- 📏 **Append Typewriter Height Stability** - Character reveal is now separated from height remeasurement. Layout callbacks fire only when height actually changes, reducing row jitter during streaming playback.
- 🧱 **No Pre-Reveal Blank Height** - Append mode discards precalculated final height before typing starts, so cells no longer flash a large empty area, and height only grows with visible text.
- 🔒 **Height Floor During Playback** - While append typewriter is active, height is not allowed to shrink on transient width corrections, preventing bubble bounce; the floor is released after playback finishes or the engine stops so wider reflows can still settle correctly.
- 🧪 **Streaming Layout Tests** - Added coverage for reveal/height decoupling, pre-playback height reset, and height-floor release on finish/stop.

### 1.8.0 (2026-07-14)

- 🌊 **Stable Real-Streaming Rendering** - Starting real streaming now cancels and invalidates pending regular renders, preventing stale parse results from replacing the active typewriter UI.
- 🧱 **Atomic Block Reveal** - Tables, code blocks, images, LaTeX, details, thematic breaks, and custom views are revealed as complete blocks with their final height instead of expanding from a temporary `1pt` placeholder.
- 📜 **Chat Auto-Follow and Row-Height Fixes** - The SPM and CocoaPods AI chat examples now coalesce row-height updates, keep following the streaming message after layout changes, and pause auto-scroll while the user browses older messages.
- ✨ **Reduced Streaming Cell Flicker** - Offscreen deltas no longer reload cells repeatedly, reused streaming cells resume from accumulated content, and the final state waits for the typewriter queue to finish before switching to static rendering.

### 1.7.8 (2026-05-26)

- 🖼 **Kingfisher Image Loading** - Switched Markdown image loading and caching to Kingfisher 8.9.0 in `ImageView.swift`.
- 📦 **Dependency Alignment** - Added Kingfisher to both `Package.swift` and `MarkdownDisplayKit.podspec`, so SPM and CocoaPods resolve the same image library.
- 🧪 **Example Update** - Updated `ExampleForMarkdown` and `CocoapodsMDExample` image views to use Kingfisher-based loading.

### 1.7.5 (2026-05-15)

- 🚀 **Prepared Content Rendering** - Added `MarkdownRenderer.prepare(_:)` and `MarkdownViewTextKit.setPreparedContent(_:)` so apps can pre-parse long Markdown off the main display path and reuse the generated render elements.
- 📏 **Precomputed Height Fast Path** - Prepared content carries estimated element heights, allowing text/heading views to skip expensive first-pass TextKit height calculation when the width is known.
- 🧪 **History Markdown Example Optimization** - `CocoapodsMDExample` now pre-renders historical long Markdown messages in the background and uses cached row heights to reduce first-scroll stutter.
- 🐛 **History Row Blank-Space Fix** - Removed the oversized initial row-height placeholder and fixed callback ordering so measured content height replaces estimates correctly.

### 1.7.4 (2026-04-10)

- 📏 **Height Measurement Stabilization** - Hardened `notifyHeightChange` with width fallback, frame-height fallback, and transient-zero suppression to avoid `0 ↔ actual height` jumps during initial layout or rapid updates.
- 🌊 **Paragraph-Level Streaming Fallback** - Real streaming now emits single-heading or heading-less Markdown by paragraph boundaries when heading-based segmentation is unavailable, while skipping fenced code blocks.
- 📐 **Whole-List Top/Bottom Padding** - Added `listTopPadding` and `listBottomPadding` so the entire list wrapper can apply configurable top/bottom spacing without changing per-item layout.

### 1.7.2 (2026-04-04)

- ➕ **`isPlainText()` Detection** - Added `isPlainText()` in `MarkdownStreamBuffer` to identify non-Markdown content.
- ⚡ **Faster Plain-Text Output** - For plain text without Markdown markers, modules can now be submitted at `\n` boundaries instead of requiring `\n\n`, enabling faster typewriter output.
- ✅ **Markdown Flow Unchanged** - Markdown content behavior is unchanged and still waits for `\n\n` paragraph boundaries.

### 1.7.1 (2026-04-03)

- 🐛 **Ordered List Height Consistency Fix** - Fixed an issue where the first ordered-list item could be stretched taller than following items in some stack/reuse layouts.
- 🧱 **List Layout Constraint Hardening** - Adjusted list wrapper constraints (`bottom <=`) and strengthened vertical hugging/compression priorities to prevent extra height from being absorbed by the first item.
- 🧹 **List Content Normalization** - Added normalization/cleanup for invisible list text nodes (leading/trailing newlines, zero-width/control whitespace) to avoid phantom height.

### 1.7.0 (2026-04-03)

- 📊 **Markdown Table Column Alignment** - Added support for table alignment syntax (`:---`, `:---:`, `---:`) and applied alignment per column.
- 🛠 **Malformed Table Auto-Fix** - Added `autoFixMalformedTables` (default: `true`) to normalize common broken table output (isolated `|`, accidental blank lines inside table blocks).
- ✍️ **Configurable Line Spacing** - Added `lineSpacing` configuration for `body`, `heading`, `quote`, `codeBlock`, replacing fixed line spacing constants.
- 🔗 **Table Link Tap Callback** - Table cells keep using `UILabel` for better scrolling performance; link tap now routes through table cell selection and triggers existing `onLinkTap`.
- 🐛 **Touch Routing Fix** - Fixed gesture conflict where outer TextKit tap handling could swallow table attachment touches.
- ⚠️ **Configuration Cleanup** - Removed table-level alignment override config; table text alignment now follows Markdown table syntax (fallback: left).

### 1.6.9 (2026-03-17)

- 🔗 **Link Underline Control** - Added `linkUnderlineEnabled` configuration option to control whether links display underlines
  - New property `linkUnderlineEnabled: Bool` in `MarkdownConfiguration` (default: `true`)
  - Affects all link types: inline Markdown links (`[text](url)`) and TOC navigation links
  - **Root cause fix**: Implemented `NSTextLayoutManagerDelegate.renderingAttributesForLink(_:at:defaultAttributes:)` to properly intercept TextKit 2's built-in link rendering pipeline, which previously ignored `NSAttributedString` underline attributes entirely

### 1.6.8 (2026-02-06)

- 📜 **Code Block Horizontal Scrolling** - Code blocks now support horizontal scrolling to view complete long code lines
  - Implemented using `NSTextAttachmentViewProvider` pattern, consistent with LaTeX formula and table rendering architecture
  - New `CodeBlockAttachment` and `CodeBlockAttachmentViewProvider` classes for code block rendering
  - Code text no longer wraps; users can scroll horizontally to view full code content
  - Maintains original syntax highlighting, background color, and corner radius styling

### 1.6.2 (2026-02-05)

- 📳 **Haptic Feedback Timing Optimization** - Haptic feedback now syncs precisely with TypewriterEngine output rhythm
  - Text haptics: Only triggers when `revealCharacter` actually displays new characters
  - Block haptics: Triggers when block element animation completes (image, LaTeX, etc.)
  - Removed unnecessary haptics for container views (`.show`) and small elements (`.label`)
  - Haptic feedback no longer triggers on data arrival, but on actual content display

### 1.6.1 (2026-02-02)

- 📳 **Streaming Haptic Feedback** - Added haptic feedback support during streaming output for enhanced user experience
  - New `StreamingHapticFeedbackStyle` enum with options: `.none`, `.light`, `.medium`, `.heavy`, `.soft`, `.rigid`
  - New configuration options: `streamingHapticFeedbackStyle` (feedback intensity) and `streamingHapticMinInterval` (minimum interval)
  - Feedback follows content revealed by the real streaming pipeline (`appendStreamData`)

### 1.6.0 (2026-01-30)

- 🎨 **Comprehensive Configuration Options** - Added extensive customization for all Markdown elements:
  - **LaTeX Formula**: `latexFontSize`, `latexAlignment` (left/center/right), `latexBackgroundColor`, `latexPadding`
  - **Blockquote**: `blockquoteBackgroundColor`, `blockquoteBarWidth`, `blockquoteContentSpacing`, `blockquoteContentPadding`
  - **Table**: `tableMinColumnWidth`, `tableMaxColumnWidth`, `tableRowHeight`, `tableCellPadding`, `tableSeparatorHeight`
  - **List**: `listItemSpacing`, `listMarkerMinWidth`, `listMarkerSpacing`
  - **Details**: `detailsSummaryFont`, `detailsSummaryTextColor`, `detailsSummaryMinHeight`, `detailsContentPadding`, `detailsSpacing`
  - **Syntax Highlighting**: `syntaxColors`, `syntaxColorsDark` with `SyntaxHighlightColors` struct (keyword, string, number, comment, type, function, property, preprocessor)
  - **TOC**: `tocTextColor`
- 🐛 **Bug Fix** - `tableRowBackgroundColor` now properly applied to table rows
- 📝 **Documentation** - Updated README with complete configuration options

### 1.5.9 (2026-01-26)

- 🚀 **Typewriter Append** - Add `.append` mode with throttled height updates to reduce layout jumps during cell streaming
- ⚙️ **Streaming Config** - Expose `typewriterTextMode`, `typewriterHeightUpdateInterval`, `streamMinModuleLength`
- 🧹 **Memory Cleanup** - Add cache clearing helpers and Mermaid WebView cleanup to reduce retained memory
- 🧪 **Example Update** - AI chat stream uses safer LaTeX normalization (code regions ignored) and recommended config

### 1.5.8 (2026-01-23)

- 📝 **Docs Update** - Refresh README content
- 🐛 **SPM Fix** - Fix simulator build error in Swift Package Manager example project

### 1.5.2 (2026-01-08)

- 🐛 **Crash Fix** - Serialize `swift-markdown` parsing to avoid `cmark_parser_attach_syntax_extension` race crash in concurrent renders
- 🧹 **Reuse Safety** - Add `resetForReuse()` to clear internal caches/state for `UITableViewCell` reuse scenarios
- 🧪 **Example Update** - Add crash reproduction screen and incremental row insert demo for table view usage

### 1.5.1 (2026-01-07)

- 🐛 **Bug Fix** - Fixed potential crash when processing Unicode characters (emoji, CJK characters) in streaming mode
  - `MarkdownStreamBuffer.extractModule`: Use safe string index with `limitedBy` to prevent out-of-bounds crash
  - `TypewriterEngine.calculateDelay`: Use safe string index to prevent crash when calculating delay for special characters

### 1.5.0 (2026-01-04)

- 🚀 **Real Streaming Support** - New `MarkdownStreamBuffer` for intelligent real-time streaming from network/LLM APIs
  - Smart module detection: automatically detects complete Markdown blocks (headings, code blocks, tables, LaTeX)
  - Handles incomplete structures: waits for closing tags before rendering (e.g., unclosed ``` or $$)
  - Incremental rendering: renders complete modules immediately while buffering incomplete content
- 💫 **Smart Waiting Indicator** - In real streaming mode, automatically shows waiting animation when TypewriterEngine queue is empty and no network data arrives
- 🏗️ **Code Refactoring** - Extracted `MarkdownTextViewTK2`, `MarkdownStreamBuffer`, and `TypewriterEngine` into separate files for better maintainability
- 🐛 **Streaming Fixes** - Multiple fixes for real streaming mode stability and rendering issues

### 1.4.1 (2026-01-02)

- 🐛 **Bug Fix** - Fixed code blocks not rendering properly in real streaming mode when content arrives in multiple chunks

### 1.4.0 (2025-12-31)

- 🚀 **Instant Loading** - Significantly optimized loading speed with ultra-fast first screen rendering
- ⚡ **CPU Optimization** - Streaming mode with nested style rendering now uses much less CPU (iPhone 17 Pro simulator peak < 56%, average 30%)
- 🔌 **Enhanced Custom Extensions** - New `MarkdownCodeBlockRenderer` protocol for custom code block rendering (e.g., Mermaid diagrams)
- 🎨 **Mermaid Support** - Example project now includes Mermaid diagram renderer supporting flowcharts, mind maps, and more

### 1.0.0 (2025-12-15)

- 🎉 Initial release
- ✅ Full Markdown syntax support
- ✅ 20+ language code highlighting
- ✅ Automatic table of contents generation
- ✅ Dark mode support
- ✅ High-performance asynchronous rendering

</details>

## Contributing

Issues and Pull Requests are welcome!

Before submitting a PR, please ensure:

- Code compiles successfully
- Follows existing code style
- Adds necessary tests

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Author

MarkdownDisplayView is created and maintained by [@zjc19891106](https://github.com/zjc19891106).
If this library saved you time, consider supporting me. Thanks to everyone who has supported me so far.

- Support the author
- WeChat
  ![](Support/wechat.jpg)
- AliPay
  ![](Support/alipay.jpg)
- Paypal

  ![](Support/paypal.png)

## Acknowledgments

- [swift-markdown](https://github.com/swiftlang/swift-markdown) - Markdown parsing library
- [Kingfisher](https://github.com/onevcat/Kingfisher) - Image loading and caching library
- [KaTeX](https://github.com/KaTeX/KaTeX) - Math formula rendering fonts
- Apple TextKit 2 - High-performance text rendering framework
- Gemini3 Pro&Claude&Grok&GPT
- All contributors and users
- All friends who provided suggestions and feedback

## Contact

If you have questions or suggestions, please contact via:

- Submit [GitHub Issue](https://github.com/zjc19891106/MarkdownDisplayView/issues)
- Send email to: 984065974@qq.com or luomobancheng@gmail.com

- QQ Group
![QQ Group](./Communication/qq.jpeg)

- Telegram
![Telegram](./Communication/telegram.jpeg)

- Discord
![Discord](./Communication/discord.jpeg)

---

**If you find this project helpful, please give it a Star ⭐️ for support!
