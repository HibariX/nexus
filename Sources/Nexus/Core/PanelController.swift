import AppKit
import SwiftUI

final class PanelController {
    private let panel: LauncherPanel
    let coordinator: SearchCoordinator
    let executor: ActionExecutor

    private static let panelSize = LauncherLayout.size

    init(coordinator: SearchCoordinator, executor: ActionExecutor, settings: AppSettings) {
        self.coordinator = coordinator
        self.executor = executor

        panel = LauncherPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            // nonactivating：面板接收键盘但前台 app 保持 frontmost，
            // 这是「粘贴回原应用」无需焦点还原的关键
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = false

        let rootView = LauncherView(coordinator: coordinator, executor: executor, settings: settings)
        panel.contentView = NSHostingView(rootView: rootView)

        coordinator.onDismiss = { [weak self] in self?.hide() }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    /// 面板内按 ⌘, 的回调
    var onOpenSettings: (() -> Void)? {
        get { panel.onOpenSettings }
        set { panel.onOpenSettings = newValue }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        coordinator.clearShutdown()
        coordinator.notePanelShown()
        positionOnActiveScreen()
        coordinator.refresh()
        panel.makeKeyAndOrderFront(nil)
        // 不调 NSApp.activate —— 会破坏 nonactivating 语义
    }

    func hide() {
        guard panel.isVisible else { return }
        // 开启「减少动态」时，跳过 CRT 关机动画，直接隐藏
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.orderOut(nil)
            coordinator.cancelSearch()
            coordinator.popToRoot()
            coordinator.clearShutdown()
            return
        }
        // CRT 关机：先播 SwiftUI 退场动画（垂直收拢成亮线），动画结束后再真正隐藏
        coordinator.beginShutdown()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            self.coordinator.cancelSearch()
            self.coordinator.popToRoot()
            self.coordinator.clearShutdown()
        }
    }

    private func positionOnActiveScreen() {
        let screen = screenWithMouse() ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = Self.panelSize
        let x = frame.midX - size.width / 2
        let y = frame.midY - size.height / 2
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private func screenWithMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }
}
