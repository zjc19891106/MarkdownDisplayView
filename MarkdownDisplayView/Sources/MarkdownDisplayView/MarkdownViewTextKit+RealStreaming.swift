//
//  MarkdownViewTextKit+RealStreaming.swift
//  MarkdownDisplayView
//
//  Mechanical extension split from MarkdownDisplayView.swift.
//

import UIKit
import Foundation

@available(iOS 15.0, *)
extension MarkdownViewTextKit {
    // MARK: - 智能流式

    /// 开始智能流式模式
    /// - Parameter autoScrollBottom: 是否自动滚动到底部
    public func beginRealStreaming(autoScrollBottom: Bool = true) {
        mdLog("[FOOTNOTE_DEBUG] 🟢 beginRealStreaming called")

        // 停止任何现有流式
        resetForReuse()

        // Cell 可能刚在 configure 中调度过普通 Markdown 渲染。进入真流式前必须
        // 同时取消尚未执行的任务，并让已经在后台解析的结果失效，禁止其回写流式 UI。
        renderWorkItem?.cancel()
        renderWorkItem = nil
        offscreenRenderWorkItem?.cancel()
        offscreenRenderWorkItem = nil
        renderVersionLock.lock()
        renderVersion += 1
        renderVersionLock.unlock()

        // 初始化真流式状态
        isRealStreamingMode = true
        isStreaming = true
        mdLog("[FOOTNOTE_DEBUG] 🟢 isRealStreamingMode set to TRUE")
        autoScrollEnabled = autoScrollBottom
        userScrolledAway = false
        realStreamParsedElementCount = 0
        realStreamRenderGeneration += 1
        pendingRealStreamElements.removeAll()
        realStreamRenderPumpScheduled = false
        realStreamParseInFlightCount = 0
        pendingSmartStreamModules.removeAll()
        smartStreamParseActive = false
        realStreamDrainCompletion = nil
        isEndingRealStream = false
        realStreamBackpressureActive = false
        realStreamNextModuleSequence = 0
        realStreamHeightAccumulator.reset(
            verticalMargins: contentStackView.layoutMargins.top + contentStackView.layoutMargins.bottom
        )
        lastReportedHeight = 0
        invalidateIntrinsicHeightCache()
        invalidateIntrinsicContentSize()
        pendingKnownStreamingHeight = nil
        pendingRequiresFullHeightMeasurement = false
        heightNotificationGeneration += 1
        heightNotificationScheduled = false
        pendingForcedHeightNotification = false
        streamPerformanceDiagnostics.begin(generation: realStreamRenderGeneration)

        // 清空现有内容
        markdown = ""
        oldElements = []
        contentStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        headingViews.removeAll()
        tocSectionView = nil
        tableOfContents.removeAll()
        tocSectionId = nil
        imageAttachments.removeAll()

        // 重置 TypewriterEngine
        typewriterEngine.stop()

        // 重置 StreamBuffer，由它自动识别完整 Markdown 模块。
        streamBuffer.reset()
        streamBuffer.updateContainerWidth(bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width - 32)

        // ⭐️ 修复：启动等待检测，而不是直接显示等待动画
        // 等待动画只在 TypewriterEngine 空闲且一段时间无数据到达时显示
        startWaitingDetection()

        // 准备震动反馈
        prepareHapticFeedback()

        // 记录开始时间
        streamingStartTimestamp = CFAbsoluteTimeGetCurrent()

        mdLog("🎬 [RealStream] Started smart streaming mode")
    }

    /// ⭐️ 新 API：追加流式数据（智能缓存模式）
    /// 自动检测完整模块并渲染，无需外部预分割
    /// - Parameter data: 网络到达的原始文本数据
    public func appendStreamData(_ data: String) {
        // 该方法会同步阻塞调用方并直接改动视图层级，必须在主线程调用
        dispatchPrecondition(condition: .onQueue(.main))

        guard isRealStreamingMode else {
            mdLog("⚠️ [RealStream] Not in real streaming mode, call beginRealStreaming() first")
            return
        }
        guard !isEndingRealStream else { return }

        // ⭐️ 标记收到新数据，用于等待动画检测
        markDataReceived()

        mdLog("📥 [SmartBuffer] Received data: \(data.count) chars")
        if MarkdownStreamPerformanceDiagnostics.enabled {
            streamPerformanceDiagnostics.recordReceive(characters: data.count)
        }

        // 原样累计网络 delta。StreamBuffer 只决定渲染边界，不得改写最终 Markdown。

        // 使用 StreamBuffer 检测完整模块
        let result = streamBuffer.append(data)

        // 串行后台队列保持模块顺序，同时避免 Markdown 解析阻塞主线程。
        if !result.completeModules.isEmpty {
            for (index, moduleText) in result.completeModules.enumerated() {
                mdLog("📦 [SmartBuffer] Processing module \(index + 1)/\(result.completeModules.count): \(moduleText.prefix(50))...")
                enqueueSmartStreamModule(moduleText)
            }
        }

        // 如果有未完成的结构，日志记录
        if result.hasPendingStructure, let pending = result.pendingType {
            mdLog("⏳ [SmartBuffer] Waiting for \(pending.rawValue) to close...")
        }
    }

    /// 串行后台解析模块。renderQueue 保证完成顺序与输入顺序一致；UIKit 更新只回到主线程执行。
    func enqueueSmartStreamModule(_ moduleText: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isRealStreamingMode else { return }

        realStreamParseInFlightCount += 1
        let moduleSequence = realStreamNextModuleSequence
        realStreamNextModuleSequence += 1
        renderVersionLock.lock()
        let currentRenderVersion = renderVersion
        renderVersionLock.unlock()
        pendingSmartStreamModules.append(PendingSmartStreamModule(
            text: moduleText,
            renderVersion: currentRenderVersion,
            renderGeneration: realStreamRenderGeneration,
            sequence: moduleSequence
        ))
        streamPerformanceDiagnostics.recordModuleQueued(
            pendingModules: realStreamParseInFlightCount
        )
        startNextSmartStreamParseIfPossible()
    }

    func startNextSmartStreamParseIfPossible() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isRealStreamingMode,
              !smartStreamParseActive,
              !realStreamBackpressureActive,
              pendingRealStreamElements.count < realStreamTypewriterHighWatermark * 2,
              let module = pendingSmartStreamModules.popFirst() else { return }

        smartStreamParseActive = true
        let containerWidth = currentContainerWidthForParsing()
        let config = configuration

        renderQueue.async { [weak self] in
            guard let self else { return }
            self.renderVersionLock.lock()
            let isCurrentVersion = self.renderVersion == module.renderVersion
            self.renderVersionLock.unlock()
            guard isCurrentVersion else { return }

            let parseStart = CFAbsoluteTimeGetCurrent()
            let (processedText, _) = self.preprocessFootnotes(module.text)
            let renderer = MarkdownRenderer(configuration: config, containerWidth: containerWidth)
            let result = renderer.render(processedText)
            let parseDuration = (CFAbsoluteTimeGetCurrent() - parseStart) * 1000

            DispatchQueue.main.async { [weak self] in
                guard let self, module.renderGeneration == self.realStreamRenderGeneration else { return }
                self.smartStreamParseActive = false
                self.realStreamParseInFlightCount = max(0, self.realStreamParseInFlightCount - 1)
                guard self.isRealStreamingMode else { return }

                let (parsedElements, attachments, parsedTOCItems, parsedTOCId) = result
                let (elements, tocItems, tocId) = self.rebaseRealStreamHeadingIDs(
                    elements: parsedElements,
                    tocItems: parsedTOCItems,
                    tocSectionId: parsedTOCId
                )
                let previousElementCount = self.realStreamParsedElementCount
                self.realStreamParsedElementCount += elements.count
                self.imageAttachments.append(contentsOf: attachments)
                self.tableOfContents.append(contentsOf: tocItems)
                if let tocId { self.tocSectionId = tocId }

                mdLog("✅ [SmartBuffer] Parsed module: \(elements.count) elements, parse: \(String(format: "%.1f", parseDuration))ms, UI backlog: \(self.pendingRealStreamElements.count), typewriter: \(self.typewriterEngine.outstandingTaskCount)")
                self.streamPerformanceDiagnostics.recordModuleParsed(
                    sequence: module.sequence,
                    durationMS: parseDuration,
                    elements: elements.count,
                    pendingModules: self.realStreamParseInFlightCount,
                    pendingViews: self.pendingRealStreamElements.count,
                    typewriter: self.typewriterEngine.outstandingTaskCount
                )
                if !elements.isEmpty {
                    self.displayRealStreamElements(
                        elements,
                        startIndex: previousElementCount,
                        moduleSequence: module.sequence
                    )
                }
                self.startNextSmartStreamParseIfPossible()
                self.tryFinishRealStreamDrain()
            }
        }
    }

    /// 每个完整模块都会使用新的 MarkdownParser，局部标题 ID 会从 heading-0 重新开始。
    /// 合并模块前将标题及 TOC ID 重定位到当前文档的全局序号，避免 headingViews 被覆盖。
    func rebaseRealStreamHeadingIDs(
        elements: [MarkdownRenderElement],
        tocItems: [MarkdownTOCItem],
        tocSectionId: String?
    ) -> (elements: [MarkdownRenderElement], tocItems: [MarkdownTOCItem], tocSectionId: String?) {
        let offset = tableOfContents.count
        let idMap = Dictionary(uniqueKeysWithValues: tocItems.enumerated().map { index, item in
            (item.id, "heading-\(offset + index)")
        })

        func remap(_ element: MarkdownRenderElement) -> MarkdownRenderElement {
            switch element {
            case .heading(let id, let text):
                return .heading(id: idMap[id] ?? id, text: text)
            case .quote(let children, let level):
                return .quote(children: children.map(remap), level: level)
            case .details(let summary, let children):
                return .details(summary: summary, children: children.map(remap))
            case .list(let items, let level):
                let remappedItems = items.map { item in
                    ListNodeItem(marker: item.marker, children: item.children.map(remap))
                }
                return .list(items: remappedItems, level: level)
            default:
                return element
            }
        }

        let rebasedTOCItems = tocItems.enumerated().map { index, item in
            MarkdownTOCItem(level: item.level, title: item.title, id: "heading-\(offset + index)")
        }

        return (
            elements.map(remap),
            rebasedTOCItems,
            tocSectionId.flatMap { idMap[$0] }
        )
    }

    /// 显示智能流式新增的元素
    func displayRealStreamElements(
        _ elements: [MarkdownRenderElement],
        startIndex: Int,
        moduleSequence: Int
    ) {
        for (index, element) in elements.enumerated() {
            pendingRealStreamElements.append(PendingRealStreamElement(
                element: element,
                globalIndex: startIndex + index,
                moduleSequence: moduleSequence
            ))
        }
        scheduleRealStreamRenderPump()
    }

    func scheduleRealStreamRenderPump() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isRealStreamingMode,
              !pendingRealStreamElements.isEmpty,
              !realStreamRenderPumpScheduled else {
            tryFinishRealStreamDrain()
            return
        }

        if enableTypewriterEffect,
           typewriterEngine.outstandingTaskCount >= realStreamTypewriterHighWatermark {
            realStreamBackpressureActive = true
            mdLog("⏸️ [SmartBuffer] UI backpressure: typewriter=\(typewriterEngine.outstandingTaskCount), pendingViews=\(pendingRealStreamElements.count)")
            return
        }

        realStreamRenderPumpScheduled = true
        let generation = realStreamRenderGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60.0) { [weak self] in
            guard let self else { return }
            self.realStreamRenderPumpScheduled = false
            guard generation == self.realStreamRenderGeneration, self.isRealStreamingMode else { return }
            self.processRealStreamRenderFrame()
        }
    }

    func processRealStreamRenderFrame() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isRealStreamingMode else { return }

        if isShowingWaitingIndicator { hideWaitingIndicator() }

        let frameStart = CACurrentMediaTime()
        let containerWidth = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width - 32
        var createdCount = 0

        repeat {
            guard let item = pendingRealStreamElements.popFirst() else { break }
            guard item.globalIndex <= oldElements.count else {
                assertionFailure("Real-stream element order gap: expected at most \(oldElements.count), got \(item.globalIndex)")
                mdLog("❌ [SmartBuffer] Dropped out-of-order UI element: expected<=\(oldElements.count), actual=\(item.globalIndex)")
                break
            }
            let createStart = CFAbsoluteTimeGetCurrent()
            let duplicateElement = item.globalIndex < oldElements.count
            if duplicateElement, MarkdownStreamPerformanceDiagnostics.enabled {
                streamPerformanceDiagnostics.recordDuplicateElement(
                    sequence: item.moduleSequence,
                    index: item.globalIndex,
                    type: elementTypeString(item.element)
                )
            }
            let view = createView(for: item.element, containerWidth: containerWidth)
            let createDuration = (CFAbsoluteTimeGetCurrent() - createStart) * 1000
            view.tag = 1000 + item.globalIndex

            if enableTypewriterEffect {
                view.isHidden = true
                contentStackView.addArrangedSubview(view)
                typewriterEngine.enqueue(view: view)
            } else {
                contentStackView.addArrangedSubview(view)
            }

            if case .heading(let id, _) = item.element {
                headingViews[id] = view
                if id == tocSectionId { tocSectionView = view }
            }

            if item.globalIndex == oldElements.count {
                oldElements.append(item.element)
            } else {
                oldElements[item.globalIndex] = item.element
            }

            createdCount += 1
            if MarkdownStreamPerformanceDiagnostics.enabled {
                streamPerformanceDiagnostics.recordViewCreated(
                    sequence: item.moduleSequence,
                    index: item.globalIndex,
                    type: elementTypeString(item.element),
                    durationMS: createDuration
                )
            }
            mdLog("⚙️ [SmartBuffer] View created: index=\(item.globalIndex), type=\(elementTypeString(item.element)), cost=\(String(format: "%.1f", createDuration))ms")

            if enableTypewriterEffect,
               typewriterEngine.outstandingTaskCount >= realStreamTypewriterHighWatermark {
                realStreamBackpressureActive = true
                break
            }
        } while CACurrentMediaTime() - frameStart < realStreamFrameBudget

        if enableTypewriterEffect, createdCount > 0 {
            typewriterEngine.start()
        }

        if createdCount > 0 {
            // 打字机模式下新 View 仍是 hidden，不会改变可见高度；真正 show/文字增高时
            // TypewriterEngine.onLayoutChange 会统一触发测高。这里提前测只会空跑整棵布局树。
            if !enableTypewriterEffect {
                scheduleHeightChangeNotification()
            }
            handleAutoScroll()
            mdLog("⚙️ [SmartBuffer] UI frame: created=\(createdCount), cost=\(String(format: "%.1f", (CACurrentMediaTime() - frameStart) * 1000))ms, pendingViews=\(pendingRealStreamElements.count), typewriter=\(typewriterEngine.outstandingTaskCount)")
        }

        streamPerformanceDiagnostics.recordRenderFrame(
            durationMS: (CACurrentMediaTime() - frameStart) * 1000,
            created: createdCount,
            pendingModules: realStreamParseInFlightCount,
            pendingViews: pendingRealStreamElements.count,
            typewriter: typewriterEngine.outstandingTaskCount,
            arrangedSubviews: contentStackView.arrangedSubviews.count
        )

        if !realStreamBackpressureActive { scheduleRealStreamRenderPump() }
        startNextSmartStreamParseIfPossible()
        tryFinishRealStreamDrain()
    }

    /// 结束真流式模式
    /// - Parameter completion: 完成回调，在 TypewriterEngine 完全结束且脚注渲染完毕后触发
    public func endRealStreaming(completion: (() -> Void)? = nil) {
        mdLog("[FOOTNOTE_DEBUG] 🔴 endRealStreaming called, isRealStreamingMode=\(isRealStreamingMode)")
        guard isRealStreamingMode else {
            completion?()
            return
        }
        guard !isEndingRealStream else { return }
        isEndingRealStream = true

        mdLog("🎉 [RealStream] Ending real streaming mode")

        // ⭐️ 停止等待检测定时器
        stopWaitingDetection()

        // ⭐️ 隐藏等待动画
        hideWaitingIndicator()

        // 处理缓冲区中剩余的未完成内容。
        let remainingText = streamBuffer.flush()
        if !remainingText.isEmpty {
            mdLog("📦 [SmartBuffer] Flushing remaining content: \(remainingText.prefix(50))...")
            enqueueSmartStreamModule(remainingText)
        }

        // 更新 markdown 属性（用于后续非流式访问）
        markdown = streamBuffer.getFullText()

        // ⚠️ 解析脚注，但延迟到 TypewriterEngine 完成后再渲染
        let (_, footnotes) = preprocessFootnotes(streamBuffer.getFullText())
        mdLog("[FOOTNOTE_DEBUG] 🔴 endRealStreaming parsed \(footnotes.count) footnotes, will defer rendering")

        // ⭐️ 关键修复：保存脚注和完成回调，等待 TypewriterEngine 完成后统一处理
        let pendingFootnotes = footnotes
        let externalCompletion = completion

        // 定义收尾逻辑
        let finishBlock: () -> Void = { [weak self] in
            guard let self = self else {
                externalCompletion?()
                return
            }

            mdLog("[FOOTNOTE_DEBUG] 🔴 finishBlock executing, rendering \(pendingFootnotes.count) footnotes")

            let completedElements = self.oldElements
            let containerWidth = self.bounds.width > 0
                ? self.bounds.width
                : UIScreen.main.bounds.width - 32

            // drain 屏障已保证所有 element 都已经显示并完成布局。先退出
            // streaming 分支，再用现有 elements / root views 原地转为静态视口。
            self.isRealStreamingMode = false
            self.isStreaming = false
            self.stopHapticFeedback()
            mdLog("[FOOTNOTE_DEBUG] 🔴 isRealStreamingMode set to FALSE")

            let promoted = self.promoteCompletedStreamToViewportWindow(
                elements: completedElements,
                footnotes: pendingFootnotes,
                containerWidth: containerWidth
            )
            if !promoted, !pendingFootnotes.isEmpty {
                self.updateFootnotes(
                    pendingFootnotes,
                    width: containerWidth,
                    newElementCount: completedElements.count
                )
                mdLog("📝 [RealStream] Processed \(pendingFootnotes.count) footnotes at end")
            }

            // promotion 保持完整结构高度；脚注若新增高度也只在这里合并通知一次。
            self.notifyHeightChange(force: true)

            self.streamPerformanceDiagnostics.end(
                pendingModules: self.realStreamParseInFlightCount,
                pendingViews: self.pendingRealStreamElements.count,
                typewriter: self.typewriterEngine.outstandingTaskCount,
                arrangedSubviews: self.contentStackView.arrangedSubviews.count
            )

            // 触发结束阶段传入的完成回调。
            externalCompletion?()

            let elapsed = (CFAbsoluteTimeGetCurrent() - self.streamingStartTimestamp) * 1000
            mdLog("✅ [RealStream] Completed in \(String(format: "%.1f", elapsed))ms")
            mdLog("Full text is:\n\(self.streamBuffer.getFullText())")

            // 释放流式缓冲区的全文（markdown 已持有全文，buffer 不再需要）
            self.streamBuffer.reset()
        }

        realStreamDrainCompletion = finishBlock
        scheduleRealStreamRenderPump()
        tryFinishRealStreamDrain()
    }

    func tryFinishRealStreamDrain() {
        guard let completion = realStreamDrainCompletion,
              realStreamParseInFlightCount == 0,
              pendingRealStreamElements.isEmpty,
              !realStreamRenderPumpScheduled,
              typewriterEngine.isIdle else { return }

        realStreamDrainCompletion = nil
        completion()
    }

    /// 向上查找宿主 UIScrollView
    func findEnclosingScrollView() -> UIScrollView? {
        var superview = self.superview
        while let current = superview {
            if let sv = current as? UIScrollView { return sv }
            superview = current.superview
        }
        return nil
    }

    /// 滚动到底部
    public func scrollToBottom(animated: Bool = true) {
        guard let sv = findEnclosingScrollView() else { return }

        let bottomOffset = CGPoint(
            x: 0,
            y: max(0, sv.contentSize.height - sv.bounds.height + sv.contentInset.bottom)
        )
        sv.setContentOffset(bottomOffset, animated: animated)
    }

    /// 滚动到顶部
    public func scrollToTop(animated: Bool = true) {
        guard let sv = findEnclosingScrollView() else { return }
        sv.setContentOffset(CGPoint(x: 0, y: -sv.contentInset.top), animated: animated)
    }
    
}
