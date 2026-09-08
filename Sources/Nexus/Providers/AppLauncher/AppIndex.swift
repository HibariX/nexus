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
    /// path -> .app bundle 的 creationDate（近似安装时间），scan 时随 entries 一并读取缓存。
    private var installedDates: [String: Date] = [:]
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
            let result = await Task.detached(priority: .utility) {
                Self.scanEntries(aliases: aliases)
            }.value
            guard !Task.isCancelled, generation == scanGeneration else { return }
            entries = result.entries
            installedDates = result.installDates
            scanTask = nil
        }
    }

    func scan() {
        scanTask?.cancel()
        scanTask = nil
        scanGeneration += 1
        lastScan = Date()
        let result = Self.scanEntries(aliases: aliasStore?.map ?? [:])
        entries = result.entries
        installedDates = result.installDates
    }

    nonisolated private static func scanEntries(aliases: [String: [String]]) -> (entries: [AppEntry], installDates: [String: Date]) {
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

        // 同一遍读 .app 的 creationDate，作为「安装时间」的近似（供应用建议评分）
        var installDates: [String: Date] = [:]
        for entry in found {
            if let date = try? fm.attributesOfItem(atPath: entry.path)[.creationDate] as? Date {
                installDates[entry.path] = date
            }
        }
        return (found, installDates)
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

    // MARK: - 应用建议

    /// 建议评分：frecency（启动频次 + 最近启动）叠加安装新鲜度。纯函数可单测。
    /// 最近 60 天内安装/获取的应用加分更高，让「刚装的新应用」也能排进建议。
    nonisolated static func suggestionScore(frecency: Double, installDate: Date?,
                                            now: Date = .now) -> Double {
        var score = frecency
        if let installDate {
            let days = max(now.timeIntervalSince(installDate) / 86400, 0)
            score += 2.0 / (1.0 + days / 60.0)
        }
        return score
    }

    /// 取建议集合：综合「启动频次 + 最近启动 + 最近安装」排序后的前 limit 个应用。
    func suggestions(limit: Int) -> [AppEntry] {
        entries
            .map { ($0, Self.suggestionScore(frecency: frecencyBoost(for: $0.path),
                                             installDate: installedDates[$0.path])) }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
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
