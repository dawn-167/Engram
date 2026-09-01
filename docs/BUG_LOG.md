# 缺陷记录与修复日志 — Engram

记录开发与验证过程中发现的问题、根因与修复方案，供后续维护参考。

---

## BUG-001：逻辑测试顶层代码编译错误

**严重度**：高（阻塞测试）
**发现阶段**：逻辑层测试编写
**现象**：`Tests/LogicTests.swift` 顶层直接调用 `try runAll()`，编译报错 "expressions are not allowed at the top level"。
**根因**：Swift 仅允许 `main.swift` 包含顶层可执行代码，普通 `.swift` 文件顶层只能有声明。
**修复**：改为 `@main enum LogicTestRunner { static func main() throws { try runAll() } }`。
**回归**：42 项断言全部通过。

---

## BUG-002：ProgressStore 对非可选 String 做 `if let` 编译错误

**严重度**：中
**发现阶段**：Services 层编写
**现象**：`if let dayKey = stat.dateKey` 编译报错，因为 `dateKey` 是 `let` 非可选 `String`。
**根因**：误把非可选值当可选解包。
**修复**：直接使用 `stat.dateKey`，移除 `if let`。

---

## BUG-003：发音评分 LCS 空输入运行时崩溃（关键）

**严重度**：致命（App 闪退）
**发现阶段**：逻辑层测试 / 边界用例
**现象**：当语音识别结果为空字符串时，App 崩溃，报错 "Range requires lowerBound <= upperBound"。
**根因**：LCS 填表使用闭区间 `1...spoken.count`，当 `spoken.count == 0` 时形成 `1...0` 非法区间触发 trap。
**修复**：改为半开区间 `1..<(spoken.count + 1)`，空输入时循环安全跳过，返回 0 分。
**回归**：新增空识别用例，评分返回 accuracyPercent=0、wpm=0、missedWords=目标全部词。
**经验**：调试时 stdout 管道缓冲导致崩溃前 print 丢失，需 `setbuf(stdout, nil)` 才能看到崩溃前日志。

---

## BUG-004：Swift 6 并发数据竞争告警

**严重度**：中（零警告质量门）
**发现阶段**：全量编译
**现象**：SpeechService / SpeechRecognitionService 涉及 AVSpeechSynthesizer、AVAudioEngine 等非 Sendable 类型，Swift 6 并发检查告警。
**根因**：Service 约定主线程调用，但编译器无法静态证明。
**修复**：
- 两个 protocol 与实现类标注 `@MainActor`。
- AVSpeechSynthesizer 用 `nonisolated(unsafe)` 显式标注（约定仅主线程访问）。
- delegate 回调方法标 `nonisolated`，内部用 `Task { @MainActor in }` 复位状态。
- 音频 tap / 识别回调统一切主线程。
**回归**：全量编译零警告。

---

## BUG-005：中文输入法下打字页按键字符错乱

**严重度**：高（核心功能不可用）
**发现阶段**：副屏实机验证（CGEvent 投递按键模拟用户输入）
**现象**：在中文拼音输入法激活状态下，打字页收到的 `event.charactersIgnoringModifiers` 可能为空或处于合成态，导致按键不响应或判定为错误字母（正确率掉到 0%）。
**根因**：`KeyboardCatcher.keyDown` 依赖 `event.charactersIgnoringModifiers` 取字符，中文 IME 合成态下该字段不可靠。
**修复**：`KeyboardCatcher` 改为直接按 `event.keyCode`（虚拟键码）映射为小写字母 / Tab，使用固定 ANSI 键码表，完全绕过输入法合成层。非字母键兜底仍走 `charactersIgnoringModifiers`。
**验证**：投递 "abandon" 后正确完成第 1 词并自动进到第 2 词（ability），WPM/正确率正常；投递 "abz"（a,b 正确 + z 错误）后整词重置，正确率按累计口径正确下降。
**经验**：打字训练类应用应按物理键码而非字符取键，这是 Qwerty Learner 等同类工具的通用做法。

---

## BUG-006：ReviewPageView 存储属性名 `isFlipped` 与 NSView 协议冲突

**严重度**：中（编译错误）
**发现阶段**：全量编译
**现象**：`private var isFlipped = false` 编译报错 "overriding property must be as accessible as its enclosing type" / "cannot override with a stored property"。
**根因**：`NSView` 已有只读计算属性 `isFlipped`，存储属性同名冲突。
**修复**：存储属性重命名为 `cardFlipped`，`override var isFlipped: Bool { true }` 保留。

---

## BUG-007：main.swift 顶层调用 @MainActor 隔离的 AppDelegate 初始化

**严重度**：高（编译错误）
**发现阶段**：全量编译
**现象**：`let delegate = AppDelegate()` 报错 "call to main actor-isolated initializer in a synchronous nonisolated context"。
**根因**：AppDelegate 标注 `@MainActor`（持有 @MainActor 的 AppState / SpeechService），而 main.swift 顶层上下文非隔离。
**修复**：用 `MainActor.assumeIsolated { ... }` 包裹入口代码（需 macOS 14+，同步将最低系统要求从 13.0 提升到 14.0）。
**说明**：`MainActor.assumeIsolated` 是同步 API，适合 main.swift 这种已知运行在主线程的入口。

---

## 验证环境

- macOS 15.7.4（Apple Silicon arm64）
- Swift 6.1.2（swiftlang-6.1.2，target arm64-apple-macosx15.0）
- 双屏：主 Sidecar Display（AirPlay）+ 副屏 DELL P2422H
- 验证方式：副屏启动 + 窗口截图 + CGEvent 投递键盘/鼠标事件模拟交互 + 逻辑层 42 项断言
