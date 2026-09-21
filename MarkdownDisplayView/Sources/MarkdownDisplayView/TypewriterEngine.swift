//
//  TypewriterEngine.swift
//  MarkdownDisplayView
//
//  Created by 朱继超 on 12/15/25.
//

import UIKit
import Foundation

/// FIFO storage whose dequeue cost is amortized O(1).
///
/// Keeping a logical head avoids `Array.removeFirst()` shifting every remaining
/// typewriter task. The consumed prefix is compacted only occasionally.
struct TypewriterPendingQueue<Element> {
    private var storage: [Element] = []
    private var head = 0

    var isEmpty: Bool { head >= storage.count }
    var count: Int { storage.count - head }

    mutating func append(_ element: Element) {
        storage.append(element)
    }

    mutating func popFirst() -> Element? {
        guard !isEmpty else { return nil }

        let element = storage[head]
        head += 1

        if head == storage.count {
            storage.removeAll(keepingCapacity: true)
            head = 0
        } else if head >= 64, head * 2 >= storage.count {
            storage.removeFirst(head)
            head = 0
        }

        return element
    }

    func forEach(_ body: (Element) -> Void) {
        guard !isEmpty else { return }
        for index in head..<storage.count {
            body(storage[index])
        }
    }

    func contains(where predicate: (Element) -> Bool) -> Bool {
        guard !isEmpty else { return false }
        return storage[head...].contains(where: predicate)
    }

    mutating func updateEach(_ body: (inout Element) -> Void) {
        guard !isEmpty else { return }
        for index in head..<storage.count {
            body(&storage[index])
        }
    }

    mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        head = 0
    }
}

/// Task-local punctuation classification indexed in UTF-16 coordinates.
///
/// `NSAttributedString.length` and `revealCharacter(upto:)` both use UTF-16
/// offsets. Building this lookup once keeps every animation tick O(1) and avoids
/// mixing those offsets with Swift grapheme-cluster indices.
struct TypewriterPunctuationProfile {
    private static let commaLikeUnits: Set<UInt16> = [0xFF0C, 0x002C, 0x3001] // ， , 、
    private static let sentenceEndUnits: Set<UInt16> = [
        0x3002, // 。
        0xFF01, // ！
        0xFF1F, // ？
        0x0021, // !
        0x003F, // ?
        0x003B, // ;
        0xFF1B, // ；
        0x000A, // newline
        0x2028, // line separator (soft break rendered as a compact line break)
    ]

    private let extraDelays: [Int: TimeInterval]

    init(text: String) {
        var delays: [Int: TimeInterval] = [:]
        delays.reserveCapacity(max(1, text.utf16.count / 16))

        for (offset, codeUnit) in text.utf16.enumerated() {
            if Self.commaLikeUnits.contains(codeUnit) {
                delays[offset] = 0.03
            } else if Self.sentenceEndUnits.contains(codeUnit) {
                delays[offset] = 0.08
            }
        }

        extraDelays = delays
    }

    func extraDelay(atUTF16Offset offset: Int) -> TimeInterval {
        guard offset >= 0 else { return 0 }
        return extraDelays[offset] ?? 0
    }
}

/// Pure, clock-independent state for batching logical typewriter steps into display frames.
/// It intentionally uses UTF-16 offsets because NSAttributedString and TextKit do too.
struct TypewriterFrameSchedule {
    struct AdvanceResult {
        let targetUTF16Offset: Int?
        let completed: Bool
        let logicalStepCount: Int
    }

    let totalUTF16Length: Int
    private(set) var revealedUTF16Offset = 0
    private(set) var isComplete = false
    private var remainingDuration: TimeInterval = 0
    private var hasStarted = false

    init(totalUTF16Length: Int) {
        self.totalUTF16Length = max(0, totalUTF16Length)
    }

    mutating func start(
        charsPerStep: Int,
        delay: (Int) -> TimeInterval
    ) -> AdvanceResult {
        guard !hasStarted, totalUTF16Length > 0 else {
            isComplete = totalUTF16Length == 0
            return AdvanceResult(targetUTF16Offset: nil, completed: isComplete, logicalStepCount: 0)
        }
        hasStarted = true
        let stepStart = revealedUTF16Offset
        revealedUTF16Offset = min(totalUTF16Length, revealedUTF16Offset + max(1, charsPerStep))
        remainingDuration = max(0, delay(stepStart))
        return AdvanceResult(
            targetUTF16Offset: revealedUTF16Offset,
            completed: false,
            logicalStepCount: 1
        )
    }

    mutating func advance(
        elapsed: TimeInterval,
        charsPerStep: Int,
        delay: (Int) -> TimeInterval
    ) -> AdvanceResult {
        guard hasStarted, !isComplete, elapsed.isFinite, elapsed >= 0 else {
            return AdvanceResult(targetUTF16Offset: nil, completed: isComplete, logicalStepCount: 0)
        }

        remainingDuration -= elapsed
        var target: Int?
        var logicalStepCount = 0
        while remainingDuration <= 0, !isComplete {
            let overshoot = -remainingDuration
            if revealedUTF16Offset >= totalUTF16Length {
                isComplete = true
                break
            }

            let stepStart = revealedUTF16Offset
            revealedUTF16Offset = min(
                totalUTF16Length,
                revealedUTF16Offset + max(1, charsPerStep)
            )
            target = revealedUTF16Offset
            logicalStepCount += 1
            remainingDuration = max(0, delay(stepStart)) - overshoot
        }

        return AdvanceResult(
            targetUTF16Offset: target,
            completed: isComplete,
            logicalStepCount: logicalStepCount
        )
    }

    mutating func resetTiming(delay: (Int) -> TimeInterval) {
        guard hasStarted, !isComplete else { return }
        remainingDuration = max(0, delay(revealedUTF16Offset))
    }
}

@available(iOS 15.0, *)
private final class TypewriterDisplayLinkProxy {
    weak var engine: TypewriterEngine?

    init(engine: TypewriterEngine) {
        self.engine = engine
    }

    @objc func displayLinkDidFire(_ displayLink: CADisplayLink) {
        engine?.displayLinkDidFire(displayLink)
    }
}

// MARK: - Typewriter Engine

@available(iOS 15.0, *)
class TypewriterEngine {

    enum LayoutChange {
        case rootBecameVisible(UIView)
        case textHeightChanged(delta: CGFloat)
    }

    enum TaskType {
        case show(UIView)
        case text(MarkdownTextViewTK2)
        case label(UILabel)
        case block(UIView)
    }

    private var taskQueue = TypewriterPendingQueue<TaskType>()
    private var isRunning = false
    private var isPaused = false

    private var watchdogTimer: Timer?
    private var lastFeedTimestamp: CFAbsoluteTime = 0

    /// 任务无进展超过该时长即强制完成
    private static let watchdogTimeout: CFAbsoluteTime = 4.0
    /// 常驻 Timer 的检查周期
    private static let watchdogTickInterval: TimeInterval = 1.0

    // 追踪当前正在执行的任务，以便超时后强制完成
    private var currentTask: TaskType?
    private var currentTaskToken: UUID?
    private var playbackGeneration = 0
    private var currentPunctuationProfile: TypewriterPunctuationProfile?
    private var textFrameSchedule: TypewriterFrameSchedule?
    private var textDisplayLink: CADisplayLink?
    private var textDisplayLinkProxy: TypewriterDisplayLinkProxy?
    private var lastTextFrameTimestamp: CFTimeInterval?

    // 基础耗时
    // ⭐️ 优化：降低基础延迟，加快打字速度
    private var baseDuration: TimeInterval = 0.012  // 从18ms降到12ms

    // ⭐️ 优化：批量显示字符数
    private var charsPerStep: Int = 6  // 每次显示6个字符（从4增加到6）

    // ⭐️ 新增：元素间的额外延迟（块级元素结束后的等待时间）
    private var elementGapDuration: TimeInterval = 0.04  // 从120ms降到40ms

    // ⭐️ 新增：标记上一个任务是否是块级任务（用于判断是否需要添加间隔）
    private var lastTaskWasBlock: Bool = false
    var taskGapScheduler: (TimeInterval, @escaping () -> Void) -> Void = { delay, action in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
    }

    var onComplete: (() -> Void)?
    var onLayoutChange: ((LayoutChange) -> Void)?
    var onOutstandingTaskCountChange: ((Int) -> Void)?
    /// 每次输出内容时的回调（用于震动反馈等）
    var onTypewriterStep: (() -> Void)?

    func updateSpeed(charsPerStep: Int? = nil,
                     baseDuration: TimeInterval? = nil,
                     elementGapDuration: TimeInterval? = nil) {
        if let charsPerStep {
            self.charsPerStep = max(1, charsPerStep)
        }
        if let baseDuration {
            self.baseDuration = max(0.001, baseDuration)
        }
        if let elementGapDuration {
            self.elementGapDuration = max(0, elementGapDuration)
        }
        if case .text = currentTask, var schedule = textFrameSchedule {
            schedule.resetTiming { [weak self] offset in
                self?.calculateDelay(atUTF16Offset: offset) ?? 0
            }
            textFrameSchedule = schedule
            lastTextFrameTimestamp = CACurrentMediaTime()
        }
    }

    func enqueue(view: UIView, isRoot: Bool = true) {
        defer {
            if isRoot { onOutstandingTaskCountChange?(outstandingTaskCount) }
        }
        let atomicIdentifier = view.accessibilityIdentifier ?? ""
        let isCompoundAtomicBlock = atomicIdentifier.hasPrefix("MarkdownAtomicQuote")
            || atomicIdentifier.hasPrefix("MarkdownAtomicDetails")

        // Quote/details descendants are not enqueued as individual text tasks. Resolve
        // append mode's provisional 1pt text height before the whole block is revealed.
        // This runs for both root `.show` and nested `.block` paths.
        if isCompoundAtomicBlock {
            prepareDeferredAppendText(in: view)
        }

        // 完整块只执行根视图的 show：先不占 StackView 高度，轮到它时整块插入并淡入。
        // 普通文本继续递归到 MarkdownTextViewTK2，保持逐字显示。
        let isAtomicRoot = isRoot && atomicIdentifier.hasPrefix("MarkdownAtomic")
        if isRoot {
            // 🆕 根视图初始设为透明，通过 .show 任务渐显
            view.alpha = 0
            taskQueue.append(.show(view))
            mdLog("[TYPEWRITER] 🎬 enqueue root: \(type(of: view)), subviews: \(view.subviews.count)")
        }

        if isAtomicRoot {
            return
        }

        // 1. 文本组件
        if let textView = view as? MarkdownTextViewTK2 {
            mdLog("[TYPEWRITER] ✅ 识别到 MarkdownTextViewTK2, 字符数: \(textView.attributedText?.length ?? 0)")
            textView.prepareForTypewriter()
            taskQueue.append(.text(textView))
            return
        }

        // 2. UILabel
        if let label = view as? UILabel {
            label.alpha = 0
            taskQueue.append(.label(label))
            return
        }

        // 3. UIButton
        if view is UIButton {
            view.alpha = 0
            taskQueue.append(.block(view))
            return
        }

        // 4. StackView 递归
        if let stackView = view as? UIStackView {
            for subview in stackView.arrangedSubviews {
                enqueue(view: subview, isRoot: false)
            }
            return
        }

        // 兼容旧的非 attachment 代码块容器。
        if view.accessibilityIdentifier == "CodeBlockContainer" {
            // 1. 先添加容器显示任务（显示背景色）
            view.alpha = 0
            taskQueue.append(.show(view))
            mdLog("[TYPEWRITER] 🎨 代码块容器: 先显示背景，再递归子视图")

            // 2. 递归处理内部的 MarkdownTextViewTK2
            for subview in view.subviews {
                enqueue(view: subview, isRoot: false)
            }
            return
        }

        // 5. 普通容器递归
        // ⭐️ 合并两个版本：使用前缀匹配（更灵活），并保留脚注容器检查
        // ⭐️ 注意：CodeBlockContainer 不再作为原子块，允许内部 MarkdownTextViewTK2 逐字显示
        let isAtomicBlock = (view is UIImageView) ||
                            (view.accessibilityIdentifier?.hasPrefix("MarkdownAtomic") == true) ||
                            (view.accessibilityIdentifier?.hasPrefix("latex_") == true) ||
                            (view.accessibilityIdentifier == "FootnoteContainer")
        if view.subviews.count > 0 && !isAtomicBlock {
            mdLog("[TYPEWRITER] 📦 递归容器: \(type(of: view)), 子视图数: \(view.subviews.count), 子视图类型: \(view.subviews.map { type(of: $0) })")
            for subview in view.subviews {
                enqueue(view: subview, isRoot: false)
            }
            return
        }

        // 6. 原子 Block
        mdLog("[TYPEWRITER] ⬛️ 原子块: \(type(of: view)), id: \(view.accessibilityIdentifier ?? "nil")")
        view.alpha = 0
        taskQueue.append(.block(view))
    }

    private func prepareDeferredAppendText(in view: UIView) {
        if let textView = view as? MarkdownTextViewTK2 {
            textView.prepareDeferredAppendTextForAtomicDisplay()
            return
        }

        for subview in view.subviews {
            prepareDeferredAppendText(in: subview)
        }
    }

    func start() {
        if !isRunning {
            runNext()
        }
    }

    func stop() {
        playbackGeneration += 1
        isPaused = true
        stopWatchdog()
        invalidateTextDisplayLink()

        // TextView 在入队时已经 prepare；停止播放时必须同时清理当前任务和
        // 尚未执行的文字任务，否则它们会永久保留播放期的高度下限。
        if case .text(let textView) = currentTask {
            textView.finishAppendTypewriterPlayback()
        }
        taskQueue.forEach { task in
            if case .text(let textView) = task {
                textView.finishAppendTypewriterPlayback()
            }
        }

        taskQueue.removeAll()
        isRunning = false
        currentTask = nil
        currentTaskToken = nil
        currentPunctuationProfile = nil
        textFrameSchedule = nil
        lastTaskWasBlock = false  // ⭐️ 重置状态
        onOutstandingTaskCountChange?(0)
    }

    /// ⭐️ 新增：检查 TypewriterEngine 是否已完成（队列为空且不在运行）
    var isIdle: Bool {
        return taskQueue.isEmpty && !isRunning
    }

    var outstandingTaskCount: Int {
        taskQueue.count + (isRunning ? 1 : 0)
    }

    /// ⭐️ 检查视图是否在队列中
    func isViewInQueue(_ view: UIView) -> Bool {
        return taskQueue.contains { task in
            switch task {
            case .show(let v):
                return v === view
            case .text(let tv):
                return tv === view
            case .label(let lbl):
                return lbl === view
            case .block(let bv):
                return bv === view
            }
        }
    }

    /// ⭐️ 替换队列中的视图（替换所有匹配的任务）
    func replaceView(_ oldView: UIView, with newView: UIView) {
        var replacedCount = 0

        taskQueue.updateEach { task in
            switch task {
            case .show(let v):
                if v === oldView {
                    newView.alpha = 0
                    task = .show(newView)
                    replacedCount += 1
                    mdLog("[TYPEWRITER] 🔄 Replaced .show task view")
                }
            case .text(let tv):
                if tv === oldView, let newTv = newView.subviews.compactMap({ $0 as? MarkdownTextViewTK2 }).first ?? (newView as? MarkdownTextViewTK2) {
                    newTv.prepareForTypewriter()
                    task = .text(newTv)
                    replacedCount += 1
                    mdLog("[TYPEWRITER] 🔄 Replaced .text task view")
                }
            case .label(let lbl):
                if lbl === oldView, let newLbl = newView as? UILabel {
                    task = .label(newLbl)
                    replacedCount += 1
                    mdLog("[TYPEWRITER] 🔄 Replaced .label task view")
                }
            case .block(let bv):
                if bv === oldView {
                    newView.alpha = 0
                    task = .block(newView)
                    replacedCount += 1
                    mdLog("[TYPEWRITER] 🔄 Replaced .block task view")
                }
            }
        }

        if replacedCount == 0 {
            mdLog("[TYPEWRITER] ⚠️ View not found in queue for replacement")
        } else {
            mdLog("[TYPEWRITER] ✅ Replaced \(replacedCount) tasks for view")
        }
    }

    private func feedWatchdog() {
        lastFeedTimestamp = CFAbsoluteTimeGetCurrent()
        startWatchdogIfNeeded()
    }

    /// 常驻看门狗：每步只更新时间戳，避免 typeNextCharacter 每 12ms 重建一次 Timer 并注册 RunLoop。
    /// 用 .common mode 注册，保证用户拖动 scrollView 期间（.tracking）仍会触发。
    private func startWatchdogIfNeeded() {
        guard watchdogTimer == nil else { return }

        let timer = Timer(timeInterval: Self.watchdogTickInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            // ⚡️ 超时 4.0 秒，为复杂渲染（如 LaTeX）卡顿留出余量
            guard CFAbsoluteTimeGetCurrent() - self.lastFeedTimestamp > Self.watchdogTimeout else { return }
            mdLog("🐶 [Watchdog] Task timed out, forcing completion...")
            self.forceFinishCurrentTask()
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdogTimer = timer
    }

    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }

    deinit {
        // 常驻 Timer 由 RunLoop 持有，不 invalidate 会在引擎释放后继续空转
        watchdogTimer?.invalidate()
        textDisplayLink?.invalidate()
    }

    /// 超时强制完成当前任务
    func forceFinishCurrentTask() {
        guard let task = currentTask, let token = currentTaskToken else { return }

        invalidateTextDisplayLink()

        switch task {
        case .text(let textView):
            if let len = textView.attributedText?.length {
                let result = textView.revealCharacter(upto: len)
                if result.didChangeHeight {
                    onLayoutChange?(.textHeightChanged(delta: result.heightDelta))
                }
            }
        case .block(let view):
            view.layer.removeAllAnimations()
            view.alpha = 1.0
        case .label(let label):
            label.layer.removeAllAnimations()
            label.alpha = 1.0
        case .show(let view):
            view.layer.removeAllAnimations()
            view.isHidden = false
            view.alpha = 1.0
            onLayoutChange?(.rootBecameVisible(view)) // 强制完成时也要通知
        }

        finishCurrentTask(token: token)
    }

    private func runNext() {
        guard !isRunning, !taskQueue.isEmpty else {
            if taskQueue.isEmpty {
                // 队列空闲，停掉常驻 Timer 避免空转
                stopWatchdog()
                currentTask = nil
                onComplete?()
            }
            return
        }

        isRunning = true
        isPaused = false

        guard let task = taskQueue.popFirst() else { return }
        currentTask = task

        let token = UUID()
        currentTaskToken = token

        feedWatchdog()

        switch task {
        case .show(let view):
            // 🆕 渐显根视图，解决闪烁和突兀感
            view.isHidden = false
            view.alpha = 0

            // ⭐️ 添加日志：追踪视图显示时机
            let viewType = view.accessibilityIdentifier ?? String(describing: type(of: view))
            mdLog("[STREAM] 👁️ 视图开始显示: \(viewType), tag=\(view.tag)")

            // [CODEBLOCK_DEBUG] 特殊日志：追踪代码块显示
            if view.accessibilityIdentifier == "CodeBlockContainer" {
                mdLog("[CODEBLOCK_DEBUG] 🎬 CodeBlock .show task executing: frame=\(view.frame), subviews=\(view.subviews.count)")
            }

            // ⚡️ 关键修复：视图显示后立即通知高度变化
            onLayoutChange?(.rootBecameVisible(view))

            // 注意：.show 是容器/根视图渐显，不触发震动反馈

            let showStartTime = CFAbsoluteTimeGetCurrent()
            UIView.animate(withDuration: 0.15, animations: {
                view.alpha = 1.0
            }) { _ in
                mdLog("[STREAM] 👁️ 视图显示完成: \(viewType), 动画耗时: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - showStartTime) * 1000))ms")
                self.finishCurrentTask(token: token)
            }

        case .block(let view):
            // ⭐️ 添加日志：追踪块级视图显示时机
            let blockViewType = view.accessibilityIdentifier ?? String(describing: type(of: view))
            let now = CFAbsoluteTimeGetCurrent()

            // [CODEBLOCK_DEBUG] 特殊日志：追踪代码块显示
            if view.accessibilityIdentifier == "CodeBlockContainer" {
                mdLog("[CODEBLOCK_DEBUG] 🎬 CodeBlock .block task executing: alpha=\(view.alpha), isHidden=\(view.isHidden), frame=\(view.frame)")
            }

            // 解析时间戳
            // 格式: LatexContainer_<streamStartTime>_<createTime> 或 DetailsContainer_<streamStartTime>_<createTime>
            var delayInfo: String = ""
            if let identifier = view.accessibilityIdentifier {
                let isLatex = identifier.hasPrefix("LatexContainer_")
                let isDetails = identifier.hasPrefix("DetailsContainer_")

                if isLatex || isDetails {
                    let parts = identifier.split(separator: "_")
                    if parts.count >= 3,
                       let streamStart = Double(parts[1]),
                       let createTime = Double(parts[2]),
                       streamStart > 0 {  // 确保是流式模式
                        let totalDelay = (now - streamStart) * 1000  // 从流式开始到显示
                        let queueDelay = (now - createTime) * 1000   // 从创建到显示（排队时间）

                        let label = isLatex ? "【公式上屏】" : "【Details上屏】"
                        delayInfo = "\n    ⏱️ \(label) 从流式开始: \(String(format: "%.1f", totalDelay))ms, 排队等待: \(String(format: "%.1f", queueDelay))ms"
                    }
                }
            }

            mdLog("[STREAM] 📦 块视图开始显示: \(blockViewType), tag=\(view.tag)\(delayInfo)")
            let blockStartTime = now

            UIView.animate(withDuration: 0.2, animations: {
                view.alpha = 1.0
            }, completion: { [weak self] _ in
                mdLog("[STREAM] 📦 块视图显示完成: \(blockViewType), 动画耗时: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - blockStartTime) * 1000))ms")
                // 块级元素动画完成时触发震动反馈
                self?.onTypewriterStep?()
                self?.finishCurrentTask(token: token)
            })

        case .label(let label):
            // 注意：.label 是小元素，不触发震动反馈
            UIView.animate(withDuration: 0.1, animations: {
                label.alpha = 1.0
            }, completion: { _ in
                self.finishCurrentTask(token: token)
            })

        case .text(let textView):
            let textSnapshot = textView.attributedText ?? NSAttributedString()
            let plainTextSnapshot = textSnapshot.string
            let textLen = textSnapshot.length
            let textPreview = plainTextSnapshot.prefix(30)
            mdLog("[TYPEWRITER] 📝 开始执行 .text 任务, 文本长度: \(textLen), 内容: \(textPreview)...")
            currentPunctuationProfile = TypewriterPunctuationProfile(text: plainTextSnapshot)
            if textLen == 0 {
                _ = textView.revealCharacter(upto: 0)
                finishCurrentTask(token: token)
            } else {
                startTextDisplayLinkTask(textView, textLength: textLen, token: token)
            }
        }
    }

    private func startTextDisplayLinkTask(
        _ textView: MarkdownTextViewTK2,
        textLength: Int,
        token: UUID
    ) {
        invalidateTextDisplayLink()
        var schedule = TypewriterFrameSchedule(totalUTF16Length: textLength)
        let initial = schedule.start(charsPerStep: charsPerStep) { [weak self] offset in
            self?.calculateDelay(atUTF16Offset: offset) ?? 0
        }
        textFrameSchedule = schedule
        if let target = initial.targetUTF16Offset {
            revealText(textView, upto: target)
        }

        guard currentTaskToken == token, !initial.completed else {
            finishCurrentTask(token: token)
            return
        }

        let proxy = TypewriterDisplayLinkProxy(engine: self)
        let displayLink = CADisplayLink(target: proxy, selector: #selector(TypewriterDisplayLinkProxy.displayLinkDidFire(_:)))
        displayLink.preferredFramesPerSecond = 30
        textDisplayLinkProxy = proxy
        textDisplayLink = displayLink
        lastTextFrameTimestamp = CACurrentMediaTime()
        displayLink.add(to: .main, forMode: .common)
    }

    fileprivate func displayLinkDidFire(_ displayLink: CADisplayLink) {
        handleTextFrame(timestamp: displayLink.timestamp)
    }

    func handleTextFrame(timestamp: CFTimeInterval) {
        guard !isPaused,
              let token = currentTaskToken,
              case .text(let textView) = currentTask,
              var schedule = textFrameSchedule,
              let previousTimestamp = lastTextFrameTimestamp else { return }
        let elapsed = timestamp - previousTimestamp
        guard elapsed.isFinite, elapsed >= 0 else {
            lastTextFrameTimestamp = timestamp
            return
        }
        lastTextFrameTimestamp = timestamp
        let frame = schedule.advance(elapsed: elapsed, charsPerStep: charsPerStep) { [weak self] offset in
            self?.calculateDelay(atUTF16Offset: offset) ?? 0
        }
        textFrameSchedule = schedule

        if let target = frame.targetUTF16Offset {
            revealText(textView, upto: target)
            feedWatchdog()
        }
        if frame.completed {
            invalidateTextDisplayLink()
            finishCurrentTask(token: token)
        }
    }

    func advanceTextFrame(by elapsed: TimeInterval) {
        guard let lastTextFrameTimestamp else { return }
        handleTextFrame(timestamp: lastTextFrameTimestamp + max(0, elapsed))
    }

    private func revealText(_ textView: MarkdownTextViewTK2, upto target: Int) {
        let revealResult = textView.revealCharacter(upto: target)
        guard revealResult.didReveal else { return }
        if revealResult.didChangeHeight {
            onLayoutChange?(.textHeightChanged(delta: revealResult.heightDelta))
        }
        onTypewriterStep?()
    }

    private func invalidateTextDisplayLink() {
        textDisplayLink?.invalidate()
        textDisplayLink = nil
        textDisplayLinkProxy = nil
        lastTextFrameTimestamp = nil
    }

    var hasActiveTextDisplayLink: Bool { textDisplayLink != nil }

    private func finishCurrentTask(token: UUID) {
        guard currentTaskToken == token else { return }
        // 任务间隔（elementGapDuration）不应计入超时，这里刷新时间戳而非停表；
        // 队列真正空了由 runNext 停掉常驻 Timer。
        lastFeedTimestamp = CFAbsoluteTimeGetCurrent()

        // ⭐️ 记录当前任务类型，用于判断是否需要添加间隔
        let isBlockTask: Bool
        if let task = currentTask {
            switch task {
            case .block, .show:
                isBlockTask = true
            case .text, .label:
                isBlockTask = false
            }
        } else {
            isBlockTask = false
        }
        lastTaskWasBlock = isBlockTask

        if Thread.isMainThread {
            self._finish(token: token)
        } else {
            DispatchQueue.main.async { self._finish(token: token) }
        }
    }

    private func _finish(token: UUID) {
        guard currentTaskToken == token else { return }
        // 正常完成、空文本和 watchdog 强制完成最终都会汇聚到主线程的这里。
        // 此时最后一次字符测高已经结束，可以解除播放期的单调高度保护。
        if case .text(let textView) = currentTask {
            textView.finishAppendTypewriterPlayback()
        }
        invalidateTextDisplayLink()
        textFrameSchedule = nil
        currentPunctuationProfile = nil
        currentTaskToken = nil
        currentTask = nil

        isRunning = false
        onOutstandingTaskCountChange?(outstandingTaskCount)
        // ⭐️ 优化：如果上一个任务是块级任务，添加额外延迟，让元素之间有明显间隔
        if lastTaskWasBlock && !taskQueue.isEmpty {
            let generation = playbackGeneration
            taskGapScheduler(elementGapDuration) { [weak self] in
                guard let self, self.playbackGeneration == generation else { return }
                self.runNext()
            }
        } else {
            runNext()
        }
    }

    private func calculateDelay(atUTF16Offset offset: Int) -> TimeInterval {
        baseDuration
            + (currentPunctuationProfile?.extraDelay(atUTF16Offset: offset) ?? 0)
            + Double.random(in: 0...0.005)
    }
}
