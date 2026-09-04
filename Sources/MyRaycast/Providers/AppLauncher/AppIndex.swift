import AppKit

struct AppEntry: Sendable {
    let name: String
    let path: String
    let match: SearchableText  // 名称的可搜索封装（含拼音/首字母），扫描时预计算
}

/// 本机应用索引 + frecency（启动次数/最近启动时间加权）
final class AppIndex {
    private(set) var entries: [AppEntry] = []
    private var lastScan: Date = .distantPast
    private var scanTask: Task<Void, Never>?
    private var scanGeneration = 0
    private var statsSaveTask: Task<Void, Never>?
    private var statsSaveGeneration = 0

    private var launchStats: [String: LaunchStat] = [:]  // path -> stat
    private let statsFile = AppStorageDir.root.appendingPathComponent("launchCounts.json")

    /// 别名来源；scan 时把别名喂进 SearchableText，变更后经 refreshAliases 即时重建。
    private let aliasStore: AliasStore?

    struct LaunchStat: Codable {
        var count: Int
        var lastLaunch: Date
    }

    nonisolated private static let searchDirs = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications",
    ]

    init(aliasStore: AliasStore? = nil) {
        self.aliasStore = aliasStore
        loadStats()
        scan()
    }

    func scanIfStale() {
        guard Date().timeIntervalSince(lastScan) > 300, scanTask == nil else { return }
        lastScan = .now
        scanGeneration += 1
        let generation = scanGeneration
        let aliases = aliasStore?.map ?? [:]
        scanTask = Task {
            let found = await Task.detached(priority: .utility) {
                Self.scanEntries(aliases: aliases)
            }.value
            guard !Task.isCancelled, generation == scanGeneration else { return }
            entries = found
            scanTask = nil
        }
    }

    func scan() {
        scanTask?.cancel()
        scanTask = nil
        scanGeneration += 1
        lastScan = Date()
        entries = Self.scanEntries(aliases: aliasStore?.map ?? [:])
    }

    nonisolated private static func scanEntries(aliases: [String: [String]]) -> [AppEntry] {
        let fm = FileManager.default
        var found: [AppEntry] = []
        var seen = Set<String>()

        for dir in Self.searchDirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.hasSuffix(".app") {
                let path = dir + "/" + item
                guard seen.insert(path).inserted else { continue }
                var name = fm.displayName(atPath: path)
                if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
                found.append(AppEntry(name: name, path: path,
                                      match: SearchableText(name, aliases: aliases[path] ?? [])))
            }
        }
        return found
    }

    /// 别名变更后即时生效：纯内存重建各 entry 的 match，不重扫目录、不动 lastScan
    /// （绕过 scanIfStale 的 300s 缓存，也不干扰 frecency/staleness 语义）。
    func refreshAliases() {
        scanTask?.cancel()
        scanTask = nil
        scanGeneration += 1
        entries = entries.map { entry in
            let aliases = aliasStore?.aliases(for: entry.path) ?? []
            return AppEntry(name: entry.name, path: entry.path,
                            match: SearchableText(entry.name, aliases: aliases))
        }
    }

    /// 卸载后即时从内存索引剔除该 App（废纸篓搬走后重扫不会找回）
    func remove(path: String) {
        entries.removeAll { $0.path == path }
    }

    // MARK: - Frecency

    func frecencyBoost(for path: String) -> Double {
        guard let stat = launchStats[path] else { return 0 }
        let days = max(Date().timeIntervalSince(stat.lastLaunch) / 86400, 0)
        let recency = 1.0 / (1.0 + days / 7.0)  // 一周内启动权重高
        return log(Double(stat.count) + 1) * 2 * recency
    }

    func recordLaunch(path: String) {
        var stat = launchStats[path] ?? LaunchStat(count: 0, lastLaunch: .now)
        stat.count += 1
        stat.lastLaunch = .now
        launchStats[path] = stat
        scheduleStatsSave()
    }

    private func loadStats() {
        guard let data = try? Data(contentsOf: statsFile),
              let stats = try? JSONDecoder().decode([String: LaunchStat].self, from: data) else { return }
        launchStats = stats
    }

    private func scheduleStatsSave() {
        statsSaveTask?.cancel()
        statsSaveGeneration += 1
        let generation = statsSaveGeneration
        let snapshot = launchStats
        let file = statsFile
        statsSaveTask = Task {
            let data = await Task.detached(priority: .utility) {
                try? JSONEncoder().encode(snapshot)
            }.value
            guard !Task.isCancelled, generation == statsSaveGeneration, let data else { return }
            await Task.detached(priority: .utility) {
                try? data.write(to: file, options: .atomic)
            }.value
        }
    }

    func flush() {
        statsSaveTask?.cancel()
        guard let data = try? JSONEncoder().encode(launchStats) else { return }
        try? data.write(to: statsFile, options: .atomic)
    }
}
