//
//  ImageCacheManager.swift
//  ChatUIKit
//
//  Created by 朱继超 on 2023/9/1.
//

import Foundation
import UIKit
import Combine

/**
 A singleton class that manages caching of images in memory and on disk.
 */
final public class ImageCacheManager {
    
    public static let shared = ImageCacheManager()
    
    /// The memory cache used to store images.
    private let memoryCache = NSCache<NSString, UIImage>()
    
    /// The file manager used to manage files on disk.
    private let fileManager = FileManager.default
    
    /// The directory used to store cached images on disk.
    private let cacheDirectory = NSTemporaryDirectory() + "ImageCache/"
    
    /// A set of cancellables used to cancel image loading tasks.
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        self.createCacheDirectory()
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] out in
                self?.memoryCache.removeAllObjects()
            }
            .store(in: &cancellables)
    }
    
    /**
     Creates a cache directory using the file manager. If the directory already exists, it will not be recreated.

     - Returns: Void
    */
    private func createCacheDirectory() {
        do {
            try self.fileManager.createDirectory(atPath: self.cacheDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Failed to create cache directory: \(error)")
        }
    }
    
     private func cachePath(for key: String) -> String {
       return cacheDirectory + key.replacingOccurrences(of: "/", with: "-")
    }
    
    /**
     Returns the image for the given key if it exists in the memory cache or disk cache.
     
     - Parameter key: The key used to identity the image.
     - Returns: The image for the given key if it exists in the memory cache or disk cache, otherwise returns nil.
     */
     public func image(for key: String) -> UIImage? {
        // Check memory cache first
        if let cachedImage = self.memoryCache.object(forKey: key as NSString) {
            return cachedImage
        }
        
        // Check disk cache
        let filePath = self.cachePath(for: key)
        if self.fileManager.fileExists(atPath: filePath) {
            if let data = self.fileManager.contents(atPath: filePath), let image = UIImage(data: data) {
                // Cache the image to memory
                self.memoryCache.setObject(image, forKey: key as NSString)
                return image
            }
        }
        
        return nil
    }
    
    /**
     Caches the given image for the specified key in memory and on disk.
     
     - Parameters:
        - image: The image to be cached.
        - key: The key to associate with the image.
     */
    func cacheImage(_ image: UIImage, for key: String) {
        DispatchQueue.main.async {
            self.memoryCache.setObject(image, forKey: key as NSString)
            
            // Save image to disk cache
            let filePath = self.cachePath(for: key)
            if let data = image.pngData()  {
                self.fileManager.createFile(atPath: filePath, contents: data, attributes: nil)
            }
        }
    }
    
    
}
