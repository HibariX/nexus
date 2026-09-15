import AppKit

struct AppEntry: Sendable {
    let name: String
    let path: String
    let match: SearchableText  // 名称的可搜索封装（含拼音/首字母），扫描时预计算
    /// bundle 里的原始（通常为英文）名称。别名变更后重建 match 时要用它，
    /// 否则用户在中文系统里就再也搜不到 Finder / Calculator 这类英文名。
    let nameAliases: [String]
}

/// 一个待扫描的应用目录。
nonisolated struct AppSearchDir: Sendable {
    let path: String
    /// 该目录混有系统进程级 bundle（loginwindow、NotificationCenter 等），
    /// 需要按「用户可见应用」规则过滤后再收录，不能整目录照单全收。
    let filtersInternalApps: Bool
    /// 是否再进一层子目录找 .app（如 /Applications/SQLiteStudio/SQLiteStudio.app）。
    let descends: Bool

    init(path: String, filtersInternalApps: Bool = false, descends: Bool = false) {
        self.path = path
        self.filtersInternalApps = filtersInternalApps
        self.descends = descends
    }
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

    nonisolated static let searchDirs: [AppSearchDir] = [
        AppSearchDir(path: "/Applications", descends: true),
        AppSearchDir(path: "/Applications/Utilities", descends: true),
        AppSearchDir(path: "/System/Applications", descends: true),
        AppSearchDir(path: "/System/Applications/Utilities", descends: true),
        AppSearchDir(path: NSHomeDirectory() + "/Applications", descends: true),
        // 访达与「钥匙串访问」「反馈助理」等系统小工具住在 CoreServices 下，但它们和一堆
        // 进程级 bundle（loginwindow、NotificationCenter、Dock…）混在同一层，必须过滤。
        AppSearchDir(path: "/System/Library/CoreServices", filtersInternalApps: true),
        AppSearchDir(path: "/System/Library/CoreServices/Applications",
                     filtersInternalApps: true, descends: true),
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
        var seenPaths = Set<String>()
        var seenBundleIDs = Set<String>()

        for dir in Self.searchDirs {
            for path in Self.appBundlePaths(in: dir, fileManager: fm) {
                guard seenPaths.insert(path).inserted else { continue }
                let info = Bundle(path: path)?.infoDictionary
                if dir.filtersInternalApps, !Self.isUserVisibleApp(infoDictionary: info) { continue }
                // 同一应用可能在多个目录各存一份（如 Feedback Assistant 同时出现在
                // /Applications/Utilities 与 CoreServices/Applications），按 Bundle ID 去重。
                // 读不到 Bundle ID 的条目照常保留，不去重也不丢。
                if let bundleID = info?["CFBundleIdentifier"] as? String, !bundleID.isEmpty,
                   !seenBundleIDs.insert(bundleID).inserted { continue }
                var name = fm.displayName(atPath: path)
                if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
                let nameAliases = Self.nameAliases(localizedName: name, infoDictionary: info)
                found.append(AppEntry(name: name, path: path,
                                      match: SearchableText(name, aliases: (aliases[path] ?? []) + nameAliases),
                                      nameAliases: nameAliases))
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

    /// 列出目录下的 .app；目录开了 `descends` 时再进一层子目录（跳过隐藏项）。
    nonisolated private static func appBundlePaths(in dir: AppSearchDir, fileManager fm: FileManager) -> [String] {
        let items = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
        var paths: [String] = []
        var subdirectories: [String] = []

        for item in items where !item.hasPrefix(".") {
            let path = dir.path + "/" + item
            if item.hasSuffix(".app") {
                paths.append(path)
                continue
            }
            guard dir.descends else { continue }
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                subdirectories.append(path)
            }
        }

        for subdirectory in subdirectories {
            let nested = (try? fm.contentsOfDirectory(atPath: subdirectory)) ?? []
            for item in nested.sorted() where item.hasSuffix(".app") && !item.hasPrefix(".") {
                paths.append(subdirectory + "/" + item)
            }
        }
        return paths
    }

    /// 是否是「用户可见应用」：CoreServices 里的进程级 bundle（loginwindow、NotificationCenter、
    /// Dock…）一律带 LSUIElement 或 LSBackgroundOnly，个别（liquiddetectiond）连 Info.plist 都没有。
    nonisolated static func isUserVisibleApp(infoDictionary: [String: Any]?) -> Bool {
        guard let info = infoDictionary,
              let bundleID = info["CFBundleIdentifier"] as? String, !bundleID.isEmpty else { return false }
        return !isFlagOn(info["LSUIElement"]) && !isFlagOn(info["LSBackgroundOnly"])
    }

    /// 本地化名之外再补上 bundle 里的原始名作为别名：中文系统下应用显示为「访达」「计算器」，
    /// 但用户可能按英文名（Finder、Calculator）搜索，两个检索入口都要保留。
    nonisolated static func nameAliases(localizedName: String, infoDictionary: [String: Any]?) -> [String] {
        guard let info = infoDictionary else { return [] }
        var aliases: [String] = []
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            guard var raw = info[key] as? String, !raw.isEmpty else { continue }
            if raw.hasSuffix(".app") { raw = String(raw.dropLast(4)) }
            guard raw != localizedName, !aliases.contains(raw) else { continue }
            aliases.append(raw)
        }
        return aliases
    }

    /// plist 里同一个标志有 <true/>、<integer>1</integer>、<string>YES</string> 三种写法，统一归一化。
    nonisolated private static func isFlagOn(_ value: Any?) -> Bool {
        switch value {
        case let flag as Bool: return flag
        case let number as NSNumber: return number.boolValue
        case let text as String: return ["1", "true", "yes"].contains(text.lowercased())
        default: return false
        }
    }

    /// 别名变更后即时生效：纯内存重建各 entry 的 match，不重扫目录、不动 lastScan
    /// （绕过 scanIfStale 的 300s 缓存，也不干扰 frecency/staleness 语义）。
    func refreshAliases() {
        scanTask?.cancel()
        scanTask = nil
        scanGeneration += 1
        entries = entries.map { entry in
            let aliases = (aliasStore?.aliases(for: entry.path) ?? []) + entry.nameAliases
            return AppEntry(name: entry.name, path: entry.path,
                            match: SearchableText(entry.name, aliases: aliases),
                            nameAliases: entry.nameAliases)
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
