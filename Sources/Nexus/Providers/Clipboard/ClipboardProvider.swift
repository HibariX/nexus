import Foundation

final class ClipboardProvider: CommandProvider {
    let sectionTitle = "剪贴板历史"
    let sectionRank = 30

    private let store: ClipboardStore

    /// 触发关键词：命中后展示/过滤剪贴板历史
    nonisolated private static let keywords = ["clip", "clipboard", "剪贴板", "粘贴板"]

    init(store: ClipboardStore) {
        self.store = store
    }

    func prefersExclusiveResults(for query: Query) -> Bool {
        Self.keywordFilter(in: query.trimmed.lowercased()) != nil
    }

    func results(for query: Query) async -> [ResultItem] {
        let text = query.trimmed.lowercased()

        // 关键词模式：`clip` 或 `clip 搜索词`
        if let filter = Self.keywordFilter(in: text) {
            return items(matching: filter, limit: 15, baseScore: 2000)
        }

        // 普通搜索兜底：≥2 字符时对历史做全文过滤，低分排在应用之后
        guard text.count >= 2 else { return [] }
        return items(matching: text, limit: 5, baseScore: 1)
    }

    private func items(matching filter: String, limit: Int, baseScore: Double) -> [ResultItem] {
        var results: [ResultItem] = []
        for (index, item) in store.items.enumerated() {
            guard results.count < limit else { break }
            let content = store.searchPreview(for: item)
            if !filter.isEmpty {
                switch item.kind {
                case .text:
                    guard content.contains(filter) else { continue }
                case .image:
                    continue  // 图片无文本可匹配，仅在无过滤词时展示
                }
            }
            results.append(makeItem(item, score: baseScore - Double(index) * 0.001))
        }
        return results
    }

    private func makeItem(_ item: ClipItem, score: Double) -> ResultItem {
        let dateText = item.date.formatted(.relative(presentation: .named))
        let source = item.sourceApp.map { "\($0) · " } ?? ""
        switch item.kind {
        case .text:
            return ResultItem(
                id: "clip:\(item.id)",
                title: Self.resultTitle(for: item.text ?? ""),
                subtitle: source + dateText,
                icon: .symbol(name: "doc.on.clipboard"),
                score: score,
                accessoryHint: "⏎ 粘贴",
                action: .pasteClip(id: item.id)
            )
        case .image:
            return ResultItem(
                id: "clip:\(item.id)",
                title: "图片",
                subtitle: source + dateText,
                icon: .clipboardImage(id: item.id),
                score: score,
                accessoryHint: "⏎ 粘贴",
                action: .pasteClip(id: item.id)
            )
        }
    }

    nonisolated static func keywordFilter(in normalizedQuery: String) -> String? {
        for keyword in keywords where normalizedQuery == keyword || normalizedQuery.hasPrefix(keyword + " ") {
            return normalizedQuery.dropFirst(keyword.count).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    nonisolated static func resultTitle(for text: String) -> String {
        let preview = String(text.prefix(512))
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return String(preview.prefix(80))
    }
}
