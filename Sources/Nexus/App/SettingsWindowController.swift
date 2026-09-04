import AppKit
import SwiftUI
import Carbon.HIToolbox

/// 菜单栏（LSUIElement）应用没有标准主菜单，因此 NSWindow 不会自动得到 ⌘W。
/// 在窗口层处理可避免依赖应用是否拥有主菜单，也不会影响其他窗口。
private final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == UInt16(kVK_ANSI_W), modifiers == .command {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}

/// 设置窗口。LSUIElement 应用没有 Dock/主窗口，打开设置时临时激活自己。
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: AppSettings
    private let makeView: (SettingsSection) -> AnyView

    init(settings: AppSettings, makeView: @escaping (SettingsSection) -> AnyView) {
        self.settings = settings
        self.makeView = makeView
    }

    func show(section: SettingsSection = .hotkeys) {
        if window == nil {
            let hosting = NSHostingController(rootView: makeView(section))
            let window = SettingsWindow(contentViewController: hosting)
            window.title = "Nexus 设置"
            // NavigationSplitView 侧边栏需要可调尺寸 + 全尺寸内容视图才有系统设置观感
            window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = false
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = CyberpunkTheme.windowNSColor
            window.isOpaque = false
            window.setContentSize(NSSize(width: 720, height: 520))
            window.center()
            self.window = window
        } else if let hosting = window?.contentViewController as? NSHostingController<AnyView> {
            hosting.rootView = makeView(section)
        }
        window?.makeKeyAndOrderFront(nil)
        // accessory 应用需要显式激活，否则设置窗口出现在其他应用后面
        NSApp.activate(ignoringOtherApps: true)
    }
}
