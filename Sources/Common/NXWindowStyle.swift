import Cocoa

// MARK: - Nexus 窗口样式
// CommonKit Version: 1.0
// 统一的毛玻璃浮动窗口创建与配置

public enum NXWindowStyle {

    private static var vibrancyView: NSVisualEffectView?
    private static var tintLayer: CAGradientLayer?

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
        win.isReleasedWhenClosed = false
        win.acceptsMouseMovedEvents = true
        win.minSize = NSSize(width: size.width, height: 400)
        if fixedWidth {
            win.maxSize = NSSize(width: size.width, height: 3000)
        }

        // 毛玻璃背景（underWindowBackground 在深色模式下更深邃）
        let vibrancy = NSVisualEffectView(frame: win.contentLayoutRect)
        vibrancy.material = .underWindowBackground
        vibrancy.blendingMode = .behindWindow
        vibrancy.state = .active
        vibrancy.wantsLayer = true
        vibrancy.layer?.cornerRadius = 12
        vibrancy.layer?.masksToBounds = true
        vibrancy.layer?.borderWidth = 0.5
        vibrancy.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        vibrancy.autoresizingMask = [.width, .height]
        win.contentView = vibrancy
        vibrancyView = vibrancy

        // 主题色渐变叠加层（上浅下深，明暗自适应）
        let tint = NSView(frame: vibrancy.bounds)
        tint.wantsLayer = true
        let gradient = CAGradientLayer()
        gradient.frame = vibrancy.bounds
        gradient.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        updateTintGradient(gradient)
        tint.layer?.addSublayer(gradient)
        tint.autoresizingMask = [.width, .height]
        vibrancy.addSubview(tint)
        tintLayer = gradient

        return win
    }

    /// 更新渐变叠加层颜色（明暗模式切换时调用）
    public static func updateAppearance() {
        guard let gradient = tintLayer else { return }
        updateTintGradient(gradient)
        vibrancyView?.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
    }

    private static func updateTintGradient(_ gradient: CAGradientLayer) {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if isDark {
            // 深色模式：深紫蓝渐变，顶部微亮底部深邃
            gradient.colors = [
                NSColor(red: 0.16, green: 0.14, blue: 0.26, alpha: 0.85).cgColor,
                NSColor(red: 0.08, green: 0.07, blue: 0.14, alpha: 0.92).cgColor
            ]
        } else {
            // 浅色模式：淡紫白渐变
            gradient.colors = [
                NSColor(red: 0.96, green: 0.95, blue: 0.99, alpha: 0.7).cgColor,
                NSColor(red: 0.92, green: 0.91, blue: 0.97, alpha: 0.8).cgColor
            ]
        }
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
    }

    /// 在毛玻璃窗口上添加内容容器视图
    public static func makeContainerView(in window: NSWindow) -> NSView {
        let container = NSView(frame: window.contentLayoutRect)
        container.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(container)
        return container
    }
}
