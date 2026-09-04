import AppKit

final class StatusBarController {
    private let statusItem: NSStatusItem
    private let menu: NSMenu

    var onTogglePanel: (() -> Void)?
    var onCaptureScreen: (() -> Void)?
    var onPinClipboard: (() -> Void)?
    var onToggleTodo: (() -> Void)?
    var onAnnotateScreen: (() -> Void)?
    var onWindowAction: ((WindowAction) -> Void)?
    var onOpenWindowManagementSettings: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu = NSMenu()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "command.circle.fill",
                                   accessibilityDescription: "Nexus")
            button.image?.isTemplate = true
            button.contentTintColor = CyberpunkTheme.matrixNSColor
            button.setAccessibilityLabel("Nexus")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        let openItem = NSMenuItem(title: "打开面板", action: #selector(togglePanel), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let snipItem = NSMenuItem(title: "截图贴图", action: #selector(captureScreen), keyEquivalent: "")
        snipItem.target = self
        menu.addItem(snipItem)

        let clipboardPinItem = NSMenuItem(title: "剪贴板贴图", action: #selector(pinClipboard), keyEquivalent: "")
        clipboardPinItem.target = self
        menu.addItem(clipboardPinItem)

        let annotateItem = NSMenuItem(title: "屏幕标注", action: #selector(annotateScreen), keyEquivalent: "")
        annotateItem.target = self
        menu.addItem(annotateItem)

        let todoItem = NSMenuItem(title: "今日待办", action: #selector(toggleTodo), keyEquivalent: "")
        todoItem.target = self
        menu.addItem(todoItem)

        let windowItem = NSMenuItem(title: "窗口管理", action: nil, keyEquivalent: "")
        windowItem.submenu = makeWindowMenu()
        menu.addItem(windowItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 Nexus", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

    }

    func showCommandMenu() {
        guard let button = statusItem.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 4), in: button)
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showCommandMenu()
        } else {
            onTogglePanel?()
        }
    }

    @objc private func togglePanel() { onTogglePanel?() }
    @objc private func captureScreen() { onCaptureScreen?() }
    @objc private func pinClipboard() { onPinClipboard?() }
    @objc private func toggleTodo() { onToggleTodo?() }
    @objc private func annotateScreen() { onAnnotateScreen?() }
    @objc private func windowAction(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let action = WindowAction(rawValue: rawValue) else { return }
        onWindowAction?(action)
    }
    @objc private func openWindowManagementSettings() { onOpenWindowManagementSettings?() }
    @objc private func openSettings() { onOpenSettings?() }

    private func makeWindowMenu() -> NSMenu {
        let menu = NSMenu()
        var previousSection: String?
        for action in WindowAction.allCases {
            if let previousSection, previousSection != action.section {
                menu.addItem(.separator())
            }
            let item = NSMenuItem(title: action.title, action: #selector(windowAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.rawValue
            menu.addItem(item)
            previousSection = action.section
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "窗口管理设置…", action: #selector(openWindowManagementSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        return menu
    }
}
