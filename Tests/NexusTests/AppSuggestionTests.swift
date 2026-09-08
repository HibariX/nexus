import Foundation
import Testing
@testable import Nexus

@Suite("应用建议 AppSuggestion")
struct AppSuggestionTests {

    @Test("无安装日期时评分 = frecency")
    func scoreWithoutInstallDate() {
        #expect(AppIndex.suggestionScore(frecency: 1.5, installDate: nil) == 1.5)
        #expect(AppIndex.suggestionScore(frecency: 0, installDate: nil) == 0)
    }

    @Test("安装越近，新鲜度加分越高")
    func scoreInstallBoost() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let ancient = now.addingTimeInterval(-30 * 86400)   // 30 天前
        let recent = now.addingTimeInterval(-3 * 86400)     // 3 天前
        #expect(AppIndex.suggestionScore(frecency: 0, installDate: recent, now: now)
                > AppIndex.suggestionScore(frecency: 0, installDate: ancient, now: now))
        #expect(AppIndex.suggestionScore(frecency: 0, installDate: nil, now: now) == 0)
    }

    @Test("安装加分恒为正（即便安装极久以前），且不会为负")
    func scoreNonNegative() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let ancient = now.addingTimeInterval(-10000 * 86400)
        #expect(AppIndex.suggestionScore(frecency: 0, installDate: ancient, now: now) > 0)
        #expect(AppIndex.suggestionScore(frecency: -3, installDate: nil) == -3)
    }

    @Test @MainActor
    func providerSuggestionsAreLaunchItems() throws {
        let provider = AppLauncherProvider(index: AppIndex())
        let items = provider.suggestions(limit: 6)
        #expect(items.count <= 6)
        for item in items {
            #expect(item.id.hasPrefix("app:"))
            guard case .launchApp = item.action else {
                Issue.record("建议项 action 应为 .launchApp：\(item.title)")
                continue
            }
        }
    }

    @Test @MainActor
    func commandProviderDefaultReturnsEmptySuggestions() {
        // 未实现 suggestions 的 provider 应走默认空实现
        let provider = SystemCommandProvider()
        #expect(provider.suggestions(limit: 6).isEmpty)
    }
}
