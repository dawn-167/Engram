import Cocoa

// MARK: - Nexus 窗口样式
// CommonKit Version: 1.0
// 统一的毛玻璃浮动窗口创建与配置

public enum NXWindowStyle {

    /// 创建 Nexus 标准毛玻璃浮动窗口
    /// - Parameters:
    ///   - size: 窗口内容尺寸
    ///   - title: 窗口标题
    ///   - tintColor: 主题色叠加层颜色（alpha 建议 0.15）
    ///   - fixedWidth: 是否固定宽度（只允许纵向拉升）
    /// - Returns: 配置好的 NSWindow
    public static func makeFloatingWindow(size: NSSize,
                                          title: String,
                                          tintColor: NSColor = NSColor(red: 0.75, green: 0.95, blue: 0.80, alpha: 0.15),
                                          fixedWidth: Bool = true) -> NSWindow {
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        win.title = title
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.titlebarSeparatorStyle = .none
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.acceptsMouseMovedEvents = true
        win.minSize = NSSize(width: size.width, height: 400)
        if fixedWidth {
            win.maxSize = NSSize(width: size.width, height: 3000)
        }

        // 毛玻璃背景
        let vibrancy = NSVisualEffectView(frame: win.contentLayoutRect)
        vibrancy.material = .popover
        vibrancy.blendingMode = .behindWindow
        vibrancy.state = .active
        vibrancy.wantsLayer = true
        vibrancy.layer?.cornerRadius = 12
        vibrancy.layer?.masksToBounds = true
        vibrancy.layer?.borderWidth = 0.5
        vibrancy.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        vibrancy.autoresizingMask = [.width, .height]
        win.contentView = vibrancy

        // 主题色叠加层
        let tint = NSView(frame: vibrancy.bounds)
        tint.wantsLayer = true
        tint.layer?.backgroundColor = tintColor.cgColor
        tint.autoresizingMask = [.width, .height]
        vibrancy.addSubview(tint)

        return win
    }

    /// 在毛玻璃窗口上添加内容容器视图
    public static func makeContainerView(in window: NSWindow) -> NSView {
        let container = NSView(frame: window.contentLayoutRect)
        container.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(container)
        return container
    }
}
