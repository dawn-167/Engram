import Cocoa

// MARK: - 通用 UI 组件（卡片 / 按钮 / 标签 / 进度条 / 悬停基类）
// Views 层：只负责呈现与把用户操作通过 target/action、闭包上报，不做业务判断。

/// 圆角卡片容器
final class CardView: NSView {
    private let bgLayer = CALayer()
    private let fill: NSColor

    init(fill: NSColor = Theme.cardBackground) {
        self.fill = fill
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        bgLayer.cornerRadius = Theme.cornerRadius
        bgLayer.backgroundColor = fill.cgColor
        bgLayer.borderWidth = 1
        bgLayer.borderColor = Theme.cardBorder.cgColor
        bgLayer.shadowColor = NSColor.black.cgColor
        bgLayer.shadowOpacity = 0.07
        bgLayer.shadowRadius = 7
        bgLayer.shadowOffset = CGSize(width: 0, height: -2)
        layer?.addSublayer(bgLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未使用") }

    override func layout() {
        super.layout()
        bgLayer.frame = bounds
        // 动态颜色（明暗模式）需要在布局时重新解析 cgColor
        bgLayer.backgroundColor = fill.cgColor
        bgLayer.borderColor = Theme.cardBorder.cgColor
    }
}

/// 支持悬停高亮与手型光标的可点击视图基类
class HoverView: NSView {
    var onClick: (() -> Void)?
    private var isHovered = false
    private let cardLayer = CALayer()
    private let hoverLayer = CALayer()
    private let cardStyle: Bool

    init(frame frameRect: NSRect = .zero, cardStyle: Bool = true) {
        self.cardStyle = cardStyle
        super.init(frame: frameRect)
        wantsLayer = true
        if cardStyle {
            cardLayer.cornerRadius = Theme.cornerRadius
            cardLayer.backgroundColor = Theme.cardBackground.cgColor
            cardLayer.shadowColor = NSColor.black.cgColor
            cardLayer.shadowOpacity = 0.07
            cardLayer.shadowRadius = 7
            cardLayer.shadowOffset = CGSize(width: 0, height: -2)
            layer?.addSublayer(cardLayer)
        }
        hoverLayer.backgroundColor = NSColor.black.withAlphaComponent(0.05).cgColor
        hoverLayer.cornerRadius = Theme.cornerRadius
        hoverLayer.opacity = 0
        layer?.addSublayer(hoverLayer)
        updateTrackingAreas()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未使用") }

    override func layout() {
        super.layout()
        cardLayer.frame = bounds
        hoverLayer.frame = bounds
        if cardStyle {
            cardLayer.backgroundColor = Theme.cardBackground.cgColor
        }
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
        hoverLayer.opacity = 1
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        hoverLayer.opacity = 0
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseUp(with event: NSEvent) {
        guard isHovered, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
    }
}

/// 悬停时显示小手光标的按钮（所有可点击按钮的基类）
/// 用 resetCursorRects 而非 push/pop，避免光标堆栈不平衡导致回不到箭头
class HandCursorButton: NSButton {
    override func resetCursorRects() {
        if isEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}

/// 主按钮样式工厂
enum ButtonFactory {
    /// 实心强调按钮
    static func primary(_ title: String, target: AnyObject?, action: Selector) -> HandCursorButton {
        let button = HandCursorButton(title: title, target: target, action: action)
        button.bezelStyle = .inline
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.contentTintColor = .white
        button.wantsLayer = true
        button.layer?.backgroundColor = Theme.primary.cgColor
        button.layer?.cornerRadius = 8
        button.layer?.shadowColor = Theme.primary.cgColor
        button.layer?.shadowOpacity = 0.35
        button.layer?.shadowRadius = 6
        button.layer?.shadowOffset = CGSize(width: 0, height: 2)
        button.isBordered = false
        button.focusRingType = .none
        return button
    }

    /// 描边次按钮
    static func ghost(_ title: String, target: AnyObject?, action: Selector) -> HandCursorButton {
        let button = HandCursorButton(title: title, target: target, action: action)
        button.bezelStyle = .inline
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.contentTintColor = Theme.textPrimary
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.layer?.cornerRadius = 8
        button.layer?.borderWidth = 1
        button.layer?.borderColor = Theme.divider.cgColor
        button.isBordered = false
        button.focusRingType = .none
        return button
    }
}

/// 只读文本标签工厂
enum LabelFactory {
    static func label(_ text: String, font: NSFont = Theme.body(),
                      color: NSColor = Theme.textPrimary, align: NSTextAlignment = .left) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.alignment = align
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.isSelectable = false
        return label
    }
}

/// 线性进度条
final class ProgressBar: NSView {
    private let track = CALayer()
    private let fill = CALayer()
    private var progress: Double = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        track.cornerRadius = 4
        track.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor
        fill.cornerRadius = 4
        fill.backgroundColor = Theme.primary.cgColor
        layer?.addSublayer(track)
        layer?.addSublayer(fill)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未使用") }

    func setProgress(_ value: Double, color: NSColor = Theme.primary) {
        progress = min(1, max(0, value))
        fill.backgroundColor = color.cgColor
        needsLayout = true
    }

    override func layout() {
        super.layout()
        track.frame = bounds
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * CGFloat(progress), height: bounds.height)
    }
}
