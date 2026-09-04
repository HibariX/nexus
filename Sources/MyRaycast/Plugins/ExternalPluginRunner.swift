import Foundation

/// 插件 query 返回的单个结果项（外部数据）
struct PluginItem: Decodable {
    let title: String
    var subtitle: String?
    var icon: String?
    var hint: String?
    var action: String?
    var payload: String?
    /// 回车后进入的子查询（关键词之后的文本）。用于面板内导航到展示型子视图（如额度）。
    var query: String?
}

private struct PluginQueryResponse: Decodable {
    let items: [PluginItem]
}

/// 插件 action 执行后的结果指令（外部数据）
struct PluginOutcome: Decodable {
    var copy: String?
    /// 机密内容使用系统约定的剪贴板类型标记，避免进入剪贴板历史。
    var concealed: Bool?
    var reload: Bool?
    var keepOpen: Bool?
}

/// 以子进程方式调用外部插件入口，用 JSON 通信。
/// 一切 stdout 当数据解析；超时/非零退出/解析失败都被隔离为「无结果 / 默认 outcome」，不崩主程序。
final class ExternalPluginRunner {
    private let pluginsByID: [String: LoadedPlugin]

    private let queryTimeout: TimeInterval = 4  // 子查询可能含网络展示（如额度）
    private let actionTimeout: TimeInterval = 15

    init(plugins: [LoadedPlugin]) {
        pluginsByID = Dictionary(plugins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func plugin(id: String) -> LoadedPlugin? { pluginsByID[id] }

    /// 查询：`<entry> query "<arg>"` → items。失败返回 []。
    func query(_ plugin: LoadedPlugin, arg: String) async -> [PluginItem] {
        guard let data = await Self.run(
            executable: plugin.entryURL, arguments: ["query", arg],
            cwd: plugin.directory, timeout: queryTimeout
        ) else { return [] }
        return (try? JSONDecoder().decode(PluginQueryResponse.self, from: data))?.items ?? []
    }

    /// 动作：`<entry> action "<actionId>" "<payload>"` → outcome。失败返回默认（关面板）。
    func action(pluginId: String, actionId: String, payload: String) async -> PluginOutcome {
        guard let plugin = pluginsByID[pluginId] else { return PluginOutcome() }
        guard let data = await Self.run(
            executable: plugin.entryURL, arguments: ["action", actionId, payload],
            cwd: plugin.directory, timeout: actionTimeout
        ) else { return PluginOutcome() }
        return (try? JSONDecoder().decode(PluginOutcome.self, from: data)) ?? PluginOutcome()
    }

    // MARK: - 子进程执行

    /// 在后台运行子进程，读取 stdout。仅当正常退出(status==0)且未超时才返回数据，否则 nil。
    /// stderr 丢弃到 /dev/null，避免管道写满阻塞。
    private nonisolated static func run(
        executable: URL, arguments: [String], cwd: URL, timeout: TimeInterval
    ) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                process.currentDirectoryURL = cwd
                process.environment = augmentedEnvironment()

                let outPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                // 超时看门狗：到点仍在跑就 terminate（→ 非零退出 → 判为失败）
                let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                watchdog.cancel()

                continuation.resume(returning: process.terminationStatus == 0 ? data : nil)
            }
        }
    }

    /// GUI 应用继承的 PATH 往往很短，补上常见路径，保证 curl / python3 / hyswitch 等可被找到。
    private nonisolated static func augmentedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = env["HOME"] ?? NSHomeDirectory()
        let extra = ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
                     "\(home)/.local/bin"]
        let current = env["PATH"].map { $0.split(separator: ":").map(String.init) } ?? []
        var seen = Set<String>()
        let merged = (current + extra).filter { seen.insert($0).inserted }
        env["PATH"] = merged.joined(separator: ":")
        return env
    }
}
