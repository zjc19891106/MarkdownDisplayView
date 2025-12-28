//
//  FontLoader.swift
//  MarkdownDisplayView
//
//  Created by AI Assistant on 12/19/25.
//

import Foundation
import CoreGraphics
import CoreText

/// KaTeX 字体加载器
/// 负责动态注册 KaTeX 字体到系统
public final class FontLoader {

    /// 单例
    static let shared = FontLoader()

    /// 字体是否已注册
    private var isRegistered = false

    /// 注册锁
    private let lock = NSLock()

    /// KaTeX 字体文件名列表
    private let fontNames = [
        "KaTeX_AMS-Regular.ttf",
        "KaTeX_Caligraphic-Bold.ttf",
        "KaTeX_Caligraphic-Regular.ttf",
        "KaTeX_Fraktur-Bold.ttf",
        "KaTeX_Fraktur-Regular.ttf",
        "KaTeX_Main-Bold.ttf",
        "KaTeX_Main-BoldItalic.ttf",
        "KaTeX_Main-Italic.ttf",
        "KaTeX_Main-Regular.ttf",
        "KaTeX_Math-BoldItalic.ttf",
        "KaTeX_Math-Italic.ttf",
        "KaTeX_SansSerif-Bold.ttf",
        "KaTeX_SansSerif-Italic.ttf",
        "KaTeX_SansSerif-Regular.ttf",
        "KaTeX_Script-Regular.ttf",
        "KaTeX_Size1-Regular.ttf",
        "KaTeX_Size2-Regular.ttf",
        "KaTeX_Size3-Regular.ttf",
        "KaTeX_Size4-Regular.ttf",
        "KaTeX_Typewriter-Regular.ttf"
    ]

    private init() {}

    /// 注册所有 KaTeX 字体
    func registerFonts() {
        lock.lock()
        defer { lock.unlock() }

        guard !isRegistered else { return }

        // 获取资源 bundle
        guard let resourceBundle = getResourceBundle() else {
            print("⚠️ [FontLoader] 无法找到资源 bundle")
            return
        }

        var successCount = 0
        var failedFonts: [String] = []

        // 注册每个字体
        for fontName in fontNames {
            if registerFont(named: fontName, in: resourceBundle) {
                successCount += 1
            } else {
                failedFonts.append(fontName)
            }
        }

        isRegistered = true

        print("✅ [FontLoader] 成功注册 \(successCount)/\(fontNames.count) 个字体")

        if !failedFonts.isEmpty {
            print("⚠️ [FontLoader] 以下字体注册失败：")
            failedFonts.forEach { print("   - \($0)") }
        }
    }

    /// 获取资源 bundle
    private func getResourceBundle() -> Bundle? {
        #if SWIFT_PACKAGE
        // SPM 环境：使用 Bundle.module
        return Bundle.module
        #else
        // CocoaPods 环境：从 resource_bundles 获取
        let bundleName = "MarkdownDisplayKit"

        // 尝试多种查找路径
        if let bundleURL = Bundle(for: FontLoader.self).url(forResource: bundleName, withExtension: "bundle"),
           let bundle = Bundle(url: bundleURL) {
            return bundle
        }

        // 回退到主 bundle
        if let bundleURL = Bundle.main.url(forResource: bundleName, withExtension: "bundle"),
           let bundle = Bundle(url: bundleURL) {
            return bundle
        }

        // 最后尝试直接使用类的 bundle
        return Bundle(for: FontLoader.self)
        #endif
    }

    /// 注册单个字体
    private func registerFont(named fontName: String, in bundle: Bundle) -> Bool {
        // 从 Resources 目录查找字体文件
        guard let fontURL = bundle.url(
            forResource: fontName.replacingOccurrences(of: ".ttf", with: ""),
            withExtension: "ttf",
            subdirectory: "Resources"
        ) else {
            // 如果 Resources 目录不存在，尝试直接查找
            guard let fontURL = bundle.url(
                forResource: fontName.replacingOccurrences(of: ".ttf", with: ""),
                withExtension: "ttf"
            ) else {
                print("⚠️ [FontLoader] 找不到字体文件：\(fontName)")
                return false
            }

            return registerFontFromURL(fontURL, fontName: fontName)
        }

        return registerFontFromURL(fontURL, fontName: fontName)
    }

    /// 从 URL 注册字体
    private func registerFontFromURL(_ fontURL: URL, fontName: String) -> Bool {
        guard let fontDataProvider = CGDataProvider(url: fontURL as CFURL),
              let font = CGFont(fontDataProvider) else {
            print("⚠️ [FontLoader] 无法创建 CGFont：\(fontName)")
            return false
        }

        var error: Unmanaged<CFError>?
        let success = CTFontManagerRegisterGraphicsFont(font, &error)

        if !success {
            if let error = error?.takeRetainedValue() {
                let errorDescription = CFErrorCopyDescription(error) as String
                // 忽略"已注册"的错误
                if !errorDescription.contains("already registered") {
                    print("⚠️ [FontLoader] 注册字体失败：\(fontName), 错误：\(errorDescription)")
                }
            }
            return false
        }

        return true
    }
}

/// 字体加载器扩展 - 自动注册
public extension FontLoader {

    /// 确保字体已注册（在使用字体前调用）
    static func ensureFontsRegistered() {
        shared.registerFonts()
    }
}
