import Foundation

/// 扫描插件根目录、加载并校验每个插件的 manifest.json。
/// 校验失败（清单缺字段、entry 不存在或不可执行）的插件被跳过，不影响其它插件。
enum PluginLoader {
    /// 插件根目录：~/Library/Application Support/Nexus/Plugins/
    static var rootDirectory: URL { AppStorageDir.subdirectory("Plugins") }

    static func loadAll() -> [LoadedPlugin] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: rootDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        var plugins: [LoadedPlugin] = []
        for dir in entries {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            if let plugin = load(from: dir) {
                plugins.append(plugin)
            }
        }
        return plugins
    }

    static func load(from directory: URL) -> LoadedPlugin? {
        try? validatedPlugin(from: directory)
    }

    static func validatedPlugin(from directory: URL) throws -> LoadedPlugin {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw PluginManagerError.invalidPackage("缺少 manifest.json")
        }
        let data: Data
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            throw PluginManagerError.invalidPackage("无法读取 manifest.json")
        }
        let manifest: PluginManifest
        do {
            manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        } catch {
            throw PluginManagerError.invalidPackage("manifest.json 格式无效")
        }
        guard !manifest.id.isEmpty, !manifest.name.isEmpty,
              !manifest.keywords.isEmpty, !manifest.entry.isEmpty else {
            throw PluginManagerError.invalidPackage("清单中的 id、name、keywords 和 entry 不能为空")
        }
        let allowedID = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard manifest.id.unicodeScalars.allSatisfy(allowedID.contains) else {
            throw PluginManagerError.invalidPackage("插件 ID 只能包含字母、数字、点、下划线和连字符")
        }

        let rootPath = directory.standardizedFileURL.path
        let entryURL = directory.appendingPathComponent(manifest.entry).standardizedFileURL
        guard !manifest.entry.hasPrefix("/"),
              entryURL.path.hasPrefix(rootPath + "/") else {
            throw PluginManagerError.invalidPackage("入口文件必须位于插件目录内")
        }

        let plugin = LoadedPlugin(manifest: manifest, directory: directory)
        // entry 必须存在且可执行
        let entryPath = plugin.entryURL.path
        let fm = FileManager.default
        guard fm.fileExists(atPath: entryPath) else {
            throw PluginManagerError.invalidPackage("入口文件不存在：\(manifest.entry)")
        }
        guard fm.isExecutableFile(atPath: entryPath) else {
            throw PluginManagerError.invalidPackage("入口文件不可执行：\(manifest.entry)")
        }

        return plugin
    }
}
