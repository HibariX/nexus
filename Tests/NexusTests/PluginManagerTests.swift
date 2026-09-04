import Foundation
import Testing
@testable import Nexus

@Suite struct PluginManagerTests {
    private func makeRoot() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writePlugin(root: URL, id: String = "demo", name: String = "Demo") throws -> URL {
        let directory = root.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = PluginManifest(id: id, name: name, keywords: [id], entry: "run.sh", icon: nil, summary: "测试插件")
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: directory.appendingPathComponent("manifest.json"))
        let entry = directory.appendingPathComponent("run.sh")
        FileManager.default.createFile(
            atPath: entry.path,
            contents: Data("#!/bin/sh\nprintf '{\"items\":[]}'\n".utf8),
            attributes: [.posixPermissions: 0o755]
        )
        return directory
    }

    @Test func disableStatePersistsAcrossManagerInstances() throws {
        let root = try makeRoot()
        let state = root.appendingPathComponent("state.json")
        _ = try writePlugin(root: root)
        let first = PluginManager(rootDirectory: root, bundledDirectory: nil, stateFile: state, performStartupMaintenance: false)
        first.setEnabled(false, pluginID: "demo")
        #expect(first.enabledPlugins.isEmpty)

        let second = PluginManager(rootDirectory: root, bundledDirectory: nil, stateFile: state, performStartupMaintenance: false)
        #expect(second.plugins.first?.isEnabled == false)
        #expect(second.enabledPlugins.isEmpty)
    }

    @Test func importAndReplaceUsesValidatedPackage() async throws {
        let root = try makeRoot()
        let state = root.appendingPathComponent("state.json")
        _ = try writePlugin(root: root, name: "旧版本")
        let manager = PluginManager(rootDirectory: root, bundledDirectory: nil, stateFile: state, performStartupMaintenance: false)
        let source = try makeRoot()
        let imported = try writePlugin(root: source, name: "新版本")
        let candidate = try await manager.prepareImport(from: imported)
        #expect(candidate.replacing?.manifest?.name == "旧版本")
        try manager.install(candidate)
        #expect(manager.plugins.first?.manifest?.name == "新版本")
    }

    @Test func protectedPluginCannotBeReplacedOrRemoved() async throws {
        let root = try makeRoot()
        let bundled = try makeRoot()
        _ = try writePlugin(root: root, id: "random-passwd", name: "随机密码")
        _ = try writePlugin(root: bundled, id: "random-passwd", name: "随机密码")
        let manager = PluginManager(rootDirectory: root, bundledDirectory: bundled, performStartupMaintenance: false)
        let source = try makeRoot()
        let imported = try writePlugin(root: source, id: "random-passwd")
        await #expect(throws: PluginManagerError.protectedPlugin) {
            try await manager.prepareImport(from: imported)
        }
        let record = try #require(manager.plugins.first)
        #expect(throws: PluginManagerError.protectedPlugin) {
            try manager.uninstall(record)
        }
    }

    @Test func zipWithSingleTopLevelPluginCanBeImported() async throws {
        let root = try makeRoot()
        let source = try makeRoot()
        let plugin = try writePlugin(root: source)
        let archive = source.appendingPathComponent("demo.zip")
        let output = await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-c", "-k", "--keepParent", plugin.path, archive.path],
            timeout: 10
        )
        #expect(output?.exitCode == 0)
        let manager = PluginManager(
            rootDirectory: root,
            bundledDirectory: nil,
            stateFile: root.appendingPathComponent("state.json"),
            performStartupMaintenance: false
        )
        let candidate = try await manager.prepareImport(from: archive)
        #expect(candidate.manifest.id == "demo")
        manager.discard(candidate)
    }

    @Test func entryCannotEscapePluginDirectory() throws {
        let root = try makeRoot()
        let directory = root.appendingPathComponent("unsafe")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = PluginManifest(
            id: "unsafe", name: "Unsafe", keywords: ["unsafe"], entry: "../run.sh", icon: nil, summary: nil
        )
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("manifest.json"))
        let entry = root.appendingPathComponent("run.sh")
        FileManager.default.createFile(atPath: entry.path, contents: Data(), attributes: [.posixPermissions: 0o755])
        #expect(throws: PluginManagerError.self) {
            try PluginLoader.validatedPlugin(from: directory)
        }
    }
}
