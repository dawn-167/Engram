import Foundation

// MARK: - 间隔重复调度服务（自研 SM-2，思想源自公开的 SuperMemo SM-2 算法描述，未复制 Anki 代码以规避 AGPL）
// Services 层：纯逻辑、无 UI 依赖，可在命令行直接断言测试。

protocol SpacedRepetitionServiceProtocol {
    /// 为新条目创建初始调度状态（立即到期）
    func makeNewItem(id: String, kind: MemoryKind, now: Date) -> MemoryItem
    /// 根据评分推进调度状态，返回更新后的条目
    func schedule(_ item: MemoryItem, grade: ReviewGrade, now: Date) -> MemoryItem
    /// 从条目集合中取出到期队列（到期时间升序，新条目优先）
    func dueQueue(from items: [MemoryItem], now: Date, limit: Int?) -> [MemoryItem]
}

final class SpacedRepetitionService: SpacedRepetitionServiceProtocol {

    // MARK: - 公开方法

    func makeNewItem(id: String, kind: MemoryKind, now: Date) -> MemoryItem {
        // 新条目立即到期，等待第一次学习/复习
        MemoryItem(id: id, kind: kind, dueAt: now)
    }

    func schedule(_ item: MemoryItem, grade: ReviewGrade, now: Date) -> MemoryItem {
        var updated = item
        let quality = grade.rawValue
        updated.totalReviews += 1
        updated.lastReviewed = now

        // 1) 更新难度系数 EF：EF' = EF + (0.1 - (5-q)*(0.08+(5-q)*0.02))
        updated.ease = adjustedEase(current: updated.ease, quality: quality)

        // 2) 根据是否通过决定间隔
        if quality < 3 {
            // 未通过：重置连续成功次数，10 分钟后重新出现（学习阶段）
            updated.repetitions = 0
            updated.intervalDays = 0
            updated.lapses += 1
            updated.dueAt = now.addingTimeInterval(SpacedRepetitionConstants.relearnIntervalSeconds)
        } else {
            updated.repetitions += 1
            updated.intervalDays = nextInterval(reps: updated.repetitions,
                                                 previousInterval: updated.intervalDays,
                                                 ease: updated.ease)
            updated.dueAt = now.addingTimeInterval(updated.intervalDays * 86_400)
        }
        return updated
    }

    func dueQueue(from items: [MemoryItem], now: Date, limit: Int?) -> [MemoryItem] {
        var due = items.filter { $0.isDue(now: now) }
        // 排序：新条目（从未复习）优先，其次按到期时间先后
        due.sort { lhs, rhs in
            if lhs.isNew != rhs.isNew { return lhs.isNew && !rhs.isNew }
            return lhs.dueAt < rhs.dueAt
        }
        if let limit, due.count > limit {
            return Array(due.prefix(limit))
        }
        return due
    }

    // MARK: - 私有方法

    /// 计算调整后的难度系数，下限 1.3
    private func adjustedEase(current: Double, quality: Int) -> Double {
        let c = SpacedRepetitionConstants.self
        let delta = c.easeAdjustStep
            - Double(5 - quality) * (c.easeAdjustScale + Double(5 - quality) * c.easeAdjustScale2)
        return max(c.minimumEase, current + delta)
    }

    /// 计算下一次间隔（天）：第一次 1 天，第二次 6 天，之后 间隔×EF
    private func nextInterval(reps: Int, previousInterval: Double, ease: Double) -> Double {
        let c = SpacedRepetitionConstants.self
        switch reps {
        case 1:
            return c.firstIntervalDays
        case 2:
            return c.secondIntervalDays
        default:
            // 前一次间隔至少为第二次间隔，避免初始值为 0
            let base = max(previousInterval, c.secondIntervalDays)
            return (base * ease).rounded()
        }
    }
}
