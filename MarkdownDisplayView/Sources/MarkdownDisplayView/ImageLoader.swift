//
//  ImageLoader.swift
//  CallUIKit
//
//  Created by 朱继超 on 2023/9/1.
//

import Foundation

import UIKit
import Combine

/**
 private var cancellables = Set<AnyCancellable>()
 let imageURL = URL(string: "https://example.com/image.jpg")!
 
 ImageLoader.shared.loadImage(from: imageURL)
     .sink(receiveValue: { [weak self] image in
         self?.imageView.image = image
     })
     .store(in: &cancellables)
 */

/// An Image loader
public struct ImageLoader {
    public static let shared = ImageLoader()
    private let cache = ImageCacheManager.shared
    
    /// Load image from url.
    /// - Parameter url: image url
    /// - Returns: An
    /// - How to user? See above the ImageLoader.
    public func loadImage(from url: URL) -> AnyPublisher<UIImage?, Never> {
        if let cachedImage = cache.image(for: url.absoluteString) {
            return Just(cachedImage).eraseToAnyPublisher()
        } else {
            return URLSession.shared.dataTaskPublisher(for: url)
                .map({
                    if ($0.response as? HTTPURLResponse)?.statusCode ?? 0 != 200 {
                        return  UIImage()
                    } else {
                        return UIImage(data: $0.data) ?? UIImage()
                    }
                })
                .map({ image in
                    if image.size != .zero {
                        self.cache.cacheImage(image, for: url.absoluteString)
                        return image
                    }
                    return UIImage()
                })
                .replaceError(with: UIImage())
                .receive(on: DispatchQueue.main)
                .eraseToAnyPublisher()
        }
    }
}
