//
//  MarkdownExampleViewController.swift
//  ExampleForMarkdown
//
//  Created by 朱继超 on 12/15/25.
//

import UIKit
import MarkdownDisplayView

/// 示例 ViewController，展示 MarkdownView 的使用方法
class MarkdownExampleViewController: UIViewController {

    private let scrollableMarkdownView = ScrollableMarkdownViewTextKit()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadSampleMarkdown()
    }

    private func setupUI() {
        
        self.view.backgroundColor = .white
        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.text = "Sync Markdown Preview"
        titleLabel.backgroundColor = .systemBackground
        titleLabel.textColor = .systemBlue
        view.addSubview(titleLabel)
        
        let backButton = UIButton(type: .system)
        backButton.setTitle("返回目录", for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        backButton.addTarget(self, action: #selector(backToMenus), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backButton)

        // 关闭按钮
        let closeButton = UIButton(type: .system)
        closeButton.setTitle("关闭", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        closeButton.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        view.addSubview(scrollableMarkdownView)

        scrollableMarkdownView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            titleLabel.heightAnchor.constraint(equalToConstant: 44),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            backButton.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            backButton.heightAnchor.constraint(equalToConstant: 44),
            closeButton.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            scrollableMarkdownView.topAnchor.constraint(
                equalTo: closeButton.bottomAnchor, constant: 8),
            scrollableMarkdownView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollableMarkdownView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollableMarkdownView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // 设置链接点击回调
        scrollableMarkdownView.onLinkTap = { [weak self] url in
            self?.handleLinkTap(url)
        }
        scrollableMarkdownView.onImageTap = { imageURL in
            //获取图片,如果已经加载出来
            _ = ImageCacheManager.shared.image(for: imageURL)
        }
        scrollableMarkdownView.onTOCItemTap = { item in
            print("title:\(item.title), level:\(item.level), id:\(item.id)")
        }
    }

    @objc private func dismissSelf() {
        dismiss(animated: true, completion: nil)
    }
    
    @objc private func backToMenus() {
        scrollableMarkdownView.backToTableOfContentsSection()
    }

    private func handleLinkTap(_ url: URL) {
        // 处理链接点击
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    private func loadSampleMarkdown() {
        let start = CFAbsoluteTimeGetCurrent()
        scrollableMarkdownView.markdown = sampleMarkdown
        let end = CFAbsoluteTimeGetCurrent()
        print(
            "[MarkdownViewExample] Sync View Render Time: \(String(format: "%.2f", (end - start) * 1000))ms"
        )
    }
}

// MARK: - 示例 Markdown 内容

let sampleMarkdown = """
    # MarkdownView 完整功能测试文档

    这是一个全面的 Markdown 边界测试文档，用于验证 MarkdownView 对各种格式的支持情况。

    ## 目录

    本文档包含以下测试内容：

    1. [公式测试](#公式测试)
    2. [标题层级测试](#标题层级测试)
    3. [文本格式测试](#文本格式测试)
    4. [链接测试](#链接测试)
    5. [图片测试](#图片测试)
    6. [列表测试](#列表测试)
    7. [引用测试](#引用测试)
    8. [代码测试](#代码测试)
    9. [表格测试](#表格测试)
    10. [分隔线测试](#分隔线测试)
    11. [脚注测试](#脚注测试)
    12. [自定义样式测试](#自定义样式测试)
    13. [混合内容测试](#混合内容测试)
    14. [边界情况测试](#边界情况测试)
    15. [CocoaPods (折叠)](#CocoaPods)


    ## CocoaPods

    使用`pod init`命令创建podfile文件,在podfile中添加如下依赖

    <details>
    <summary>点击展开/收起 Podfile 配置代码</summary>

    ```ruby
    source 'https://github.com/CocoaPods/Specs.git'
    platform :ios, '15.0'

    target 'YourTarget' do
      use_frameworks!

      pod 'EaseCallUIKit'
    end

    post_install do |installer|
      installer.pods_project.targets.each do |target|
        target.build_configurations.each do |config|
          config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
        end
      end
    end
    ```
    </details>

    ---
    # 一、公式测试

    ## 1.1 二次方程公式

    $$\\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}$$

    ## 1.2 高斯积分

    $$\\int_{0}^{\\infty} e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}$$

    ## 1.3 矩阵 (bmatrix)

    $$\\begin{bmatrix} 1 & x & x^2 \\\\\\\\ 0 & 1 & 2x \\\\\\\\ 0 & 0 & 2 \\end{bmatrix}$$

    ## 1.4 嵌套混合

    $$f(x) = \\begin{pmatrix} \\frac{1}{2} & \\sqrt{x} \\\\\\\\ \\alpha & \\beta \\end{pmatrix}$$

    ## 1.5 求和公式

    $$\\sum_{i=0}^{n} i^2 = \\frac{n(n+1)(2n+1)}{6}$$

    ## 1.6 极限

    $$\\lim_{x \\to 0} \\frac{\\sin x}{x} = 1$$

    ## 1.7 动态括号

    $$\\left( \\frac{a}{b} + c \\right) \\times \\left[ 1 + x \\right]$$

    ## 1.8 定积分

    $$\\int_{a}^{b} f(x) dx$$

    ## 1.9 物理向量与样式

    $$\\mathbf{F} = m \\vec{a} \\quad \\mathrm{(Newton's Law)}$$

    ## 1.10 颜色与装饰符

    $$\\bar{x} = \\frac{1}{n} \\color{red}{\\sum_{i=1}^{n} x_i}$$

    ## 1.11 各类重音符号

    $$\\hat{v} = \\frac{\\dot{r}}{|r|}$$

    ## 1.12 文本混排

    $$\\text{if } x > 0, \\quad y = \\color{blue}{\\sqrt{x}}$$

    ## 1.13 物理平均速度

    $$\\overline{v} = \\boxed{\\frac{\\Delta x}{\\Delta t}}$$

    ## 1.14 概率组合数

    $$P(A) = \\frac{\\binom{n}{k}}{2^n}$$

    ## 1.15 分段函数

    $$f(x) = \\begin{cases} x^2 & x > 0 \\\\\\\\ -x & x \\le 0 \\end{cases}$$

    ## 1.16 下划线标记

    $$\\underline{A} \\cup \\underline{B} = \\text{All}$$

    ## 1.17 伸缩箭头

    $$A \\xrightarrow{\\text{heat}} B$$

    ## 1.18 化学反应

    $$\\ce{2H2 + O2 -> 2H2O}$$

    ## 1.19 离子方程式

    $$\\ce{Cu^2+ + 2OH- -> Cu(OH)2}$$

    ## 1.20 化学平衡

    $$\\ce{N2 + 3H2 \\xleftarrow[\\text{high P}]{\\text{high T}} 2NH3}$$

    ## 1.21 银氨溶液

    $$\\ce{[Ag(NH3)2]+ + OH- -> AgOH \\downarrow + 2NH3}$$

    ## 1.22 辛烷燃烧

    $$\\ce{2C8H_{18} + 25O2 -> 16CO2 + 18H2O}$$

    ## 1.23 合成氨 (修复文字)

    $$N_2 + 3H_2 \\xrightarrow[\\text{high P}]{\\text{high T}} 2NH_3$$

    ## 1.24 酯化反应

    $$C_2H_5OH + CH_3COOH \\xrightarrow{\\text{conc. H}_2\\text{SO}_4} CH_3COOC_2H_5 + H_2O$$

    ## 1.25 沉淀符号测试

    $$AgOH \\downarrow + 2NH_3$$

    ## 1.26 基础芳香环 (Aromatic)

    $$\\chemfig{**6(------)}$$

    ## 1.27 凯库勒式 (Kekulé)

    $$\\chemfig{*6(-=-=-=)}$$

    ## 1.28 垂直对齐 (Check Baseline!)

    $$A + \\chemfig{**6(------)} \\rightarrow B$$

    ## 1.29 苯酚 (Substituents)

    $$\\chemfig{**6(---(-CH_3)---)}$$

    ## 1.30 TNT (Complex Layout)

    $$\\chemfig{**6(-NO_2-(-CH_3)-NO_2--NO_2-)}$$

    ## 1.31 终极测试：反应方程式

    $$\\chemfig{**6(---(-CH_3)---)} + 3HNO_3 \\longrightarrow \\chemfig{**6(-NO_2-(-CH_3)-NO_2--NO_2-)} + 3H_2O$$

    ## 1.32 傅里叶变换

    $$\\mathcal{F}(\\omega) = \\int_{-\\infty}^{\\infty} f(t) e^{-i\\omega t} dt$$

    ## 1.33 正态分布

    $$X \\sim \\mathcal{N}(\\mu, \\sigma^2) \\quad f(x) = \\frac{1}{\\sqrt{2\\pi}\\sigma} e^{-\\frac{(x-\\mu)^2}{2\\sigma^2}}$$

    ## 1.34 薛定谔方程

    $$i\\hbar \\frac{\\partial}{\\partial t} \\Psi = \\hat{H} \\Psi$$

    ## 1.35 高斯定律

    $$\\oint_{\\partial V} \\vec{E} \\cdot d\\vec{A} = \\frac{Q}{\\epsilon_0}$$

    ## 1.36 实数集公理

    $$\\forall x \\in \\mathbb{R}, \\quad x^2 \\geq 0$$

    ---
    # 二、标题层级测试

    # H1 一级标题 - 最大标题

    ## H2 二级标题 - 章节标题

    ### H3 三级标题 - 小节标题

    #### H4 四级标题 - 子节标题

    ##### H5 五级标题 - 细分标题

    ###### H6 六级标题 - 最小标题

    ### 标题中包含特殊格式

    ## **粗体标题**

    ### *斜体标题*

    #### `代码标题`

    ##### ~~删除线标题~~

    ###### 标题中包含 [链接](https://apple.com)

    ---

    # 三、文本格式测试

    ## 3.1 基础格式

    这是普通文本，没有任何格式。

    **这是粗体文本。**

    *这是斜体文本。*

    ***这是粗斜体文本。***

    ~~这是删除线文本。~~

    `这是行内代码`

    ## 3.2 格式组合

    这段文字包含 **粗体** 和 *斜体* 以及 ~~删除线~~ 和 `代码`。

    **粗体中包含 *斜体* 文本**

    *斜体中包含 **粗体** 文本*

    ~~删除线中包含 **粗体** 和 *斜体*~~

    `行内代码不会渲染 **粗体** 或 *斜体*`

    ## 3.3 长文本换行测试

    这是一段非常长的文本，用于测试自动换行功能。在移动设备上，文本应该能够正确换行，而不会超出屏幕边界。这段文字会继续延伸，以确保换行功能正常工作。Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.

    ## 3.4 连续空行测试

    上面的段落。


    下面的段落（中间有两个空行）。

    ---
    
    # 四、链接测试

    ## 4.1 基础链接

    [Apple 官网](https://www.apple.com)

    [Google](https://www.google.com)

    [百度一下](https://www.baidu.com)

    ## 4.2 链接文本格式

    [**粗体链接**](https://apple.com)

    [*斜体链接*](https://apple.com)

    [`代码链接`](https://apple.com)

    [~~删除线链接~~](https://apple.com)

    ## 4.3 特殊 URL

    [带参数的链接](https://example.com/search?q=test&page=1)

    [带锚点的链接](https://example.com/page#section)

    [中文路径链接](https://example.com/文档/测试)

    ## 4.4 行内多链接

    这段话包含 [第一个链接](https://apple.com) 和 [第二个链接](https://google.com) 以及 [第三个链接](https://baidu.com)。

    ---

    # 五、图片测试

    ## 5.1 基础图片

    ![测试图片1](https://download-sdk.oss-cn-beijing.aliyuncs.com/downloads/IMDemo/avatar/Image1.png)

    ## 5.2 不同尺寸图片

    小图片：
    ![小头像](https://download-sdk.oss-cn-beijing.aliyuncs.com/downloads/IMDemo/avatar/Image2.png)

    中等图片：
    ![中等图片](https://download-sdk.oss-cn-beijing.aliyuncs.com/downloads/IMDemo/avatar/Image3.png)

    ## 5.3 多图片连续显示

    ![图片A](https://download-sdk.oss-cn-beijing.aliyuncs.com/downloads/IMDemo/avatar/Image1.png)

    ![图片B](https://download-sdk.oss-cn-beijing.aliyuncs.com/downloads/IMDemo/avatar/Image2.png)

    ![图片C](https://download-sdk.oss-cn-beijing.aliyuncs.com/downloads/IMDemo/avatar/Image3.png)

    ## 5.4 无效图片（测试占位符）

    ![无效图片](https://invalid-url.example.com/not-exist.png)

    ## 5.5 无 Alt 文本图片

    ![](https://download-sdk.oss-cn-beijing.aliyuncs.com/downloads/IMDemo/avatar/Image1.png)

    ---

    # 六、列表测试

    ## 6.1 无序列表

    - 第一项

        | 序号 | 标题 | 描述 |
        |------|------|------|
        | 1 | 第一项 | 这是第一项的描述文本 |
        | 2 | 第二项 | 这是第二项的描述文本 |
        | 3 | 第三项 | 这是第三项的描述文本 |
    
    - 第二项

        ```swift
        struct User {
            let id: Int
            let name: String
        }

        let user = User(id: 1, name: "Alice")
        print(user)
        ```
    
    - 第三项
        
            $$\\mathcal{F}(\\omega) = \\int_{-\\infty}^{\\infty} f(t) e^{-i\\omega t} dt$$

    ## 6.2 无序列表嵌套（多层级）

    - 一级项目 A
      - 二级项目 A.1
      - 二级项目 A.2
        - 三级项目 A.2.1
        - 三级项目 A.2.2
          - 四级项目 A.2.2.1
          - 四级项目 A.2.2.2
            - 五级项目（测试深层嵌套）
    - 一级项目 B
      - 二级项目 B.1

    ## 6.3 有序列表

    1. 第一步
    2. 第二步
    3. 第三步

    ## 6.4 有序列表嵌套

    1. 第一章
       1. 第一节
       2. 第二节
          1. 第一小节
          2. 第二小节
    2. 第二章
       1. 第一节

    ## 6.5 任务列表

    - [x] 已完成：设计 UI
    - [x] 已完成：编写代码
    - [ ] 待完成：编写测试
    - [ ] 待完成：发布上线

    ## 6.6 混合列表

    1. 有序项一
       - 无序子项 A
       - 无序子项 B
    2. 有序项二
       - [x] 任务子项（已完成）
       - [ ] 任务子项（未完成）

    ## 6.7 列表项包含多行文本

    - 这是一个很长的列表项，内容会换行显示。Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore.

    - 这是另一个包含 **粗体**、*斜体* 和 `代码` 的列表项。

    - 这是包含 [链接](https://apple.com) 的列表项。

    ---

    # 七、引用测试

    ## 7.1 基础引用

    > 这是一段引用文本。

    ## 7.2 多行引用

    > 这是引用的第一行。
    > 这是引用的第二行。
    > 这是引用的第三行。

    ## 7.3 引用中的格式

    > 引用可以包含 **粗体**、*斜体*、`代码` 和 [链接](https://apple.com)。

    ## 7.4 嵌套引用

    > 这是一级引用。
    >> 这是二级嵌套引用。
    >>> 这是三级嵌套引用。

    ## 7.5 引用中的列表

    > 引用中的列表：
    > - 项目一
    > - 项目二
    > - 项目三

    ## 7.6 长引用文本

    > 这是一段非常长的引用文本，用于测试引用块在长文本情况下的换行和显示效果。Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.

    ## 7.7 嵌套模块

    > 引用中的表格
    >
    > | 序号 | 名称 | 说明 |
    > |------|------|------|
    > | 1 | Alpha | 第一项说明 |
    > | 2 | Beta  | 第二项说明 |
    > | 3 | Gamma | 第三项说明 |
    >
    > 引用中的代码块
    >
    > ```swift
    > struct Point {
    >     let x: Double
    >     let y: Double
    > }
    >
    > let p = Point(x: 1.0, y: 2.0)
    > print(p)
    > ```
    >
    > 引用中的公式
    >
    > $$\\mathcal{F}(\\omega) = \\int_{-\\infty}^{\\infty} f(t) e^{-i\\omega t} dt$$
        
    ---

    # 八、代码测试

    ## 8.1 行内代码

    使用 `print("Hello")` 输出文本。

    变量 `let x = 10` 和函数 `func test() {}` 示例。

    ## 8.2 代码块 - Swift

    ```swift
    // Swift 代码示例
    import UIKit

    class ViewController: UIViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            
            let label = UILabel()
            label.text = "Hello, World!"
            view.addSubview(label)
        }
        
        func greet(name: String) -> String {
            return "Hello, \\(name)!"
        }
    }
    ```

    ## 8.3 代码块 - Python

    ```python
    # Python 代码示例
    def fibonacci(n):
        if n <= 1:
            return n
        return fibonacci(n-1) + fibonacci(n-2)

    # 打印前 10 个斐波那契数
    for i in range(10):
        print(fibonacci(i))
    ```

    ## 8.4 代码块 - JavaScript

    ```javascript
    // JavaScript 代码示例
    const fetchData = async (url) => {
        try {
            const response = await fetch(url);
            const data = await response.json();
            return data;
        } catch (error) {
            console.error('Error:', error);
        }
    };

    fetchData('https://api.example.com/data')
        .then(data => console.log(data));
    ```

    ## 8.5 代码块 - JSON

    ```json
    {
        "name": "MarkdownDisplayView",
        "version": "1.0.0",
        "features": [
            "headings",
            "bold",
            "italic",
            "links",
            "images",
            "tables"
        ],
        "config": {
            "theme": "default",
            "fontSize": 16
        }
    }
    ```

    ## 8.6 代码块 - 无语言标识

    ```
    这是一个没有指定语言的代码块
    可以包含任意文本
        保留缩进和格式
    ```

    ## 8.7 代码块 - 长代码行测试

    ```swift
    let veryLongVariableName = "This is a very long string that should test horizontal scrolling or wrapping in code blocks when displayed on mobile devices"
    ```
    
    ---

    # 九、表格测试

    ## 9.1 基础表格

    | 列A | 列B | 列C |
    |-----|-----|-----|
    | A1 | B1 | C1 |
    | A2 | B2 | C2 |
    | A3 | B3 | C3 |

    ## 9.2 表格含格式

    | 功能 | 状态 | 说明 |
    |------|------|------|
    | **粗体** | ✅ | 支持 |
    | *斜体* | ✅ | 支持 |
    | `代码` | ✅ | 支持 |
    | ~~删除线~~ | ✅ | 支持 |
    | [链接](https://apple.com) | ✅ | 支持 |

    ## 9.3 多列表格（测试横向滚动）

    | 功能 | 支持 | 备注 | 版本 | 平台 | 依赖 | 作者 | 更新时间 |
    |------|------|------|------|------|------|------|----------|
    | 标题 | ✅ | H1-H6 | 1.0 | iOS | 无 | 开发者 | 2024-01 |
    | 粗体 | ✅ | **text** | 1.0 | iOS | 无 | 开发者 | 2024-01 |
    | 斜体 | ✅ | *text* | 1.0 | iOS | 无 | 开发者 | 2024-01 |
    | 链接 | ✅ | [text](url) | 1.0 | iOS | 无 | 开发者 | 2024-01 |
    | 图片 | ✅ | ![](url) | 1.1 | iOS | 无 | 开发者 | 2024-02 |
    | 表格 | ✅ | 横向滚动 | 1.2 | iOS | 无 | 开发者 | 2024-03 |

    ## 9.4 多行表格

    | 序号 | 标题 | 描述 |
    |------|------|------|
    | 1 | 第一项 | 这是第一项的描述文本 |
    | 2 | 第二项 | 这是第二项的描述文本 |
    | 3 | 第三项 | 这是第三项的描述文本 |
    | 4 | 第四项 | 这是第四项的描述文本 |
    | 5 | 第五项 | 这是第五项的描述文本 |
    | 6 | 第六项 | 这是第六项的描述文本 |
    | 7 | 第七项 | 这是第七项的描述文本 |
    | 8 | 第八项 | 这是第八项的描述文本 |
    | 9 | 第九项 | 这是第九项的描述文本 |
    | 10 | 第十项 | 这是第十项的描述文本 |

    ## 9.5 单列表格

    | 单列表格 |
    |----------|
    | 行1 |
    | 行2 |
    | 行3 |

    ## 9.6 两列表格

    | 键 | 值 |
    |----|----|
    | name | MarkdownView |
    | version | 1.0.0 |
    | platform | iOS |

    ---

    # 十、分隔线测试

    ## 10.1 使用三个横线

    上方内容

    ---

    下方内容

    ## 10.2 使用三个星号

    上方内容

    ***

    下方内容

    ## 10.3 使用三个下划线

    上方内容

    ___

    下方内容

    ## 10.4 连续分隔线

    ---

    ---

    ---

    ---

    # 十一、脚注测试

    ## 11.1 基础脚注

    这是一段包含脚注的文本[^1]。

    这是另一段文本，引用了第二个脚注[^2]。

    ## 11.2 命名脚注

    Markdown 是一种轻量级标记语言[^markdown]。

    Swift 是 Apple 开发的编程语言[^swift]。

    ## 11.3 多个脚注在同一段

    这段话包含多个脚注[^a]，可以测试[^b]脚注的连续显示[^c]效果。

    ## 11.4 脚注定义

    [^1]: 这是第一个脚注的内容。
    [^2]: 这是第二个脚注的内容，可以包含更长的解释文本。
    [^markdown]: Markdown 由 John Gruber 于 2004 年创建。
    [^swift]: Swift 于 2014 年 WWDC 大会上首次发布。
    [^a]: 脚注 A 的内容。
    [^b]: 脚注 B 的内容。
    [^c]: 脚注 C 的内容。

    ---

    # 十二、自定义样式测试

    ## 12.1 视频播放

    下面是一个视频示例，点击播放按钮可使用 QuickLook 播放：

    [video:video]

    视频支持自动生成缩略图和时长显示。
    
    ## 12.2 Mermaid

    支持 Mermaid 语法渲染各类图表：

    ```mermaid
    graph TD
        A[开始] --> B{是否支持?}
        B -->|是| C[渲染图表]
        B -->|否| D[显示代码]
        C --> E[完成]
        D --> E
    ```

    ## 12.3 Mindmap

    Mermaid 也支持思维导图语法（Mermaid 9.1+ 功能）：

    ```mermaid
    mindmap
      root((MarkdownDisplayKit))
        基础语法
          标题
          列表
          表格
          代码块
        扩展功能
          LaTeX公式
          语法高亮
          目录生成
        自定义扩展
          视频播放
          Mermaid图表
          更多...
    ```    

    ---

    # 十三、混合内容测试

    ## 13.1 复杂段落

    这是一段**复杂**的段落，包含 *多种* 格式：`代码`、[链接](https://apple.com)、~~删除线~~ 以及普通文本。它还引用了一个脚注[^mix]。

    [^mix]: 这是混合内容测试的脚注。

    ## 13.2 列表中的复杂内容

    - **粗体项目** - 包含 *斜体* 和 `代码`
    - 包含 [链接](https://apple.com) 的项目
    - 包含图片引用的项目：![小图](https://download-sdk.oss-cn-beijing.aliyuncs.com/downloads/IMDemo/avatar/Image1.png)

    ## 13.3 引用中的复杂内容

    > 这是一段引用，包含 **粗体**、*斜体*、`代码`。
    > 
    > 还包含 [链接](https://apple.com) 和脚注[^quote]。
    > 
    > - 以及列表项
    > - 和更多内容

    [^quote]: 引用中的脚注。

    ## 13.4 表格后紧跟其他内容

    | 名称 | 值 |
    |------|-----|
    | A | 100 |
    | B | 200 |

    上面是表格，这是表格后的段落文本。

    下面是代码块：

    ```swift
    print("表格后的代码块")
    ```

    ---

    # 十四、边界情况测试

    ## 14.1 空内容测试

    ### 空标题后的内容

    这是空标题下的内容。

    ## 14.2 特殊字符

    - 小于号: <
    - 大于号: >
    - 与号: &
    - 引号: "双引号" '单引号'
    - 反斜杠: \\
    - 星号: \\*
    - 下划线: \\_

    ## 14.3 Unicode 字符

    - Emoji: 😀 🎉 🚀 ✅ ❌ ⚠️ 💡 🔥
    - 中文: 你好世界
    - 日文: こんにちは
    - 韩文: 안녕하세요
    - 阿拉伯文: مرحبا
    - 希腊字母: α β γ δ ε
    - 数学符号: ∑ ∏ √ ∞ ≈ ≠ ≤ ≥

    ## 14.4 超长单词

    Pneumonoultramicroscopicsilicovolcanoconiosis

    Supercalifragilisticexpialidocious

    ## 14.5 纯数字内容

    1234567890

    ## 14.6 纯符号内容

    !@#$%^&*()_+-=[]{}|;':\",./<>?

    ## 14.7 空链接和图片

    [空链接]()

    ![空图片]()

    ## 14.8 连续格式切换

    **粗***斜*`码`~~删~~**粗***斜*`码`~~删~~

    ---



    # 总结

    本文档测试了 MarkdownView 的以下功能：

    | 功能类别 | 测试项数 | 状态 |
    |----------|----------|------|
    | 标题 | 6 级 + 格式 | ✅ |
    | 文本格式 | 粗体/斜体/删除线/代码 | ✅ |
    | 链接 | 基础/格式/特殊URL | ✅ |
    | 图片 | 基础/多图/无效 | ✅ |
    | 列表 | 有序/无序/任务/嵌套 | ✅ |
    | 引用 | 基础/嵌套/格式 | ✅ |
    | 代码 | 行内/块级/多语言 | ✅ |
    | 表格 | 基础/格式/多列 | ✅ |
    | 分隔线 | 多种语法 | ✅ |
    | 脚注 | 数字/命名 | ✅ |
    | 视频 | 自定义扩展 | ✅ |
    | Mermaid | 代码块扩展 | ✅ |
    | 边界情况 | 特殊字符/Unicode | ✅ |

    ---

    **感谢使用 MarkdownView！** 🎉

    如有问题，请访问 [GitHub](https://github.com)。
    """
