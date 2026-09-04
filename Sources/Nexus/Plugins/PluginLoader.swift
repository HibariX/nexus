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
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data),
              !manifest.id.isEmpty, !manifest.keywords.isEmpty, !manifest.entry.isEmpty
        else { return nil }

        let plugin = LoadedPlugin(manifest: manifest, directory: directory)
        // entry 必须存在且可执行
        let entryPath = plugin.entryURL.path
        let fm = FileManager.default
        guard fm.fileExists(atPath: entryPath), fm.isExecutableFile(atPath: entryPath) else { return nil }

        return plugin
    }
}
