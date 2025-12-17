//
//  MarkdownImageAttachment.swift
//  MyLibrary
//
//  Created by 朱继超 on 12/15/25.
//

import UIKit

/// 自定义图片附件，支持按比例缩放
final class MarkdownImageAttachment: NSTextAttachment {
    
    var maxWidth: CGFloat = 0
    var maxHeight: CGFloat = 400
    var imageURL: String?
    
    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        // 如果已经手动设置了 bounds，直接返回
        if bounds.size.width > 0 && bounds.size.height > 0 {
            return bounds
        }
        
        guard let image = self.image else {
            return CGRect(x: 0, y: 0, width: 200, height: 150)
        }
        
        return CGRect(origin: .zero, size: scaledSize(for: image.size))
    }
    
    private func scaledSize(for imageSize: CGSize) -> CGSize {
        guard imageSize.width > 0 && imageSize.height > 0 else {
            return CGSize(width: 100, height: 100)
        }
        
        var targetWidth = imageSize.width
        var targetHeight = imageSize.height
        
        // 按宽度等比缩放
        if maxWidth > 0 && targetWidth > maxWidth {
            let scale = maxWidth / targetWidth
            targetWidth = maxWidth
            targetHeight = targetHeight * scale
        }
        
        // 按高度等比缩放
        if maxHeight > 0 && targetHeight > maxHeight {
            let scale = maxHeight / targetHeight
            targetHeight = maxHeight
            targetWidth = targetWidth * scale
        }
        
        return CGSize(width: ceil(targetWidth), height: ceil(targetHeight))
    }
}
