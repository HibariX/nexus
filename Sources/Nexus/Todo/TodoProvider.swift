import Foundation

/// 面板命令入口：`todo` 唤起浮窗并列出未完成项；`todo <内容>` 直接添加
final class TodoProvider: CommandProvider {
    let sectionTitle = "今日待办"
    let sectionRank = 22

    private let store: TodoStore

    /// 触发关键词
    private static let keywords = ["todo", "todos", "待办", "daiban"]

    init(store: TodoStore) {
        self.store = store
    }

    func results(for query: Query) async -> [ResultItem] {
        let text = query.trimmed
        let lower = text.lowercased()

        for keyword in Self.keywords where lower == keyword || lower.hasPrefix(keyword + " ") {
            // 没授权就谈不上列表和添加，一律先引导（回车开浮窗，授权入口在那里）
            guard store.authorization == .granted else { return [authGuide()] }
            let arg = String(text.dropFirst(keyword.count)).trimmingCharacters(in: .whitespaces)
            return arg.isEmpty ? openAndList() : [addItem(arg)]
        }
        return []
    }

    private func authGuide() -> ResultItem {
        ResultItem(
            id: "todo:auth",
            title: "今日待办需要访问「提醒事项」",
            subtitle: store.authorization == .denied
                ? "已被拒绝，需在系统设置中重新允许" : "待办与系统提醒事项同步",
            icon: .symbol(name: "lock"),
            score: 3000,
            accessoryHint: "⏎ 打开浮窗",
            action: .showTodoPanel
        )
    }

    private func addItem(_ title: String) -> ResultItem {
        ResultItem(
            id: "todo:add",
            title: "添加待办：\(title)",
            subtitle: "回车加入今日待办清单",
            icon: .symbol(name: "plus.circle.fill"),
            score: 3000,
            accessoryHint: "⏎ 添加",
            action: .addTodo(title)
        )
    }

    private func openAndList() -> [ResultItem] {
        var results: [ResultItem] = [
            ResultItem(
                id: "todo:open",
                title: "打开今日待办",
                subtitle: "剩余 \(store.remainingCount) 项",
                icon: .symbol(name: "checklist"),
                score: 3000,
                accessoryHint: "⏎ 打开浮窗",
                action: .showTodoPanel
            )
        ]
        let listLimit = 8
        let pending = store.items.filter { !$0.isDone }
        for (index, item) in pending.prefix(listLimit).enumerated() {
            results.append(ResultItem(
                id: "todo:item:\(item.id)",
                title: item.title,
                subtitle: nil,
                icon: .symbol(name: "circle"),
                score: 2000 - Double(index),
                accessoryHint: "⏎ 标记完成",
                action: .toggleTodo(id: item.id)
            ))
        }
        if pending.count > listLimit {
            results.append(ResultItem(
                id: "todo:more",
                title: "还有 \(pending.count - listLimit) 项…",
                subtitle: "打开浮窗查看全部",
                icon: .symbol(name: "ellipsis.circle"),
                score: 1,
                accessoryHint: "⏎ 打开浮窗",
                action: .showTodoPanel
            ))
        }
        return results
    }
}
