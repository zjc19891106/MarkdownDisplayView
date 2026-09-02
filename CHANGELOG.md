# Changelog / 更新日志

All notable changes to this project will be documented in this file.

本项目的所有重要更改都将记录在此文件中。

## [2.1.8] - 2026-08-20

### Added / 新增
- 🪟 **Viewport Virtualization for Static Documents / 静态文档视口虚拟化** - Long static documents no longer create every root text layer up front; keep only visible views' backing stores resident and release offscreen ones on scroll / 长静态文档不再提前创建所有根文本视图，只保留可见视图的 backing store，滚动时释放离屏视图
- 🧱 **Bounded Backing-Store Budget for Complex Blocks / 复杂块的背衬存储预算有界化** - Virtualization covers LaTeX formulas, tables, default code blocks, and list/quote composites / 视口虚拟化扩展到 LaTeX 公式、表格、代码块与列表/引用组合
- 🧱 **Optional Diff-Baseline Release / 可选释放 diff 基线** - `retainsDiffBaseline` allows static one-shot renders to skip retaining full element list / 允许静态一次性渲染不再保留全量元素列表

### Changed / 变更
- 📉 **Redundant Full-Text Copies Removed / 去除冗余全文拷贝** - Stream buffer is the single source of accumulated text / 以流式缓存为全文唯一来源并在流结束后释放
- ⚡ **Faster Block LaTeX Rendering / 块级 LaTeX 渲染提速** - Block formulas created directly from parsed result / 块级公式直接用解析结果创建视图，去掉冗余布局管线

### Fixed / 修复
- 🧹 **Complete deinit Cleanup / deinit 清理补全** - Invalidate run-loop timers, cancel pending work items, clear streaming queues on dealloc / 视图析构时停掉 RunLoop 定时器、取消待执行任务、清空待处理队列
- 🐛 **AI Chat URLSession Retain Cycle Fixed / 修复 AI Chat URLSession 保留环** - Invalidate `URLSession` on completion and deinit / 聊天流会话在结束与析构时 invalidate 其 `URLSession`

## [2.1.2] - 2026-08-19

### Added / 新增
- ➗ **Inline LaTeX in Every Inline Context / 行内 LaTeX 全面支持** - Inline `$...$` renders as an inline attachment in paragraphs, headings, table cells, blockquotes, and list items / 行内 `$...$` 在段落、标题、表格单元格、引用块和列表项中内联渲染
- 🛡 **Inline Code Is Not Math / 行内代码不再被误判为公式** - `$...$` inside backticks stays literal; added `\dfrac` / `\tfrac` fraction aliases / 反引号内 `$...$` 保持字面量，新增 `\dfrac` / `\tfrac` 分数别名
- 📐 **CommonMark Fenced-Code Detection / CommonMark 围栏代码块识别** - Follows CommonMark fence rules (≤3 leading spaces, ≥3 backticks or tildes) / 遵循 CommonMark 围栏规则
- 📊 **Table & Code Layout Configs Effective / 表格与代码布局配置生效** - `tableMinColumnWidth`, `tableMaxColumnWidth`, `tableRowHeight`, `tableCellPadding`, `tableSeparatorHeight`, `codeBlockPadding`, `tableCellVerticalPadding` / 表格与代码块布局配置真正生效

### Fixed / 修复
- 🖼 **Inline Image Ordering / 行内图片顺序** - Inline images keep their position inside paragraphs / 行内图片保持其在段落中的位置，不再被提前
- 🧱 **Details Expand & Snapshot-Safe Rendering / 折叠块展开与快照安全渲染** - Details expand/collapse keeps correct content / 折叠块展开/收起不再丢内容更新

## [2.1.1] - 2026-08-18

### Added / 新增
- 📏 **First-Pass Cell Height Accuracy / 首次测高即准确** - Added `preferredMeasurementWidth` for one-pass accurate height / 新增 `preferredMeasurementWidth` 实现单趟准确测高
- 🖥 **Example: HTML/JS Code Preview / 示例：HTML/JS 代码预览** - Added HTML/JS code block preview renderer to demo / 示例 App 新增 HTML/JS 代码块预览渲染器

### Changed / 变更
- ✨ **Flicker-Free Append Typewriter Wrapping / Append 打字机折行不再闪烁** - Remeasures height every frame / Append 打字机改为每帧测高，消除折行边界闪烁
- 📏 **Incremental Streaming Height Threshold / 流式增量高度阈值下调** - Notifies host on any growth >0.5pt (down from 9pt) / 任意超过 0.5pt 的增长都上报宿主

### Fixed / 修复
- 🧱 **Snapshot Width Yields to Host Layout / 快照宽度让位于宿主布局** - Width constraints use 999 priority to avoid conflict / 宽度约束改为 999 优先级
- 🐛 **Zero-Height Feedback Loop Fixed / 修复 0 高度反馈环** - Suppresses transient zero height after `resetForReuse()` / `resetForReuse()` 后抑制空内容阶段 0 高度上报
- 🧱 **Atomic Quote/Details Text in Append Mode / Append 模式下原子引用/详情文本** - Layout text at final height before revealing / 引用块、详情块子文本在整块揭示前先按最终高度排版
- 🧪 **Regression Coverage / 回归测试覆盖** - Added regression test cases / 新增回归测试覆盖

## [2.0.0] - 2026-08-13

### Added / 新增
- 🤖 **AI Chat Web Search & Tool Calls / AI 对话联网搜索与工具调用** - DeepSeek function calling with built-in `web_search` tool / AI Chat 示例接入 DeepSeek function calling 与内置联网搜索
- 🗣 **AI Chat Copy & Read-Aloud Footer / AI 对话复制与朗读底部操作** - Copy full message and read aloud via SpeechKit / 新增复制全部内容与基于 SpeechKit 的朗读功能
- 🧠 **Thinking Mode Parameters / Thinking 模式参数** - Pass-through `thinking` & `reasoning_effort` / 透传 `thinking` 与 `reasoning_effort` 参数

### Changed / 变更
- 📊 **Faster Table Horizontal Scrolling / 表格横向滚动更流畅** - Optimized collection layout and direction locking / 优化集合布局与方向锁定，提升表格滑动流畅度

### Fixed / 修复
- 🐛 **Fixed Self-Sizing Constraint Conflicts / 修复自适高约束冲突** - Lower priority on width constraints / 降低宽度约束优先级消除警告
- 🐛 **Fixed Re-render Feedback Loop / 修复重复渲染反馈环** - Prevent full re-render on identical content assignment / 赋值相同内容不再触发整篇重渲染

## [1.9.9] - 2026-08-06

### Added / 新增
- 🎨 **Four Demo Themes & Gallery / 四套 Demo 主题与主题画廊** - Parchment, Sage, Midnight, Plum themes / 新增暖纸张、鼠尾草、深海代码和暮紫夜色四套主题
- 🧱 **Configurable Block Appearance / 块级外观可配置** - Corner-radius and border configuration for blocks / 为代码块、引用块、表格、图片、LaTeX 和详情块新增圆角与边框配置
- ➗ **Theme-Aware Formula Rendering / 公式渲染跟随主题** - Added `latexTextColor` / 新增 `latexTextColor` 使公式字形与线条随主题切换

### Changed / 变更
- 🔄 **Consistent Prepared-Content Styling / 预渲染样式保持一致** - Inject same theme configuration / 注入同一份主题配置，避免使用过期主题颜色
- 🖼 **Cleaner Image Defaults / 更干净的图片默认外观** - Keep rounding, disable default borders / 保留图片圆角，默认关闭图片边框

## [1.9.8] - 2026-08-04

### Added / 新增
- 🚀 **Backpressured Smart-Streaming Pipeline / 带背压的智能流式管线** - Serial background parsing with frame budget & watermarks / 后台串行解析与单帧预算/高低水位控制
- ⚡ **DisplayLink Typewriter Scheduling / 基于 DisplayLink 的打字机调度** - 30 FPS `CADisplayLink` timeline with O(1) FIFO head / 30 FPS `CADisplayLink` 调度与 O(1) FIFO 消费
- 📏 **Incremental Height Cache / 增量高度缓存** - Incremental height growth tracking & cache / 增量高度跟踪与缓存
- 📊 **Performance Diagnostics / 性能诊断与回归覆盖** - Added `[MDPERF]` aggregate diagnostics / 新增 `[MDPERF]` 聚合诊断

### Changed / 变更
- ✨ **Stable Rendering Without Repaint Flashes / 稳定渲染避免重复重绘闪烁** - Invalidate only on real bounds change / 仅真实 bounds 变化时重绘
- 🧱 **Bounded Rich-Block Layout Work / 富文本块布局工作量有界** - Tables and quotes layout bounded / 限制表格与引用块布局开销
- 🔒 **Deterministic Module & Extension Handling / 模块与自定义扩展处理确定化** - Global ordering and heading IDs preserved / 保持全局顺序与标题 ID
- 🧹 **Smart-Streaming API Consolidation / 智能流式 API 收敛** - Consolidated around `beginRealStreaming`, `appendStreamData`, `endRealStreaming` / 统一智能流式 API

## [1.8.9] - 2026-07-31

### Added / 新增
- 🔒 **Thread-Safe Custom Extension Registry / 自定义扩展注册表线程安全** - Thread-safe parser and renderer registries / 扩展注册与读取加锁保护
- ⚡ **Single-Pass LaTeX Rendering / LaTeX 公式真正单次解析** - Parse once and share render result across layout and view / 公式单次解析共享渲染结果

### Changed / 变更
- 🖼 **Unified Kingfisher Image Pipeline / 统一使用 Kingfisher 图片管线** - Image loading and caching handled by Kingfisher / 图片加载与缓存统一交由 Kingfisher
- 🧩 **Modularized Markdown Renderer / Markdown 渲染器模块化拆分** - Split monolithic view into extension files / 拆分为职责清晰的 extension 文件

## [1.8.6] - 2026-07-31

### Fixed / 修复
- 🐛 **Fixed Initial Details-Block Whitespace / 修复首次进入时折叠模块前大段留白** - List wrapper strictly follows content height / 列表 wrapper 严格跟随真实内容高度
- 📏 **Synchronized Deferred Layout / 无需滑动同步延迟布局** - Final height propagated via `contentLayoutGuide` / 最终高度主动同步
- 📍 **Preserved Scroll Position / 追加式渲染保持当前滚动位置** - Correct `contentOffset` calculation for offscreen appends / 避免追加内容影响滚动位置

## [1.8.5] - 2026-07-30

### Performance / 性能
- ⚡ **Incremental Stream Buffer Scanning / 流式缓存器增量扫描** - Scan only uncommitted tail (1.6x-3.8x speedup) / 仅扫描未提交尾部，提速 1.6~3.8 倍
- ⚡ **TextKit 2 Incremental Layout / TextKit 2 增量排版与测高** - Incremental editing transactions without full replacement / 事务内增量修改与测高
- ⚡ **LaTeX Formula Parse Deduplication / LaTeX 公式解析去重** - Deduplicated repeated formula parsing / 避免单个公式重复解析
- ⚡ **Persistent Typewriter Watchdog / 打字机看门狗常驻 Timer** - Persistent timer in `.common` mode / 常驻 Timer 兜底

### Fixed / 修复
- 🐛 **Regression Bug Fixes / 修复回归缺陷** - Fixed container width semantics, dirty-rect clipping, off-screen fade-in / 修复容器宽度、脏矩形裁剪与淡入过渡
- 🐛 **Eliminated Background UIKit Access / 消除后台线程 UIKit 访问** - Snapshot container width on main thread / 主线程读取宽度快照
- 🐛 **Streaming Auto-Scroll Improvements / 流式自动滚动优化** - User takeover detection / 增加用户接管判定
- 🧹 **Code Cleanup / 代码清理** - Removed unused code and added `#if DEBUG` guards / 删除死代码并添加日志守卫
- ✨ **Enhanced AI Chat Examples / AI 对话示例增强** - Added chat history support / 新增聊天历史记录能力

## [1.8.1] - 2026-07-15

### Fixed / 修复
- 📏 **Append Typewriter Height Stability / Append 打字机高度稳定性** - Separated character reveal from height remeasurement and only fire layout callbacks when height actually changes / 将字符揭示与高度重测解耦，仅在高度真正变化时触发布局回调
- 🧱 **No Pre-Reveal Blank Height / 不再预暴露最终空白高度** - Append mode discards precalculated final height before typing starts, so height grows with visible text only / Append 模式在开始打字前丢弃预计算最终高度，高度只随可见文本增长
- 🔒 **Height Floor During Playback / 播放期高度下限** - Prevents shrink from transient width corrections while append typewriter is active; releases the floor on finish or engine stop / 播放期间禁止临时宽度修正导致高度回缩，完成或 stop 后释放下限

### Tests / 测试
- 🧪 **Streaming Layout Coverage / 流式布局覆盖** - Added tests for reveal/height decoupling, pre-playback height reset, and height-floor release on finish/stop / 新增字符揭示/高度解耦、播放前高度重置、完成/停止后释放高度下限用例

## [1.7.8] - 2026-05-26

### Changed / 变更
- 🖼 **Kingfisher Image Loading / Kingfisher 图片加载** - Switched Markdown image loading and caching to Kingfisher 8.9.0 in `ImageView.swift` / `ImageView.swift` 中的 Markdown 图片加载与缓存切换为 Kingfisher 8.9.0
- 📦 **Dependency Alignment / 依赖对齐** - Added Kingfisher to both `Package.swift` and `MarkdownDisplayKit.podspec` so SPM and CocoaPods resolve the same image library / `Package.swift` 与 `MarkdownDisplayKit.podspec` 同步声明 Kingfisher，SPM 和 CocoaPods 使用同一个图片库
- 🧪 **Example Update / 示例更新** - Updated `ExampleForMarkdown` and `CocoapodsMDExample` image views to use Kingfisher-based loading / `ExampleForMarkdown` 和 `CocoapodsMDExample` 的图片视图已更新为 Kingfisher 加载实现

## [1.7.5] - 2026-05-15

### Added / 新增
- 🚀 **Prepared Content Rendering / 预渲染内容渲染入口** - Added `MarkdownRenderer.prepare(_:)` and `MarkdownViewTextKit.setPreparedContent(_:)` so apps can pre-parse long Markdown off the main display path and reuse generated render elements / 新增 `MarkdownRenderer.prepare(_:)` 与 `MarkdownViewTextKit.setPreparedContent(_:)`，业务侧可提前解析长 Markdown，并复用生成好的渲染元素
- 📏 **Precomputed Height Fast Path / 预计算高度快速路径** - Prepared content carries estimated element heights so text and heading views can skip expensive first-pass TextKit height calculation when width is known / 预渲染结果携带元素高度估算，在宽度已知时文本和标题视图可跳过首次 TextKit 高度计算

### Changed / 变更
- 🧪 **History Markdown Example Optimization / 历史长 Markdown 示例优化** - `CocoapodsMDExample` now pre-renders historical long Markdown messages in the background and uses cached row heights to reduce first-scroll stutter / `CocoapodsMDExample` 中的历史消息页面改为后台预渲染长 Markdown，并使用缓存行高，降低首次滑动卡顿

### Fixed / 修复
- 🐛 **History Row Blank-Space Fix / 历史消息空白修复** - Removed the oversized initial row-height placeholder and fixed callback ordering so measured content height replaces estimates correctly / 移除过大的初始行高占位，并修正高度回调设置顺序，确保真实测量高度能正确替换估算高度

## [1.7.4] - 2026-04-10

### Added / 新增
- 📐 **Whole-List Top/Bottom Padding / 整个列表头尾内边距** - Added `listTopPadding` and `listBottomPadding` so the entire list wrapper can apply configurable top/bottom spacing without changing per-item layout / 新增 `listTopPadding` 和 `listBottomPadding`，支持为整个列表 wrapper 配置顶部/底部间距，而不改变每个列表项自身布局

### Fixed / 修复
- 📏 **Height Measurement Stabilization / 高度测量稳定性修复** - Hardened `notifyHeightChange` with width fallback, frame-height fallback, and transient-zero suppression to avoid `0 ↔ actual height` jumps during initial layout or rapid updates / 加固 `notifyHeightChange`：增加宽度兜底、基于 frame 的高度回退，以及临时 `0` 高度抑制，避免初始布局或快速更新时出现 `0 ↔ 实际高度` 来回跳变
- 🌊 **Paragraph-Level Streaming Fallback / 段落级流式切分回退** - Real streaming now emits single-heading or heading-less Markdown by paragraph boundaries when heading-based segmentation is unavailable, while skipping fenced code blocks / 当标题数量不足以用于模块切分时，真流式模式现在会按段落边界输出单标题或无标题 Markdown，同时跳过 fenced code block 内部的空段切分

## [1.7.1] - 2026-04-03

### Fixed / 修复
- 🐛 **Ordered List Height Consistency / 有序列表高度一致性** - Fixed an issue where the first ordered-list item could be stretched taller than following items in some stack/reuse layouts / 修复部分 Stack/ReUse 场景下首个有序列表项高度被异常拉高、与后续项不一致的问题
- 🧱 **List Layout Constraint Hardening / 列表布局约束加固** - Changed list wrapper bottom constraint to `<=` and strengthened vertical hugging/compression priorities to avoid extra height being absorbed by the first item / 调整列表外层底部约束为 `<=`，并增强垂直 hugging/compression，避免额外高度被首项吸收
- 🧹 **List Invisible Text Cleanup / 列表不可见文本清理** - Added normalization and cleanup for invisible list text nodes (leading/trailing newlines, zero-width/control whitespace) to prevent phantom list item height / 增加列表不可见文本节点的归一化与清理（首尾换行、零宽字符、控制/空白字符），避免“幽灵高度”撑开列表项

## [1.7.0] - 2026-04-03

### Added / 新增
- 📊 **Markdown Table Column Alignment / Markdown 表格列对齐支持** - Added support for table alignment syntax (`:---`, `:---:`, `---:`) and applied alignment per column / 新增 `:---`、`:---:`、`---:` 对齐语法解析，并按列应用左/中/右对齐
- 🛠 **Malformed Table Auto-Fix / 异常表格自动修复** - Added `autoFixMalformedTables` (default: `true`) to normalize common broken table output (isolated `|`, accidental blank lines inside tables) / 新增 `autoFixMalformedTables`（默认 `true`），自动修正常见异常输出（孤立 `|`、表格块内误空行）
- ✍️ **Configurable Line Spacing / 行间距配置化** - Added `lineSpacing` configuration for `body`, `heading`, `quote`, `codeBlock`, replacing fixed line spacing constants / 新增 `lineSpacing` 配置（`body`、`heading`、`quote`、`codeBlock`），替代固定行间距常量

### Changed / 变更
- 🔗 **Table Link Tap Callback / 表格链接点击回调** - Keep `UILabel` in table cells for better scrolling performance; link taps now route through cell selection and existing `onLinkTap` callback chain / 表格 cell 保持 `UILabel`（滚动性能更优），通过 cell 点击识别链接并复用 `onLinkTap` 回调链路
- ⚠️ **Configuration Cleanup / 配置项收敛** - Removed table-level alignment override config; table text alignment now follows Markdown syntax (fallback: left) / 移除表格文本对齐覆盖配置项；表格文本对齐以 Markdown 语法为准（默认左对齐）

### Fixed / 修复
- 🐛 **Touch Routing Fix / 触摸路由修复** - Fixed gesture conflict where outer TextKit tap handling could swallow table attachment touches and prevent link callbacks / 修复外层 TextKit 点击手势可能抢占表格附件触摸，导致表格链接点击回调不生效

## [1.6.0] - 2026-01-30

### Added / 新增
- 🎨 **Comprehensive Configuration Options / 全面配置项支持** - Added extensive customization for all Markdown elements / 新增所有 Markdown 元素的详细配置：
  - **LaTeX Formula / LaTeX 公式**: `latexFontSize`, `latexAlignment` (left/center/right), `latexBackgroundColor`, `latexPadding`
  - **Blockquote / 引用块**: `blockquoteBackgroundColor`, `blockquoteBarWidth`, `blockquoteContentSpacing`, `blockquoteContentPadding`
  - **Table / 表格**: `tableMinColumnWidth`, `tableMaxColumnWidth`, `tableRowHeight`, `tableCellPadding`, `tableSeparatorHeight`
  - **List / 列表**: `listItemSpacing`, `listMarkerMinWidth`, `listMarkerSpacing`
  - **Details / 折叠块**: `detailsSummaryFont`, `detailsSummaryTextColor`, `detailsSummaryMinHeight`, `detailsContentPadding`, `detailsSpacing`
  - **Syntax Highlighting / 代码高亮**: `syntaxColors`, `syntaxColorsDark` with `SyntaxHighlightColors` struct (keyword, string, number, comment, type, function, property, preprocessor) / 支持 `SyntaxHighlightColors` 结构体
  - **TOC / 目录**: `tocTextColor`

### Fixed / 修复
- `tableRowBackgroundColor`: Now properly applied to table rows / 现已正确应用于表格行

### Documentation / 文档
- Updated README with complete configuration options / 更新 README 完善所有配置选项文档

## [1.5.9] - 2026-01-26

### Added / 新增
- 🚀 **Typewriter Append Mode / 打字机追加模式** - Add `.append` mode with throttled height updates to reduce layout jumps during cell streaming / 新增 `.append` 模式，并对高度更新节流，减少 Cell 流式输出时的布局跳变
- ⚙️ **Streaming Config / 流式配置项** - Expose `typewriterTextMode`, `typewriterHeightUpdateInterval`, `streamMinModuleLength` / 提供 `typewriterTextMode`、`typewriterHeightUpdateInterval`、`streamMinModuleLength`
- 🧹 **Memory Cleanup / 内存清理** - Add cache clearing helpers and Mermaid WebView cleanup to reduce retained memory / 增加缓存清理与 Mermaid WebView 释放逻辑，降低页面退出后的驻留内存

### Changed / 变更
- 🧪 **Example Update / 示例更新** - AI chat stream uses safer LaTeX normalization (code regions ignored) and recommended config / AI 对话流式 LaTeX 规范化更安全（忽略代码区域），并给出推荐配置

## [1.5.8] - 2026-01-23

### Documentation / 文档
- 📝 **Docs Update / 文档更新** - Refresh README content / 更新 README 内容

### Fixed / 修复
- 🐛 **SPM Fix / SPM 修复** - Fix simulator build error in Swift Package Manager example project / 修复 Swift Package Manager 示例在模拟器上的编译问题

## [1.5.2] - 2026-01-08

### Fixed / 修复
- 🐛 **Crash Fix / 崩溃修复** - Serialize `swift-markdown` parsing to avoid `cmark_parser_attach_syntax_extension` race crash in concurrent renders / 串行化 `swift-markdown` 解析，避免并发渲染触发崩溃

### Added / 新增
- 🧹 **Reuse Safety / 复用安全** - Add `resetForReuse()` to clear internal caches/state for `UITableViewCell` reuse scenarios / 新增 `resetForReuse()` 清理内部缓存与状态，适配 `UITableViewCell` 复用场景
- 🧪 **Example Update / 示例更新** - Add crash reproduction screen and incremental row insert demo for table view usage / 增加崩溃复现页面与表格场景的逐条插入演示

## [1.5.1] - 2026-01-07

### Fixed / 修复
- 🐛 **Bug Fix** - Fixed potential crash when processing Unicode characters (emoji, CJK characters) in streaming mode / 修复流式渲染处理 Unicode 字符（emoji、中日韩字符）时可能崩溃的问题
  - `MarkdownStreamBuffer.extractModule`: Use safe string index with `limitedBy` to prevent out-of-bounds crash / 使用 `limitedBy` 安全获取字符串索引，防止越界崩溃
  - `TypewriterEngine.calculateDelay`: Use safe string index to prevent crash when calculating delay for special characters / 使用安全索引获取字符，防止计算特殊字符延迟时崩溃

## [1.5.0] - 2026-01-04

### Added / 新增
- 🚀 **Real Streaming Support / 真流式渲染支持** - New `MarkdownStreamBuffer` for intelligent real-time streaming from network/LLM APIs / 新增 `MarkdownStreamBuffer` 智能流式缓冲器，支持网络/LLM API 实时流式渲染
  - Smart module detection: automatically detects complete Markdown blocks (headings, code blocks, tables, LaTeX) / 智能模块检测：自动识别完整的 Markdown 块
  - Handles incomplete structures: waits for closing tags before rendering / 未闭合结构处理：等待闭合标签后再渲染
  - Incremental rendering: renders complete modules immediately while buffering incomplete content / 增量渲染：完整模块立即渲染，未完成内容继续缓冲
- 💫 **Smart Waiting Indicator / 智能等待动画** - In real streaming mode, automatically shows waiting animation when TypewriterEngine queue is empty and no network data arrives / 真流式模式下，当 TypewriterEngine 队列为空且网络数据未到达时，自动显示等待动画

### Changed / 变更
- 🏗️ **Code Refactoring / 代码重构** - Extracted `MarkdownTextViewTK2`, `MarkdownStreamBuffer`, and `TypewriterEngine` into separate files for better maintainability / 将相关类提取到独立文件，提升代码可维护性

### Fixed / 修复
- 🐛 **Streaming Fixes / 流式修复** - Multiple fixes for real streaming mode stability and rendering issues / 多项真流式模式稳定性和渲染问题修复

## [1.4.1] - 2026-01-02

### Fixed / 修复
- 🐛 **Bug Fix** - Fixed code blocks not rendering properly in real streaming mode when content arrives in multiple chunks / 修复真流式模式下代码块分块到达时无法正确渲染的问题

## [1.4.0] - 2025-12-31

### Added / 新增
- 🚀 **Instant Loading / 秒开优化** - Significantly optimized loading speed with ultra-fast first screen rendering / 大幅优化加载速度，首屏渲染极速完成
- 🔌 **Enhanced Custom Extensions / 自定义扩展增强** - New `MarkdownCodeBlockRenderer` protocol for custom code block rendering (e.g., Mermaid diagrams) / 新增代码块渲染器协议，支持 Mermaid 等图表渲染
- 🎨 **Mermaid Support / Mermaid 支持** - Example project now includes Mermaid diagram renderer supporting flowcharts, mind maps, and more / 示例项目新增 Mermaid 图表渲染器

### Performance / 性能
- ⚡ **CPU Optimization / CPU 优化** - Streaming mode with nested style rendering now uses much less CPU (iPhone 17 Pro simulator peak < 56%, average 30%) / 流式模式下 CPU 使用率大幅降低

## [1.0.0] - 2025-12-15

### Added / 新增
- 🎉 Initial release / 首次发布
- ✅ Full Markdown syntax support / 完整 Markdown 语法支持
- ✅ 20+ language code highlighting / 20+ 种语言代码高亮
- ✅ Automatic table of contents generation / 自动目录生成
- ✅ Dark mode support / 深色模式支持
- ✅ High-performance asynchronous rendering / 高性能异步渲染
