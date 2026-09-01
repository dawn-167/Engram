import Cocoa

// MARK: - 左侧导航栏（模块切换 + 品牌 + 连续天数）
// Views 层：点击仅通过 onSelect 闭包上报，由 App 层决定路由。

final class SidebarView: NSView {

    // MARK: - 属性

    var onSelect: ((AppPage) -> Void)?
    private let stack = NSStackView()
    private var rowButtons: [AppPage: NSButton] = [:]
    private let streakLabel = LabelFactory.label("", font: .systemFont(ofSize: 12, weight: .medium),
                                                 color: Theme.textSecondary)
    private var selectedPage: AppPage = .home

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.04).cgColor
        setupBrand()
        setupNavStack()
        setupFooter()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未使用") }

    // MARK: - 公开方法

    /// 设置当前选中项并刷新样式
    func setSelected(_ page: AppPage) {
        selectedPage = page
        for (itemPage, button) in rowButtons {
            let selected = itemPage == page
            button.layer?.backgroundColor = (selected ? Theme.sidebarSelected : NSColor.clear).cgColor
            button.contentTintColor = selected ? Theme.primary : Theme.textPrimary
        }
    }

    /// 更新底部连续天数与复习角标
    func refresh(streak: Int, dueCount: Int) {
        streakLabel.stringValue = "连续学习 \(streak) 天"
        if let reviewButton = rowButtons[.review] {
            reviewButton.title = dueCount > 0 ? "复习（\(dueCount)）" : "复习"
        }
    }

    // MARK: - 私有方法

    private func setupBrand() {
        let logo = LabelFactory.label("Engram", font: .systemFont(ofSize: 22, weight: .heavy),
                                      color: Theme.primary)
        let subtitle = LabelFactory.label("英语记忆引擎", font: .systemFont(ofSize: 11),
                                          color: Theme.textSecondary)
        addSubview(logo)
        addSubview(subtitle)
        logo.frame = CGRect(x: 20, y: bounds.height - 52, width: 160, height: 28)
        subtitle.frame = CGRect(x: 20, y: bounds.height - 70, width: 160, height: 16)
        logo.autoresizingMask = [.minYMargin]
        subtitle.autoresizingMask = [.minYMargin]
    }

    private func setupNavStack() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 96)
        ])

        for page in AppPage.allCases {
            let button = HandCursorButton()
            button.isBordered = false
            button.focusRingType = .none
            button.title = page.title
            button.font = .systemFont(ofSize: 14, weight: .medium)
            button.image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: page.title)
            button.imagePosition = .imageLeft
            button.alignment = .left
            button.contentTintColor = Theme.textPrimary
            button.target = self
            button.action = #selector(rowClicked(_:))
            button.tag = page.rawValue
            button.wantsLayer = true
            button.layer?.cornerRadius = 8
            NSLayoutConstraint.activate([
                button.heightAnchor.constraint(equalToConstant: 38),
                button.widthAnchor.constraint(equalToConstant: Theme.sidebarWidth - 24)
            ])
            rowButtons[page] = button
            stack.addArrangedSubview(button)
        }
        setSelected(.home)
    }

    private func setupFooter() {
        let hint = LabelFactory.label("⌃⌥E 随时唤出", font: .systemFont(ofSize: 11),
                                      color: Theme.textTertiary)
        addSubview(streakLabel)
        addSubview(hint)
        streakLabel.frame = CGRect(x: 20, y: 56, width: 170, height: 16)
        hint.frame = CGRect(x: 20, y: 34, width: 170, height: 16)
        streakLabel.autoresizingMask = [.maxYMargin]
        hint.autoresizingMask = [.maxYMargin]
    }

    @objc private func rowClicked(_ sender: NSButton) {
        guard let page = AppPage(rawValue: sender.tag) else { return }
        onSelect?(page)
    }
}
