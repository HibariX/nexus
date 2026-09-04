import Foundation

/// 可模糊匹配的目标：主文本 + 别名，自动为含中文的候选补拼音（全拼 + 首字母）。
/// 候选在构造时一次性展开并预计算拼音，匹配时纯查表；底层复用 FuzzyMatcher 打分，
/// 分数量级与英文匹配一致，可与其它结果同框排序。
///
/// 后续任何「中文可拼音搜」的模糊搜索场景都应通过本类型组织候选，
/// 而不是各自调用 FuzzyMatcher + Pinyin 重复拼装。
nonisolated struct SearchableText: Sendable {
    /// 参与匹配的全部候选：原文/别名，以及各自派生的拼音全拼与首字母
    private let candidates: [String]

    init(_ primary: String, aliases: [String] = []) {
        var all: [String] = []
        for text in [primary] + aliases {
            all.append(text)
            if let form = Pinyin.form(of: text) {
                all.append(form.full)
                all.append(form.initials)
            }
        }
        candidates = all
    }

    /// 对所有候选打分取最高；全部不匹配返回 nil
    func score(for query: String) -> Double? {
        var best: Double?
        for candidate in candidates {
            if let s = FuzzyMatcher.score(query: query, target: candidate) {
                best = max(best ?? s, s)
            }
        }
        return best
    }
}
