import Foundation

// MARK: - 句子学习条目（Earthworm 造句 / ChatterPal 口语共用数据源）
// Models 层：纯数据结构。分词、打乱等逻辑放在 Services 层。

/// 课程难度分级（对应 ChatterPal 的初/中/高三级难度）
enum LessonLevel: String, Codable, CaseIterable {
    case beginner
    case intermediate
    case advanced

    /// 中文展示名
    var displayName: String {
        switch self {
        case .beginner: return "初级"
        case .intermediate: return "中级"
        case .advanced: return "高级"
        }
    }
}

/// 单个英文句子学习条目（造句与口语模块共用）
struct SentenceEntry: Codable, Identifiable, Equatable {
    /// 全局唯一标识，如 "daily-001"
    let id: String
    /// 英文原句，如 "How do I get to the station?"
    let text: String
    /// 中文翻译，如 "去车站怎么走？"
    let translation: String
    /// 场景标签，如 "travel / business / daily"
    let scene: String
    /// 难度等级
    let level: LessonLevel
}

/// 句库 JSON 文件结构：元信息 + 句子列表
struct SentenceDeckFile: Codable {
    let deck: Deck
    let sentences: [SentenceEntry]
}
