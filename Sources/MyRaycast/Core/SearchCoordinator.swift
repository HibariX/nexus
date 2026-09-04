import AppKit
import Observation

/// 工作台网格布局常量（放此避免 coordinator import SwiftUI）
enum WorkbenchLayout {
    static let columns = 5
}

@Observable
final class SearchCoordinator {
    var query = "" {
        didSet {
            guard !suppressSchedule else { return }
            // root 下输入 `=` → 自动进入计算器页面，= 之后的内容作为初始算式
            if case .root = currentSource, query.hasPrefix("=") {
                push(source: .builtin(id: "calc"), title: "计算器",
                     initialQuery: String(query.dropFirst()).trimmingCharacters(in: .whitespaces))
                return
            }
            schedule()
        }
    }
    private(set) var sections: [ResultSection] = []
    var selection: ResultItem.ID?

    var onDismiss: (() -> Void)?

    /// 插件页面的结果来源（AppDelegate 注入）；root 页不用
    weak var pluginHost: PluginHostProvider?

    /// 工作台(空态)专用的应用来源（AppDelegate 注入，通常是 AppLauncherProvider）。
    /// 强引用无妨：provider 不反向持有 coordinator，无循环。
    var workbenchProvider: (any CommandProvider)?

    /// 内置页面（如计算器），按 id 索引
    private var builtinPages: [String: BuiltinPage] = [:]

    func registerBuiltin(_ page: BuiltinPage) { builtinPages[page.id] = page }

    private var providers: [any CommandProvider] = []
    private var searchTask: Task<Void, Never>?
    private var providerTasks: [Task<(Int, ResultSection)?, Never>] = []

    // MARK: - 导航栈

    /// 一层的快照（非当前层）
    private struct Frame {
        let source: PageSource
        let query: String
        let selection: ResultItem.ID?
        let sections: [ResultSection]
        let title: String
    }

    private var stack: [Frame] = []
    private(set) var currentSource: PageSource = .root
    private(set) var pageTitle = ""            // 当前页名，root 为空
    private var suppressSchedule = false        // 恢复快照/清空时抑制 didSet 触发搜索

    var canGoBack: Bool { !stack.isEmpty }

    /// 工作台态：root 顶层且搜索框为空 → 以网格展示全部 App
    var isWorkbench: Bool {
        if case .root = currentSource {
            return query.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return false
    }

    var isRandomPasswordPluginPage: Bool {
        if case .plugin(let id, _) = currentSource { return id == "random-passwd" }
        return false
    }

    var currentPluginPath: String {
        if case .plugin(_, let path) = currentSource { return path }
        return ""
    }

    var searchPlaceholder: String {
        switch currentSource {
        case .root: return "搜索应用、算式，@ 唤起插件…"
        case .plugin: return "在 \(pageTitle) 中搜索…"
        case .builtin: return "输入算式，回车复制结果…"
        }
    }

    /// 压栈进入新页面：保存当前层，把搜索框设为 initialQuery（默认清空），拉取新页结果
    func push(source: PageSource, title: String, initialQuery: String = "") {
        stack.append(Frame(source: currentSource, query: query,
                           selection: selection, sections: sections, title: pageTitle))
        currentSource = source
        pageTitle = title
        suppressSchedule = true
        query = initialQuery
        suppressSchedule = false
        selection = nil
        schedule()
    }

    /// 返回上一层：恢复快照，不重新搜索
    func pop() {
        guard let frame = stack.popLast() else { return }
        searchTask?.cancel()
        providerTasks.forEach { $0.cancel() }
        currentSource = frame.source
        pageTitle = frame.title
        suppressSchedule = true
        query = frame.query
        suppressSchedule = false
        selection = frame.selection
        sections = frame.sections
    }

    /// 直接回到顶层（面板隐藏时用），恢复最早的 root 快照
    func popToRoot() {
        guard let root = stack.first else { return }
        searchTask?.cancel()
        providerTasks.forEach { $0.cancel() }
        stack.removeAll()
        currentSource = root.source
        pageTitle = root.title
        suppressSchedule = true
        query = root.query
        suppressSchedule = false
        selection = root.selection
        sections = root.sections
    }

    // MARK: -

    func register(_ provider: any CommandProvider) {
        providers.append(provider)
        providers.sort { $0.sectionRank < $1.sectionRank }
    }

    var flatItems: [ResultItem] { sections.flatMap(\.items) }

    var selectedItem: ResultItem? {
        flatItems.first { $0.id == selection }
    }

    func reset() {
        searchTask?.cancel()
        providerTasks.forEach { $0.cancel() }
        stack.removeAll()
        currentSource = .root
        pageTitle = ""
        query = ""
        sections = []
        selection = nil
    }

    /// 面板隐藏时调用：保留上一次的 query 与结果，仅取消进行中的搜索。
    func cancelSearch() {
        searchTask?.cancel()
        providerTasks.forEach { $0.cancel() }
    }

    func refresh() { schedule() }

    static func exclusiveProvider(for query: Query,
                                  in providers: [any CommandProvider]) -> (any CommandProvider)? {
        providers.first { $0.prefersExclusiveResults(for: query) }
    }

    private func schedule() {
        searchTask?.cancel()
        providerTasks.forEach { $0.cancel() }
        let q = Query(raw: query)
        let source = currentSource
        let snapshot = providers
        let host = pluginHost
        let title = pageTitle
        let pages = builtinPages
        let rootExclusive: (any CommandProvider)?
        if case .root = source {
            rootExclusive = Self.exclusiveProvider(for: q, in: snapshot)
        } else {
            rootExclusive = nil
        }
        let debounceMilliseconds: Int64 = rootExclusive == nil ? 60 : 16

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(debounceMilliseconds))
            guard !Task.isCancelled else { return }

            switch source {
            case .root:
                // 工作台快路：空 query 时只跑应用来源、全量展示，不混其它 provider
                if q.trimmed.isEmpty, let wp = workbenchProvider {
                    let items = await wp.results(for: q)
                    guard !Task.isCancelled else { return }
                    sections = items.isEmpty ? [] : [ResultSection(title: wp.sectionTitle, items: items)]
                    selection = flatItems.first?.id
                    return
                }
                // 明确算式等强意图只运行认领它的 Provider。否则每次输入都会让应用、
                // 剪贴板、文件和插件搜索同时工作，并与搜索框绘制争抢主线程。
                if let exclusive = rootExclusive {
                    let items = await exclusive.results(for: q)
                    guard !Task.isCancelled else { return }
                    sections = items.isEmpty ? [] : [ResultSection(
                        title: exclusive.sectionTitle,
                        items: items.sorted { $0.score > $1.score }
                    )]
                    selection = sections.first?.items.first?.id
                    return
                }
                // 混合搜索会增量返回多个分区，开始前清掉上一轮结果。
                sections = []
                selection = nil
                // 所有 provider 并发发起（子 Task 继承 MainActor，IO await 让出可 overlap）。
                // 按 rank 顺序收集：rank 小的通常更快，先返回先显示；文件搜索(rank 40)最后补上。
                let tasks = snapshot.map { provider in
                    Task { () -> (Int, ResultSection)? in
                        let items = await provider.results(for: q)
                        guard !items.isEmpty else { return nil }
                        return (provider.sectionRank,
                                ResultSection(title: provider.sectionTitle,
                                              items: items.sorted { $0.score > $1.score }))
                    }
                }
                providerTasks = tasks

                var accumulated: [(rank: Int, section: ResultSection)] = []
                for task in tasks {
                    let result = await task.value
                    guard !Task.isCancelled else { return }
                    guard let result else { continue }
                    accumulated.append(result)
                    accumulated.sort { $0.rank < $1.rank }
                    sections = accumulated.map(\.section)
                    if selection == nil { selection = flatItems.first?.id }
                }

            case .plugin(let id, let path):
                // 插件页：只跑该插件子进程，path + 页内输入 作为 arg
                sections = []
                selection = nil
                let arg = [path, q.trimmed].filter { !$0.isEmpty }.joined(separator: " ")
                let items = await host?.pageResults(pluginId: id, arg: arg) ?? []
                guard !Task.isCancelled else { return }
                sections = items.isEmpty ? [] : [ResultSection(title: title, items: items)]
                selection = flatItems.first?.id

            case .builtin(let id):
                // 内置页（如计算器）：Swift 直接生成结果
                let items = await pages[id]?.results(for: q) ?? []
                guard !Task.isCancelled else { return }
                sections = items.isEmpty ? [] : [ResultSection(title: title, items: items)]
                selection = flatItems.first?.id
            }
        }
    }

    // MARK: - 键盘导航

    func moveSelection(by offset: Int) {
        let items = flatItems
        guard !items.isEmpty else { return }
        guard let current = selection,
              let index = items.firstIndex(where: { $0.id == current }) else {
            selection = items.first?.id
            return
        }
        let next = min(max(index + offset, 0), items.count - 1)
        selection = items[next].id
    }

    /// 语义化方向移动：工作台网格时上下按列数换算，左右移一格；列表时上下移一格。
    func moveUp() { moveSelection(by: isWorkbench ? -WorkbenchLayout.columns : -1) }
    func moveDown() { moveSelection(by: isWorkbench ? WorkbenchLayout.columns : 1) }

    /// 左右仅在工作台生效；返回是否处理（未处理则让搜索框光标正常移动）
    func moveLeft() -> Bool {
        guard isWorkbench else { return false }
        moveSelection(by: -1)
        return true
    }
    func moveRight() -> Bool {
        guard isWorkbench else { return false }
        moveSelection(by: 1)
        return true
    }

    /// root 下选中某 App 时按 Tab 触发：进入别名编辑页；否则 no-op 返回 false（搜索框不拦 Tab）
    func beginAliasEditing() -> Bool {
        guard case .root = currentSource,
              let item = selectedItem,
              case .launchApp(let path) = item.action else { return false }
        (builtinPages["alias"] as? AliasEditorPage)?.configure(path: path, name: item.title)
        push(source: .builtin(id: "alias"), title: "设置别名 · \(item.title)")
        return true
    }

    /// copyExpression: cmd+回车触发，对计算结果改为复制「表达式 = 结果」整体
    func executeSelected(executor: ActionExecutor, copyExpression: Bool = false) {
        guard let item = selectedItem else { return }
        switch item.action {
        case .replaceQuery(let newQuery):
            // 关键词补全/占位：改写搜索框，保持面板打开
            query = newQuery
        case .pushPage(let pluginId, let path, let title):
            // 压栈进入插件页面，保持面板打开
            push(source: .plugin(pluginId: pluginId, path: path), title: title)
        case .pluginAction, .toggleSleepDisabled:
            // 插件动作 / 禁止休眠切换：异步执行，关/留面板与刷新由 executor 依 outcome 决定。
            // 此处不得 refresh()——切换类动作的状态刷新必须等 executor 在子进程返回后再触发，
            // 否则会在授权/执行期间读到旧状态。
            executor.execute(item.action)
        case .saveAlias, .removeAlias:
            // 持久化别名后返回上一层并重算结果（pop 只恢复快照不重搜，须显式 refresh），保持面板打开
            executor.execute(item.action)
            pop()
            refresh()
        case .copyCalculation(let expression, let result) where copyExpression:
            // cmd+回车：复制「表达式 = 结果」
            onDismiss?()
            executor.execute(.copyCalculationFull(expression: expression, result: result))
        default:
            onDismiss?()
            executor.execute(item.action)
        }
    }
}
