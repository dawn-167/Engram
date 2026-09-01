import Foundation

// MARK: - 连词造句服务（融合 Earthworm 核心机制）
// 将英文句子拆成词块并打乱，用户按正确语序点选还原。
// Services 层：纯逻辑、无 UI 依赖，可命令行测试。

protocol SentenceBuildServiceProtocol {
    /// 把句子切分为有序词块（标点附着在相邻词上，不单独成块）
    func tokens(of sentence: SentenceEntry) -> [String]
    /// 打乱词块顺序，保证结果不等于原序；词块过少时直接返回
    func shuffled(_ tokens: [String]) -> [String]
    /// 判断当前已选前缀是否仍然正确（用于即时反馈）
    func isPrefixCorrect(picked: [String], target: [String]) -> Bool
    /// 判断是否完整还原
    func isComplete(picked: [String], target: [String]) -> Bool
}

final class SentenceBuildService: SentenceBuildServiceProtocol {

    // MARK: - 公开方法

    func tokens(of sentence: SentenceEntry) -> [String] {
        // 按空白切分；撇号缩写（don't / I'm）保持完整
        sentence.text
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func shuffled(_ tokens: [String]) -> [String] {
        guard tokens.count > 1 else { return tokens }
        var candidate = tokens
        var attempts = 0
        // 最多尝试若干次，避免极端情况下（大量重复词）死循环
        repeat {
            candidate.shuffle()
            attempts += 1
        } while candidate == tokens && attempts < 20
        return candidate
    }

    func isPrefixCorrect(picked: [String], target: [String]) -> Bool {
        guard picked.count <= target.count else { return false }
        return zip(picked, target).allSatisfy { $0 == $1 }
    }

    func isComplete(picked: [String], target: [String]) -> Bool {
        picked == target
    }
}
