import AppKit
import Carbon.HIToolbox
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum HotkeyID {
        static let launcher: UInt32 = 1
        static let snip: UInt32 = 2
        static let todo: UInt32 = 3
        static let annotate: UInt32 = 4
        static let clipboardPin: UInt32 = 5
        static let toggleHiddenPins: UInt32 = 6
        static let todoAliasBase: UInt32 = 50
        static let windowBase: UInt32 = 100

        static let names: [UInt32: String] = [
            launcher: "呼出面板", snip: "截图贴图", todo: "今日待办", annotate: "屏幕标注",
            clipboardPin: "剪贴板贴图", toggleHiddenPins: "隐藏/显示贴图",
        ]
    }

    /// 改键失败原因文案，nil 表示改键成功
    private func rebindFailureMessage(id: UInt32, to spec: HotkeySpec) -> String? {
        switch hotkeys.rebind(id: id, to: spec) {
        case .ok:
            return nil
        case .usedByOwnHotkey(let other):
            return "\(spec.display) 已分配给「\(HotkeyID.names[other] ?? "其他功能")」"
        case .rejectedBySystem:
            return "\(spec.display) 已被其他应用占用"
        case .notBound:
            return "\(spec.display) 设置失败：该功能未初始化，请重启 App"
        }
    }

    private var statusBar: StatusBarController!
    private var hotkeys: HotkeyManager!
    private var panelController: PanelController!
    private var appIndex: AppIndex!
    private var aliasStore: AliasStore!
    private var clipboardStore: ClipboardStore!
    private var clipboardMonitor: ClipboardMonitor!
    private var pinController: PinWindowController!
    private var todoStore: TodoStore!
    private var todoPanelController: TodoPanelController!
    private var calculationHistory: CalculationHistory!
    private var settings: AppSettings!
    private var settingsWindow: SettingsWindowController!
    private var windowManager: WindowManager!
    private var iPhoneMirrorController: IPhoneMirrorController!
    private var pluginManager: PluginManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = AppSettings()
        windowManager = WindowManager()
        iPhoneMirrorController = IPhoneMirrorController()
        windowManager.iPhoneMirrorController = iPhoneMirrorController

        // 数据层
        aliasStore = AliasStore()
        appIndex = AppIndex(aliasStore: aliasStore)
        clipboardStore = ClipboardStore()
        clipboardStore.maxItems = settings.clipboardMaxItems
        ClipboardStore.shared = clipboardStore
        clipboardMonitor = ClipboardMonitor(store: clipboardStore)
        clipboardMonitor.isEnabled = settings.clipboardEnabled
        clipboardMonitor.start()
        pinController = PinWindowController(settings: settings)
        todoStore = TodoStore(settings: settings)
        TodoStore.shared = todoStore
        todoPanelController = TodoPanelController(store: todoStore)
        calculationHistory = CalculationHistory()

        // 插件系统：管理器负责内置同步、迁移、启停与动态刷新
        pluginManager = PluginManager()
        let pluginRunner = ExternalPluginRunner(manager: pluginManager)

        // 动作执行
        let executor = ActionExecutor()
        executor.onAppLaunched = { [weak self] path in
            self?.appIndex.recordLaunch(path: path)
        }
        executor.clipboardStore = clipboardStore
        executor.pasteService = PasteService(store: clipboardStore, monitor: clipboardMonitor)
        executor.pinController = pinController
        executor.todoStore = todoStore
        executor.todoPanelController = todoPanelController
        executor.calculationHistory = calculationHistory
        executor.pluginRunner = pluginRunner
        executor.aliasStore = aliasStore
        executor.onAliasesChanged = { [weak self] in self?.appIndex.refreshAliases() }

        // 搜索管线
        let coordinator = SearchCoordinator()
        coordinator.register(CalculatorProvider(history: calculationHistory))
        let appLauncher = AppLauncherProvider(index: appIndex)
        coordinator.register(appLauncher)
        coordinator.workbenchProvider = appLauncher  // 空态工作台只跑此来源
        coordinator.register(SystemCommandProvider())
        coordinator.register(SnipProvider(pinController: pinController))
        coordinator.register(ClipboardProvider(store: clipboardStore))
        coordinator.register(FileSearchProvider())
        coordinator.register(TodoProvider(store: todoStore))
        let pluginHost = PluginHostProvider(manager: pluginManager, runner: pluginRunner)
        coordinator.register(pluginHost)
        coordinator.pluginHost = pluginHost  // 插件页结果来源
        pluginManager.onPluginsChanged = { [weak coordinator, weak pluginManager] in
            if let manager = pluginManager, coordinator?.isCurrentPluginUnavailable(manager: manager) == true {
                coordinator?.popToRoot()
            }
            coordinator?.refresh()
        }

        // 内置页面：输入 = 进入计算器页；Tab 进入别名编辑页
        coordinator.registerBuiltin(CalculatorPage(history: calculationHistory))
        coordinator.registerBuiltin(AliasEditorPage(aliasStore: aliasStore))

        panelController = PanelController(coordinator: coordinator, executor: executor)

        // 插件动作的收尾回调：刷新结果 / 关闭面板
        executor.onReloadResults = { coordinator.refresh() }
        executor.onClosePanel = { [weak self] in self?.panelController.hide() }

        // 卸载 App：成功后即时剔出索引并刷新工作台；失败则提示
        executor.onAppUninstalled = { [weak self] path in
            self?.appIndex.remove(path: path)
            coordinator.refresh()
        }
        executor.onUninstallError = { [weak self] _, message in
            self?.presentUninstallError(message)
        }

        // 全局热键
        hotkeys = HotkeyManager()
        hotkeys.install()
        var conflicts: [String] = []
        if !hotkeys.register(id: HotkeyID.launcher, spec: settings.launcherHotkey, action: { [weak self] in
            self?.panelController.toggle()
        }) {
            conflicts.append("\(settings.launcherHotkey.display)（呼出面板）")
        }
        if !hotkeys.register(id: HotkeyID.snip, spec: settings.snipHotkey, action: { [weak self] in
            self?.pinController.captureAndPin()
        }) {
            conflicts.append("\(settings.snipHotkey.display)（截图贴图）")
        }
        if !hotkeys.register(id: HotkeyID.clipboardPin, spec: settings.clipboardPinHotkey, action: { [weak self] in
            self?.pinController.pinFromClipboard()
        }) {
            conflicts.append("\(settings.clipboardPinHotkey.display)（剪贴板贴图）")
        }
        let toggleHiddenPinsHotkey = HotkeySpec(keyCode: UInt32(kVK_F3), carbonModifiers: UInt32(shiftKey))
        if !hotkeys.register(id: HotkeyID.toggleHiddenPins, spec: toggleHiddenPinsHotkey, action: { [weak self] in
            self?.pinController.toggleHiddenPins()
        }) {
            conflicts.append("\(toggleHiddenPinsHotkey.display)（隐藏/显示贴图）")
        }
        if !hotkeys.register(id: HotkeyID.todo, spec: settings.todoHotkey, action: { [weak self] in
            self?.todoPanelController.toggle()
        }) {
            conflicts.append("\(settings.todoHotkey.display)（今日待办）")
        }
        if !hotkeys.register(id: HotkeyID.annotate, spec: settings.annotateHotkey, action: { [weak self] in
            self?.pinController.annotateScreen()
        }) {
            conflicts.append("\(settings.annotateHotkey.display)（屏幕标注）")
        }
        conflicts.append(contentsOf: registerTodoAliases())
        conflicts.append(contentsOf: registerWindowHotkeys())
        if !conflicts.isEmpty {
            notifyHotkeyConflict(conflicts)
        }

        statusBar = StatusBarController()

        // 设置窗口
        settingsWindow = SettingsWindowController(settings: settings) { [unowned self] section in
            AnyView(SettingsView(
                settings: settings,
                onRebindLauncher: { [weak self] spec in
                    self?.rebindFailureMessage(id: HotkeyID.launcher, to: spec)
                },
                onRebindSnip: { [weak self] spec in
                    self?.rebindFailureMessage(id: HotkeyID.snip, to: spec)
                },
                onRebindClipboardPin: { [weak self] spec in
                    self?.rebindFailureMessage(id: HotkeyID.clipboardPin, to: spec)
                },
                onRebindTodo: { [weak self] spec in
                    self?.rebindFailureMessage(id: HotkeyID.todo, to: spec)
                },
                onRebindAnnotate: { [weak self] spec in
                    self?.rebindFailureMessage(id: HotkeyID.annotate, to: spec)
                },
                onRebindWindow: { [weak self] action, spec in
                    self?.rebindWindow(action: action, to: spec)
                },
                onDisableWindow: { [weak self] action in
                    self?.disableWindowHotkey(action)
                },
                onRestoreWindowDefaults: { [weak self] in
                    self?.restoreWindowDefaults() ?? "窗口快捷键已恢复。"
                },
                onImportRectangle: { [weak self] in
                    self?.importRectangle() ?? "无法读取 Rectangle 配置。"
                },
                initialSelection: section,
                onRecordingStateChange: { [weak self] recording in
                    // 录制期间暂停全局热键，避免按到自己的热键被吞掉
                    recording ? self?.hotkeys.suspendAll() : self?.hotkeys.resumeAll()
                },
                onClipboardEnabledChange: { [weak self] enabled in
                    self?.clipboardMonitor.isEnabled = enabled
                },
                onClipboardMaxChange: { [weak self] count in
                    self?.clipboardStore.maxItems = count
                },
                pluginManager: pluginManager
            ))
        }

        // 面板内 ⌘, 打开设置：先收面板，再拉设置窗口
        panelController.onOpenSettings = { [weak self] in
            self?.panelController.hide()
            self?.settingsWindow.show()
        }

        statusBar.onTogglePanel = { [weak self] in self?.panelController.toggle() }
        statusBar.onCaptureScreen = { [weak self] in self?.pinController.captureAndPin() }
        statusBar.onPinClipboard = { [weak self] in self?.pinController.pinFromClipboard() }
        statusBar.onToggleTodo = { [weak self] in self?.todoPanelController.toggle() }
        statusBar.onAnnotateScreen = { [weak self] in self?.pinController.annotateScreen() }
        statusBar.onWindowAction = { [weak self] action in self?.performWindowAction(action) }
        statusBar.onOpenWindowManagementSettings = { [weak self] in
            self?.settingsWindow.show(section: .windowManagement)
        }
        statusBar.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardStore.flush()
        appIndex.flush()
        // 待办无需 flush：EventKit 每次写入即时提交
        calculationHistory.flush()
    }


    private func notifyHotkeyConflict(_ names: [String]) {
        let alert = NSAlert()
        alert.messageText = "全局快捷键注册失败"
        alert.informativeText = "以下快捷键可能已被其他应用占用：\n\(names.joined(separator: "\n"))\n可在设置中更换快捷键，或先通过菜单栏图标使用对应功能。"
        alert.alertStyle = .warning
        alert.runModal()
    }

    /// 卸载 App 失败提示
    private func presentUninstallError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "卸载失败"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: - 窗口管理

    private func windowHotkeyID(_ action: WindowAction) -> UInt32 {
        HotkeyID.windowBase + UInt32(WindowAction.allCases.firstIndex(of: action) ?? 0)
    }

    private func windowHotkeyName(_ action: WindowAction) -> String {
        "窗口：\(action.title)"
    }

    private func registerWindowHotkeys(whileRectangleMayBeRunning: Bool = false) -> [String] {
        let rectangleIsRunning = !NSRunningApplication.runningApplications(
            withBundleIdentifier: RectangleImporter.suiteName
        ).isEmpty
        let occupiedByRectangle: [HotkeySpec]
        if rectangleIsRunning, !whileRectangleMayBeRunning,
           let imported = RectangleImporter.readCurrentConfiguration() {
            occupiedByRectangle = RectangleImporter.occupiedHotkeys(in: imported)
        } else {
            occupiedByRectangle = []
        }
        var conflicts: [String] = []
        for action in WindowAction.allCases {
            guard let spec = settings.windowHotkey(for: action) else { continue }
            // Rectangle 运行时只暂缓它实际占用的组合键，独立快捷键仍应正常注册。
            guard !occupiedByRectangle.contains(spec) else { continue }
            if !hotkeys.register(id: windowHotkeyID(action), spec: spec, action: { [weak self] in
                self?.performWindowAction(action)
            }) {
                conflicts.append("\(spec.display)（\(windowHotkeyName(action))）")
            }
        }
        return conflicts
    }

    private func unregisterWindowHotkeys() {
        for action in WindowAction.allCases {
            hotkeys.unregister(id: windowHotkeyID(action))
        }
    }

    private func rebindWindow(action: WindowAction, to spec: HotkeySpec) -> String? {
        let result = hotkeys.bind(id: windowHotkeyID(action), spec: spec, action: { [weak self] in
            self?.performWindowAction(action)
        })
        switch result {
        case .ok: return nil
        case .usedByOwnHotkey(let other):
            return "\(spec.display) 已分配给「\(hotkeyName(for: other))」"
        case .rejectedBySystem: return "\(spec.display) 已被其他应用占用"
        case .notBound: return "\(spec.display) 设置失败"
        }
    }

    private func disableWindowHotkey(_ action: WindowAction) {
        hotkeys.unregister(id: windowHotkeyID(action))
        settings.setWindowHotkey(nil, for: action)
    }

    private func restoreWindowDefaults() -> String? {
        unregisterWindowHotkeys()
        settings.windowHotkeys = AppSettings.defaultWindowHotkeys
        let conflicts = registerWindowHotkeys()
        return conflicts.isEmpty ? nil : "以下快捷键未能注册：\(conflicts.joined(separator: "、"))"
    }

    private func performWindowAction(_ action: WindowAction) {
        switch windowManager.execute(action) {
        case .success:
            break
        case .pinned:
            NSLog("窗口管理：已置顶当前窗口")
        case .unpinned:
            NSLog("窗口管理：已取消当前窗口置顶")
        case .accessibilityRequired:
            PermissionCenter.requestAccessibility()
            PermissionCenter.showGuide(
                title: "需要辅助功能权限",
                message: "窗口管理需要辅助功能权限来移动和调整其他应用的窗口。授权后请重试。",
                openSettings: PermissionCenter.openAccessibilitySettings
            )
        case .noFocusedWindow:
            NSSound.beep()
        case .unsupportedWindow:
            showWindowError("当前窗口不支持窗口管理操作。")
        case .noRestorePosition:
            showWindowError("没有可还原的窗口位置。")
        case .failed:
            showWindowError("无法修改当前窗口层级；该应用可能限制了辅助功能窗口操作。")
        }
    }

    private func showWindowError(_ message: String) {
        NSSound.beep()
        NSLog("窗口管理：%@", message)
    }

    private func registerTodoAliases() -> [String] {
        var conflicts: [String] = []
        for (index, spec) in settings.todoHotkeyAliases.enumerated() {
            let id = HotkeyID.todoAliasBase + UInt32(index)
            if !hotkeys.register(id: id, spec: spec, action: { [weak self] in
                self?.todoPanelController.toggle()
            }) {
                conflicts.append("\(spec.display)（今日待办别名）")
            }
        }
        return conflicts
    }

    private func unregisterTodoAliases() {
        for index in settings.todoHotkeyAliases.indices {
            hotkeys.unregister(id: HotkeyID.todoAliasBase + UInt32(index))
        }
    }

    private func hotkeyName(for id: UInt32) -> String {
        if let name = HotkeyID.names[id] { return name }
        if id >= HotkeyID.windowBase,
           let action = WindowAction.allCases[safe: Int(id - HotkeyID.windowBase)] {
            return windowHotkeyName(action)
        }
        return "其他功能"
    }

    private func importRectangle() -> String? {
        guard let imported = RectangleImporter.readCurrentConfiguration() else { return nil }
        let alert = NSAlert()
        alert.messageText = "从 Rectangle 导入快捷键"
        alert.informativeText = "\(imported.summary)\n\n确认后会覆盖 Nexus 的窗口快捷键，将 Rectangle 的待办快捷键迁移到「今日待办」，关闭 Rectangle 的登录启动偏好并退出正在运行的 Rectangle。不会卸载 Rectangle。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "导入并停用 Rectangle")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return "已取消导入。" }

        settings.windowHotkeys = imported.windowHotkeys
        if let todoHotkey = imported.todoHotkey { settings.todoHotkey = todoHotkey }
        settings.todoHotkeyAliases = imported.todoAliases

        RectangleImporter.disableLaunchAtLoginPreference()
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: RectangleImporter.suiteName) {
            app.terminate()
        }

        // 给 macOS 一小段时间解除 Rectangle 占用的 Carbon 热键；主线程不阻塞 UI。
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(700)) { [weak self] in
            guard let self else { return }
            let failures = self.activateImportedHotkeys()
            if !failures.isEmpty { self.notifyHotkeyConflict(failures) }
        }
        return "\(imported.summary) 正在切换到 Nexus 快捷键；Rectangle 已请求退出。若“登录项”仍显示 Rectangle，请在系统设置中手动关闭。"
    }

    private func activateImportedHotkeys() -> [String] {
        unregisterWindowHotkeys()
        unregisterTodoAliases()
        var failures = registerWindowHotkeys(whileRectangleMayBeRunning: true)
        let todoResult = hotkeys.bind(id: HotkeyID.todo, spec: settings.todoHotkey, action: { [weak self] in
            self?.todoPanelController.toggle()
        })
        if case .ok = todoResult {} else { failures.append("\(settings.todoHotkey.display)（今日待办）") }
        failures.append(contentsOf: registerTodoAliases())
        return failures
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
