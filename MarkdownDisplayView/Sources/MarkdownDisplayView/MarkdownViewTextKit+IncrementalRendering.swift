//
//  MarkdownViewTextKit+IncrementalRendering.swift
//  MarkdownDisplayView
//
//  Mechanical extension split from MarkdownDisplayView.swift.
//

import UIKit
import Foundation
import Combine
import NaturalLanguage

@available(iOS 15.0, *)
extension MarkdownViewTextKit {
    func performRender() {
        let markdownText = markdown
        let config = configuration
        let containerWidth = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width - 32

        // 🔍 性能监控：performRender 开始
        if renderStartTime > 0 {
            let elapsed = (CFAbsoluteTimeGetCurrent() - renderStartTime) * 1000
            mdLog("🔍 [Perf] performRender start: +\(String(format: "%.1f", elapsed))ms")
        }

        let perfStartTime = renderStartTime // 捕获性能监控起始时间

        // `markdown` 是完整文档快照 API。网络增量由 RealStreaming 管线独立处理；
        // 普通渲染始终全量解析，避免在字符窗口和 Markdown 块之间做不可靠的重叠猜测。
        mdLog("🔄 [Snapshot Parse] Parsing complete document")
        performFullParse(
            markdownText: markdownText,
            config: config,
            containerWidth: containerWidth,
            perfStartTime: perfStartTime
        )
    }

    /// 执行全量解析（原有逻辑保持不变）
    func performFullParse(
        markdownText: String,
        config: MarkdownConfiguration,
        containerWidth: CGFloat,
        perfStartTime: CFAbsoluteTime
    ) {
        // 增加渲染版本号（线程安全）
        renderVersionLock.lock()
        renderVersion += 1
        let currentVersion = renderVersion
        renderVersionLock.unlock()

        renderQueue.async { [weak self] in
            guard let self else { return }

            let startTime = CFAbsoluteTimeGetCurrent()

            // 预处理脚注
            let (processedMarkdown, footnotes) = self.preprocessFootnotes(markdownText)

            // 直接渲染，获取所有需要的返回
            let renderer = MarkdownRenderer(configuration: config, containerWidth: containerWidth)
            let (newElements, attachments, tocItems, tocSectionId) = renderer.render(processedMarkdown)

            let endTime = CFAbsoluteTimeGetCurrent()
            let parseDuration = endTime - startTime

            // 🔍 性能监控：解析完成
            if !self.isStreaming && perfStartTime > 0 {
                let elapsed = (CFAbsoluteTimeGetCurrent() - perfStartTime) * 1000
                mdLog("🔍 [Perf] Parsing complete: +\(String(format: "%.1f", elapsed))ms (parse took \(String(format: "%.1f", parseDuration * 1000))ms)")
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                // ⭐️ 关键：只使用最新版本的渲染结果
                self.renderVersionLock.lock()
                let isLatestVersion = currentVersion == self.renderVersion
                self.renderVersionLock.unlock()

                guard isLatestVersion, !self.isRealStreamingMode else {
                    mdLog("[MarkdownDisplayView] 丢弃旧版本渲染结果 (version \(currentVersion))")
                    return
                }

                self.tableOfContents = tocItems
                self.tocSectionId = tocSectionId
                self.imageAttachments = attachments

                // 🔍 性能监控：开始UI渲染
                if !self.isStreaming && perfStartTime > 0 {
                    let elapsed = (CFAbsoluteTimeGetCurrent() - perfStartTime) * 1000
                    mdLog("🔍 [Perf] updateViews start: +\(String(format: "%.1f", elapsed))ms")
                }

                self.updateViews(newElements: newElements, footnotes: footnotes, containerWidth: containerWidth, parseDuration: parseDuration, perfStartTime: perfStartTime)
            }
        }
    }
    
    func updateViews(
        newElements: [MarkdownRenderElement],
        footnotes: [MarkdownFootnote],
        containerWidth: CGFloat,
        parseDuration: Double = 0,
        perfStartTime: CFAbsoluteTime = 0,
        precalculatedTextHeights: [CGFloat?]? = nil
    ) {
        let startTime = CFAbsoluteTimeGetCurrent()
        renderCosts = [:] // Reset performance counters

        // Record Parsing Time
        recordCost(for: "1. Parsing", duration: parseDuration)

        if shouldUseStaticViewportWindow(for: newElements) {
            offscreenRenderWorkItem?.cancel()
            placeholderView?.removeFromSuperview()
            placeholderView = nil
            updateViewportWindowViews(
                elements: newElements,
                footnotes: footnotes,
                containerWidth: containerWidth,
                startTime: startTime,
                perfStartTime: perfStartTime,
                precalculatedTextHeights: precalculatedTextHeights
            )
            return
        }

        // 宿主或内容形态变化后恢复原有渲染路径，避免 diff 把槽位误当成内容视图复用。
        leaveViewportWindowForLegacyRendering()

        // ⚡️ 首屏优化：判断是否启用分批渲染
        // 条件：非流式模式 + 元素数量 > 5（避免过少内容也分批）
        let shouldUseBatchRendering = !isStreaming && newElements.count > 5 && !isEmbeddedInReusableCell()

        // 🔍 诊断日志
        if perfStartTime > 0 {
            mdLog("🔍 [Perf] updateViews: isStreaming=\(isStreaming), elementCount=\(newElements.count), shouldBatch=\(shouldUseBatchRendering)")
        }

        if shouldUseBatchRendering {
            // 🎯 阶段1: 逐个渲染直到达到目标高度（2屏）
            let targetHeight = UIScreen.main.bounds.height * firstScreenHeightMultiplier
            let firstScreenCutoff = calculateFirstScreenCutoff(
                elements: newElements,
                targetHeight: targetHeight,
                containerWidth: containerWidth
            )

            guard firstScreenCutoff < newElements.count else {
                // 所有元素都在首屏范围内，直接全部渲染
                updateViewsInternal(
                    newElements: newElements,
                    footnotes: footnotes,
                    containerWidth: containerWidth,
                    parseDuration: parseDuration,
                    startTime: startTime,
                    isBatchFirstScreen: false,
                    perfStartTime: perfStartTime,
                    precalculatedTextHeights: precalculatedTextHeights
                )
                return
            }

            mdLog("⚡️ [FirstScreen] Rendering \(firstScreenCutoff)/\(newElements.count) elements (~\(Int(targetHeight))pt)")

            // 渲染首屏元素
            let firstScreenElements = Array(newElements.prefix(firstScreenCutoff))
            let offscreenElements = Array(newElements.dropFirst(firstScreenCutoff))

            // ⭐️ 记录首屏渲染前的估算高度（用于后续校准）
            let estimatedFirstScreenHeight = firstScreenElements.reduce(CGFloat(0)) { total, element in
                total + estimateElementHeight(element, containerWidth: containerWidth)
            }

            updateViewsInternal(
                newElements: firstScreenElements,
                footnotes: [], // 首屏暂不渲染脚注
                containerWidth: containerWidth,
                parseDuration: parseDuration,
                startTime: startTime,
                isBatchFirstScreen: true,
                perfStartTime: perfStartTime,
                precalculatedTextHeights: precalculatedTextHeights.map { Array($0.prefix(firstScreenCutoff)) }
            )

            // ⭐️ 关键修复：测量首屏实际高度，计算估算误差
            contentStackView.layoutIfNeeded()
            let actualFirstScreenHeight = contentStackView.bounds.height
            let firstScreenHeightError = actualFirstScreenHeight - estimatedFirstScreenHeight

            mdLog("📏 [FirstScreen] Estimated: \(String(format: "%.1f", estimatedFirstScreenHeight))pt, Actual: \(String(format: "%.1f", actualFirstScreenHeight))pt, Error: \(String(format: "%.1f", firstScreenHeightError))pt")

            // ⭐️ 是否需要占位视图取决于用户当前是否已经滚动离开顶部。
            // 用户刚进入页面时 offset≈0，内容向下增长不会引起任何可见跳动，
            // 此时插入一个几千 pt 的空白占位视图纯粹是制造"大段空白 + 二次跳变"（估算误差越大越明显）。
            // 只有当用户已经滚动到内容中间时，才需要占位撑住高度，避免离屏内容加载完成后
            // 页面在其视口内发生突兀的回缩/前跳。
            let scrollViewForPlacement = findParentScrollView()
            let currentScrollOffset = scrollViewForPlacement?.contentOffset.y ?? 0

            if currentScrollOffset > 50 {
                // ⚡️ 添加占位视图，预留离屏内容空间，避免布局跳动
                let baseEstimatedHeight = offscreenElements.reduce(CGFloat(0)) { total, element in
                    total + estimateElementHeight(element, containerWidth: containerWidth)
                }

                // ⭐️ 改进：基于首屏误差比例来调整离屏估算
                // 如果首屏估算偏低10%，假设离屏也会偏低类似比例
                let errorRatio = estimatedFirstScreenHeight > 0 ? actualFirstScreenHeight / estimatedFirstScreenHeight : 1.0
                let adjustedOffscreenHeight = baseEstimatedHeight * errorRatio

                // 额外增加 5% 缓冲（比之前的10%少，因为已经用误差比例校准了）
                let estimatedOffscreenHeight = adjustedOffscreenHeight * 1.05

                mdLog("📦 [Placeholder] Creating placeholder: base=\(String(format: "%.1f", baseEstimatedHeight))pt, adjusted=\(String(format: "%.1f", adjustedOffscreenHeight))pt (ratio=\(String(format: "%.2f", errorRatio))), final=\(String(format: "%.1f", estimatedOffscreenHeight))pt")

                // 创建占位视图
                placeholderView?.removeFromSuperview()
                let placeholder = UIView()
                placeholder.backgroundColor = .clear
                placeholder.translatesAutoresizingMaskIntoConstraints = false
                contentStackView.addArrangedSubview(placeholder)

                NSLayoutConstraint.activate([
                    placeholder.heightAnchor.constraint(equalToConstant: estimatedOffscreenHeight)
                ])

                placeholderView = placeholder

                // 强制立即布局，确保占位视图生效
                contentStackView.layoutIfNeeded()

                // ⚡️ 现在通知父视图完整高度（首屏内容 + 占位视图）
                mdLog("🎬 [FirstScreen] Calling notifyHeightChange() after adding placeholder")
                notifyHeightChange()
            } else {
                // 用户在顶部：不占位，直接上报首屏真实高度，避免出现空白区域
                mdLog("📦 [Placeholder] Skipped (user at top, offset=\(String(format: "%.1f", currentScrollOffset))) - reporting real first-screen height only")
                placeholderView?.removeFromSuperview()
                placeholderView = nil
                notifyHeightChange()
            }

            // 🎯 阶段2: 延迟渲染离屏元素
            offscreenRenderWorkItem?.cancel()

            // ⭐️ 捕获离屏元素，用于后续追加渲染
            let offscreenElementsCaptured = offscreenElements
            let firstScreenCountCaptured = firstScreenCutoff
            let offscreenPrecalculatedTextHeights = precalculatedTextHeights.map {
                Array($0.dropFirst(firstScreenCutoff))
            }

            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }

                let offscreenStartTime = CFAbsoluteTimeGetCurrent()
                mdLog("⚡️ [Offscreen] Rendering remaining \(offscreenElementsCaptured.count) elements (append-only mode)")

                // ⭐️ 查找父 ScrollView，用于位置补偿
                let scrollView = self.findParentScrollView()
                let scrollOffsetBeforeRender = scrollView?.contentOffset.y ?? 0

                // ⭐️ 记录渲染前的总高度（首屏 + 占位视图）
                self.contentStackView.layoutIfNeeded()
                let contentHeightBeforeRender = self.contentStackView.bounds.height

                // ⚡️ 移除占位视图
                if let placeholder = self.placeholderView {
                    mdLog("📦 [Placeholder] Removing placeholder before offscreen rendering")
                    placeholder.removeFromSuperview()
                    self.placeholderView = nil
                }

                // ⭐️ 关键优化：只追加离屏元素，不重新 Diff 首屏元素
                // 这样首屏视图保持不变，避免布局跳动
                var newlyAddedViews: [UIView] = []
                for (index, element) in offscreenElementsCaptured.enumerated() {
                    let createStart = CFAbsoluteTimeGetCurrent()
                    let view = self.createView(
                        for: element,
                        containerWidth: containerWidth,
                        precalculatedHeight: offscreenPrecalculatedTextHeights?[safe: index] ?? nil
                    )

                    // 设置 tag 便于调试
                    view.tag = 1000 + firstScreenCountCaptured + index

                    // 占位符是纯空白，替换成真实内容是硬切；淡入让这个替换不那么突兀
                    view.alpha = 0
                    self.contentStackView.addArrangedSubview(view)
                    newlyAddedViews.append(view)

                    // 注册 heading
                    if case .heading(let id, _) = element {
                        self.headingViews[id] = view
                        if id == self.tocSectionId {
                            self.tocSectionView = view
                        }
                    }

                    let createTime = (CFAbsoluteTimeGetCurrent() - createStart) * 1000
                    if createTime > 10 {
                        mdLog("⚡️ [Offscreen] Created \(self.elementTypeString(element)) in \(String(format: "%.1f", createTime))ms")
                    }
                }

                UIView.animate(withDuration: 0.15) {
                    newlyAddedViews.forEach { $0.alpha = 1 }
                }

                // 更新 oldElements 为完整元素列表（静态一次性渲染不保留）
                self.oldElements = self.retainsDiffBaseline ? newElements : []

                // 处理脚注
                if !footnotes.isEmpty {
                    self.updateFootnotes(footnotes, width: containerWidth, newElementCount: newElements.count)
                }

                // 加载图片
                self.loadImages()
                self.invalidateIntrinsicContentSize()

                // ⭐️ 计算追加前后的高度变化，供诊断使用。
                // 离屏元素始终追加在现有内容末尾，不会改变当前视口之前的内容位置，
                // 因此无论用户是否已经滚动，都不应该把整段新增高度加到 contentOffset。
                self.contentStackView.layoutIfNeeded()
                let contentHeightAfterRender = self.contentStackView.bounds.height
                let heightDiff = contentHeightAfterRender - contentHeightBeforeRender

                mdLog("📏 [Offscreen] Height before: \(String(format: "%.1f", contentHeightBeforeRender))pt, after: \(String(format: "%.1f", contentHeightAfterRender))pt, diff: \(String(format: "%.1f", heightDiff))pt")

                // ⭐️ force: true，绕过 9pt 防抖门槛，确保离屏内容加载完成后高度变化一定会通知出去，
                // 并沿约束链刷新父 ScrollView 的 contentLayoutGuide/contentSize，不依赖用户触摸。
                self.notifyHeightChange(force: true)
                if let scrollView {
                    mdLog("📍 [Scroll Preservation] Appended content below viewport; offset remains \(String(format: "%.1f", scrollOffsetBeforeRender)), contentSize=\(String(format: "%.1f", scrollView.contentSize.height))")
                }
                mdLog("⚡️ [Offscreen] Completed in \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - offscreenStartTime) * 1000))ms")
            }
            offscreenRenderWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + offscreenRenderDelay, execute: workItem)

            return
        }

        // 常规渲染（流式模式或元素数量较少）
        if perfStartTime > 0 {
            mdLog("🔍 [Perf] Using regular rendering (no batch)")
        }
        updateViewsInternal(
            newElements: newElements,
            footnotes: footnotes,
            containerWidth: containerWidth,
            parseDuration: parseDuration,
            startTime: startTime,
            isBatchFirstScreen: false,
            perfStartTime: perfStartTime,
            precalculatedTextHeights: precalculatedTextHeights
        )
    }

    /// 计算首屏应该渲染到第几个元素（基于高度）
    func calculateFirstScreenCutoff(
        elements: [MarkdownRenderElement],
        targetHeight: CGFloat,
        containerWidth: CGFloat
    ) -> Int {
        var accumulatedHeight: CGFloat = 0
        var cutoffIndex = elements.count

        for (index, element) in elements.enumerated() {
            // 估算元素高度（快速估算，不创建实际视图）
            let estimatedHeight = estimateElementHeight(element, containerWidth: containerWidth)
            accumulatedHeight += estimatedHeight

            if accumulatedHeight >= targetHeight {
                cutoffIndex = max(3, index + 1) // 至少渲染3个元素
                break
            }
        }

        return cutoffIndex
    }

    /// 快速估算元素高度（不创建视图）
    func estimateElementHeight(_ element: MarkdownRenderElement, containerWidth: CGFloat) -> CGFloat {
        switch element {
        case .attributedText(let text):
            // 文本：使用boundingRect估算
            let size = text.boundingRect(
                with: CGSize(width: containerWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).size
            return ceil(size.height) + configuration.paragraphSpacing + configuration.paragraphTopSpacing + configuration.paragraphBottomSpacing

        case .heading(_, let text):
            // ⭐️ 改进：使用实际文本计算高度，而不是固定值
            let size = text.boundingRect(
                with: CGSize(width: containerWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).size
            return ceil(size.height) + configuration.headingTopSpacing + configuration.headingBottomSpacing

        case .quote(let children, _):
            // 引用：递归估算子元素 + padding
            let childrenHeight = children.reduce(0) { $0 + estimateElementHeight($1, containerWidth: containerWidth - 40) }
            return childrenHeight + 24  // 上下各12pt padding

        case .codeBlock(_, let code):
            let lines = code.string.components(separatedBy: .newlines).count
            return CGFloat(lines) * 20 + 40  // 每行20pt + 上下各20pt padding

        case .table(let data):
            // 表格：行数 * 估算行高
            let rowCount = data.rows.count + 1 // +1 for header
            return CGFloat(rowCount) * 44 + 24  // 表格额外padding

        case .list(let items, _):
            // ⭐️ 改进：递归估算列表项高度
            var totalHeight: CGFloat = 0
            for item in items {
                // 估算每个列表项的文本高度
                if !item.children.isEmpty {
                    totalHeight += item.children.reduce(0) { $0 + estimateElementHeight($1, containerWidth: containerWidth - 32) }
                } else {
                    totalHeight += 28  // 最小行高
                }
            }
            return max(totalHeight, CGFloat(items.count) * 28)

        case .thematicBreak:
            return 24

        case .image:
            return configuration.imagePlaceholderHeight + 16  // 上下间距

        case .latex:
            return 80  // LaTeX 公式通常较高

        case .details(let _, let children):
            // ⭐️ 改进：summary 按钮 + 少量 padding
            // 折叠状态下只显示按钮，但考虑按钮实际高度
            return 56  // 40pt 按钮 + 16pt 上下间距

        case .rawHTML:
            // raw HTML 当前不生成可见内容，与 createView(.rawHTML) 的零高实现保持一致。
            // 否则嵌套在 list/quote 的离屏槽位会长期高估，滚到附近才突然回缩。
            return 0

        case .custom(let data):
            // 自定义元素：尝试从 ViewProvider 获取尺寸
            if let provider = MarkdownCustomExtensionManager.shared.viewProvider(for: data.type) {
                return provider.calculateSize(for: data, configuration: configuration, containerWidth: containerWidth).height
            }
            return 100
        }
    }

    /// 实际的视图更新逻辑（支持分批渲染）
    func updateViewsInternal(
        newElements: [MarkdownRenderElement],
        footnotes: [MarkdownFootnote],
        containerWidth: CGFloat,
        parseDuration: Double,
        startTime: Double,
        isBatchFirstScreen: Bool,
        perfStartTime: CFAbsoluteTime,
        precalculatedTextHeights: [CGFloat?]? = nil
    ) {
        var newSubviews: [UIView] = []
        var consumedOldIndices = Set<Int>()
        var searchStart = 0
        
        // --- 1. 智能 Diff & Patch ---
        for (newIndex, newElement) in newElements.enumerated() {
            var foundIndex = -1

            // 🔍 追踪嵌套元素
            let isNested = { () -> Bool in
                switch newElement {
                case .quote, .list, .details: return true
                default: return false
                }
            }()

            // 设置搜索窗口（例如向后看5个元素），处理插入/删除造成的索引偏移
            let searchEnd = min(searchStart + 5, oldElements.count)

            if isNested {
               // mdLog("🔍 [Diff] Searching for nested element at newIndex=\(newIndex), searchStart=\(searchStart), searchEnd=\(searchEnd)")
            }

            for i in searchStart..<searchEnd {
                if consumedOldIndices.contains(i) { continue }

                let oldElement = oldElements[i]

                // 1. 检查类型是否兼容
                if canReuseElement(old: oldElement, new: newElement) {
                    if isNested {
                       // mdLog("  → Found reusable element at oldIndex=\(i), attempting updateViewInPlace...")
                    }

                    // 2. 尝试执行更新 (如果 LaTeX 模式改变，这里会返回 false)
                    // ⏱ Measure Update Time
                    let updateStart = CFAbsoluteTimeGetCurrent()
                    if let candidateView = contentStackView.arrangedSubviews[safe: i],
                       updateViewInPlace(candidateView, old: oldElement, new: newElement, containerWidth: containerWidth) {
                        
                        recordCost(for: "Update \(elementTypeString(newElement))", duration: CFAbsoluteTimeGetCurrent() - updateStart)
                        
                        foundIndex = i
                        if isNested {
                           // mdLog("  ✅ updateViewInPlace succeeded, reusing view at index \(i)")
                        }
                        break
                    } else {
                        // Update failed, count cost anyway
                         recordCost(for: "UpdateFail \(elementTypeString(newElement))", duration: CFAbsoluteTimeGetCurrent() - updateStart)
                        if isNested {
                           // mdLog("  ❌ updateViewInPlace failed or view not found")
                        }
                    }
                } else if isNested {
                   // mdLog("  → oldElement at \(i) cannot be reused (type mismatch)")
                }
            }

            if foundIndex != -1 {
                // ✅ 复用成功
                consumedOldIndices.insert(foundIndex)
                // 优化：如果刚好是当前搜索起点，推进起点
                if foundIndex == searchStart { searchStart += 1 }

                if let view = contentStackView.arrangedSubviews[safe: foundIndex] {
                    newSubviews.append(view)
                }
            } else {
                // 🆕 无法复用，创建新视图
                if isNested {
                   // mdLog("  ⚠️ No reusable view found, creating NEW nested view")
                }
                
                // ⏱ Measure Creation Time
                let createStart = CFAbsoluteTimeGetCurrent()
                let newView = createView(
                    for: newElement,
                    containerWidth: containerWidth,
                    precalculatedHeight: precalculatedTextHeights?[safe: newIndex] ?? nil
                )
                recordCost(for: "Create \(elementTypeString(newElement))", duration: CFAbsoluteTimeGetCurrent() - createStart)
                
                newSubviews.append(newView)
                
                // 注册目录
                if case .heading(let id, _) = newElement {
                    headingViews[id] = newView
                    if id == tocSectionId {
                        tocSectionView = newView
                    }
                }
            }
        }
        
        // --- 2. 协调 StackView (Reconcile) ---
        // 此时 newSubviews 包含了正确的视图顺序（复用的 + 新建的）
        // 我们需要把 contentStackView 调整成 newSubviews 的样子
        
        let reconcileStart = CFAbsoluteTimeGetCurrent()
        for (index, view) in newSubviews.enumerated() {
            if index < contentStackView.arrangedSubviews.count {
                let currentView = contentStackView.arrangedSubviews[index]
                
                if currentView != view {
                    // 视图位置不对，插入正确视图（UIStackView 会自动移动已存在的视图）
                    contentStackView.insertArrangedSubview(view, at: index)
                }
                // 如果 currentView == view，说明位置正确，无需操作
            } else {
                // 追加新视图
                contentStackView.addArrangedSubview(view)
            }
        }
        
        // --- 3. 清理多余视图 ---
        while contentStackView.arrangedSubviews.count > newSubviews.count {
            contentStackView.arrangedSubviews.last?.removeFromSuperview()
        }
        recordCost(for: "StackReconcile", duration: CFAbsoluteTimeGetCurrent() - reconcileStart)
        
        // --- 4. 脚注处理 ---
        // ⚡️ 流式渲染时跳过脚注，等流式完成后再渲染
        if !isStreaming {
            let footnoteStart = CFAbsoluteTimeGetCurrent()
            updateFootnotes(footnotes, width: containerWidth, newElementCount: newElements.count)
            recordCost(for: "UpdateFootnotes", duration: CFAbsoluteTimeGetCurrent() - footnoteStart)
        }

        finishUpdate(newElements: newElements, startTime: startTime, isBatchFirstScreen: isBatchFirstScreen, perfStartTime: perfStartTime)
    }

    // Helper to get element type name
    func elementTypeString(_ element: MarkdownRenderElement) -> String {
        switch element {
        case .attributedText: return "Text"
        case .heading: return "Heading"
        case .quote: return "Quote"
        case .codeBlock: return "CodeBlock"
        case .table: return "Table"
        case .thematicBreak: return "Rule"
        case .image: return "Image"
        case .latex: return "LaTeX"
        case .details: return "Details"
        case .list: return "List"
        case .rawHTML: return "HTML"
        case .custom(let data): return "Custom(\(data.type))"
        }
    }

    func updateFootnotes(_ footnotes: [MarkdownFootnote], width: CGFloat, newElementCount: Int) {
        // ⭐️ [FOOTNOTE_DEBUG] 关键日志：谁调用了 updateFootnotes
        mdLog("[FOOTNOTE_DEBUG] 🚨 updateFootnotes CALLED! count=\(footnotes.count), isRealStreamingMode=\(isRealStreamingMode), isStreaming=\(isStreaming)")
        // 调用栈仅用于调试。Release 下连捕获和字符串拼接也必须完全移除。
        #if DEBUG
        if mdVerboseLoggingEnabled {
            let callStack = Thread.callStackSymbols.prefix(8).joined(separator: "\n")
            mdLog("[FOOTNOTE_DEBUG] 📚 Call stack:\n\(callStack)")
        }
        #endif

        // ⚡️ 使用无动画更新，避免闪烁
        UIView.performWithoutAnimation {
            // 此时 contentStackView 的 subviews 数量应该是 newElementCount (如果不含脚注)
            // 先移除旧的脚注视图（如果存在）
            if contentStackView.arrangedSubviews.count > newElementCount {
                contentStackView.arrangedSubviews.last?.removeFromSuperview()
            }

            // 立即添加新的脚注视图（在同一个动画块中，避免中间状态显示）
            if !footnotes.isEmpty {
                let footnoteView = createFootnoteView(footnotes: footnotes, width: width)
                contentStackView.addArrangedSubview(footnoteView)

                // 强制立即布局，避免延迟
                footnoteView.layoutIfNeeded()
            }
        }
    }

    func finishUpdate(newElements: [MarkdownRenderElement], startTime: Double, isBatchFirstScreen: Bool, perfStartTime: CFAbsoluteTime) {
        // 静态一次性渲染（retainsDiffBaseline == false）不保留 diff 基线，避免整份富文本被 oldElements 重复持有
        oldElements = retainsDiffBaseline ? newElements : []

        // ⚡️ 首屏优化：首屏阶段跳过耗时操作，等离屏渲染完成后再执行
        if !isBatchFirstScreen {
            loadImages()
            invalidateIntrinsicContentSize()
            mdLog("🎬 [Regular/Offscreen] Calling notifyHeightChange() after rendering \(newElements.count) elements")
            notifyHeightChange()

            // 🔍 性能监控：打印首帧时间（常规渲染模式）
            if perfStartTime > 0 {
                let firstFrameTime = (CFAbsoluteTimeGetCurrent() - perfStartTime) * 1000
                let renderTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                mdLog("🎯 [FIRST FRAME] Total: \(String(format: "%.1f", firstFrameTime))ms | Render: \(String(format: "%.1f", renderTime))ms (regular)")
                mdLog("🔍 [Perf] ========================================")
            }
        } else {
            // 首屏阶段：只更新布局，但不通知高度（等添加占位视图后再通知）
            invalidateIntrinsicContentSize()

            // 🔍 性能监控：打印首帧时间（分批渲染首屏）
            if perfStartTime > 0 {
                let firstFrameTime = (CFAbsoluteTimeGetCurrent() - perfStartTime) * 1000
                let renderTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                mdLog("🎯 [FIRST FRAME] Total: \(String(format: "%.1f", firstFrameTime))ms | Render: \(String(format: "%.1f", renderTime))ms (batched)")
                mdLog("🔍 [Perf] ========================================")
            }

            // ⚠️ 注意：首屏不调用 notifyHeightChange()，等占位视图添加后再通知
        }

//        let endTime = CFAbsoluteTimeGetCurrent()
//        let totalDuration = endTime - startTime
//
//        // Only print if it took noticeable time (e.g. > 10ms)
//        if totalDuration > 0.01 && !isBatchFirstScreen {
//             printRenderCosts(totalDuration: totalDuration)
//        }
    }

}
