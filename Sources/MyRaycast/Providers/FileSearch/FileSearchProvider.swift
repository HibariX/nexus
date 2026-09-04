import Foundation

final class FileSearchProvider: CommandProvider {
    let sectionTitle = "文件"
    let sectionRank = 40

    private let search = MetadataSearch()

    func results(for query: Query) async -> [ResultItem] {
        let text = query.trimmed
        // 算式不查文件；过短的 query 噪音太大
        guard text.count >= 3, !ExpressionParser.looksLikeExpression(text) else { return [] }

        // 二级防抖：等 250ms 再真正打 Spotlight，输入过程中被取消
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return [] }

        let hits = await search.search(text, limit: 10)
        guard !Task.isCancelled else { return [] }

        return hits.enumerated().map { index, hit in
            ResultItem(
                id: "file:\(hit.path)",
                title: hit.name,
                subtitle: abbreviatePath(hit.path),
                icon: .file(path: hit.path),
                score: 100 - Double(index),
                accessoryHint: "⏎ 打开 · ⌘⏎ 在 Finder 显示",
                action: .openFile(path: hit.path)
            )
        }
    }

    private func abbreviatePath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
