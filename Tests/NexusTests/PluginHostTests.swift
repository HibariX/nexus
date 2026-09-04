import Foundation
import Testing
@testable import Nexus

@Suite struct PluginHostTests {
    private func makeHost() -> PluginHostProvider {
        let manifest = PluginManifest(
            id: "random-passwd",
            name: "随机密码",
            keywords: ["random-passwd", "passwd"],
            entry: "random-passwd.py",
            icon: "key.fill",
            summary: "安全生成密码"
        )
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dir = root.appendingPathComponent(manifest.id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(manifest).write(to: dir.appendingPathComponent("manifest.json"))
        let entry = dir.appendingPathComponent(manifest.entry)
        FileManager.default.createFile(atPath: entry.path, contents: Data("#!/bin/sh".utf8), attributes: [.posixPermissions: 0o755])
        let manager = PluginManager(rootDirectory: root, bundledDirectory: nil, performStartupMaintenance: false)
        let runner = ExternalPluginRunner(manager: manager)
        return PluginHostProvider(manager: manager, runner: runner)
    }

    @Test func directKeywordCarriesArgumentsIntoPluginPage() async throws {
        let items = await makeHost().results(for: Query(raw: "random-passwd 32 symbols=off"))
        let item = try #require(items.first)
        guard case .pushPage(let pluginID, let path, _) = item.action else {
            Issue.record("直接关键词应进入插件页")
            return
        }
        #expect(pluginID == "random-passwd")
        #expect(path == "32 symbols=off")
    }

    @Test func partialDirectKeywordDoesNotTrigger() async {
        let items = await makeHost().results(for: Query(raw: "random"))
        #expect(items.isEmpty)
    }
}
