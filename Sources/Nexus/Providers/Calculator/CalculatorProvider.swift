import Foundation

final class CalculatorProvider: CommandProvider {
    let sectionTitle = "计算"
    let sectionRank = 0  // 永远排最前

    private let history: CalculationHistory

    init(history: CalculationHistory) {
        self.history = history
    }

    func prefersExclusiveResults(for query: Query) -> Bool {
        ExpressionParser.looksLikeExpression(query.trimmed)
    }

    func results(for query: Query) async -> [ResultItem] {
        let text = query.trimmed
        guard !text.isEmpty else { return [] }

        var items: [ResultItem] = []

        // 单位换算优先
        if let conversion = UnitConversion.convert(text) {
            let display = conversion.formatted
            items.append(ResultItem(
                id: "calc:convert",
                title: display,
                subtitle: text,
                icon: .symbol(name: "arrow.left.arrow.right"),
                score: 1000,
                accessoryHint: "⏎ 复制",
                action: .copyCalculation(expression: text, result: display)
            ))
        } else if ExpressionParser.looksLikeExpression(text),
                  let value = try? ExpressionParser.evaluate(text) {
            let display = ExpressionParser.format(value)
            items.append(ResultItem(
                id: "calc:result",
                title: display,
                subtitle: "\(text) =",
                icon: .symbol(name: "equal.circle"),
                score: 1000,
                accessoryHint: "⏎ 复制",
                action: .copyCalculation(expression: text, result: display)
            ))
        }

        // 计算场景（已算出结果，或输入看起来像算式）下，附带最近历史。
        // 排除与当前算式相同的一条，避免和上面的结果重复。
        let isCalcContext = !items.isEmpty || ExpressionParser.looksLikeExpression(text)
        if isCalcContext {
            for (offset, entry) in history.recent(limit: 5, excluding: text).enumerated() {
                items.append(ResultItem(
                    id: "calc:history:\(entry.expression)",
                    title: entry.result,
                    subtitle: "\(entry.expression) =",
                    icon: .symbol(name: "clock.arrow.circlepath"),
                    score: 900 - Double(offset),  // 恒低于当前结果，按新旧递减
                    accessoryHint: "⏎ 复制",
                    action: .copyCalculation(expression: entry.expression, result: entry.result)
                ))
            }
        }

        return items
    }
}
