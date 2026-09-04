import AppKit

/// 今日待办浮窗的显隐管理 + 位置记忆（AppKit 原生 frameAutosaveName）
final class TodoPanelController {
    private let store: TodoStore
    private var panel: TodoPanel?

    init(store: TodoStore) {
        self.store = store
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        let panel = ensurePanel()
        panel.makeKeyAndOrderFront(nil)
        // 面板常驻不销毁，SwiftUI 不会再走 onAppear，每次显示时主动对齐系统数据
        Task { await store.refresh() }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    private func ensurePanel() -> TodoPanel {
        if let panel { return panel }
        let panel = TodoPanel(store: store)
        // 恢复上次位置；无记忆时首帧 origin 为 0，落到主屏右上角
        panel.setFrameAutosaveName("TodoPanel")
        if panel.frame.origin == .zero, let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.maxX - panel.frame.width - 24,
                                         y: visible.maxY - panel.frame.height - 24))
        }
        self.panel = panel
        return panel
    }
}
