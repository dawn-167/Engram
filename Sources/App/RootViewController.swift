import Cocoa

// MARK: - 根视图控制器（App 层路由：侧边栏 + 页面容器，只协调不写业务）

@MainActor
final class RootViewController: NSViewController {

    // MARK: - 属性

    private let appState: AppState
    private let sidebar = SidebarView()
    private let contentContainer = NSView()
    private var pageViews: [AppPage: NSView] = [:]
    private var currentPage: AppPage?

    // MARK: - 初始化

    init(state: AppState) {
        self.appState = state
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未使用") }

    // MARK: - 生命周期

    override func loadView() {
        view = NSView(frame: CGRect(x: 0, y: 0, width: 940, height: 640))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSidebar()
        setupContainer()
        buildPages()
        appState.onPageChange = { [weak self] page in self?.showPage(page) }
        showPage(.home)
        refreshSidebar()
    }

    // MARK: - 布局

    private func setupSidebar() {
        sidebar.frame = CGRect(x: 0, y: 0, width: Theme.sidebarWidth, height: view.bounds.height)
        sidebar.autoresizingMask = [.height]
        sidebar.onSelect = { [weak self] page in self?.appState.go(page) }
        view.addSubview(sidebar)
    }

    private func setupContainer() {
        let x = Theme.sidebarWidth
        contentContainer.frame = CGRect(x: x, y: 0,
                                        width: view.bounds.width - x, height: view.bounds.height)
        contentContainer.autoresizingMask = [.width, .height]
        view.addSubview(contentContainer)
    }

    private func buildPages() {
        let home = HomeView(state: appState)
        home.onNavigate = { [weak self] page in self?.appState.go(page) }
        pageViews[.home] = home
        pageViews[.typing] = TypingPageView(state: appState)
        pageViews[.sentence] = SentenceBuildPageView(state: appState)
        pageViews[.speaking] = SpeakingPageView(state: appState)
        pageViews[.review] = ReviewPageView(state: appState)
        pageViews[.stats] = StatsPageView(state: appState)
    }

    // MARK: - 页面切换

    private func showPage(_ page: AppPage) {
        guard let target = pageViews[page] else { return }
        if target.superview == nil {
            let inset = Theme.pagePadding
            target.frame = CGRect(x: inset, y: inset,
                                  width: contentContainer.bounds.width - inset * 2,
                                  height: contentContainer.bounds.height - inset * 2)
            target.autoresizingMask = [.width, .height]
            contentContainer.addSubview(target)
        }
        contentContainer.subviews.forEach { $0.isHidden = ($0 !== target) }
        currentPage = page
        sidebar.setSelected(page)
        refreshPage(page)
        refreshSidebar()
    }

    /// 进入页面时刷新数据
    private func refreshPage(_ page: AppPage) {
        switch page {
        case .home: (pageViews[.home] as? HomeView)?.refresh()
        case .review: (pageViews[.review] as? ReviewPageView)?.refresh()
        case .stats: (pageViews[.stats] as? StatsPageView)?.refresh()
        case .typing: (pageViews[.typing] as? TypingPageView)?.activate()
        case .sentence, .speaking: break
        }
    }

    private func refreshSidebar() {
        let summary = appState.statsService.summary(now: Date())
        sidebar.refresh(streak: summary.streakDays, dueCount: summary.dueCount)
    }

    /// 窗口重新激活时，让打字页夺回键盘第一响应者
    func refocusTyping() {
        (pageViews[.typing] as? TypingPageView)?.activate()
    }

    // MARK: - 键盘转发

    override func keyDown(with event: NSEvent) {
        // 空格翻复习卡
        if currentPage == .review, event.charactersIgnoringModifiers == " " {
            (pageViews[.review] as? ReviewPageView)?.handleSpace()
            return
        }
        super.keyDown(with: event)
    }
}
