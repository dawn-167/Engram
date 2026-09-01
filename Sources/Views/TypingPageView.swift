import Cocoa

// MARK: - 单词打字页（复刻 qwerty 打字功能）
// 顶部栏：白卡（词库/章节/发音 + qwerty SVG 图标 + Start）
// 中间：单词大字逐字母着色 + 音标 + 释义 +「按任意键开始」遮罩
// 底部：进度条 + 五项实时统计；整章完成出结果面板（时间/WPM/正确率 + 错词 + 再来一组）

/// 文字菜单按钮（无边框无背景，点击弹出 NSMenu，对齐 qwerty 文字导航项）
private final class TextMenuButton: NSButton {
    var items: [String] = []
    var values: [Any?] = []
    var onPick: ((Int) -> Void)?
    private var isHovered = false

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        focusRingType = .none
        font = .systemFont(ofSize: 15, weight: .medium)
        alignment = .center
        contentTintColor = .labelColor
        wantsLayer = true
        layer?.cornerRadius = 4
        target = self
        action = #selector(showMenu)
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未使用") }

    @objc private func showMenu() {
        guard !items.isEmpty else { return }
        let menu = NSMenu()
        for (index, title) in items.enumerated() {
            let item = NSMenuItem(title: title, action: #selector(picked(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 6), in: self)
    }

    @objc private func picked(_ sender: NSMenuItem) {
        let index = sender.tag
        guard items.indices.contains(index) else { return }
        title = items[index]
        onPick?(index)
    }

    private func updateAppearance() {
        layer?.backgroundColor = isHovered ? NSColor.black.withAlphaComponent(0.05).cgColor : .clear
        contentTintColor = isHovered ? Theme.primary : .labelColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSCursor.pointingHand.push()
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSCursor.pop()
        updateAppearance()
    }
}

/// 工具栏图标按钮（qwerty 原版 SVG，模板着色：激活=星云紫、关闭=灰；加载失败回退 SF Symbol）
private final class ToolbarIconButton: NSButton {
    private var isHovered = false
    private let activeTint: NSColor
    private let inactiveTint: NSColor
    private var activeState: Bool

    init(iconName: String, fallbackSymbol: String, tooltip: String, active: Bool) {
        self.activeTint = Theme.primary
        self.inactiveTint = Theme.textSecondary
        self.activeState = active
        super.init(frame: .zero)
        image = Self.loadToolbarIcon(iconName) ?? NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: tooltip)
        image?.isTemplate = true
        imagePosition = .imageOnly
        isBordered = false
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 5
        self.toolTip = tooltip
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未使用") }

    private static func loadToolbarIcon(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "icons"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    /// 切换图标与激活态（释义/循环/深色等开关用）
    func setIcon(_ iconName: String?, fallbackSymbol: String, active: Bool) {
        activeState = active
        if let iconName, let image = Self.loadToolbarIcon(iconName) {
            self.image = image
        } else {
            self.image = NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: toolTip)
        }
        image?.isTemplate = true
        updateAppearance()
    }

    func setActive(_ active: Bool) {
        activeState = active
        updateAppearance()
    }

    private func updateAppearance() {
        layer?.backgroundColor = isHovered ? Theme.primary.withAlphaComponent(0.10).cgColor : .clear
        contentTintColor = isHovered ? Theme.primary : (activeState ? activeTint : inactiveTint)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSCursor.pointingHand.push()
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSCursor.pop()
        updateAppearance()
    }
}

/// 轻量音效管理器（qwerty 按键音/正确音/错误音，用 macOS 系统音，零资源）
private final class SoundManager {
    static let shared = SoundManager()
    var enabled = true
    private let keySound = NSSound(named: .init("Tink"))
    private let correctSound = NSSound(named: .init("Glass"))
    private let wrongSound = NSSound(named: .init("Basso"))
    private let completeSound = NSSound(named: .init("Hero"))

    func playKey() { if enabled { keySound?.play() } }
    func playCorrect() { if enabled { correctSound?.play() } }
    func playWrong() { if enabled { wrongSound?.play() } }
    func playComplete() { if enabled { completeSound?.play() } }
}

/// 默写模式（qwerty eye 图标）：隐藏单词的全部/元音/辅音/随机，边听边默写
private enum DictationMode: Int, CaseIterable {
    case off = 0
    case hideAll
    case hideVowels
    case hideConsonants
    case randomHide

    var label: String {
        switch self {
        case .off: return "默写：关闭"
        case .hideAll: return "默写：隐藏全部"
        case .hideVowels: return "默写：隐藏元音"
        case .hideConsonants: return "默写：隐藏辅音"
        case .randomHide: return "默写：随机隐藏"
        }
    }

    func next() -> DictationMode {
        DictationMode(rawValue: (rawValue + 1) % DictationMode.allCases.count) ?? .off
    }

    /// 判断某个字符是否应被隐藏（返回 true 表示显示为占位符）
    func shouldHide(_ char: Character, at index: Int, total: Int) -> Bool {
        switch self {
        case .off: return false
        case .hideAll: return true
        case .hideVowels: return "aeiouAEIOU".contains(char)
        case .hideConsonants: return !"aeiouAEIOU".contains(char) && char.isLetter
        case .randomHide: return (index * 7 + 3) % 3 == 0 // 伪随机，固定种子保证同一单词一致
        }
    }
}

final class TypingPageView: NSView {

    // MARK: - 属性

    private weak var state: AppState?
    /// 页面内跳转（统计图标等）
    var onNavigate: ((AppPage) -> Void)?
    private let service = TypingService()
    private var sessionWords: [WordEntry] = []
    private var wrongFlash = false
    private var hasStartedTyping = false
    private var sessionStart = Date()
    private var ticker: Timer?
    private var wrongWords: [String] = []
    private var wrongWordSet: Set<String> = []
    /// 释义显示开关（qwerty language 图标）
    private var translationVisible = true
    /// 默写模式（qwerty eye 图标）
    private var dictationMode: DictationMode = .off
    /// 音效开关（qwerty speaker 图标）
    private var soundEnabled = true

    // 顶部栏
    private let deckText = TextMenuButton(title: "")
    private let chapterText = TextMenuButton(title: "")
    private let accentText = TextMenuButton(title: "美音")
    private let toolbarCard = CardView()
    private var iconButtons: [ToolbarIconButton] = []
    private let skipButton: NSButton
    private let startButton: NSButton

    // 中间界面
    private let wordLabel = NSTextField(labelWithString: "")
    private let phoneticLabel = LabelFactory.label("", font: .systemFont(ofSize: 14), color: Theme.textSecondary, align: .center)
    private let translationLabel = LabelFactory.label("", font: .systemFont(ofSize: 18), color: Theme.textPrimary, align: .center)
    private let hintLabel = LabelFactory.label("", font: .systemFont(ofSize: 11), color: Theme.textSecondary, align: .center)
    private let overlayView = NSVisualEffectView()
    private let overlayLabel = LabelFactory.label("按任意键开始", font: .systemFont(ofSize: 20), color: Theme.textPrimary, align: .center)
    /// 当前发音口音（美音 en-US / 英音 en-GB / 关闭=空串）
    private var accentLocale = "en-US"

    // 底部进度与统计
    private let progressBar = ProgressBar()
    private let statCard = CardView()
    private let statTime = LabelFactory.label("00:00", font: .monospacedDigitSystemFont(ofSize: 20, weight: .bold), color: Theme.textSecondary, align: .center)
    private let statInput = LabelFactory.label("0", font: .monospacedDigitSystemFont(ofSize: 20, weight: .bold), color: Theme.textSecondary, align: .center)
    private let statWPM = LabelFactory.label("0", font: .monospacedDigitSystemFont(ofSize: 20, weight: .bold), color: Theme.textSecondary, align: .center)
    private let statCorrect = LabelFactory.label("0", font: .monospacedDigitSystemFont(ofSize: 20, weight: .bold), color: Theme.textSecondary, align: .center)
    private let statAcc = LabelFactory.label("100%", font: .monospacedDigitSystemFont(ofSize: 20, weight: .bold), color: Theme.textSecondary, align: .center)

    // 结束面板
    private let dimView = NSView()
    private let resultCard = CardView()

    private let keyboardCatcher = KeyboardCatcher()

    /// 每章单词数（对齐 qwerty 章节切分口径）
    private static let wordsPerChapter = 20
    /// 词典固定宽度基准（5 字）
    private static let deckFixedTitle = "四级核心词"
    /// 章节固定宽度基准（两位数）
    private static let chapterFixedTitle = "第 10 章"

    // MARK: - 布局常量

    private static let barHeight: CGFloat = 44
    private static let cardPadding: CGFloat = 12
    private static let textGap: CGFloat = 12
    private static let iconGap: CGFloat = 4
    private static let textToIconsGap: CGFloat = 16
    private static let iconsToStartGap: CGFloat = 12
    private static let iconSize: CGFloat = 22
    private static let startWidth: CGFloat = 64
    private static let skipWidth: CGFloat = 52
    private static let iconsToSkipGap: CGFloat = 8
    private static let skipToStartGap: CGFloat = 8

    // MARK: - 初始化

    init(state: AppState) {
        self.state = state
        startButton = ButtonFactory.primary("开始", target: nil, action: #selector(TypingPageView.startTapped))
        skipButton = ButtonFactory.ghost("跳过", target: nil, action: #selector(TypingPageView.skipTapped))
        super.init(frame: .zero)
        startButton.target = self
        skipButton.target = self
        keyboardCatcher.onKey = { [weak self] char in self?.handleKey(char) }
        setupLayout()
        populateDecks()
        populateChapters()
        layoutToolbar()
        startSession()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未使用") }
    override var isFlipped: Bool { true }
    deinit { ticker?.invalidate() }

    /// 页面出现时夺回键盘焦点
    func activate() {
        window?.makeFirstResponder(keyboardCatcher)
    }

    // MARK: - 布局

    private func setupLayout() {
        // 顶部栏
        deckText.onPick = { [weak self] _ in
            self?.populateChapters()
            self?.layoutToolbar()
            self?.startSession()
        }
        chapterText.onPick = { [weak self] _ in
            self?.layoutToolbar()
            self?.startSession()
        }
        accentText.onPick = { [weak self] index in
            guard let self = self else { return }
            self.accentLocale = [0: "en-US", 1: "en-GB", 2: ""][index] ?? "en-US"
            self.layoutToolbar()
        }
        accentText.items = ["美音", "英音", "关闭发音"]

        addSubview(toolbarCard)
        toolbarCard.autoresizingMask = [.maxYMargin]
        toolbarCard.addSubview(deckText)
        toolbarCard.addSubview(chapterText)
        toolbarCard.addSubview(accentText)

        let icons: [(String, String, String, Bool)] = [
            ("heroicons_speaker-wave-solid", "speaker.wave.2.fill", "音效设置", true),
            ("tabler_repeat-off", "repeat", "单词循环", false),
            ("heroicons_eye-slash-solid", "eye.slash.fill", "默写模式", false),
            ("tabler_language", "textformat.size", "释义显示", true),
            ("bxs_book", "book.fill", "错题本", true),
            ("heroicons_chart-pie-solid", "chart.pie.fill", "数据统计", true),
            ("heroicons_sun-solid", "sun.max.fill", "深色模式", true),
            ("ic_round-keyboard", "keyboard.fill", "指法图示", true),
            ("heroicons_cog-6-tooth-solid", "gearshape.fill", "设置", true),
        ]
        for (iconName, fallback, tooltip, active) in icons {
            let button = ToolbarIconButton(iconName: iconName, fallbackSymbol: fallback, tooltip: tooltip, active: active)
            button.target = self
            button.action = #selector(iconTapped(_:))
            toolbarCard.addSubview(button)
            iconButtons.append(button)
        }
        toolbarCard.addSubview(skipButton)
        toolbarCard.addSubview(startButton)

        // 中间界面
        wordLabel.alignment = .center
        wordLabel.wantsLayer = true
        wordLabel.font = .monospacedSystemFont(ofSize: 48, weight: .regular)
        addSubview(wordLabel)
        addSubview(phoneticLabel)
        addSubview(translationLabel)
        addSubview(hintLabel)

        // 毛玻璃遮罩：铺满整页（无边框），材质与窗口背景一致，工具栏/统计浮在其上
        overlayView.material = .popover
        overlayView.blendingMode = .withinWindow
        overlayView.state = .active
        overlayView.wantsLayer = true
        overlayView.layer?.cornerRadius = 0
        overlayView.addSubview(overlayLabel)
        addSubview(overlayView)
        // 工具栏和底部统计必须在遮罩之上
        addSubview(toolbarCard, positioned: .above, relativeTo: overlayView)
        addSubview(progressBar, positioned: .above, relativeTo: overlayView)
        addSubview(statCard, positioned: .above, relativeTo: overlayView)

        // 底部
        addSubview(progressBar)
        progressBar.setProgress(0)

        addSubview(statCard)
        let captions = [("时间", statTime), ("输入数", statInput), ("WPM", statWPM), ("正确数", statCorrect), ("正确率", statAcc)]
        captions.enumerated().forEach { index, pair in
            let caption = LabelFactory.label(pair.0, font: .systemFont(ofSize: 11), color: Theme.textSecondary.withAlphaComponent(0.85), align: .center)
            let line = NSView()
            line.wantsLayer = true
            line.layer = CALayer()
            line.layer?.backgroundColor = Theme.divider.cgColor
            statCard.addSubview(pair.1); statCard.addSubview(caption); statCard.addSubview(line)
            pair.1.frame = CGRect(x: CGFloat(index) * 112 + 16, y: 16, width: 80, height: 28)
            line.frame = CGRect(x: CGFloat(index) * 112 + 24, y: 48, width: 64, height: 1)
            caption.frame = CGRect(x: CGFloat(index) * 112, y: 58, width: 112, height: 16)
        }

        // 结束面板
        dimView.wantsLayer = true
        dimView.layer = CALayer()
        dimView.layer?.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(white: 0.10, alpha: 0.75)
                : NSColor(white: 0.82, alpha: 0.75)
        }.cgColor
        addSubview(dimView)
        dimView.isHidden = true
        addSubview(resultCard)
        resultCard.isHidden = true

        // 键盘捕获
        addSubview(keyboardCatcher)
        keyboardCatcher.autoresizingMask = [.width, .height]
    }

    /// 页面高度变化时自适应重排：顶栏固定、单词区垂直居中、底部贴底
    override func layout() {
        super.layout()
        let h = bounds.height
        guard h > 0 else { return }

        keyboardCatcher.frame = bounds

        let bottomGap: CGFloat = 12
        let progressH: CGFloat = 8
        let cardH: CGFloat = 92
        let gap: CGFloat = 8
        statCard.frame = CGRect(x: 68, y: h - bottomGap - cardH, width: 560, height: cardH)
        progressBar.frame = CGRect(x: 238, y: h - bottomGap - cardH - gap - progressH, width: 220, height: progressH)

        let topEdge: CGFloat = 8 + Self.barHeight + 16
        let zoneBottom = h - bottomGap - cardH - gap - progressH - gap
        let zoneH = max(zoneBottom - topEdge, 200)
        let blockH: CGFloat = 90 + 10 + 22 + 8 + 28 + 6 + 16
        var y = topEdge + (zoneH - blockH) / 2
        wordLabel.frame = CGRect(x: 48, y: y, width: 600, height: 90)
        y += 90 + 10
        phoneticLabel.frame = CGRect(x: 60, y: y, width: 576, height: 22)
        y += 22 + 8
        translationLabel.frame = CGRect(x: 60, y: y, width: 576, height: 28)
        y += 28 + 6
        hintLabel.frame = CGRect(x: 60, y: y, width: 576, height: 16)

        // 遮罩铺满整页，无边框；"按任意键开始"文字定位到单词区中心
        overlayView.frame = bounds
        overlayLabel.frame = CGRect(x: 0, y: topEdge + (zoneH - 36) / 2, width: 696, height: 36)

        dimView.frame = bounds
        resultCard.frame = CGRect(x: 108, y: max((h - 400) / 2, 60), width: 480, height: 400)
    }

    /// 白框宽度按内容自适应并水平居中（词典/章节固定宽度，发音自适应）
    private func layoutToolbar() {
        let deckW = Self.textWidth(Self.deckFixedTitle) + 4
        let chapterW = Self.textWidth(Self.chapterFixedTitle) + 4
        let accentW = Self.textWidth(accentText.title) + 4
        let iconsW = CGFloat(iconButtons.count) * Self.iconSize
            + CGFloat(max(iconButtons.count - 1, 0)) * Self.iconGap

        let contentW = deckW + Self.textGap + chapterW + Self.textGap + accentW
            + Self.textToIconsGap + iconsW + Self.iconsToSkipGap + Self.skipWidth
            + Self.skipToStartGap + Self.startWidth
        let cardW = contentW + Self.cardPadding * 2
        let cardX = (696 - cardW) / 2

        toolbarCard.frame = CGRect(x: cardX, y: 8, width: cardW, height: Self.barHeight)

        var x = Self.cardPadding
        deckText.frame = CGRect(x: x, y: 8, width: deckW, height: 28)
        x += deckW + Self.textGap
        chapterText.frame = CGRect(x: x, y: 8, width: chapterW, height: 28)
        x += chapterW + Self.textGap
        accentText.frame = CGRect(x: x, y: 8, width: accentW, height: 28)
        x += accentW + Self.textToIconsGap
        for (index, button) in iconButtons.enumerated() {
            button.frame = CGRect(x: x, y: 11, width: Self.iconSize, height: Self.iconSize)
            x += Self.iconSize + (index < iconButtons.count - 1 ? Self.iconGap : Self.iconsToSkipGap)
        }
        skipButton.frame = CGRect(x: x, y: 8, width: Self.skipWidth, height: 28)
        x += Self.skipWidth + Self.skipToStartGap
        startButton.frame = CGRect(x: x, y: 8, width: Self.startWidth, height: 28)
    }

    private static func textWidth(_ text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 15, weight: .medium)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    // MARK: - 会话控制

    private func populateDecks() {
        let decks = state?.library.wordDecks ?? []
        deckText.items = decks.map { $0.name }
        deckText.values = decks.map { $0.id as Any? }
        deckText.title = decks.first?.name ?? ""
    }

    private func populateChapters() {
        guard let deckId = selectedDeckId(), let count = state?.library.words(in: deckId).count, count > 0 else {
            chapterText.items = ["第 1 章"]
            chapterText.title = "第 1 章"
            return
        }
        let chapterCount = max(1, Int(ceil(Double(count) / Double(Self.wordsPerChapter))))
        chapterText.items = (1...chapterCount).map { "第 \($0) 章" }
        chapterText.title = "第 1 章"
    }

    private func selectedDeckId() -> String? {
        guard let index = deckText.items.firstIndex(of: deckText.title) else { return nil }
        return deckText.values[index] as? String
    }

    /// 当前章节的单词组（每章 20 词）
    private func chapterWords() -> [WordEntry] {
        guard let deckId = selectedDeckId(), let words = state?.library.words(in: deckId), !words.isEmpty else { return [] }
        let digits = chapterText.title.filter { $0.isNumber }
        let chapterIndex = max(0, (Int(digits) ?? 1) - 1)
        let start = chapterIndex * Self.wordsPerChapter
        guard start < words.count else { return Array(words.prefix(Self.wordsPerChapter)) }
        let end = min(start + Self.wordsPerChapter, words.count)
        return Array(words[start..<end])
    }

    @objc private func startTapped() { startSession() }

    @objc private func skipTapped() { skipCurrentWord() }

    // MARK: - 工具栏图标功能

    @objc private func iconTapped(_ sender: NSButton) {
        guard let index = iconButtons.firstIndex(where: { $0 === sender }) else { return }
        switch index {
        case 0: toggleSound()             // 音效
        case 1: cycleLoopTimes()          // 循环
        case 2: cycleDictation()          // 默写
        case 3: toggleTranslation()       // 释义显示
        case 4: showErrorBook(sender)     // 错题本
        case 5: onNavigate?(.stats)       // 数据统计
        case 6: toggleDarkMode()          // 深色模式
        case 7: showKeyboardGuide(sender) // 指法图示
        case 8: showSettings(sender)      // 设置
        default: break
        }
    }

    // MARK: - 音效开关

    private func toggleSound() {
        soundEnabled.toggle()
        SoundManager.shared.enabled = soundEnabled
        iconButtons[0].setActive(soundEnabled)
        iconButtons[0].toolTip = soundEnabled ? "音效：开" : "音效：关"
    }

    // MARK: - 默写模式

    private func cycleDictation() {
        dictationMode = dictationMode.next()
        let isOff = dictationMode == .off
        iconButtons[2].setIcon(isOff ? "heroicons_eye-slash-solid" : "heroicons_eye-solid",
                               fallbackSymbol: isOff ? "eye.slash.fill" : "eye.fill",
                               active: !isOff)
        iconButtons[2].toolTip = dictationMode.label
        render()
    }

    /// 单词循环：1 → 3 → 5 → 8 → ∞ → 1
    private func cycleLoopTimes() {
        let options = [1, 3, 5, 8, Int.max]
        let next = options.first { $0 > service.loopTimes } ?? options[0]
        service.loopTimes = next
        let infinite = next == Int.max
        iconButtons[1].setIcon(infinite || next > 1 ? "tabler_repeat" : "tabler_repeat-off",
                               fallbackSymbol: "repeat", active: next > 1)
        iconButtons[1].toolTip = infinite ? "单词循环：无限次" : "单词循环 ×\(next)"
    }

    /// 释义显示开关（qwerty language 图标）
    private func toggleTranslation() {
        translationVisible.toggle()
        translationLabel.isHidden = !translationVisible
        iconButtons[3].setIcon(translationVisible ? "tabler_language" : "tabler_language-off",
                               fallbackSymbol: "textformat.size", active: translationVisible)
    }

    // MARK: - 错题本弹窗

    private func showErrorBook(_ sender: NSButton) {
        let popover = NSPopover()
        popover.behavior = .transient
        let content = NSViewController()
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 280))
        content.view = view

        let title = LabelFactory.label("错题本", font: Theme.titleFont(16))
        title.frame = CGRect(x: 16, y: 248, width: 200, height: 22)
        view.addSubview(title)

        if wrongWords.isEmpty {
            let empty = LabelFactory.label("暂无错词，继续保持！", font: .systemFont(ofSize: 13),
                                           color: Theme.textSecondary, align: .center)
            empty.frame = CGRect(x: 0, y: 120, width: 320, height: 20)
            view.addSubview(empty)
        } else {
            let scroll = NSScrollView(frame: CGRect(x: 16, y: 16, width: 288, height: 220))
            scroll.hasVerticalScroller = true
            scroll.borderType = .noBorder
            scroll.drawsBackground = false
            let doc = NSView(frame: CGRect(x: 0, y: 0, width: 272, height: max(CGFloat(wrongWords.count) * 32, 220)))
            for (i, word) in wrongWords.enumerated() {
                let row = NSView()
                row.wantsLayer = true
                row.layer = CALayer()
                row.layer?.backgroundColor = Theme.danger.withAlphaComponent(0.08).cgColor
                row.layer?.cornerRadius = 6
                row.frame = CGRect(x: 0, y: CGFloat(wrongWords.count - 1 - i) * 32 + 4, width: 272, height: 26)
                let label = LabelFactory.label(word, font: .monospacedSystemFont(ofSize: 14, weight: .medium),
                                               color: Theme.danger)
                label.frame = CGRect(x: 12, y: 4, width: 200, height: 18)
                row.addSubview(label)
                doc.addSubview(row)
            }
            scroll.documentView = doc
            view.addSubview(scroll)
        }
        popover.contentViewController = content
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    // MARK: - 指法图示弹窗

    private func showKeyboardGuide(_ sender: NSButton) {
        let popover = NSPopover()
        popover.behavior = .transient
        let content = NSViewController()
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 360, height: 260))
        content.view = view

        let title = LabelFactory.label("推荐指法", font: Theme.titleFont(16))
        title.frame = CGRect(x: 16, y: 228, width: 200, height: 22)
        view.addSubview(title)

        let rows = [
            ("左手小指", "` 1 Q A Z"),
            ("左手无名指", "2 W S X"),
            ("左手中指", "3 E D C"),
            ("左手食指", "4 5 R T F G V B"),
            ("右手食指", "6 7 Y U H J N M"),
            ("右手中指", "8 I K ,"),
            ("右手无名指", "9 O L ."),
            ("右手小指", "0 - = P [ ] ; ' /"),
        ]
        for (i, row) in rows.enumerated() {
            let y = 200 - CGFloat(i) * 24
            let finger = LabelFactory.label(row.0, font: .systemFont(ofSize: 11, weight: .semibold),
                                            color: Theme.primary)
            finger.frame = CGRect(x: 16, y: y, width: 80, height: 18)
            let keys = LabelFactory.label(row.1, font: .monospacedSystemFont(ofSize: 11, weight: .regular),
                                          color: Theme.textSecondary)
            keys.frame = CGRect(x: 100, y: y, width: 250, height: 18)
            view.addSubview(finger); view.addSubview(keys)
        }
        popover.contentViewController = content
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    // MARK: - 设置弹窗

    private func showSettings(_ sender: NSButton) {
        let popover = NSPopover()
        popover.behavior = .transient
        let content = NSViewController()
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 280, height: 200))
        content.view = view

        let title = LabelFactory.label("设置", font: Theme.titleFont(16))
        title.frame = CGRect(x: 16, y: 168, width: 200, height: 22)
        view.addSubview(title)

        // 音效开关
        let soundBtn = NSButton(checkboxWithTitle: "按键音效", target: self, action: #selector(settingsSoundToggle(_:)))
        soundBtn.state = soundEnabled ? .on : .off
        soundBtn.frame = CGRect(x: 16, y: 136, width: 200, height: 22)
        view.addSubview(soundBtn)

        // 释义默认显示
        let transBtn = NSButton(checkboxWithTitle: "默认显示释义", target: self, action: #selector(settingsTransToggle(_:)))
        transBtn.state = translationVisible ? .on : .off
        transBtn.frame = CGRect(x: 16, y: 108, width: 200, height: 22)
        view.addSubview(transBtn)

        // 每章词数
        let countLabel = LabelFactory.label("每章单词数：\(Self.wordsPerChapter)", font: .systemFont(ofSize: 12),
                                            color: Theme.textSecondary)
        countLabel.frame = CGRect(x: 16, y: 76, width: 200, height: 18)
        view.addSubview(countLabel)

        let hint = LabelFactory.label("快捷键：Enter 开始 ｜ Tab 跳过 ｜ Ctrl+V 默写", font: .systemFont(ofSize: 10),
                                      color: Theme.textTertiary)
        hint.frame = CGRect(x: 16, y: 16, width: 250, height: 36)
        hint.cell?.wraps = true
        view.addSubview(hint)

        popover.contentViewController = content
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    @objc private func settingsSoundToggle(_ sender: NSButton) {
        soundEnabled = sender.state == .on
        SoundManager.shared.enabled = soundEnabled
        iconButtons[0].setActive(soundEnabled)
    }

    @objc private func settingsTransToggle(_ sender: NSButton) {
        translationVisible = sender.state == .on
        translationLabel.isHidden = !translationVisible
        iconButtons[3].setActive(translationVisible)
    }

    /// 深色模式开关（qwerty sun/moon 图标）
    private func toggleDarkMode() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        NSApp.appearance = isDark ? NSAppearance(named: .aqua) : NSAppearance(named: .darkAqua)
        iconButtons[6].setIcon(isDark ? "heroicons_sun-solid" : "heroicons_moon-solid",
                               fallbackSymbol: isDark ? "sun.max.fill" : "moon.fill", active: true)
    }

    private func startSession() {
        let words = chapterWords()
        guard !words.isEmpty else { return }
        sessionWords = words
        service.startSession(words: words)
        hasStartedTyping = false
        sessionStart = Date()
        wrongWords.removeAll()
        wrongWordSet.removeAll()
        resultCard.isHidden = true
        dimView.isHidden = true
        stopTicker()
        render()
        activate()
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.resultCard.isHidden { self.render() }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: - 输入处理

    private func handleKey(_ char: Character) {
        if !resultCard.isHidden { startSession(); return }
        if char == "\t" { skipCurrentWord(); return }
        if !hasStartedTyping {
            hasStartedTyping = true
            sessionStart = Date()  // 第一次按键才开始计时（qwerty 行为）
            startTicker()
            guard char.isLetter else { render(); return }
        }
        guard char.isLetter else { return }
        let feedback = service.input(character: char)
        switch feedback {
        case .accepted:
            SoundManager.shared.playKey()
            render()
        case .wrongAndReset:
            SoundManager.shared.playWrong()
            if let word = service.currentWord { recordWrongWord(word.text) }
            animateWrongShake()
            wrongFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                self?.wrongFlash = false
                self?.render()
            }
            render()
        case .wordCompleted:
            SoundManager.shared.playCorrect()
            onWordCompleted()
        case .wordRepeated:
            SoundManager.shared.playKey()
            render()
        case .sessionFinished:
            SoundManager.shared.playComplete()
            onWordCompleted()
            finishSession()
        }
    }

    private func skipCurrentWord() {
        if let word = service.currentWord { recordWrongWord(word.text) }
        let feedback = service.skipCurrent()
        if feedback == .sessionFinished { finishSession() } else { render() }
    }

    private func recordWrongWord(_ text: String) {
        guard !wrongWordSet.contains(text) else { return }
        wrongWordSet.insert(text)
        wrongWords.append(text)
    }

    /// Qwerty 同款：输错时单词左右抖动
    private func animateWrongShake() {
        guard let layer = wordLabel.layer else { return }
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = [0, -4, 4, -6, 6, -4, 4, 0]
        shake.duration = 0.45
        layer.add(shake, forKey: "typingWrongShake")
    }

    private func onWordCompleted() {
        // TypingService 完成后已前进，completedWords 即刚完成单词的序号（从 1 起）
        let done = service.stats.completedWords
        let target = sessionWords[max(0, done - 1)]
        state?.recordPractice(id: target.id, kind: .word, grade: .good)
        state?.store.recordToday(action: { $0.wordsTyped += 1 }, now: Date())
        state?.speech.speak(target.text, rate: 0.5, locale: accentLocale)
        render()
    }

    private func finishSession() {
        stopTicker()
        let s = service.stats
        state?.store.recordToday(action: { stat in
            stat.keyPressCorrect += s.correctKeyPresses
            stat.keyPressTotal += s.totalKeyPresses
        }, now: Date())
        let elapsed = max(Date().timeIntervalSince(sessionStart), 1)
        let minutes = elapsed / 60
        let wpm = Int((Double(s.correctKeyPresses) / 5.0 / minutes).rounded())
        let acc = Int((s.accuracy * 100).rounded())
        resultCard.subviews.forEach { $0.removeFromSuperview() }
        buildResultContent(wpm: wpm, acc: acc, elapsed: elapsed)
        dimView.isHidden = false
        resultCard.isHidden = false
    }

    // MARK: - 渲染

    private func render() {
        guard let word = service.currentWord else { return }
        let s = service.stats
        let elapsed = max(Date().timeIntervalSince(sessionStart), 0)
        let minutes = elapsed / 60
        let wpm = minutes > 0 ? Int((Double(s.correctKeyPresses) / 5.0 / minutes).rounded()) : 0
        translationLabel.stringValue = word.translation
        phoneticLabel.stringValue = word.phonetic
        statTime.stringValue = Self.timeString(elapsed)
        statInput.stringValue = "\(s.totalKeyPresses)"
        statWPM.stringValue = "\(wpm)"
        statCorrect.stringValue = "\(s.correctKeyPresses)"
        statAcc.stringValue = "\(Int((s.accuracy * 100).rounded()))%"
        progressBar.setProgress(service.progress)
        wordLabel.attributedStringValue = renderWordText(word.text)
        hintLabel.stringValue = wrongFlash ? "输入错误，本词需要重新输入" : (hasStartedTyping ? "错一个字母就要重来" : "")
        overlayView.isHidden = hasStartedTyping || !resultCard.isHidden
    }

    private func renderWordText(_ text: String) -> NSAttributedString {
        let states = service.charStates()
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let font = NSFont.monospacedSystemFont(ofSize: 48, weight: .regular)
        let result = NSMutableAttributedString()
        for (index, char) in text.enumerated() {
            let state = states.indices.contains(index) ? states[index] : .pending
            // 默写模式：未输入的字符显示为下划线占位，已输入的正常显示
            let isHidden = dictationMode.shouldHide(char, at: index, total: text.count)
                && state != .correct
            let displayChar = isHidden ? "＿" : String(char)
            let color: NSColor
            if wrongFlash { color = Theme.danger }
            else if isHidden { color = Theme.textTertiary }
            else {
                switch state {
                case .correct: color = Theme.success
                case .wrong: color = Theme.danger
                case .pending: color = Theme.textSecondary
                }
            }
            result.append(NSAttributedString(string: displayChar,
                                             attributes: [.font: font,
                                                          .foregroundColor: color,
                                                          .kern: 1.5,
                                                          .paragraphStyle: para]))
        }
        return result
    }

    // MARK: - 结束面板（简化版 ResultScreen：统计 + 错词 + 再来一组）

    private func buildResultContent(wpm: Int, acc: Int, elapsed: TimeInterval) {
        let title = LabelFactory.label("本组完成！", font: Theme.titleFont(22), align: .center)
        resultCard.addSubview(title)
        title.frame = CGRect(x: 0, y: 330, width: 480, height: 32)

        let cols = [("时间", Self.timeString(elapsed)), ("WPM", "\(wpm)"), ("正确率", "\(acc)%")]
        cols.enumerated().forEach { index, col in
            let value = LabelFactory.label(col.1, font: .monospacedDigitSystemFont(ofSize: 26, weight: .bold), color: Theme.textPrimary, align: .center)
            let caption = LabelFactory.label(col.0, font: .systemFont(ofSize: 12), color: Theme.textSecondary, align: .center)
            resultCard.addSubview(value); resultCard.addSubview(caption)
            let x = 60 + CGFloat(index) * 120
            value.frame = CGRect(x: x, y: 256, width: 120, height: 32)
            caption.frame = CGRect(x: x, y: 230, width: 120, height: 16)
        }

        if wrongWords.isEmpty {
            let praise = LabelFactory.label("全部正确，非常棒！", font: .systemFont(ofSize: 14), color: Theme.success, align: .center)
            resultCard.addSubview(praise)
            praise.frame = CGRect(x: 0, y: 190, width: 480, height: 20)
        } else {
            let caption = LabelFactory.label("错词（\(wrongWords.count)）", font: .systemFont(ofSize: 12), color: Theme.textSecondary, align: .center)
            resultCard.addSubview(caption)
            caption.frame = CGRect(x: 0, y: 208, width: 480, height: 16)
            addWrongWordChips(to: resultCard, words: wrongWords)
        }

        let again = ButtonFactory.primary("再来一组", target: self, action: #selector(startTapped))
        resultCard.addSubview(again)
        again.frame = CGRect(x: 170, y: 40, width: 140, height: 40)
    }

    private func addWrongWordChips(to card: NSView, words: [String]) {
        let chips = Array(words.prefix(9))
        var x: CGFloat = 40
        var y: CGFloat = 172
        let rowMax: CGFloat = 440
        for word in chips {
            let label = LabelFactory.label(word, font: .systemFont(ofSize: 12), color: Theme.danger)
            label.sizeToFit()
            let chip = NSView()
            chip.wantsLayer = true
            chip.layer = CALayer()
            chip.layer?.cornerRadius = 10
            chip.layer?.backgroundColor = Theme.danger.withAlphaComponent(0.12).cgColor
            chip.addSubview(label)
            let w = label.bounds.width + 24
            if x + w > rowMax { x = 40; y -= 34 }
            chip.frame = CGRect(x: x, y: y, width: w, height: 26)
            label.frame = CGRect(x: 12, y: 5, width: label.bounds.width, height: 16)
            card.addSubview(chip)
            x += w + 8
        }
    }

    private static func timeString(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
