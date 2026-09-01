import Cocoa

// MARK: - 复习页（融合 Anki：翻转卡片 + SM-2 四档评分，队列来自全部模块的共享记忆）
// Views 层：队列构建与评分落库委托 ReviewService，本视图只负责翻卡与渲染。

final class ReviewPageView: NSView {

    // MARK: - 属性

    private weak var state: AppState?
    private var queue: [ReviewCard] = []
    private var position = 0
    private var cardFlipped = false

    private let progressLabel = LabelFactory.label("", font: .systemFont(ofSize: 12), color: Theme.textSecondary, align: .center)
    private let card = CardView()
    private let kindLabel = LabelFactory.label("", font: .systemFont(ofSize: 12, weight: .medium), color: Theme.primary, align: .center)
    private let frontLabel = LabelFactory.label("", font: .systemFont(ofSize: 28, weight: .bold), align: .center)
    private let phoneticLabel = LabelFactory.label("", font: .systemFont(ofSize: 15), color: Theme.textSecondary, align: .center)
    private let backLabel = LabelFactory.label("", font: Theme.mono(24), color: Theme.success, align: .center)
    private let detailLabel = LabelFactory.label("", font: Theme.body(13), color: Theme.textSecondary, align: .center)
    private let flipHint = LabelFactory.label("点击卡片查看答案", font: .systemFont(ofSize: 12), color: Theme.textTertiary, align: .center)
    private var gradeButtons: [ReviewGrade: NSButton] = [:]
    private let emptyView = NSView()

    // MARK: - 初始化

    init(state: AppState) {
        self.state = state
        super.init(frame: .zero)
        setupLayout()
        rebuildQueue()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未使用") }
    override var isFlipped: Bool { true }

    /// 每次进入页面时重建到期队列
    func refresh() {
        rebuildQueue()
    }

    // MARK: - 布局

    private func setupLayout() {
        let title = LabelFactory.label("间隔复习", font: Theme.titleFont(24))
        addSubview(title)
        title.frame = CGRect(x: 0, y: 8, width: 200, height: 30)

        addSubview(progressLabel)
        progressLabel.frame = CGRect(x: 0, y: 60, width: 700, height: 18)

        card.frame = CGRect(x: 80, y: 92, width: 540, height: 280)
        addSubview(card)
        let clickCard = NSClickGestureRecognizer(target: self, action: #selector(cardTapped))
        card.addGestureRecognizer(clickCard)

        kindLabel.frame = CGRect(x: 20, y: 26, width: 500, height: 18)
        frontLabel.frame = CGRect(x: 30, y: 70, width: 480, height: 80)
        phoneticLabel.frame = CGRect(x: 30, y: 158, width: 480, height: 22)
        backLabel.frame = CGRect(x: 30, y: 184, width: 480, height: 40)
        detailLabel.frame = CGRect(x: 40, y: 232, width: 460, height: 36)
        flipHint.frame = CGRect(x: 20, y: 252, width: 500, height: 18)
        [kindLabel, frontLabel, phoneticLabel, backLabel, detailLabel, flipHint].forEach { card.addSubview($0) }

        layoutGradeButtons()
        layoutEmpty()
    }

    private func layoutGradeButtons() {
        let grades: [ReviewGrade] = [.again, .hard, .good, .easy]
        let colors: [ReviewGrade: NSColor] = [
            .again: Theme.danger, .hard: Theme.warning, .good: Theme.info, .easy: Theme.success
        ]
        let width: CGFloat = 120
        let startX: CGFloat = 90
        grades.enumerated().forEach { index, grade in
            let button = HandCursorButton()
            button.title = grade.displayName
            button.isBordered = false
            button.font = .systemFont(ofSize: 13, weight: .semibold)
            button.contentTintColor = .white
            button.wantsLayer = true
            button.layer?.cornerRadius = 8
            button.layer?.backgroundColor = colors[grade]?.cgColor
            button.target = self
            button.action = #selector(gradeTapped(_:))
            button.tag = grade.rawValue
            addSubview(button)
            button.frame = CGRect(x: startX + CGFloat(index) * (width + 13), y: 400, width: width, height: 44)
            gradeButtons[grade] = button
        }
    }

    private func layoutEmpty() {
        addSubview(emptyView)
        emptyView.frame = CGRect(x: 80, y: 120, width: 540, height: 300)
        let icon = LabelFactory.label("✅", font: .systemFont(ofSize: 46), align: .center)
        let done = LabelFactory.label("今日复习已完成", font: Theme.titleFont(22), align: .center)
        let tip = LabelFactory.label("各模块练习过的内容会按记忆曲线在到期时回到这里",
                                     font: Theme.body(13), color: Theme.textSecondary, align: .center)
        let home = ButtonFactory.primary("回到学习中心", target: self, action: #selector(homeTapped))
        emptyView.addSubview(icon); emptyView.addSubview(done); emptyView.addSubview(tip); emptyView.addSubview(home)
        icon.frame = CGRect(x: 0, y: 30, width: 540, height: 60)
        done.frame = CGRect(x: 0, y: 110, width: 540, height: 30)
        tip.frame = CGRect(x: 60, y: 150, width: 420, height: 40)
        home.frame = CGRect(x: 200, y: 210, width: 140, height: 40)
        emptyView.isHidden = true
    }

    // MARK: - 队列与渲染

    private func rebuildQueue() {
        queue = state?.reviewService.buildQueue(now: Date()) ?? []
        position = 0
        emptyView.isHidden = !queue.isEmpty
        card.isHidden = queue.isEmpty
        gradeButtons.values.forEach { $0.isHidden = queue.isEmpty }
        showCurrent()
    }

    private func showCurrent() {
        cardFlipped = false
        guard position < queue.count else {
            progressLabel.stringValue = queue.isEmpty ? "" : "本轮复习完成"
            emptyView.isHidden = queue.isEmpty ? false : true
            card.isHidden = queue.isEmpty
            return
        }
        let item = queue[position]
        progressLabel.stringValue = "第 \(position + 1)/\(queue.count) 张 · 来源：\(sourceName(item.kind))"
        kindLabel.stringValue = sourceName(item.kind)
        frontLabel.stringValue = item.prompt
        phoneticLabel.stringValue = ""
        backLabel.stringValue = ""
        detailLabel.stringValue = ""
        flipHint.stringValue = "点击卡片查看答案（或按空格键）"
        gradeButtons.values.forEach { $0.isHidden = true }
    }

    private func flip() {
        guard position < queue.count else { return }
        cardFlipped = true
        let item = queue[position]
        phoneticLabel.stringValue = item.phonetic
        backLabel.stringValue = item.answer
        detailLabel.stringValue = item.detail
        flipHint.stringValue = "根据回忆情况选择下方评分"
        gradeButtons.values.forEach { $0.isHidden = false }
        state?.speech.speak(item.answer, rate: 0.5)
    }

    // MARK: - 交互

    @objc private func cardTapped() { if !cardFlipped { flip() } }

    /// 键盘空格翻卡（由 RootViewController 转发）
    func handleSpace() { if !cardFlipped { flip() } }

    @objc private func gradeTapped(_ sender: NSButton) {
        guard let grade = ReviewGrade(rawValue: sender.tag), position < queue.count else { return }
        let cardItem = queue[position]
        let updated = state?.reviewService.grade(cardItem, grade: grade, now: Date())
        if grade == .again, let updated {
            // 没记住：本轮末尾再出现一次，记忆状态使用刚评分后的最新值
            let repeatCard = ReviewCard(memory: updated, kind: cardItem.kind, prompt: cardItem.prompt,
                                        answer: cardItem.answer, phonetic: cardItem.phonetic, detail: cardItem.detail)
            queue.append(repeatCard)
        }
        position += 1
        showCurrent()
    }

    @objc private func homeTapped() { state?.go(.home) }

    private func sourceName(_ kind: MemoryKind) -> String {
        switch kind {
        case .word: return "单词打字"
        case .sentence: return "连词造句"
        case .speaking: return "口语私教"
        }
    }
}
