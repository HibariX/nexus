import EventKit
import Foundation

/// 一条待办 —— 系统「提醒事项」的只读快照。不落盘，数据源始终是 EventKit。
///
/// nonisolated：EventKit 的 fetchReminders 回调在任意线程触发，映射必须能在
/// 非主线程执行。同时它是唯一被允许穿过隔离边界的类型（EKReminder 非 Sendable）。
nonisolated struct TodoItem: Identifiable, Sendable {
    /// EKReminder.calendarItemIdentifier
    let id: String
    var title: String
    var isDone: Bool
    var createdAt: Date
    var completedAt: Date?

    init(reminder: EKReminder) {
        id = reminder.calendarItemIdentifier
        // EKCalendarItem.title 是 String!，桥接成可选再兜底，避免隐式解包崩溃
        title = (reminder.title as String?) ?? ""
        isDone = reminder.isCompleted
        createdAt = reminder.creationDate ?? .distantPast
        completedAt = reminder.completionDate
    }
}
