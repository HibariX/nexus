import AppKit
import SwiftUI

/// NSTextField 包装：nonactivating panel 下 SwiftUI @FocusState 不可靠，
/// 用 makeFirstResponder 保证呼出即可输入；↑↓/回车经 doCommandBy 拦截。
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    /// 工作台网格的左右移动；返回 true 表示已处理（拦截，不移动光标）
    var onMoveLeft: () -> Bool
    var onMoveRight: () -> Bool
    var onSubmit: () -> Void
    /// cmd+回车：对计算结果复制「表达式 = 结果」
    var onSubmitCopyExpression: () -> Void
    var onEscape: () -> Void
    /// 搜索框为空时按退格返回上一层；返回 true 表示已处理（拦截删除）
    var onBackIfEmpty: () -> Bool
    /// Tab 触发动作（如给选中 App 设别名）；返回 true 表示已处理
    var onActionKey: () -> Bool

    func makeNSView(context: Context) -> FocusGrabbingTextField {
        let field = FocusGrabbingTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = CyberpunkTheme.monoNSFont(size: 22)
        field.textColor = CyberpunkTheme.matrixBrightNSColor
        field.appearance = NSAppearance(named: .darkAqua)
        field.placeholderAttributedString = Self.placeholderString(placeholder)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: FocusGrabbingTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderAttributedString?.string != placeholder {
            nsView.placeholderAttributedString = Self.placeholderString(placeholder)
        }
    }

    private static func placeholderString(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .foregroundColor: CyberpunkTheme.mutedTextNSColor,
            .font: CyberpunkTheme.monoNSFont(size: 22),
        ])
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField
        init(_ parent: SearchField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onMoveUp(); return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onMoveDown(); return true
            case #selector(NSResponder.moveLeft(_:)):
                // 仅工作台空搜索框时拦截用于网格左移；有文本时放行让光标移动
                if textView.string.isEmpty, parent.onMoveLeft() { return true }
                return false
            case #selector(NSResponder.moveRight(_:)):
                if textView.string.isEmpty, parent.onMoveRight() { return true }
                return false
            case #selector(NSResponder.insertTab(_:)):
                if parent.onActionKey() { return true }
                return false
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
                 #selector(NSResponder.insertLineBreak(_:)):
                // cmd+回车走「复制算式+结果」；cmd 修饰下 field editor 可能派发后两个 selector，一并归拢
                if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                    parent.onSubmitCopyExpression()
                } else {
                    parent.onSubmit()
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape(); return true
            case #selector(NSResponder.deleteBackward(_:)):
                // 搜索框为空时，退格返回上一层
                if textView.string.isEmpty, parent.onBackIfEmpty() { return true }
                return false
            default:
                return false
            }
        }
    }
}

final class FocusGrabbingTextField: NSTextField {
    private var keyObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        // 面板 orderOut/orderFront 复用同一视图，viewDidMoveToWindow 只触发一次；
        // 监听窗口成为 key，保证每次呼出都重新聚焦并全选上次内容
        if let old = keyObserver {
            NotificationCenter.default.removeObserver(old)
            keyObserver = nil
        }
        if let window {
            keyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                // queue: .main 已保证回调在主线程，编译器证明不了，运行期断言兜底
                MainActor.assumeIsolated {
                    self?.grabFocus()
                }
            }
        }
        grabFocus()
    }

    /// 聚焦并全选：上次输入可见，直接键入即覆盖，也可继续编辑
    func grabFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
            (currentEditor() as? NSTextView)?.insertionPointColor = CyberpunkTheme.matrixNSColor
            self.selectText(nil)
        }
    }
}
