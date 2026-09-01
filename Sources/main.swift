import Cocoa

// MARK: - Engram 应用入口（Nexus 标准 main.swift）
// AppDelegate 与 AppState 均为主线程隔离，顶层入口显式假定运行在 MainActor。

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
