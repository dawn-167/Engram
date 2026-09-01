import Cocoa

// MARK: - 隐形键盘捕获视图（作为第一响应者接收按键，不拦截鼠标）
// Views 层：仅把物理按键映射为字符后转发给闭包，无业务逻辑。
// 直接按虚拟键码映射为 ASCII 字母，保证在任意输入法（含中文拼音）下都稳定取键。

final class KeyboardCatcher: NSView {

    /// 收到字符时回调（字母或 Tab）
    var onKey: ((Character) -> Void)?

    /// ANSI 物理键码到小写字母 / Tab 的固定映射（US 布局，打字训练不随输入法变化）
    private static let keyMap: [UInt16: Character] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
        8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
        16: "y", 17: "t", 31: "o", 32: "u", 34: "i", 35: "p", 37: "l",
        38: "j", 40: "k", 45: "n", 46: "m",
        48: "\t", // Tab
        36: "\r"  // Return/Enter（开始/暂停切换）
    ]

    override var acceptsFirstResponder: Bool { true }

    /// 不参与鼠标命中测试，避免遮挡下层按钮
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func keyDown(with event: NSEvent) {
        // 优先用物理键码，规避输入法合成导致的字符缺失/错乱
        if let mapped = Self.keyMap[event.keyCode] {
            onKey?(mapped)
            return
        }
        // 其余可打印字符兜底（理论上打字页只需要字母与 Tab）
        guard let text = event.charactersIgnoringModifiers, let char = text.first,
              char.isLetter || char == "\t" || char == "\r" || char == "\n" else { return }
        onKey?(Character(String(char).lowercased()))
    }
}
