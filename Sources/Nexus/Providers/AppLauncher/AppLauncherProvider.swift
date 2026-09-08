import Foundation

final class AppLauncherProvider: CommandProvider {
    let sectionTitle = "应用"
    let sectionRank = 10

    private let index: AppIndex

    init(index: AppIndex) {
        self.index = index
    }

    func results(for query: Query) async -> [ResultItem] {
        let text = query.trimmed
        index.scanIfStale()

        if text.isEmpty {
            // 空 query（工作台）：展示全部应用。frecency 常用置顶，其余按名称排序。
            let ranked = index.entries.map { ($0, index.frecencyBoost(for: $0.path)) }
            let hot = ranked.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
            let cold = ranked.filter { $0.1 == 0 }
                .sorted { $0.0.name.localizedStandardCompare($1.0.name) == .orderedAscending }
            return (hot + cold).map { entry, boost in makeItem(entry, score: boost) }
        }

        return index.entries.compactMap { entry in
            guard let base = entry.match.score(for: text) else { return nil }
            return makeItem(entry, score: base + index.frecencyBoost(for: entry.path))
        }
        .sorted { $0.score > $1.score }
        .prefix(8)
        .map { $0 }
    }

    /// 工作台空态顶部的「应用建议」：综合启动频次/最近启动/最近安装，取前 limit 个。
    func suggestions(limit: Int) -> [ResultItem] {
        index.scanIfStale()
        return index.suggestions(limit: limit)
            .map { makeItem($0, score: index.frecencyBoost(for: $0.path)) }
    }

    private func makeItem(_ entry: AppEntry, score: Double) -> ResultItem {
        ResultItem(
            id: "app:\(entry.path)",
            title: entry.name,
            subtitle: nil,
            icon: .appBundle(path: entry.path),
            score: score,
            accessoryHint: "应用",
            action: .launchApp(path: entry.path)
        )
    }
}
