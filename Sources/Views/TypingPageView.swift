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
    var selectedIndex: Int = 0

    init(title: String, tooltip: String = "") {
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        focusRingType = .none
        font = .systemFont(ofSize: 15, weight: .medium)
        alignment = .center
        contentTintColor = .labelColor
        wantsLayer = true
        layer?.cornerRadius = 6
        self.toolTip = tooltip
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
            item.state = (index == selectedIndex) ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 6), in: self)
    }

    @objc private func picked(_ sender: NSMenuItem) {
        let index = sender.tag
        guard items.indices.contains(index) else { return }
        selectedIndex = index
        title = items[index]
        onPick?(index)
    }

    private func updateAppearance() {
        // qwerty 悬停：紫底白字
        layer?.backgroundColor = isHovered ? Theme.primary.cgColor : .clear
        contentTintColor = isHovered ? .white : .labelColor
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
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

/// 工具栏图标按钮（qwerty 原版 SVG，模板着色：激活=星云紫、关闭=灰；加载失败回退 SF Symbol）
private final class ToolbarIconButton: NSButton {
    private var isHovered = false
    private let activeTint: NSColor
    private let inactiveTint: NSColor
    private var activeState: Bool

    init(iconName: String, fallbackSymbol: String, tooltip: String, active: Bool) {
        // qwerty 图标色调：indigo-500 (#6366f1)
        self.activeTint = NSColor(red: 0.388, green: 0.400, blue: 0.945, alpha: 1.0)
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
        layer?.backgroundColor = isHovered ? activeTint.withAlphaComponent(0.10).cgColor : .clear
        contentTintColor = isHovered ? activeTint : (activeState ? activeTint : inactiveTint)
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
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

/// 轻量音效管理器（qwerty 按键音/效果音，用 macOS 系统音，零资源）
private final class SoundManager {
    static let shared = SoundManager()
    var keySoundEnabled = true
    var hintSoundEnabled = true
    private let keySound = NSSound(named: .init("Tink"))
    private let correctSound = NSSound(named: .init("Glass"))
    private let wrongSound = NSSound(named: .init("Basso"))
    private let completeSound = NSSound(named: .init("Hero"))

    func playKey() { if keySoundEnabled { keySound?.play() } }
    func playCorrect() { if hintSoundEnabled { correctSound?.play() } }
    func playWrong() { if hintSoundEnabled { wrongSound?.play() } }
    func playComplete() { if hintSoundEnabled { completeSound?.play() } }
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
    /// 音标显示开关（qwerty 发音面板）
    private var phoneticVisible = true
    /// 释义发音开关（qwerty 发音面板）
    private var transPronunciationEnabled = false
    /// 循环发音开关（qwerty 发音面板）
    private var loopPronunciationEnabled = false
    /// 暂停状态（qwerty Pause）
    private var isPaused = false
    /// 暂停前累计已用时间（暂停/恢复计时用）
    private var accumulatedElapsed: TimeInterval = 0

    // 顶部栏
    private let deckText = TextMenuButton(title: "")
    private let chapterText = TextMenuButton(title: "")
    private let pronunciationButton: HandCursorButton
    private let toolbarCard = CardView()
    private var iconButtons: [ToolbarIconButton] = []
    private let startButton: NSButton
    /// 当前弹出的 Popover（统一管理，修复关闭后无法再次打开的 bug）
    private var currentPopover: NSPopover?

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

    // MARK: - 初始化

    init(state: AppState) {
        self.state = state
        startButton = ButtonFactory.primary("Start", target: nil, action: #selector(TypingPageView.startTapped))
        pronunciationButton = HandCursorButton(title: "美音", target: nil, action: #selector(TypingPageView.showPronunciationPanel(_:)))
        pronunciationButton.isBordered = false
        pronunciationButton.focusRingType = .none
        pronunciationButton.font = .systemFont(ofSize: 15, weight: .medium)
        pronunciationButton.contentTintColor = .labelColor
        pronunciationButton.wantsLayer = true
        pronunciationButton.layer?.cornerRadius = 4
        super.init(frame: .zero)
        startButton.target = self
        pronunciationButton.target = self
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
        deckText.toolTip = "词库切换"
        deckText.onPick = { [weak self] idx in
            self?.deckText.selectedIndex = idx
            self?.populateChapters()
            self?.layoutToolbar()
            self?.startSession()
        }
        chapterText.toolTip = "章节切换"
        chapterText.onPick = { [weak self] idx in
            self?.chapterText.selectedIndex = idx
            self?.layoutToolbar()
            self?.startSession()
        }
        // 发音按钮：点击弹出面板（音标/发音/口音设置）
        pronunciationButton.toolTip = "发音及音标设置"

        addSubview(toolbarCard)
        toolbarCard.autoresizingMask = [.maxYMargin]
        toolbarCard.addSubview(deckText)
        toolbarCard.addSubview(chapterText)
        toolbarCard.addSubview(pronunciationButton)

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
        toolbarCard.addSubview(startButton)

        // 中间界面
        wordLabel.alignment = .center
        wordLabel.wantsLayer = true
        wordLabel.font = .monospacedSystemFont(ofSize: 48, weight: .regular)
        addSubview(wordLabel)
        addSubview(phoneticLabel)
        addSubview(translationLabel)
        addSubview(hintLabel)

        // 毛玻璃：仅覆盖单词区，模糊背后的单词/音标/释义，"按任意键开始"文字清晰浮于其上
        // 用渐变 mask 让上下边缘柔和过渡，看不出方框边界（对齐 qwerty backdrop-blur）
        overlayView.material = .popover
        overlayView.blendingMode = .withinWindow
        overlayView.state = .active
        overlayView.wantsLayer = true
        overlayView.layer?.cornerRadius = 0
        overlayView.addSubview(overlayLabel)
        addSubview(overlayView)

        // 离开窗口/页面时自动暂停（qwerty 行为）
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] _ in
            self?.pauseIfNeeded()
        }

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
        let wordBlockTop = topEdge + (zoneH - blockH) / 2
        var y = wordBlockTop
        wordLabel.frame = CGRect(x: 48, y: y, width: 600, height: 90)
        y += 90 + 10
        phoneticLabel.frame = CGRect(x: 60, y: y, width: 576, height: 22)
        y += 22 + 8
        translationLabel.frame = CGRect(x: 60, y: y, width: 576, height: 28)
        y += 28 + 6
        hintLabel.frame = CGRect(x: 60, y: y, width: 576, height: 16)

        // 毛玻璃覆盖整个单词区（单词+音标+释义+提示），上下各留 24pt 缓冲
        let blurTop = max(wordBlockTop - 24, topEdge)
        let blurBottom = min(y + 16 + 24, zoneBottom)
        overlayView.frame = CGRect(x: 0, y: blurTop, width: 696, height: blurBottom - blurTop)
        // 渐变 mask：上下边缘透明→中间不透明，消除模糊硬边界
        let mask = CAGradientLayer()
        mask.frame = overlayView.bounds
        mask.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        mask.locations = [0, 0.12, 0.88, 1]
        mask.startPoint = CGPoint(x: 0.5, y: 0)
        mask.endPoint = CGPoint(x: 0.5, y: 1)
        overlayView.layer?.mask = mask
        // "按任意键开始/继续"文字定位到单词区偏下（qwerty 样式：模糊单词下方）
        overlayLabel.frame = CGRect(x: 0, y: (blurBottom - blurTop) * 0.62, width: 696, height: 36)

        dimView.frame = bounds
        resultCard.frame = CGRect(x: 108, y: max((h - 400) / 2, 60), width: 480, height: 400)
    }

    /// 白框宽度按内容自适应并水平居中（词典/章节固定宽度，发音自适应）
    private func layoutToolbar() {
        let deckW = Self.textWidth(Self.deckFixedTitle) + 4
        let chapterW = Self.textWidth(Self.chapterFixedTitle) + 4
        let accentW = Self.textWidth(pronunciationButton.title) + 4
        let iconsW = CGFloat(iconButtons.count) * Self.iconSize
            + CGFloat(max(iconButtons.count - 1, 0)) * Self.iconGap

        let contentW = deckW + Self.textGap + chapterW + Self.textGap + accentW
            + Self.textToIconsGap + iconsW + Self.iconsToStartGap + Self.startWidth
        let cardW = contentW + Self.cardPadding * 2
        let cardX = (696 - cardW) / 2

        toolbarCard.frame = CGRect(x: cardX, y: 8, width: cardW, height: Self.barHeight)

        var x = Self.cardPadding
        deckText.frame = CGRect(x: x, y: 8, width: deckW, height: 28)
        x += deckW + Self.textGap
        chapterText.frame = CGRect(x: x, y: 8, width: chapterW, height: 28)
        x += chapterW + Self.textGap
        pronunciationButton.frame = CGRect(x: x, y: 8, width: accentW, height: 28)
        x += accentW + Self.textToIconsGap
        for (index, button) in iconButtons.enumerated() {
            button.frame = CGRect(x: x, y: 11, width: Self.iconSize, height: Self.iconSize)
            x += Self.iconSize + (index < iconButtons.count - 1 ? Self.iconGap : Self.iconsToStartGap)
        }
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
        deckText.selectedIndex = 0
    }

    private func populateChapters() {
        guard let deckId = selectedDeckId(), let count = state?.library.words(in: deckId).count, count > 0 else {
            chapterText.items = ["第 1 章"]
            chapterText.title = "第 1 章"
            chapterText.selectedIndex = 0
            return
        }
        let chapterCount = max(1, Int(ceil(Double(count) / Double(Self.wordsPerChapter))))
        chapterText.items = (1...chapterCount).map { "第 \($0) 章" }
        chapterText.title = "第 1 章"
        chapterText.selectedIndex = 0
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

    @objc private func startTapped() {
        if !hasStartedTyping {
            // 未开始：Start 按钮 = 开始会话（重置后开始）
            startSession()
            hasStartedTyping = true
            sessionStart = Date()
            accumulatedElapsed = 0
            isPaused = false
            startTicker()
            updateStartButton()
            render()
        } else if isPaused {
            // 暂停中：恢复
            resumeSession()
        } else {
            // 进行中：暂停
            pauseSession()
        }
    }

    /// 暂停：停止计时、显示模糊遮罩、按钮变 Pause
    private func pauseSession() {
        guard hasStartedTyping && !isPaused else { return }
        isPaused = true
        accumulatedElapsed += Date().timeIntervalSince(sessionStart)
        stopTicker()
        overlayLabel.stringValue = "按任意键继续"
        overlayView.isHidden = false
        updateStartButton()
    }

    /// 恢复：继续计时、隐藏遮罩、按钮变回 Start（进行中显示 Pause）
    private func resumeSession() {
        guard hasStartedTyping && isPaused else { return }
        isPaused = false
        sessionStart = Date()
        startTicker()
        overlayView.isHidden = true
        overlayLabel.stringValue = "按任意键开始"
        updateStartButton()
        render()
    }

    /// 离开页面/窗口失焦时自动暂停（供 RootViewController 调用）
    func pauseIfNeeded() {
        if hasStartedTyping && !isPaused && resultCard.isHidden {
            pauseSession()
        }
    }

    /// 离开页面时自动暂停（view 从 window 移除）
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { pauseIfNeeded() }
    }

    /// 更新 Start/Pause 按钮外观：进行中=灰色 Pause，未开始/暂停=紫色 Start
    private func updateStartButton() {
        if hasStartedTyping && !isPaused {
            startButton.title = "Pause"
            startButton.layer?.backgroundColor = Theme.textSecondary.withAlphaComponent(0.4).cgColor
        } else {
            startButton.title = "Start"
            startButton.layer?.backgroundColor = Theme.primary.cgColor
        }
    }

    // MARK: - 工具栏图标功能

    @objc private func iconTapped(_ sender: NSButton) {
        guard let index = iconButtons.firstIndex(where: { $0 === sender }) else { return }
        switch index {
        case 0: showSoundPanel(sender)         // 音效（面板：按键音+效果音）
        case 1: showLoopPanel(sender)          // 循环（面板：1/3/5/8/∞ 单选）
        case 2: showDictationPanel(sender)     // 默写（面板：开关+模式）
        case 3: toggleTranslation()            // 释义显示（toggle）
        case 4: showErrorBook(sender)          // 错题本
        case 5: onNavigate?(.stats)            // 数据统计
        case 6: toggleDarkMode()               // 深色模式
        case 7: showKeyboardGuide(sender)      // 指法图示
        case 8: showSettings(sender)           // 设置
        default: break
        }
    }

    // MARK: - 通用：干净样式的下拉按钮（NSButton+NSMenu，替代 NSPopUpButton）

    /// 自定义下拉按钮：白色圆角 + 文字左 + chevron 右，点击弹出独立 NSMenu（带勾选）
    private class DropdownButton: NSView {
        private let titleLabel = NSTextField(labelWithString: "")
        private let chevron = NSImageView()
        private let bg = NSView()
        var items: [String]
        var selectedIndex: Int
        var onPick: ((Int) -> Void)?

        init(items: [String], selectedIndex: Int, onPick: @escaping (Int) -> Void) {
            self.items = items
            self.selectedIndex = selectedIndex
            self.onPick = onPick
            super.init(frame: .zero)
            wantsLayer = true

            bg.wantsLayer = true
            bg.layer?.cornerRadius = 6
            bg.layer?.borderWidth = 1
            bg.layer?.borderColor = Theme.divider.cgColor
            bg.layer?.shadowColor = NSColor.black.cgColor
            bg.layer?.shadowOpacity = 0.08
            bg.layer?.shadowRadius = 4
            bg.layer?.shadowOffset = CGSize(width: 0, height: 1)
            bg.layer?.backgroundColor = NSColor(name: nil) { app in
                app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    ? NSColor(white: 0.22, alpha: 1)
                    : NSColor(white: 0.97, alpha: 1)
            }.cgColor
            addSubview(bg)

            titleLabel.stringValue = items.indices.contains(selectedIndex) ? items[selectedIndex] : ""
            titleLabel.font = .systemFont(ofSize: 13, weight: .regular)
            titleLabel.textColor = Theme.textPrimary
            titleLabel.drawsBackground = false
            titleLabel.isBezeled = false
            titleLabel.isEditable = false
            titleLabel.cell?.usesSingleLineMode = true
            titleLabel.cell?.lineBreakMode = .byTruncatingTail
            addSubview(titleLabel)

            chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
            chevron.contentTintColor = Theme.textSecondary
            chevron.imageScaling = .scaleProportionallyUpOrDown
            addSubview(chevron)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            bg.frame = bounds
            titleLabel.frame = CGRect(x: 10, y: (bounds.height - 18) / 2,
                                      width: bounds.width - 36, height: 18)
            chevron.frame = CGRect(x: bounds.width - 22, y: (bounds.height - 10) / 2,
                                   width: 12, height: 10)
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .pointingHand)
        }

        override func mouseDown(with event: NSEvent) {
            showMenu()
        }

        private func showMenu() {
            let menu = NSMenu()
            menu.autoenablesItems = false
            for (i, item) in items.enumerated() {
                let mi = NSMenuItem(title: item, action: #selector(menuPicked(_:)), keyEquivalent: "")
                mi.target = self
                mi.tag = i
                mi.state = (i == selectedIndex) ? .on : .off
                menu.addItem(mi)
            }
            // 弹出位置：按钮左下角下方 2pt，转屏幕坐标
            let windowPt = convert(NSPoint(x: 0, y: -2), to: nil)
            let screenPt = window?.convertPoint(toScreen: windowPt) ?? windowPt
            menu.popUp(positioning: nil, at: screenPt, in: nil)
        }

        @objc private func menuPicked(_ sender: NSMenuItem) {
            selectedIndex = sender.tag
            titleLabel.stringValue = items[selectedIndex]
            onPick?(selectedIndex)
        }
    }

    private func makeCleanDropdown(frame: CGRect, items: [String], selectedIndex: Int,
                                   onPick: @escaping (Int) -> Void) -> DropdownButton {
        let btn = DropdownButton(items: items, selectedIndex: selectedIndex, onPick: onPick)
        btn.frame = frame
        return btn
    }

    /// 统一弹出 Popover：先关闭上一个，再显示新的（修复关闭后无法再次打开的 bug）
    private func presentPopover(_ popover: NSPopover, sender: NSButton) {
        currentPopover?.close()
        currentPopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    // MARK: - 音效面板（qwerty SoundSwitcher：按键音 + 效果音）

    private func showSoundPanel(_ sender: NSButton) {
        let popover = NSPopover()
        popover.behavior = .transient
        let content = NSViewController()
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 240, height: 130))
        content.view = view

        // 按键音
        let keyLabel = LabelFactory.label("开关按键音", font: .systemFont(ofSize: 13, weight: .medium))
        keyLabel.frame = CGRect(x: 16, y: 96, width: 100, height: 18)
        view.addSubview(keyLabel)
        let keySwitch = NSSwitch()
        keySwitch.state = SoundManager.shared.keySoundEnabled ? .on : .off
        keySwitch.frame = CGRect(x: 16, y: 70, width: 40, height: 22)
        keySwitch.target = self
        keySwitch.action = #selector(soundKeyToggle(_:))
        view.addSubview(keySwitch)
        let keyStatus = LabelFactory.label(SoundManager.shared.keySoundEnabled ? "发音已开启" : "发音已关闭",
                                           font: .systemFont(ofSize: 11), color: Theme.textSecondary, align: .right)
        keyStatus.frame = CGRect(x: 150, y: 72, width: 74, height: 18)
        keyStatus.tag = 101
        view.addSubview(keyStatus)

        // 效果音
        let hintLabel = LabelFactory.label("开关效果音", font: .systemFont(ofSize: 13, weight: .medium))
        hintLabel.frame = CGRect(x: 16, y: 44, width: 100, height: 18)
        view.addSubview(hintLabel)
        let hintSwitch = NSSwitch()
        hintSwitch.state = SoundManager.shared.hintSoundEnabled ? .on : .off
        hintSwitch.frame = CGRect(x: 16, y: 18, width: 40, height: 22)
        hintSwitch.target = self
        hintSwitch.action = #selector(soundHintToggle(_:))
        view.addSubview(hintSwitch)
        let hintStatus = LabelFactory.label(SoundManager.shared.hintSoundEnabled ? "发音已开启" : "发音已关闭",
                                            font: .systemFont(ofSize: 11), color: Theme.textSecondary, align: .right)
        hintStatus.frame = CGRect(x: 150, y: 20, width: 74, height: 18)
        hintStatus.tag = 102
        view.addSubview(hintStatus)

        popover.contentViewController = content
        presentPopover(popover, sender: sender)
    }

    @objc private func soundKeyToggle(_ sender: NSSwitch) {
        SoundManager.shared.keySoundEnabled = sender.state == .on
        iconButtons[0].setActive(SoundManager.shared.keySoundEnabled || SoundManager.shared.hintSoundEnabled)
        if let status = sender.superview?.viewWithTag(101) as? NSTextField {
            status.stringValue = sender.state == .on ? "发音已开启" : "发音已关闭"
        }
    }

    @objc private func soundHintToggle(_ sender: NSSwitch) {
        SoundManager.shared.hintSoundEnabled = sender.state == .on
        iconButtons[0].setActive(SoundManager.shared.keySoundEnabled || SoundManager.shared.hintSoundEnabled)
        if let status = sender.superview?.viewWithTag(102) as? NSTextField {
            status.stringValue = sender.state == .on ? "发音已开启" : "发音已关闭"
        }
    }

    // MARK: - 默写模式下拉面板（qwerty WordDictationSwitcher）

    private func showDictationPanel(_ sender: NSButton) {
        let isOn = dictationMode != .off
        let viewH: CGFloat = isOn ? 130 : 70
        let popover = NSPopover()
        popover.behavior = .transient
        let content = NSViewController()
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 240, height: viewH))
        content.view = view

        // 开关
        let toggle = NSSwitch()
        toggle.state = isOn ? .on : .off
        toggle.frame = CGRect(x: 16, y: viewH - 52, width: 40, height: 22)
        toggle.target = self
        toggle.action = #selector(dictationToggleChanged(_:))
        view.addSubview(toggle)

        let toggleLabel = LabelFactory.label("开关默写模式", font: .systemFont(ofSize: 13, weight: .medium))
        toggleLabel.frame = CGRect(x: 64, y: viewH - 50, width: 100, height: 18)
        view.addSubview(toggleLabel)

        let statusLabel = LabelFactory.label(isOn ? "默写已开启" : "默写已关闭",
                                             font: .systemFont(ofSize: 11), color: Theme.textSecondary, align: .right)
        statusLabel.frame = CGRect(x: 160, y: viewH - 50, width: 64, height: 18)
        view.addSubview(statusLabel)

        // 模式选择（仅开启时显示）
        if isOn {
            let modeLabel = LabelFactory.label("默写模式", font: .systemFont(ofSize: 12), color: Theme.textSecondary)
            modeLabel.frame = CGRect(x: 16, y: 58, width: 80, height: 18)
            view.addSubview(modeLabel)

            let modeMap: [DictationMode] = [.hideAll, .hideVowels, .hideConsonants, .randomHide]
            let selectedIdx = modeMap.firstIndex(of: dictationMode) ?? 0
            let popup = makeCleanDropdown(
                frame: CGRect(x: 16, y: 24, width: 208, height: 28),
                items: ["全部隐藏", "隐藏元音", "隐藏辅音", "随机隐藏"],
                selectedIndex: selectedIdx
            ) { [weak self] idx in
                let modes: [DictationMode] = [.hideAll, .hideVowels, .hideConsonants, .randomHide]
                self?.dictationMode = modes[idx]
                self?.updateDictationIcon()
                self?.render()
            }
            view.addSubview(popup)
        }

        popover.contentViewController = content
        presentPopover(popover, sender: sender)
    }

    @objc private func dictationToggleChanged(_ sender: NSSwitch) {
        if sender.state == .on {
            if dictationMode == .off { dictationMode = .hideAll }
        } else {
            dictationMode = .off
        }
        updateDictationIcon()
        render()
        // 切换开关时重建面板（显示/隐藏模式选择）
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            currentPopover?.close()
            if self.iconButtons.count > 2 {
                self.showDictationPanel(self.iconButtons[2])
            }
        }
    }

    private func updateDictationIcon() {
        let isOff = dictationMode == .off
        iconButtons[2].setIcon(isOff ? "heroicons_eye-slash-solid" : "heroicons_eye-solid",
                               fallbackSymbol: isOff ? "eye.slash.fill" : "eye.fill",
                               active: !isOff)
        iconButtons[2].toolTip = isOff ? "默写：关闭" : "默写模式"
    }

    // MARK: - 循环面板（qwerty LoopWordSwitcher：1/3/5/8/∞ 单选）

    private func showLoopPanel(_ sender: NSButton) {
        let popover = NSPopover()
        popover.behavior = .transient
        let content = NSViewController()
        let options: [Int] = [1, 3, 5, 8, Int.max]
        let labels = ["1", "3", "5", "8", "无限"]
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 240, height: CGFloat(30 + options.count * 32)))
        content.view = view

        let title = LabelFactory.label("选择单词的循环次数", font: .systemFont(ofSize: 13, weight: .medium))
        title.frame = CGRect(x: 16, y: view.frame.height - 28, width: 200, height: 18)
        view.addSubview(title)

        for (i, opt) in options.enumerated() {
            let y = view.frame.height - 60 - CGFloat(i) * 32
            let radio = NSButton(radioButtonWithTitle: labels[i], target: self, action: #selector(loopOptionSelected(_:)))
            radio.tag = opt
            radio.state = service.loopTimes == opt ? .on : .off
            radio.frame = CGRect(x: 16, y: y, width: 200, height: 22)
            radio.font = .systemFont(ofSize: 14)
            view.addSubview(radio)
        }

        popover.contentViewController = content
        presentPopover(popover, sender: sender)
    }

    @objc private func loopOptionSelected(_ sender: NSButton) {
        let times = sender.tag
        service.loopTimes = times
        updateLoopIcon()
        currentPopover?.close()
    }

    /// 更新循环图标：1=repeat-off(灰)，其他=repeat+数字角标(紫)
    private func updateLoopIcon() {
        let times = service.loopTimes
        let isOff = times == 1
        iconButtons[1].setIcon(isOff ? "tabler_repeat-off" : "tabler_repeat",
                               fallbackSymbol: "repeat", active: !isOff)
        iconButtons[1].toolTip = isOff ? "单词循环：关闭" : (times == Int.max ? "单词循环：无限" : "单词循环 ×\(times)")
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
        presentPopover(popover, sender: sender)
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
        presentPopover(popover, sender: sender)
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

        // 按键音开关
        let soundBtn = NSButton(checkboxWithTitle: "按键音效", target: self, action: #selector(settingsSoundToggle(_:)))
        soundBtn.state = SoundManager.shared.keySoundEnabled ? .on : .off
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

        let hint = LabelFactory.label("快捷键：Enter 开始/暂停 ｜ Tab 跳过 ｜ 任意键恢复", font: .systemFont(ofSize: 10),
                                      color: Theme.textTertiary)
        hint.frame = CGRect(x: 16, y: 16, width: 250, height: 36)
        hint.cell?.wraps = true
        view.addSubview(hint)

        popover.contentViewController = content
        presentPopover(popover, sender: sender)
    }

    @objc private func settingsSoundToggle(_ sender: NSButton) {
        let on = sender.state == .on
        SoundManager.shared.keySoundEnabled = on
        SoundManager.shared.hintSoundEnabled = on
        iconButtons[0].setActive(on)
    }

    @objc private func settingsTransToggle(_ sender: NSButton) {
        translationVisible = sender.state == .on
        translationLabel.isHidden = !translationVisible
        iconButtons[3].setActive(translationVisible)
    }

    // MARK: - 发音面板（qwerty PronunciationSwitcher：音标+单词发音+释义发音+循环发音+口音）

    @objc private func showPronunciationPanel(_ sender: NSButton) {
        let pronOn = !accentLocale.isEmpty
        let viewH: CGFloat = pronOn ? 310 : 150
        let popover = NSPopover()
        popover.behavior = .transient
        let content = NSViewController()
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 240, height: viewH))
        content.view = view

        var y = viewH - 30

        // 音标显示
        let phoneticLabel = LabelFactory.label("开关音标显示", font: .systemFont(ofSize: 13, weight: .medium))
        phoneticLabel.frame = CGRect(x: 16, y: y, width: 120, height: 18)
        view.addSubview(phoneticLabel)
        y -= 28
        let phoneticSwitch = NSSwitch()
        phoneticSwitch.state = phoneticVisible ? .on : .off
        phoneticSwitch.frame = CGRect(x: 16, y: y, width: 40, height: 22)
        phoneticSwitch.target = self
        phoneticSwitch.action = #selector(pronPhoneticToggle(_:))
        view.addSubview(phoneticSwitch)
        let phoneticStatus = LabelFactory.label(phoneticVisible ? "音标已开启" : "音标已关闭",
                                                font: .systemFont(ofSize: 11), color: Theme.textSecondary, align: .right)
        phoneticStatus.frame = CGRect(x: 150, y: y + 2, width: 74, height: 18)
        phoneticStatus.tag = 201
        view.addSubview(phoneticStatus)
        y -= 34

        // 单词发音
        let wordPronLabel = LabelFactory.label("开关单词发音", font: .systemFont(ofSize: 13, weight: .medium))
        wordPronLabel.frame = CGRect(x: 16, y: y, width: 120, height: 18)
        view.addSubview(wordPronLabel)
        y -= 28
        let wordPronSwitch = NSSwitch()
        wordPronSwitch.state = pronOn ? .on : .off
        wordPronSwitch.frame = CGRect(x: 16, y: y, width: 40, height: 22)
        wordPronSwitch.target = self
        wordPronSwitch.action = #selector(pronWordToggle(_:))
        view.addSubview(wordPronSwitch)
        let wordPronStatus = LabelFactory.label(pronOn ? "发音已开启" : "发音已关闭",
                                                font: .systemFont(ofSize: 11), color: Theme.textSecondary, align: .right)
        wordPronStatus.frame = CGRect(x: 150, y: y + 2, width: 74, height: 18)
        wordPronStatus.tag = 202
        view.addSubview(wordPronStatus)

        if pronOn {
            y -= 34
            // 释义发音
            let transPronLabel = LabelFactory.label("开关释义发音", font: .systemFont(ofSize: 13, weight: .medium))
            transPronLabel.frame = CGRect(x: 16, y: y, width: 120, height: 18)
            view.addSubview(transPronLabel)
            y -= 28
            let transPronSwitch = NSSwitch()
            transPronSwitch.state = transPronunciationEnabled ? .on : .off
            transPronSwitch.frame = CGRect(x: 16, y: y, width: 40, height: 22)
            transPronSwitch.target = self
            transPronSwitch.action = #selector(pronTransToggle(_:))
            view.addSubview(transPronSwitch)
            let transPronStatus = LabelFactory.label(transPronunciationEnabled ? "发音已开启" : "发音已关闭",
                                                    font: .systemFont(ofSize: 11), color: Theme.textSecondary, align: .right)
            transPronStatus.frame = CGRect(x: 150, y: y + 2, width: 74, height: 18)
            transPronStatus.tag = 203
            view.addSubview(transPronStatus)

            y -= 34
            // 循环发音
            let loopPronLabel = LabelFactory.label("开关循环发音", font: .systemFont(ofSize: 13, weight: .medium))
            loopPronLabel.frame = CGRect(x: 16, y: y, width: 120, height: 18)
            view.addSubview(loopPronLabel)
            y -= 28
            let loopPronSwitch = NSSwitch()
            loopPronSwitch.state = loopPronunciationEnabled ? .on : .off
            loopPronSwitch.frame = CGRect(x: 16, y: y, width: 40, height: 22)
            loopPronSwitch.target = self
            loopPronSwitch.action = #selector(pronLoopToggle(_:))
            view.addSubview(loopPronSwitch)
            let loopPronStatus = LabelFactory.label(loopPronunciationEnabled ? "循环已开启" : "循环已关闭",
                                                    font: .systemFont(ofSize: 11), color: Theme.textSecondary, align: .right)
            loopPronStatus.frame = CGRect(x: 150, y: y + 2, width: 74, height: 18)
            loopPronStatus.tag = 204
            view.addSubview(loopPronStatus)

            y -= 34
            // 口音选择
            let accentLabel = LabelFactory.label("单词发音口音", font: .systemFont(ofSize: 13, weight: .medium))
            accentLabel.frame = CGRect(x: 16, y: y, width: 120, height: 18)
            view.addSubview(accentLabel)
            y -= 30
            let accentPopup = makeCleanDropdown(
                frame: CGRect(x: 16, y: y, width: 208, height: 28),
                items: ["美音", "英音"],
                selectedIndex: accentLocale == "en-GB" ? 1 : 0
            ) { [weak self] idx in
                guard let self = self else { return }
                self.accentLocale = idx == 1 ? "en-GB" : "en-US"
                self.pronunciationButton.title = idx == 1 ? "英音" : "美音"
                self.layoutToolbar()
            }
            view.addSubview(accentPopup)
        }

        popover.contentViewController = content
        presentPopover(popover, sender: sender)
    }

    @objc private func pronPhoneticToggle(_ sender: NSSwitch) {
        phoneticVisible = sender.state == .on
        phoneticLabel.isHidden = !phoneticVisible
        if let status = sender.superview?.viewWithTag(201) as? NSTextField {
            status.stringValue = phoneticVisible ? "音标已开启" : "音标已关闭"
        }
    }

    @objc private func pronWordToggle(_ sender: NSSwitch) {
        let isOn = sender.state == .on
        accentLocale = isOn ? "en-US" : ""
        pronunciationButton.title = isOn ? (accentLocale == "en-GB" ? "英音" : "美音") : "关闭"
        layoutToolbar()
        if let status = sender.superview?.viewWithTag(202) as? NSTextField {
            status.stringValue = isOn ? "发音已开启" : "发音已关闭"
        }
        // 切换单词发音开关时重建面板（显示/隐藏下方选项）
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            currentPopover?.close()
            self.showPronunciationPanel(self.pronunciationButton)
        }
    }

    @objc private func pronTransToggle(_ sender: NSSwitch) {
        transPronunciationEnabled = sender.state == .on
        if let status = sender.superview?.viewWithTag(203) as? NSTextField {
            status.stringValue = transPronunciationEnabled ? "发音已开启" : "发音已关闭"
        }
    }

    @objc private func pronLoopToggle(_ sender: NSSwitch) {
        loopPronunciationEnabled = sender.state == .on
        if let status = sender.superview?.viewWithTag(204) as? NSTextField {
            status.stringValue = loopPronunciationEnabled ? "循环已开启" : "循环已关闭"
        }
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
        isPaused = false
        accumulatedElapsed = 0
        sessionStart = Date()
        wrongWords.removeAll()
        wrongWordSet.removeAll()
        resultCard.isHidden = true
        dimView.isHidden = true
        stopTicker()
        overlayLabel.stringValue = "按任意键开始"
        updateStartButton()
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
        if !resultCard.isHidden {
            // 结束面板：任意键开始新一组
            startSession()
            hasStartedTyping = true
            sessionStart = Date()
            accumulatedElapsed = 0
            isPaused = false
            startTicker()
            updateStartButton()
            render()
            return
        }
        // Enter 键：开始/暂停切换（qwerty 行为）
        if char == "\r" || char == "\n" {
            startTapped()
            return
        }
        // 暂停中：任意字母键恢复
        if isPaused {
            resumeSession()
            guard char.isLetter else { return }
        }
        if char == "\t" { skipCurrentWord(); return }
        if !hasStartedTyping {
            hasStartedTyping = true
            sessionStart = Date()
            accumulatedElapsed = 0
            startTicker()
            updateStartButton()
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
        if !accentLocale.isEmpty {
            state?.speech.speak(target.text, rate: 0.5, locale: accentLocale)
            // 释义发音：单词朗读后读中文释义
            if transPronunciationEnabled {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    guard let self = self, self.transPronunciationEnabled else { return }
                    self.state?.speech.speak(target.translation, rate: 0.5, locale: "zh-CN")
                }
            }
        }
        render()
    }

    private func finishSession() {
        stopTicker()
        let s = service.stats
        state?.store.recordToday(action: { stat in
            stat.keyPressCorrect += s.correctKeyPresses
            stat.keyPressTotal += s.totalKeyPresses
        }, now: Date())
        // 最终用时 = 累计 + 当前段
        let currentSegment = hasStartedTyping ? Date().timeIntervalSince(sessionStart) : 0
        let elapsed = max(accumulatedElapsed + currentSegment, 1)
        let minutes = elapsed / 60
        let wpm = Int((Double(s.correctKeyPresses) / 5.0 / minutes).rounded())
        let acc = Int((s.accuracy * 100).rounded())
        hasStartedTyping = false
        isPaused = false
        updateStartButton()
        resultCard.subviews.forEach { $0.removeFromSuperview() }
        buildResultContent(wpm: wpm, acc: acc, elapsed: elapsed)
        dimView.isHidden = false
        resultCard.isHidden = false
    }

    // MARK: - 渲染

    private func render() {
        guard let word = service.currentWord else { return }
        let s = service.stats
        // 累计时间 = 暂停前累计 + 当前活跃段（暂停时不加）
        let currentSegment = (hasStartedTyping && !isPaused) ? Date().timeIntervalSince(sessionStart) : 0
        let elapsed = accumulatedElapsed + currentSegment
        let minutes = elapsed / 60
        let wpm = minutes > 0 ? Int((Double(s.correctKeyPresses) / 5.0 / minutes).rounded()) : 0
        translationLabel.stringValue = word.translation
        phoneticLabel.stringValue = word.phonetic
        phoneticLabel.isHidden = !phoneticVisible
        statTime.stringValue = Self.timeString(elapsed)
        statInput.stringValue = "\(s.totalKeyPresses)"
        statWPM.stringValue = "\(wpm)"
        statCorrect.stringValue = "\(s.correctKeyPresses)"
        statAcc.stringValue = "\(Int((s.accuracy * 100).rounded()))%"
        progressBar.setProgress(service.progress)
        wordLabel.attributedStringValue = renderWordText(word.text)
        hintLabel.stringValue = wrongFlash ? "输入错误，本词需要重新输入" : (hasStartedTyping ? "错一个字母就要重来" : "")
        // 遮罩：未开始 或 暂停时显示；进行中或结束时隐藏
        overlayView.isHidden = (hasStartedTyping && !isPaused) || !resultCard.isHidden
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
