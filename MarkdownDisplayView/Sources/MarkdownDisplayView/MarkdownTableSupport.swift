//
//  MarkdownTableSupport.swift
//  MarkdownDisplayView
//
//  Created by Gemini on 12/27/25.
//

import UIKit

// MARK: - Cell Geometry (single source of truth for padding)

/// 表格单元格内边距的唯一几何来源。
/// 布局计算器（`MarkdownTableLayoutCalculator`）和单元格（`MarkdownTableCell`）
/// 都通过该结构读取内边距，确保测量口径与实际排版完全一致。
struct MarkdownTableCellGeometry: Equatable {
    /// 单侧水平内边距（按像素网格取整）
    let horizontalPadding: CGFloat
    /// 单侧垂直内边距（按像素网格取整）
    let verticalPadding: CGFloat

    init(config: MarkdownConfiguration) {
        horizontalPadding = max(0, ceil(config.tableCellPadding))
        verticalPadding = max(0, ceil(config.tableCellVerticalPadding))
    }

    var totalHorizontal: CGFloat { horizontalPadding * 2 }
    var totalVertical: CGFloat { verticalPadding * 2 }
}

// MARK: - Layout Calculator

struct MarkdownTableLayoutResult {
    let columnWidths: [CGFloat]
    let rowHeights: [CGFloat]
    let totalSize: CGSize
}

struct MarkdownTableLayoutCalculator {
    static func calculate(
        data: MarkdownTableData,
        config: MarkdownConfiguration,
        containerWidth: CGFloat
    ) -> MarkdownTableLayoutResult {
        guard !data.headers.isEmpty || !data.rows.isEmpty else {
            return MarkdownTableLayoutResult(
                columnWidths: [],
                rowHeights: [],
                totalSize: .zero
            )
        }

        let geometry = MarkdownTableCellGeometry(config: config)

        // 1. Calculate Column Widths
        let columnCount = max(
            data.headers.count,
            data.rows.map(\.count).max() ?? 0
        )
        var columnWidths: [CGFloat] = Array(repeating: config.tableMinColumnWidth, count: columnCount)

        func measureWidth(_ text: NSAttributedString) -> CGFloat {
            let width = text.boundingRect(
                with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).width
            return ceil(width) + geometry.totalHorizontal
        }

        // Measure Headers
        for (i, header) in data.headers.enumerated() {
            if i < columnCount {
                columnWidths[i] = max(columnWidths[i], measureWidth(header))
            }
        }

        // Measure Rows
        for row in data.rows {
            for (i, cell) in row.enumerated() {
                if i < columnCount {
                    columnWidths[i] = max(columnWidths[i], measureWidth(cell))
                }
            }
        }

        // Cap max width per column, then ceil to avoid sub-pixel rounding clipping
        columnWidths = columnWidths.map { ceil(min($0, config.tableMaxColumnWidth)) }

        // 2. Calculate Row Heights
        var rowHeights: [CGFloat] = []

        func measureHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
            let availableWidth = max(1, width - geometry.totalHorizontal)
            let measured = text.boundingRect(
                with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).height
            return ceil(measured) + geometry.totalVertical
        }

        // Header Height
        var headerHeight: CGFloat = config.tableRowHeight
        for (i, header) in data.headers.enumerated() {
            if i < columnCount {
                headerHeight = max(headerHeight, measureHeight(header, width: columnWidths[i]))
            }
        }
        rowHeights.append(headerHeight)

        // Row Heights
        for row in data.rows {
            var rowHeight: CGFloat = config.tableRowHeight
            for (i, cell) in row.enumerated() {
                if i < columnCount {
                    rowHeight = max(rowHeight, measureHeight(cell, width: columnWidths[i]))
                }
            }
            rowHeights.append(rowHeight)
        }

        let totalWidth = columnWidths.reduce(0, +)
        // CollectionView 内部不绘制分隔行，contentSize 等于 Σ rowHeights。
        // 仅在外层追加一个 separatorHeight 作为视觉边框余量。
        let totalHeight = rowHeights.reduce(0, +) + config.tableSeparatorHeight

        let frameWidth = min(totalWidth, containerWidth)

        return MarkdownTableLayoutResult(
            columnWidths: columnWidths,
            rowHeights: rowHeights,
            totalSize: CGSize(width: frameWidth, height: totalHeight)
        )
    }
}

// MARK: - Custom CollectionView Layout

class MarkdownTableLayout: UICollectionViewLayout {
    var columnWidths: [CGFloat] = [] {
        didSet {
            if columnWidths != oldValue { invalidateLayout() }
        }
    }
    var rowHeights: [CGFloat] = [] {
        didSet {
            if rowHeights != oldValue { invalidateLayout() }
        }
    }
    
    private var layoutAttributes: [IndexPath: UICollectionViewLayoutAttributes] = [:]
    private var contentSize: CGSize = .zero
    private var preparedColumnWidths: [CGFloat] = []
    private var preparedRowHeights: [CGFloat] = []
    /// 每列左边界累积 x 坐标（与 columnWidths 对齐）
    private var columnXOffsets: [CGFloat] = []
    /// 每行(section)顶部累积 y 坐标（与 rowHeights 对齐）
    private var sectionYOffsets: [CGFloat] = []
    private(set) var layoutRebuildCount = 0
    
    override func prepare() {
        super.prepare()

        if columnWidths == preparedColumnWidths,
           rowHeights == preparedRowHeights,
           !layoutAttributes.isEmpty {
            return
        }

        layoutAttributes.removeAll()
        columnXOffsets.removeAll()
        sectionYOffsets.removeAll()
        preparedColumnWidths = columnWidths
        preparedRowHeights = rowHeights
        layoutRebuildCount += 1
        
        guard !columnWidths.isEmpty && !rowHeights.isEmpty else {
            contentSize = .zero
            return
        }
        mdLog("[MarkdownTable] layout prepare cells=\(rowHeights.count * columnWidths.count) rebuild=\(layoutRebuildCount)")
        
        var currentX: CGFloat = 0
        for width in columnWidths {
            columnXOffsets.append(currentX)
            currentX += width
        }
        let totalWidth = currentX
        
        var yOffset: CGFloat = 0
        for section in 0..<rowHeights.count {
            let height = rowHeights[section]
            sectionYOffsets.append(yOffset)
            
            for item in 0..<columnWidths.count {
                let indexPath = IndexPath(item: item, section: section)
                let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
                
                attributes.frame = CGRect(
                    x: columnXOffsets[item],
                    y: yOffset,
                    width: columnWidths[item],
                    height: height
                )
                
                layoutAttributes[indexPath] = attributes
            }
            
            yOffset += height
        }
        
        contentSize = CGSize(width: totalWidth, height: yOffset)
    }
    
    override var collectionViewContentSize: CGSize {
        return contentSize
    }
    
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard !layoutAttributes.isEmpty, !columnWidths.isEmpty, !rowHeights.isEmpty else { return nil }
        
        var firstSection = -1
        for section in 0..<rowHeights.count {
            if sectionYOffsets[section] + rowHeights[section] > rect.minY {
                firstSection = section
                break
            }
        }
        guard firstSection >= 0 else { return [] }
        
        var lastSection = firstSection
        for section in firstSection..<rowHeights.count {
            if sectionYOffsets[section] < rect.maxY {
                lastSection = section
            } else {
                break
            }
        }
        
        var firstItem = -1
        for item in 0..<columnWidths.count {
            if columnXOffsets[item] + columnWidths[item] > rect.minX {
                firstItem = item
                break
            }
        }
        guard firstItem >= 0 else { return [] }
        
        var lastItem = firstItem
        for item in firstItem..<columnWidths.count {
            if columnXOffsets[item] < rect.maxX {
                lastItem = item
            } else {
                break
            }
        }
        
        var result: [UICollectionViewLayoutAttributes] = []
        result.reserveCapacity((lastSection - firstSection + 1) * (lastItem - firstItem + 1))
        for section in firstSection...lastSection {
            for item in firstItem...lastItem {
                if let attributes = layoutAttributes[IndexPath(item: item, section: section)] {
                    result.append(attributes)
                }
            }
        }
        return result
    }
    
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        return layoutAttributes[indexPath]
    }
}

// MARK: - Table Cell

class MarkdownTableCell: UICollectionViewCell {
    static let identifier = "MarkdownTableCell"
    
    private let label = UILabel()
    private let border = UIView()
    
    private var labelLeading: NSLayoutConstraint!
    private var labelTrailing: NSLayoutConstraint!
    private var labelTop: NSLayoutConstraint!
    private var labelBottom: NSLayoutConstraint!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        contentView.addSubview(label)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(border)
        border.translatesAutoresizingMaskIntoConstraints = false
        
        labelLeading = label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 0)
        labelTrailing = label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 0)
        labelTop = label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 0)
        labelBottom = label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: 0)
        
        NSLayoutConstraint.activate([
            labelLeading,
            labelTrailing,
            labelTop,
            labelBottom,
            
            border.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            border.topAnchor.constraint(equalTo: contentView.topAnchor),
            border.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            border.widthAnchor.constraint(equalToConstant: 0.5)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        label.attributedText = nil
    }
    
    func configure(
        text: NSAttributedString,
        isHeader: Bool,
        borderColor: UIColor,
        textAlignment: NSTextAlignment,
        geometry: MarkdownTableCellGeometry
    ) {
        // 只在值真的变化时赋值：横向滚动的 cell 复用是热路径，
        // 无条件写 constant 会每次都触发 setNeedsLayout。
        if labelTop.constant != geometry.verticalPadding {
            labelTop.constant = geometry.verticalPadding
            labelBottom.constant = -geometry.verticalPadding
        }
        if labelLeading.constant != geometry.horizontalPadding {
            labelLeading.constant = geometry.horizontalPadding
            labelTrailing.constant = -geometry.horizontalPadding
        }
        
        label.textAlignment = textAlignment
        if text.length > 0, text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) != nil {
            label.attributedText = text.withOverriddenParagraphAlignment(textAlignment)
        } else {
            label.attributedText = text
        }
        border.backgroundColor = borderColor
    }

    func firstLinkURL() -> URL? {
        guard let attrText = label.attributedText, attrText.length > 0 else { return nil }

        var foundURL: URL?
        attrText.enumerateAttribute(
            .link,
            in: NSRange(location: 0, length: attrText.length),
            options: []
        ) { value, _, stop in
            if let url = value as? URL {
                foundURL = url
                stop.pointee = true
            } else if let urlString = value as? String, let url = URL(string: urlString) {
                foundURL = url
                stop.pointee = true
            }
        }

        return foundURL
    }
}

private extension NSAttributedString {
    func withOverriddenParagraphAlignment(_ alignment: NSTextAlignment) -> NSAttributedString {
        guard length > 0 else { return self }
        let mutable = NSMutableAttributedString(attributedString: self)
        let fullRange = NSRange(location: 0, length: mutable.length)

        mutable.enumerateAttribute(.paragraphStyle, in: fullRange, options: []) { value, range, _ in
            let paragraphStyle: NSMutableParagraphStyle
            if let style = value as? NSParagraphStyle {
                paragraphStyle = style.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            } else {
                paragraphStyle = NSMutableParagraphStyle()
            }
            paragraphStyle.alignment = alignment
            mutable.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        }

        return mutable
    }
}

// MARK: - CollectionView Wrapper

class MarkdownTableCollectionView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    
    private var collectionView: UICollectionView!
    private let attachment: MarkdownTableAttachment
    
    init(frame: CGRect, attachment: MarkdownTableAttachment) {
        self.attachment = attachment
        super.init(frame: frame)
        setupCollectionView()
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    private func setupCollectionView() {
        layer.applyMarkdownBlockAppearance(attachment.configuration.tableAppearance)
        layer.masksToBounds = attachment.configuration.tableAppearance.cornerRadius > 0

        let layout = MarkdownTableLayout()
        layout.columnWidths = attachment.columnWidths
        layout.rowHeights = attachment.rowHeights
        
        collectionView = UICollectionView(frame: bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.allowsSelection = true
        collectionView.register(MarkdownTableCell.self, forCellWithReuseIdentifier: MarkdownTableCell.identifier)
        
        collectionView.isScrollEnabled = true
        collectionView.isDirectionalLockEnabled = true
        collectionView.showsHorizontalScrollIndicator = true
        collectionView.showsVerticalScrollIndicator = false
        
        addSubview(collectionView)
        mdLog("[MarkdownTable] view cols=\(attachment.columnWidths.count) sections=\(attachment.tableData.rows.count + 1) totalW=\(Int(attachment.totalSize.width))")
    }
    
    // MARK: DataSource
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1 + attachment.tableData.rows.count
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return attachment.columnWidths.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MarkdownTableCell.identifier, for: indexPath) as! MarkdownTableCell
        
        let isHeader = indexPath.section == 0
        let rowData: [NSAttributedString]
        
        if isHeader {
            rowData = attachment.tableData.headers
            cell.backgroundColor = attachment.configuration.tableHeaderBackgroundColor
        } else {
            rowData = attachment.tableData.rows[indexPath.section - 1]
            if (indexPath.section - 1) % 2 == 1 {
                cell.backgroundColor = attachment.configuration.tableAlternateRowBackgroundColor
            } else {
                cell.backgroundColor = attachment.configuration.tableRowBackgroundColor
            }
        }
        
        let text: NSAttributedString
        if indexPath.item < rowData.count {
            text = rowData[indexPath.item]
        } else {
            text = NSAttributedString(string: "")
        }

        let textAlignment = attachment.tableData.columnAlignments[safe: indexPath.item]
            .flatMap { $0 } ?? .left
        
        cell.configure(
            text: text,
            isHeader: isHeader,
            borderColor: attachment.configuration.tableBorderColor.withAlphaComponent(0.3),
            textAlignment: textAlignment,
            geometry: attachment.cellGeometry
        )
        
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let cell = collectionView.cellForItem(at: indexPath) as? MarkdownTableCell else { return }
        guard let url = cell.firstLinkURL() else { return }
        attachment.onLinkTap?(url)
    }
}

// MARK: - Text Attachment & Provider

class MarkdownTableAttachment: NSTextAttachment {
    let tableData: MarkdownTableData
    let configuration: MarkdownConfiguration
    let columnWidths: [CGFloat]
    let rowHeights: [CGFloat]
    let totalSize: CGSize
    let cellGeometry: MarkdownTableCellGeometry
    let onLinkTap: ((URL) -> Void)?
    
    init(
        data: MarkdownTableData,
        config: MarkdownConfiguration,
        containerWidth: CGFloat,
        layoutResult: MarkdownTableLayoutResult? = nil,
        onLinkTap: ((URL) -> Void)? = nil
    ) {
        self.tableData = data
        self.configuration = config
        self.onLinkTap = onLinkTap
        self.cellGeometry = MarkdownTableCellGeometry(config: config)
        
        let result = layoutResult ?? MarkdownTableLayoutCalculator.calculate(
            data: data,
            config: config,
            containerWidth: containerWidth
        )
        self.columnWidths = result.columnWidths
        self.rowHeights = result.rowHeights
        self.totalSize = result.totalSize
        mdLog("[MarkdownTable] created rows=\(data.rows.count + 1) cols=\(result.columnWidths.count) totalW=\(Int(result.totalSize.width)) totalH=\(Int(result.totalSize.height)) containerW=\(Int(containerWidth))")
        
        super.init(data: nil, ofType: nil)
        
        self.image = UIImage()
        self.bounds = CGRect(origin: .zero, size: self.totalSize)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func viewProvider(for parentView: UIView?, location: NSTextLocation, textContainer: NSTextContainer?) -> NSTextAttachmentViewProvider? {
        return MarkdownTableAttachmentProvider(
            textAttachment: self,
            parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager,
            location: location
        )
    }
}

class MarkdownTableAttachmentProvider: NSTextAttachmentViewProvider {
    override func loadView() {
        guard let tableAttachment = self.textAttachment as? MarkdownTableAttachment else { return }
        self.view = MarkdownTableCollectionView(
            frame: CGRect(origin: .zero, size: tableAttachment.totalSize),
            attachment: tableAttachment
        )
    }
}
