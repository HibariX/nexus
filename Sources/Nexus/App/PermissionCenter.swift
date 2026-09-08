import AppKit
import ApplicationServices
import EventKit

/// 权限检测与引导统一收口
enum PermissionCenter {

    /// 权限提示使用 Bundle 中的正式产品名，避免更名后残留旧品牌文案。
    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Nexus"
    }

    // MARK: - Accessibility（合成 ⌘V 需要）

    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    /// 触发系统授权弹窗（仅首次有效），并深链设置页
    static func requestAccessibility() {
        // kAXTrustedCheckOptionPrompt 是全局 var，Swift 6 并发检查不放行，用其字面值
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        openSettings("Privacy_Accessibility")
    }

    // MARK: - 屏幕录制（screencapture 需要）

    static var hasScreenCapture: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestScreenCapture() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openScreenCaptureSettings() {
        openSettings("Privacy_ScreenCapture")
    }

    // MARK: - Pasteboard（macOS 26 新隐私机制）

    static func openPasteboardSettings() {
        openSettings("Privacy_Pasteboard")
    }

    // MARK: - 提醒事项 / 日历（今日待办的存储后端与日程展示）

    /// 授权请求本身在 EventKitBridge 里发起——必须复用它持有的那个 EKEventStore 实例，
    /// 这里只做状态查询与设置深链。状态查询是 static，无需实例。
    static var hasReminders: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    static var hasCalendar: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// 用户明确拒绝过（或被描述文件限制），此时再调 request 不会弹窗，只能引导去设置
    static func isBlocked(_ entity: EKEntityType) -> Bool {
        switch EKEventStore.authorizationStatus(for: entity) {
        case .denied, .restricted, .writeOnly:
            return true
        default:
            return false
        }
    }

    static func openRemindersSettings() {
        openSettings("Privacy_Reminders")
    }

    static func openCalendarSettings() {
        openSettings("Privacy_Calendars")
    }

    private static func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 展示权限引导弹窗，返回用户是否点击了「打开设置」
    static func showGuide(title: String, message: String, openSettings: () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            openSettings()
        }
    }
}
