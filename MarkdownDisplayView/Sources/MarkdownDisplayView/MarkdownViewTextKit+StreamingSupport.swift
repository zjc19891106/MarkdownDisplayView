//
//  MarkdownViewTextKit+StreamingSupport.swift
//  MarkdownDisplayView
//
//  Helpers shared by real fragment streaming and reusable views.
//

import UIKit
import Foundation

@available(iOS 15.0, *)
extension MarkdownViewTextKit {
    // MARK: - Auto Scroll

    func handleAutoScroll() {
        guard autoScrollEnabled else { return }

        autoScrollWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.autoScrollToBottomIfAppropriate()
        }
        autoScrollWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    /// 仅在用户未接管滚动、且视图仍贴近底部时才滚动
    func autoScrollToBottomIfAppropriate() {
        guard autoScrollEnabled, let sv = findEnclosingScrollView() else { return }

        // 用户手指在屏幕上或惯性滚动中：视为接管，不再抢夺
        if sv.isDragging || sv.isTracking || sv.isDecelerating {
            userScrolledAway = true
            return
        }

        let distance = distanceFromBottom(sv)

        if distance <= Self.autoScrollBottomTolerance {
            // 已贴回底部，恢复跟随
            userScrolledAway = false
        } else if userScrolledAway {
            return
        } else if distance > max(Self.autoScrollBottomTolerance, sv.bounds.height * 0.5) {
            // 拖拽在两次流式更新之间结束、且无惯性时 isDragging/isDecelerating 都已复位，
            // 此处用距离兜底：单次流式更新的内容增量不应造成半屏以上的偏离
            userScrolledAway = true
            return
        }

        scrollToBottom(animated: false)
    }

    /// 当前偏移距底部的距离
    func distanceFromBottom(_ sv: UIScrollView) -> CGFloat {
        let maxOffsetY = max(0, sv.contentSize.height - sv.bounds.height + sv.contentInset.bottom)
        return maxOffsetY - sv.contentOffset.y
    }

    /// 用于可复用场景（如 UITableViewCell）重置渲染与真实流式状态
    public func resetForReuse() {
        teardownViewportWindow()
        renderWorkItem?.cancel()
        offscreenRenderWorkItem?.cancel()
        lastPreparedContentSignature = nil
        // 下面会清空 contentStackView，本轮及之后若干次测高都会得到 0。
        // 屏蔽这段中间态的 0 高度上报，等重渲染出真实高度再通知宿主，
        // 否则宿主按 0 重排行高会把可见 Cell 推倒重来，反过来又触发 reset。
        suppressesZeroHeightNotification = true
        autoScrollWorkItem?.cancel()
        autoScrollWorkItem = nil
        userScrolledAway = false
        waitingDetectionTimer?.invalidate()
        waitingDetectionTimer = nil
        waitingAnimationTimer?.invalidate()
        waitingAnimationTimer = nil
        isShowingWaitingIndicator = false
        waitingIndicatorView.removeFromSuperview()

        renderVersionLock.lock()
        renderVersion += 1
        renderVersionLock.unlock()

        isStreaming = false
        isRealStreamingMode = false
        realStreamRenderGeneration += 1
        pendingRealStreamElements.removeAll()
        realStreamRenderPumpScheduled = false
        realStreamParseInFlightCount = 0
        pendingSmartStreamModules.removeAll()
        smartStreamParseActive = false
        realStreamDrainCompletion = nil
        isEndingRealStream = false
        realStreamBackpressureActive = false
        heightNotificationScheduled = false
        pendingForcedHeightNotification = false
        pendingKnownStreamingHeight = nil
        pendingRequiresFullHeightMeasurement = false
        heightNotificationGeneration += 1
        realStreamHeightAccumulator.reset(verticalMargins: 0)
        // ⚠️ 不复位 lastReportedHeight：Cell 复用后重渲染相同内容时，
        // 高度应与上一次一致，若归零会把“0→实际高度”误判为大变化，
        // 从而触发 onHeightChange → performBatchUpdates → cell 复用 → 重渲染的循环。
        invalidateIntrinsicHeightCache()
        invalidateIntrinsicContentSize()
        lastHeightNotificationTimestamp = 0
        lastLayoutWidthForHeightMeasurement = 0

        oldElements = []
        retainsDiffBaseline = true
        headingViews.removeAll()
        tocSectionView = nil
        tocSectionId = nil
        tableOfContents = []
        imageAttachments = []

        typewriterEngine.stop()
        streamBuffer.reset()
        contentStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // 必须放在 renderVersion 自增与 contentStackView 清空之后。
        // markdown 的 didSet 里有 `guard oldValue != markdown`：若不清空，Cell 复用后
        // 被赋予同一段 markdown 会直接早退不渲染，而内容已被上面清光，结果是空白 Cell。
        // 同时这里会触发一次 scheduleRerender()，放在末尾可保证它排队时拿到的是新版本号；
        // 紧接着取消该任务，避免为空串白跑一轮渲染。
        markdown = ""
        renderWorkItem?.cancel()
        renderWorkItem = nil

        setNeedsLayout()
        layoutIfNeeded()
    }

    // MARK: - 等待动画控制

    /// ⭐️ 启动等待检测（在真流式开始时调用）
    func startWaitingDetection() {
        stopWaitingDetection()
        lastDataReceivedTime = CFAbsoluteTimeGetCurrent()

        // 每 0.2 秒检测一次是否需要显示等待动画
        waitingDetectionTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.checkAndUpdateWaitingIndicator()
        }
    }

    /// ⭐️ 停止等待检测
    func stopWaitingDetection() {
        waitingDetectionTimer?.invalidate()
        waitingDetectionTimer = nil
    }

    /// ⭐️ 检测并更新等待动画状态
    /// 只有当 TypewriterEngine 空闲且超过延迟时间未收到新数据时才显示
    func checkAndUpdateWaitingIndicator() {
        guard isRealStreamingMode else {
            hideWaitingIndicator()
            return
        }

        let now = CFAbsoluteTimeGetCurrent()
        let timeSinceLastData = now - lastDataReceivedTime
        let hasRenderBacklog = realStreamParseInFlightCount > 0 || !pendingRealStreamElements.isEmpty || realStreamRenderPumpScheduled
        let isEngineIdle = typewriterEngine.isIdle && !hasRenderBacklog

        // ⭐️ 调试日志
        mdLog("[WaitingIndicator] 检测: isEngineIdle=\(isEngineIdle), renderBacklog=\(hasRenderBacklog), timeSinceLastData=\(String(format: "%.2f", timeSinceLastData))s, delay=\(waitingIndicatorDelay)s, isShowing=\(isShowingWaitingIndicator)")

        // ⭐️ 核心逻辑：只有当 TypewriterEngine 空闲且超过延迟时间未收到数据时才显示
        if isEngineIdle && timeSinceLastData > waitingIndicatorDelay {
            if !isShowingWaitingIndicator {
                mdLog("[WaitingIndicator] ✅ 条件满足，显示等待动画")
                showWaitingIndicator()
            }
        } else {
            if isShowingWaitingIndicator {
                hideWaitingIndicator()
            }
        }
    }

    /// ⭐️ 标记收到新数据（在 appendStreamData 时调用）
    func markDataReceived() {
        lastDataReceivedTime = CFAbsoluteTimeGetCurrent()
        // 收到数据时立即隐藏等待动画
        if isShowingWaitingIndicator {
            hideWaitingIndicator()
        }
    }

    // MARK: - 流式输出震动反馈

    /// 准备震动反馈生成器（在流式开始时调用）
    func prepareHapticFeedback() {
        guard configuration.streamingHapticFeedbackStyle != .none else { return }

        if let style = configuration.streamingHapticFeedbackStyle.impactStyle {
            hapticFeedbackGenerator = UIImpactFeedbackGenerator(style: style)
            hapticFeedbackGenerator?.prepare()
        }
    }

    /// 触发震动反馈（带节流控制）
    func triggerHapticFeedback() {
        guard configuration.streamingHapticFeedbackStyle != .none else { return }

        let currentTime = CACurrentMediaTime()
        let minInterval = configuration.streamingHapticMinInterval

        // 节流控制：避免过于频繁的震动
        guard currentTime - lastHapticFeedbackTime >= minInterval else { return }

        lastHapticFeedbackTime = currentTime
        hapticFeedbackGenerator?.impactOccurred()
    }

    /// 停止震动反馈（在流式结束时调用）
    func stopHapticFeedback() {
        hapticFeedbackGenerator = nil
        lastHapticFeedbackTime = 0
    }

    /// 显示等待动画
    func showWaitingIndicator() {
        guard !isShowingWaitingIndicator else { return }
        isShowingWaitingIndicator = true

        // 添加到 StackView 末尾
        if waitingIndicatorView.superview == nil {
            contentStackView.addArrangedSubview(waitingIndicatorView)
        }
        waitingIndicatorView.isHidden = false
        if isRealStreamingMode {
            // Waiting View 是低频结构变化；同步校准避免先显示 indicator、后改变 Cell 高度。
            notifyHeightChange(force: true)
        }

        // 启动跳动动画
        startWaitingAnimation()

        mdLog("[StreamBuffer] 💫 Waiting indicator shown")
    }

    /// 隐藏等待动画
    func hideWaitingIndicator() {
        guard isShowingWaitingIndicator else { return }
        isShowingWaitingIndicator = false

        // 停止动画
        stopWaitingAnimation()

        // 从 StackView 移除
        waitingIndicatorView.isHidden = true
        waitingIndicatorView.removeFromSuperview()
        if isRealStreamingMode {
            // 新数据到达时先删除 waiting view。同步提交高度，避免删除、插入新模块和
            // 宿主 batch 被拆成多个可见中间帧。
            notifyHeightChange(force: true)
        }

        mdLog("[StreamBuffer] 💫 Waiting indicator hidden")
    }

    /// 启动等待动画（三点跳动）
    func startWaitingAnimation() {
        waitingAnimationTimer?.invalidate()

        var animationStep = 0
        waitingAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            guard let self = self, self.isShowingWaitingIndicator else {
                timer.invalidate()
                return
            }

            // 找到所有的点
            for i in 0..<3 {
                if let dot = self.waitingIndicatorView.viewWithTag(100 + i) {
                    let isActive = (i == animationStep % 3)
                    UIView.animate(withDuration: 0.15) {
                        dot.transform = isActive ? CGAffineTransform(scaleX: 1.3, y: 1.3) : .identity
                        dot.alpha = isActive ? 1.0 : 0.5
                    }
                }
            }
            animationStep += 1
        }
    }

    /// 停止等待动画
    func stopWaitingAnimation() {
        waitingAnimationTimer?.invalidate()
        waitingAnimationTimer = nil

        // 重置所有点的状态
        for i in 0..<3 {
            if let dot = waitingIndicatorView.viewWithTag(100 + i) {
                dot.transform = .identity
                dot.alpha = 1.0
            }
        }
    }

}
