import Testing
import Foundation
@testable import Nexus

@Suite("拼音与模糊匹配")
struct SearchMatchingTests {
    @Test("中文转全拼与首字母")
    func pinyinForm() {
        let form = Pinyin.form(of: "六合彩")
        #expect(form?.full == "liuhecai")
        #expect(form?.initials == "lhc")
    }

    @Test("纯英文不产生拼音")
    func englishNoPinyin() {
        #expect(Pinyin.form(of: "Safari") == nil)
    }

    @Test("首字母缩写可匹配中文目标：lhc → 六合彩")
    func initialsMatch() {
        #expect(SearchableText("六合彩").score(for: "lhc") != nil)
    }

    @Test("全拼前缀可匹配：liuhe → 六合彩")
    func fullPrefixMatch() {
        #expect(SearchableText("六合彩").score(for: "liuhe") != nil)
    }

    @Test("无关输入不匹配")
    func noMatch() {
        #expect(SearchableText("六合彩").score(for: "xyz") == nil)
    }

    @Test("英文别名参与匹配")
    func aliasMatch() {
        let target = SearchableText("锁定屏幕", aliases: ["lock screen"])
        #expect(target.score(for: "lock") != nil)
    }

    @Test("原文英文仍可直接匹配，不受拼音改造影响")
    func latinPrimary() {
        #expect(SearchableText("Safari").score(for: "saf") != nil)
    }
}
