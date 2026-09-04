import Foundation

/// 计算器内置页面：输入 `=` 进入。页内输入算式实时求值，下方列出计算历史。
/// 复用 UnitConversion / ExpressionParser / CalculationHistory（与 CalculatorProvider 同源）。
final class CalculatorPage: BuiltinPage {
    let id = "calc"

    private let history: CalculationHistory

    init(history: CalculationHistory) {
        self.history = history
    }

    func results(for query: Query) async -> [ResultItem] {
        let text = query.trimmed
        var items: [ResultItem] = []

        // 当前算式结果（单位换算优先）
        if !text.isEmpty {
            if let conversion = UnitConversion.convert(text) {
                items.append(resultRow(id: "calc:page:convert", result: conversion.formatted,
                                       expression: text, symbol: "arrow.left.arrow.right"))
            } else if ExpressionParser.looksLikeExpression(text),
                      let value = try? ExpressionParser.evaluate(text) {
                items.append(resultRow(id: "calc:page:result", result: ExpressionParser.format(value),
                                       expression: text, symbol: "equal.circle"))
            }
        }

        // 计算历史（排除与当前算式相同的一条）
        for (index, entry) in history.recent(limit: 8, excluding: text).enumerated() {
            items.append(ResultItem(
                id: "calc:page:hist:\(entry.expression)",
                title: entry.result,
                subtitle: "\(entry.expression) =",
                icon: .symbol(name: "clock.arrow.circlepath"),
                score: 500 - Double(index),
                accessoryHint: "⏎ 复制",
                action: .copyCalculation(expression: entry.expression, result: entry.result)
            ))
        }

        // 空态提示
        if items.isEmpty {
            items.append(ResultItem(
                id: "calc:page:empty",
                title: "输入算式开始计算",
                subtitle: "例如 1+2*3、sqrt(2)、100 usd",
                icon: .symbol(name: "equal.circle"),
                score: 0,
                accessoryHint: nil,
                action: .replaceQuery("")
            ))
        }
        return items
    }

    private func resultRow(id: String, result: String, expression: String, symbol: String) -> ResultItem {
        ResultItem(
            id: id,
            title: result,
            subtitle: "\(expression) =",
            icon: .symbol(name: symbol),
            score: 1000,
            accessoryHint: "⏎ 复制 · ⌘⏎ 算式",
            action: .copyCalculation(expression: expression, result: result)
        )
    }
}
