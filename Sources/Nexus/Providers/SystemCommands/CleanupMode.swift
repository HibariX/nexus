import Carbon.HIToolbox
import CoreGraphics

/// 「清理模式」（cleanup）：擦拭屏幕/键盘时临时屏蔽输入，倒计时结束或按 Esc 恢复。
/// 与 SleepControl 一样，可测的部分抽成 nonisolated enum；真正副作用
/// （全屏遮罩窗 / 事件 tap / 倒计时）在 CleanupModeController。
nonisolated enum CleanupMode {

    /// Esc 键码（Carbon kVK_Escape = 0x35 = 53）
    static let escapeKeyCode: UInt16 = UInt16(kVK_Escape)
    /// 长按 Esc 多少秒才退出（防止擦拭时误触单次 Esc）
    static let escHoldDuration: TimeInterval = 3

    /// 状态，供 provider 的 subtitle 与 controller 使用
    enum Phase: Equatable {
        case idle
        /// active 时携带剩余秒数，供倒计时展示
        case active(remaining: Double)
    }

    /// 需要监听并处理的 CGEvent 类型。rawValue 均为 1…27，可安全 `1 << raw` 做掩码。
    /// 不含 tapDisabled*——那两事件系统会无条件投递，由回调单独处理。
    static var cleanupEventMask: CGEventMask {
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .scrollWheel,
        ]
        var mask: CGEventMask = 0
        for type in types {
            mask |= 1 << UInt32(type.rawValue)
        }
        return mask
    }

    /// 纯函数：给定事件类型与键码，决定是否吞掉。true = 消费（阻断），false = 放行。
    /// 仅 Esc 的 keyDown/keyUp 放行（供遮罩窗触发手动恢复），其余按键/鼠标/滚轮全部吞掉。
    static func shouldConsume(type: CGEventType, keyCode: UInt16) -> Bool {
        switch type {
        case .keyDown, .keyUp:
            return keyCode != escapeKeyCode
        case .flagsChanged:
            // 修饰键状态变化全吞：防止键鼠状态半途泄漏到前台 app（避免「卡键」）。
            // 启动瞬间若已按住某个修饰键、中途松开，其 keyUp 会被吞，由 controller 退出时补发复位。
            return true
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp,
             .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
             .scrollWheel:
            return true
        default:
            return false
        }
    }

    /// 状态文案（provider 的 subtitle 直接用）
    static func subtitle(for phase: Phase) -> String {
        switch phase {
        case .idle:
            return "擦拭屏幕/键盘前启动，临时屏蔽输入"
        case .active(let remaining):
            return "清理中 · 剩余 \(max(0, Int(remaining.rounded(.up))))s"
        }
    }

    /// 长按进度：0…1，供遮罩画进度条。
    static func holdProgress(_ elapsed: TimeInterval) -> Double {
        min(max(elapsed / escHoldDuration, 0), 1)
    }

    /// 长按时遮罩里显示的子文案。
    static func holdSubtitle(elapsed: TimeInterval) -> String {
        let remain = max(0, Int((escHoldDuration - elapsed).rounded(.up)))
        return remain > 0 ? "再按住 \(remain)s 退出 · 松开取消" : "正在退出…"
    }
}
