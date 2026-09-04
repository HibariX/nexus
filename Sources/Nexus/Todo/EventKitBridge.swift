import EventKit
import Foundation

/// EventKit 收口层：全 App 唯一的 EKEventStore 持有者。
///
/// 必须复用同一个 store 实例——每次 new 都会重建缓存，让已经发出去的
/// calendarItemIdentifier 失效，且首次访问有明显开销。
///
/// 对外只暴露 TodoItem / CalendarEvent 这两个值类型：EKEventStore、EKReminder、
/// EKEvent 都不是 Sendable，绝不能穿过隔离边界。
final class EventKitBridge {
    enum BridgeError: LocalizedError {
        case noWritableSource
        case listUnavailable
        case itemMissing
        case underlying(String)

        var errorDescription: String? {
            switch self {
            case .noWritableSource:
                return "没有可写入的提醒事项账户，请先在「提醒事项」App 中登录 iCloud 或新建一个本地列表。"
            case .listUnavailable:
                return "无法创建「\(EventKitBridge.listTitle)」提醒列表。"
            case .itemMissing:
                return "这条待办已在「提醒事项」中被删除。"
            case .underlying(let message):
                return message
            }
        }
    }

    /// 专属列表名。只在首次创建时用到，之后一律按 calendarIdentifier 认人。
    /// nonisolated：错误文案要在 LocalizedError 的 nonisolated 实现里引用它
    nonisolated static let listTitle = "Nexus"

    private let store = EKEventStore()
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: - 授权

    /// 授权请求必须走本实例，否则新 store 拿不到刚授予的权限
    func requestReminderAccess() async -> Bool {
        (try? await store.requestFullAccessToReminders()) ?? false
    }

    func requestCalendarAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// 收到 EKEventStoreChanged 后必须先丢掉本地缓存，否则可能读回旧快照
    func reset() {
        store.reset()
    }

    // MARK: - 专属列表

    /// 按 identifier → 标题 → 新建 的顺序拿到专属列表
    @discardableResult
    func ensureList() throws -> EKCalendar {
        if let id = settings.todoReminderListID,
           let calendar = store.calendar(withIdentifier: id),
           calendar.allowsContentModifications {
            return calendar
        }

        // identifier 失效（换机、列表被删）时按标题兜底认领
        let existing = store.calendars(for: .reminder)
        if let calendar = existing.first(where: {
            $0.title == Self.listTitle && $0.allowsContentModifications
        }) {
            settings.todoReminderListID = calendar.calendarIdentifier
            return calendar
        }

        // 迁移：旧版名为「MyRaycast」的提醒列表重命名为 Nexus，保留已存待办
        if let legacy = existing.first(where: {
            $0.title == "MyRaycast" && $0.allowsContentModifications
        }) {
            legacy.title = Self.listTitle
            do {
                try store.saveCalendar(legacy, commit: true)
            } catch {
                throw BridgeError.underlying(error.localizedDescription)
            }
            settings.todoReminderListID = legacy.calendarIdentifier
            return legacy
        }

        guard let source = preferredSource() else { throw BridgeError.noWritableSource }
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = Self.listTitle
        calendar.source = source
        do {
            try store.saveCalendar(calendar, commit: true)
        } catch {
            throw BridgeError.underlying(error.localizedDescription)
        }
        settings.todoReminderListID = calendar.calendarIdentifier
        return calendar
    }

    /// 新建列表要挂在某个账户下。优先跟随系统默认提醒列表所在账户，
    /// 其次 iCloud（calDAV），最后本地
    private func preferredSource() -> EKSource? {
        if let source = store.defaultCalendarForNewReminders()?.source { return source }
        let usable = store.sources.filter { !$0.calendars(for: .reminder).isEmpty }
        return usable.first { $0.sourceType == .calDAV }
            ?? usable.first { $0.sourceType == .local }
            ?? usable.first
    }

    // MARK: - 读取待办

    func fetchReminders() async -> [TodoItem] {
        guard PermissionCenter.hasReminders, let list = try? ensureList() else { return [] }
        let predicate = store.predicateForReminders(in: [list])

        return await withCheckedContinuation { continuation in
            // 回调线程不定：在闭包内部就把 EKReminder 映射成 Sendable 的 TodoItem，
            // 只让值类型跨过边界。闭包不捕获 self
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(TodoItem.init(reminder:)))
            }
        }
    }

    // MARK: - 写入待办（EventKit 写操作是同步的，主线程直接调用即可）

    func add(title: String) throws -> TodoItem {
        let list = try ensureList()
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = list
        do {
            try store.save(reminder, commit: true)
        } catch {
            throw BridgeError.underlying(error.localizedDescription)
        }
        // identifier 在 save 之后才稳定，此时再快照
        return TodoItem(reminder: reminder)
    }

    func setCompleted(id: String, _ done: Bool) throws {
        try mutate(id: id) { $0.isCompleted = done }
    }

    func rename(id: String, to title: String) throws {
        try mutate(id: id) { $0.title = title }
    }

    func delete(id: String) throws {
        guard let reminder = reminder(withID: id) else { throw BridgeError.itemMissing }
        do {
            try store.remove(reminder, commit: true)
        } catch {
            throw BridgeError.underlying(error.localizedDescription)
        }
    }

    private func mutate(id: String, _ change: (EKReminder) -> Void) throws {
        guard let reminder = reminder(withID: id) else { throw BridgeError.itemMissing }
        change(reminder)
        do {
            try store.save(reminder, commit: true)
        } catch {
            throw BridgeError.underlying(error.localizedDescription)
        }
    }

    private func reminder(withID id: String) -> EKReminder? {
        store.calendarItem(withIdentifier: id) as? EKReminder
    }

    // MARK: - 日历（只读）

    /// 今天 00:00 → 次日 00:00 的事件，全天置顶，其余按开始时间升序
    func todayEvents() -> [CalendarEvent] {
        guard PermissionCenter.hasCalendar else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .map(CalendarEvent.init(event:))
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return lhs.start < rhs.start
            }
    }

    /// 下一个尚未开始的非全天事件。向后扫 7 天，所以可能落在明天及以后
    func nextUpcomingEvent() -> CalendarEvent? {
        guard PermissionCenter.hasCalendar else { return nil }
        let now = Date.now
        guard let end = Calendar.current.date(byAdding: .day, value: 7, to: now) else { return nil }

        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay && ($0.startDate ?? .distantPast) > now }
            .min { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            .map(CalendarEvent.init(event:))
    }
}
