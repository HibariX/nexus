import AppKit
import Foundation
import Observation

enum PluginManagerError: LocalizedError, Equatable {
    case invalidPackage(String)
    case protectedPlugin
    case pluginNotFound
    case identifierMismatch(expected: String, actual: String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPackage(let message): return message
        case .protectedPlugin: return "内置插件不支持删除或替换"
        case .pluginNotFound: return "找不到目标插件"
        case .identifierMismatch(let expected, let actual):
            return "插件 ID 不匹配：需要 \(expected)，实际为 \(actual)"
        case .operationFailed(let message): return message
        }
    }
}

struct PluginImportCandidate: Identifiable {
    let id = UUID()
    let plugin: LoadedPlugin
    let stagingRoot: URL
    let replacing: PluginRecord?

    var manifest: PluginManifest { plugin.manifest }
}

@Observable
final class PluginManager {
    static let protectedPluginIDs: Set<String> = ["random-passwd"]

    private(set) var plugins: [PluginRecord] = []
    private(set) var lastMessage: String?
    var onPluginsChanged: (() -> Void)?

    let rootDirectory: URL
    private let bundledDirectory: URL?
    private let stateFile: URL
    private let importsDirectory: URL
    private var state: PersistedState

    private struct PersistedState: Codable {
        var disabledPluginIDs: Set<String> = []
        var didRemoveHySwitch = false
    }

    init(
        rootDirectory: URL = PluginLoader.rootDirectory,
        bundledDirectory: URL? = Bundle.main.resourceURL?.appendingPathComponent("Plugins"),
        stateFile: URL? = nil,
        performStartupMaintenance: Bool = true
    ) {
        self.rootDirectory = rootDirectory
        self.bundledDirectory = bundledDirectory
        self.stateFile = stateFile ?? rootDirectory.deletingLastPathComponent()
            .appendingPathComponent("plugin-state.json")
        importsDirectory = rootDirectory.appendingPathComponent(".imports", isDirectory: true)
        self.state = (try? Data(contentsOf: self.stateFile))
            .flatMap { try? JSONDecoder().decode(PersistedState.self, from: $0) }
            ?? PersistedState()

        try? FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: importsDirectory, withIntermediateDirectories: true)
        if performStartupMaintenance {
            synchronizeBundledPlugins()
            removeLegacyHySwitchIfNeeded()
        }
        refresh(notify: false)
    }

    var enabledPlugins: [LoadedPlugin] {
        plugins.compactMap { record in
            guard record.isEnabled, record.health == .ready else { return nil }
            return try? PluginLoader.validatedPlugin(from: record.directory)
        }
    }

    func runnablePlugin(id: String) -> LoadedPlugin? {
        guard let record = plugins.first(where: { $0.manifest?.id == id }),
              record.isEnabled, record.health == .ready else { return nil }
        return try? PluginLoader.validatedPlugin(from: record.directory)
    }

    func refresh() { refresh(notify: true) }

    func setEnabled(_ enabled: Bool, pluginID: String) {
        if enabled {
            state.disabledPluginIDs.remove(pluginID)
        } else {
            state.disabledPluginIDs.insert(pluginID)
        }
        saveState()
        refresh()
        lastMessage = enabled ? "插件已启用" : "插件已停用"
    }

    func prepareImport(from source: URL, replacingID: String? = nil) async throws -> PluginImportCandidate {
        let stagingRoot = importsDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
            let values = try source.resourceValues(forKeys: [.isDirectoryKey])
            let pluginDirectory: URL
            if values.isDirectory == true {
                pluginDirectory = stagingRoot.appendingPathComponent("plugin", isDirectory: true)
                try FileManager.default.copyItem(at: source, to: pluginDirectory)
            } else {
                guard source.pathExtension.lowercased() == "zip" else {
                    throw PluginManagerError.invalidPackage("请选择插件文件夹或 ZIP 文件")
                }
                try await extractZIP(source, to: stagingRoot)
                pluginDirectory = try locatePluginDirectory(in: stagingRoot)
            }
            try rejectSymbolicLinks(in: pluginDirectory)
            let plugin = try PluginLoader.validatedPlugin(from: pluginDirectory)
            if let replacingID, replacingID != plugin.id {
                throw PluginManagerError.identifierMismatch(expected: replacingID, actual: plugin.id)
            }
            let existing = plugins.first { $0.manifest?.id == plugin.id }
            if existing?.origin == .bundled {
                throw PluginManagerError.protectedPlugin
            }
            return PluginImportCandidate(plugin: plugin, stagingRoot: stagingRoot, replacing: existing)
        } catch {
            try? FileManager.default.removeItem(at: stagingRoot)
            throw error
        }
    }

    func install(_ candidate: PluginImportCandidate) throws {
        let fm = FileManager.default
        let existing = candidate.replacing
        let target = existing?.directory ?? rootDirectory.appendingPathComponent(candidate.manifest.id)
        let incoming = rootDirectory.appendingPathComponent(".incoming-\(UUID().uuidString)")
        let backup = rootDirectory.appendingPathComponent(".backup-\(UUID().uuidString)")
        do {
            try fm.copyItem(at: candidate.plugin.directory, to: incoming)
            _ = try PluginLoader.validatedPlugin(from: incoming)
            if fm.fileExists(atPath: target.path) { try fm.moveItem(at: target, to: backup) }
            do {
                try fm.moveItem(at: incoming, to: target)
            } catch {
                if fm.fileExists(atPath: backup.path) { try? fm.moveItem(at: backup, to: target) }
                throw error
            }
            if fm.fileExists(atPath: backup.path) { try fm.removeItem(at: backup) }
            state.disabledPluginIDs.remove(candidate.manifest.id)
            saveState()
            try? fm.removeItem(at: candidate.stagingRoot)
            refresh()
            lastMessage = existing == nil ? "插件已安装" : "插件已更新"
        } catch {
            try? fm.removeItem(at: incoming)
            try? fm.removeItem(at: candidate.stagingRoot)
            throw PluginManagerError.operationFailed("安装失败：\(error.localizedDescription)")
        }
    }

    func discard(_ candidate: PluginImportCandidate) {
        try? FileManager.default.removeItem(at: candidate.stagingRoot)
    }

    func uninstall(_ record: PluginRecord) throws {
        guard record.origin == .user else { throw PluginManagerError.protectedPlugin }
        guard FileManager.default.fileExists(atPath: record.directory.path) else {
            throw PluginManagerError.pluginNotFound
        }
        do {
            try FileManager.default.trashItem(at: record.directory, resultingItemURL: nil)
            if let id = record.manifest?.id { state.disabledPluginIDs.remove(id) }
            saveState()
            refresh()
            lastMessage = "插件已移到废纸篓"
        } catch {
            throw PluginManagerError.operationFailed("卸载失败：\(error.localizedDescription)")
        }
    }

    func reveal(_ record: PluginRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([record.directory])
    }

    private func refresh(notify: Bool) {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        plugins = entries.compactMap { directory in
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                return nil
            }
            do {
                let plugin = try PluginLoader.validatedPlugin(from: directory)
                let origin: PluginOrigin = Self.protectedPluginIDs.contains(plugin.id) ? .bundled : .user
                return PluginRecord(
                    id: directory.path,
                    manifest: plugin.manifest,
                    directory: directory,
                    origin: origin,
                    health: .ready,
                    isEnabled: !state.disabledPluginIDs.contains(plugin.id)
                )
            } catch {
                let fallbackID = directory.lastPathComponent
                let origin: PluginOrigin = Self.protectedPluginIDs.contains(fallbackID) ? .bundled : .user
                return PluginRecord(
                    id: directory.path,
                    manifest: nil,
                    directory: directory,
                    origin: origin,
                    health: .invalid(error.localizedDescription),
                    isEnabled: false
                )
            }
        }.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        if notify { onPluginsChanged?() }
    }

    private func synchronizeBundledPlugins() {
        guard let bundledDirectory else { return }
        let fm = FileManager.default
        for id in Self.protectedPluginIDs {
            let source = bundledDirectory.appendingPathComponent(id, isDirectory: true)
            guard fm.fileExists(atPath: source.path) else { continue }
            let target = rootDirectory.appendingPathComponent(id, isDirectory: true)
            let incoming = rootDirectory.appendingPathComponent(".bundled-\(UUID().uuidString)")
            let backup = rootDirectory.appendingPathComponent(".bundled-backup-\(UUID().uuidString)")
            do {
                try fm.copyItem(at: source, to: incoming)
                guard (try? PluginLoader.validatedPlugin(from: incoming)) != nil else {
                    try? fm.removeItem(at: incoming)
                    continue
                }
                if fm.fileExists(atPath: target.path) { try fm.moveItem(at: target, to: backup) }
                do {
                    try fm.moveItem(at: incoming, to: target)
                    try? fm.removeItem(at: backup)
                } catch {
                    if fm.fileExists(atPath: backup.path) { try? fm.moveItem(at: backup, to: target) }
                    throw error
                }
            } catch {
                try? fm.removeItem(at: incoming)
            }
        }
    }

    private func removeLegacyHySwitchIfNeeded() {
        guard !state.didRemoveHySwitch else { return }
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(
            at: rootDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        let matches = entries.filter { directory in
            (try? PluginLoader.validatedPlugin(from: directory).id) == "hyswitch"
                || directory.lastPathComponent == "hyswitch"
        }
        do {
            for directory in matches where fm.fileExists(atPath: directory.path) {
                try fm.trashItem(at: directory, resultingItemURL: nil)
            }
            state.didRemoveHySwitch = true
            state.disabledPluginIDs.remove("hyswitch")
            saveState()
        } catch {
            lastMessage = "HySwitch 自动卸载失败：\(error.localizedDescription)"
        }
    }

    private func extractZIP(_ archive: URL, to destination: URL) async throws {
        guard let listing = await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-Z1", archive.path], timeout: 10
        ), listing.exitCode == 0,
              let text = String(data: listing.stdout, encoding: .utf8) else {
            throw PluginManagerError.invalidPackage("无法读取 ZIP 文件")
        }
        let paths = text.split(whereSeparator: \Character.isNewline).map(String.init)
        guard !paths.isEmpty else { throw PluginManagerError.invalidPackage("ZIP 文件为空") }
        for path in paths {
            let components = path.replacingOccurrences(of: "\\", with: "/").split(separator: "/")
            guard !path.hasPrefix("/"), !components.contains(".."), !path.contains("\0") else {
                throw PluginManagerError.invalidPackage("ZIP 包含不安全路径")
            }
        }
        guard let result = await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-qq", archive.path, "-d", destination.path], timeout: 30
        ), result.exitCode == 0 else {
            throw PluginManagerError.invalidPackage("ZIP 解压失败")
        }
    }

    private func locatePluginDirectory(in extractedRoot: URL) throws -> URL {
        let fm = FileManager.default
        let enumerator = fm.enumerator(
            at: extractedRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        let manifests = (enumerator?.allObjects as? [URL] ?? []).filter { $0.lastPathComponent == "manifest.json" }
        guard manifests.count == 1, let manifest = manifests.first else {
            throw PluginManagerError.invalidPackage("ZIP 必须且只能包含一个 manifest.json")
        }
        let directory = manifest.deletingLastPathComponent().standardizedFileURL
        let rootPath = extractedRoot.standardizedFileURL.path
        let relativePath = directory.path.hasPrefix(rootPath + "/")
            ? String(directory.path.dropFirst(rootPath.count + 1))
            : directory.path
        let relative = relativePath.split(separator: "/")
        guard relative.count <= 1 else {
            throw PluginManagerError.invalidPackage("manifest.json 只能位于 ZIP 根目录或唯一的顶层文件夹中")
        }
        return directory
    }

    private func rejectSymbolicLinks(in directory: URL) throws {
        let keys: [URLResourceKey] = [.isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: keys, options: []
        ) else { return }
        for case let url as URL in enumerator {
            if try url.resourceValues(forKeys: Set(keys)).isSymbolicLink == true {
                throw PluginManagerError.invalidPackage("插件包不能包含符号链接")
            }
        }
    }

    private func saveState() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateFile, options: .atomic)
    }
}
