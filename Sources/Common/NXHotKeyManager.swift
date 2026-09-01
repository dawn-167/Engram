import Cocoa
import Carbon.HIToolbox

// MARK: - Nexus 全局热键管理
// CommonKit Version: 1.0
// 所有 Nexus 应用统一使用此模块注册全局热键

/// 全局热键管理器
public enum NXHotKeyManager {
    fileprivate static var hotKeyRef: EventHotKeyRef?
    fileprivate static var eventHandlerRef: EventHandlerRef?
    fileprivate static var callback: (() -> Void)?

    /// 注册全局热键
    /// - Parameters:
    ///   - keyCode: 虚拟键码，如 kVK_ANSI_L
    ///   - modifiers: 修饰键位掩码，如 controlKey | optionKey
    ///   - signature: 4字符签名，如 OSType(0x4B52) ("KR")
    ///   - onHotKey: 热键触发回调（在主线程执行）
    public static func register(keyCode: UInt32,
                                modifiers: UInt32,
                                signature: OSType,
                                onHotKey: @escaping () -> Void) {
        callback = onHotKey

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            dvHotKeyHandler, 1, &eventType, nil, &eventHandlerRef
        )
        guard status == noErr else { return }

        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        RegisterEventHotKey(
            keyCode, modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
    }

    /// 注销全局热键
    public static func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = eventHandlerRef { RemoveEventHandler(ref) }
        hotKeyRef = nil
        eventHandlerRef = nil
        callback = nil
    }
}

// C 回调函数（必须是全局函数，不能是实例方法）
private func dvHotKeyHandler(_ nextHandler: EventHandlerCallRef?,
                             _ theEvent: EventRef?,
                             _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    DispatchQueue.main.async {
        NXHotKeyManager.callback?()
    }
    return noErr
}
