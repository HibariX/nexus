import SwiftUI
import UniformTypeIdentifiers

struct PluginSettingsPane: View {
    @Bindable var manager: PluginManager
    @State private var isImporting = false
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var pendingImport: PluginImportCandidate?
    @State private var pendingDelete: PluginRecord?

    var body: some View {
        Section {
            HStack {
                Text("已安装 (manager.plugins.count) 个插件")
                    .foregroundStyle(CyberpunkTheme.secondaryText)
                Spacer()
                Button {
                    isImporting = true
                } label: {
                    Label("安装插件", systemImage: "plus")
                }
                .disabled(isBusy)
                Button {
                    manager.refresh()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .help("重新扫描插件目录")
            }
            if let message = manager.lastMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(CyberpunkTheme.matrix)
            }
        }

        Section {
            if manager.plugins.isEmpty {
                ContentUnavailableView("暂无插件", systemImage: "puzzlepiece.extension", description: Text("点击右上角安装本地插件"))
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(manager.plugins) { record in
                    pluginRow(record)
                }
            }
        } header: {
            Text("插件列表")
        } footer: {
            Text("插件在独立进程中运行。导入 ZIP 前会检查路径安全性和入口权限。")
                .font(.caption)
                .foregroundStyle(CyberpunkTheme.secondaryText)
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.folder, .zip],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            importPlugin(url)
        }
        .alert("插件操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .alert("替换现有插件？", isPresented: Binding(
            get: { pendingImport != nil },
            set: { if !$0, let candidate = pendingImport { manager.discard(candidate); pendingImport = nil } }
        )) {
            Button("替换", role: .destructive) {
                guard let candidate = pendingImport else { return }
                pendingImport = nil
                perform { try manager.install(candidate) }
            }
            Button("取消", role: .cancel) {
                if let candidate = pendingImport { manager.discard(candidate) }
                pendingImport = nil
            }
        } message: {
            if let candidate = pendingImport {
                Text(replaceMessage(for: candidate))
            }
        }
        .alert("卸载插件？", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("移到废纸篓", role: .destructive) {
                guard let record = pendingDelete else { return }
                pendingDelete = nil
                perform { try manager.uninstall(record) }
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text(deleteMessage)
        }
    }

    private var deleteMessage: String {
        let name = pendingDelete?.displayName ?? "此插件"
        return "“\(name)”将从 Nexus 移除，可在废纸篓中恢复。"
    }

    private func replaceMessage(for candidate: PluginImportCandidate) -> String {
        "“\(candidate.manifest.name)”将替换当前版本。现有插件会在失败时保留。"
    }

    @ViewBuilder
    private func pluginRow(_ record: PluginRecord) -> some View {
        HStack(spacing: 12) {
            IconView(source: iconSource(for: record))
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(record.displayName)
                    Text(record.origin == .bundled ? "内置" : "用户")
                        .font(.caption2)
                        .foregroundStyle(CyberpunkTheme.secondaryText)
                }
                Text(record.summary)
                    .font(.caption)
                    .foregroundStyle(CyberpunkTheme.secondaryText)
                    .lineLimit(2)
            }
            Spacer()
            if record.health == .ready {
                Toggle("启用", isOn: Binding(
                    get: { record.isEnabled },
                    set: { manager.setEnabled($0, pluginID: record.manifest?.id ?? "") }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .help(record.isEnabled ? "停用插件" : "启用插件")
            } else {
                Text("损坏")
                    .font(.caption)
                    .foregroundStyle(CyberpunkTheme.danger)
            }
            Menu {
                Button("在 Finder 中显示", systemImage: "folder") { manager.reveal(record) }
                if record.health == .ready, record.origin == .user {
                    Button("更新插件…", systemImage: "arrow.triangle.2.circlepath") { chooseUpdate(record) }
                    Divider()
                    Button("卸载", systemImage: "trash", role: .destructive) { pendingDelete = record }
                } else if record.origin == .user {
                    Button("卸载", systemImage: "trash", role: .destructive) { pendingDelete = record }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18))
            }
            .menuStyle(.borderlessButton)
            .help("插件操作")
        }
        .padding(.vertical, 4)
    }

    private func importPlugin(_ url: URL) {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        performAsync {
            defer { if isSecurityScoped { url.stopAccessingSecurityScopedResource() } }
            let candidate = try await manager.prepareImport(from: url)
            if candidate.replacing == nil {
                try manager.install(candidate)
            } else {
                pendingImport = candidate
            }
        }
    }

    private func iconSource(for record: PluginRecord) -> IconSource {
        guard record.health == .ready else { return .symbol(name: "exclamationmark.triangle.fill") }
        return LoadedPlugin.iconSource(record.manifest?.icon, in: record.directory)
            ?? .symbol(name: "puzzlepiece.extension")
    }

    private func chooseUpdate(_ record: PluginRecord) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.folder, .zip]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        performAsync {
            defer { if isSecurityScoped { url.stopAccessingSecurityScopedResource() } }
            pendingImport = try await manager.prepareImport(from: url, replacingID: record.manifest?.id)
        }
    }

    private func perform(_ operation: @escaping () throws -> Void) {
        do { try operation() } catch { errorMessage = error.localizedDescription }
    }

    private func performAsync(_ operation: @escaping () async throws -> Void) {
        isBusy = true
        Task { @MainActor in
            defer { isBusy = false }
            do { try await operation() } catch { errorMessage = error.localizedDescription }
        }
    }
}
