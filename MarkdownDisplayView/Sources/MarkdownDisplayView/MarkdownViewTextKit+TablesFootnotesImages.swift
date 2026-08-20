//
//  MarkdownViewTextKit+TablesFootnotesImages.swift
//  MarkdownDisplayView
//
//  Mechanical extension split from MarkdownDisplayView.swift.
//

import UIKit
import Foundation
import Combine

@available(iOS 15.0, *)
extension MarkdownViewTextKit {
    // MARK: - Table View

    func createTableView(with tableData: MarkdownTableData, containerWidth: CGFloat) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer.applyMarkdownBlockAppearance(configuration.tableAppearance)
        container.layer.masksToBounds = configuration.tableAppearance.cornerRadius > 0

        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)

        let tableStackView = UIStackView()
        tableStackView.axis = .vertical
        tableStackView.spacing = 0
        tableStackView.distribution = .fill
        tableStackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(tableStackView)

        // 计算列宽
        let columnCount = max(tableData.headers.count, tableData.rows.first?.count ?? 0)
        let cellPadding = configuration.tableCellPadding * 2  // 左右各 padding
        var columnWidths: [CGFloat] = Array(repeating: configuration.tableMinColumnWidth, count: columnCount)

        for (index, header) in tableData.headers.enumerated() {
            let width = header.boundingRect(
                with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: configuration.tableRowHeight),
                options: [.usesLineFragmentOrigin],
                context: nil
            ).width + cellPadding
            columnWidths[index] = max(columnWidths[index], width)
        }

        for row in tableData.rows {
            for (index, cell) in row.enumerated() where index < columnCount {
                let width = cell.boundingRect(
                    with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: configuration.tableRowHeight),
                    options: [.usesLineFragmentOrigin],
                    context: nil
                ).width + cellPadding
                columnWidths[index] = max(columnWidths[index], width)
            }
        }

        columnWidths = columnWidths.map { min($0, configuration.tableMaxColumnWidth) }
        let totalWidth = columnWidths.reduce(0, +)

        // 表头行
        let headerRow = createTableRow(cells: tableData.headers, columnWidths: columnWidths, isHeader: true)
        tableStackView.addArrangedSubview(headerRow)

        // 分隔线
        let separator = UIView()
        separator.backgroundColor = configuration.tableBorderColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: configuration.tableSeparatorHeight).isActive = true
        tableStackView.addArrangedSubview(separator)

        // 数据行
        for (index, row) in tableData.rows.enumerated() {
            let rowView = createTableRow(cells: row, columnWidths: columnWidths, isHeader: false)
            if index % 2 == 1 {
                rowView.backgroundColor = configuration.tableAlternateRowBackgroundColor
            } else {
                rowView.backgroundColor = configuration.tableRowBackgroundColor
            }
            tableStackView.addArrangedSubview(rowView)
        }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            tableStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            tableStackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            tableStackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            tableStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            tableStackView.widthAnchor.constraint(equalToConstant: totalWidth),
        ])

        let rowHeight = configuration.tableRowHeight
        let tableHeight = rowHeight * CGFloat(tableData.rows.count + 1) + configuration.tableSeparatorHeight
        container.heightAnchor.constraint(equalToConstant: tableHeight).isActive = true

        return container
    }
    
    func createTableRow(
        cells: [NSAttributedString],
        columnWidths: [CGFloat],
        isHeader: Bool
    ) -> UIView {
        let rowStack = UIStackView()
        rowStack.axis = .horizontal
        rowStack.spacing = 0
        rowStack.distribution = .fill
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        
        if isHeader {
            rowStack.backgroundColor = configuration.tableHeaderBackgroundColor
        }
        
        for (index, cell) in cells.enumerated() {
            let cellView = UIView()
            cellView.translatesAutoresizingMaskIntoConstraints = false
            
            let label = UILabel()
            label.attributedText = cell
            label.numberOfLines = 0
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            
            if isHeader {
                label.font = UIFont.systemFont(ofSize: configuration.bodyFont.pointSize, weight: .semibold)
            }
            
            cellView.addSubview(label)
            
            if index < cells.count - 1 {
                let border = UIView()
                border.backgroundColor = configuration.tableBorderColor.withAlphaComponent(0.3)
                border.translatesAutoresizingMaskIntoConstraints = false
                cellView.addSubview(border)
                
                NSLayoutConstraint.activate([
                    border.topAnchor.constraint(equalTo: cellView.topAnchor, constant: 8),
                    border.bottomAnchor.constraint(equalTo: cellView.bottomAnchor, constant: -8),
                    border.trailingAnchor.constraint(equalTo: cellView.trailingAnchor),
                    border.widthAnchor.constraint(equalToConstant: 0.5),
                ])
            }
            
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: cellView.topAnchor, constant: 10),
                label.bottomAnchor.constraint(equalTo: cellView.bottomAnchor, constant: -10),
                label.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 12),
                label.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -12),
            ])
            
            let width = index < columnWidths.count ? columnWidths[index] : 80
            cellView.widthAnchor.constraint(equalToConstant: width).isActive = true
            
            rowStack.addArrangedSubview(cellView)
        }
        
        rowStack.heightAnchor.constraint(equalToConstant: 44).isActive = true
        
        return rowStack
    }
    
    // MARK: - Footnote View

    func createFootnoteView(footnotes: [MarkdownFootnote], width: CGFloat) -> UIView {
        // [FOOTNOTE_DEBUG] 脚注视图创建
        mdLog("[FOOTNOTE_DEBUG] 🎨 createFootnoteView called! count=\(footnotes.count), isRealStreamingMode=\(isRealStreamingMode)")
        #if DEBUG
        if mdVerboseLoggingEnabled {
            let callStack = Thread.callStackSymbols.prefix(6).joined(separator: "\n")
            mdLog("[FOOTNOTE_DEBUG] 🎨 Call stack:\n\(callStack)")
        }
        #endif

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        // ⭐️ 标记为原子块，让打字机引擎将其视为整体淡入，而不是逐字打印
        container.accessibilityIdentifier = "FootnoteContainer"
        
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.alignment = .leading // 使用 .leading 允许分隔线宽度自定义
        stackView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stackView)
        
        // 1. 分隔线
        let separator = UIView()
        separator.backgroundColor = configuration.horizontalRuleColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(separator)
        
        NSLayoutConstraint.activate([
            separator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
            separator.widthAnchor.constraint(equalToConstant: width * 0.3)
        ])
        
        // 2. 合并所有脚注到一个 AttributedString (性能优化：O(N) Views -> O(1) View)
        let allFootnotesText = NSMutableAttributedString()
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = 6 // 脚注之间的间距
        paragraphStyle.lineHeightMultiple = 1.1
        
        for (index, footnote) in footnotes.enumerated() {
            // 添加换行 (除第一个外)
            if index > 0 {
                allFootnotesText.append(NSAttributedString(string: "\n"))
            }
            
            // ID: ⁽1⁾
            let idText = NSAttributedString(
                string: "⁽\(footnote.id)⁾ ",
                attributes: [
                    .font: UIFont.systemFont(ofSize: configuration.bodyFont.pointSize - 2),
                    .foregroundColor: configuration.linkColor,
                    .baselineOffset: 3,
                    .paragraphStyle: paragraphStyle
                ])
            allFootnotesText.append(idText)
            
            // Content
            let contentText = NSAttributedString(
                string: footnote.content,
                attributes: [
                    .font: UIFont.systemFont(ofSize: configuration.bodyFont.pointSize - 2),
                    .foregroundColor: configuration.textColor.withAlphaComponent(0.8),
                    .paragraphStyle: paragraphStyle
                ])
            allFootnotesText.append(contentText)
        }
        
        // 3. 创建唯一的 TextView
        // 注意：我们显式传递 width 确保 createTextView 内部正确计算布局
        let textView = createTextView(
            with: allFootnotesText,
            width: width,
            insets: UIEdgeInsets(top: 8, left: 0, bottom: 16, right: 0)
        )
        
        // 确保 TextView 占满全宽 (因为 StackView 是 .leading 对齐)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.widthAnchor.constraint(equalToConstant: width).isActive = true
        
        stackView.addArrangedSubview(textView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        
        return container
    }
    
    // MARK: - Footnote Preprocessing
    
    func preprocessFootnotes(_ text: String) -> (String, [MarkdownFootnote]) {
        // Optimization: Fast check for footnote syntax markers.
        // If neither definition marker nor reference marker exists, skip regex entirely.
        if !text.contains("[^") {
            return (text, [])
        }
        
        var processedText = text
        var footnotes: [MarkdownFootnote] = []
        
        let definitionPattern = #"\[\^([^\]]+)\]:\s*(.+)$"#
        if let regex = try? NSRegularExpression(pattern: definitionPattern, options: .anchorsMatchLines) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            
            for match in matches.reversed() {
                if let idRange = Range(match.range(at: 1), in: text),
                   let contentRange = Range(match.range(at: 2), in: text),
                   let fullRange = Range(match.range, in: text) {
                    let id = String(text[idRange])
                    let content = String(text[contentRange])
                    footnotes.insert(MarkdownFootnote(id: id, content: content), at: 0)
                    processedText = processedText.replacingCharacters(in: fullRange, with: "")
                }
            }
        }
        
        let referencePattern = #"\[\^([^\]]+)\]"#
        if let regex = try? NSRegularExpression(pattern: referencePattern, options: []) {
            let matches = regex.matches(in: processedText, range: NSRange(processedText.startIndex..., in: processedText))
            
            for match in matches.reversed() {
                if let idRange = Range(match.range(at: 1), in: processedText),
                   let fullRange = Range(match.range, in: processedText) {
                    let id = String(processedText[idRange])
                    let replacement = "⁽\(id)⁾"
                    processedText = processedText.replacingCharacters(in: fullRange, with: replacement)
                }
            }
        }
        
        return (processedText, footnotes)
    }
    
    // MARK: - Image Loading
    
    func loadImages() {
        for (attachment, urlString) in imageAttachments {
            loadImage(urlString: urlString, into: attachment)
        }
    }
    
    func loadImage(urlString: String, into attachment: MarkdownImageAttachment) {
        var processedURLString = urlString
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            processedURLString = "https://" + urlString
        }
        
        guard let url = URL(string: processedURLString) else { return }
        
        ImageLoader.shared.loadImage(from: url)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] image in
                guard let self = self, let image = image else { return }
                
                let imageSize = image.size
                var targetSize = CGSize(width: 100, height: 100)
                
                if imageSize.width > 0 && imageSize.height > 0 {
                    let aspectRatio = ceilf(Float(imageSize.width / imageSize.height))
                    var targetWidth = imageSize.width
                    var targetHeight = imageSize.height
                    
                    // 按宽度缩放
                    if attachment.maxWidth > 0 && targetWidth > attachment.maxWidth {
                        targetWidth = attachment.maxWidth
                        targetHeight = targetWidth / CGFloat(aspectRatio)
                    }
                    
                    // 按高度缩放
                    if attachment.maxHeight > 0 && targetHeight > attachment.maxHeight {
                        targetHeight = attachment.maxHeight
                        targetWidth = targetHeight * CGFloat(aspectRatio)
                    }
                    
                    targetSize = CGSize(width: ceil(targetWidth), height: ceil(targetHeight))
                }
                
                // 直接生成缩放后的图片
                let renderer = UIGraphicsImageRenderer(size: targetSize)
                let scaledImage = renderer.image { _ in
                    image.draw(in: CGRect(origin: .zero, size: targetSize))
                }
                
                attachment.bounds = CGRect(origin: .zero, size: targetSize)
                attachment.image = scaledImage
                
                self.refreshWorkItem?.cancel()
                let workItem = DispatchWorkItem { [weak self] in
                    self?.refreshTextViews()
                }
                self.refreshWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
            }
            .store(in: &cancellables)
    }
    
    func refreshTextViews() {
        for container in contentStackView.arrangedSubviews {
            for textView in markdownTextViews(in: container) {
                textView.setNeedsDisplay()
            }
        }

        remeasureMountedViewportSlots()
        
        invalidateIntrinsicContentSize()
        notifyHeightChange()
    }
    
    func measuredVisibleContentStackHeight() -> CGFloat {
        let visibleSubviews = contentStackView.arrangedSubviews.filter { !$0.isHidden }
        var totalHeight: CGFloat = visibleSubviews.reduce(0) { $0 + $1.frame.height }

        if visibleSubviews.count > 1 {
            totalHeight += CGFloat(visibleSubviews.count - 1) * contentStackView.spacing
        }

        totalHeight += contentStackView.layoutMargins.top + contentStackView.layoutMargins.bottom
        return max(0, totalHeight)
    }

    func handleTypewriterLayoutChange(_ change: TypewriterEngine.LayoutChange) {
        guard isRealStreamingMode else {
            scheduleHeightChangeNotification()
            return
        }

        let knownHeight: CGFloat?
        switch change {
        case .rootBecameVisible(let root):
            knownHeight = realStreamHeightAccumulator.rootBecameVisible(
                root,
                measuredHeight: measuredStreamingRootHeight(root),
                spacing: contentStackView.spacing
            )
        case .textHeightChanged(let delta):
            knownHeight = realStreamHeightAccumulator.textHeightChanged(delta: delta)
        }

        guard let knownHeight else { return }
        invalidateIntrinsicContentSize()
        // Typewriter 已经按显示帧合并 reveal，这里的增量高度又是 O(1) 已知值。
        // 立即提交给宿主，保证文字写入、Cell self-sizing 和最终 draw 位于同一轮
        // 主线程事务；再次延迟 30Hz 会让新内容在旧 Cell 高度中被裁剪数帧。
        notifyHeightChange(knownStreamingHeight: knownHeight)
    }

    private func measuredStreamingRootHeight(_ root: UIView) -> CGFloat {
        if let stack = root as? UIStackView {
            let visible = stack.arrangedSubviews.filter { !$0.isHidden }
            var height = visible.reduce(CGFloat.zero) {
                $0 + measuredStreamingRootHeight($1)
            }
            if visible.count > 1 {
                height += CGFloat(visible.count - 1) * stack.spacing
            }
            if stack.isLayoutMarginsRelativeArrangement {
                height += stack.layoutMargins.top + stack.layoutMargins.bottom
            }
            if height.isFinite, height > 0 { return height }
        }

        let intrinsicHeight = root.intrinsicContentSize.height
        if intrinsicHeight.isFinite,
           intrinsicHeight != UIView.noIntrinsicMetric,
           intrinsicHeight > 0 {
            return intrinsicHeight
        }

        if let fixedHeight = root.constraints.first(where: {
            $0.isActive
                && $0.firstItem === root
                && $0.firstAttribute == .height
                && $0.relation == .equal
        }), fixedHeight.constant > 0 {
            return fixedHeight.constant
        }

        let fittingWidth = max(
            1,
            contentStackView.bounds.width > 0
                ? contentStackView.bounds.width
                : bounds.width
        )
        let height = root.systemLayoutSizeFitting(
            CGSize(width: fittingWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        if height.isFinite, height > 0 { return height }
        return max(0, root.bounds.height)
    }

    /// 合并同一轮 RunLoop 内的测高请求，避免 Typewriter、建 View 和外层列表连续触发布局。
    func scheduleHeightChangeNotification(
        force: Bool = false,
        knownStreamingHeight: CGFloat? = nil
    ) {
        streamPerformanceDiagnostics.recordHeightRequest()
        // 只有 Typewriter 的 append 高度变化可以走 O(1) 增量值。图片回调、宽度变化和
        // 强制测高都必须清空该值，回退到完整布局以保证最终正确性。
        if knownStreamingHeight == nil || force {
            invalidateIntrinsicHeightCache()
            pendingRequiresFullHeightMeasurement = true
            pendingKnownStreamingHeight = nil
        } else if !pendingRequiresFullHeightMeasurement {
            pendingKnownStreamingHeight = knownStreamingHeight
        }
        pendingForcedHeightNotification = pendingForcedHeightNotification || force
        guard !heightNotificationScheduled else { return }
        heightNotificationScheduled = true
        let now = heightNotificationClock()
        // 流式 Cell 的一次高度通知会触发 UITableView self-sizing/batch update。
        // 30Hz 足以跟随打字机，同时避免对不断增长的 StackView 每帧完整测量。
        let frameInterval = isStreaming ? 1.0 / 30.0 : 1.0 / 60.0
        let delay = max(0, frameInterval - (now - lastHeightNotificationTimestamp))
        let generation = heightNotificationGeneration

        heightNotificationScheduler(delay) { [weak self] in
            guard let self else { return }
            guard generation == self.heightNotificationGeneration else { return }
            self.heightNotificationScheduled = false
            self.lastHeightNotificationTimestamp = self.heightNotificationClock()
            let shouldForce = self.pendingForcedHeightNotification
            self.pendingForcedHeightNotification = false
            let knownHeight = self.pendingRequiresFullHeightMeasurement
                ? nil
                : self.pendingKnownStreamingHeight
            self.pendingKnownStreamingHeight = nil
            self.pendingRequiresFullHeightMeasurement = false
            self.notifyHeightChange(force: shouldForce, knownStreamingHeight: knownHeight)
        }
    }

    func notifyHeightChange(
        force: Bool = false,
        knownStreamingHeight: CGFloat? = nil
    ) {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            recordCost(for: "Layout Calculation", duration: CFAbsoluteTimeGetCurrent() - start)
        }

        if let knownStreamingHeight,
           isRealStreamingMode,
           !force,
           knownStreamingHeight.isFinite {
            cacheIntrinsicHeight(knownStreamingHeight, width: heightMeasurementWidth)
            let heightDiff = knownStreamingHeight - lastReportedHeight
            // ⚠️ 增量路径不能套用全量测高那条 9pt 防抖阈值。
            //
            // isRealStreamingMode 下 `intrinsicContentSize` 直接返回累加器的 totalHeight，
            // 而 handleTypewriterLayoutChange 每次高度变化都会 invalidateIntrinsicContentSize()，
            // 也就是说 **markdownView 自身是无阈值、每帧跟随内容的**。若这里再按 9pt 拦截，
            // 宿主 Cell 的 UIView-Encapsulated-Layout-Height（required）就会一直停在旧值，
            // 而 textView 的 heightConstraint 只有 999 —— 差额全部由"把正在打字的文字压掉"
            // 来吸收，直到累积跨过 9pt 才一次性弹出。表现就是流式过程中周期性闪一下。
            //
            // 这也解释了"第一个标题不闪、后续标题闪"：beginRealStreaming 会把
            // lastReportedHeight 归零，第一个元素的 diff 是从 0 起跳，必然远大于 9pt 而立即
            // 上报；从第二个元素开始才是小增量，才会落进阈值窗口被截留。标题行高 30pt 以上
            // 又叠加 headingTopSpacing/headingBottomSpacing，被截留时裁掉的是一整截大字，
            // 所以只在标题前后肉眼可见。
            //
            // 增量值本身已经过两层过滤（revealCharacter 的 didChangeHeight、累加器的 0.5pt），
            // 上报频率等于折行频率而不是帧率，因此这里直接跟随即可。
            // 全量测高路径的 9pt 阈值保留：那条路径读的是 frame 求和，本身会抖。
            let shouldNotifyParent = abs(heightDiff) > 0.5
            if shouldNotifyParent {
                lastReportedHeight = knownStreamingHeight
                onHeightChange?(knownStreamingHeight)
            }
            streamPerformanceDiagnostics.recordHeightMeasurement(
                durationMS: (CFAbsoluteTimeGetCurrent() - start) * 1000,
                notified: shouldNotifyParent,
                force: false,
                source: "incremental",
                arrangedSubviews: contentStackView.arrangedSubviews.count
            )
            return
        }

        // 结构性变化（Details 展开/收起、宽度变化等）不能沿用旧的根高度缓存。
        // 先失效根 intrinsic size，再解算 compressed fitting height；否则旧高度会让
        // UIStackView `.fill` 把差额塞进目录/列表，随后 frame fallback 又会固化错误值。
        if force {
            invalidateIntrinsicHeightCache()
            invalidateIntrinsicContentSize()
            self.contentStackView.invalidateIntrinsicContentSize()
            self.contentStackView.setNeedsLayout()
            self.setNeedsLayout()
        }
        self.layoutIfNeeded()
        self.contentStackView.layoutIfNeeded()

        // 使用稳定的测量宽度，避免父视图尚未完成布局时出现 width=0 导致测高抖动
        let fittingWidth = heightMeasurementWidth

        let frameBasedHeight = measuredVisibleContentStackHeight()
        let hasVisibleContent = contentStackView.arrangedSubviews.contains { !$0.isHidden }

        // 流式阶段刚完成 layoutIfNeeded，arrangedSubview frame 已是当前可见内容的结果。
        // 复用这些 frame，避免每次打字机高度变化都让 systemLayoutSizeFitting 再解一次整棵树。
        let fittingHeight: CGFloat = {
            if isStreaming, frameBasedHeight > 0, !force {
                return frameBasedHeight
            }
            return contentStackView.systemLayoutSizeFitting(
                CGSize(width: fittingWidth, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
        }()

        var newHeight = fittingHeight
        var usedFrameFallback = false
        var measurementSource = isStreaming && frameBasedHeight > 0 && !force ? "frame" : "fitting"

        if !newHeight.isFinite || newHeight <= 0 {
            newHeight = frameBasedHeight
            usedFrameFallback = true
            measurementSource = "frameFallback"
        }

        // 有可见内容但高度仍为 0，通常是布局尚未稳定；本轮跳过，等待下一次布局回调
        if newHeight <= 0, hasVisibleContent, !force {
            mdLog("📏 [Height] ⏳ Deferred notification (transient 0 with visible content)")
            streamPerformanceDiagnostics.recordHeightMeasurement(
                durationMS: (CFAbsoluteTimeGetCurrent() - start) * 1000,
                notified: false,
                force: force,
                source: "deferred",
                arrangedSubviews: contentStackView.arrangedSubviews.count
            )
            return
        }

        // 刚被 resetForReuse() 清空：内容栈是空的，上面那条保护（要求 hasVisibleContent）
        // 拦不住，但这个 0 同样只是重渲染前的中间态。放行会让宿主按 0 重排一次行高，
        // 进而触发可见 Cell 重建 → 再 reset → 再报 0 的自激环。等真实高度出来再上报。
        if newHeight <= 0, suppressesZeroHeightNotification {
            mdLog("📏 [Height] ⏳ Suppressed zero notification (post-reset, empty content)")
            streamPerformanceDiagnostics.recordHeightMeasurement(
                durationMS: (CFAbsoluteTimeGetCurrent() - start) * 1000,
                notified: false,
                force: force,
                source: "suppressedZero",
                arrangedSubviews: contentStackView.arrangedSubviews.count
            )
            return
        }

        if newHeight > 0 {
            suppressesZeroHeightNotification = false
        }

        if newHeight.isFinite, newHeight >= 0 {
            cacheIntrinsicHeight(newHeight, width: fittingWidth)
        }

        // 🔍 诊断日志：打印高度变化
        let heightDiff = newHeight - lastReportedHeight
        if isRealStreamingMode {
            realStreamHeightAccumulator.synchronize(totalHeight: newHeight)
            invalidateIntrinsicContentSize()
        }
        mdLog("🔍 [Height] Current: \(String(format: "%.1f", newHeight))pt | Last: \(String(format: "%.1f", lastReportedHeight))pt | Diff: \(String(format: "%.1f", heightDiff))pt | Force: \(force) | Width: \(String(format: "%.1f", fittingWidth)) | Source: \(usedFrameFallback ? "frame" : "fitting")")

        // 只有高度变化超过阈值才通知，避免浮点数误差导致的死循环
        // 如果 force 为 true，忽略防抖检查
        let shouldNotifyParent = force || abs(newHeight - lastReportedHeight) > 9.0
        if shouldNotifyParent {
            mdLog("📏 [Height] ✅ Notifying parent: \(String(format: "%.1f", lastReportedHeight)) -> \(String(format: "%.1f", newHeight))")
            lastReportedHeight = newHeight
            self.onHeightChange?(newHeight)

            // ⭐️ 关键修复：上面的 layoutIfNeeded() 只解算了 self（markdownView）这一层。
            // 当宿主是 ScrollableMarkdownViewTextKit 时，真正持有 contentSize 的是外层
            // UIScrollView，它的 bottomAnchor 通过 contentLayoutGuide 依赖 markdownView 的高度。
            // 在异步（离屏渲染 / 打字机）路径里手动调 layoutIfNeeded() 会让 markdownView 自己
            // 提前解算完毕，但不会顺带触发祖先 scrollView 的布局 —— 于是 scrollView 的
            // contentSize 和内部子视图 frame 停留在旧状态，直到用户触屏滚动、系统才被动调用
            // UIScrollView.layoutSubviews() 重新从约束里取值。这里主动把父 scrollView 也
            // 一起刷新，消除"必须手动滑一下才能恢复正常布局"的问题。
            //
            // ⚠️ 注意：嵌在 UITableView/UICollectionView cell 里时不能这样做 —— UITableView
            // 本身也是 UIScrollView，findParentScrollView() 会一路找到它。流式打字机期间
            // notifyHeightChange 每秒触发几十次，若每次都强制整张表 layoutIfNeeded()，
            // 代价是对全表重新布局而非仅这一行 cell，且可能与 self-sizing cell 自身的
            // 高度计算产生时序冲突。这类场景已经通过 cell 侧的 onHeightChange 回调
            // （tableView.beginUpdates/endUpdates 或 performBatchUpdates）来驱动高度变化，
            // 不需要也不应该在这里代劳。
            if !isEmbeddedInReusableCell(), let scrollView = findParentScrollView() {
                scrollView.setNeedsLayout()
                scrollView.layoutIfNeeded()
            }
        } else {
            mdLog("📏 [Height] ⚠️ Skipped notification (diff < 9.0pt)")
        }
        streamPerformanceDiagnostics.recordHeightMeasurement(
            durationMS: (CFAbsoluteTimeGetCurrent() - start) * 1000,
            notified: shouldNotifyParent,
            force: force,
            source: measurementSource,
            arrangedSubviews: contentStackView.arrangedSubviews.count
        )
    }
    
    public override var intrinsicContentSize: CGSize {
        if isRealStreamingMode, realStreamHeightAccumulator.totalHeight > 0 {
            return CGSize(
                width: UIView.noIntrinsicMetric,
                height: realStreamHeightAccumulator.totalHeight
            )
        }
        let fittingWidth = heightMeasurementWidth
        if let cachedWidth = cachedIntrinsicHeightWidth,
           let cachedHeight = cachedIntrinsicHeight,
           abs(cachedWidth - fittingWidth) <= 0.5 {
            return CGSize(width: UIView.noIntrinsicMetric, height: cachedHeight)
        }
        intrinsicHeightMeasurementCount += 1
        let size = contentStackView.systemLayoutSizeFitting(
            CGSize(
                width: fittingWidth,
                height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        cacheIntrinsicHeight(size.height, width: fittingWidth)
        return CGSize(width: UIView.noIntrinsicMetric, height: size.height)
    }

    var heightMeasurementWidth: CGFloat {
        if bounds.width > 0 { return bounds.width }
        if contentStackView.bounds.width > 0 { return contentStackView.bounds.width }
        // 宿主给出的宽度优先于整屏兜底：兜底值会让未布局的 Cell 首轮测出偏矮的高度，
        // 导致行高分两趟应用（先长高再重刷）。
        if let preferredMeasurementWidth, preferredMeasurementWidth > 0 {
            return preferredMeasurementWidth
        }
        return max(1, UIScreen.main.bounds.width - 32)
    }

    func cacheIntrinsicHeight(_ height: CGFloat, width: CGFloat? = nil) {
        guard height.isFinite, height >= 0 else { return }
        cachedIntrinsicHeightWidth = width ?? heightMeasurementWidth
        cachedIntrinsicHeight = height
    }

    func invalidateIntrinsicHeightCache() {
        cachedIntrinsicHeightWidth = nil
        cachedIntrinsicHeight = nil
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()

        // layoutSubviews 也会由高度回调和 UITableView batch update 触发。只在测量宽度
        // 真正变化时重新测高，切断 notify → table layout → layoutSubviews → notify 的反馈环。
        let widthChanged = consumeLayoutWidthChange(bounds.width)
        if widthChanged {
            relayoutViewportSlotsForWidthChange(to: bounds.width)
            scheduleHeightChangeNotification(force: true)
        }
        refreshViewportObservationIfNeeded()
        scheduleViewportReconcile()
    }

    func consumeLayoutWidthChange(_ width: CGFloat) -> Bool {
        guard width > 0, abs(width - lastLayoutWidthForHeightMeasurement) > 0.5 else { return false }
        lastLayoutWidthForHeightMeasurement = width
        invalidateIntrinsicHeightCache()
        return true
    }
    
}
