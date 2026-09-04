import AppKit

final class LauncherPanel: NSPanel {
    /// ⌘, 打开设置
    var onOpenSettings: (() -> Void)?

    // borderless 窗口默认拒绝成为 key window，必须 override 搜索框才能拿到焦点
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }

    /// LSUIElement 应用没有主菜单，搜索框的 ⌘A/⌘C/⌘V/⌘X/⌘Z 手动转发给 field editor
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // ⌘, 打开设置（同样因为没有主菜单，只能手动接）。
        // 精确匹配修饰键，免得 ⇧⌘, 之类也误触发
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "," {
            onOpenSettings?()
            return true
        }

        if event.modifierFlags.contains(.command),
           let editor = firstResponder as? NSTextView, editor.isFieldEditor {
            switch event.charactersIgnoringModifiers {
            case "a": editor.selectAll(nil); return true
            case "c": editor.copy(nil); return true
            case "v": editor.paste(nil); return true
            case "x": editor.cut(nil); return true
            case "z":
                if event.modifierFlags.contains(.shift) {
                    editor.undoManager?.redo()
                } else {
                    editor.undoManager?.undo()
                }
                return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}
