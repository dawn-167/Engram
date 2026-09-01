import Cocoa

// MARK: - 连词造句页（融合 Earthworm：打乱词块、点选排序、即时纠错、朗读）
// Views 层：分词/打乱/校验全部委托 SentenceBuildService，本视图只渲染与转发点击。

final class SentenceBuildPageView: NSView {

    // MARK: - 属性

    private weak var state: AppState?
    private let service = SentenceBuildService()
    private var sentences: [SentenceEntry] = []
    private var index = 0
    private var targetTokens: [String] = []
    private var scrambled: [String] = []
    private var pickedIndices: [Int] = []

    private let deckPicker = NSPopUpButton()
    private let progressLabel = LabelFactory.label("", font: .systemFont(ofSize: 12), color: Theme.textSecondary)
    private let translationLabel = LabelFactory.label("", font: .systemFont(ofSize: 24, weight: .bold), align: .center)
    private let answerLabel = LabelFactory.label("", font: Theme.mono(22), color: Theme.success, align: .center)
    private let pickedFlow = FlowLayoutView()
    private let optionsFlow = FlowLayoutView()
    private let feedbackLabel = LabelFactory.label("", font: .systemFont(ofSize: 13), align: .center)
    private let nextButton = NSButton()

    // MARK: - 初始化

    init(state: AppState) {
        self.state = state
        super.init(frame: .zero)
        setupLayout()
        populateDecks()
        loadSentences()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未使用") }
    override var isFlipped: Bool { true }

    // MARK: - 布局

    private func setupLayout() {
        let title = LabelFactory.label("连词造句", font: Theme.titleFont(24))
        addSubview(title)
        title.frame = CGRect(x: 0, y: 8, width: 200, height: 30)

        deckPicker.target = self
        deckPicker.action = #selector(deckChanged)
        addSubview(deckPicker)
        deckPicker.frame = CGRect(x: 466, y: 9, width: 230, height: 28)

        addSubview(progressLabel)
        progressLabel.frame = CGRect(x: 0, y: 62, width: 700, height: 18)
        progressLabel.alignment = .center

        translationLabel.frame = CGRect(x: 60, y: 100, width: 580, height: 36)
        addSubview(translationLabel)

        let pickedCard = CardView()
        addSubview(pickedCard)
        pickedCard.frame = CGRect(x: 40, y: 160, width: 620, height: 130)
        pickedCard.autoresizingMask = [.width]
        pickedCard.addSubview(pickedFlow)
        pickedFlow.frame = CGRect(x: 0, y: 0, width: 620, height: 130)
        pickedFlow.autoresizingMask = [.width]

        answerLabel.frame = CGRect(x: 40, y: 300, width: 620, height: 30)
        addSubview(answerLabel)

        feedbackLabel.frame = CGRect(x: 40, y: 336, width: 620, height: 20)
        addSubview(feedbackLabel)

        let optionsCard = CardView()
        addSubview(optionsCard)
        optionsCard.frame = CGRect(x: 40, y: 372, width: 620, height: 150)
        optionsCard.autoresizingMask = [.width]
        optionsCard.addSubview(optionsFlow)
        optionsFlow.frame = CGRect(x: 0, y: 0, width: 620, height: 150)
        optionsFlow.autoresizingMask = [.width]

        nextButton.title = "下一句 →"
        nextButton.bezelStyle = .inline
        nextButton.isBordered = false
        nextButton.font = .systemFont(ofSize: 14, weight: .semibold)
        nextButton.contentTintColor = .white
        nextButton.wantsLayer = true
        nextButton.layer?.backgroundColor = Theme.primary.cgColor
        nextButton.layer?.cornerRadius = 8
        nextButton.target = self
        nextButton.action = #selector(nextTapped)
        addSubview(nextButton)
        nextButton.frame = CGRect(x: 290, y: 540, width: 120, height: 38)
        nextButton.isHidden = true
    }

    // MARK: - 数据加载

    private func populateDecks() {
        deckPicker.removeAllItems()
        for deck in state?.library.sentenceDecks ?? [] where deck.kind == .sentence {
            deckPicker.addItem(withTitle: deck.name)
            deckPicker.lastItem?.representedObject = deck.id
        }
    }

    @objc private func deckChanged() { loadSentences() }

    private func loadSentences() {
        guard let deckId = deckPicker.selectedItem?.representedObject as? String else { return }
        sentences = state?.library.sentences(in: deckId) ?? []
        index = 0
        presentCurrent()
    }

    private func presentCurrent() {
        guard index < sentences.count else { return }
        let sentence = sentences[index]
        targetTokens = service.tokens(of: sentence)
        scrambled = service.shuffled(targetTokens)
        pickedIndices = []
        translationLabel.stringValue = sentence.translation
        answerLabel.stringValue = ""
        feedbackLabel.stringValue = "按正确语序点击下方词块组成句子"
        feedbackLabel.textColor = Theme.textSecondary
        nextButton.isHidden = true
        progressLabel.stringValue = "第 \(index + 1)/\(sentences.count) 句 · \(sentence.level.displayName)"
        rebuildFlows()
    }

    // MARK: - 交互

    private func rebuildFlows() {
        let pickedTokens = pickedIndices.map { scrambled[$0] }
        pickedFlow.setSubviews(pickedTokens.enumerated().map { order, _ in
            makeTokenButton(title: pickedTokens[order], tag: pickedIndices[order], style: .picked)
        })
        let remaining = scrambled.indices.filter { !pickedIndices.contains($0) }
        optionsFlow.setSubviews(remaining.map { idx in
            makeTokenButton(title: scrambled[idx], tag: idx, style: .option)
        })
    }

    private enum TokenStyle { case option, picked }

    private func makeTokenButton(title: String, tag: Int, style: TokenStyle) -> NSButton {
        let button = NSButton()
        button.title = title
        button.tag = tag
        button.isBordered = false
        button.font = .systemFont(ofSize: 15, weight: .medium)
        button.target = self
        button.action = style == .picked ? #selector(pickedTapped(_:)) : #selector(optionTapped(_:))
        button.sizeToFit()
        let padded = NSSize(width: button.bounds.width + 24, height: 34)
        button.setFrameSize(padded)
        button.wantsLayer = true
        button.layer?.cornerRadius = 17
        switch style {
        case .option:
            button.layer?.backgroundColor = Theme.primary.withAlphaComponent(0.12).cgColor
            button.contentTintColor = Theme.primaryDeep
        case .picked:
            button.layer?.backgroundColor = Theme.success.withAlphaComponent(0.15).cgColor
            button.contentTintColor = Theme.success
        }
        return button
    }

    @objc private func optionTapped(_ sender: NSButton) {
        let candidate = pickedIndices.map { scrambled[$0] } + [scrambled[sender.tag]]
        guard service.isPrefixCorrect(picked: candidate, target: targetTokens) else {
            feedbackLabel.stringValue = "语序不对，想想这个词应该放在哪里"
            feedbackLabel.textColor = Theme.danger
            return
        }
        pickedIndices.append(sender.tag)
        feedbackLabel.stringValue = pickedIndices.count == targetTokens.count ? "" : "继续"
        feedbackLabel.textColor = Theme.textSecondary
        if service.isComplete(picked: pickedIndices.map({ scrambled[$0] }), target: targetTokens) {
            completeSentence()
        } else {
            rebuildFlows()
        }
    }

    @objc private func pickedTapped(_ sender: NSButton) {
        // 点击已选词块：撤销它及其后所有选择
        guard let position = pickedIndices.firstIndex(of: sender.tag) else { return }
        pickedIndices = Array(pickedIndices.prefix(position))
        answerLabel.stringValue = ""
        nextButton.isHidden = true
        feedbackLabel.stringValue = "已回退，继续组句"
        feedbackLabel.textColor = Theme.textSecondary
        rebuildFlows()
    }

    private func completeSentence() {
        guard let sentence = sentences[safe: index] else { return }
        rebuildFlows()
        answerLabel.stringValue = sentence.text
        feedbackLabel.stringValue = "组句正确！"
        feedbackLabel.textColor = Theme.success
        nextButton.isHidden = false
        state?.recordPractice(id: sentence.id, kind: .sentence, grade: .good)
        state?.store.recordToday(action: { $0.sentencesBuilt += 1 }, now: Date())
        state?.speech.speak(sentence.text, rate: state?.store.data.settings.speechRate ?? 0.42)
    }

    @objc private func nextTapped() {
        index = (index + 1) % max(sentences.count, 1)
        presentCurrent()
    }
}

// MARK: - 安全下标访问
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
