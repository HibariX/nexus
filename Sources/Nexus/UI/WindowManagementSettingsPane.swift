import SwiftUI

/// 可选快捷键录制器：窗口动作即使未分配全局键，也仍然可以从菜单执行。
private struct OptionalKeyRecorderField: NSViewRepresentable {
    @Binding var spec: HotkeySpec?
    var onBeginRecording: () -> Void
    var onEndRecording: () -> Void

    func makeNSView(context: Context) -> KeyRecorderView {
        let view = KeyRecorderView()
        view.spec = spec
        view.onChange = { spec = $0 }
        view.onBeginRecording = onBeginRecording
        view.onEndRecording = onEndRecording
        return view
    }

    func updateNSView(_ view: KeyRecorderView, context: Context) {
        if !view.isRecording { view.spec = spec }
    }
}

struct WindowManagementSettingsPane: View {
    @Bindable var settings: AppSettings
    var onRebind: (WindowAction, HotkeySpec) -> String?
    var onDisable: (WindowAction) -> Void
    var onRestoreDefaults: () -> String?
    var onImportRectangle: () -> String
    var onRecordingStateChange: (Bool) -> Void

    @State private var message: String?

    var body: some View {
        Section {
            LabeledContent("辅助功能") {
                if PermissionCenter.hasAccessibility {
                    Label("已授权", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(CyberpunkTheme.matrix)
                } else {
                    Button("去授权") { PermissionCenter.openAccessibilitySettings() }
                }
            }
            Text("移动和调整其他应用窗口需要辅助功能权限。")
                .font(.caption)
                .foregroundStyle(CyberpunkTheme.secondaryText)
        }

        ForEach(groupedActions, id: \.0) { group, actions in
            Section(group) {
                ForEach(actions) { action in
                    LabeledContent(action.title) {
                        HStack(spacing: 8) {
                            OptionalKeyRecorderField(
                                spec: binding(for: action),
                                onBeginRecording: { onRecordingStateChange(true) },
                                onEndRecording: { onRecordingStateChange(false) }
                            )
                            Button("停用") { onDisable(action) }
                                .controlSize(.small)
                                .disabled(settings.windowHotkey(for: action) == nil)
                        }
                    }
                }
            }
        }

        Section {
            Button("从 Rectangle 导入…") { message = onImportRectangle() }
            Button("恢复 Rectangle 备用默认快捷键") {
                message = onRestoreDefaults()
            }
        } header: {
            Text("迁移")
        } footer: {
            if let message {
                Text(message).font(.caption).foregroundStyle(CyberpunkTheme.secondaryText)
            } else {
                Text("导入会先显示摘要；确认后 Nexus 会尝试关闭 Rectangle 的登录启动偏好并退出正在运行的 Rectangle。")
                    .font(.caption).foregroundStyle(CyberpunkTheme.secondaryText)
            }
        }
        .tint(CyberpunkTheme.matrix)
    }

    private var groupedActions: [(String, [WindowAction])] {
        let order = ["半屏", "四角", "三分屏", "窗口", "显示器", "仅移动"]
        return order.compactMap { title in
            let actions = WindowAction.allCases.filter { $0.section == title }
            return actions.isEmpty ? nil : (title, actions)
        }
    }

    private func binding(for action: WindowAction) -> Binding<HotkeySpec?> {
        Binding(
            get: { settings.windowHotkey(for: action) },
            set: { spec in
                guard let spec else {
                    onDisable(action)
                    return
                }
                if let error = onRebind(action, spec) {
                    message = error
                } else {
                    settings.setWindowHotkey(spec, for: action)
                    message = nil
                }
            }
        )
    }
}
