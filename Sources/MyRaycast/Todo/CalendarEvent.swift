import AppKit
import EventKit
import Foundation

/// 一条日历事件的只读快照（浮窗只展示，不写回日历）。
/// nonisolated + Sendable 的理由同 TodoItem。
nonisolated struct CalendarEvent: Identifiable, Sendable {
    /// 重复事件的每个实例共享 eventIdentifier，拼上开始时间才在列表里唯一
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    /// 所属日历的颜色。CGColor 非 Sendable，拆成分量存
    let color: RGB?

    struct RGB: Sendable {
        let red: Double
        let green: Double
        let blue: Double
    }

    init(event: EKEvent) {
        let start = event.startDate ?? .distantPast
        id = "\(event.eventIdentifier ?? UUID().uuidString)@\(start.timeIntervalSince1970)"
        title = (event.title as String?) ?? "(无标题)"
        self.start = start
        end = event.endDate ?? start
        isAllDay = event.isAllDay
        color = Self.rgb(from: event.calendar?.cgColor)
    }

    private static func rgb(from cgColor: CGColor?) -> RGB? {
        guard let cgColor,
              let converted = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB) else { return nil }
        return RGB(red: converted.redComponent,
                   green: converted.greenComponent,
                   blue: converted.blueComponent)
    }

    // MARK: - 展示

    /// "14:30"；全天事件显示"全天"
    var timeText: String {
        guard !isAllDay else { return "全天" }
        return start.formatted(.dateTime.hour().minute().locale(Locale(identifier: "zh_CN")))
    }

    /// 距开始还有多久，如"28 分钟后"。已开始或全天返回 nil
    func countdownText(now: Date = .now) -> String? {
        guard !isAllDay else { return nil }
        let seconds = start.timeIntervalSince(now)
        guard seconds > 0 else { return nil }

        let minutes = Int(seconds / 60)
        if minutes < 1 { return "即将开始" }
        if minutes < 60 { return "\(minutes) 分钟后" }

        let hours = minutes / 60
        if hours < 24 {
            let rest = minutes % 60
            return rest == 0 ? "\(hours) 小时后" : "\(hours) 小时 \(rest) 分后"
        }
        return "\(hours / 24) 天后"
    }
}
