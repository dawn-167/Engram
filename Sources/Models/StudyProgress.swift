import Foundation

// MARK: - 学习统计与持久化根模型
// 纯数据结构，由 ProgressStore 负责读写，Views 不直接操作文件。

/// 单日学习统计（按本地日期聚合）
struct DailyStat: Codable, Identifiable, Equatable {
    /// 日期键，格式 yyyy-MM-dd（本地时区）
    let dateKey: String
    /// 打字练习完成的单词数
    var wordsTyped: Int = 0
    /// 造句完成句数
    var sentencesBuilt: Int = 0
    /// 口语练习句数
    var spoken: Int = 0
    /// 复习卡片数
    var reviewed: Int = 0
    /// 当日新学条目数
    var newLearned: Int = 0
    /// 打字正确按键数（用于正确率统计）
    var keyPressCorrect: Int = 0
    /// 打字总按键数
    var keyPressTotal: Int = 0
    /// 口语发音平均得分（0~100 的累加值，配合 spokenCount 求平均）
    var pronunciationScoreSum: Int = 0
    var pronunciationCount: Int = 0

    var id: String { dateKey }

    /// 当日总练习量
    var totalActions: Int { wordsTyped + sentencesBuilt + spoken + reviewed }
}

/// 用户可配置项
struct UserSettings: Codable, Equatable {
    /// 是否开启按键/操作音效
    var soundEnabled: Bool = true
    /// TTS 语速，0.3~0.6 之间（学习宜慢）
    var speechRate: Float = 0.42
    /// 每日新学目标
    var dailyNewGoal: Int = 20
    /// 每日复习上限
    var dailyReviewLimit: Int = 100
}

/// 持久化到磁盘的根数据对象
struct ProgressData: Codable {
    /// 记忆条目表，key 为条目 id
    var memory: [String: MemoryItem] = [:]
    /// 每日统计，key 为 dateKey
    var daily: [String: DailyStat] = [:]
    /// 连续学习天数
    var streakDays: Int = 0
    /// 最近一次学习的日期键（用于连续天数计算）
    var lastActiveDay: String?
    /// 用户设置
    var settings = UserSettings()
}
