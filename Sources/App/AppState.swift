import Foundation

// MARK: - 应用级状态中枢（集中持有服务与页面路由，Views 不持有业务状态）
// App 层：只做协调与路由，不写具体业务算法。

/// 应用页面
enum AppPage: Int, CaseIterable {
    case home
    case typing
    case sentence
    case speaking
    case review
    case stats

    /// 侧边栏展示名
    var title: String {
        switch self {
        case .home: return "学习中心"
        case .typing: return "单词打字"
        case .sentence: return "连词造句"
        case .speaking: return "口语私教"
        case .review: return "复习"
        case .stats: return "学习统计"
        }
    }

    /// 侧边栏 SF Symbol
    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .typing: return "keyboard"
        case .sentence: return "rectangle.and.text.magnifyingglass"
        case .speaking: return "mic.fill"
        case .review: return "rectangle.stack.fill"
        case .stats: return "chart.bar.fill"
        }
    }
}

@MainActor
final class AppState {

    // MARK: - 属性（服务层）

    let library: ContentLibraryServiceProtocol
    let store: ProgressStoreProtocol
    let scheduler: SpacedRepetitionServiceProtocol
    let reviewService: ReviewServiceProtocol
    let statsService: StatsServiceProtocol
    let speech: SpeechServiceProtocol
    let recognizer: SpeechRecognitionServiceProtocol

    /// 当前页面
    private(set) var currentPage: AppPage = .home
    /// 页面切换回调（由 RootViewController 订阅）
    var onPageChange: ((AppPage) -> Void)?

    // MARK: - 初始化

    init() {
        let library = ContentLibraryService()
        let store = ProgressStore()
        let scheduler = SpacedRepetitionService()
        self.library = library
        self.store = store
        self.scheduler = scheduler
        self.reviewService = ReviewService(scheduler: scheduler, store: store, library: library)
        self.statsService = StatsService(store: store, library: library)
        self.speech = SpeechService()
        self.recognizer = SpeechRecognitionService()
    }

    // MARK: - 路由

    /// 切换页面
    func go(_ page: AppPage) {
        currentPage = page
        onPageChange?(page)
    }

    /// 统一登记一次跨模块练习结果，写入共享记忆曲线
    /// - Parameters:
    ///   - id: 条目 id
    ///   - kind: 来源模块
    ///   - grade: 本次掌握程度
    func recordPractice(id: String, kind: MemoryKind, grade: ReviewGrade) {
        let now = Date()
        let item = store.ensureItem(id: id, kind: kind, now: now)
        let updated = scheduler.schedule(item, grade: grade, now: now)
        store.upsert(updated)
    }
}
