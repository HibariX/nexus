import Foundation

/// 通用子进程运行器：后台线程跑子进程、整块读 stdout、可选超时看门狗。
/// 与 ExternalPluginRunner.run 的模式一致（stderr 丢 /dev/null，避免管道写满阻塞）。
/// 仅当 Process.run() 成功启动才返回结果；超时会 terminate → 由调用方按 exitCode 判定。
/// 包默认 @MainActor，本实现全程在后台线程，故标 nonisolated。
nonisolated enum ProcessRunner {

    struct Output: Sendable {
        let exitCode: Int32
        let stdout: Data
    }

    /// - timeout：nil 表示不设看门狗（用于可能长期停留的交互进程，如管理员密码框）。
    /// - environment：nil 表示继承父进程环境。
    static func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval? = nil,
        environment: [String: String]? = nil
    ) async -> Output? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                if let environment { process.environment = environment }

                let outPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                var watchdog: DispatchWorkItem?
                if let timeout {
                    let item = DispatchWorkItem { if process.isRunning { process.terminate() } }
                    watchdog = item
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
                }

                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                watchdog?.cancel()

                continuation.resume(returning: Output(exitCode: process.terminationStatus, stdout: data))
            }
        }
    }
}
