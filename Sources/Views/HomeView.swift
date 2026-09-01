import Cocoa

// MARK: - 学习中心首页（仪表盘：今日概览 + 模块入口 + 七日活跃）
// Views 层：数据来自 StatsService，点击通过 onNavigate 上报，由 App 层路由。

final class HomeView: NSView {

    // MARK: - 属性

    private weak var state: AppState?
    var onNavigate: ((AppPage) -> Void)?

    private let dueValue = LabelFactory.label("", font: .systemFont(ofSize: 30, weight: .heavy), color: Theme.primary)
    private let todayValue = LabelFactory.label("", font: .systemFont(ofSize: 22, weight: .bold))
    private let streakValue = LabelFactory.label("", font: .systemFont(ofSize: 22, weight: .bold))
    private let learnedValue = LabelFactory.label("", font: .systemFont(ofSize: 22, weight: .bold))
    private let masteredValue = LabelFactory.label("", font: .systemFont(ofSize: 22, weight: .bold))
    private let goalBar = ProgressBar()
    private let goalLabel = LabelFactory.label("", font: .systemFont(ofSize: 12), color: Theme.textSecondary)
    private let weekBars = WeekBarsView()

    // MARK: - 初始化

    init(state: AppState) {
        self.state = state
        super.init(frame: .zero)
        setupLayout()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未使用") }

    /// 页面容器统一使用翻转坐标，自顶向下布局
    override var isFlipped: Bool { true }

    // MARK: - 公开方法

    /// 每次页面出现时调用，按最新数据重绘
    func refresh() {
        guard let summary = state?.statsService.summary(now: Date()) else { return }
        dueValue.stringValue = "\(summary.dueCount)"
        todayValue.stringValue = "\(summary.todayActions)"
        streakValue.stringValue = "\(summary.streakDays)"
        learnedValue.stringValue = "\(summary.learnedTotal)"
        masteredValue.stringValue = "\(summary.masteredTotal)"
        goalBar.setProgress(summary.goalProgress)
        goalLabel.stringValue = "今日新学 \(summary.todayNewLearned)/\(summary.dailyNewGoal)"
        weekBars.setData(summary.weekly)
    }

    // MARK: - 布局

    private func setupLayout() {
        let title = LabelFactory.label("学习中心", font: Theme.titleFont(26), color: Theme.textPrimary)
        let dateLabel = LabelFactory.label(Self.dateText(), font: Theme.body(12), color: Theme.textSecondary)
        addSubview(title); addSubview(dateLabel)
        title.frame = CGRect(x: 0, y: 8, width: 300, height: 32)
        dateLabel.frame = CGRect(x: 0, y: 44, width: 300, height: 18)
        // 翻转坐标下 .maxYMargin 表示下边距可伸缩，从而把视图固定在顶部
        title.autoresizingMask = [.maxYMargin]
        dateLabel.autoresizingMask = [.maxYMargin]

        layoutStatTiles()
        layoutModuleEntries()
        layoutBottomCard()
    }

    private func layoutStatTiles() {
        let tiles: [(String, NSTextField, NSColor)] = [
            ("待复习", dueValue, Theme.danger),
            ("今日练习", todayValue, Theme.primary),
            ("连续天数", streakValue, Theme.warning),
            ("已学条目", learnedValue, Theme.info),
            ("已掌握", masteredValue, Theme.success)
        ]
        let tileWidth: CGFloat = 128
        let gap: CGFloat = 12
        tiles.enumerated().forEach { index, item in
            let card = HoverView()
            let caption = LabelFactory.label(item.1 == dueValue ? "立即复习 →" : item.0,
                                             font: .systemFont(ofSize: 12, weight: .medium),
                                             color: Theme.textSecondary)
            item.1.textColor = item.2
            addSubview(card)
            card.addSubview(item.1); card.addSubview(caption)
            let x = CGFloat(index) * (tileWidth + gap)
            card.frame = CGRect(x: x, y: 74, width: tileWidth, height: 76)
            card.autoresizingMask = [.maxYMargin]
            item.1.frame = CGRect(x: 14, y: 30, width: 110, height: 30)
            caption.frame = CGRect(x: 14, y: 10, width: 110, height: 16)
            if item.1 == dueValue {
                card.onClick = { [weak self] in self?.onNavigate?(.review) }
            }
        }
    }

    private func layoutModuleEntries() {
        let sectionTitle = LabelFactory.label("学习模块", font: Theme.heading(15), color: Theme.textPrimary)
        addSubview(sectionTitle)
        sectionTitle.frame = CGRect(x: 0, y: 168, width: 200, height: 20)
        sectionTitle.autoresizingMask = [.maxYMargin]

        let modules: [(AppPage, String, String)] = [
            (.typing, "keyboard", "边打字边背单词，练肌肉记忆"),
            (.sentence, "rectangle.and.text.magnifyingglass", "打乱词块，连词成句"),
            (.speaking, "mic.fill", "跟读评测，AI 式发音打分"),
            (.review, "rectangle.stack.fill", "间隔重复，到期复习")
        ]
        let width: CGFloat = 165
        modules.enumerated().forEach { index, item in
            let card = ModuleCard(symbol: item.1, title: item.0.title, subtitle: item.2)
            card.onClick = { [weak self] in self?.onNavigate?(item.0) }
            addSubview(card)
            card.frame = CGRect(x: CGFloat(index) * (width + 12), y: 198, width: width, height: 140)
            card.autoresizingMask = [.maxYMargin]
        }
    }

    private func layoutBottomCard() {
        let card = CardView()
        addSubview(card)
        card.frame = CGRect(x: 0, y: 358, width: 696, height: 220)
        card.autoresizingMask = [.maxYMargin]

        let goalTitle = LabelFactory.label("今日新学目标", font: Theme.heading(13))
        card.addSubview(goalTitle); card.addSubview(goalLabel); card.addSubview(goalBar)
        goalTitle.frame = CGRect(x: 18, y: 172, width: 200, height: 18)
        goalLabel.frame = CGRect(x: 496, y: 172, width: 170, height: 18)
        goalLabel.alignment = .right
        goalBar.frame = CGRect(x: 18, y: 148, width: 660, height: 8)

        let weekTitle = LabelFactory.label("最近 7 天活跃", font: Theme.heading(13))
        card.addSubview(weekTitle)
        weekTitle.frame = CGRect(x: 18, y: 104, width: 200, height: 18)
        card.addSubview(weekBars)
        weekBars.frame = CGRect(x: 18, y: 16, width: 660, height: 80)
    }

    // MARK: - 辅助

    private static func dateText() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        return formatter.string(from: Date())
    }
}

// MARK: - 模块入口卡片
private final class ModuleCard: HoverView {
    init(symbol: String, title: String, subtitle: String) {
        super.init(frame: .zero)
        let icon = NSImageView()
        icon.symbolConfiguration = .init(pointSize: 22, weight: .semibold)
        icon.contentTintColor = Theme.primary
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        let name = LabelFactory.label(title, font: Theme.heading(15))
        let desc = LabelFactory.label(subtitle, font: .systemFont(ofSize: 11), color: Theme.textSecondary)
        addSubview(icon); addSubview(name); addSubview(desc)
        icon.frame = CGRect(x: 16, y: 88, width: 32, height: 32)
        name.frame = CGRect(x: 16, y: 58, width: 150, height: 20)
        desc.frame = CGRect(x: 16, y: 20, width: 142, height: 36)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) 未使用") }
}
