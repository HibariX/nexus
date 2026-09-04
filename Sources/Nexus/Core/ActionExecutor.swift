import AppKit

/// 所有 ResultAction 的统一执行入口
final class ActionExecutor {
    var onAppLaunched: ((String) -> Void)?
    var pasteService: PasteService?
    var clipboardStore: ClipboardStore?
    var pinController: PinWindowController?
    var todoStore: TodoStore?
    var todoPanelController: TodoPanelController?
    var calculationHistory: CalculationHistory?
    var pluginRunner: ExternalPluginRunner?
    var aliasStore: AliasStore?
    /// 清理模式控制器（AppDelegate 注入）
    var cleanupMode: CleanupModeController?
    /// 别名变更后回调（通常接 appIndex.refreshAliases）
    var onAliasesChanged: (() -> Void)?
    /// 插件动作要求刷新结果时回调（通常接 coordinator.refresh）
    var onReloadResults: (() -> Void)?
    /// 插件动作要求关闭面板时回调（通常接 panelController.hide）
    var onClosePanel: (() -> Void)?
    /// App 卸载成功（已移入废纸篓）后回调，参数为 path
    var onAppUninstalled: ((String) -> Void)?
    /// App 卸载失败（无法移入废纸篓）回调，参数为 path + 错误文案
    var onUninstallError: ((String, String) -> Void)?

    func execute(_ action: ResultAction) {
        switch action {
        case .launchApp(let path):
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
            onAppLaunched?(path)

        case .openFile(let path):
            NSWorkspace.shared.open(URL(fileURLWithPath: path))

        case .revealInFinder(let path):
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])

        case .uninstallApp(let path):
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                onAppUninstalled?(path)
            } catch {
                onUninstallError?(path, error.localizedDescription)
            }

        case .copyText(let text):
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)

        case .copyCalculation(let expression, let result):
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(result, forType: .string)
            calculationHistory?.record(expression: expression, result: result)

        case .copyCalculationFull(let expression, let result):
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString("\(expression) = \(result)", forType: .string)
            calculationHistory?.record(expression: expression, result: result)

        case .pasteClip(let id):
            guard let store = clipboardStore,
                  let item = store.items.first(where: { $0.id == id }) else { return }
            Task { await pasteService?.paste(item) }

        case .runSystem(let command):
            SystemCommandRunner.run(command)

        case .toggleSleepDisabled:
            // 保持面板：异步以管理员权限切换，完成后回调刷新 subtitle（绝不关面板）。
            // 刷新只能放在 toggle 返回之后——否则会在密码框停留期间读到旧状态。
            Task { @MainActor in
                _ = await SleepControl.toggle()
                onReloadResults?()
            }

        case .startCleanupMode:
            // 面板已在 executeSelected 的 default 里先行收起（清理要盖满全屏）。
            // toggle 兼「已激活则退出」的极端兜底。不调 onReloadResults：清理期间后台空跑搜索无意义，
            // 倒计时更新由 controller 自身的 timer 驱动。
            cleanupMode?.toggle()

        case .pinClipboardContent:
            pinController?.pinFromClipboard()

        case .addTodo(let title):
            todoStore?.add(title)
            todoPanelController?.show()  // 添加后弹出浮窗给用户确认

        case .toggleTodo(let id):
            todoStore?.toggle(id: id)

        case .showTodoPanel:
            todoPanelController?.show()

        case .replaceQuery, .pushPage:
            break  // 由 SearchCoordinator.executeSelected 处理，这里不应到达

        case .saveAlias(let path, let alias):
            aliasStore?.add(alias, for: path)
            onAliasesChanged?()

        case .removeAlias(let path, let alias):
            aliasStore?.remove(alias, for: path)
            onAliasesChanged?()

        case .pluginAction(let pluginId, let actionId, let payload):
            guard let runner = pluginRunner else { return }
            Task { @MainActor in
                let outcome = await runner.action(pluginId: pluginId, actionId: actionId, payload: payload)
                if let text = outcome.copy {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(text, forType: .string)
                    if outcome.concealed == true {
                        pb.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
                        pb.setData(Data(), forType: .init("org.nspasteboard.TransientType"))
                    }
                }
                if outcome.reload == true {
                    onReloadResults?()
                }
                if outcome.keepOpen != true {
                    onClosePanel?()
                }
            }
        }
    }
}
