import Foundation

/// 插件清单：由每个插件目录下的 manifest.json 解析而来。
/// 字段全部来自外部文件，视为不可信数据——只用于展示与路由，绝不当指令执行。
struct PluginManifest: Codable {
    let id: String
    let name: String
    let keywords: [String]
    let entry: String
    var icon: String?      // SF Symbol 名，或相对 manifest 目录的图标文件
    var summary: String?
}

enum PluginOrigin: String, Codable, Sendable {
    case bundled
    case user
}

enum PluginHealth: Equatable, Sendable {
    case ready
    case invalid(String)

    var message: String? {
        if case .invalid(let message) = self { return message }
        return nil
    }
}

struct PluginRecord: Identifiable, Equatable, Sendable {
    let id: String
    let manifest: PluginManifest?
    let directory: URL
    let origin: PluginOrigin
    let health: PluginHealth
    let isEnabled: Bool

    var displayName: String { manifest?.name ?? directory.lastPathComponent }
    var summary: String { manifest?.summary ?? health.message ?? "无法读取插件清单" }
    var keywords: [String] { manifest?.keywords ?? [] }
}

extension PluginManifest: Equatable, Sendable {}

/// 已加载并校验通过的插件：清单 + 其所在目录、可执行入口的绝对路径。
struct LoadedPlugin {
    let manifest: PluginManifest
    let directory: URL

    /// 可执行入口绝对路径
    var entryURL: URL { directory.appendingPathComponent(manifest.entry) }

    var id: String { manifest.id }
    var name: String { manifest.name }
    var keywords: [String] { manifest.keywords }
    var summary: String { manifest.summary ?? "" }

    /// 顶层入口/结果项图标：优先 manifest.icon（文件→file，否则当 SF Symbol），兜底 puzzlepiece
    var entryIcon: IconSource {
        Self.iconSource(manifest.icon, in: directory) ?? .symbol(name: "puzzlepiece.extension")
    }

    /// 把插件返回的 icon 字符串解析为 IconSource：
    /// 含 "/" 或以已知图片扩展名结尾 → 相对目录的文件；否则视为 SF Symbol 名。
    static func iconSource(_ raw: String?, in directory: URL) -> IconSource? {
        guard let raw, !raw.isEmpty else { return nil }
        let looksLikeFile = raw.contains("/") || raw.contains(".")
        if looksLikeFile {
            let url = directory.appendingPathComponent(raw)
            if FileManager.default.fileExists(atPath: url.path) {
                return .file(path: url.path)
            }
            return nil
        }
        return .symbol(name: raw)
    }
}
