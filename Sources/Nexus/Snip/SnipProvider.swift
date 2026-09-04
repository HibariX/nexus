import Foundation

/// 面板内的贴图命令入口
final class SnipProvider: CommandProvider {
    let sectionTitle = "截图贴图"
    let sectionRank = 25

    private let pinController: PinWindowController

    init(pinController: PinWindowController) {
        self.pinController = pinController
    }

    func results(for query: Query) async -> [ResultItem] {
        let text = query.trimmed
        guard !text.isEmpty else { return [] }

        var items: [ResultItem] = []

        let pinAliases = ["pin clipboard", "贴图", "贴剪贴板", "贴剪贴板图片", "tietu"]
        if let score = bestScore(query: text, candidates: pinAliases) {
            items.append(ResultItem(
                id: "snip:pin-clipboard",
                title: "剪贴板贴图",
                subtitle: "把剪贴板中的图片或文本作为置顶浮窗显示",
                icon: .symbol(name: "pin.fill"),
                score: score,
                accessoryHint: "命令",
                action: .pinClipboardContent
            ))
        }

        return items
    }

    private func bestScore(query: String, candidates: [String]) -> Double? {
        candidates.compactMap { FuzzyMatcher.score(query: query, target: $0) }.max()
    }
}
