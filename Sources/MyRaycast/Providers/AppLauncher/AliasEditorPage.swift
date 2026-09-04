import Foundation

/// 别名编辑内置页：在 root 选中某 App 后按 Tab 进入。
/// 搜索框输入 = 正在录入的别名文本；页内展示「设为别名」与既有别名的「清除」项。
final class AliasEditorPage: BuiltinPage {
    let id = "alias"

    private let aliasStore: AliasStore
    /// 当前编辑目标，push 前由 configure 重设，避免残留上次 App。
    private var target: (path: String, name: String)?

    init(aliasStore: AliasStore) {
        self.aliasStore = aliasStore
    }

    func configure(path: String, name: String) {
        target = (path, name)
    }

    func results(for query: Query) async -> [ResultItem] {
        guard let target else { return [] }
        var items: [ResultItem] = []
        let text = query.trimmed

        if !text.isEmpty {
            items.append(ResultItem(
                id: "alias:set:\(text)",
                title: "设为别名「\(text)」",
                subtitle: target.name,
                icon: .symbol(name: "plus.circle"),
                score: 1000,
                accessoryHint: "⏎ 保存",
                action: .saveAlias(path: target.path, alias: text)
            ))
        }

        for alias in aliasStore.aliases(for: target.path) {
            items.append(ResultItem(
                id: "alias:del:\(alias)",
                title: alias,
                subtitle: "现有别名",
                icon: .symbol(name: "trash"),
                score: 500,
                accessoryHint: "⏎ 清除",
                action: .removeAlias(path: target.path, alias: alias)
            ))
        }

        if items.isEmpty {
            items.append(ResultItem(
                id: "alias:empty",
                title: "输入要设置的别名",
                subtitle: "支持中文，将自动匹配拼音/首字母",
                icon: .symbol(name: "textformat"),
                score: 0,
                accessoryHint: nil,
                action: .replaceQuery("")
            ))
        }

        return items
    }
}
