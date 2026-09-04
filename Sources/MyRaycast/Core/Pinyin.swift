import Foundation

/// 中文 → 拼音（全拼 + 首字母）。基于 CFStringTransform，无需第三方词库。
/// 纯函数，可在任意隔离域使用；多音字取系统默认读音，属 best-effort。
nonisolated enum Pinyin {
    struct Form: Equatable, Sendable {
        let full: String      // 无空格全拼，如 "liuhecai"
        let initials: String  // 每个音节首字母，如 "lhc"
    }

    /// 不含中日韩表意文字时返回 nil（纯英文项无需拼音匹配）。
    static func form(of text: String) -> Form? {
        guard containsHan(text) else { return nil }

        let mutable = NSMutableString(string: text) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)          // 六合彩 → liù hé cǎi
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)  // → liu he cai
        let latin = (mutable as String).lowercased()

        // ToLatin 会在音节间插空格；按空白切分取各段
        let syllables = latin.split(whereSeparator: \.isWhitespace)
        guard !syllables.isEmpty else { return nil }

        let full = syllables.joined()
        let initials = String(syllables.compactMap(\.first))
        guard !full.isEmpty else { return nil }
        return Form(full: full, initials: initials)
    }

    private static func containsHan(_ s: String) -> Bool {
        s.unicodeScalars.contains { scalar in
            let v = scalar.value
            return (0x4E00...0x9FFF).contains(v)   // CJK 统一表意
                || (0x3400...0x4DBF).contains(v)   // 扩展 A
                || (0xF900...0xFAFF).contains(v)   // 兼容表意
        }
    }
}
