import Foundation

// MARK: - 单词学习条目（Qwerty Learner 模块数据源）
// Models 层：纯数据结构，只允许简单计算属性，不包含任何文件/网络/UI 逻辑。

/// 内容类型：区分三大练习模块的素材
enum ContentKind: String, Codable {
    case word       // 单词打字
    case sentence   // 连词造句
    case speaking   // 口语练习
}

/// 单个英文单词学习条目
struct WordEntry: Codable, Identifiable, Equatable {
    /// 全局唯一标识，如 "cet4-abandon"
    let id: String
    /// 英文单词，如 "abandon"
    let text: String
    /// 音标，如 "/əˈbændən/"
    let phonetic: String
    /// 中文释义，如 "v. 放弃；抛弃"
    let translation: String
    /// 英文例句
    let example: String
    /// 例句中文翻译
    let exampleZh: String
    /// 所属词库 id
    let deck: String
}

/// 词库元信息
struct Deck: Codable, Identifiable, Equatable {
    /// 词库 id，如 "cet4-core"
    let id: String
    /// 展示名称，如 "四级核心词"
    let name: String
    /// 词库简介
    let description: String
    /// 内容类型
    let kind: ContentKind
}

/// 词库 JSON 文件结构：元信息 + 单词列表
struct WordDeckFile: Codable {
    let deck: Deck
    let words: [WordEntry]
}
