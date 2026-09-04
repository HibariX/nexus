import Foundation

/// 子序列模糊匹配打分。纯函数，可在任意隔离域使用。
nonisolated enum FuzzyMatcher {

    /// query 作为子序列匹配 target 时返回得分（越高越好），不匹配返回 nil。
    static func score(query: String, target: String) -> Double? {
        if query.isEmpty { return 0 }
        let q = Array(query.lowercased())
        let t = Array(target.lowercased())
        let original = Array(target)
        guard q.count <= t.count else { return nil }

        var score = 0.0
        var qi = 0
        var lastMatch = -1

        for ti in 0..<t.count {
            guard qi < q.count, t[ti] == q[qi] else { continue }

            var charScore = 1.0
            if ti == 0 {
                charScore += 8  // 整串前缀
            } else {
                let prev = original[ti - 1]
                if prev == " " || prev == "-" || prev == "_" || prev == "." {
                    charScore += 6  // 单词边界
                } else if original[ti].isUppercase && prev.isLowercase {
                    charScore += 5  // 驼峰边界
                }
            }
            if lastMatch == ti - 1 { charScore += 5 }  // 连续命中重奖：前缀连续串必须赢过分散的词边界
            let gap = lastMatch < 0 ? 0 : ti - lastMatch - 1
            charScore -= Double(min(gap, 6)) * 0.5     // 间隙惩罚

            score += charScore
            lastMatch = ti
            qi += 1
        }

        guard qi == q.count else { return nil }
        score -= Double(t.count - q.count) * 0.05  // 目标越长略微降权
        return score
    }
}
