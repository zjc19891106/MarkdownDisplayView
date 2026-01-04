//
//  MarkdownStreamBuffer.swift
//  MarkdownDisplayView
//
//  Created by 朱继超 on 12/15/25.
//

import Foundation
import UIKit

// MARK: - Stream Buffer

/// 智能流式缓存器，用于真流式场景下的模块检测和渲染控制
/// 负责缓存网络到达的字节流，检测完整的 Markdown 模块（标题+内容），
/// 并在模块完整时通知外部进行渲染
@available(iOS 15.0, *)
final class MarkdownStreamBuffer {

    // MARK: - 模块检测结果

    /// 模块检测结果
    struct ModuleDetectionResult {
        /// 检测到的完整模块（可渲染的 Markdown 文本）
        let completeModules: [String]
        /// 剩余的未完成文本（需要继续缓存）
        let pendingText: String
        /// 是否有未完成的结构（代码块、表格等未闭合）
        let hasPendingStructure: Bool
        /// 未完成结构类型
        let pendingType: PendingStructureType?
    }

    // MARK: - Properties

    /// 累积的缓存文本
    private(set) var accumulatedText: String = ""

    /// 上次成功解析到的安全位置
    private(set) var lastSafePosition: Int = 0

    /// 已提交渲染的元素数量
    private(set) var committedElementCount: Int = 0

    /// 上次检测到的模块边界位置列表
    private var moduleBoundaries: [Int] = []

    /// 最小模块长度（防止过于频繁的模块检测）
    private let minModuleLength: Int = 50

    /// 配置
    private let configuration: MarkdownConfiguration

    /// 容器宽度
    private var containerWidth: CGFloat

    // MARK: - Callbacks

    /// 当检测到完整模块时的回调
    var onModuleReady: ((String, [MarkdownRenderElement]) -> Void)?

    /// 当缓存状态变化时的回调（用于显示/隐藏等待动画）
    var onBufferStateChanged: ((Bool) -> Void)?

    // MARK: - Init

    init(configuration: MarkdownConfiguration, containerWidth: CGFloat) {
        self.configuration = configuration
        self.containerWidth = containerWidth
    }

    // MARK: - Public Methods

    /// 重置缓存状态
    func reset() {
        accumulatedText = ""
        lastSafePosition = 0
        committedElementCount = 0
        moduleBoundaries = []
        print("[StreamBuffer] 🔄 Buffer reset")
    }

    /// 更新容器宽度
    func updateContainerWidth(_ width: CGFloat) {
        self.containerWidth = width
    }

    /// 追加新到达的文本数据
    /// - Parameter text: 新到达的文本片段
    /// - Returns: 检测结果，包含可渲染的完整模块
    func append(_ text: String) -> ModuleDetectionResult {
        accumulatedText += text
        print("[StreamBuffer] 📥 Appended \(text.count) chars, total: \(accumulatedText.count) chars")

        return detectCompleteModules()
    }

    /// 强制提交所有剩余内容（流式结束时调用）
    /// - Returns: 剩余的所有文本
    func flush() -> String {
        let remaining = String(accumulatedText.dropFirst(lastSafePosition))
        print("[StreamBuffer] 🚿 Flushing remaining: \(remaining.count) chars")
        lastSafePosition = accumulatedText.count
        return remaining
    }

    /// 获取完整的累积文本
    func getFullText() -> String {
        return accumulatedText
    }

    // MARK: - Module Detection

    /// 检测完整的 Markdown 模块
    private func detectCompleteModules() -> ModuleDetectionResult {
        let textToAnalyze = accumulatedText
        let startPosition = lastSafePosition

        // 1. 检测未完成的结构（代码块、表格等）
        let pendingInfo = detectPendingStructure(in: textToAnalyze)

        // 2. 如果有未闭合的结构，需要等待
        if let pending = pendingInfo {
            print("[StreamBuffer] ⏳ Pending structure detected: \(pending.rawValue)")
            // ⭐️ 移除频繁的状态回调，避免 UI 闪烁
            return ModuleDetectionResult(
                completeModules: [],
                pendingText: String(textToAnalyze.dropFirst(startPosition)),
                hasPendingStructure: true,
                pendingType: pending
            )
        }

        // 3. 查找模块边界（基于标题行）
        let boundaries = findModuleBoundaries(in: textToAnalyze, from: startPosition)

        // 4. 如果没有新的完整模块，继续等待
        if boundaries.isEmpty {
            // 检查是否有足够的纯文本内容（无标题的情况）
            let remainingText = String(textToAnalyze.dropFirst(startPosition))
            if remainingText.count > minModuleLength * 3 && remainingText.hasSuffix("\n\n") {
                // 有大量文本且以双换行结束，可以提交
                let completeText = remainingText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !completeText.isEmpty {
                    lastSafePosition = textToAnalyze.count
                    print("[StreamBuffer] ✅ No heading found, but submitting text block: \(completeText.prefix(50))...")
                    return ModuleDetectionResult(
                        completeModules: [completeText],
                        pendingText: "",
                        hasPendingStructure: false,
                        pendingType: nil
                    )
                }
            }

            // ⭐️ 移除频繁的状态回调，避免 UI 闪烁
            return ModuleDetectionResult(
                completeModules: [],
                pendingText: String(textToAnalyze.dropFirst(startPosition)),
                hasPendingStructure: false,
                pendingType: nil
            )
        }

        // 5. 提取完整的模块
        var completeModules: [String] = []
        var lastBoundary = startPosition

        for boundary in boundaries {
            if boundary > lastBoundary {
                let moduleText = extractModule(from: textToAnalyze, start: lastBoundary, end: boundary)
                if !moduleText.isEmpty {
                    completeModules.append(moduleText)
                    print("[StreamBuffer] ✅ Complete module found: \(moduleText.prefix(50))... (\(moduleText.count) chars)")
                }
            }
            lastBoundary = boundary
        }

        // 更新安全位置
        lastSafePosition = lastBoundary
        moduleBoundaries = boundaries

        // ⭐️ 移除频繁的状态回调，避免 UI 闪烁
        // 当有内容渲染时，等待动画会被自然推开

        let pendingText = String(textToAnalyze.dropFirst(lastSafePosition))
        return ModuleDetectionResult(
            completeModules: completeModules,
            pendingText: pendingText,
            hasPendingStructure: false,
            pendingType: nil
        )
    }

    /// 检测文本中是否有未完成的结构
    private func detectPendingStructure(in text: String) -> PendingStructureType? {
        let nsText = text as NSString

        // ⭐️ 检测末尾是否有不完整的代码块标记（如 ` 或 ``）
        // 这是数据流被随机分割导致的
        let trimmedEnd = text.suffix(10)  // 检查末尾10个字符
        if trimmedEnd.contains("`") {
            // 检查是否是完整的 ``` 开头或结尾
            let backtickSuffix = String(text.suffix(5))
            // 如果末尾有1-2个反引号但不是3个，可能是被截断了
            if backtickSuffix.hasSuffix("`") && !backtickSuffix.hasSuffix("```") {
                let backtickCount = backtickSuffix.reversed().prefix(while: { $0 == "`" }).count
                if backtickCount == 1 || backtickCount == 2 {
                    print("[StreamBuffer] ⏳ Incomplete backtick detected at end: \(backtickCount) backticks")
                    return .codeBlock
                }
            }
        }

        // 1. 检测未闭合的代码块 ```
        let codeBlockPattern = "```"
        var codeBlockCount = 0
        var searchRange = NSRange(location: 0, length: nsText.length)

        while searchRange.location < nsText.length {
            let foundRange = nsText.range(of: codeBlockPattern, options: [], range: searchRange)
            if foundRange.location == NSNotFound { break }
            codeBlockCount += 1
            searchRange.location = foundRange.location + foundRange.length
            searchRange.length = nsText.length - searchRange.location
        }

        if codeBlockCount % 2 != 0 {
            return .codeBlock
        }

        // 2. 检测未闭合的 LaTeX 块 $$
        let latexBlockPattern = "$$"
        var latexBlockCount = 0
        searchRange = NSRange(location: 0, length: nsText.length)

        while searchRange.location < nsText.length {
            let foundRange = nsText.range(of: latexBlockPattern, options: [], range: searchRange)
            if foundRange.location == NSNotFound { break }
            latexBlockCount += 1
            searchRange.location = foundRange.location + foundRange.length
            searchRange.length = nsText.length - searchRange.location
        }

        if latexBlockCount % 2 != 0 {
            return .latexBlock
        }

        // 3. 检测未完成的表格（末尾以 | 开头但无空行结束）
        let lines = text.components(separatedBy: .newlines)
        if let lastNonEmptyLine = lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            if lastNonEmptyLine.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                if lastNonEmptyLine.contains("|") && !text.hasSuffix("\n\n") {
                    return .table
                }
            }
        }

        return nil
    }

    /// 查找模块边界（自适应策略）
    /// ⭐️ 自适应分割策略：
    /// 1. 如果有多个一级标题 → 按一级标题分割
    /// 2. 如果只有一个/没有一级标题但有多个二级标题 → 按二级标题分割
    /// 3. 如果都没有 → 按双换行分割段落
    /// - Parameters:
    ///   - text: 完整文本
    ///   - from: 起始搜索位置
    /// - Returns: 模块边界位置数组（每个位置是模块的结束位置，即下一个模块的开始位置）
    private func findModuleBoundaries(in text: String, from startPosition: Int) -> [Int] {
        let lines = text.components(separatedBy: "\n")
        var currentPosition = 0

        // 收集各级标题位置（只收集 startPosition 之后的标题）
        var h1Positions: [Int] = []  // # 一级标题
        var h2Positions: [Int] = []  // ## 二级标题

        // 追踪代码块状态
        var isInsideCodeBlock = false

        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // 检测代码块边界
            if trimmedLine.hasPrefix("```") {
                isInsideCodeBlock = !isInsideCodeBlock
            }

            // ⭐️ 关键修复：只收集 startPosition 之后的标题
            // 这样避免重复处理已经解析过的标题
            if !isInsideCodeBlock && currentPosition >= startPosition {
                // 一级标题：以 `# ` 开头但不是 `## `
                if trimmedLine.hasPrefix("# ") && !trimmedLine.hasPrefix("## ") {
                    h1Positions.append(currentPosition)
                }
                // 二级标题：以 `## ` 开头但不是 `### `
                else if trimmedLine.hasPrefix("## ") && !trimmedLine.hasPrefix("### ") {
                    h2Positions.append(currentPosition)
                }
            }

            currentPosition += line.count + (index < lines.count - 1 ? 1 : 0)
        }

        // ⭐️ 自适应选择分割级别
        var headingPositions: [Int]
        var headingLevel: String

        if h1Positions.count >= 2 {
            // 策略1：有多个一级标题，按一级标题分割
            headingPositions = h1Positions
            headingLevel = "H1"
        } else if h2Positions.count >= 2 {
            // 策略2：只有一个/没有一级标题，但有多个二级标题，按二级标题分割
            headingPositions = h2Positions
            headingLevel = "H2"
        } else {
            // 策略3：没有足够的标题，按双换行分割
            headingPositions = []
            headingLevel = "paragraph"
        }

        print("[StreamBuffer] 📊 Strategy: \(headingLevel), H1=\(h1Positions.count), H2=\(h2Positions.count), startPos=\(startPosition)")

        // ⭐️ 核心修复：正确计算边界
        // 边界 = 下一个标题的开始位置（即当前模块的结束位置）
        var boundaries: [Int] = []

        if headingPositions.count >= 2 {
            // 有多个标题：每个标题（除了最后一个）后面的标题位置就是它的边界
            // 例如：标题A在位置100，标题B在位置200，那么模块A的边界是200
            for i in 1..<headingPositions.count {
                let boundary = headingPositions[i]
                // 只添加在 startPosition 之后的边界
                if boundary > startPosition {
                    boundaries.append(boundary)
                }
            }

            // 检查最后一个模块是否完整（以双换行结束）
            if let lastHeadingPos = headingPositions.last {
                let contentAfterLast = text.count - lastHeadingPos
                if contentAfterLast > minModuleLength && text.hasSuffix("\n\n") {
                    boundaries.append(text.count)
                }
            }
        } else if headingPositions.count == 1 {
            // 只有一个标题：检查标题后的内容是否完整
            let headingPos = headingPositions[0]
            let contentAfter = text.count - headingPos
            if contentAfter > minModuleLength && text.hasSuffix("\n\n") {
                boundaries.append(text.count)
            }
        } else if text.count > startPosition + minModuleLength * 2 && text.hasSuffix("\n\n") {
            // 没有标题，但有足够内容且以双换行结束
            boundaries.append(text.count)
        }

        print("[StreamBuffer] 📊 Found \(boundaries.count) boundaries: \(boundaries)")
        return boundaries
    }

    /// 提取模块文本
    private func extractModule(from text: String, start: Int, end: Int) -> String {
        guard start < end && end <= text.count else { return "" }

        let startIndex = text.index(text.startIndex, offsetBy: start)
        let endIndex = text.index(text.startIndex, offsetBy: end)

        return String(text[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
