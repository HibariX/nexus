import EventKit
import Foundation
import Observation

/// 今日待办：以系统「提醒事项」的 MyRaycast 列表为唯一数据源。
/// 不再落盘——写入即时提交给 EventKit，iCloud 负责同步到其他设备。
@Observable
final class TodoStore {
    static var shared: TodoStore?

    enum AuthState: Equatable {
        /// 还没问过用户，可以直接弹系统授权窗
        case notDetermined
        case granted
        /// 已被拒绝，只能引导去系统设置
        case denied
    }

    private(set) var items: [TodoItem] = []
    private(set) var authorization: AuthState = .notDetermined
    private(set) var todayEvents: [CalendarEvent] = []
    private(set) var nextEvent: CalendarEvent?
    /// 最近一次写入失败的原因，供面板提示
    private(set) var lastError: String?

    /// 「清除已完成」只在面板隐藏，不动系统数据；再有新完成项时自动复位
    private(set) var hidesCompleted = false

    @ObservationIgnored
    private let bridge: EventKitBridge
    @ObservationIgnored
    private var refreshTask: Task<Void, Never>?
    @ObservationIgnored
    private var observationTask: Task<Void, Never>?

    init(settings: AppSettings) {
        bridge = EventKitBridge(settings: settings)
        syncAuthState()
        observeExternalChanges()
        if authorization == .granted {
            // 已授权则启动即加载，让启动器里的 `todo` 立刻有内容；
            // 未决定时不主动弹窗，等用户真正打开待办再请求
            Task { await refresh() }
        }
    }

    deinit {
        refreshTask?.cancel()
        observationTask?.cancel()
    }

    // MARK: - 派生视图

    /// 未完成在上、已完成沉底划掉；同组按创建时间升序
    var sorted: [TodoItem] {
        items
            .filter { !hidesCompleted || !$0.isDone }
            .sorted { a, b in
                if a.isDone != b.isDone { return !a.isDone }
                return a.createdAt < b.createdAt
            }
    }

    var remainingCount: Int { items.lazy.filter { !$0.isDone }.count }

    /// 是否还有「可以隐藏」的已完成项——决定垃圾桶按钮显不显示
    var hasCompleted: Bool { !hidesCompleted && items.contains { $0.isDone } }

    // MARK: - 授权

    func requestAccess() async {
        let granted = await bridge.requestReminderAccess()
        // 日历只用于展示日程，拒绝了不影响待办本身
        _ = await bridge.requestCalendarAccess()
        syncAuthState()
        if granted { await refresh() }
    }

    private func syncAuthState() {
        if PermissionCenter.hasReminders {
            authorization = .granted
        } else if PermissionCenter.isBlocked(.reminder) {
            authorization = .denied
        } else {
            authorization = .notDetermined
        }
    }

    // MARK: - 读取

    func refresh() async {
        syncAuthState()
        guard authorization == .granted else {
            items = []
            return
        }
        do {
            // 先确保专属列表在——创建失败（如无可写账户）要让用户看到原因，
            // 而不是退化成一个空空如也的"今天还没有待办"
            try bridge.ensureList()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            items = []
            return
        }
        items = await bridge.fetchReminders()
        refreshCalendar()
    }

    /// 日程可以单独刷（比如倒计时跨过了事件开始时间）
    func refreshCalendar() {
        todayEvents = bridge.todayEvents()
        nextEvent = bridge.nextUpcomingEvent()
    }

    /// 监听系统侧变更（提醒事项 App、iPhone 同步过来的改动）。
    /// 自己的写入同样会触发，靠防抖吸收掉这次冗余刷新。
    private func observeExternalChanges() {
        observationTask = Task { [weak self] in
            let changes = NotificationCenter.default.notifications(named: .EKEventStoreChanged)
            for await _ in changes {
                guard let self else { return }
                self.bridge.reset()
                self.scheduleRefresh()
            }
        }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            await self.refresh()
        }
    }

    // MARK: - 写入
    //
    // EventKit 的写操作是同步的，成功后本地即时更新；失败一律重新拉取，
    // 以系统侧的真实状态为准，避免面板与提醒事项 App 对不上。

    func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            items.append(try bridge.add(title: trimmed))
            lastError = nil
        } catch {
            report(error)
        }
    }

    func toggle(id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let done = !items[index].isDone
        items[index].isDone = done
        items[index].completedAt = done ? .now : nil
        if done { hidesCompleted = false }  // 刚勾的这条要看得见

        do {
            try bridge.setCompleted(id: id, done)
            lastError = nil
        } catch {
            report(error)
        }
    }

    /// 改名；空串忽略（视为取消编辑，删除请走 remove(id:)）
    func updateTitle(id: String, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].title = trimmed

        do {
            try bridge.rename(id: id, to: trimmed)
            lastError = nil
        } catch {
            report(error)
        }
    }

    /// 真删除——会从「提醒事项」中一并移除
    func remove(id: String) {
        items.removeAll { $0.id == id }
        do {
            try bridge.delete(id: id)
            lastError = nil
        } catch {
            report(error)
        }
    }

    /// 仅从面板隐藏已完成项。系统「提醒事项」里的记录完整保留
    func clearCompleted() {
        hidesCompleted = true
    }

    private func report(_ error: Error) {
        lastError = error.localizedDescription
        scheduleRefresh()
    }
}
