import Foundation

/// 一条计算历史：原算式、格式化结果、时间
struct CalcEntry: Codable {
    let expression: String
    let result: String
    var date: Date
}

/// 计算历史存储：history.json，最近 50 条，相同算式去重置顶。
/// 仿 ClipboardStore 的防抖写盘；在 MainActor 上下文使用。
final class CalculationHistory {
    private(set) var entries: [CalcEntry] = []

    private let file = AppStorageDir.subdirectory("Calculator").appendingPathComponent("history.json")
    private var saveTask: Task<Void, Never>?
    private let maxItems = 50

    init() { load() }

    /// 记录一次计算（用户回车复制时调用）。相同算式提升到顶。
    func record(expression: String, result: String) {
        let expr = expression.trimmingCharacters(in: .whitespaces)
        guard !expr.isEmpty else { return }
        if let index = entries.firstIndex(where: { $0.expression == expr }) {
            var entry = entries.remove(at: index)
            entry.date = .now
            entries.insert(entry, at: 0)
        } else {
            entries.insert(CalcEntry(expression: expr, result: result, date: .now), at: 0)
        }
        while entries.count > maxItems { entries.removeLast() }
        // 即时写盘：记录频率很低（仅回车复制时），且 pkill/SIGTERM 不走 applicationWillTerminate，
        // 防抖写盘会丢数据，故直接落盘保证不丢。
        flush()
    }

    /// 最近 limit 条，可排除某个算式（通常是当前正在输入的，避免与当前结果重复）
    func recent(limit: Int, excluding expression: String? = nil) -> [CalcEntry] {
        let excluded = expression?.trimmingCharacters(in: .whitespaces)
        return entries
            .filter { excluded == nil || $0.expression != excluded }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - 持久化

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: file),
              let decoded = try? decoder.decode([CalcEntry].self, from: data) else { return }
        entries = decoded
    }

    /// 防抖 2s 写盘
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = entries
        saveTask = Task { [file] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(snapshot) {
                try? data.write(to: file, options: .atomic)
            }
        }
    }

    func flush() {
        saveTask?.cancel()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) {
            try? data.write(to: file, options: .atomic)
        }
    }
}
