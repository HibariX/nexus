import Foundation

/// 应用自定义别名的持久化存储：bundle path -> 别名列表。
/// key 用 bundle path（与 frecency 的 launchCounts 一致，比 app 名稳定）。
/// 别名会经 SearchableText 自动派生拼音全拼/首字母参与匹配。
final class AliasStore {
    private(set) var map: [String: [String]] = [:]  // path -> aliases
    private let file: URL

    /// file 可注入，便于单测用临时目录，不污染真实 Application Support。
    init(file: URL = AppStorageDir.root.appendingPathComponent("appAliases.json")) {
        self.file = file
        load()
    }

    func aliases(for path: String) -> [String] { map[path] ?? [] }

    /// 追加别名（trim + 大小写去重）；空串忽略。
    func add(_ alias: String, for path: String) {
        let a = alias.trimmingCharacters(in: .whitespaces)
        guard !a.isEmpty else { return }
        var list = map[path] ?? []
        guard !list.contains(where: { $0.caseInsensitiveCompare(a) == .orderedSame }) else { return }
        list.append(a)
        map[path] = list
        save()
    }

    /// 移除指定别名；移空后删除该 key。
    func remove(_ alias: String, for path: String) {
        guard var list = map[path] else { return }
        list.removeAll { $0.caseInsensitiveCompare(alias) == .orderedSame }
        map[path] = list.isEmpty ? nil : list
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else { return }
        map = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(map) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
