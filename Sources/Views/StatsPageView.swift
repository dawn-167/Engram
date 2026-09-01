import Cocoa

// MARK: - 学习统计页（累计数据 / 连续天数 / 七日活跃 / 各模块练习量）
// Views 层：所有数值由 StatsService 计算，本视图只展示。

final class StatsPageView: NSView {

    // MARK: - 属性

    private weak var state: AppState?
    private let weekBars = WeekBarsView()
    private let valueLabels: [String: NSTextField] = [
        "typed": StatsPageView.makeValue(),
        "sentence": StatsPageView.makeValue(),
        "spoken": StatsPageView.makeValue(),
        "reviewed": StatsPageView.makeValue(),
        "streak": StatsPageView.makeValue(),
        "learned": StatsPageView.makeValue(),
        "mastered": StatsPageView.makeValue(),
        "accuracy": StatsPageView.makeValue()
    ]

    // MARK: - 初始化

    init(state: AppState) {
        self.state = state
        super.init(frame: .zero)
        setupLayout()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未使用") }
    override var isFlipped: Bool { true }

    func refresh() {
        guard let summary = state?.statsService.summary(now: Date()) else { return }
        valueLabels["typed"]?.stringValue = "\(summary.totalTyped)"
        valueLabels["sentence"]?.stringValue = "\(summary.totalSentences)"
        valueLabels["spoken"]?.stringValue = "\(summary.totalSpoken)"
        valueLabels["reviewed"]?.stringValue = "\(summary.totalReviewed)"
        valueLabels["streak"]?.stringValue = "\(summary.streakDays)"
        valueLabels["learned"]?.stringValue = "\(summary.learnedTotal)"
        valueLabels["mastered"]?.stringValue = "\(summary.masteredTotal)"
        valueLabels["accuracy"]?.stringValue = "\(Int(summary.typingAccuracy * 100))%"
        weekBars.setData(summary.weekly)
    }

    // MARK: - 布局

    private func setupLayout() {
        let title = LabelFactory.label("学习统计", font: Theme.titleFont(24))
        addSubview(title)
        title.frame = CGRect(x: 0, y: 8, width: 200, height: 30)

        // 第一行：核心成就
        let achievements: [(String, String)] = [
            ("streak", "连续天数"), ("learned", "累计学习"),
            ("mastered", "已掌握"), ("accuracy", "打字正确率")
        ]
        layoutTiles(achievements, y: 60, color: Theme.primary)

        // 第二行：分模块练习量
        let modules: [(String, String)] = [
            ("typed", "打字单词"), ("sentence", "造句"),
            ("spoken", "口语练习"), ("reviewed", "复习卡片")
        ]
        layoutTiles(modules, y: 180, color: Theme.info)

        // 七日活跃卡片
        let card = CardView()
        addSubview(card)
        card.frame = CGRect(x: 0, y: 300, width: 700, height: 240)
        card.autoresizingMask = [.maxYMargin, .width]
        let weekTitle = LabelFactory.label("最近 7 天练习量", font: Theme.heading(15))
        card.addSubview(weekTitle)
        weekTitle.frame = CGRect(x: 18, y: 16, width: 300, height: 20)
        card.addSubview(weekBars)
        weekBars.frame = CGRect(x: 24, y: 56, width: 652, height: 160)
    }

    private func layoutTiles(_ items: [(key: String, caption: String)], y: CGFloat, color: NSColor) {
        let width: CGFloat = 166
        items.enumerated().forEach { index, item in
            let card = CardView()
            addSubview(card)
            card.frame = CGRect(x: CGFloat(index) * (width + 12), y: y, width: width, height: 96)
            card.autoresizingMask = [.maxYMargin]
            guard let value = valueLabels[item.key] else { return }
            value.textColor = color
            let caption = LabelFactory.label(item.caption, font: .systemFont(ofSize: 12),
                                             color: Theme.textSecondary, align: .center)
            card.addSubview(value); card.addSubview(caption)
            value.frame = CGRect(x: 0, y: 22, width: width, height: 34)
            caption.frame = CGRect(x: 0, y: 60, width: width, height: 18)
        }
    }

    private static func makeValue() -> NSTextField {
        LabelFactory.label("0", font: .systemFont(ofSize: 26, weight: .bold), align: .center)
    }
}
