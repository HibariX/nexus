import Foundation
import Testing
@testable import Nexus

@Suite("清理模式 CleanupMode")
struct CleanupModeTests {

    @Test("Esc 的 keyDown/keyUp 放行（供遮罩窗触发手动恢复）")
    func escPasses() {
        #expect(CleanupMode.shouldConsume(type: .keyDown, keyCode: CleanupMode.escapeKeyCode) == false)
        #expect(CleanupMode.shouldConsume(type: .keyUp, keyCode: CleanupMode.escapeKeyCode) == false)
    }

    @Test("其它按键被吞掉")
    func otherKeysConsumed() {
        #expect(CleanupMode.shouldConsume(type: .keyDown, keyCode: 0) == true)   // 'a'
        #expect(CleanupMode.shouldConsume(type: .keyUp, keyCode: 0) == true)
    }

    @Test("修饰键状态变化被吞掉（防卡键）")
    func flagsChangedConsumed() {
        #expect(CleanupMode.shouldConsume(type: .flagsChanged, keyCode: 0) == true)
    }

    @Test("鼠标与滚轮全部被吞掉")
    func mouseAndScrollConsumed() {
        #expect(CleanupMode.shouldConsume(type: .leftMouseDown, keyCode: 0) == true)
        #expect(CleanupMode.shouldConsume(type: .leftMouseUp, keyCode: 0) == true)
        #expect(CleanupMode.shouldConsume(type: .rightMouseDown, keyCode: 0) == true)
        #expect(CleanupMode.shouldConsume(type: .otherMouseUp, keyCode: 0) == true)
        #expect(CleanupMode.shouldConsume(type: .mouseMoved, keyCode: 0) == true)
        #expect(CleanupMode.shouldConsume(type: .leftMouseDragged, keyCode: 0) == true)
        #expect(CleanupMode.shouldConsume(type: .scrollWheel, keyCode: 0) == true)
    }

    @Test("未列出的疑难杂症事件默认放行")
    func unhandledTypesPass() {
        #expect(CleanupMode.shouldConsume(type: .tabletProximity, keyCode: 0) == false)
    }

    @Test("subtitle 反映状态：idle 提示启动，active 显示剩余秒数")
    func subtitleReflectsState() {
        #expect(CleanupMode.subtitle(for: .idle).contains("启动"))
        #expect(CleanupMode.subtitle(for: .active(remaining: 42)).contains("42"))
        #expect(CleanupMode.subtitle(for: .active(remaining: 0.4)).contains("1"))
    }

    @Test("长按 Esc 3 秒才退出（常量）")
    func holdDurationIsThreeSeconds() {
        #expect(CleanupMode.escHoldDuration == 3)
    }

    @Test("长按进度夹在 0…1 之间")
    func holdProgressClamped() {
        #expect(CleanupMode.holdProgress(0) == 0)
        #expect(CleanupMode.holdProgress(1.5) == 0.5)
        #expect(CleanupMode.holdProgress(-1) == 0)
        #expect(CleanupMode.holdProgress(9) == 1)
    }

    @Test("长按文案：未满显示剩余秒数，满格提示正在退出")
    func holdSubtitleText() {
        #expect(CleanupMode.holdSubtitle(elapsed: 0).contains("3"))
        #expect(CleanupMode.holdSubtitle(elapsed: 2.4).contains("1"))
        #expect(CleanupMode.holdSubtitle(elapsed: 3.0).contains("正在退出"))
    }
}
