import Foundation

// MARK: - 发音评分（ChatterPal 多维评估的离线、零云依赖实现）
// 不依赖任何云 API：把系统语音识别出的文本与目标句做词级对齐，
// 输出准确度、语速(WPM)、漏词/多词与评级。纯逻辑，可命令行测试。

/// 发音评级
enum PronunciationLevel: String {
    case excellent  // 90~100
    case good       // 75~89
    case fair       // 55~74
    case poor       // 0~54

    var displayName: String {
        switch self {
        case .excellent: return "优秀"
        case .good: return "良好"
        case .fair: return "及格"
        case .poor: return "需练习"
        }
    }

    static func from(percent: Int) -> PronunciationLevel {
        switch percent {
        case 90...100: return .excellent
        case 75..<90: return .good
        case 55..<75: return .fair
        default: return .poor
        }
    }
}

/// 一次发音评分结果
struct PronunciationResult: Equatable {
    /// 总准确度（0~100）
    let accuracyPercent: Int
    /// 目标句中被正确读出的词（按顺序）
    let matchedWords: [String]
    /// 目标句中漏掉/读错的词
    let missedWords: [String]
    /// 识别结果中多出的词
    let extraWords: [String]
    /// 每分钟词数（流利度）
    let wpm: Int
    /// 评级
    let level: PronunciationLevel
}

protocol PronunciationScorerProtocol {
    /// - Parameters:
    ///   - target: 目标英文句子
    ///   - recognized: 语音识别出的文本
    ///   - duration: 录音时长（秒）
    func score(target: String, recognized: String, duration: TimeInterval) -> PronunciationResult
}

final class PronunciationScorer: PronunciationScorerProtocol {

    // MARK: - 公开方法

    func score(target: String, recognized: String, duration: TimeInterval) -> PronunciationResult {
        let targetWords = Self.normalize(target)
        let spokenWords = Self.normalize(recognized)

        let alignment = Self.align(target: targetWords, spoken: spokenWords)
        let matched = alignment.matched
        let missed = alignment.missed
        let extra = alignment.extra

        let percent: Int
        if targetWords.isEmpty {
            percent = 0
        } else {
            // 命中占主导，同时对多余词做轻微惩罚，避免“多读也满分”
            let hitRatio = Double(matched.count) / Double(targetWords.count)
            let extraPenalty = min(0.15, Double(extra.count) / Double(targetWords.count) * 0.5)
            percent = Int((hitRatio - extraPenalty * 0.3).clamped(to: 0...1) * 100)
        }

        let minutes = max(duration / 60.0, 1.0 / 60.0)
        let wpm = Int(Double(spokenWords.count) / minutes)

        return PronunciationResult(
            accuracyPercent: percent,
            matchedWords: matched,
            missedWords: missed,
            extraWords: extra,
            wpm: wpm,
            level: PronunciationLevel.from(percent: percent)
        )
    }

    // MARK: - 私有方法

    /// 归一化：小写、去标点、按词切分
    static func normalize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// 最长公共子序列对齐，得到 命中/漏词/多词
    static func align(target: [String], spoken: [String])
        -> (matched: [String], missed: [String], extra: [String]) {
        let row = Array(repeating: 0, count: spoken.count + 1)
        var lcsTable = Array(repeating: row, count: target.count + 1)

        // 填表：LCS 长度（用半开区间，spoken 为空时 1..<1 安全跳过）
        for i in 1..<(target.count + 1) {
            for j in 1..<(spoken.count + 1) {
                if target[i - 1] == spoken[j - 1] {
                    lcsTable[i][j] = lcsTable[i - 1][j - 1] + 1
                } else {
                    lcsTable[i][j] = max(lcsTable[i - 1][j], lcsTable[i][j - 1])
                }
            }
        }

        // 回溯，标记 spoken 中哪些词被匹配
        var spokenMatched = Array(repeating: false, count: spoken.count)
        var targetMatched = Array(repeating: false, count: target.count)
        var i = target.count, j = spoken.count
        while i > 0 && j > 0 {
            if target[i - 1] == spoken[j - 1] {
                spokenMatched[j - 1] = true
                targetMatched[i - 1] = true
                i -= 1; j -= 1
            } else if lcsTable[i - 1][j] >= lcsTable[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }

        let matched = target.enumerated().filter { targetMatched[$0.offset] }.map { $0.element }
        let missed = target.enumerated().filter { !targetMatched[$0.offset] }.map { $0.element }
        let extra = spoken.enumerated().filter { !spokenMatched[$0.offset] }.map { $0.element }
        return (matched, missed, extra)
    }
}

private extension Comparable {
    /// 将值限制在给定区间内
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
