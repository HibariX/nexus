import Foundation

struct Query: Sendable {
    let raw: String
    let trimmed: String

    init(raw: String) {
        self.raw = raw
        self.trimmed = raw.trimmingCharacters(in: .whitespaces)
    }
}

/// 导航栈里一层的来源：root 为顶层混合搜索，plugin 为外部插件页面，builtin 为内置页面（如计算器）
enum PageSource: Sendable {
    case root
    case plugin(pluginId: String, path: String)
    case builtin(id: String)
}

/// 内置页面（Swift 实现，非外部子进程），以页面层级呈现。如计算器。
protocol BuiltinPage: AnyObject {
    var id: String { get }
    func results(for query: Query) async -> [ResultItem]
}

enum IconSource: Sendable {
    case appBundle(path: String)
    case file(path: String)
    case symbol(name: String)
    case clipboardImage(id: UUID)
}

enum ResultAction: Sendable {
    case launchApp(path: String)
    case openFile(path: String)
    case revealInFinder(path: String)
    case copyText(String)
    /// 复制计算结果，并记入计算历史
    case copyCalculation(expression: String, result: String)
    /// 复制「表达式 = 结果」整体（cmd+回车），并记入计算历史
    case copyCalculationFull(expression: String, result: String)
    case pasteClip(id: UUID)
    case runSystem(SystemCommand)
    case pinClipboardContent
    case addTodo(String)
    case toggleTodo(id: String)
    case showTodoPanel
    /// 把搜索框文本替换为指定串（不关面板）——用于插件关键词补全、进入子模式
    case replaceQuery(String)
    /// 压栈进入一个插件页面（不关面板）——用于页面层级导航
    case pushPage(pluginId: String, path: String, title: String)
    /// 异步调用外部插件的一个动作（子进程执行副作用）
    case pluginAction(pluginId: String, actionId: String, payload: String)
    /// 给某 App 保存一个别名（不关面板，随后返回并刷新）
    case saveAlias(path: String, alias: String)
    /// 移除某 App 的一个别名
    case removeAlias(path: String, alias: String)
    /// 卸载应用（把 .app 移到废纸篓）
    case uninstallApp(path: String)
    /// 切换「禁止休眠」：异步 + 管理员权限执行，保持面板并刷新状态
    case toggleSleepDisabled
}

struct ResultItem: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: IconSource
    let score: Double
    let accessoryHint: String?
    let action: ResultAction
}

struct ResultSection: Identifiable, Sendable {
    let title: String
    var items: [ResultItem]
    var id: String { title }
}

protocol CommandProvider {
    var sectionTitle: String { get }
    /// 分区排序，越小越靠前
    var sectionRank: Int { get }
    /// 返回 true 表示该 Provider 已明确识别查询意图，无需再运行其他 Provider。
    func prefersExclusiveResults(for query: Query) -> Bool
    func results(for query: Query) async -> [ResultItem]
    /// `@` 分类浏览：root 下 @ 或 @<前缀> 时罗列该 Provider 的入口。默认不参与。
    func atEntries(for query: Query) async -> [ResultItem]
}

extension CommandProvider {
    func prefersExclusiveResults(for query: Query) -> Bool { false }
    func atEntries(for query: Query) async -> [ResultItem] { [] }
}
