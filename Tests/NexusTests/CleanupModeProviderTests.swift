import Foundation
import Testing
@testable import Nexus

@Suite("清理模式系统命令 Provider")
struct CleanupModeProviderTests {

    @Test @MainActor
    func providerExposesCleanupEntry() async throws {
        let provider = SystemCommandProvider(cleanupMode: CleanupModeController())
        let items = await provider.results(for: Query(raw: "清理模式"))

        let item = try #require(items.first { $0.id == "sys:cleanupMode" })
        #expect(item.title == "清理模式")
        #expect(item.subtitle?.contains("启动") == true)

        guard case .symbol(let name) = item.icon, name == "shield.fill" else {
            Issue.record("清理条目应使用 shield.fill 图标")
            return
        }
        guard case .startCleanupMode = item.action else {
            Issue.record("应返回 .startCleanupMode，实际 \(item.action)")
            return
        }
    }

    @Test @MainActor
    func providerHidesCleanupWhenNotMatching() async throws {
        let provider = SystemCommandProvider(cleanupMode: CleanupModeController())
        // "计算器" 不命中清理模式别名，不应出现清理条目（但可命中计算器 provider 之外逻辑）
        let items = await provider.results(for: Query(raw: "计算器"))
        #expect(items.first { $0.id == "sys:cleanupMode" } == nil)
    }
}
