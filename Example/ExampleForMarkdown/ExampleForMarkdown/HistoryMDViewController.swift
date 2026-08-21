//
//  CrashReproViewController.swift
//  CocoapodsMDExample
//
//  Created by 朱继超 on 12/19/25.
//

import UIKit
import MarkdownDisplayView

private final class HistoryMarkdownPreparationToken {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

private final class HistoryMarkdownPreparedBox {
    let row: Int
    let markdown: String
    let width: CGFloat
    let content: MarkdownPreparedContent

    init(row: Int, markdown: String, width: CGFloat, content: MarkdownPreparedContent) {
        self.row = row
        self.markdown = markdown
        self.width = width
        self.content = content
    }
}

private final class HistoryMarkdownPreparationTask {
    let row: Int
    let markdown: String
    let width: CGFloat
    let token = HistoryMarkdownPreparationToken()
    weak var operation: BlockOperation?

    init(row: Int, markdown: String, width: CGFloat) {
        self.row = row
        self.markdown = markdown
        self.width = width
    }

    func cancel() {
        token.cancel()
        operation?.cancel()
    }

    func matches(row: Int, markdown: String, width: CGFloat) -> Bool {
        self.row == row && self.markdown == markdown && abs(self.width - width) <= 1
    }
}

private struct HistoryMarkdownHeightEntry {
    let markdown: String
    let width: CGFloat
    let height: CGFloat
}

final class HistoryMDViewController: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let selectedTheme = MarkdownDemoThemeStore.selectedTheme
    private var markdownConfiguration: MarkdownConfiguration {
        selectedTheme?.makeConfiguration() ?? .default
    }
    private var messages: [String] = []
    private var cachedHeights: [Int: HistoryMarkdownHeightEntry] = [:]
    private let preparedContentCache: NSCache<NSNumber, HistoryMarkdownPreparedBox> = {
        let cache = NSCache<NSNumber, HistoryMarkdownPreparedBox>()
        cache.countLimit = 16
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()
    private var preparedContentWidth: CGFloat = 0
    private var preparationTasks: [Int: HistoryMarkdownPreparationTask] = [:]
    private var prefetchedRows = Set<Int>()
    private let prepareQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.markdown.history.prepare"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private let cellVerticalPadding: CGFloat = 24
    private let firstRowExtraPadding: CGFloat = 12

    private var pendingHeightUpdateRows = Set<Int>()
    private var isHeightUpdateScheduled = false
    private let rowHeightUpdateThreshold: CGFloat = 2

    private var shouldApplyHeightUpdates = false
    private var isInitialAppearance = true

    private lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("关闭", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        if let selectedTheme {
            overrideUserInterfaceStyle = selectedTheme.interfaceStyle
        }
        view.backgroundColor = .systemBackground
        setupTableView()
        setupCloseButton()
        applySelectedTheme()
        prepareMessages()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let width = markdownContentWidth()
        guard width > 1 else { return }
        guard !messages.isEmpty else { return }
        guard abs(width - preparedContentWidth) > 1 else { return }

        updatePreparationWidth(width)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        shouldApplyHeightUpdates = false

        if isInitialAppearance {
            tableView.alpha = 0
        } else {
            tableView.alpha = 1
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        shouldApplyHeightUpdates = true

        guard isInitialAppearance else { return }
        isInitialAppearance = false

        DispatchQueue.main.async { [weak self] in
            self?.flushPendingHeightUpdates()
        }

        UIView.animate(
            withDuration: 0.16,
            delay: 0.02,
            options: [.curveEaseInOut, .allowUserInteraction],
            animations: { [weak self] in
                self?.tableView.alpha = 1
            }
        )
    }

    deinit {
        cancelAllPreparationTasks()
    }

    private func setupTableView() {
        tableView.dataSource = self
        tableView.prefetchDataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.estimatedRowHeight = 120
        tableView.rowHeight = UITableView.automaticDimension
        tableView.register(MarkdownHistoryCell.self, forCellReuseIdentifier: MarkdownHistoryCell.reuseIdentifier)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 44),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupCloseButton() {
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    private func applySelectedTheme() {
        guard let theme = selectedTheme else { return }
        view.backgroundColor = theme.canvasColor
        tableView.backgroundColor = theme.canvasColor
        tableView.indicatorStyle = theme.interfaceStyle == .dark ? .white : .black
        closeButton.tintColor = theme.accentColor
    }

    private func prepareMessages() {
        let baseTableArray = [
            "在 Android 上实现贝塞尔曲线动画，通常可以使用 `ValueAnimator` 与 `Path`、`PathInterpolator` 等类结合，实现平滑的曲线动画效果。下面是一个使用 **贝塞尔曲线（Bezier Curve）** 实现动画的示例代码，展示如何在屏幕上绘制一个点沿着贝塞尔曲线运动的动画。\n\n---\n\n## ✅ 示例代码：贝塞尔曲线动画（Android）\n\n### 📌 1. 在布局文件中添加一个 `View`\n\n```xml\n<!-- res/layout/activity_main.xml -->\n<FrameLayout\n    xmlns:android=\"http://schemas.android.com/apk/res/android\"\n    android:layout_width=\"match_parent\"\n    android:layout_height=\"match_parent\">\n\n    <com.example.bezieranimation.BezierView\n        android:id=\"@+id/bezierView\"\n        android:layout_width=\"match_parent\"\n        android:layout_height=\"match_parent\" />\n</FrameLayout>\n```\n\n---\n\n### 📌 2. 自定义 `BezierView` 类\n\n```java\n// BezierView.java\npublic class BezierView extends View {\n\n    private static final int ANIMATION_DURATION = 2000;\n    private Path mPath;\n    private PathInterpolator mInterpolator;\n    private float mX, mY;\n\n    public BezierView(Context context) {\n        super(context);\n        init();\n    }\n\n    public BezierView(Context context, AttributeSet attrs) {\n        super(context, attrs);\n        init();\n    }\n\n    private void init() {\n        mPath = new Path();\n        mInterpolator = new PathInterpolator(0.4f, 0.2f, 0.6f, 0.9f);\n    }\n\n    @Override\n    protected void onDraw(Canvas canvas) {\n        super.onDraw(canvas);\n\n        Paint paint = new Paint();\n        paint.setColor(Color.RED);\n        paint.setStrokeWidth(5);\n        paint.setStyle(Paint.Style.STROKE);\n\n        // 绘制贝塞尔曲线\n        canvas.drawPath(mPath, paint);\n\n        // 绘制动画点\n        Paint pointPaint = new Paint();\n        pointPaint.setColor(Color.BLUE);\n        canvas.drawCircle(mX, mY, 10, pointPaint);\n    }\n\n    public void startAnimation() {\n        // 定义贝塞尔曲线路径\n        mPath.reset();\n        mPath.moveTo(100, 500); // 起点\n        mPath.cubicTo(300, 100, 500, 100, 700, 500); // 控制点1、控制点2、终点\n\n        // 创建动画\n        ValueAnimator animator = ValueAnimator.ofFloat(0, 1);\n        animator.setInterpolator(mInterpolator);\n        animator.setDuration(ANIMATION_DURATION);\n        animator.addUpdateListener(animation -> {\n            float t = animation.getAnimatedFraction();\n            float x = mPath.getInterpolation(t).x;\n            float y = mPath.getInterpolation(t).y;\n            mX = x;\n            mY = y;\n            invalidate();\n        });\n\n        animator.start();\n    }\n}\n```\n\n---\n\n### 📌 3. 在 `Activity` 中启动动画\n\n```java\n// MainActivity.java\npublic class MainActivity extends AppCompatActivity {\n\n    @Override\n    protected void onCreate(Bundle savedInstanceState) {\n        super.onCreate(savedInstanceState);\n        setContentView(R.layout.activity_main);\n\n        BezierView bezierView = findViewById(R.id.bezierView);\n        bezierView.startAnimation();\n    }\n}\n```\n\n---\n\n## ✅ 说明\n\n- `Path`：定义贝塞尔曲线的形状。\n- `PathInterpolator`：用于定义动画的插值方式（即曲线的缓动效果）。\n- `ValueAnimator`：用于控制动画的播放和更新。\n- `onDraw()`：用于绘制贝塞尔曲线和动画点。\n\n---\n\n## ✅ 可选扩展\n\n- 使用 `ObjectAnimator` 与 `PointF` 或 `Point` 实现更复杂的动画。\n- 使用 `BezierPathInterpolator`（自定义插值器）实现更精细的动画控制。\n- 使用 `Canvas` 的 `drawPath()` 方法绘制路径。\n- 使用 `XML` 定义动画路径，实现更灵活的动画定义。\n\n---\n\n## ✅ 总结\n\n在 Android 中实现贝塞尔曲线动画，可以使用以下组件：\n\n| 组件 | 作用 |\n|------|------|\n| `Path` | 定义贝塞尔曲线的形状 |\n| `PathInterpolator` | 定义动画的缓动曲线 |\n| `ValueAnimator` | 控制动画的播放和更新 |\n| `Canvas` | 绘制动画路径和点 |\n\n如需实现更复杂的动画（如多点动画、路径跟随等），可以进一步扩展该示例。\n\n---\n\n如果你希望我帮你实现更复杂的动画（如手势跟随、路径绘制动画等），也可以告诉我！",
            
            "圆周率（π）是数学中一个非常重要的常数，表示圆的周长与直径的比值。它在数学中出现了很多种形式，尤其是在几何、微积分、数论等领域。以下是一些常见的**圆周率的数学公式**或表达方式：\n\n---\n\n## 一、基本定义（几何）\n\n1. **圆的周长公式**：\n   $$\n   C = \\pi d = 2\\pi r\n   $$\n   - $C$ 是圆的周长\n   - $d$ 是直径\n   - $r$ 是半径\n\n2. **圆的面积公式**：\n   $$\n   A = \\pi r^2\n   $$\n\n---\n\n## 二、无穷级数（用于计算 π）\n\n1. **莱布尼茨公式**（级数形式）：\n   $$\n   \\pi = 4 \\left(1 - \\frac{1}{3} + \\frac{1}{5} - \\frac{1}{7} + \\cdots \\right)\n   $$\n\n2. **格雷戈里-莱布尼茨级数**：\n   $$\n   \\pi = 4 \\sum_{n=0}^{\\infty} \\frac{(-1)^n}{2n+1}\n   $$\n\n3. **拉马努金公式**（快速收敛的公式）：\n   $$\n   \\pi = \\frac{1}{4} \\sum_{k=0}^{\\infty} \\frac{(6k)!}{(k!)^3 (3k)!} \\cdot \\frac{13591409 + 545140134k}{640320^{3k}}\n   $$\n\n---\n\n## 三、积分表达式\n\n1. **积分表达式（由勒让德提出）**：\n   $$\n   \\pi = 2 \\int_{0}^{1} \\frac{1}{\\sqrt{1 - x^2}} \\, dx\n   $$\n\n2. **积分表达式（由欧拉提出）**：\n   $$\n   \\pi = 4 \\int_{0}^{1} \\frac{1}{1 + x^2} \\, dx\n   $$\n\n---\n\n## 四、无理数和超越数的表达\n\n1. **π 是无理数**（1768 年由 Lambert 证明）：\n   - 不能表示为两个整数的比值。\n\n2. **π 是超越数**（1882 年由林德曼 证明）：\n   - 不是任何非零整系数多项式方程的根。\n\n---\n\n## 五、其他数学公式中出现 π\n\n1. **欧拉公式（复数中）**：\n   $$\n   e^{i\\pi} + 1 = 0\n   $$\n\n2. **高斯积分**：\n   $$\n   \\int_{-\\infty}^{\\infty} e^{-x^2} dx = \\sqrt{\\pi}\n   $$\n\n3. **球体体积公式**：\n   $$\n   V = \\frac{4}{3}\\pi r^3\n   $$\n\n4. **球体表面积公式**：\n   $$\n   A = 4\\pi r^2\n   $$\n\n---\n\n## 六、π 的近似值表达式\n\n1. **常用近似值**：\n   $$\n   \\pi \\approx 3.141592653589793...\n   $$\n\n2. **分数近似**：\n   $$\n   \\frac{22}{7} \\approx 3.142857\n   $$\n   $$\n   \\frac{355}{113} \\approx 3.1415929\n   $$\n\n---\n\n## 七、π 在复分析中的表达\n\n1. **欧拉公式（复数）**：\n   $$\n   e^{i\\pi} = -1\n   $$\n\n2. **Γ 函数的性质**：\n   $$\n   \\Gamma\\left(\\frac{1}{2}\\right) = \\sqrt{\\pi}\n   $$\n\n---\n\n## 八、π 在概率与统计中的应用\n\n1. **正态分布的密度函数**：\n   $$\n   f(x) = \\frac{1}{\\sqrt{2\\pi}} e^{-\\frac{x^2}{2}}\n   $$\n\n---\n\n## 总结\n\n圆周率 π 出现在数学的多个领域，形式多样，包括：\n\n- 几何公式\n- 级数表达\n- 积分表达\n- 复数与复分析\n- 概率与统计\n- 无理数与超越数的性质\n\n如果你对某个特定领域（比如几何、微积分、复数等）的 π 公式感兴趣，可以告诉我，我可以进一步详细讲解！",
            
            "学习微积分是一个循序渐进的过程，需要从基础的数学知识开始，逐步深入到微分和积分的概念，最后掌握更高级的应用。以下是一个 **Mermaid 流程图**，展示了学习微积分的步骤和路径：\n\n```mermaid\ngraph TD\n    A[1. 数学基础] --> B[2. 函数与图像]\n    B --> C[3. 极限与连续]\n    C --> D[4. 导数与微分]\n    D --> E[5. 积分与微积分基本定理]\n    E --> F[6. 多变量微积分]\n    F --> G[7. 微分方程]\n    G --> H[8. 级数与级数求和]\n    H --> I[9. 应用与实际问题]\n    I --> J[10. 进阶与拓展]\n```\n\n---\n\n## 📌 学习微积分的步骤说明\n\n### 1. **数学基础**\n- 学习**代数、几何、三角函数**等基础知识。\n- 熟悉**函数**的定义、性质和图像（如一次函数、二次函数、指数函数、对数函数等）。\n\n---\n\n### 2. **函数与图像**\n- 学习**函数的定义、图像、单调性、奇偶性、周期性**等。\n- 熟悉**函数的运算**（加减乘除、复合函数、反函数等）。\n\n---\n\n### 3. **极限与连续**\n- 理解**极限的概念**（左右极限、无穷大极限、极限的性质）。\n- 学习**连续函数的定义**和判断方法。\n\n---\n\n### 4. **导数与微分**\n- 理解**导数的定义**（瞬时变化率）。\n- 掌握**导数的计算方法**（基本导数公式、求导法则、隐函数求导、参数方程求导等）。\n- 熟悉**导数的应用**（极值、单调性、曲线的切线、最优化问题）。\n\n---\n\n### 5. **积分与微积分基本定理**\n- 学习**不定积分与定积分的定义**。\n- 掌握**积分法则**（换元积分、分部积分、积分表等）。\n- 理解**微积分基本定理**（导数与积分的联系）。\n\n---\n\n### 6. **多变量微积分**\n- 学习**偏导数、梯度、方向导数**等。\n- 掌握**多重积分**（二重积分、三重积分）和**曲线积分、曲面积分**。\n- 熟悉**向量场、散度、旋度**等。\n\n---\n\n### 7. **微分方程**\n- 学习**常微分方程和偏微分方程**的基本概念。\n- 掌握**解微分方程的方法**（变量分离、积分因子、特征方程、拉普拉斯变换等）。\n- 理解**微分方程在物理、工程中的应用**。\n\n---\n\n### 8. **级数与级数求和**\n- 学习**数列与级数的基本概念**（收敛、发散、收敛性判别）。\n- 掌握**幂级数、泰勒级数、傅里叶级数**等。\n- 熟悉**级数在近似计算与函数展开中的应用**。\n\n---\n\n### 9. **应用与实际问题**\n- 学习如何将微积分用于**物理、工程、经济学、生物学**等领域的实际问题。\n- 掌握**优化问题、运动学、力学、热力学**等领域的建模与求解方法。\n\n---\n\n### 10. **进阶与拓展**\n- 学习**实变函数、复变函数、泛函分析、拓扑学**等高级数学内容。\n- 掌握**数学建模、数值分析、计算数学**等方向。\n- 深入学习**微积分在机器学习、人工智能、数据科学**等领域的应用。\n\n---\n\n## ✅ 学习建议\n\n- **循序渐进**：不要急于求成，打好基础是关键。\n- **多做练习**：通过大量习题巩固知识。\n- **结合图形**：用图像理解抽象概念（如导数的几何意义）。\n- **善用工具**：使用**GeoGebra、Desmos、WolframAlpha、MATLAB、Python**等工具辅助学习。\n- **多看视频**：YouTube、B站、Coursera、edX 等平台有大量优质微积分课程。\n\n---\n\n如果你希望我帮你制定一个具体的学习计划（如每天学习内容、时间安排等），也可以告诉我你的学习目标和时间安排，我可以为你量身定制一个学习计划！"
            
        ]
        messages = baseTableArray
        cachedHeights.removeAll()
        preparedContentCache.removeAllObjects()
        cancelAllPreparationTasks()
        prefetchedRows.removeAll()
        preparedContentWidth = 0
        tableView.reloadData()
    }

    private func markdownContentWidth() -> CGFloat {
        let tableWidth: CGFloat
        if tableView.bounds.width > 0 {
            tableWidth = tableView.bounds.width
        } else if view.bounds.width > 0 {
            tableWidth = view.bounds.width
        } else {
            tableWidth = UIScreen.main.bounds.width
        }
        return max(1, tableWidth - 32)
    }

    private func updatePreparationWidth(_ width: CGFloat) {
        guard width > 1 else { return }
        preparedContentWidth = width
        cancelAllPreparationTasks()
        preparedContentCache.removeAllObjects()
        cachedHeights.removeAll()
        tableView.reloadData()
    }

    private func preparedContent(forRow row: Int, markdown: String, width: CGFloat) -> MarkdownPreparedContent? {
        let key = NSNumber(value: row)
        guard let cached = preparedContentCache.object(forKey: key) else { return nil }
        guard cached.row == row,
              cached.markdown == markdown,
              abs(cached.width - width) <= 1,
              abs(cached.content.preparedWidth - width) <= 1 else {
            preparedContentCache.removeObject(forKey: key)
            return nil
        }
        return cached.content
    }

    private func cachedHeight(forRow row: Int, markdown: String, width: CGFloat) -> CGFloat? {
        guard let cached = cachedHeights[row],
              cached.markdown == markdown,
              abs(cached.width - width) <= 1 else {
            cachedHeights[row] = nil
            return nil
        }
        return cached.height
    }

    private func shouldPrepareMarkdown(_ markdown: String) -> Bool {
        markdown.utf8.count >= 1_200
    }

    private func requestPreparation(forRow row: Int, width: CGFloat) {
        guard messages.indices.contains(row), width > 1 else { return }
        let markdown = messages[row]
        guard shouldPrepareMarkdown(markdown) else { return }
        guard preparedContent(forRow: row, markdown: markdown, width: width) == nil else { return }

        if let existing = preparationTasks[row] {
            if existing.matches(row: row, markdown: markdown, width: width) {
                return
            }
            existing.cancel()
            preparationTasks[row] = nil
        }

        let task = HistoryMarkdownPreparationTask(
            row: row,
            markdown: markdown,
            width: width
        )
        let verticalPadding = cellVerticalPadding
        let firstExtraPadding = firstRowExtraPadding
        let configuration = markdownConfiguration
        let operation = BlockOperation { [weak self, weak task] in
            guard let task, !task.token.isCancelled else { return }
            let renderer = MarkdownRenderer(configuration: configuration, containerWidth: width)
            let prepared = renderer.prepare(markdown)
            guard !task.token.isCancelled else { return }

            let extraPadding = row == 0 ? firstExtraPadding : 0
            let height = prepared.estimatedTotalHeight + verticalPadding + extraPadding
            DispatchQueue.main.async { [weak self, weak task] in
                guard let self, let task else { return }
                self.finishPreparation(task, content: prepared, height: height)
            }
        }
        operation.queuePriority = .normal
        task.operation = operation
        preparationTasks[row] = task
        prepareQueue.addOperation(operation)
    }

    private func finishPreparation(
        _ task: HistoryMarkdownPreparationTask,
        content: MarkdownPreparedContent,
        height: CGFloat
    ) {
        guard preparationTasks[task.row] === task else { return }
        preparationTasks[task.row] = nil
        guard !task.token.isCancelled,
              messages.indices.contains(task.row),
              messages[task.row] == task.markdown,
              abs(markdownContentWidth() - task.width) <= 1,
              abs(content.preparedWidth - task.width) <= 1 else {
            return
        }

        let box = HistoryMarkdownPreparedBox(
            row: task.row,
            markdown: task.markdown,
            width: task.width,
            content: content
        )
        preparedContentCache.setObject(
            box,
            forKey: NSNumber(value: task.row),
            cost: preparedContentCost(markdown: task.markdown, content: content)
        )
        cachedHeights[task.row] = HistoryMarkdownHeightEntry(
            markdown: task.markdown,
            width: task.width,
            height: height
        )

        let indexPath = IndexPath(row: task.row, section: 0)
        if let cell = tableView.cellForRow(at: indexPath) as? MarkdownHistoryCell {
            _ = cell.apply(
                preparedContent: content,
                row: task.row,
                markdown: task.markdown,
                width: task.width
            )
            scheduleHeightUpdates(forRow: task.row)
        }
    }

    private func preparedContentCost(markdown: String, content: MarkdownPreparedContent) -> Int {
        let textCost = markdown.utf8.count * 4
        let elementCost = content.elements.count * 512
        let imageCost = content.imageAttachments.count * 64 * 1024
        return max(1, textCost + elementCost + imageCost)
    }

    private func cancelPreparation(forRow row: Int) {
        preparationTasks.removeValue(forKey: row)?.cancel()
    }

    private func cancelAllPreparationTasks() {
        preparationTasks.values.forEach { $0.cancel() }
        preparationTasks.removeAll()
        prepareQueue.cancelAllOperations()
    }

    @objc private func closeTapped() {
        dismiss(animated: false)
    }

    private func scheduleHeightUpdates(forRow row: Int) {
        pendingHeightUpdateRows.insert(row)
        guard shouldApplyHeightUpdates else { return }
        guard !isHeightUpdateScheduled else { return }
        isHeightUpdateScheduled = true

        DispatchQueue.main.async { [weak self] in
            self?.flushPendingHeightUpdates()
        }
    }

    private func flushPendingHeightUpdates() {
        isHeightUpdateScheduled = false

        guard !pendingHeightUpdateRows.isEmpty else { return }
        pendingHeightUpdateRows.removeAll()

        UIView.performWithoutAnimation { [weak self] in
            guard let self else { return }
            self.tableView.beginUpdates()
            self.tableView.endUpdates()
        }
    }

}

extension HistoryMDViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: MarkdownHistoryCell.reuseIdentifier,
            for: indexPath
        ) as? MarkdownHistoryCell else {
            return UITableViewCell(style: .default, reuseIdentifier: "fallback")
        }
        let row = indexPath.row
        let markdown = messages[safe: row] ?? ""
        let width = markdownContentWidth()
        prefetchedRows.remove(row)
        cell.apply(theme: selectedTheme, configuration: markdownConfiguration)

        cell.onContentHeightChange = { [weak self, weak tableView, weak cell] contentHeight in
            guard let self, let tableView, let cell else { return }
            guard tableView.indexPath(for: cell)?.row == row else { return }
            guard cell.represents(row: row, markdown: markdown, width: width) else { return }
            guard self.messages.indices.contains(row), self.messages[row] == markdown else { return }
            guard abs(self.markdownContentWidth() - width) <= 1 else { return }
            guard contentHeight > 1 else { return }

            let extraPadding = row == 0 ? self.firstRowExtraPadding : 0
            let newRowHeight = contentHeight + self.cellVerticalPadding + extraPadding

            if let cached = self.cachedHeight(forRow: row, markdown: markdown, width: width),
               abs(cached - newRowHeight) <= self.rowHeightUpdateThreshold {
                return
            }
            self.cachedHeights[row] = HistoryMarkdownHeightEntry(
                markdown: markdown,
                width: width,
                height: newRowHeight
            )
            self.scheduleHeightUpdates(forRow: row)
        }

        if let prepared = preparedContent(forRow: row, markdown: markdown, width: width) {
            cell.configure(preparedContent: prepared, row: row, markdown: markdown, width: width)
        } else if shouldPrepareMarkdown(markdown) {
            cell.configurePreparationPlaceholder(row: row, markdown: markdown, width: width)
            requestPreparation(forRow: row, width: width)
        } else {
            cell.configure(markdown: markdown, row: row, width: width)
        }

        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let row = indexPath.row
        let markdown = messages[safe: row] ?? ""
        if let cachedHeight = cachedHeight(forRow: row, markdown: markdown, width: markdownContentWidth()) {
            return cachedHeight
        }
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        let row = indexPath.row
        let markdown = messages[safe: row] ?? ""
        return cachedHeight(forRow: row, markdown: markdown, width: markdownContentWidth())
            ?? tableView.estimatedRowHeight
    }

    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard tableView.indexPathsForVisibleRows?.contains(indexPath) != true else { return }
        if !prefetchedRows.contains(indexPath.row) {
            cancelPreparation(forRow: indexPath.row)
        }
        guard let historyCell = cell as? MarkdownHistoryCell else { return }
        DispatchQueue.main.async { [weak tableView, weak historyCell] in
            guard let tableView,
                  let historyCell,
                  tableView.indexPath(for: historyCell) == nil,
                  !tableView.visibleCells.contains(where: { $0 === historyCell }),
                  !historyCell.frame.intersects(tableView.bounds) else { return }
            historyCell.releaseRenderedContent()
        }
    }
}

extension HistoryMDViewController: UITableViewDataSourcePrefetching {
    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        let width = markdownContentWidth()
        for indexPath in indexPaths where messages.indices.contains(indexPath.row) {
            prefetchedRows.insert(indexPath.row)
            requestPreparation(forRow: indexPath.row, width: width)
        }
    }

    func tableView(_ tableView: UITableView, cancelPrefetchingForRowsAt indexPaths: [IndexPath]) {
        let visibleRows = Set(tableView.indexPathsForVisibleRows?.map(\.row) ?? [])
        for indexPath in indexPaths {
            prefetchedRows.remove(indexPath.row)
            guard !visibleRows.contains(indexPath.row) else {
                continue
            }
            cancelPreparation(forRow: indexPath.row)
        }
    }
}

final class MarkdownHistoryCell: UITableViewCell {
    static let reuseIdentifier = "MarkdownHistoryCell"

    private let markdownView = MarkdownViewTextKit()
    private let preparationIndicator = UIActivityIndicatorView(style: .medium)

    var onContentHeightChange: ((CGFloat) -> Void)?

    private var renderToken = UUID()
    private var representedRow: Int?
    private var representedMarkdown: String?
    private var representedWidth: CGFloat = 0
    private var appliedThemeRawValue: Int?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        contentView.clipsToBounds = true

        markdownView.enableTypewriterEffect = false
        markdownView.allowsStaticViewportRenderingInReusableCell = true
        markdownView.translatesAutoresizingMaskIntoConstraints = false
        markdownView.clipsToBounds = true

        markdownView.onHeightChange = { [weak self] newHeight in
            guard let self else { return }
            let token = self.renderToken
            guard token == self.renderToken else { return }
            self.onContentHeightChange?(newHeight)
        }

        contentView.addSubview(markdownView)
        preparationIndicator.hidesWhenStopped = true
        preparationIndicator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(preparationIndicator)
        let bottomConstraint = markdownView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        bottomConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([
            markdownView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            markdownView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            markdownView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            bottomConstraint,
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 68),
            preparationIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            preparationIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(theme: MarkdownDemoTheme?, configuration: MarkdownConfiguration) {
        guard let theme else { return }

        if appliedThemeRawValue != theme.rawValue {
            markdownView.configuration = configuration
            appliedThemeRawValue = theme.rawValue
        }

        backgroundColor = .clear
        contentView.backgroundColor = theme.panelColor
        markdownView.backgroundColor = theme.panelColor
        preparationIndicator.color = theme.accentColor
    }

    func configure(markdown: String, row: Int, width: CGFloat) {
        renderToken = UUID()
        representedRow = row
        representedMarkdown = markdown
        representedWidth = width
        markdownView.preferredMeasurementWidth = width
        preparationIndicator.stopAnimating()
        markdownView.isHidden = false
        // 历史消息为静态内容，一次性渲染不保留 diff 基线以省内存
        markdownView.retainsDiffBaseline = false
        markdownView.markdown = markdown
        setNeedsLayout()
    }

    func configurePreparationPlaceholder(row: Int, markdown: String, width: CGFloat) {
        renderToken = UUID()
        representedRow = row
        representedMarkdown = markdown
        representedWidth = width
        markdownView.preferredMeasurementWidth = width
        markdownView.resetForReuse()
        markdownView.isHidden = true
        preparationIndicator.startAnimating()
        setNeedsLayout()
    }

    func configure(
        preparedContent: MarkdownPreparedContent,
        row: Int,
        markdown: String,
        width: CGFloat
    ) {
        renderToken = UUID()
        representedRow = row
        representedMarkdown = markdown
        representedWidth = width
        markdownView.preferredMeasurementWidth = width
        preparationIndicator.stopAnimating()
        markdownView.isHidden = false
        markdownView.setPreparedContent(preparedContent)
        setNeedsLayout()
    }

    func apply(
        preparedContent: MarkdownPreparedContent,
        row: Int,
        markdown: String,
        width: CGFloat
    ) -> Bool {
        guard represents(row: row, markdown: markdown, width: width) else { return false }
        renderToken = UUID()
        markdownView.preferredMeasurementWidth = width
        preparationIndicator.stopAnimating()
        markdownView.isHidden = false
        markdownView.setPreparedContent(preparedContent)
        setNeedsLayout()
        return true
    }

    func represents(row: Int, markdown: String, width: CGFloat) -> Bool {
        representedRow == row
            && representedMarkdown == markdown
            && abs(representedWidth - width) <= 1
    }

    /// UITableView 将 Cell 放入复用队列时不会立即调用 `prepareForReuse()`。
    /// 离屏即释放长文的 slots、文本池与自定义视图；页面级 prepared cache
    /// 仍保留紧凑渲染模型，回滚时无需重新 parse Markdown。
    func releaseRenderedContent() {
        // 短文本由 UITableView 整行复用已经足够；反复清空只会让边界回滚
        // 重新 parse/render。只清理已进入文档内视口窗口的长 prepared cell。
        guard markdownView.isUsingStaticViewportRendering else { return }
        renderToken = UUID()
        representedRow = nil
        representedMarkdown = nil
        representedWidth = 0
        preparationIndicator.stopAnimating()
        markdownView.isHidden = false
        markdownView.resetForReuse()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        renderToken = UUID()
        representedRow = nil
        representedMarkdown = nil
        representedWidth = 0
        preparationIndicator.stopAnimating()
        markdownView.isHidden = false
        onContentHeightChange = nil
        markdownView.resetForReuse()
    }
}
