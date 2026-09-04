import AppKit
import SwiftUI

/// 便笺式置顶待办浮窗。borderless + nonactivatingPanel：常驻桌面、不抢 App 焦点。
final class TodoPanel: NSPanel {
    static let defaultSize = NSSize(width: 300, height: 500)

    init(store: TodoStore) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        appearance = NSAppearance(named: .darkAqua)
        hasShadow = true
        isMovableByWindowBackground = true  // 空白/标题区拖动；按钮与输入框优先消费点击

        let root = TodoListView(store: store, onClose: { [weak self] in self?.orderOut(nil) })
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: Self.defaultSize)
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
    }

    // 点击输入框/标注时可成为 key（接收键盘，含中文输入），但不激活整个 App
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
