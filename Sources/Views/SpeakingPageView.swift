import Cocoa

// MARK: - 口语私教页（融合 ChatterPal：示范朗读 / 录音识别 / 多维发音评分，全程离线零 Key）
// Views 层：识别委托 Recognizer、评分委托 PronunciationScorer，本视图只做渲染与交互转发。

final class SpeakingPageView: NSView {

    // MARK: - 属性

    private weak var state: AppState?
    private let scorer = PronunciationScorer()
    private var sentences: [SentenceEntry] = []
    private var index = 0
    private var isRecording = false

    private let deckPicker = NSPopUpButton()
    private let targetLabel = LabelFactory.label("", font: .systemFont(ofSize: 26, weight: .bold), align: .center)
    private let translationLabel = LabelFactory.label("", font: .systemFont(ofSize: 15), color: Theme.textSecondary, align: .center)
    private let transcriptLabel = LabelFactory.label("", font: Theme.body(13), color: Theme.textSecondary, align: .center)
    private let scoreLabel = LabelFactory.label("", font: .systemFont(ofSize: 40, weight: .heavy), align: .center)
    private let levelLabel = LabelFactory.label("", font: Theme.heading(16), align: .center)
    private let detailLabel = LabelFactory.label("", font: Theme.body(12), color: Theme.textSecondary, align: .center)
    private let recordButton = NSButton()
    private let speakButton = NSButton()
    private let voicePicker = NSPopUpButton()
    private let voiceHint = LabelFactory.label("", font: .systemFont(ofSize: 11),
                                                color: Theme.textTertiary, align: .center)

    // MARK: - 初始化

    init(state: AppState) {
        self.state = state
        super.init(frame: .zero)
        setupLayout()
        populateDecks()
        populateVoices()
        loadSentences()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未使用") }
    override var isFlipped: Bool { true }

    // MARK: - 布局

    private func setupLayout() {
        let title = LabelFactory.label("口语私教", font: Theme.titleFont(24))
        addSubview(title)
        title.frame = CGRect(x: 0, y: 8, width: 200, height: 30)

        deckPicker.target = self
        deckPicker.action = #selector(deckChanged)
        addSubview(deckPicker)
        deckPicker.frame = CGRect(x: 466, y: 9, width: 230, height: 28)

        let card = CardView()
        addSubview(card)
        card.frame = CGRect(x: 60, y: 70, width: 580, height: 200)
        targetLabel.frame = CGRect(x: 30, y: 40, width: 520, height: 70)
        translationLabel.frame = CGRect(x: 30, y: 120, width: 520, height: 24)
        transcriptLabel.frame = CGRect(x: 30, y: 150, width: 520, height: 40)
        card.addSubview(targetLabel); card.addSubview(translationLabel); card.addSubview(transcriptLabel)

        layoutResultArea()
        layoutControls()
        layoutVoicePicker()
    }

    private func layoutVoicePicker() {
        addSubview(voicePicker)
        voicePicker.frame = CGRect(x: 218, y: 520, width: 260, height: 26)
        voicePicker.target = self
        voicePicker.action = #selector(voiceChanged)
        addSubview(voiceHint)
        voiceHint.frame = CGRect(x: 60, y: 552, width: 580, height: 18)
        voiceHint.stringValue = "音质不佳？系统设置 → 辅助功能 → 朗读内容 → 系统声音 → 管理声音，安装 ★Premium 语音"
    }

    private func layoutResultArea() {
        scoreLabel.frame = CGRect(x: 250, y: 296, width: 200, height: 50)
        levelLabel.frame = CGRect(x: 250, y: 350, width: 200, height: 22)
        detailLabel.frame = CGRect(x: 80, y: 380, width: 540, height: 40)
        addSubview(scoreLabel); addSubview(levelLabel); addSubview(detailLabel)
    }

    private func layoutControls() {
        configureRoundButton(speakButton, title: "听示范", symbol: "speaker.wave.2.fill",
                             color: Theme.info, action: #selector(speakTapped))
        configureRoundButton(recordButton, title: "按住录音", symbol: "mic.fill",
                             color: Theme.primary, action: #selector(recordTapped))
        addSubview(speakButton); addSubview(recordButton)
        speakButton.frame = CGRect(x: 220, y: 450, width: 120, height: 46)
        recordButton.frame = CGRect(x: 360, y: 450, width: 140, height: 46)

        let prev = ButtonFactory.ghost("上一句", target: self, action: #selector(prevTapped))
        let next = ButtonFactory.primary("下一句", target: self, action: #selector(nextTapped))
        addSubview(prev); addSubview(next)
        prev.frame = CGRect(x: 60, y: 452, width: 90, height: 42)
        next.frame = CGRect(x: 590, y: 452, width: 90, height: 42)
    }

    private func configureRoundButton(_ button: NSButton, title: String, symbol: String,
                                      color: NSColor, action: Selector) {
        button.title = title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.isBordered = false
        button.bezelStyle = .inline
        button.font = .systemFont(ofSize: 14, weight: .semibold)
        button.contentTintColor = .white
        button.wantsLayer = true
        button.layer?.cornerRadius = 23
        button.layer?.backgroundColor = color.cgColor
        button.target = self
        button.action = action
    }

    // MARK: - 数据

    private func populateDecks() {
        deckPicker.removeAllItems()
        for deck in state?.library.sentenceDecks ?? [] where deck.kind == .speaking {
            deckPicker.addItem(withTitle: deck.name)
            deckPicker.lastItem?.representedObject = deck.id
        }
    }

    @objc private func deckChanged() { loadSentences() }

    private func populateVoices() {
        voicePicker.removeAllItems()
        guard let state else { return }
        for v in state.speech.availableVoices {
            voicePicker.addItem(withTitle: v.label)
            voicePicker.lastItem?.representedObject = v.identifier
        }
        // availableVoices 已按质量降序，默认选第一个（当前最优）
        voicePicker.selectItem(at: 0)
    }

    @objc private func voiceChanged() {
        guard let identifier = voicePicker.selectedItem?.representedObject as? String else { return }
        state?.speech.setVoice(identifier: identifier)
    }

    private func loadSentences() {
        guard let deckId = deckPicker.selectedItem?.representedObject as? String else { return }
        sentences = state?.library.sentences(in: deckId) ?? []
        index = 0
        presentCurrent()
    }

    private func presentCurrent() {
        guard index < sentences.count else { return }
        let sentence = sentences[index]
        targetLabel.stringValue = sentence.text
        translationLabel.stringValue = sentence.translation
        transcriptLabel.stringValue = "点击「听示范」跟读，再点「按住录音」评测发音"
        scoreLabel.stringValue = ""
        levelLabel.stringValue = ""
        detailLabel.stringValue = ""
    }

    // MARK: - 交互

    @objc private func speakTapped() {
        guard let sentence = sentences[safe: index] else { return }
        state?.speech.speak(sentence.text, rate: state?.store.data.settings.speechRate ?? 0.42)
    }

    @objc private func prevTapped() {
        index = (index - 1 + max(sentences.count, 1)) % max(sentences.count, 1)
        presentCurrent()
    }

    @objc private func nextTapped() {
        index = (index + 1) % max(sentences.count, 1)
        presentCurrent()
    }

    @objc private func recordTapped() {
        guard let recognizer = state?.recognizer else { return }
        if isRecording {
            isRecording = false
            recognizer.stop()
            recordButton.title = "按住录音"
            return
        }
        guard recognizer.isAvailable else {
            transcriptLabel.stringValue = "系统英文识别暂不可用，可先用「听示范」跟读"
            return
        }
        recognizer.requestAuthorization { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.transcriptLabel.stringValue = "未获得麦克风/语音识别授权"
                return
            }
            self.startRecording()
        }
    }

    private func startRecording() {
        guard let recognizer = state?.recognizer, let sentence = sentences[safe: index] else { return }
        isRecording = true
        recordButton.title = "停止识别"
        transcriptLabel.stringValue = "正在聆听……请大声朗读"
        do {
            try recognizer.start(onPartial: { [weak self] partial in
                self?.transcriptLabel.stringValue = "识别中：\(partial)"
            }, onFinished: { [weak self] result in
                self?.handleResult(result, target: sentence.text)
            })
        } catch {
            isRecording = false
            recordButton.title = "按住录音"
            transcriptLabel.stringValue = "麦克风启动失败，请检查音频设备"
        }
    }

    // MARK: - 评分展示

    private func handleResult(_ result: Result<(text: String, duration: TimeInterval), SpeechRecognitionError>,
                              target: String) {
        isRecording = false
        recordButton.title = "按住录音"
        switch result {
        case .failure(let error):
            transcriptLabel.stringValue = error.errorDescription ?? "识别失败，请重试"
        case .success(let output):
            let score = scorer.score(target: target, recognized: output.text, duration: output.duration)
            showScore(score, recognized: output.text, target: target)
            persistScore(score)
        }
    }

    private func showScore(_ result: PronunciationResult, recognized: String, target: String) {
        scoreLabel.stringValue = "\(result.accuracyPercent) 分"
        scoreLabel.textColor = color(for: result.level)
        levelLabel.stringValue = "\(result.level.displayName) · 语速 \(result.wpm) WPM"
        let missed = result.missedWords.isEmpty ? "无" : result.missedWords.joined(separator: ", ")
        detailLabel.stringValue = "漏读/读错：\(missed)\n识别内容：\(recognized.isEmpty ? "（未识别到语音）" : recognized)"
        transcriptLabel.stringValue = "目标句：\(target)"
    }

    private func persistScore(_ result: PronunciationResult) {
        guard let sentence = sentences[safe: index] else { return }
        let grade: ReviewGrade
        switch result.accuracyPercent {
        case 90...100: grade = .easy
        case 60..<90: grade = .good
        case 30..<60: grade = .hard
        default: grade = .again
        }
        state?.recordPractice(id: sentence.id, kind: .speaking, grade: grade)
        state?.store.recordToday(action: { stat in
            stat.spoken += 1
            stat.pronunciationScoreSum += result.accuracyPercent
            stat.pronunciationCount += 1
        }, now: Date())
    }

    private func color(for level: PronunciationLevel) -> NSColor {
        switch level {
        case .excellent: return Theme.success
        case .good: return Theme.info
        case .fair: return Theme.warning
        case .poor: return Theme.danger
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
