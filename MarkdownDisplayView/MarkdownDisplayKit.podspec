#
# Be sure to run `pod lib lint MarkdownDisplayKit.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'MarkdownDisplayKit'
  s.version          = '1.0.0'
  s.summary          = '一个功能强大的 iOS Markdown 渲染组件，基于 TextKit 2 构建，提供流畅的渲染性能和丰富的自定义选项。同时也支持流式渲染md格式。'

  s.description      = <<-DESC
TODO: Add long description of the pod here.
                       DESC

  s.homepage         = 'https://github.com/zjc19891106/MarkdownDisplayView'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'zjc19891106' => '984065974@qq.com' }
  s.source           = { :git => 'https://github.com/zjc19891106/MarkdownDisplayView.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'

  s.source_files = 'Sources/MarkdownDisplayView/**/*.swift'
  

end
