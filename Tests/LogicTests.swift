import Foundation

// MARK: - Services 纯逻辑层命令行测试（不引入 XCTest，swiftc 直接编译运行）
// 运行：scripts/run_logic_tests.sh

private var failureCount = 0
private var caseCount = 0

private func expect(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    caseCount += 1
    if !condition {
        failureCount += 1
        print("❌ 失败 [\(file):\(line)] \(message)")
    }
}

private func expectApprox(_ actual: Double, _ expected: Double, tolerance: Double, _ message: String) {
    expect(abs(actual - expected) <= tolerance, "\(message)（实际 \(actual)，期望 \(expected)）")
}

// MARK: - SM-2 调度测试

private func testSpacedRepetition() {
    let service = SpacedRepetitionService()
    let now = Date(timeIntervalSince1970: 1_000_000)

    var item = service.makeNewItem(id: "w1", kind: .word, now: now)
    expect(item.isDue(now: now), "新条目应立即到期")
    expect(item.ease == 2.5, "初始 EF 应为 2.5")

    // 第一次 good → 间隔 1 天
    item = service.schedule(item, grade: .good, now: now)
    expect(item.repetitions == 1, "good 后 reps=1")
    expectApprox(item.intervalDays, 1, tolerance: 0.001, "第一次通过间隔 1 天")
    expect(!item.isDue(now: now), "当天不应再次到期")

    // 第二次 good → 间隔 6 天
    let day1 = now.addingTimeInterval(86_400)
    item = service.schedule(item, grade: .good, now: day1)
    expect(item.repetitions == 2, "第二次 good 后 reps=2")
    expectApprox(item.intervalDays, 6, tolerance: 0.001, "第二次通过间隔 6 天")

    // 第三次 good → 间隔 = 6 × EF
    let day7 = day1.addingTimeInterval(6 * 86_400)
    item = service.schedule(item, grade: .good, now: day7)
    expect(item.repetitions == 3, "第三次 good 后 reps=3")
    expectApprox(item.intervalDays, 6 * 2.5, tolerance: 0.001, "第三次间隔 = 6×EF=15 天")

    // again → 重置 reps，lapses+1，10 分钟后到期
    item = service.schedule(item, grade: .again, now: day7)
    expect(item.repetitions == 0, "忘记后 reps 重置为 0")
    expect(item.lapses == 1, "忘记后 lapses=1")
    expect(item.isDue(now: day7.addingTimeInterval(11 * 60)), "10 分钟后应到期")

    // EF 下限 1.3：连续 again/hard 不会跌破
    var weak = service.makeNewItem(id: "w2", kind: .word, now: now)
    for _ in 0..<10 { weak = service.schedule(weak, grade: .hard, now: now.addingTimeInterval(86_400)) }
    expect(weak.ease >= 1.3 - 0.0001, "EF 不得低于 1.3，实际 \(weak.ease)")

    // easy 会提升 EF
    var easy = service.makeNewItem(id: "w3", kind: .word, now: now)
    let before = easy.ease
    easy = service.schedule(easy, grade: .easy, now: now)
    expect(easy.ease > before, "easy 后 EF 应上升")
}

// MARK: - 连词造句测试

private func testSentenceBuild() {
    let service = SentenceBuildService()
    let sentence = SentenceEntry(id: "s1", text: "I don't like it.",
                                 translation: "我不喜欢它。", scene: "daily", level: .beginner)
    let tokens = service.tokens(of: sentence)
    expect(tokens == ["I", "don't", "like", "it."], "缩写不应被拆开，实际 \(tokens)")

    let shuffled = service.shuffled(tokens)
    expect(Set(shuffled) == Set(tokens), "打乱后词块集合不变")

    expect(service.isPrefixCorrect(picked: ["I"], target: tokens), "正确前缀")
    expect(!service.isPrefixCorrect(picked: ["like"], target: tokens), "错误前缀")
    expect(service.isComplete(picked: tokens, target: tokens), "完全一致才算完成")
}

// MARK: - 发音评分测试

private func testPronunciation() {
    let scorer = PronunciationScorer()

    let perfect = scorer.score(target: "How are you", recognized: "how are you", duration: 3)
    expect(perfect.accuracyPercent == 100, "完全正确应 100 分，实际 \(perfect.accuracyPercent)")
    expect(perfect.missedWords.isEmpty, "满分无漏词")
    expect(perfect.wpm == 60, "3 秒读 3 词 = 60WPM，实际 \(perfect.wpm)")

    let missed = scorer.score(target: "How are you", recognized: "how you", duration: 3)
    expect(missed.missedWords == ["are"], "应识别漏词 are，实际 \(missed.missedWords)")
    expect(missed.accuracyPercent < 100, "漏词应扣分")

    let extra = scorer.score(target: "good morning", recognized: "good morning everyone", duration: 2)
    expect(extra.extraWords == ["everyone"], "应识别多读词，实际 \(extra.extraWords)")

    let empty = scorer.score(target: "Nice", recognized: "", duration: 1)
    expect(empty.accuracyPercent == 0, "无识别结果应 0 分")
}

// MARK: - 持久化与连续天数测试

private func testProgressStore() throws {
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("engram_test_\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: temp) }

    let store = ProgressStore(fileURL: temp)
    let now = Date()
    let item = store.ensureItem(id: "w-cat", kind: .word, now: now)
    expect(item.id == "w-cat", "登记新条目成功")
    expect(store.data.daily[ProgressStore.dayKey(now)]?.newLearned == 1, "新学计数 +1")

    // 再次 ensure 同一 id 不应重复计新学
    _ = store.ensureItem(id: "w-cat", kind: .word, now: now)
    expect(store.data.daily[ProgressStore.dayKey(now)]?.newLearned == 1, "同一条目不重复计新学")

    store.recordToday(action: { $0.wordsTyped += 1 }, now: now)
    expect(store.todayStat(now: now).wordsTyped == 1, "今日打字计数累加")

    // 重新从磁盘加载，数据应保留
    let reloaded = ProgressStore(fileURL: temp)
    expect(reloaded.memoryItem(for: "w-cat") != nil, "重启后记忆条目仍在")
    expect(reloaded.todayStat(now: now).wordsTyped == 1, "重启后今日统计仍在")
}

// MARK: - 主入口

private func runAll() throws {
    testSpacedRepetition()
    testSentenceBuild()
    testPronunciation()
    try testProgressStore()

    print("———————————————————————————")
    if failureCount == 0 {
        print("✅ 逻辑测试全部通过（\(caseCount) 项断言）")
    } else {
        print("❌ \(failureCount)/\(caseCount) 项断言失败")
        exit(1)
    }
}

@main
enum LogicTestRunner {
    static func main() throws {
        setbuf(stdout, nil)
        try runAll()
    }
}
