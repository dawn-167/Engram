import Cocoa

// MARK: - Nexus 菜单栏项
// CommonKit Version: 1.0
// 统一的菜单栏图标和菜单模板

public enum NXStatusItem {

    /// 创建标准菜单栏状态项
    /// - Parameters:
    ///   - symbolName: SF Symbol 名称
    ///   - pointSize: 图标大小
    ///   - tooltip: 悬停提示
    /// - Returns: NSStatusItem
    public static func make(symbolName: String,
                            pointSize: CGFloat = 14,
                            tooltip: String) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            let img = NSImage(systemSymbolName: symbolName,
                              accessibilityDescription: tooltip)?
                .withSymbolConfiguration(config)
            img?.isTemplate = true
            button.image = img
            button.imagePosition = .imageOnly
            button.toolTip = tooltip
        }
        return item
    }

    /// 构建标准菜单（显示/隐藏 + 退出）
    /// - Parameters:
    ///   - appName: 应用名称
    ///   - onToggle: 显示/隐藏回调
    ///   - onQuit: 退出回调
    /// - Returns: NSMenu
    public static func makeStandardMenu(appName: String,
                                        onToggle: @escaping () -> Void,
                                        onQuit: @escaping () -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "显示/隐藏 \(appName)", action: #selector(NXMenuAction.toggle), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "退出 \(appName)", action: #selector(NXMenuAction.quit), keyEquivalent: "q")

        NXMenuAction.shared.onToggle = onToggle
        NXMenuAction.shared.onQuit = onQuit
        for item in menu.items {
            item.target = NXMenuAction.shared
        }
        return menu
    }
}

// 菜单动作代理（单例，持有回调）
final class NXMenuAction: NSObject {
    static let shared = NXMenuAction()
    var onToggle: (() -> Void)?
    var onQuit: (() -> Void)?

    @objc func toggle() { onToggle?() }
    @objc func quit() { onQuit?() }
}
