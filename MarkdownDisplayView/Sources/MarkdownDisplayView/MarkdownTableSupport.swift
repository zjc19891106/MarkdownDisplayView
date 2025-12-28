//
//  MarkdownTableSupport.swift
//  MarkdownDisplayView
//
//  Created by Gemini on 12/27/25.
//

import UIKit

// MARK: - Layout Calculator

struct MarkdownTableLayoutCalculator {
    static func calculate(data: MarkdownTableData, font: UIFont, containerWidth: CGFloat) -> (columnWidths: [CGFloat], rowHeights: [CGFloat], totalSize: CGSize) {
        guard !data.headers.isEmpty || !data.rows.isEmpty else {
            return ([], [], .zero)
        }

        // 1. Calculate Column Widths
        let columnCount = max(data.headers.count, data.rows.first?.count ?? 0)
        var columnWidths: [CGFloat] = Array(repeating: 60, count: columnCount) // Min width 60

        // Helper to measure text width
        func measureWidth(_ text: NSAttributedString) -> CGFloat {
            return text.boundingRect(
                with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 44),
                options: [.usesLineFragmentOrigin],
                context: nil
            ).width + 32 // Padding: 12 left + 12 right + 8 buffer
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

        // Cap max width per column (e.g., 300) to prevent super wide columns
        // But also ensure we don't shrink too much
        columnWidths = columnWidths.map { min($0, 300) }
        
        // 2. Calculate Row Heights
        // We need to know exact height of each row given the column width
        var rowHeights: [CGFloat] = []
        
        func measureHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
            let availableWidth = width - 24 // Padding
            return text.boundingRect(
                with: CGSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                context: nil
            ).height + 20 // Vertical padding: 10 top + 10 bottom
        }

        // Header Height
        var headerHeight: CGFloat = 44
        for (i, header) in data.headers.enumerated() {
            if i < columnCount {
                headerHeight = max(headerHeight, measureHeight(header, width: columnWidths[i]))
            }
        }
        rowHeights.append(headerHeight)

        // Row Heights
        for row in data.rows {
            var rowHeight: CGFloat = 44
            for (i, cell) in row.enumerated() {
                if i < columnCount {
                    rowHeight = max(rowHeight, measureHeight(cell, width: columnWidths[i]))
                }
            }
            rowHeights.append(rowHeight)
        }

        let totalWidth = columnWidths.reduce(0, +)
        let totalHeight = rowHeights.reduce(0, +) + CGFloat(rowHeights.count) // +1 separator per row approx

        // Attachment Frame Width: min(totalWidth, containerWidth)
        // If table is smaller than screen, use table width.
        // If table is larger, use screen width (and scroll internally).
        let frameWidth = min(totalWidth, containerWidth)
        
        return (columnWidths, rowHeights, CGSize(width: frameWidth, height: totalHeight))
    }
}

// MARK: - Custom CollectionView Layout

class MarkdownTableLayout: UICollectionViewLayout {
    var columnWidths: [CGFloat] = []
    var rowHeights: [CGFloat] = []
    
    private var layoutAttributes: [IndexPath: UICollectionViewLayoutAttributes] = [:]
    private var contentSize: CGSize = .zero
    
    override func prepare() {
        super.prepare()
        layoutAttributes.removeAll()
        
        guard !columnWidths.isEmpty && !rowHeights.isEmpty else {
            contentSize = .zero
            return
        }
        
        var yOffset: CGFloat = 0
        var xOffsets: [CGFloat] = []
        var currentX: CGFloat = 0
        
        for width in columnWidths {
            xOffsets.append(currentX)
            currentX += width
        }
        
        let totalWidth = currentX
        
        for section in 0..<rowHeights.count {
            let height = rowHeights[section]
            
            for item in 0..<columnWidths.count {
                let indexPath = IndexPath(item: item, section: section)
                let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
                
                attributes.frame = CGRect(
                    x: xOffsets[item],
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
        return layoutAttributes.values.filter { $0.frame.intersects(rect) }
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
    
    func configure(text: NSAttributedString, isHeader: Bool, borderColor: UIColor) {
        label.attributedText = text
        border.backgroundColor = borderColor
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
        let layout = MarkdownTableLayout()
        layout.columnWidths = attachment.columnWidths
        layout.rowHeights = attachment.rowHeights
        
        collectionView = UICollectionView(frame: bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(MarkdownTableCell.self, forCellWithReuseIdentifier: MarkdownTableCell.identifier)
        
        // 允许水平滚动
        collectionView.isScrollEnabled = true 
        // 禁用垂直滚动（由外层处理），但 contentSize.height = frame.height，所以本身也不会垂直滚
        collectionView.showsHorizontalScrollIndicator = true
        collectionView.showsVerticalScrollIndicator = false
        
        addSubview(collectionView)
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
        
        // Use semi-transparent border to mimic grid
        cell.configure(text: text, isHeader: isHeader, borderColor: attachment.configuration.tableBorderColor.withAlphaComponent(0.3))
        
        return cell
    }
}

// MARK: - Text Attachment & Provider

class MarkdownTableAttachment: NSTextAttachment {
    let tableData: MarkdownTableData
    let configuration: MarkdownConfiguration
    let columnWidths: [CGFloat]
    let rowHeights: [CGFloat]
    let totalSize: CGSize
    
    init(data: MarkdownTableData, config: MarkdownConfiguration, containerWidth: CGFloat) {
        self.tableData = data
        self.configuration = config
        
        // Pre-calculate layout
        let result = MarkdownTableLayoutCalculator.calculate(
            data: data,
            font: config.bodyFont,
            containerWidth: containerWidth
        )
        self.columnWidths = result.columnWidths
        self.rowHeights = result.rowHeights
        self.totalSize = result.totalSize
        
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
