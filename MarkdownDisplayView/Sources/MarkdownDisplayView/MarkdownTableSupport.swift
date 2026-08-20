//
//  MarkdownTableSupport.swift
//  MarkdownDisplayView
//
//  Created by Gemini on 12/27/25.
//

import UIKit

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

        // 水平内边距（左右各 tableCellPadding）
        let horizontalPadding = config.tableCellPadding * 2

        // 1. Calculate Column Widths
        let columnCount = max(
            data.headers.count,
            data.rows.map(\.count).max() ?? 0
        )
        var columnWidths: [CGFloat] = Array(repeating: config.tableMinColumnWidth, count: columnCount)

        // Helper to measure text width
        func measureWidth(_ text: NSAttributedString) -> CGFloat {
            return text.boundingRect(
                with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: config.tableRowHeight),
                options: [.usesLineFragmentOrigin],
                context: nil
            ).width + horizontalPadding
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

        // Cap max width per column to prevent super wide columns
        columnWidths = columnWidths.map { min($0, config.tableMaxColumnWidth) }

        // 2. Calculate Row Heights
        var rowHeights: [CGFloat] = []

        func measureHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
            let availableWidth = max(1, width - horizontalPadding)
            return text.boundingRect(
                with: CGSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                context: nil
            ).height + config.tableCellVerticalPadding * 2 // 上下各 tableCellVerticalPadding
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
        let totalHeight = rowHeights.reduce(0, +) + CGFloat(rowHeights.count) * config.tableSeparatorHeight

        // Attachment Frame Width: min(totalWidth, containerWidth)
        // If table is smaller than screen, use table width.
        // If table is larger, use screen width (and scroll internally).
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

        // UITableView 自适应高度和 TextKit attachment 可能多次要求同一张表布局。
        // 表格几何只由列宽、行高决定；输入未变时复用 attributes，避免 O(rows × columns)
        // 地重复创建 UICollectionViewLayoutAttributes。
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
        print("[MarkdownTable] layout prepare cells=\(rowHeights.count * columnWidths.count) rebuild=\(layoutRebuildCount)")
        
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
        
        // 只遍历与 rect 相交的行(section)与列(item)区间，避免横向滚动时每帧全量过滤。
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
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        contentView.addSubview(label)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(border)
        border.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            
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
        textAlignment: NSTextAlignment
    ) {
        label.textAlignment = textAlignment
        // 表格单元格文本通常不带 .paragraphStyle（只有 .font/.link 等），
        // 直接用 label.textAlignment 即可。只有确实存在段落样式时才做对齐覆盖，
        // 避免每次横向滚动复用时都做一次全文拷贝 + 枚举（导致掉帧）。
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

        // 表格单元格文本使用富文本渲染，段落样式中的 alignment 优先级高于控件默认对齐。
        // 这里统一覆盖为列对齐，避免 Markdown 默认段落样式把对齐“拉回左侧”。
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
        
        // 允许水平滚动
        collectionView.isScrollEnabled = true
        // 横向锁定：嵌在纵向 UITableView 里时，避免与竖向滚动手势竞争导致卡顿
        collectionView.isDirectionalLockEnabled = true
        // 禁用垂直滚动（由外层处理），但 contentSize.height = frame.height，所以本身也不会垂直滚
        collectionView.showsHorizontalScrollIndicator = true
        collectionView.showsVerticalScrollIndicator = false
        
        addSubview(collectionView)
        print("[MarkdownTable] view cols=\(attachment.columnWidths.count) sections=\(attachment.tableData.rows.count + 1) totalW=\(Int(attachment.totalSize.width))")
    }
    
    // MARK: DataSource
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        // Headers (section 0) + Rows
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
            // Alternate colors
            if (indexPath.section - 1) % 2 == 1 {
                cell.backgroundColor = attachment.configuration.tableAlternateRowBackgroundColor
            } else {
                cell.backgroundColor = attachment.configuration.tableRowBackgroundColor
            }
        }
        
        // Safely get text
        let text: NSAttributedString
        if indexPath.item < rowData.count {
            text = rowData[indexPath.item]
        } else {
            text = NSAttributedString(string: "")
        }

        // 列对齐优先使用 Markdown 表格语法中的列对齐，缺省时回退为左对齐
        let textAlignment = attachment.tableData.columnAlignments[safe: indexPath.item]
            .flatMap { $0 } ?? .left
        
        // Use semi-transparent border to mimic grid
        cell.configure(
            text: text,
            isHeader: isHeader,
            borderColor: attachment.configuration.tableBorderColor.withAlphaComponent(0.3),
            textAlignment: textAlignment
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
        
        // Pre-calculate layout
        let result = layoutResult ?? MarkdownTableLayoutCalculator.calculate(
            data: data,
            config: config,
            containerWidth: containerWidth
        )
        self.columnWidths = result.columnWidths
        self.rowHeights = result.rowHeights
        self.totalSize = result.totalSize
        print("[MarkdownTable] created rows=\(data.rows.count + 1) cols=\(result.columnWidths.count) totalW=\(Int(result.totalSize.width)) totalH=\(Int(result.totalSize.height)) containerW=\(Int(containerWidth))")
        
        super.init(data: nil, ofType: nil)
        
        // Set an empty image to prevent the default placeholder icon from appearing
        self.image = UIImage()
        
        // Set attachment bounds
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
