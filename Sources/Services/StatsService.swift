import Foundation

// MARK: - 统计聚合服务（把进度数据加工成首页仪表盘所需的汇总结构）
// Services 层：纯计算，无 UI、无磁盘写入。

/// 首页仪表盘汇总数据
struct DashboardSummary: Equatable {
    var dueCount: Int = 0
    var learnedTotal: Int = 0
    var masteredTotal: Int = 0
    var streakDays: Int = 0
    var todayActions: Int = 0
    var todayNewLearned: Int = 0
    var dailyNewGoal: Int = 20
    var weekly: [DailyStat] = []
    var typingAccuracy: Double = 1
    var averagePronunciation: Int = 0
    var totalTyped: Int = 0
    var totalSentences: Int = 0
    var totalSpoken: Int = 0
    var totalReviewed: Int = 0

    /// 今日新学目标完成比例（0~1）
    var goalProgress: Double {
        guard dailyNewGoal > 0 else { return 1 }
        return min(1, Double(todayNewLearned) / Double(dailyNewGoal))
    }
}

protocol StatsServiceProtocol {
    /// 依据当前进度生成仪表盘汇总
    func summary(now: Date) -> DashboardSummary
}

final class StatsService: StatsServiceProtocol {

    // MARK: - 属性

    private let store: ProgressStoreProtocol
    private let library: ContentLibraryServiceProtocol
    /// 连续成功复习达到该次数即视为“已掌握”
    private let masteredRepetitionThreshold = 3

    // MARK: - 初始化

    init(store: ProgressStoreProtocol, library: ContentLibraryServiceProtocol) {
        self.store = store
        self.library = library
    }

    // MARK: - 公开方法

    func summary(now: Date) -> DashboardSummary {
        let progress = store.data
        var result = DashboardSummary()
        result.dailyNewGoal = progress.settings.dailyNewGoal
        result.streakDays = progress.streakDays

        let items = Array(progress.memory.values)
        result.dueCount = items.filter { $0.isDue(now: now) }.count
        result.learnedTotal = items.count
        result.masteredTotal = items.filter { $0.repetitions >= masteredRepetitionThreshold }.count

        let today = store.todayStat(now: now)
        result.todayActions = today.totalActions
        result.todayNewLearned = today.newLearned

        result.weekly = lastSevenDays(now: now)
        result.typingAccuracy = overallTypingAccuracy(result.weekly)
        result.averagePronunciation = overallPronunciation(result.weekly)

        result.totalTyped = progress.daily.values.reduce(0) { $0 + $1.wordsTyped }
        result.totalSentences = progress.daily.values.reduce(0) { $0 + $1.sentencesBuilt }
        result.totalSpoken = progress.daily.values.reduce(0) { $0 + $1.spoken }
        result.totalReviewed = progress.daily.values.reduce(0) { $0 + $1.reviewed }
        return result
    }

    // MARK: - 私有方法

    /// 取最近 7 天（含今天）的统计，缺失日期补零
    private func lastSevenDays(now: Date) -> [DailyStat] {
        (0..<7).reversed().map { offset in
            let day = now.addingTimeInterval(Double(-offset) * 86_400)
            let key = ProgressStore.dayKey(day)
            return store.data.daily[key] ?? DailyStat(dateKey: key)
        }
    }

    private func overallTypingAccuracy(_ week: [DailyStat]) -> Double {
        let correct = week.reduce(0) { $0 + $1.keyPressCorrect }
        let total = week.reduce(0) { $0 + $1.keyPressTotal }
        guard total > 0 else { return 1 }
        return Double(correct) / Double(total)
    }

    private func overallPronunciation(_ week: [DailyStat]) -> Int {
        let sum = week.reduce(0) { $0 + $1.pronunciationScoreSum }
        let count = week.reduce(0) { $0 + $1.pronunciationCount }
        guard count > 0 else { return 0 }
        return sum / count
    }
}
