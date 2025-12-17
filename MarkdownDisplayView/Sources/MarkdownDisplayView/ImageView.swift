//
//  ImageView.swift
//  ChatUIKit
//
//  Created by 朱继超 on 2023/9/1.
//

import UIKit
import ImageIO
import Combine

/// A subclass of `UIImageView` that provides a method for loading an image from a URL.
@objc final public class ImageView: UIImageView {

    private var cancellables = Set<AnyCancellable>()
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// Loads an image from the specified URL and sets it as the image of the image view.
    /// - Parameters:
    ///   - url: The URL of the image to load.
    ///   - placeHolder: An optional placeholder image to display while the image is being loaded.
    @MainActor public func image(with url: String,placeHolder: UIImage?) {
        self.image = placeHolder
        var urlString = ""
        if url.hasSuffix(".png") || url.hasSuffix(".jpg") || url.hasSuffix(".jpeg") {
            urlString = url
        } else {
            urlString = url.lowercased()
        }
        if !url.hasPrefix("http://"), !url.hasPrefix("https://") {
            urlString = "https://" + url
        } else {
            if url.hasPrefix("http://") {
                if let index = urlString.index(urlString.startIndex, offsetBy: 4, limitedBy: urlString.endIndex) {
                    urlString.insert("s", at: index)
                }
            }
        }
        guard let imageURL = URL(string: urlString) else {
            return
        }
        ImageLoader.shared.loadImage(from: imageURL)
            .sink(receiveValue: { [weak self] url_image in
                if url_image != nil,url_image?.size ?? .zero != .zero {
                    self?.image = url_image
                }
            })
            .store(in: &self.cancellables)
    }

    /// Loads an image from the specified URL and sets it as the image of the image view.
    /// - Parameters:
    ///   - url: The URL of the image to load.
    ///   - placeHolder: An optional placeholder image to display while the image is being loaded.
    ///   - loadFinished: Load finished callback.
    public func image(with url: String,placeHolder: UIImage?,loadFinished: @escaping (UIImage?) -> Void) {
        self.image = placeHolder
        guard let imageURL = URL(string: url) else {
            return
        }
        ImageLoader.shared.loadImage(from: imageURL)
            .sink(receiveValue: { [weak self] url_image in
                if url_image != nil,url_image?.size ?? .zero != .zero  {
                    self?.image = url_image
                    loadFinished(url_image)
                }
            })
            .store(in: &self.cancellables)
    }
}

//extension ImageView {
//    public func loadGif(from path: String) {
//        DispatchQueue.global().async {
//            let cachedKey = NSString(string: path)
//            
//            if let cachedImage = ImageCacheManager.shared.image(for: path) {
//                DispatchQueue.main.async {
//                    self.image = cachedImage
//                }
//            } else {
//                let image = UIImage.gif(from: path)
//                if let image = image {
//                    ImageCacheManager.shared.cacheImage(image, for: path)
//                }
//                DispatchQueue.main.async {
//                    self.image = image
//                }
//            }
//        }
//    }
//}
//
//extension UIImage {
//    
//    public class func gif(from path: String) -> UIImage? {
//        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
////            consoleLogInfo("SwiftGif: Cannot turn image at path \"\(path)\" into NSData", type: .error)
//            return nil
//        }
//        return gif(data: data)
//    }
//
//    public class func gif(data: Data) -> UIImage? {
//        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
////            consoleLogInfo("SwiftGif: Source for the image does not exist", type: .error)
//            return nil
//        }
//        return UIImage.animatedImageWithSource(source)
//    }
//
//    class func delayForImageAtIndex(_ index: Int, source: CGImageSource!) -> Double {
//        var delay = 0.1
//
//        let cfProperties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
//        let gifProperties: CFDictionary = unsafeBitCast(
//            CFDictionaryGetValue(cfProperties,
//                                 Unmanaged.passUnretained(kCGImagePropertyGIFDictionary).toOpaque()),
//            to: CFDictionary.self)
//
//        var delayObject: AnyObject = unsafeBitCast(
//            CFDictionaryGetValue(gifProperties,
//                                 Unmanaged.passUnretained(kCGImagePropertyGIFUnclampedDelayTime).toOpaque()),
//            to: AnyObject.self)
//        if delayObject.doubleValue == 0 {
//            delayObject = unsafeBitCast(
//                CFDictionaryGetValue(gifProperties,
//                                     Unmanaged.passUnretained(kCGImagePropertyGIFDelayTime).toOpaque()),
//                to: AnyObject.self)
//        }
//
//        if let delayObject = delayObject as? Double, delayObject > 0 {
//            delay = delayObject
//        }
//
//        return delay
//    }
//
//    class func gcdForPair(_ a: Int?, _ b: Int?) -> Int {
//        var a = a
//        var b = b
//        if b == nil || a == nil {
//            if b != nil {
//                return b!
//            } else if a != nil {
//                return a!
//            } else {
//                return 0
//            }
//        }
//
//        if a! < b! {
//            let c = a
//            a = b
//            b = c
//        }
//
//        var rest: Int
//        while true {
//            rest = a! % b!
//
//            if rest == 0 {
//                return b!
//            } else {
//                a = b
//                b = rest
//            }
//        }
//    }
//
//    class func gcdForArray(_ array: Array<Int>) -> Int {
//        if array.isEmpty {
//            return 1
//        }
//
//        var gcd = array[0]
//
//        for val in array {
//            gcd = UIImage.gcdForPair(val, gcd)
//        }
//
//        return gcd
//    }
//
//    class func animatedImageWithSource(_ source: CGImageSource) -> UIImage? {
//        let count = CGImageSourceGetCount(source)
//        var images = [CGImage]()
//        var delays = [Int]()
//
//        for i in 0..<count {
//            if let image = CGImageSourceCreateImageAtIndex(source, i, nil) {
//                images.append(image)
//            }
//
//            let delaySeconds = UIImage.delayForImageAtIndex(Int(i),
//                                                            source: source)
//            delays.append(Int(delaySeconds * 1000.0)) // Seconds to ms
//        }
//
//        let duration: Int = {
//            var sum = 0
//
//            for val: Int in delays {
//                sum += val
//            }
//
//            return sum
//        }()
//
//        let gcd = gcdForArray(delays)
//        var frames = [UIImage]()
//
//        var frame: UIImage
//        var frameCount: Int
//        for i in 0..<count {
//            frame = UIImage(cgImage: images[Int(i)])
//            frameCount = Int(delays[Int(i)] / gcd)
//
//            for _ in 0..<frameCount {
//                frames.append(frame)
//            }
//        }
//
//        let animation = UIImage.animatedImage(with: frames,
//                                              duration: Double(duration) / 1000.0)
//
//        return animation
//    }
//}
