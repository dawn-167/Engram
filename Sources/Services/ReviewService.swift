import Foundation

// MARK: - 复习队列服务（Anki 式翻转卡片 + SM-2 调度，跨模块统一复习）
// Services 层：组合 调度器/进度库/内容库，产出可复习卡片并处理评分，不依赖 UI。

/// 一张可复习卡片（把记忆状态与实际内容解析成 UI 可直接展示的结构）
struct ReviewCard: Equatable {
    let memory: MemoryItem
    let kind: MemoryKind
    /// 正面提示（中文释义或中文句意）
    let prompt: String
    /// 背面答案（英文单词或句子）
    let answer: String
    /// 音标（单词卡片用）
    let phonetic: String
    /// 附加说明（例句/场景）
    let detail: String
}

protocol ReviewServiceProtocol {
    /// 构建当前到期复习队列
    func buildQueue(now: Date) -> [ReviewCard]
    /// 对一张卡片评分并落库，返回更新后的记忆状态
    func grade(_ card: ReviewCard, grade: ReviewGrade, now: Date) -> MemoryItem
}

final class ReviewService: ReviewServiceProtocol {

    // MARK: - 属性

    private let scheduler: SpacedRepetitionServiceProtocol
    private let store: ProgressStoreProtocol
    private let library: ContentLibraryServiceProtocol

    // MARK: - 初始化

    init(scheduler: SpacedRepetitionServiceProtocol,
         store: ProgressStoreProtocol,
         library: ContentLibraryServiceProtocol) {
        self.scheduler = scheduler
        self.store = store
        self.library = library
    }

    // MARK: - 公开方法

    func buildQueue(now: Date) -> [ReviewCard] {
        let due = scheduler.dueQueue(from: Array(store.data.memory.values), now: now, limit: nil)
        return due.compactMap { makeCard(from: $0) }
    }

    func grade(_ card: ReviewCard, grade: ReviewGrade, now: Date) -> MemoryItem {
        let updated = scheduler.schedule(card.memory, grade: grade, now: now)
        store.upsert(updated)
        store.recordToday(action: { $0.reviewed += 1 }, now: now)
        return updated
    }

    // MARK: - 私有方法

    /// 把记忆条目解析成卡片；若对应内容已不存在则跳过
    private func makeCard(from memory: MemoryItem) -> ReviewCard? {
        switch memory.kind {
        case .word:
            guard let word = library.word(by: memory.id) else { return nil }
            return ReviewCard(memory: memory, kind: .word,
                              prompt: word.translation, answer: word.text,
                              phonetic: word.phonetic, detail: word.example)
        case .sentence, .speaking:
            guard let sentence = library.sentence(by: memory.id) else { return nil }
            return ReviewCard(memory: memory, kind: memory.kind,
                              prompt: sentence.translation, answer: sentence.text,
                              phonetic: "", detail: sentence.scene)
        }
    }
}
