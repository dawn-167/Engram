import Foundation

// MARK: - 打字练习状态机（融合 Qwerty Learner 核心机制）
// 核心规则：输错任一字符，整个单词必须重新输入，避免形成错误的肌肉记忆。
// Services 层：纯逻辑、无 UI 依赖，可命令行测试。

/// 单个字符的输入状态（用于 UI 逐字符着色）
enum CharState {
    case pending
    case correct
    case wrong
}

/// 一次按键后的反馈，驱动 UI 响应
enum TypingFeedback: Equatable {
    case accepted
    case wrongAndReset
    case wordCompleted
    case wordRepeated
    case sessionFinished
}

/// 本次打字会话的统计
struct TypingSessionStats: Equatable {
    var completedWords = 0
    var totalWords: Int = 0
    var correctKeyPresses = 0
    var totalKeyPresses = 0
    var errorWords = 0
    var elapsedSeconds: Double = 0

    /// 正确率（0~1）
    var accuracy: Double {
        guard totalKeyPresses > 0 else { return 1 }
        return Double(correctKeyPresses) / Double(totalKeyPresses)
    }

    /// 每分钟正确单词数（WPM，按 5 个字符=1 词的通用口径）
    var wpm: Double {
        guard elapsedSeconds > 0 else { return 0 }
        let minutes = elapsedSeconds / 60.0
        return Double(correctKeyPresses) / 5.0 / minutes
    }
}

protocol TypingServiceProtocol {
    /// 当前正在练习的单词
    var currentWord: WordEntry? { get }
    /// 当前单词每个字符的状态
    func charStates() -> [CharState]
    /// 会话统计
    var stats: TypingSessionStats { get }
    /// 用一组单词开启会话
    func startSession(words: [WordEntry])
    /// 输入一个字符，返回反馈
    func input(character: Character) -> TypingFeedback
    /// 跳过当前单词（计为一次错误）
    func skipCurrent() -> TypingFeedback
}

final class TypingService: TypingServiceProtocol {

    // MARK: - 属性

    private var queue: [WordEntry] = []
    private var index = 0
    private var typedLength = 0
    private var hadWrongThisWord = false
    private var sessionStart = Date()
    private(set) var stats = TypingSessionStats()
    /// 每个单词循环输入次数（qwerty 单词循环：1=不循环；Int.max=无限）
    var loopTimes = 1
    /// 是否忽略大小写（qwerty 高级设置）
    var ignoreCase = true
    private var loopRemaining = 0
    private var advancedWords = 0

    /// 进度（已前进单词 / 总单词）
    var progress: Double {
        guard !queue.isEmpty else { return 0 }
        return Double(advancedWords) / Double(queue.count)
    }

    var currentWord: WordEntry? {
        guard index < queue.count else { return nil }
        return queue[index]
    }

    /// 当前单词在队列中的索引（用于前后单词导航）
    var currentIndex: Int { index }

    /// 队列总单词数
    var totalWords: Int { queue.count }

    /// 获取指定索引的单词（用于前后单词预览）
    func word(at index: Int) -> WordEntry? {
        guard index >= 0, index < queue.count else { return nil }
        return queue[index]
    }

    // MARK: - 公开方法

    func startSession(words: [WordEntry]) {
        queue = words
        index = 0
        typedLength = 0
        hadWrongThisWord = false
        advancedWords = 0
        loopRemaining = max(1, loopTimes)
        stats = TypingSessionStats(totalWords: words.count)
        sessionStart = Date()
    }

    func charStates() -> [CharState] {
        guard let word = currentWord else { return [] }
        return word.text.enumerated().map { position, _ in
            if position < typedLength { return .correct }
            return .pending
        }
    }

    func input(character: Character) -> TypingFeedback {
        guard let word = currentWord else { return .sessionFinished }
        stats.totalKeyPresses += 1
        let target = Array(word.text)

        // 忽略大小写差异，降低挫败感，但仍要求逐字母正确
        guard typedLength < target.count else { return .accepted }
        let isCorrect: Bool
        if ignoreCase {
            isCorrect = String(character).lowercased() == String(target[typedLength]).lowercased()
        } else {
            isCorrect = String(character) == String(target[typedLength])
        }

        guard isCorrect else {
            // Qwerty 核心机制：错误即整词重来，锁定正确肌肉记忆
            typedLength = 0
            hadWrongThisWord = true
            return .wrongAndReset
        }

        typedLength += 1
        stats.correctKeyPresses += 1
        guard typedLength == target.count else { return .accepted }
        return completeCurrentWord()
    }

    func skipCurrent() -> TypingFeedback {
        guard currentWord != nil else { return .sessionFinished }
        stats.errorWords += 1
        return advance()
    }

    /// 跳转到指定索引的单词（qwerty 前后单词导航：SKIP_2_WORD_INDEX）
    func skipToWord(_ newIndex: Int) -> TypingFeedback {
        guard newIndex >= 0, newIndex < queue.count else { return .sessionFinished }
        index = newIndex
        typedLength = 0
        hadWrongThisWord = false
        loopRemaining = max(1, loopTimes)
        advancedWords = max(advancedWords, newIndex)
        return .wordCompleted
    }

    // MARK: - 私有方法

    private func completeCurrentWord() -> TypingFeedback {
        stats.completedWords += 1
        if hadWrongThisWord { stats.errorWords += 1 }
        stats.elapsedSeconds = Date().timeIntervalSince(sessionStart)
        loopRemaining -= 1
        if loopRemaining > 0 {
            // 循环模式：继续重复当前词（不计入进度）
            typedLength = 0
            hadWrongThisWord = false
            return .wordRepeated
        }
        return advance()
    }

    private func advance() -> TypingFeedback {
        advancedWords += 1
        loopRemaining = max(1, loopTimes)
        index += 1
        typedLength = 0
        hadWrongThisWord = false
        if index >= queue.count {
            stats.elapsedSeconds = max(Date().timeIntervalSince(sessionStart), 1)
            return .sessionFinished
        }
        return .wordCompleted
    }
}
