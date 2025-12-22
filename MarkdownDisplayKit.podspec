#
# Be sure to run `pod lib lint MarkdownDisplayKit.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'MarkdownDisplayKit'
  s.version          = '1.2.0'
  s.summary          = '一个功能强大的 iOS Markdown 渲染组件，基于 TextKit 2 构建，提供流畅的渲染性能和丰富的自定义选项。'

  s.description      = <<-DESC
  MarkdownDisplayKit 是一个高性能的 iOS Markdown 渲染库，基于 Apple 的 TextKit 2 框架构建。

  主要特性：
  • 完整的 Markdown 语法支持（标题、列表、表格、代码块等）
  • 20+ 编程语言的代码高亮
  • 流式渲染支持（打字机效果）
  • 自动生成文档目录
  • 深色模式支持
  • 高性能异步渲染
  • 丰富的自定义选项（字体、颜色、间距等）
  • 支持图片异步加载和缓存

  注意：本库依赖 swift-markdown 进行 Markdown 解析。由于 swift-markdown 尚未发布到 CocoaPods trunk，
  您需要在 Podfile 中手动添加该依赖。详见 README 安装说明。
                       DESC

  s.homepage         = 'https://github.com/zjc19891106/MarkdownDisplayView'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'zjc19891106' => '984065974@qq.com' }
  s.source           = { :git => 'https://github.com/zjc19891106/MarkdownDisplayView.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.swift_versions = ['5.9']
  s.source_files = 'MarkdownDisplayView/**/*.swift'  # 递归匹配 MarkdownDisplayView/ 下所有 .swift
  s.exclude_files = 'MarkdownDisplayView/Tests/**/*', 'MarkdownDisplayView/Package.swift'

  # KaTeX 字体资源
  s.resource_bundles = {
    'MarkdownDisplayKit' => ['MarkdownDisplayView/Sources/MarkdownDisplayView/Resources/*.ttf']
  }

  # System frameworks
  s.frameworks = 'UIKit', 'Foundation', 'Combine', 'NaturalLanguage'

  s.dependency 'AppleSwiftMDWrapper', '1.1.0'
end
