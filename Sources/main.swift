import Cocoa

// MARK: - Engram 应用入口（Nexus 标准 main.swift）
// AppDelegate 与 AppState 均为主线程隔离，顶层入口显式假定运行在 MainActor。

setbuf(stdout, nil) // 调试期关闭 stdout 缓冲，确保 print 立即可见

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
