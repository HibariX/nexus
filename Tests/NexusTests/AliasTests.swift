import Testing
import Foundation
@testable import Nexus

@Suite("应用别名")
struct AliasTests {
    /// 用临时文件构造 AliasStore，避免污染真实 Application Support
    private func makeStore() -> (AliasStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alias-test-\(UUID().uuidString).json")
        return (AliasStore(file: url), url)
    }

    @Test("增删与持久化往返")
    func persistRoundTrip() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let path = "/Applications/Chrome.app"

        store.add("浏览器", for: path)
        store.add("llq", for: path)
        #expect(store.aliases(for: path) == ["浏览器", "llq"])

        // 从同一文件重新加载，别名仍在
        let reloaded = AliasStore(file: url)
        #expect(reloaded.aliases(for: path) == ["浏览器", "llq"])

        store.remove("浏览器", for: path)
        #expect(store.aliases(for: path) == ["llq"])
    }

    @Test("大小写去重、空串忽略")
    func dedupAndEmpty() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let path = "/Applications/Code.app"

        store.add("VSC", for: path)
        store.add("vsc", for: path)   // 大小写重复，不追加
        store.add("   ", for: path)   // 空白，忽略
        #expect(store.aliases(for: path) == ["VSC"])
    }

    @Test("别名叠加拼音仍可命中，原名不受影响")
    func aliasWithPinyin() {
        let target = SearchableText("Visual Studio Code", aliases: ["代码", "vsc"])
        #expect(target.score(for: "daima") != nil)   // 中文别名的全拼
        #expect(target.score(for: "vsc") != nil)      // 英文别名
        #expect(target.score(for: "visual") != nil)   // 原名仍命中
    }
}
