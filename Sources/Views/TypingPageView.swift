import Cocoa
import AVFoundation

// MARK: - 单词打字页（复刻 qwerty 打字功能）
// 顶部栏：白卡（词库/章节/发音 + qwerty SVG 图标 + Start）
// 中间：单词大字逐字母着色 + 音标 + 释义 +「按任意键开始」遮罩
// 底部：进度条 + 五项实时统计；整章完成出结果面板（时间/WPM/正确率 + 错词 + 再来一组）

/// Qwerty 风格 tooltip：白底圆角阴影、文字垂直居中
private final class TooltipView: NSView {
    init(text: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = Theme.divider.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.12
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: 2)

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .black.withAlphaComponent(0.85)
        label.alignment = .center
        label.drawsBackground = false
        label.isBezeled = false
        label.sizeToFit()
        let padX: CGFloat = 14
        let h: CGFloat = 26
        let w = label.bounds.width + padX
        setFrameSize(NSSize(width: w, height: h))
        label.frame = CGRect(x: padX / 2, y: (h - label.bounds.height) / 2,
                             width: w - padX, height: label.bounds.height)
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// 自定义白色下拉菜单窗口（替代 NSMenu，纯白背景+圆角+悬停高亮）
private final class DropdownMenuWindow: NSWindow {
    private let onPick: (Int) -> Void
    private var hoveredRow: Int = -1

    init(items: [String], selectedIndex: Int, at point: NSPoint, minWidth: CGFloat, onPick: @escaping (Int) -> Void) {
        self.onPick = onPick
        let rowH: CGFloat = 32
        // 根据最长文字计算宽度
        let font = NSFont.systemFont(ofSize: 14)
        let textWidth = items.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 100
        let w = max(minWidth, textWidth + 60)
        let h = CGFloat(items.count) * rowH + 8
        super.init(contentRect: NSRect(x: point.x, y: point.y - h, width: w, height: h),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        level = .popUpMenu

        let container = NSView(frame: NSRect(x: 0, y: 0, width: frame.width, height: h))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.white.cgColor
        container.layer?.cornerRadius = 8
        container.layer?.masksToBounds = true
        container.layer?.borderColor = NSColor.black.withAlphaComponent(0.08).cgColor
        container.layer?.borderWidth = 1
        contentView = container

        for (i, title) in items.enumerated() {
            let row = NSButton(frame: NSRect(x: 4, y: h - 4 - CGFloat(i + 1) * rowH, width: frame.width - 8, height: rowH))
            row.title = ""
            row.isBordered = false
            row.tag = i
            row.target = self
            row.action = #selector(rowClicked(_:))
            row.wantsLayer = true
            row.layer?.cornerRadius = 5
            row.layer?.backgroundColor = (i == selectedIndex) ? NSColor.systemBlue.withAlphaComponent(0.1).cgColor : .clear

            let check = NSTextField(labelWithString: i == selectedIndex ? "✓" : "")
            check.frame = CGRect(x: 10, y: 6, width: 20, height: 20)
            check.font = .systemFont(ofSize: 14, weight: .bold)
            check.textColor = .systemBlue
            check.alignment = .center
            row.addSubview(check)

            let label = NSTextField(labelWithString: title)
            label.frame = CGRect(x: 34, y: 6, width: row.bounds.width - 44, height: 20)
            label.font = .systemFont(ofSize: 14)
            label.textColor = .labelColor
            row.addSubview(label)

            container.addSubview(row)
        }
    }

    @objc private func rowClicked(_ sender: NSButton) {
        onPick(sender.tag)
        close()
    }

    override func close() {
        super.close()
    }
}

/// 文字菜单按钮（无边框无背景，点击弹出自定义白色下拉，对齐 qwerty 文字导航项）
private final class TextMenuButton: NSButton {
    var items: [String] = []
    var values: [Any?] = []
    var onPick: ((Int) -> Void)?
    private var isHovered = false
    var selectedIndex: Int = 0
    private var hoverTA: NSTrackingArea?
    private var tooltipTag: NSView?
    private let tipText: String
    private var dropdownWindow: DropdownMenuWindow?
    private var dropdownMonitor: Any?
    private static var currentDropdown: TextMenuButton?

    init(title: String, tooltip: String = "") {
        self.tipText = tooltip
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        focusRingType = .none
        font = .systemFont(ofSize: 15, weight: .medium)
        alignment = .center
        contentTintColor = .labelColor
        wantsLayer = true
        layer?.cornerRadius = 6
        target = self
        action = #selector(showMenu)
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未使用") }

    @objc private func showMenu() {
        guard !items.isEmpty else { return }
        if dropdownWindow != nil {
            closeDropdown()
            return
        }
        // 关闭其他已打开的下拉
        Self.currentDropdown?.closeDropdown()
        Self.currentDropdown = self

        let windowPt = convert(NSPoint(x: -4, y: bounds.height + 6), to: nil)
        let screenPt = window?.convertPoint(toScreen: windowPt) ?? windowPt
        let w = DropdownMenuWindow(items: items, selectedIndex: selectedIndex, at: screenPt, minWidth: bounds.width + 40) { [weak self] idx in
            guard let self else { return }
            self.selectedIndex = idx
            self.title = self.items[idx]
            self.onPick?(idx)
            self.closeDropdown()
        }
        dropdownWindow = w
        w.makeKeyAndOrderFront(nil)
        // 应用内+应用外点击都关闭
        let handler: (NSEvent) -> NSEvent? = { [weak self] event in
            if let win = self?.dropdownWindow, event.window != win {
                self?.closeDropdown()
            }
            return event
        }
        dropdownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: handler)
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closeDropdown()
        }
    }

    private func closeDropdown() {
        dropdownWindow?.close()
        dropdownWindow = nil
        if let monitor = dropdownMonitor {
            NSEvent.removeMonitor(monitor)
            dropdownMonitor = nil
        }
        if Self.currentDropdown === self {
            Self.currentDropdown = nil
        }
    }

    private func updateAppearance() {
        // qwerty 悬停：紫底白字
        layer?.backgroundColor = isHovered ? Theme.primary.cgColor : .clear
        contentTintColor = isHovered ? .white : .labelColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTA { removeTrackingArea(hoverTA) }
        hoverTA = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(hoverTA!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
        showCustomTooltip()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
        hideCustomTooltip()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    // MARK: - 自定义 tooltip

    private func showCustomTooltip() {
        guard !tipText.isEmpty, let container = superview else { return }
        hideCustomTooltip()
        let tip = TooltipView(text: tipText)
        let bf = convert(bounds, to: container)
        tip.frame.origin = NSPoint(x: bf.midX - tip.bounds.width / 2, y: bf.maxY + 8)
        container.addSubview(tip, positioned: .above, relativeTo: nil)
        tooltipTag = tip
    }

    private func hideCustomTooltip() {
        tooltipTag?.removeFromSuperview()
        tooltipTag = nil
    }
}

/// 工具栏图标按钮（qwerty 原版 SVG，模板着色：激活=星云紫、关闭=灰；加载失败回退 SF Symbol）
private final class ToolbarIconButton: NSButton {
    private var isHovered = false
    private let activeTint: NSColor
    private let inactiveTint: NSColor
    private var activeState: Bool
    private var hoverTA: NSTrackingArea?
    private var tooltipTag: NSView?
    private var badgeLabel: NSTextField?
    private let tipText: String

    init(iconName: String, fallbackSymbol: String, tooltip: String, active: Bool) {
        // qwerty 图标色调：indigo-500 (#6366f1)
        self.activeTint = NSColor(red: 0.388, green: 0.400, blue: 0.945, alpha: 1.0)
        self.inactiveTint = Theme.textSecondary
        self.activeState = active
        self.tipText = tooltip
        super.init(frame: .zero)
        image = Self.loadToolbarIcon(iconName) ?? NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: tooltip)
        image?.isTemplate = true
        imagePosition = .imageOnly
        isBordered = false
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 5
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
            self.image = NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: tipText)
        }
        image?.isTemplate = true
        updateAppearance()
    }

    func setActive(_ active: Bool) {
        activeState = active
        updateAppearance()
    }

    /// 图标中央叠加数字角标（qwerty 循环次数显示）
    func setBadge(_ text: String?) {
        badgeLabel?.removeFromSuperview()
        badgeLabel = nil
        guard let text, !text.isEmpty else { return }
        let badge = NSTextField(labelWithString: text)
        badge.font = .monospacedSystemFont(ofSize: 9, weight: .bold)
        badge.textColor = activeTint
        badge.alignment = .center
        badge.drawsBackground = false
        badge.isBezeled = false
        badge.sizeToFit()
        badge.frame = CGRect(x: (bounds.width - badge.bounds.width) / 2,
                             y: (bounds.height - badge.bounds.height) / 2 - 1,
                             width: badge.bounds.width, height: badge.bounds.height)
        addSubview(badge)
        badgeLabel = badge
    }

    private func updateAppearance() {
        layer?.backgroundColor = isHovered ? activeTint.withAlphaComponent(0.10).cgColor : .clear
        contentTintColor = isHovered ? activeTint : (activeState ? activeTint : inactiveTint)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTA { removeTrackingArea(hoverTA) }
        hoverTA = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(hoverTA!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
        showCustomTooltip()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
        hideCustomTooltip()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    // MARK: - 自定义 tooltip

    private func showCustomTooltip() {
        guard !tipText.isEmpty, let container = superview else { return }
        hideCustomTooltip()
        let tip = TooltipView(text: tipText)
        let bf = convert(bounds, to: container)
        tip.frame.origin = NSPoint(x: bf.midX - tip.bounds.width / 2, y: bf.maxY + 8)
        container.addSubview(tip, positioned: .above, relativeTo: nil)
        tooltipTag = tip
    }

    private func hideCustomTooltip() {
        tooltipTag?.removeFromSuperview()
        tooltipTag = nil
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

/// 前后单词导航视图（qwerty PrevAndNextWord：半透明，悬停高亮，点击跳转）
private final class PrevNextWordView: NSView {
    enum NavType { case prev, next }
    private let type: NavType
    private let arrowLabel = NSTextField(labelWithString: "")
    private let wordLabel = NSTextField(labelWithString: "")
    private let transLabel = NSTextField(labelWithString: "")
    var onClick: (() -> Void)?

    init(type: NavType) {
        self.type = type
        super.init(frame: .zero)
        wantsLayer = true
        alphaValue = 0.55
        // 箭头
        arrowLabel.font = .systemFont(ofSize: 22, weight: .light)
        arrowLabel.textColor = Theme.textSecondary
        arrowLabel.stringValue = type == .prev ? "←" : "→"
        // 单词
        wordLabel.font = .monospacedSystemFont(ofSize: 22, weight: .regular)
        wordLabel.textColor = Theme.textSecondary
        wordLabel.lineBreakMode = .byTruncatingTail
        wordLabel.maximumNumberOfLines = 1
        // 释义
        transLabel.font = .systemFont(ofSize: 13, weight: .regular)
        transLabel.textColor = Theme.textTertiary
        transLabel.lineBreakMode = .byTruncatingTail
        transLabel.maximumNumberOfLines = 1
        addSubview(arrowLabel)
        addSubview(wordLabel)
        addSubview(transLabel)
        // 点击
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        addGestureRecognizer(click)
        // 悬停高亮
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(word: String, translation: String) {
        wordLabel.stringValue = word
        transLabel.stringValue = translation
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let arrowW: CGFloat = 28
        let contentW = bounds.width - arrowW - 6
        if type == .prev {
            arrowLabel.frame = CGRect(x: 0, y: (bounds.height - 28) / 2, width: arrowW, height: 28)
            wordLabel.frame = CGRect(x: arrowW + 6, y: bounds.height - 28, width: contentW, height: 26)
            transLabel.frame = CGRect(x: arrowW + 6, y: 0, width: contentW, height: 18)
        } else {
            wordLabel.frame = CGRect(x: 0, y: bounds.height - 28, width: contentW, height: 26)
            wordLabel.alignment = .right
            transLabel.frame = CGRect(x: 0, y: 0, width: contentW, height: 18)
            transLabel.alignment = .right
            arrowLabel.frame = CGRect(x: bounds.width - arrowW, y: (bounds.height - 28) / 2, width: arrowW, height: 28)
            arrowLabel.alignment = .right
        }
    }

    override func mouseEntered(with event: NSEvent) {
        animator().alphaValue = 1.0
    }
    override func mouseExited(with event: NSEvent) {
        animator().alphaValue = 0.55
    }

    @objc private func handleClick() { onClick?() }
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

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// 无边框可成为 key 的窗口（用于设置面板）
private final class BorderlessKeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - 设置窗口视图（qwerty Setting：左侧边栏+右侧内容，独立窗口）

private final class SettingsPanelView: NSView {
    weak var typingPage: TypingPageView?
    private var currentTab = 0
    private let sidebar = NSView()
    private let contentScroll = NSScrollView()
    private let contentDoc = FlippedView()
    private var navButtons: [NSButton] = []

    private let tabs = [
        (icon: "ear", title: "音效设置"),
        (icon: "slider.horizontal.3", title: "高级设置"),
        (icon: "eye", title: "显示设置"),
        (icon: "externaldrive", title: "数据设置"),
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        setupUI()
    }

    override func layout() {
        super.layout()
        layer?.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.15, alpha: 1)
                : .white
        }.cgColor
        if contentDoc.subviews.isEmpty {
            buildTabContent(currentTab)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        // 顶部标题栏
        let titleBar = NSView(frame: NSRect(x: 0, y: bounds.height - 44, width: bounds.width, height: 44))
        titleBar.autoresizingMask = [.width, .minYMargin]
        let titleLabel = NSTextField(labelWithString: "设置")
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.frame = CGRect(x: 20, y: 10, width: 200, height: 26)
        titleBar.addSubview(titleLabel)
        let closeBtn = NSButton(title: "×", target: self, action: #selector(closeWindow))
        closeBtn.isBordered = false
        closeBtn.font = .systemFont(ofSize: 22, weight: .light)
        closeBtn.contentTintColor = .secondaryLabelColor
        closeBtn.frame = CGRect(x: bounds.width - 40, y: 8, width: 28, height: 28)
        closeBtn.autoresizingMask = [.minXMargin]
        titleBar.addSubview(closeBtn)
        addSubview(titleBar)

        // 左侧边栏
        sidebar.frame = CGRect(x: 0, y: 0, width: 160, height: bounds.height - 44)
        sidebar.autoresizingMask = [.height, .maxXMargin]
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
        addSubview(sidebar)

        for (i, tab) in tabs.enumerated() {
            let btn = NSButton(frame: CGRect(x: 12, y: sidebar.bounds.height - 48 - CGFloat(i) * 44, width: 136, height: 36))
            btn.autoresizingMask = [.maxYMargin]
            btn.title = "  \(tab.title)"
            btn.image = NSImage(systemSymbolName: tab.icon, accessibilityDescription: tab.title)
            btn.imagePosition = .imageLeft
            btn.font = .systemFont(ofSize: 13, weight: .medium)
            btn.isBordered = false
            btn.contentTintColor = .secondaryLabelColor
            btn.tag = i
            btn.target = self
            btn.action = #selector(tabClicked(_:))
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 8
            navButtons.append(btn)
            sidebar.addSubview(btn)
        }
        updateNavSelection()

        // 右侧内容区
        contentScroll.frame = CGRect(x: 160, y: 0, width: bounds.width - 160, height: bounds.height - 44)
        contentScroll.autoresizingMask = [.width, .height]
        contentScroll.hasVerticalScroller = true
        contentScroll.borderType = .noBorder
        contentScroll.drawsBackground = false
        contentScroll.documentView = contentDoc
        addSubview(contentScroll)

        buildTabContent(0)
    }

    @objc private func closeWindow() {
        typingPage?.settingsWindowDidClose()
        window?.close()
    }

    @objc private func tabClicked(_ sender: NSButton) {
        currentTab = sender.tag
        updateNavSelection()
        buildTabContent(currentTab)
    }

    private func updateNavSelection() {
        for (i, btn) in navButtons.enumerated() {
            if i == currentTab {
                btn.layer?.backgroundColor = NSColor.selectedControlColor.withAlphaComponent(0.15).cgColor
                btn.contentTintColor = .labelColor
            } else {
                btn.layer?.backgroundColor = .clear
                btn.contentTintColor = .secondaryLabelColor
            }
        }
    }

    private func buildTabContent(_ tab: Int) {
        contentDoc.subviews.forEach { $0.removeFromSuperview() }
        let w = contentScroll.bounds.width - 24
        var y: CGFloat = 16

        switch tab {
        case 0: y = buildSoundTab(w, y)
        case 1: y = buildAdvancedTab(w, y)
        case 2: y = buildViewTab(w, y)
        case 3: y = buildDataTab(w, y)
        default: break
        }
        contentDoc.frame = CGRect(x: 0, y: 0, width: w, height: max(y + 20, contentScroll.bounds.height))
    }

    // MARK: - 音效设置 tab

    private func buildSoundTab(_ w: CGFloat, _ startY: CGFloat) -> CGFloat {
        var y = startY
        guard let page = typingPage else { return y }

        // 单词发音
        y = addSectionTitle(contentDoc, y: y, title: "单词发音", width: w)
        y = addToggleRow(contentDoc, y: y, width: w,
                         on: !page.accentLocale.isEmpty,
                         status: page.accentLocale.isEmpty ? "发音已关闭" : "发音已开启") { [weak self] on in
            self?.typingPage?.accentLocale = on ? "en-US" : ""
            self?.typingPage?.speakerButton.isHidden = !on
            self?.rebuildCurrentTab()
        }
        y = addSliderRow(contentDoc, y: y, width: w, label: "音量", value: 100, min: 0, max: 100, suffix: "%") { _ in }
        y = addSliderRow(contentDoc, y: y, width: w, label: "倍速", value: 1.0, min: 0.5, max: 4.0, suffix: "") { _ in }
        y += 12

        // 释义发音
        y = addSectionTitle(contentDoc, y: y, title: "释义发音", width: w)
        y = addToggleRow(contentDoc, y: y, width: w,
                         on: page.transPronunciationEnabled,
                         status: page.transPronunciationEnabled ? "发音已开启" : "发音已关闭") { [weak self] on in
            self?.typingPage?.transPronunciationEnabled = on
            self?.rebuildCurrentTab()
        }
        y = addSliderRow(contentDoc, y: y, width: w, label: "音量", value: 100, min: 0, max: 100, suffix: "%") { _ in }
        y += 12

        // 按键音
        y = addSectionTitle(contentDoc, y: y, title: "按键音", width: w)
        y = addToggleRow(contentDoc, y: y, width: w,
                         on: SoundManager.shared.keySoundEnabled,
                         status: SoundManager.shared.keySoundEnabled ? "发音已开启" : "发音已关闭") { [weak self] on in
            SoundManager.shared.keySoundEnabled = on
            self?.typingPage?.iconButtons[0].setActive(on)
            self?.rebuildCurrentTab()
        }
        y = addSliderRow(contentDoc, y: y, width: w, label: "音量", value: 50, min: 1, max: 100, suffix: "%") { _ in }
        y += 12

        // 效果音
        y = addSectionTitle(contentDoc, y: y, title: "效果音", width: w)
        y = addToggleRow(contentDoc, y: y, width: w,
                         on: SoundManager.shared.hintSoundEnabled,
                         status: SoundManager.shared.hintSoundEnabled ? "发音已开启" : "发音已关闭") { [weak self] on in
            SoundManager.shared.hintSoundEnabled = on
            self?.rebuildCurrentTab()
        }
        y = addSliderRow(contentDoc, y: y, width: w, label: "音量", value: 50, min: 1, max: 100, suffix: "%") { _ in }
        return y
    }

    // MARK: - 高级设置 tab

    private func buildAdvancedTab(_ w: CGFloat, _ startY: CGFloat) -> CGFloat {
        var y = startY
        guard let page = typingPage else { return y }

        y = addSectionTitle(contentDoc, y: y, title: "章节乱序", desc: "开启后，每次练习章节中单词会随机排序。下一章节生效", width: w)
        y = addToggleRow(contentDoc, y: y, width: w, on: false, status: "随机已关闭") { _ in }
        y += 12

        y = addSectionTitle(contentDoc, y: y, title: "练习时展示上一个/下一个单词", desc: "开启后，练习中会在上方展示上一个/下一个单词", width: w)
        y = addToggleRow(contentDoc, y: y, width: w,
                         on: page.showPrevNextWord,
                         status: page.showPrevNextWord ? "展示单词已开启" : "展示单词已关闭") { [weak self] on in
            self?.typingPage?.showPrevNextWord = on
            self?.typingPage?.needsLayout = true
            self?.rebuildCurrentTab()
        }
        y += 12

        y = addSectionTitle(contentDoc, y: y, title: "是否忽略大小写", desc: "开启后，输入时不区分大小写", width: w)
        y = addToggleRow(contentDoc, y: y, width: w,
                         on: page.ignoreCase,
                         status: page.ignoreCase ? "忽略大小写已开启" : "忽略大小写已关闭") { [weak self] on in
            self?.typingPage?.ignoreCase = on
            self?.typingPage?.service.ignoreCase = on
            self?.rebuildCurrentTab()
        }
        y += 12

        y = addSectionTitle(contentDoc, y: y, title: "是否允许选择文本", desc: "开启后，可以通过鼠标选择文本", width: w)
        y = addToggleRow(contentDoc, y: y, width: w, on: false, status: "选择文本已关闭") { _ in }
        return y
    }

    // MARK: - 显示设置 tab

    private func buildViewTab(_ w: CGFloat, _ startY: CGFloat) -> CGFloat {
        var y = startY
        guard let page = typingPage else { return y }

        y = addSectionTitle(contentDoc, y: y, title: "字体设置", width: w)
        y = addSliderRow(contentDoc, y: y, width: w, label: "外语字体",
                         value: Double(page.wordFontSize), min: 20, max: 96, suffix: "px") { [weak self] val in
            self?.typingPage?.wordFontSize = CGFloat(val)
            self?.typingPage?.wordLabel.font = .monospacedSystemFont(ofSize: CGFloat(val), weight: .regular)
            self?.typingPage?.needsLayout = true
        }
        y = addSliderRow(contentDoc, y: y, width: w, label: "中文字体",
                         value: Double(page.transFontSize), min: 14, max: 60, suffix: "px") { [weak self] val in
            self?.typingPage?.transFontSize = CGFloat(val)
            self?.typingPage?.translationLabel.font = .systemFont(ofSize: CGFloat(val), weight: .regular)
        }
        y += 12

        // 重置按钮
        let resetBtn = ButtonFactory.primary("重置字体设置", target: self, action: #selector(resetFont))
        resetBtn.frame = CGRect(x: 0, y: y, width: 120, height: 26)
        contentDoc.addSubview(resetBtn)
        y += 36
        return y
    }

    @objc private func resetFont() {
        typingPage?.wordFontSize = 48
        typingPage?.transFontSize = 18
        typingPage?.wordLabel.font = .monospacedSystemFont(ofSize: 48, weight: .regular)
        typingPage?.translationLabel.font = .systemFont(ofSize: 18, weight: .regular)
        typingPage?.needsLayout = true
        rebuildCurrentTab()
    }

    // MARK: - 数据设置 tab

    private func buildDataTab(_ w: CGFloat, _ startY: CGFloat) -> CGFloat {
        var y = startY

        y = addSectionTitle(contentDoc, y: y, title: "数据导出",
                            desc: "目前，用户的练习数据仅保存在本地。建议及时备份。", width: w)
        let exportBtn = ButtonFactory.primary("导出数据", target: self, action: #selector(exportData))
        exportBtn.frame = CGRect(x: 0, y: y, width: 88, height: 26)
        contentDoc.addSubview(exportBtn)
        y += 40
        y += 12

        y = addSectionTitle(contentDoc, y: y, title: "清空错词本", desc: "删除所有错词记录，不可恢复", width: w)
        let clearBtn = ButtonFactory.ghost("清空错词本", target: self, action: #selector(clearWrongWords))
        clearBtn.frame = CGRect(x: 0, y: y, width: 100, height: 26)
        contentDoc.addSubview(clearBtn)
        y += 36
        return y
    }

    @objc private func exportData() {
        guard let data = try? JSONEncoder().encode(typingPage?.state?.store.data) else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "engram-backup.json"
        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? data.write(to: url)
        }
    }

    @objc private func clearWrongWords() {
        let alert = NSAlert()
        alert.messageText = "确认清空错词本？"
        alert.informativeText = "所有错词记录将被删除，此操作不可恢复。"
        alert.addButton(withTitle: "确认清空")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            typingPage?.state?.store.clearWrongWords()
        }
    }

    private func rebuildCurrentTab() {
        buildTabContent(currentTab)
    }

    // MARK: - 通用 UI 构建器

    @discardableResult
    private func addSectionTitle(_ parent: NSView, y: CGFloat, title: String, desc: String = "", width: CGFloat) -> CGFloat {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.frame = CGRect(x: 0, y: y, width: width, height: 22)
        parent.addSubview(titleLabel)
        var newY = y + 26
        if !desc.isEmpty {
            let descLabel = NSTextField(labelWithString: desc)
            descLabel.font = .systemFont(ofSize: 11)
            descLabel.textColor = .secondaryLabelColor
            descLabel.lineBreakMode = .byWordWrapping
            descLabel.cell?.wraps = true
            descLabel.frame = CGRect(x: 0, y: newY, width: width - 20, height: 28)
            parent.addSubview(descLabel)
            newY += 32
        }
        return newY
    }

    @discardableResult
    private func addToggleRow(_ parent: NSView, y: CGFloat, width: CGFloat,
                              on: Bool, status: String, onChange: @escaping (Bool) -> Void) -> CGFloat {
        let toggle = NSSwitch()
        toggle.state = on ? .on : .off
        toggle.frame = CGRect(x: 0, y: y, width: 40, height: 24)
        toggle.target = self
        toggle.action = #selector(toggleChanged(_:))
        objc_setAssociatedObject(toggle, &Self.toggleCallbackKey, onChange, .OBJC_ASSOCIATION_RETAIN)
        parent.addSubview(toggle)

        let statusLabel = NSTextField(labelWithString: status)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .right
        statusLabel.frame = CGRect(x: width - 100, y: y + 2, width: 90, height: 18)
        parent.addSubview(statusLabel)
        return y + 30
    }

    private static var toggleCallbackKey: UInt8 = 0

    @objc private func toggleChanged(_ sender: NSSwitch) {
        if let callback = objc_getAssociatedObject(sender, &Self.toggleCallbackKey) as? (Bool) -> Void {
            callback(sender.state == .on)
        }
    }

    @discardableResult
    private func addSliderRow(_ parent: NSView, y: CGFloat, width: CGFloat,
                              label: String, value: Double, min: Double, max: Double,
                              suffix: String, onChange: @escaping (Double) -> Void) -> CGFloat {
        let labelField = NSTextField(labelWithString: label)
        labelField.font = .systemFont(ofSize: 12)
        labelField.textColor = .secondaryLabelColor
        labelField.frame = CGRect(x: 0, y: y + 1, width: 50, height: 18)
        parent.addSubview(labelField)

        let slider = NSSlider(value: value, minValue: min, maxValue: max, target: self, action: #selector(sliderChanged(_:)))
        slider.frame = CGRect(x: 50, y: y, width: width - 110, height: 20)
        objc_setAssociatedObject(slider, &Self.sliderCallbackKey, onChange, .OBJC_ASSOCIATION_RETAIN)
        parent.addSubview(slider)

        let valText = suffix.isEmpty ? String(format: "%.1f", value) : "\(Int(value))\(suffix)"
        let valLabel = NSTextField(labelWithString: valText)
        valLabel.font = .systemFont(ofSize: 12)
        valLabel.textColor = .secondaryLabelColor
        valLabel.alignment = .right
        valLabel.frame = CGRect(x: width - 54, y: y + 1, width: 48, height: 18)
        parent.addSubview(valLabel)
        return y + 28
    }

    private static var sliderCallbackKey: UInt8 = 0

    @objc private func sliderChanged(_ sender: NSSlider) {
        if let callback = objc_getAssociatedObject(sender, &Self.sliderCallbackKey) as? (Double) -> Void {
            callback(sender.doubleValue)
        }
    }
}

final class TypingPageView: NSView {

    // MARK: - 属性

    fileprivate weak var state: AppState?
    /// 页面内跳转（统计图标等）
    var onNavigate: ((AppPage) -> Void)?
    fileprivate let service = TypingService()
    private var sessionWords: [WordEntry] = []
    private var wrongFlash = false
    private var hasStartedTyping = false
    private var sessionStart = Date()
    private var ticker: Timer?
    private var wrongWords: [String] = []
    private var wrongWordSet: Set<String> = []
    /// 当前单词的错误次数（qwerty：单词完成时保存记录）
    private var currentWordWrongCount = 0
    /// 当前词库名（用于错词记录分组）
    private var currentDeckName = ""
    // MARK: - 设置项（qwerty Setting 4 tab）
    fileprivate var showPrevNextWord = true       // 高级：前后单词显示
    fileprivate var ignoreCase = true             // 高级：忽略大小写
    fileprivate var wordFontSize: CGFloat = 48    // 显示：外语字体大小
    fileprivate var transFontSize: CGFloat = 18   // 显示：中文字体大小
    private var keySoundVolume: Float = 0.5   // 音效：按键音音量
    private var hintSoundVolume: Float = 0.5  // 音效：效果音音量
    /// 释义显示开关（qwerty language 图标）
    private var translationVisible = true
    /// 默写模式（qwerty eye 图标）
    private var dictationMode: DictationMode = .off
    /// 音标显示开关（qwerty 发音面板）
    private var phoneticVisible = true
    /// 释义发音开关（qwerty 发音面板）
    fileprivate var transPronunciationEnabled = false
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
    fileprivate var iconButtons: [ToolbarIconButton] = []
    private let startButton: NSButton
    /// Start 悬停展开的 Restart 按钮（qwerty StartButton）
    private let restartButton: NSButton
    private var startHoverTA: NSTrackingArea?
    /// 当前弹出的 Popover（统一管理，修复关闭后无法再次打开的 bug）
    private var currentPopover: NSPopover?
    /// 全局快捷键监听（Ctrl+J 朗读 / Ctrl+V 默写 / Ctrl+Shift+V 释义）
    private var hotkeyMonitor: Any?

    // 中间界面
    fileprivate let wordLabel = NSTextField(labelWithString: "")
    private let phoneticLabel = LabelFactory.label("", font: .systemFont(ofSize: 14), color: Theme.textSecondary, align: .center)
    fileprivate let translationLabel = LabelFactory.label("", font: .systemFont(ofSize: 18), color: Theme.textPrimary, align: .center)
    private let hintLabel = LabelFactory.label("", font: .systemFont(ofSize: 11), color: Theme.textSecondary, align: .center)
    private let overlayView = NSVisualEffectView()
    private let overlayLabel = LabelFactory.label("按任意键开始", font: .systemFont(ofSize: 20), color: Theme.textPrimary, align: .center)
    /// 单词右侧喇叭按钮（qwerty：4帧音量图标循环动画）
    fileprivate let speakerButton = HandCursorButton()
    /// 有道真人发音播放器
    private var pronunciationPlayer: AVPlayer?
    private var pronunciationEndObserver: Any?
    /// 喇叭 4 帧动画 Timer（qwerty SoundIcon：每 500ms 切换音量图标）
    private var speakerAnimTimer: Timer?
    private var speakerFrameIndex = 0
    private let speakerFrames = ["volume_0", "volume_1", "volume_2", "volume_3"]
    /// 前后单词导航（qwerty PrevAndNextWord）
    private let prevWordView = PrevNextWordView(type: .prev)
    private let nextWordView = PrevNextWordView(type: .next)
    /// 上一个已朗读的单词 ID（避免每次 render 重复朗读）
    private var lastSpokenWordId: String?
    /// 当前发音口音（美音 en-US / 英音 en-GB / 关闭=空串）
    fileprivate var accentLocale = "en-US"

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
        restartButton = ButtonFactory.primary("Restart", target: nil, action: #selector(TypingPageView.restartTapped))
        restartButton.isHidden = true
        restartButton.font = .systemFont(ofSize: 12, weight: .medium)
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
        setupHotkeys()
        populateDecks()
        populateChapters()
        layoutToolbar()
        startSession()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未使用") }
    override var isFlipped: Bool { true }
    deinit {
        ticker?.invalidate()
        if let monitor = hotkeyMonitor { NSEvent.removeMonitor(monitor) }
    }

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
            self?.currentDeckName = self?.deckText.items[idx] ?? ""
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
        toolbarCard.addSubview(restartButton)

        // 中间界面
        wordLabel.alignment = .center
        wordLabel.wantsLayer = true
        wordLabel.font = .monospacedSystemFont(ofSize: wordFontSize, weight: .regular)
        addSubview(wordLabel)
        // 喇叭按钮：单词右侧，点击朗读（qwerty 同款 4 帧音量图标）
        speakerButton.isBordered = false
        speakerButton.focusRingType = .none
        speakerButton.imagePosition = .imageOnly
        speakerButton.image = Self.loadSpeakerIcon("volume_0")
        speakerButton.contentTintColor = Theme.textSecondary
        speakerButton.target = self
        speakerButton.action = #selector(speakerTapped)
        speakerButton.toolTip = "朗读单词（⌃J）"
        addSubview(speakerButton)
        // 前后单词导航（qwerty PrevAndNextWord）
        prevWordView.onClick = { [weak self] in self?.skipToPrevWord() }
        nextWordView.onClick = { [weak self] in self?.skipToNextWord() }
        addSubview(prevWordView)
        addSubview(nextWordView)
        addSubview(phoneticLabel)
        addSubview(translationLabel)
        addSubview(hintLabel)

        // 毛玻璃：覆盖单词区，模糊背后的单词（可透视），"按任意键开始"文字居中浮于其上
        // maskImage 垂直渐变让上下边缘柔和过渡，看不出方框边界（对齐 qwerty backdrop-blur）
        overlayView.material = .sheet
        overlayView.blendingMode = .withinWindow
        overlayView.state = .active
        overlayView.alphaValue = 0.75
        overlayView.wantsLayer = true
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
            let caption = LabelFactory.label(pair.0, font: .systemFont(ofSize: 11), color: Theme.textTertiary, align: .center)
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
        // 前后单词导航（qwerty：顶部左右两侧，仅打字中显示）
        let navH: CGFloat = 56
        let navW: CGFloat = 240
        let navY = topEdge + 4
        prevWordView.frame = CGRect(x: 24, y: navY, width: navW, height: navH)
        nextWordView.frame = CGRect(x: 696 - navW - 24, y: navY, width: navW, height: navH)
        let showNav = showPrevNextWord && hasStartedTyping && !isPaused && resultCard.isHidden
        prevWordView.isHidden = !showNav || service.word(at: service.currentIndex - 1) == nil
        nextWordView.isHidden = !showNav || service.word(at: service.currentIndex + 1) == nil

        let zoneBottom = h - bottomGap - cardH - gap - progressH - gap
        let wordTop = topEdge + navH + 8
        let zoneH = max(zoneBottom - wordTop, 200)
        let blockH: CGFloat = 90 + 10 + 22 + 8 + 28 + 6 + 16
        let wordBlockTop = wordTop + (zoneH - blockH) / 2
        var y = wordBlockTop
        wordLabel.frame = CGRect(x: 48, y: y, width: 600, height: 90)
        // 喇叭按钮：单词右侧，与单词垂直居中
        if let word = service.currentWord {
            let font = NSFont.monospacedSystemFont(ofSize: wordFontSize, weight: .regular)
            let textW = (word.text as NSString).size(withAttributes: [.font: font]).width
            let centerX = bounds.width / 2
            speakerButton.frame = CGRect(x: centerX + textW / 2 + 12,
                                         y: y + (90 - 32) / 2,
                                         width: 32, height: 32)
        }
        speakerButton.isHidden = accentLocale.isEmpty
        y += 90 + 10
        phoneticLabel.frame = CGRect(x: 60, y: y, width: 576, height: 22)
        y += 22 + 8
        translationLabel.frame = CGRect(x: 60, y: y, width: 576, height: 28)
        y += 28 + 6
        hintLabel.frame = CGRect(x: 60, y: y, width: 576, height: 16)

        // 毛玻璃覆盖整个单词区（单词+音标+释义+提示），上下各留 32pt 缓冲
        let blurTop = max(wordBlockTop - 32, wordTop)
        let blurBottom = min(y + 16 + 32, zoneBottom)
        let blurH = blurBottom - blurTop
        overlayView.frame = CGRect(x: 0, y: blurTop, width: 696, height: blurH)
        // maskImage：上下渐变透明，消除模糊硬边界（NSVisualEffectView 用 maskImage 比 layer.mask 更可靠）
        overlayView.maskImage = Self.makeVerticalGradientMask(size: overlayView.bounds.size)
        // "按任意键开始/继续"文字垂直居中
        overlayLabel.frame = CGRect(x: 0, y: (blurH - 36) / 2, width: 696, height: 36)

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
        // Restart 按钮：Start 正下方，悬停时展开
        restartButton.frame = CGRect(x: x, y: 40, width: Self.startWidth, height: 22)
        // 给 Start 加悬停追踪（qwerty：悬停展开 Restart）
        if let startHoverTA { startButton.removeTrackingArea(startHoverTA) }
        startHoverTA = NSTrackingArea(rect: startButton.bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self)
        startButton.addTrackingArea(startHoverTA!)
    }

    private static func textWidth(_ text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 15, weight: .medium)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    /// 加载喇叭 4 帧 SVG 图标（qwerty VolumeIcon 系列，模板着色）
    private static func loadSpeakerIcon(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "icons"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 28, height: 28)
        image.isTemplate = true
        return image
    }

    // MARK: - 会话控制

    private func populateDecks() {
        let decks = state?.library.wordDecks ?? []
        deckText.items = decks.map { $0.name }
        deckText.values = decks.map { $0.id as Any? }
        deckText.title = decks.first?.name ?? ""
        deckText.selectedIndex = 0
        currentDeckName = decks.first?.name ?? ""
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

    /// qwerty StartButton 悬停展开的 Restart：重新开始本章
    @objc private func restartTapped() {
        restartButton.isHidden = true
        startSession()
    }

    // MARK: - Start 按钮悬停展开 Restart

    override func mouseEntered(with event: NSEvent) {
        if event.trackingArea === startHoverTA {
            restartButton.isHidden = false
        }
    }

    override func mouseExited(with event: NSEvent) {
        if event.trackingArea === startHoverTA {
            // 延迟隐藏，给用户时间移到 Restart 按钮上
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self = self else { return }
                let loc = NSEvent.mouseLocation
                let inStart = self.startButton.isMousePoint(self.startButton.convert(loc, from: nil), in: self.startButton.bounds)
                let inRestart = self.restartButton.isMousePoint(self.restartButton.convert(loc, from: nil), in: self.restartButton.bounds)
                if !inStart && !inRestart {
                    self.restartButton.isHidden = true
                }
            }
        }
    }

    // MARK: - 全局快捷键（qwerty：Ctrl+J 朗读 / Ctrl+V 默写 / Ctrl+Shift+V 释义）

    private func setupHotkeys() {
        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.window?.isKeyWindow ?? false else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Ctrl+J：朗读当前单词
            if mods.contains(.control) && !mods.contains(.shift) && event.keyCode == 38 {
                self.speakCurrentWord()
                return nil
            }
            // Ctrl+V：切换默写模式
            if mods.contains(.control) && !mods.contains(.shift) && event.keyCode == 9 {
                self.toggleDictationQuick()
                return nil
            }
            // Ctrl+Shift+V：切换释义显示
            if mods.contains([.control, .shift]) && event.keyCode == 9 {
                self.toggleTranslation()
                return nil
            }
            return event
        }
    }

    /// 朗读当前单词（有道真人发音 API，qwerty 同款）
    private func speakCurrentWord() {
        guard !accentLocale.isEmpty, let word = service.currentWord else { return }
        // 有道词典 API：type=1 英音，type=2 美音
        let type = accentLocale == "en-GB" ? 1 : 2
        let urlStr = "https://dict.youdao.com/dictvoice?audio=\(word.text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? word.text)&type=\(type)"
        guard let url = URL(string: urlStr) else { return }
        // 停止之前的播放
        stopPronunciation()
        let playerItem = AVPlayerItem(url: url)
        pronunciationPlayer = AVPlayer(playerItem: playerItem)
        // 播放结束时停止动画
        pronunciationEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.stopSpeakerAnimation()
        }
        pronunciationPlayer?.play()
        startSpeakerAnimation()
    }

    /// 点击喇叭朗读
    @objc private func speakerTapped() {
        speakCurrentWord()
    }

    /// 停止发音播放
    private func stopPronunciation() {
        pronunciationPlayer?.pause()
        pronunciationPlayer = nil
        if let observer = pronunciationEndObserver {
            NotificationCenter.default.removeObserver(observer)
            pronunciationEndObserver = nil
        }
        stopSpeakerAnimation()
    }

    /// 喇叭 4 帧动画（qwerty SoundIcon：无波→1波→2波→3波，每 500ms 循环）
    private func startSpeakerAnimation() {
        speakerFrameIndex = 0
        speakerButton.image = Self.loadSpeakerIcon(speakerFrames[0])
        speakerAnimTimer?.invalidate()
        speakerAnimTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.speakerFrameIndex = (self.speakerFrameIndex + 1) % self.speakerFrames.count
            self.speakerButton.image = Self.loadSpeakerIcon(self.speakerFrames[self.speakerFrameIndex])
        }
    }

    /// 停止喇叭动画，回到默认图标
    private func stopSpeakerAnimation() {
        speakerAnimTimer?.invalidate()
        speakerAnimTimer = nil
        speakerFrameIndex = 0
        speakerButton.image = Self.loadSpeakerIcon("volume_0")
    }

    /// 快速切换默写（Ctrl+V）
    private func toggleDictationQuick() {
        if dictationMode == .off {
            dictationMode = .hideAll
        } else {
            dictationMode = .off
        }
        updateDictationIcon()
        render()
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

    /// 跳转到上一个单词（qwerty PrevAndNextWord）
    private func skipToPrevWord() {
        let prevIndex = max(0, service.currentIndex - 1)
        guard prevIndex != service.currentIndex else { return }
        stopPronunciation()
        lastSpokenWordId = nil
        _ = service.skipToWord(prevIndex)
        render()
        needsLayout = true
    }

    /// 跳转到下一个单词（qwerty PrevAndNextWord）
    private func skipToNextWord() {
        let nextIndex = min(service.totalWords - 1, service.currentIndex + 1)
        guard nextIndex != service.currentIndex else { return }
        stopPronunciation()
        lastSpokenWordId = nil
        _ = service.skipToWord(nextIndex)
        render()
        needsLayout = true
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
            menu.appearance = NSAppearance(named: .aqua)
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
        popover.appearance = NSAppearance(named: .aqua)
        let content = NSViewController()
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 240, height: 130))
        content.view = view
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.white.cgColor
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
        popover.appearance = NSAppearance(named: .aqua)
        let content = NSViewController()
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 240, height: viewH))
        content.view = view
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.white.cgColor
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
        popover.appearance = NSAppearance(named: .aqua)
        let content = NSViewController()
        let options: [Int] = [1, 3, 5, 8, Int.max]
        let labels = ["1", "3", "5", "8", "无限"]
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 240, height: CGFloat(30 + options.count * 32)))
        content.view = view
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.white.cgColor
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
        // qwerty：循环图标中央叠加次数数字，无限时不显示
        iconButtons[1].setBadge(isOff || times == Int.max ? nil : "\(times)")
    }

    /// 释义显示开关（qwerty language 图标）
    private func toggleTranslation() {
        translationVisible.toggle()
        translationLabel.isHidden = !translationVisible
        iconButtons[3].setIcon(translationVisible ? "tabler_language" : "tabler_language-off",
                               fallbackSymbol: "textformat.size", active: translationVisible)
    }

    // MARK: - 错题本弹窗（qwerty ErrorBook：持久化、错误次数、删除）

    private func showErrorBook(_ sender: NSButton) {
        let records = state?.store.allWrongWords() ?? []
        let popover = NSPopover()
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .aqua)
        let content = NSViewController()
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 360, height: 360))
        content.view = view
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.white.cgColor
        // 标题 + 总数
        let title = LabelFactory.label("错题本", font: Theme.titleFont(16))
        title.frame = CGRect(x: 16, y: 328, width: 120, height: 22)
        view.addSubview(title)
        let countLabel = LabelFactory.label("共 \(records.count) 词", font: .systemFont(ofSize: 12),
                                            color: Theme.textSecondary, align: .right)
        countLabel.frame = CGRect(x: 240, y: 330, width: 104, height: 18)
        view.addSubview(countLabel)

        if records.isEmpty {
            let empty = LabelFactory.label("暂无错词，继续保持！", font: .systemFont(ofSize: 13),
                                           color: Theme.textSecondary, align: .center)
            empty.frame = CGRect(x: 0, y: 160, width: 360, height: 20)
            view.addSubview(empty)
        } else {
            let scroll = NSScrollView(frame: CGRect(x: 16, y: 16, width: 328, height: 300))
            scroll.hasVerticalScroller = true
            scroll.borderType = .noBorder
            scroll.drawsBackground = false
            let rowH: CGFloat = 52
            let doc = NSView(frame: CGRect(x: 0, y: 0, width: 312, height: max(CGFloat(records.count) * rowH, 300)))
            for (i, record) in records.enumerated() {
                let row = NSView()
                row.wantsLayer = true
                row.layer = CALayer()
                row.layer?.backgroundColor = Theme.cardBackground.cgColor
                row.layer?.cornerRadius = 8
                row.layer?.borderWidth = 1
                row.layer?.borderColor = Theme.cardBorder.cgColor
                row.frame = CGRect(x: 0, y: CGFloat(records.count - 1 - i) * rowH + 4, width: 312, height: rowH - 8)
                // 单词
                let wordLabel = LabelFactory.label(record.word, font: .monospacedSystemFont(ofSize: 15, weight: .medium),
                                                   color: Theme.textPrimary)
                wordLabel.frame = CGRect(x: 12, y: 24, width: 200, height: 18)
                row.addSubview(wordLabel)
                // 释义
                let transLabel = LabelFactory.label(record.translation, font: .systemFont(ofSize: 11),
                                                    color: Theme.textSecondary)
                transLabel.frame = CGRect(x: 12, y: 6, width: 200, height: 14)
                transLabel.lineBreakMode = .byTruncatingTail
                row.addSubview(transLabel)
                // 错误次数
                let countBadge = LabelFactory.label("错 \(record.wrongCount) 次", font: .systemFont(ofSize: 11, weight: .medium),
                                                    color: Theme.danger, align: .right)
                countBadge.frame = CGRect(x: 220, y: 18, width: 56, height: 16)
                row.addSubview(countBadge)
                // 删除按钮
                let delBtn = HandCursorButton()
                delBtn.title = "删除"
                delBtn.isBordered = false
                delBtn.font = .systemFont(ofSize: 11)
                delBtn.contentTintColor = Theme.textTertiary
                delBtn.identifier = NSUserInterfaceItemIdentifier(record.id)
                delBtn.target = self
                delBtn.action = #selector(deleteWrongWord(_:))
                delBtn.frame = CGRect(x: 278, y: 16, width: 28, height: 20)
                row.addSubview(delBtn)
                doc.addSubview(row)
            }
            scroll.documentView = doc
            view.addSubview(scroll)
        }
        popover.contentViewController = content
        presentPopover(popover, sender: sender)
    }

    /// 删除错词（错题本弹窗内）
    @objc private func deleteWrongWord(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        state?.store.deleteWrongWord(id: id)
        sender.window?.close()
    }

    // MARK: - 指法图示弹窗

    private func showKeyboardGuide(_ sender: NSButton) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .aqua)
        let content = NSViewController()
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 360, height: 260))
        content.view = view
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.white.cgColor
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

    // MARK: - 设置窗口（qwerty Setting：独立窗口，左侧边栏+右侧内容）

    private var settingsWindow: NSWindow?

    private func showSettings(_ sender: NSButton) {
        // 如果已打开则前置
        if let win = settingsWindow, win.isVisible {
            win.makeKeyAndOrderFront(nil)
            return
        }
        let panel = SettingsPanelView(frame: NSRect(x: 0, y: 0, width: 550, height: 380))
        panel.typingPage = self
        let win = BorderlessKeyWindow(contentRect: NSRect(x: 0, y: 0, width: 550, height: 380),
                           styleMask: [.borderless],
                           backing: .buffered, defer: false)
        win.title = "设置"
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.isRestorable = false
        win.hasShadow = true
        win.isOpaque = false
        win.backgroundColor = .clear
        win.contentView = panel
        win.center()
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
    }

    /// 设置窗口关闭时清理
    func settingsWindowDidClose() {
        settingsWindow = nil
    }


    // MARK: - 发音面板（qwerty PronunciationSwitcher：音标+单词发音+释义发音+循环发音+口音）

    @objc private func showPronunciationPanel(_ sender: NSButton) {
        let pronOn = !accentLocale.isEmpty
        let viewH: CGFloat = pronOn ? 340 : 150
        let popover = NSPopover()
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .aqua)
        let content = NSViewController()
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 240, height: viewH))
        content.view = view
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.white.cgColor
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

            // qwerty Tips：朗读发音快捷键提示
            y -= 30
            let tips = LabelFactory.label("Tips：朗读快捷键 ⌃J", font: .systemFont(ofSize: 10, weight: .medium),
                                          color: Theme.textTertiary, align: .left)
            tips.frame = CGRect(x: 16, y: y, width: 208, height: 16)
            view.addSubview(tips)
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
        // 主动刷新窗口渐变和卡片颜色
        NXWindowStyle.updateAppearance()
        needsLayout = true
        subviews.forEach { $0.needsLayout = true }
    }

    private func startSession() {
        let words = chapterWords()
        guard !words.isEmpty else { return }
        sessionWords = words
        service.startSession(words: words)
        service.ignoreCase = ignoreCase
        hasStartedTyping = false
        isPaused = false
        accumulatedElapsed = 0
        sessionStart = Date()
        wrongWords.removeAll()
        wrongWordSet.removeAll()
        currentWordWrongCount = 0
        lastSpokenWordId = nil
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
        // 暂停中：任意键恢复（该键只触发恢复，不当作输入，qwerty 行为）
        if isPaused {
            resumeSession()
            return
        }
        if char == "\t" { skipCurrentWord(); return }
        // 未开始：任意键开始（该键只触发开始，不当作输入判断对错）
        if !hasStartedTyping {
            hasStartedTyping = true
            sessionStart = Date()
            accumulatedElapsed = 0
            startTicker()
            updateStartButton()
            render()
            return
        }
        guard char.isLetter else { return }
        let feedback = service.input(character: char)
        switch feedback {
        case .accepted:
            SoundManager.shared.playKey()
            render()
        case .wrongAndReset:
            SoundManager.shared.playWrong()
            currentWordWrongCount += 1
            if let word = service.currentWord { recordWrongWord(word.text) }
            animateWrongShake()
            wrongFlash = true
            // 打错重来时重新朗读（qwerty：错误重置后重新读单词）
            stopPronunciation()
            lastSpokenWordId = nil
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
        // qwerty：单词完成时保存错词记录（含错误次数），持久化跨会话
        if currentWordWrongCount > 0 {
            state?.store.recordWrongWord(
                word: target.text, translation: target.translation,
                dictName: currentDeckName, wrongCount: currentWordWrongCount,
                letterMistakes: nil
            )
        }
        currentWordWrongCount = 0
        state?.recordPractice(id: target.id, kind: .word, grade: .good)
        state?.store.recordToday(action: { $0.wordsTyped += 1 }, now: Date())
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
        // 动态解析遮罩颜色（明暗模式自适应）
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        dimView.layer?.backgroundColor = (isDark
            ? NSColor(white: 0.08, alpha: 0.8)
            : NSColor(white: 0.85, alpha: 0.75)).cgColor
        dimView.isHidden = false
        resultCard.isHidden = false
        playConfetti()
    }

    // MARK: - 完成彩纸动画（qwerty useConfetti）

    private func playConfetti() {
        let emitter = CAEmitterLayer()
        emitter.frame = CGRect(x: 0, y: -20, width: bounds.width, height: 10)
        emitter.emitterShape = .line
        emitter.emitterPosition = CGPoint(x: bounds.width / 2, y: 0)
        emitter.emitterSize = CGSize(width: bounds.width, height: 0)
        emitter.renderMode = .oldestFirst

        let colors: [CGColor] = [
            NSColor(red: 0.424, green: 0.361, blue: 0.906, alpha: 1).cgColor, // 主题紫
            NSColor.systemPink.cgColor,
            NSColor.systemOrange.cgColor,
            NSColor.systemTeal.cgColor,
            NSColor.systemYellow.cgColor,
            NSColor.systemGreen.cgColor
        ]
        var cells: [CAEmitterCell] = []
        for color in colors {
            let cell = CAEmitterCell()
            cell.contents = {
                let size: CGFloat = 8
                let img = NSImage(size: NSSize(width: size, height: size))
                img.lockFocus()
                let path = NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size * 0.4))
                NSColor(cgColor: color)?.setFill()
                path.fill()
                img.unlockFocus()
                return img
            }() as Any
            cell.birthRate = 30
            cell.lifetime = 3.0
            cell.velocity = 250
            cell.velocityRange = 150
            cell.emissionLongitude = .pi / 2
            cell.emissionRange = .pi / 4
            cell.spin = 4
            cell.spinRange = 4
            cell.scale = 0.8
            cell.scaleRange = 0.4
            cells.append(cell)
        }
        emitter.emitterCells = cells
        layer?.addSublayer(emitter)

        // 3 秒后停止发射，再 2 秒后移除
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            emitter.birthRate = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            emitter.removeFromSuperlayer()
        }
    }

    // MARK: - 渲染

    private func render() {
        guard let word = service.currentWord else { return }
        let s = service.stats
        // 新单词出现时自动朗读（qwerty：先读再拼，有道真人发音）
        if word.id != lastSpokenWordId && hasStartedTyping {
            lastSpokenWordId = word.id
            if !accentLocale.isEmpty {
                speakCurrentWord()
                // 释义发音：单词朗读后读中文释义（用系统 TTS，中文没有有道 API）
                if transPronunciationEnabled {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        guard let self = self, self.transPronunciationEnabled,
                              self.lastSpokenWordId == word.id else { return }
                        self.state?.speech.speak(word.translation, rate: 0.5, locale: "zh-CN")
                    }
                }
            }
        }
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
        // 前后单词导航内容（第一个词无 prev，最后一个词无 next，可见性由 layout 控制）
        if let prev = service.word(at: service.currentIndex - 1) {
            prevWordView.configure(word: prev.text, translation: prev.translation)
        }
        if let next = service.word(at: service.currentIndex + 1) {
            nextWordView.configure(word: next.text, translation: next.translation)
        }
        // 遮罩：未开始 或 暂停时显示；进行中或结束时隐藏
        overlayView.isHidden = (hasStartedTyping && !isPaused) || !resultCard.isHidden
        // 更新喇叭按钮位置
        needsLayout = true
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

    /// 生成垂直渐变 maskImage：上下透明、中间不透明，用于 NSVisualEffectView 柔化边缘
    private static func makeVerticalGradientMask(size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        let gradient = NSGradient(colorsAndLocations:
            (NSColor(white: 0, alpha: 0), 0),
            (NSColor(white: 0, alpha: 1), 0.22),
            (NSColor(white: 0, alpha: 1), 0.78),
            (NSColor(white: 0, alpha: 0), 1.0)
        )
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 90)
        image.unlockFocus()
        return image
    }
}
