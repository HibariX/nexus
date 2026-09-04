import AppKit
import Carbon.HIToolbox

/// 把历史条目写回剪贴板并向前台应用合成 ⌘V。
/// nonactivating panel 下前台 app 从未失去 frontmost，无需焦点还原。
final class PasteService {
    private let store: ClipboardStore
    private let monitor: ClipboardMonitor

    init(store: ClipboardStore, monitor: ClipboardMonitor) {
        self.store = store
        self.monitor = monitor
    }

    /// 仅写回剪贴板，不粘贴
    func copyToClipboard(_ item: ClipItem) {
        monitor.ignoreNextChange()
        write(item, to: NSPasteboard.general)
    }

    func paste(_ item: ClipItem) async {
        guard PermissionCenter.hasAccessibility else {
            PermissionCenter.requestAccessibility()
            PermissionCenter.showGuide(
                title: "需要辅助功能权限",
                message: "粘贴到其他应用需要辅助功能权限来模拟 ⌘V 按键。请在系统设置中允许 MyRaycast，然后重试。",
                openSettings: PermissionCenter.openAccessibilitySettings
            )
            return
        }

        if IsSecureEventInputEnabled() {
            // 密码框激活时合成按键会被系统吞掉
            copyToClipboard(item)
            return
        }

        copyToClipboard(item)
        try? await Task.sleep(for: .milliseconds(80))

        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func write(_ item: ClipItem, to pb: NSPasteboard) {
        pb.clearContents()
        switch item.kind {
        case .text:
            if let text = item.text {
                pb.setString(text, forType: .string)
            }
        case .image:
            if let data = store.imageData(for: item.id) {
                pb.setData(data, forType: .png)
            }
        }
    }
}
