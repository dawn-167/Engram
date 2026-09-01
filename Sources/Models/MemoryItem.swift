import Foundation

// MARK: - 统一记忆条目（跨模块共享的间隔重复状态，融合 Anki 核心思想）
// 任何模块（打字/造句/口语）练习过的条目都会生成/更新同一个 MemoryItem，
// 到期后统一进入「复习」模块 —— 实现跨模块共享的记忆曲线。
// 调度算法本身在 SpacedRepetitionService 中实现，本结构只存状态。

/// 记忆条目来源模块
enum MemoryKind: String, Codable {
    case word       // 单词打字
    case sentence   // 连词造句
    case speaking   // 口语练习
}

/// 复习评分四档（映射到 SM-2 的 0~5 质量分）
enum ReviewGrade: Int, CaseIterable {
    case again = 1   // 完全想不起来
    case hard = 3    // 想起来了但很吃力
    case good = 4    // 正常回忆
    case easy = 5    // 轻松回忆

    /// 按钮中文文案
    var displayName: String {
        switch self {
        case .again: return "忘记"
        case .hard: return "困难"
        case .good: return "良好"
        case .easy: return "简单"
        }
    }
}

/// 单个学习条目的间隔重复调度状态（SM-2 状态量）
struct MemoryItem: Codable, Identifiable, Equatable {
    /// 条目唯一 id（与 WordEntry/SentenceEntry 的 id 对齐）
    let id: String
    /// 来源模块
    let kind: MemoryKind
    /// 成功复习次数（连续）
    var repetitions: Int = 0
    /// 难度系数 Ease Factor，初始 2.5，下限 1.3
    var ease: Double = SpacedRepetitionConstants.initialEase
    /// 当前间隔（天）
    var intervalDays: Double = 0
    /// 下次到期时间
    var dueAt: Date
    /// 上次复习时间
    var lastReviewed: Date?
    /// 累计遗忘次数（lapses）
    var lapses: Int = 0
    /// 累计复习次数
    var totalReviews: Int = 0

    /// 是否为从未复习过的新条目
    var isNew: Bool { totalReviews == 0 }

    /// 当前是否到期（含已过期）
    func isDue(now: Date) -> Bool { dueAt <= now }
}

/// SM-2 算法常量集中管理，避免魔法数字
enum SpacedRepetitionConstants {
    static let initialEase: Double = 2.5
    static let minimumEase: Double = 1.3
    static let firstIntervalDays: Double = 1.0
    static let secondIntervalDays: Double = 6.0
    /// 学习阶段（尚未通过第一次）答错后的重现间隔，单位秒（10 分钟后再次出现）
    static let relearnIntervalSeconds: TimeInterval = 10 * 60
    static let easeAdjustStep: Double = 0.1
    static let easeAdjustScale: Double = 0.08
    static let easeAdjustScale2: Double = 0.02
}
