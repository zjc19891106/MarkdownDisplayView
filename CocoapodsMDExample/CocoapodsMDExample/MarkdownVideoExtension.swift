//
//  MarkdownVideoExtension.swift
//  CocoapodsMDExample
//
//  视频扩展示例
//  演示如何实现自定义行内语法解析和渲染
//

import UIKit
import QuickLook
import AVFoundation
import MarkdownDisplayKit

// MARK: - Video Parser

/// 视频语法解析器
/// 支持格式: [video:filename] 或 [video:filename.ext]
public final class MarkdownVideoParser: MarkdownCustomParser {
    public let identifier = "video"
    public let pattern = "\\[video:([^\\]]+)\\]"

    public init() {}

    public func parse(match: NSTextCheckingResult, in text: String) -> CustomElementData? {
        guard match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }

        let filename = String(text[range])

        return CustomElementData(
            type: "video",
            rawText: "[video:\(filename)]",
            payload: ["filename": filename]
        )
    }
}

// MARK: - Video View Provider

/// 视频视图提供者
public final class MarkdownVideoViewProvider: MarkdownCustomViewProvider {
    public let supportedType = "video"

    public init() {}

    public func createView(
        for data: CustomElementData,
        configuration: MarkdownConfiguration,
        containerWidth: CGFloat
    ) -> UIView {
        let filename = data.payload["filename"] ?? "video"
        let size = calculateSize(for: data, configuration: configuration, containerWidth: containerWidth)

        let container = VideoPreviewView(
            filename: filename,
            data: data,
            frame: CGRect(origin: .zero, size: size)
        )
        return container
    }

    public func calculateSize(
        for data: CustomElementData,
        configuration: MarkdownConfiguration,
        containerWidth: CGFloat
    ) -> CGSize {
        let width = containerWidth - 32
        let height = width * 9 / 16 // 16:9 比例
        return CGSize(width: width, height: height)
    }
}

// MARK: - Video Preview View

/// 视频预览视图
final class VideoPreviewView: UIView {

    private let filename: String
    private let data: CustomElementData
    private let preferredSize: CGSize  // 保存计算好的尺寸

    private let thumbnailImageView = UIImageView()
    private let playButton = UIButton(type: .custom)
    private let durationLabel = UILabel()
    private let titleLabel = UILabel()

    init(filename: String, data: CustomElementData, frame: CGRect) {
        self.filename = filename
        self.data = data
        self.preferredSize = frame.size
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false  // 使用 Auto Layout
        setupUI()
        loadThumbnail()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Intrinsic Content Size

    override var intrinsicContentSize: CGSize {
        return preferredSize
    }

    private func setupUI() {
        backgroundColor = .black
        layer.cornerRadius = 12
        clipsToBounds = true

        // 设置高度约束
        heightAnchor.constraint(equalToConstant: preferredSize.height).isActive = true

        // 缩略图
        thumbnailImageView.contentMode = .scaleAspectFill
        thumbnailImageView.clipsToBounds = true
        thumbnailImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumbnailImageView)

        // 渐变遮罩（底部）
        let gradientView = GradientView()
        gradientView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gradientView)

        // 播放按钮
        let playConfig = UIImage.SymbolConfiguration(pointSize: 50, weight: .regular)
        let playImage = UIImage(systemName: "play.circle.fill", withConfiguration: playConfig)
        playButton.setImage(playImage, for: .normal)
        playButton.tintColor = .white
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)

        // 添加点击高亮效果
        playButton.adjustsImageWhenHighlighted = true
        addSubview(playButton)

        // 时长标签
        durationLabel.font = .systemFont(ofSize: 12, weight: .medium)
        durationLabel.textColor = .white
        durationLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        durationLabel.layer.cornerRadius = 4
        durationLabel.clipsToBounds = true
        durationLabel.textAlignment = .center
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(durationLabel)

        // 标题标签
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.text = filename
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            // 缩略图填满
            thumbnailImageView.topAnchor.constraint(equalTo: topAnchor),
            thumbnailImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            thumbnailImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            thumbnailImageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // 渐变遮罩在底部
            gradientView.leadingAnchor.constraint(equalTo: leadingAnchor),
            gradientView.trailingAnchor.constraint(equalTo: trailingAnchor),
            gradientView.bottomAnchor.constraint(equalTo: bottomAnchor),
            gradientView.heightAnchor.constraint(equalToConstant: 60),

            // 播放按钮居中
            playButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 60),
            playButton.heightAnchor.constraint(equalToConstant: 60),

            // 时长在右下角
            durationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            durationLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            durationLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 50),
            durationLabel.heightAnchor.constraint(equalToConstant: 24),

            // 标题在左下角
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: durationLabel.leadingAnchor, constant: -8)
        ])

        // 整个视图可点击
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(playTapped))
        addGestureRecognizer(tapGesture)
    }

    private func loadThumbnail() {
        guard let videoURL = findVideoURL() else {
            thumbnailImageView.backgroundColor = .darkGray
            durationLabel.text = " N/A "
            return
        }

        // 异步生成缩略图
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let asset = AVAsset(url: videoURL)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true

            // 获取第一帧
            let time = CMTime(seconds: 0.5, preferredTimescale: 600)
            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                let thumbnail = UIImage(cgImage: cgImage)

                // 获取时长
                let duration = CMTimeGetSeconds(asset.duration)
                let durationText = self?.formatDuration(duration) ?? ""

                DispatchQueue.main.async {
                    self?.thumbnailImageView.image = thumbnail
                    self?.durationLabel.text = " \(durationText) "
                }
            } catch {
                DispatchQueue.main.async {
                    self?.thumbnailImageView.backgroundColor = .darkGray
                    self?.durationLabel.text = " N/A "
                }
            }
        }
    }

    private func findVideoURL() -> URL? {
        // 尝试多种文件名格式
        let possibleNames = [
            filename,
            filename.replacingOccurrences(of: ".mov", with: ""),
            filename.replacingOccurrences(of: ".mp4", with: "")
        ]

        let possibleExtensions = ["mov", "mp4", "m4v"]

        for name in possibleNames {
            for ext in possibleExtensions {
                if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                    return url
                }
            }
        }

        return nil
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    @objc private func playTapped() {
        // 通知事件处理器
        if let handler = MarkdownCustomExtensionManager.shared.actionHandler(for: "video") {
            handler.handleTap(data: data, sourceView: self, presentingViewController: findViewController())
        }
    }

    private func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let r = responder {
            if let vc = r as? UIViewController {
                return vc
            }
            responder = r.next
        }
        return nil
    }
}

// MARK: - Gradient View

private final class GradientView: UIView {
    override class var layerClass: AnyClass {
        return CAGradientLayer.self
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupGradient()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGradient()
    }

    private func setupGradient() {
        guard let gradientLayer = layer as? CAGradientLayer else { return }
        gradientLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.7).cgColor
        ]
        gradientLayer.locations = [0.0, 1.0]
    }
}

// MARK: - Video Action Handler

/// 视频点击事件处理器（使用 QuickLook）
public final class MarkdownVideoActionHandler: NSObject, MarkdownCustomActionHandler, QLPreviewControllerDataSource {

    public let supportedType = "video"

    private var currentVideoURL: URL?
    private weak var presentingVC: UIViewController?

    public override init() {
        super.init()
    }

    public func handleTap(data: CustomElementData, sourceView: UIView, presentingViewController: UIViewController?) {
        guard let filename = data.payload["filename"],
              let videoURL = findVideoURL(filename: filename) else {
            print("⚠️ [Video] Cannot find video file: \(data.payload["filename"] ?? "unknown")")
            return
        }

        currentVideoURL = videoURL
        presentingVC = presentingViewController

        let previewController = QLPreviewController()
        previewController.dataSource = self
        previewController.modalPresentationStyle = .fullScreen

        presentingViewController?.present(previewController, animated: true)
    }

    private func findVideoURL(filename: String) -> URL? {
        let possibleNames = [
            filename,
            filename.replacingOccurrences(of: ".mov", with: ""),
            filename.replacingOccurrences(of: ".mp4", with: "")
        ]

        let possibleExtensions = ["mov", "mp4", "m4v"]

        for name in possibleNames {
            for ext in possibleExtensions {
                if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                    return url
                }
            }
        }

        return nil
    }

    // MARK: - QLPreviewControllerDataSource

    public func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return currentVideoURL != nil ? 1 : 0
    }

    public func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return currentVideoURL! as QLPreviewItem
    }
}

// MARK: - Convenience Registration

public extension MarkdownCustomExtensionManager {

    /// 注册视频扩展（一键注册）
    func registerVideoExtension() {
        register(parser: MarkdownVideoParser())
        register(viewProvider: MarkdownVideoViewProvider())
        register(actionHandler: MarkdownVideoActionHandler())
        print("✅ [Video] Video extension registered")
    }
}
