import Foundation
import Testing
@testable import Nexus

@Suite("应用索引 AppIndex")
struct AppIndexTests {

    // MARK: - 内部 bundle 过滤

    @Test("有 Bundle ID 且无后台标志的应用视为用户可见")
    func visibleForPlainApp() {
        #expect(AppIndex.isUserVisibleApp(infoDictionary: ["CFBundleIdentifier": "com.example.app"]))
    }

    @Test("LSUIElement / LSBackgroundOnly 的 true、1、YES 写法都判为不可见")
    func hiddenFlagsInAllEncodings() {
        // 本机系统 bundle 里这三种写法都存在：<true/>、<integer>1</integer>、<string>YES</string>
        for flag in [true, 1, "YES", "yes", "true", "1"] as [Any] {
            let uiElement: [String: Any] = ["CFBundleIdentifier": "com.example.agent", "LSUIElement": flag]
            #expect(!AppIndex.isUserVisibleApp(infoDictionary: uiElement), "LSUIElement=\(flag) 应不可见")

            let background: [String: Any] = ["CFBundleIdentifier": "com.example.agent", "LSBackgroundOnly": flag]
            #expect(!AppIndex.isUserVisibleApp(infoDictionary: background), "LSBackgroundOnly=\(flag) 应不可见")
        }
    }

    @Test("标志显式为假时不影响可见性")
    func visibleWhenFlagsAreOff() {
        #expect(AppIndex.isUserVisibleApp(infoDictionary: [
            "CFBundleIdentifier": "com.example.app",
            "LSUIElement": false,
            "LSBackgroundOnly": false,
        ]))
        #expect(AppIndex.isUserVisibleApp(infoDictionary: [
            "CFBundleIdentifier": "com.example.app",
            "LSUIElement": "NO",
        ]))
    }

    @Test("缺 Bundle ID 或没有 Info.plist 的 bundle 判为不可见")
    func hiddenWithoutBundleID() {
        #expect(!AppIndex.isUserVisibleApp(infoDictionary: nil))
        #expect(!AppIndex.isUserVisibleApp(infoDictionary: [:]))
        #expect(!AppIndex.isUserVisibleApp(infoDictionary: ["CFBundleIdentifier": ""]))
    }

    // MARK: - 名称别名

    @Test("本地化名之外补上 bundle 原始名，且不重复")
    func aliasesCarryRawBundleName() {
        #expect(AppIndex.nameAliases(localizedName: "访达", infoDictionary: ["CFBundleName": "Finder"])
                == ["Finder"])
        // CFBundleDisplayName 与 CFBundleName 相同只留一个
        #expect(AppIndex.nameAliases(localizedName: "访达", infoDictionary: [
            "CFBundleDisplayName": "Finder", "CFBundleName": "Finder",
        ]) == ["Finder"])
        // 与本地化名相同则不重复添加
        #expect(AppIndex.nameAliases(localizedName: "访达", infoDictionary: [
            "CFBundleDisplayName": "访达", "CFBundleName": "Finder",
        ]) == ["Finder"])
        // 没有可用的原始名
        #expect(AppIndex.nameAliases(localizedName: "Finder", infoDictionary: ["CFBundleName": "Finder"]).isEmpty)
        #expect(AppIndex.nameAliases(localizedName: "Finder", infoDictionary: [:]).isEmpty)
        #expect(AppIndex.nameAliases(localizedName: "Finder", infoDictionary: nil).isEmpty)
    }

    @Test("别名去掉 .app 后缀后，中文名、英文名、拼音三条路都能命中")
    func aliasesMakeAllThreeInputStylesMatch() {
        let aliases = AppIndex.nameAliases(localizedName: "访达", infoDictionary: ["CFBundleName": "Finder.app"])
        #expect(aliases == ["Finder"])

        let text = SearchableText("访达", aliases: aliases)
        #expect(text.score(for: "访达") != nil, "中文名应命中")
        #expect(text.score(for: "finder") != nil, "英文名应命中")
        #expect(text.score(for: "fd") != nil, "拼音首字母应命中")
    }

    // MARK: - 扫描目录配置

    @Test("索引覆盖 CoreServices，且这两个目录开启内部 bundle 过滤")
    func coreServicesDirectoriesAreIndexed() {
        for path in ["/System/Library/CoreServices", "/System/Library/CoreServices/Applications"] {
            let dir = AppIndex.searchDirs.first { $0.path == path }
            #expect(dir != nil, "缺少索引目录：\(path)")
            #expect(dir?.filtersInternalApps == true, "\(path) 应开启内部 bundle 过滤")
        }
    }

    @Test("用户应用目录不参与内部 bundle 过滤")
    func userDirectoriesAreNotFiltered() {
        for path in ["/Applications", "/Applications/Utilities", "/System/Applications",
                     NSHomeDirectory() + "/Applications"] {
            let dir = AppIndex.searchDirs.first { $0.path == path }
            #expect(dir != nil, "缺少索引目录：\(path)")
            #expect(dir?.filtersInternalApps == false, "\(path) 不该过滤内部 bundle")
        }
    }

    // MARK: - 真实扫描

    @Test @MainActor
    func scanIndexesFinder() {
        let paths = Set(AppIndex().entries.map(\.path))
        #expect(paths.contains("/System/Library/CoreServices/Finder.app"), "访达必须进索引")
    }

    @Test @MainActor
    func scanSkipsProcessBundles() {
        let paths = Set(AppIndex().entries.map(\.path))
        for path in ["/System/Library/CoreServices/Dock.app",
                     "/System/Library/CoreServices/loginwindow.app",
                     "/System/Library/CoreServices/NotificationCenter.app"] {
            #expect(!paths.contains(path), "进程级 bundle 不该进索引：\(path)")
        }
    }

    @Test @MainActor
    func scanResultsAreDeduplicated() {
        let entries = AppIndex().entries
        let paths = entries.map(\.path)
        #expect(paths.count == Set(paths).count, "同一路径不该出现两次")

        // 同一应用可能在多个目录各存一份（如 Feedback Assistant），按 Bundle ID 去重
        let bundleIDs = entries.compactMap { Bundle(path: $0.path)?.bundleIdentifier }
        #expect(bundleIDs.count == Set(bundleIDs).count, "同一 Bundle ID 不该出现两次")
    }
}
