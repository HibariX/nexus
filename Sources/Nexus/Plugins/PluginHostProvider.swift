import Foundation

/// 外部插件宿主：把已加载的插件接入搜索管线。支持 `@` 前缀浏览，也支持完整关键词直接触发。
/// - root 下 `@`（空）或 `@<前缀>` → 列出（匹配的）插件入口，回车 **压栈进入插件页**（不起子进程）。
/// - root 下 `<完整关键词> [参数]` → 直接列出对应插件入口，并把参数带入插件页。
/// - 插件页的结果由 `pageResults(pluginId:arg:)` 提供（SearchCoordinator 在 .plugin 页调用）。
final class PluginHostProvider: CommandProvider {
    let sectionTitle = "插件"
    let sectionRank = 30

    private let plugins: [LoadedPlugin]
    private let runner: ExternalPluginRunner

    init(plugins: [LoadedPlugin], runner: ExternalPluginRunner) {
        self.plugins = plugins
        self.runner = runner
    }

    func prefersExclusiveResults(for query: Query) -> Bool {
        query.trimmed.hasPrefix("@")
    }

    /// `@` / `@<前缀>` 分类浏览：罗列（匹配的）插件入口，回车压栈进入插件页。零子进程。
    func atEntries(for query: Query) async -> [ResultItem] {
        let lower = query.trimmed.dropFirst()   // 去掉 @
            .trimmingCharacters(in: .whitespaces).lowercased()
        var entries: [ResultItem] = []
        for plugin in plugins {
            let match = lower.isEmpty || plugin.keywords.contains { $0.lowercased().hasPrefix(lower) }
                || plugin.name.lowercased().hasPrefix(lower)
            guard match else { continue }
            entries.append(ResultItem(
                id: "plugin:entry:\(plugin.id)",
                title: plugin.name,
                subtitle: plugin.summary.isEmpty ? nil : plugin.summary,
                icon: plugin.entryIcon,
                score: 200 - Double(entries.count),
                accessoryHint: "⏎ 进入",
                action: .pushPage(pluginId: plugin.id, path: "", title: plugin.name)
            ))
        }
        return entries
    }

    /// root 页：`@` 触发，只列插件入口（回车压栈进入插件页）。零子进程。
    func results(for query: Query) async -> [ResultItem] {
        let text = query.trimmed
        guard text.hasPrefix("@") else { return directEntries(for: text) }
        let lower = String(text.dropFirst()).trimmingCharacters(in: .whitespaces).lowercased()

        var entries: [ResultItem] = []
        for plugin in plugins {
            let match = lower.isEmpty || plugin.keywords.contains { $0.lowercased().hasPrefix(lower) }
                || plugin.name.lowercased().hasPrefix(lower)
            guard match else { continue }
            entries.append(ResultItem(
                id: "plugin:entry:\(plugin.id)",
                title: plugin.name,
                subtitle: plugin.summary.isEmpty ? nil : plugin.summary,
                icon: plugin.entryIcon,
                score: 200 - Double(entries.count),
                accessoryHint: "⏎ 进入",
                action: .pushPage(pluginId: plugin.id, path: "", title: plugin.name)
            ))
        }
        return entries
    }

    private func directEntries(for text: String) -> [ResultItem] {
        guard !text.isEmpty else { return [] }
        let lower = text.lowercased()
        var entries: [ResultItem] = []

        for plugin in plugins {
            let keyword = plugin.keywords
                .filter {
                    let candidate = $0.lowercased()
                    return lower == candidate || lower.hasPrefix(candidate + " ")
                }
                .max { $0.count < $1.count }
            guard let keyword else { continue }

            let argumentStart = text.index(text.startIndex, offsetBy: keyword.count)
            let arguments = String(text[argumentStart...]).trimmingCharacters(in: .whitespaces)
            let subtitle = arguments.isEmpty
                ? plugin.summary
                : [plugin.summary, "参数：\(arguments)"].filter { !$0.isEmpty }.joined(separator: " · ")
            entries.append(ResultItem(
                id: "plugin:direct:\(plugin.id)",
                title: plugin.name,
                subtitle: subtitle.isEmpty ? nil : subtitle,
                icon: plugin.entryIcon,
                score: 300 - Double(entries.count),
                accessoryHint: "⏎ 进入",
                action: .pushPage(pluginId: plugin.id, path: arguments, title: plugin.name)
            ))
        }
        return entries
    }

    /// 插件页：跑该插件子进程，把返回 items 映射成结果行。
    func pageResults(pluginId: String, arg: String) async -> [ResultItem] {
        guard let plugin = plugins.first(where: { $0.id == pluginId }) else { return [] }
        let items = await runner.query(plugin, arg: arg)
        return mapItems(items, plugin: plugin)
    }

    private func mapItems(_ items: [PluginItem], plugin: LoadedPlugin) -> [ResultItem] {
        items.enumerated().map { index, item in
            let action: ResultAction
            if let sub = item.query {
                // 导航型：回车压栈进入子页（path = 该值）
                action = .pushPage(pluginId: plugin.id, path: sub, title: item.title)
            } else if let actionId = item.action, !actionId.isEmpty {
                action = .pluginAction(pluginId: plugin.id, actionId: actionId, payload: item.payload ?? "")
            } else {
                action = .replaceQuery("")  // 纯展示项：无操作
            }
            return ResultItem(
                id: "plugin:\(plugin.id):\(index):\(item.title)",
                title: item.title,
                subtitle: item.subtitle,
                icon: LoadedPlugin.iconSource(item.icon, in: plugin.directory) ?? plugin.entryIcon,
                score: 500 - Double(index),
                accessoryHint: item.hint,
                action: action
            )
        }
    }
}
