import Cocoa

// MARK: - 全局视觉主题（星云紫学习风，明暗模式自适应）
// Views 层：只提供颜色/字体/度量等视觉常量与便捷构造，不含业务逻辑。

enum Theme {

    // MARK: 颜色

    /// 主色：星云紫
    static let primary = NSColor(red: 0.424, green: 0.361, blue: 0.906, alpha: 1)
    /// 主色按下态（更深）
    static let primaryDeep = NSColor(red: 0.333, green: 0.271, blue: 0.800, alpha: 1)
    /// 正确绿
    static let success = NSColor(red: 0.153, green: 0.682, blue: 0.376, alpha: 1)
    /// 错误红
    static let danger = NSColor(red: 0.906, green: 0.298, blue: 0.235, alpha: 1)
    /// 警示橙
    static let warning = NSColor(red: 0.953, green: 0.612, blue: 0.071, alpha: 1)
    /// 信息蓝
    static let info = NSColor(red: 0.161, green: 0.576, blue: 0.949, alpha: 1)

    /// 卡片背景（不透明，规避半透明在非 Retina 屏的字体模糊问题）
    static let cardBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.16, alpha: 0.92)
            : NSColor(white: 1, alpha: 0.92)
    }

    /// 侧边栏选中态背景
    static let sidebarSelected = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.12)
            : primary.withAlphaComponent(0.14)
    }

    static let sidebarHover = NSColor(white: 0.5, alpha: 0.10)
    static let divider = NSColor.separatorColor.withAlphaComponent(0.35)

    /// 主文字
    static let textPrimary = NSColor.labelColor
    /// 次要文字
    static let textSecondary = NSColor.secondaryLabelColor
    /// 占位/弱化文字
    static let textTertiary = NSColor.tertiaryLabelColor

    // MARK: 字体

    static func titleFont(_ size: CGFloat = 22) -> NSFont {
        .systemFont(ofSize: size, weight: .bold)
    }
    static func heading(_ size: CGFloat = 15) -> NSFont {
        .systemFont(ofSize: size, weight: .semibold)
    }
    static func body(_ size: CGFloat = 13) -> NSFont {
        .systemFont(ofSize: size, weight: .regular)
    }
    static func mono(_ size: CGFloat = 26) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: .semibold)
    }

    // MARK: 度量

    static let cornerRadius: CGFloat = 12
    static let smallCorner: CGFloat = 8
    static let sidebarWidth: CGFloat = 196
    static let pagePadding: CGFloat = 24
    static let elementSpacing: CGFloat = 12

    // MARK: 便捷方法

    /// 生成圆角矩形 CALayer（像素对齐由调用方在布局后处理）
    static func roundedLayer(radius: CGFloat = cornerRadius,
                             fill: NSColor = cardBackground) -> CALayer {
        let layer = CALayer()
        layer.cornerRadius = radius
        layer.backgroundColor = fill.cgColor
        layer.masksToBounds = false
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.08
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: -2)
        return layer
    }
}
