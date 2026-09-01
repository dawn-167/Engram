import Cocoa
import Carbon.HIToolbox

// MARK: - Engram 应用主体（Nexus life 类成员：菜单栏常驻 + 浮动窗 + 全局热键 + URL Scheme）

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - 常量

    private enum Const {
        static let windowSize = NSSize(width: 940, height: 680)
        static let minWindowSize = NSSize(width: 940, height: 640)
        static let hotKeySignature = OSType(0x454E) // "EN"
    }

    // MARK: - 属性

    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private let appState = AppState()
    private var rootVC: RootViewController?

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupWindow()
        setupStatusItem()
        setupHotKey()
        showWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        NXHotKeyManager.unregister()
    }

    // MARK: - Nexus URL Scheme 接收（必须实现）

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let result = NXURLScheme.parse(url) else { continue }
            showWindow()
            // 支持 nexus-engram://page?name=typing 深链直达模块
            if result.action == "page", let name = result.params["name"] {
                deepLink(to: name)
            }
        }
    }

    private func deepLink(to name: String) {
        let mapping: [String: AppPage] = [
            "home": .home, "typing": .typing, "sentence": .sentence,
            "speaking": .speaking, "review": .review, "stats": .stats
        ]
        if let page = mapping[name] { appState.go(page) }
    }

    // MARK: - 全局热键

    private func setupHotKey() {
        NXHotKeyManager.register(
            keyCode: UInt32(kVK_ANSI_E),
            modifiers: UInt32(controlKey) | UInt32(optionKey),
            signature: Const.hotKeySignature,
            onHotKey: { [weak self] in self?.toggleWindow() }
        )
    }

    // MARK: - 菜单栏（含 Nexus 应用子菜单）

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let image = NSImage(systemSymbolName: "character.book.closed.fill",
                                accessibilityDescription: "Engram")?.withSymbolConfiguration(config)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
        }

        let menu = NSMenu()
        let toggle = NSMenuItem(title: "显示 / 隐藏", action: #selector(toggleWindow), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())

        let nexusItem = NSMenuItem(title: "Nexus 应用", action: nil, keyEquivalent: "")
        nexusItem.submenu = makeNexusAppsMenu()
        menu.addItem(nexusItem)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 Engram", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    private func makeNexusAppsMenu() -> NSMenu {
        let menu = NSMenu(title: "Nexus 应用")
        let knownApps: [(id: String, name: String)] = [
            ("hub", "Nexus Hub"),
            ("keyhub", "KeyHub")
        ]
        var enabledCount = 0
        for app in knownApps {
            let item = NSMenuItem(title: app.name, action: #selector(openNexusApp(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = app.id
            item.isEnabled = NXURLScheme.isAppInstalled(appId: app.id)
            if !item.isEnabled { item.title = "\(app.name)（未安装）" } else { enabledCount += 1 }
            menu.addItem(item)
        }
        if enabledCount == 0 {
            let hint = NSMenuItem(title: "暂无其他已安装应用", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }
        return menu
    }

    @objc private func openNexusApp(_ sender: NSMenuItem) {
        guard let appId = sender.representedObject as? String else { return }
        NXURLScheme.openApp(appId: appId)
    }

    // MARK: - 窗口

    private func setupWindow() {
        let win = NXWindowStyle.makeFloatingWindow(
            size: Const.windowSize,
            title: "Engram",
            tintColor: NSColor(red: 0.424, green: 0.361, blue: 0.906, alpha: 0.12),
            fixedWidth: true
        )
        win.minSize = Const.minWindowSize
        placeOnPreferredScreen(win)

        let container = NXWindowStyle.makeContainerView(in: win)
        let controller = RootViewController(state: appState)
        rootVC = controller
        controller.view.frame = container.bounds
        controller.view.autoresizingMask = [.width, .height]
        container.addSubview(controller.view)
        window = win
    }

    /// 优先把窗口放到外接副屏（非主屏），无副屏时居中到主屏
    private func placeOnPreferredScreen(_ win: NSWindow) {
        let screens = NSScreen.screens
        let external = screens.first { $0 != NSScreen.main } ?? NSScreen.main
        guard let target = external else { win.center(); return }
        let visible = target.visibleFrame
        let origin = NSPoint(
            x: visible.midX - Const.windowSize.width / 2,
            y: visible.midY - Const.windowSize.height / 2
        )
        win.setFrameOrigin(origin)
    }

    // MARK: - 窗口切换

    @objc func toggleWindow() {
        if let win = window, win.isVisible {
            win.orderOut(nil)
        } else {
            showWindow()
        }
    }

    private func showWindow() {
        guard let win = window else { return }
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        // 让打字页在窗口重新获得焦点时夺回第一响应者
        if appState.currentPage == .typing { rootVC?.refocusTyping() }
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
}
