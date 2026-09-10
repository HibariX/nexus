import SwiftUI
import ServiceManagement
import AppKit

// MARK: - 分区定义

enum SettingsSection: String, CaseIterable, Identifiable {
    case hotkeys
    case clipboard
    case screenshot
    case windowManagement
    case plugins
    case general
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hotkeys: return "快捷键"
        case .clipboard: return "剪贴板"
        case .screenshot: return "截图"
        case .windowManagement: return "窗口管理"
        case .plugins: return "插件"
        case .general: return "通用"
        case .permissions: return "隐私与权限"
        }
    }

    var subtitle: String {
        switch self {
        case .hotkeys: return "自定义全局快捷键，点击录制框后按下新的组合键。"
        case .clipboard: return "管理剪贴板历史的记录行为与容量。"
        case .screenshot: return "截图保存目录与 OCR 识别语言。"
        case .windowManagement: return "用全局快捷键快速整理其他应用的窗口。"
        case .plugins: return "安装、启停和卸载 Nexus 插件。"
        case .general: return "启动与其他通用行为。"
        case .permissions: return "各功能所需的系统权限状态。"
        }
    }

    var iconName: String {
        switch self {
        case .hotkeys: return "command"
        case .clipboard: return "doc.on.clipboard.fill"
        case .screenshot: return "camera.viewfinder"
        case .windowManagement: return "rectangle.3.group.fill"
        case .plugins: return "puzzlepiece.extension.fill"
        case .general: return "gearshape.fill"
        case .permissions: return "hand.raised.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .hotkeys: return CyberpunkTheme.matrix
        case .clipboard: return CyberpunkTheme.cyan
        case .screenshot: return CyberpunkTheme.amber
        case .windowManagement: return CyberpunkTheme.cyan
        case .plugins: return CyberpunkTheme.amber
        case .general: return CyberpunkTheme.secondaryText
        case .permissions: return CyberpunkTheme.matrix
        }
    }
}

/// 终端主题分区图标：深色底 + 彩色描边，保留系统设置的识别结构。
private struct SectionIcon: View {
    let section: SettingsSection
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(CyberpunkTheme.surface)
            .frame(width: size, height: size)
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .strokeBorder(section.iconColor.opacity(0.82), lineWidth: 1)
            }
            .overlay(
                Image(systemName: section.iconName)
                    .font(.system(size: size * 0.55, weight: .medium))
                    .foregroundStyle(section.iconColor)
            )
    }
}

// MARK: - 根视图（侧边栏 + 内容区）

struct SettingsView: View {
    @Bindable var settings: AppSettings
    /// 改键回调：返回 false 表示新键被占用
    /// 改键回调：返回 nil 表示成功，否则是展示给用户的失败原因
    var onRebindLauncher: (HotkeySpec) -> String?
    var onRebindSnip: (HotkeySpec) -> String?
    var onRebindClipboardPin: (HotkeySpec) -> String?
    var onRebindTodo: (HotkeySpec) -> String?
    var onRebindAnnotate: (HotkeySpec) -> String?
    var onRebindWindow: (WindowAction, HotkeySpec) -> String?
    var onDisableWindow: (WindowAction) -> Void
    var onRestoreWindowDefaults: () -> String?
    var onImportRectangle: () -> String
    var initialSelection: SettingsSection = .hotkeys
    var onRecordingStateChange: (Bool) -> Void
    var onClipboardEnabledChange: (Bool) -> Void
    var onClipboardMaxChange: (Int) -> Void
    var pluginManager: PluginManager

    @State private var selection: SettingsSection = .hotkeys

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label {
                    Text(section.title)
                } icon: {
                    SectionIcon(section: section)
                }
                .tag(section)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(CyberpunkTheme.panelBackground)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            detailPane
                .navigationTitle(selection.title)
        }
        .frame(minWidth: 680, minHeight: 460)
        .background(CyberpunkTheme.windowBackground)
        .tint(CyberpunkTheme.matrix)
        .preferredColorScheme(.dark)
        .onAppear { selection = initialSelection }
    }

    @ViewBuilder
    private var detailPane: some View {
        Form {
            Section {
                pageHeader
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            switch selection {
            case .hotkeys: hotkeysPane
            case .clipboard: clipboardPane
            case .screenshot: screenshotPane
            case .windowManagement:
                WindowManagementSettingsPane(
                    settings: settings,
                    onRebind: onRebindWindow,
                    onDisable: onDisableWindow,
                    onRestoreDefaults: onRestoreWindowDefaults,
                    onImportRectangle: onImportRectangle,
                    onRecordingStateChange: onRecordingStateChange
                )
            case .plugins: PluginSettingsPane(manager: pluginManager)
            case .general: generalPane
            case .permissions: PermissionsPane()
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(CyberpunkTheme.windowBackground)
        .tint(CyberpunkTheme.matrix)
    }

    /// 系统设置同款：居中大图标 + 标题 + 说明
    private var pageHeader: some View {
        VStack(spacing: 8) {
            SectionIcon(section: selection, size: 56)
            Text(selection.title)
                .font(CyberpunkTheme.monoFont(size: 22, weight: .bold))
            Text(selection.subtitle)
                .font(.callout)
                .foregroundStyle(CyberpunkTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: 快捷键

    @State private var rebindError: String?

    @ViewBuilder
    private var hotkeysPane: some View {
        Section {
            LabeledContent("呼出面板") {
                KeyRecorderField(
                    spec: Binding(
                        get: { settings.launcherHotkey },
                        set: { newSpec in
                            if let error = onRebindLauncher(newSpec) {
                                rebindError = error
                            } else {
                                settings.launcherHotkey = newSpec
                                rebindError = nil
                            }
                        }
                    ),
                    onBeginRecording: { onRecordingStateChange(true) },
                    onEndRecording: { onRecordingStateChange(false) }
                )
            }
            LabeledContent("截图贴图") {
                KeyRecorderField(
                    spec: Binding(
                        get: { settings.snipHotkey },
                        set: { newSpec in
                            if let error = onRebindSnip(newSpec) {
                                rebindError = error
                            } else {
                                settings.snipHotkey = newSpec
                                rebindError = nil
                            }
                        }
                    ),
                    onBeginRecording: { onRecordingStateChange(true) },
                    onEndRecording: { onRecordingStateChange(false) }
                )
            }
            LabeledContent("剪贴板贴图") {
                KeyRecorderField(
                    spec: Binding(
                        get: { settings.clipboardPinHotkey },
                        set: { newSpec in
                            if let error = onRebindClipboardPin(newSpec) {
                                rebindError = error
                            } else {
                                settings.clipboardPinHotkey = newSpec
                                rebindError = nil
                            }
                        }
                    ),
                    onBeginRecording: { onRecordingStateChange(true) },
                    onEndRecording: { onRecordingStateChange(false) }
                )
            }
            LabeledContent("屏幕标注") {
                KeyRecorderField(
                    spec: Binding(
                        get: { settings.annotateHotkey },
                        set: { newSpec in
                            if let error = onRebindAnnotate(newSpec) {
                                rebindError = error
                            } else {
                                settings.annotateHotkey = newSpec
                                rebindError = nil
                            }
                        }
                    ),
                    onBeginRecording: { onRecordingStateChange(true) },
                    onEndRecording: { onRecordingStateChange(false) }
                )
            }
            LabeledContent("今日待办") {
                KeyRecorderField(
                    spec: Binding(
                        get: { settings.todoHotkey },
                        set: { newSpec in
                            if let error = onRebindTodo(newSpec) {
                                rebindError = error
                            } else {
                                settings.todoHotkey = newSpec
                                rebindError = nil
                            }
                        }
                    ),
                    onBeginRecording: { onRecordingStateChange(true) },
                    onEndRecording: { onRecordingStateChange(false) }
                )
            }
        } footer: {
            if let rebindError {
                Text(rebindError)
                    .font(.caption)
                    .foregroundStyle(CyberpunkTheme.danger)
            }
        }
    }

    // MARK: 剪贴板

    @ViewBuilder
    private var clipboardPane: some View {
        Section {
            Toggle("启用剪贴板历史", isOn: Binding(
                get: { settings.clipboardEnabled },
                set: { enabled in
                    settings.clipboardEnabled = enabled
                    onClipboardEnabledChange(enabled)
                }
            ))
            Picker("最大保留条数", selection: Binding(
                get: { settings.clipboardMaxItems },
                set: { count in
                    settings.clipboardMaxItems = count
                    onClipboardMaxChange(count)
                }
            )) {
                Text("100").tag(100)
                Text("300").tag(300)
                Text("500").tag(500)
                Text("1000").tag(1000)
            }
            .disabled(!settings.clipboardEnabled)
        } footer: {
            Text("在面板中输入 clip 或「剪贴板」即可搜索历史。密码管理器复制的机密内容不会被记录。")
                .font(.caption)
                .foregroundStyle(CyberpunkTheme.secondaryText)
        }
    }

    // MARK: 截图

    @ViewBuilder
    private var screenshotPane: some View {
        Section {
            LabeledContent("保存目录") {
                HStack(spacing: 8) {
                    Text(settings.snipSaveDirectory)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(CyberpunkTheme.secondaryText)
                    Button("选择…") { chooseSaveDirectory() }
                }
            }
        } footer: {
            Text("标注工具条点「保存」时，截图以 Snip-时间戳.png 存到此目录。")
                .font(.caption)
                .foregroundStyle(CyberpunkTheme.secondaryText)
        }

        Section {
            ForEach(AppSettings.ocrLanguageOptions) { option in
                Toggle(option.name, isOn: Binding(
                    get: { settings.ocrLanguages.contains(option.code) },
                    set: { on in
                        var langs = settings.ocrLanguages
                        if on {
                            if !langs.contains(option.code) { langs.append(option.code) }
                        } else {
                            langs.removeAll { $0 == option.code }
                        }
                        settings.ocrLanguages = langs
                    }
                ))
            }
        } header: {
            Text("OCR 识别语言")
        } footer: {
            Text("勾选的语言用于 Vision 文字识别，可多选；靠前的语言识别优先级更高。")
                .font(.caption)
                .foregroundStyle(CyberpunkTheme.secondaryText)
        }
    }

    private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: settings.snipSaveDirectory)
        if panel.runModal() == .OK, let url = panel.url {
            settings.snipSaveDirectory = url.path
        }
    }

    // MARK: 通用

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    @ViewBuilder
    private var generalPane: some View {
        Section {
            Toggle("开机自启", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
        } footer: {
            Text("登录时在后台自动启动 Nexus（仅菜单栏图标，无窗口打扰）。")
                .font(.caption)
                .foregroundStyle(CyberpunkTheme.secondaryText)
        }

        Section {
            Picker("清理模式时长", selection: Binding(
                get: { settings.cleanupModeDuration },
                set: { settings.cleanupModeDuration = $0 }
            )) {
                Text("30 秒").tag(30)
                Text("60 秒").tag(60)
                Text("120 秒").tag(120)
                Text("300 秒").tag(300)
                Text("10 分钟").tag(600)
            }
        } footer: {
            Text("启动清理模式后临时屏蔽键盘与鼠标输入，倒计时结束或按 Esc 恢复。")
                .font(.caption)
                .foregroundStyle(CyberpunkTheme.secondaryText)
        }

        Section {
            Picker("选中特效", selection: Binding(
                get: { settings.focusEffect },
                set: { settings.focusEffect = $0 }
            )) {
                ForEach(FocusEffect.allCases) { effect in
                    Text(effect.displayName).tag(effect)
                }
            }
        } footer: {
            Text("工作台选中项的 Focus 特效：「扫描线 + 故障」为 CRT 扫描线扫过；「跑马灯」为亮块绕边框追光；「静态描边」不动。系统开启「减少动态」时统一降级为静态描边。")
                .font(.caption)
                .foregroundStyle(CyberpunkTheme.secondaryText)
        }
    }
}

// MARK: - 权限页（独立 View，便于刷新状态）

private struct PermissionsPane: View {
    @State private var refreshTick = 0

    var body: some View {
        Section {
            permissionRow(
                name: "辅助功能",
                granted: PermissionCenter.hasAccessibility,
                detail: "粘贴历史、窗口管理与菜单栏图标移动",
                openSettings: PermissionCenter.openAccessibilitySettings
            )
            permissionRow(
                name: "屏幕录制",
                granted: PermissionCenter.hasScreenCapture,
                detail: "截图贴图与屏幕标注",
                openSettings: PermissionCenter.openScreenCaptureSettings
            )
            permissionRow(
                name: "粘贴板",
                granted: nil,
                detail: "读取剪贴板内容。macOS 26 隐私机制无公开状态接口，无法自动检测；点击「立即请求授权」拉起系统授权",
                openSettings: PermissionCenter.openPasteboardSettings,
                requestAccess: Self.requestPasteboardAccess
            )
        } footer: {
            HStack {
                Text("授权后如状态未更新，点击刷新。")
                    .font(.caption)
                    .foregroundStyle(CyberpunkTheme.secondaryText)
                Spacer()
                Button("刷新状态") { refreshTick += 1 }
                    .controlSize(.small)
            }
        }
        .id(refreshTick)
    }

    @ViewBuilder
    private func permissionRow(name: String, granted: Bool?, detail: String,
                               openSettings: @escaping () -> Void,
                               requestAccess: (() -> Void)? = nil) -> some View {
        LabeledContent {
            if granted == true {
                Label("已授权", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(CyberpunkTheme.matrix)
                    .labelStyle(.titleAndIcon)
                    .font(.callout)
            } else if granted == false {
                Button("去授权") { openSettings() }
                    .controlSize(.regular)
            } else {
                // 状态未知（无公开检测接口，如 macOS 26 剪贴板权限）：优先提供「立即请求授权」
                // 拉起系统授权窗，同时保留「打开设置」入口。
                HStack(spacing: 8) {
                    if let requestAccess {
                        Button("立即请求授权") { requestAccess() }
                            .controlSize(.regular)
                    }
                    Button("打开设置") { openSettings() }
                        .controlSize(.small)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(detail).font(.caption).foregroundStyle(CyberpunkTheme.secondaryText)
            }
        }
        .padding(.vertical, 2)
    }

    /// 「立即请求授权」：触发一次剪贴板读取把系统授权窗拉起，并提示用户后续操作。
    private static func requestPasteboardAccess() {
        PermissionCenter.requestPasteboardAccess()
        let alert = NSAlert()
        alert.messageText = "已触发剪贴板授权请求"
        alert.informativeText = "若系统弹出「允许 \(PermissionCenter.appName) 从其他 App 粘贴」，请选择允许；授权后可在「系统设置 → 隐私与安全性 → 从其他 App 粘贴」确认。\n\n若未弹出任何提示，说明当前系统尚未启用该隐私机制，剪贴板历史读取本身不受限。"
        alert.runModal()
    }
}
