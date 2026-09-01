import Foundation

// MARK: - 学习进度持久化服务（统一记忆状态 + 每日统计 + 连续天数）
// Services 层：唯一允许读写磁盘的服务，Views/App 通过它访问数据，不直接碰文件。

protocol ProgressStoreProtocol {
    /// 当前全部进度数据（只读快照）
    var data: ProgressData { get }
    /// 立即落盘
    func save()
    /// 在临界区内修改数据并自动落盘
    func mutate(_ block: (inout ProgressData) -> Void)
    /// 取某条目的记忆状态
    func memoryItem(for id: String) -> MemoryItem?
    /// 插入或更新记忆条目
    func upsert(_ item: MemoryItem)
    /// 确保条目存在（练习模块登记新学条目），返回当前状态
    func ensureItem(id: String, kind: MemoryKind, now: Date) -> MemoryItem
    /// 累加今日某项练习量并维护连续天数
    func recordToday(action: @escaping (inout DailyStat) -> Void, now: Date)
    /// 获取今日统计
    func todayStat(now: Date) -> DailyStat
}

final class ProgressStore: ProgressStoreProtocol {

    // MARK: - 属性

    private(set) var data: ProgressData
    private let fileURL: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - 初始化

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? ProgressStore.defaultFileURL()
        self.data = ProgressStore.load(from: self.fileURL, decoder: decoder)
        maintainStreak(now: Date())
    }

    // MARK: - 公开方法

    func save() {
        guard let data = try? encoder.encode(data) else {
            NSLog("[Engram] 进度编码失败")
            return
        }
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[Engram] 进度保存失败：\(error.localizedDescription)")
        }
    }

    func mutate(_ block: (inout ProgressData) -> Void) {
        block(&data)
        maintainStreak(now: Date())
        save()
    }

    func memoryItem(for id: String) -> MemoryItem? { data.memory[id] }

    func upsert(_ item: MemoryItem) {
        mutate { $0.memory[item.id] = item }
    }

    func ensureItem(id: String, kind: MemoryKind, now: Date) -> MemoryItem {
        if let existing = data.memory[id] { return existing }
        let fresh = MemoryItem(id: id, kind: kind, dueAt: now)
        mutate { progress in
            progress.memory[id] = fresh
            // 第一次出现计入“新学”
            var stat = progress.daily[Self.dayKey(now)] ?? DailyStat(dateKey: Self.dayKey(now))
            stat.newLearned += 1
            progress.daily[stat.dateKey] = stat
        }
        return fresh
    }

    func recordToday(action: (inout DailyStat) -> Void, now: Date) {
        mutate { progress in
            let key = Self.dayKey(now)
            var stat = progress.daily[key] ?? DailyStat(dateKey: key)
            action(&stat)
            progress.daily[key] = stat
        }
    }

    func todayStat(now: Date) -> DailyStat {
        data.daily[Self.dayKey(now)] ?? DailyStat(dateKey: Self.dayKey(now))
    }

    // MARK: - 私有方法

    /// 维护连续学习天数：今天有记录且与上次活跃日相邻则 +1，同一天不重复加
    private func maintainStreak(now: Date) {
        let today = Self.dayKey(now)
        guard let todayStat = data.daily[today], todayStat.totalActions > 0 else { return }
        guard let last = data.lastActiveDay else {
            data.streakDays = 1
            data.lastActiveDay = today
            return
        }
        if last == today { return }
        let yesterday = Self.dayKey(now.addingTimeInterval(-86_400))
        if last == yesterday {
            data.streakDays += 1
        } else {
            data.streakDays = 1
        }
        data.lastActiveDay = today
    }

    /// 本地日期键 yyyy-MM-dd（用当前时区，保证与用户感知一致）
    static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Engram/progress.json")
    }

    private static func load(from url: URL, decoder: JSONDecoder) -> ProgressData {
        guard let raw = try? Data(contentsOf: url),
              let progress = try? decoder.decode(ProgressData.self, from: raw) else {
            return ProgressData()
        }
        return progress
    }
}
