import Testing
import UIKit
@testable import MarkdownDisplayView

// MARK: - Helpers

private func cellText(_ s: String, size: CGFloat = 16, weight: UIFont.Weight = .regular) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [.font: UIFont.systemFont(ofSize: size, weight: weight)])
}

/// 验证布局计算器给出的行高对每一个单元格都不小于 UILabel 真实排版需要的高度。
@MainActor
private func assertNoCellClipping(
    config: MarkdownConfiguration,
    data: MarkdownTableData,
    containerWidth: CGFloat,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let result = MarkdownTableLayoutCalculator.calculate(
        data: data,
        config: config,
        containerWidth: containerWidth
    )

    let geometry = MarkdownTableCellGeometry(config: config)
    let allRows: [[NSAttributedString]] = [data.headers] + data.rows

    for (rowIndex, row) in allRows.enumerated() {
        let rowHeight = result.rowHeights[rowIndex]
        for (colIndex, text) in row.enumerated() where colIndex < result.columnWidths.count {
            let columnWidth = result.columnWidths[colIndex]

            let labelWidth = columnWidth - geometry.totalHorizontal
            let allottedHeight = rowHeight - geometry.totalVertical

            let probeLabel = UILabel()
            probeLabel.numberOfLines = 0
            probeLabel.attributedText = text
            let needed = probeLabel.sizeThatFits(
                CGSize(width: labelWidth, height: .greatestFiniteMagnitude)
            ).height

            #expect(
                allottedHeight >= needed - 0.01,
                "Cell r\(rowIndex)c\(colIndex): allotted=\(allottedHeight) < needed=\(needed) (deficit=\(needed - allottedHeight))",
                sourceLocation: sourceLocation
            )
        }
    }
}

// MARK: - Tests

@available(iOS 15.0, *)
@MainActor
@Test func tableLayoutDefaultConfigNoClipping() {
    let long = "这是一个很长的表格单元格内容，用来触发多行折行，看看最后一行是否会被裁切掉一部分文字。"
    let data = MarkdownTableData(
        headers: [cellText("列一标题比较长一些用来折行", weight: .semibold), cellText("列二", weight: .semibold)],
        rows: [
            [cellText(long), cellText("短")],
            [cellText(long + long), cellText(long)],
        ],
        columnAlignments: [.left, .left]
    )
    assertNoCellClipping(config: .default, data: data, containerWidth: 358)
}

@available(iOS 15.0, *)
@MainActor
@Test func tableLayoutSmallPaddingNoClipping() {
    let long = "这是一个很长的表格单元格内容，用来触发多行折行，看看最后一行是否会被裁切掉一部分文字。"
    var config = MarkdownConfiguration.default
    config.tableCellPadding = 8
    config.tableCellVerticalPadding = 4
    let data = MarkdownTableData(
        headers: [cellText("列一标题比较长一些用来折行", weight: .semibold), cellText("列二", weight: .semibold)],
        rows: [
            [cellText(long), cellText("短")],
            [cellText(long + long), cellText(long)],
        ],
        columnAlignments: [.left, .left]
    )
    assertNoCellClipping(config: config, data: data, containerWidth: 358)
}

@available(iOS 15.0, *)
@MainActor
@Test func tableLayoutLargePaddingNoClipping() {
    let long = "这是一个很长的表格单元格内容，用来触发多行折行，看看最后一行是否会被裁切掉一部分文字。"
    var config = MarkdownConfiguration.default
    config.tableCellPadding = 24
    config.tableCellVerticalPadding = 20
    let data = MarkdownTableData(
        headers: [cellText("列一标题比较长一些用来折行", weight: .semibold), cellText("列二", weight: .semibold)],
        rows: [
            [cellText(long), cellText("短")],
            [cellText(long + long), cellText(long)],
        ],
        columnAlignments: [.left, .left]
    )
    assertNoCellClipping(config: config, data: data, containerWidth: 358)
}

@available(iOS 15.0, *)
@MainActor
@Test func tableLayoutLargeFontNoClipping() {
    let long = "这是一个很长的表格单元格内容 with English words，用来触发折行。"
    var config = MarkdownConfiguration.default
    config.bodyFont = .systemFont(ofSize: 22)
    let data = MarkdownTableData(
        headers: [cellText("列一", size: 22, weight: .semibold), cellText("列二", size: 22, weight: .semibold)],
        rows: [
            [cellText(long + long, size: 22), cellText(long, size: 22)],
        ],
        columnAlignments: [.left, .left]
    )
    assertNoCellClipping(config: config, data: data, containerWidth: 358)
}

@available(iOS 15.0, *)
@MainActor
@Test func tableLayoutSingleColumnNoClipping() {
    let long = "单列表格也可能裁切，这段文字足够长到需要折行来展示。单列表格也可能裁切。"
    let data = MarkdownTableData(
        headers: [cellText("唯一的列", weight: .semibold)],
        rows: [[cellText(long)], [cellText(long + long)]],
        columnAlignments: [.left]
    )
    assertNoCellClipping(config: .default, data: data, containerWidth: 250)
}

@available(iOS 15.0, *)
@MainActor
@Test func tableLayoutUnevenColumnsNoClipping() {
    let data = MarkdownTableData(
        headers: [cellText("A", weight: .semibold), cellText("B", weight: .semibold), cellText("C", weight: .semibold)],
        rows: [
            [cellText("只有两列")],
            [cellText("a"), cellText("b"), cellText("c")],
        ],
        columnAlignments: [.left, .center, .right]
    )
    assertNoCellClipping(config: .default, data: data, containerWidth: 358)
}

@available(iOS 15.0, *)
@MainActor
@Test func tableLayoutContentSizeMatchesTotalSize() {
    let data = MarkdownTableData(
        headers: [cellText("H1", weight: .semibold), cellText("H2", weight: .semibold)],
        rows: [[cellText("A"), cellText("B")], [cellText("C"), cellText("D")]],
        columnAlignments: [.left, .left]
    )
    let result = MarkdownTableLayoutCalculator.calculate(
        data: data,
        config: .default,
        containerWidth: 400
    )

    let layout = MarkdownTableLayout()
    layout.columnWidths = result.columnWidths
    layout.rowHeights = result.rowHeights
    layout.prepare()

    let contentHeight = layout.collectionViewContentSize.height
    #expect(
        abs(contentHeight - result.totalSize.height) < 2,
        "contentSize.height=\(contentHeight) vs totalSize.height=\(result.totalSize.height)"
    )
}
