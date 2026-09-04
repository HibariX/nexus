import AppKit
import Carbon.HIToolbox
import Testing
@testable import MyRaycast

@Suite("窗口管理")
struct WindowLayoutTests {
    private let landscape = CGRect(x: 0, y: 24, width: 1440, height: 876)

    @Test("半屏与四角使用可见区域")
    func halvesAndCorners() throws {
        #expect(WindowLayout.target(for: .leftHalf, current: .zero, visibleFrame: landscape)
            == CGRect(x: 0, y: 24, width: 720, height: 876))
        #expect(WindowLayout.target(for: .bottomRight, current: .zero, visibleFrame: landscape)
            == CGRect(x: 720, y: 462, width: 720, height: 438))
    }

    @Test("三分屏按屏幕方向选择主轴")
    func thirdsFollowOrientation() throws {
        #expect(WindowLayout.third(for: .centerThird, in: landscape)
            == CGRect(x: 480, y: 24, width: 480, height: 876))
        let portrait = CGRect(x: 0, y: 0, width: 900, height: 1200)
        #expect(WindowLayout.third(for: .lastThird, in: portrait)
            == CGRect(x: 0, y: 800, width: 900, height: 400))
    }

    @Test("居中与跨屏约束不允许窗口越过可见边界")
    func constrainFrames() throws {
        let oversized = CGRect(x: -80, y: -20, width: 1800, height: 1000)
        #expect(WindowLayout.centered(oversized, in: landscape) == landscape)
        #expect(WindowLayout.constrained(CGRect(x: -100, y: 100, width: 500, height: 500), to: landscape)
            == CGRect(x: 0, y: 100, width: 500, height: 500))
    }

    @Test("Rectangle 备用方案和待办快捷键能迁移")
    func importsAlternateDefaultsAndTodoAliases() throws {
        let flags = NSEvent.ModifierFlags([.control, .option]).rawValue
        let imported = RectangleImporter.parse([
            "alternateDefaultShortcuts": true,
            "leftHalf": ["keyCode": NSNumber(value: kVK_ANSI_L), "modifierFlags": NSNumber(value: flags)],
            "toggleTodo": ["keyCode": NSNumber(value: kVK_ANSI_B), "modifierFlags": NSNumber(value: flags)],
            "reflowTodo": ["keyCode": NSNumber(value: kVK_ANSI_N), "modifierFlags": NSNumber(value: flags)],
        ])

        #expect(imported.windowHotkeys[WindowAction.leftHalf.rawValue]?.keyCode == UInt32(kVK_ANSI_L))
        #expect(imported.windowHotkeys[WindowAction.rightHalf.rawValue] == WindowAction.rightHalf.alternateDefaultHotkey)
        #expect(imported.todoHotkey?.keyCode == UInt32(kVK_ANSI_B))
        #expect(imported.todoAliases.map(\.keyCode) == [UInt32(kVK_ANSI_N)])
    }

    @Test("置顶动作属于窗口分组且默认不抢占快捷键")
    func alwaysOnTopActionConfiguration() {
        #expect(WindowAction.alwaysOnTop.title == "切换窗口置顶")
        #expect(WindowAction.alwaysOnTop.section == "窗口")
        #expect(WindowAction.alwaysOnTop.alternateDefaultHotkey == nil)
        #expect(!WindowAction.alternateDefaults.keys.contains(WindowAction.alwaysOnTop.rawValue))
    }

    @Test("Rectangle 运行时只避让它实际占用的快捷键")
    func rectangleOnlyBlocksOccupiedHotkeys() {
        let alwaysOnTop = HotkeySpec(
            keyCode: UInt32(kVK_ANSI_T), carbonModifiers: UInt32(cmdKey | shiftKey)
        )
        let imported = RectangleImport(
            windowHotkeys: WindowAction.alternateDefaults,
            todoHotkey: nil,
            todoAliases: []
        )
        let occupied = RectangleImporter.occupiedHotkeys(in: imported)

        #expect(occupied.contains(WindowAction.leftHalf.alternateDefaultHotkey!))
        #expect(!occupied.contains(alwaysOnTop))
    }

    @Test("镜像窗口区分单击与拖动并保持鼠标锚点")
    func mirrorPointerGesture() {
        let start = NSPoint(x: 100, y: 200)
        #expect(!MirrorPointerGesture.isDrag(from: start, to: NSPoint(x: 102, y: 201)))
        #expect(MirrorPointerGesture.isDrag(from: start, to: NSPoint(x: 104, y: 200)))
        #expect(MirrorPointerGesture.windowOrigin(
            from: NSPoint(x: 300, y: 400), mouseStart: start, mouseNow: NSPoint(x: 125, y: 180)
        ) == NSPoint(x: 325, y: 380))
    }

    @Test("Shift+F3 隐藏和恢复全部贴图但不销毁窗口")
    func togglesPinnedWindowsVisibility() {
        let controller = PinWindowController(settings: AppSettings())
        let image = NSImage(size: NSSize(width: 40, height: 40))
        let panel = controller.pin(image: image, at: NSPoint(x: 300, y: 300))
        #expect(panel.isVisible)
        controller.toggleHiddenPins()
        #expect(controller.arePinsHidden)
        #expect(!panel.isVisible)
        controller.toggleHiddenPins()
        #expect(!controller.arePinsHidden)
        #expect(panel.isVisible)
        panel.close()
    }
}
