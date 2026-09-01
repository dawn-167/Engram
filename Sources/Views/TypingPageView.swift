import Cocoa

// MARK: - 单词打字页（融合 Qwerty Learner：逐字母着色 / 错词重来 / 音标发音 / 速度正确率）
// Views 层：状态判断全部委托 TypingService，本视图只负责渲染与把按键转发。

final class TypingPageView: NSView {

    // MARK: - 属性

    private weak var state: AppState?
    private let service = TypingService()
    private var sessionWords: [WordEntry] = []
    private var wrongFlash = false

    private let deckPicker = NSPopUpButton()
    private let progressLabel = LabelFactory.label("", font: .systemFont(ofSize: 12), color: Theme.textSecondary)
    private let translationLabel = LabelFactory.label("", font: .systemFont(ofSize: 26, weight: .bold), align: .center)
    private let phoneticLabel = LabelFactory.label("", font: .systemFont(ofSize: 15), color: Theme.textSecondary, align: .center)
    private let wordLabel = NSTextField(labelWithString: "")
    private let hintLabel = LabelFactory.label("", font: .systemFont(ofSize: 12), color: Theme.textTertiary, align: .center)
    private let statWPM = LabelFactory.label("0", font: .systemFont(ofSize: 20, weight: .bold), align: .center)
    private let statAcc = LabelFactory.label("100%", font: .systemFont(ofSize: 20, weight: .bold), align: .center)
    private let summaryCard = CardView()
    private let keyboardCatcher = KeyboardCatcher()

    // MARK: - 初始化

    init(state: AppState) {
        self.state = state
        super.init(frame: .zero)
        keyboardCatcher.onKey = { [weak self] char in self?.handleKey(char) }
        setupLayout()
        populateDecks()
        startSession()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未使用") }
    override var isFlipped: Bool { true }

    /// 页面出现时夺回键盘焦点
    func activate() {
        window?.makeFirstResponder(keyboardCatcher)
    }

    // MARK: - 布局

    private func setupLayout() {
        let title = LabelFactory.label("单词打字", font: Theme.titleFont(24))
        addSubview(title)
        title.frame = CGRect(x: 0, y: 8, width: 200, height: 30)

        deckPicker.target = self
        deckPicker.action = #selector(deckChanged)
        addSubview(deckPicker)
        deckPicker.frame = CGRect(x: 356, y: 9, width: 228, height: 28)

        let restart = ButtonFactory.ghost("重新开始", target: self, action: #selector(restartTapped))
        addSubview(restart)
        restart.sizeToFit()
        restart.frame = CGRect(x: 592, y: 9, width: max(restart.bounds.width + 16, 96), height: 28)

        addSubview(progressLabel)
        progressLabel.frame = CGRect(x: 0, y: 64, width: 700, height: 18)
        progressLabel.alignment = .center

        translationLabel.frame = CGRect(x: 60, y: 170, width: 580, height: 40)
        phoneticLabel.frame = CGRect(x: 60, y: 216, width: 580, height: 22)
        addSubview(translationLabel); addSubview(phoneticLabel)

        wordLabel.alignment = .center
        wordLabel.font = Theme.mono(44)
        wordLabel.frame = CGRect(x: 40, y: 270, width: 620, height: 64)
        addSubview(wordLabel)

        hintLabel.frame = CGRect(x: 60, y: 350, width: 580, height: 20)
        addSubview(hintLabel)

        addSubview(keyboardCatcher)
        keyboardCatcher.frame = bounds
        keyboardCatcher.autoresizingMask = [.width, .height]

        layoutStatCards()
        layoutSummary()
        layoutBottomButtons()
    }

    private func layoutStatCards() {
        let captions = [("速度 WPM", statWPM), ("正确率", statAcc)]
        captions.enumerated().forEach { index, pair in
            let card = CardView()
            let caption = LabelFactory.label(pair.0, font: .systemFont(ofSize: 12),
                                              color: Theme.textSecondary, align: .center)
            addSubview(card)
            card.frame = CGRect(x: 200 + CGFloat(index) * 160, y: 430, width: 140, height: 72)
            card.addSubview(pair.1); card.addSubview(caption)
            pair.1.frame = CGRect(x: 0, y: 14, width: 140, height: 26)
            caption.frame = CGRect(x: 0, y: 46, width: 140, height: 16)
        }
    }

    private func layoutSummary() {
        addSubview(summaryCard)
        summaryCard.frame = CGRect(x: 120, y: 150, width: 460, height: 360)
        summaryCard.isHidden = true
    }

    private func layoutBottomButtons() {
        let speak = ButtonFactory.ghost("朗读单词", target: self, action: #selector(speakCurrent))
        let skip = ButtonFactory.ghost("跳过 (Tab)", target: self, action: #selector(skipTapped))
        addSubview(speak); addSubview(skip)
        speak.frame = CGRect(x: 230, y: 540, width: 110, height: 34)
        skip.frame = CGRect(x: 360, y: 540, width: 110, height: 34)
    }

    // MARK: - 会话控制

    private func populateDecks() {
        deckPicker.removeAllItems()
        for deck in state?.library.wordDecks ?? [] {
            deckPicker.addItem(withTitle: "\(deck.name)（\(state?.library.words(in: deck.id).count ?? 0)）")
            deckPicker.lastItem?.representedObject = deck.id
        }
    }

    @objc private func deckChanged() { startSession() }

    @objc private func restartTapped() { startSession() }

    private func startSession() {
        guard let deckId = deckPicker.selectedItem?.representedObject as? String,
              let words = state?.library.words(in: deckId), !words.isEmpty else { return }
        sessionWords = Array(words.prefix(20))
        service.startSession(words: sessionWords)
        summaryCard.isHidden = true
        render()
        activate()
    }

    // MARK: - 输入处理

    private func handleKey(_ char: Character) {
        // 总结面板出现后，任意字母键开启下一组
        if !summaryCard.isHidden { startSession(); return }
        if char == "\t" {
            let feedback = service.skipCurrent()
            if feedback == .sessionFinished { finishSession() } else { render() }
            return
        }
        guard char.isLetter else { return }
        let feedback = service.input(character: char)
        switch feedback {
        case .accepted:
            render()
        case .wrongAndReset:
            wrongFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                self?.wrongFlash = false
                self?.render()
            }
            render()
        case .wordCompleted:
            onWordCompleted()
        case .sessionFinished:
            onWordCompleted()
            finishSession()
        }
    }

    @objc private func skipTapped() {
        let feedback = service.skipCurrent()
        if feedback == .sessionFinished { finishSession() } else { render() }
    }

    @objc private func speakCurrent() {
        guard let word = service.currentWord else { return }
        state?.speech.speak(word.text, rate: state?.store.data.settings.speechRate ?? 0.42)
    }

    private func onWordCompleted() {
        // TypingService 完成后已前进，completedWords 即刚完成单词的序号（从 1 起）
        let done = service.stats.completedWords
        let target = sessionWords[max(0, done - 1)]
        state?.recordPractice(id: target.id, kind: .word, grade: .good)
        state?.store.recordToday(action: { $0.wordsTyped += 1 }, now: Date())
        state?.speech.speak(target.text, rate: 0.5)
        render()
    }

    private func finishSession() {
        let s = service.stats
        state?.store.recordToday(action: { stat in
            stat.keyPressCorrect += s.correctKeyPresses
            stat.keyPressTotal += s.totalKeyPresses
        }, now: Date())
        summaryCard.subviews.forEach { $0.removeFromSuperview() }
        buildSummaryContent(wpm: Int(s.wpm.rounded()), acc: Int((s.accuracy * 100).rounded()))
        summaryCard.isHidden = false
    }

    // MARK: - 渲染

    private func render() {
        guard let word = service.currentWord else { return }
        translationLabel.stringValue = word.translation
        phoneticLabel.stringValue = word.phonetic
        progressLabel.stringValue = "\(service.stats.completedWords)/\(service.stats.totalWords)　·　错词 \(service.stats.errorWords)"
        statWPM.stringValue = "\(Int(service.stats.wpm.rounded()))"
        statAcc.stringValue = "\(Int((service.stats.accuracy * 100).rounded()))%"
        wordLabel.attributedStringValue = renderWordText(word.text)
        hintLabel.stringValue = wrongFlash ? "输入错误，本词需要重新输入" : "直接敲击键盘输入英文，错一个字母就要重来"
    }

    private func renderWordText(_ text: String) -> NSAttributedString {
        let states = service.charStates()
        // 富文本必须显式带居中段落样式，否则会覆盖 NSTextField 的 alignment=.center
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let result = NSMutableAttributedString()
        let font = Theme.mono(44)
        for (index, char) in text.enumerated() {
            let state = states.indices.contains(index) ? states[index] : .pending
            let color: NSColor
            if wrongFlash { color = Theme.danger }
            else {
                switch state {
                case .correct: color = Theme.success
                case .wrong: color = Theme.danger
                case .pending: color = Theme.textTertiary
                }
            }
            result.append(NSAttributedString(string: String(char),
                                             attributes: [.font: font,
                                                          .foregroundColor: color,
                                                          .paragraphStyle: para]))
        }
        return result
    }

    private func buildSummaryContent(wpm: Int, acc: Int) {
        let title = LabelFactory.label("本组完成！", font: Theme.titleFont(22), align: .center)
        let wpmLabel = LabelFactory.label("速度 \(wpm) WPM", font: Theme.heading(16), align: .center)
        let accLabel = LabelFactory.label("正确率 \(acc)%", font: Theme.heading(16), align: .center)
        let again = ButtonFactory.primary("再来一组", target: self, action: #selector(restartTapped))
        for v in [title, wpmLabel, accLabel, again] { summaryCard.addSubview(v) }
        title.frame = CGRect(x: 0, y: 70, width: 460, height: 32)
        wpmLabel.frame = CGRect(x: 0, y: 140, width: 460, height: 24)
        accLabel.frame = CGRect(x: 0, y: 180, width: 460, height: 24)
        again.frame = CGRect(x: 160, y: 270, width: 140, height: 40)
    }
}
