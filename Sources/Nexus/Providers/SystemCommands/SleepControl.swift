import Foundation

/// 「禁止休眠」（disablesleep）：读取（pmset -g，无需特权）+ 切换（osascript + 管理员权限）。
/// 纯解析与状态文案可单测；子进程调用经 ProcessRunner（nonisolated，后台线程）。
nonisolated enum SleepControl {

    struct SleepStatus: Sendable, Equatable {
        /// SleepDisabled=1 → 已禁止自动休眠
        let sleepDisabled: Bool
        /// Currently in use：`sleep <N>`；0=从不，行缺失为 nil
        let automaticSleepMinutes: Int?
        /// Currently in use：`displaysleep <N>`
        let displaySleepMinutes: Int?
    }

    // MARK: - 解析（纯函数）

    static func parse(_ output: String) -> SleepStatus {
        var sleepDisabled = false
        var automaticSleepMinutes: Int?
        var displaySleepMinutes: Int?

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            // 段头（如 "Currently in use:"）不是键值行
            if line.isEmpty || line.hasSuffix(":") { continue }

            // 容忍多空格/制表符；括号注释（如 sleep 0 (sleep prevented by ...)）落到 value 之后
            let tokens = line.split(whereSeparator: \.isWhitespace)
            guard tokens.count >= 2 else { continue }
            let key = String(tokens[0])

            switch key {
            case "SleepDisabled": sleepDisabled = (Int(tokens[1]) ?? 0) == 1
            case "sleep": automaticSleepMinutes = Int(tokens[1])
            case "displaysleep": displaySleepMinutes = Int(tokens[1])
            default: break
            }
        }

        return SleepStatus(sleepDisabled: sleepDisabled,
                           automaticSleepMinutes: automaticSleepMinutes,
                           displaySleepMinutes: displaySleepMinutes)
    }

    // MARK: - 状态文案

    static func subtitle(for status: SleepStatus) -> String {
        status.sleepDisabled ? "已禁止休眠" : "未禁止休眠"
    }

    // MARK: - 读取（无需特权）

    static func readStatus() async -> SleepStatus {
        guard let out = await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/pmset"),
            arguments: ["-g"],
            timeout: 5
        ), out.exitCode == 0 else {
            return SleepStatus(sleepDisabled: false, automaticSleepMinutes: nil, displaySleepMinutes: nil)
        }
        guard let text = String(data: out.stdout, encoding: .utf8) else {
            return SleepStatus(sleepDisabled: false, automaticSleepMinutes: nil, displaySleepMinutes: nil)
        }
        return parse(text)
    }

    // MARK: - 切换（管理员权限，不设超时）

    private static func script(disable: Bool) -> String {
        disable
            ? #"do shell script "pmset -a disablesleep 1" with administrator privileges"#
            : #"do shell script "pmset -a disablesleep 0" with administrator privileges"#
    }

    /// 执行切换。osascript 弹管理员密码框可能停留较久，故不设看门狗超时。
    static func setDisableSleep(_ disable: Bool) async -> Bool {
        guard let out = await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-e", script(disable: disable)]
        ) else { return false }
        return out.exitCode == 0
    }

    /// 执行时重读当前状态再取反，避免基于展示时的过期快照。
    static func toggle() async -> Bool {
        let current = await readStatus()
        return await setDisableSleep(!current.sleepDisabled)
    }
}
