import AppKit

enum SystemCommand: String, CaseIterable, Sendable {
    case lockScreen
    case sleep
    case displaySleep
    case emptyTrash
    case toggleDarkMode
    case quitFrontApp
    case forceQuitFrontApp

    var title: String {
        switch self {
        case .lockScreen: return "锁定屏幕"
        case .sleep: return "睡眠"
        case .displaySleep: return "关闭显示器"
        case .emptyTrash: return "清空废纸篓"
        case .toggleDarkMode: return "切换深色模式"
        case .quitFrontApp: return "退出当前应用"
        case .forceQuitFrontApp: return "强制退出当前应用"
        }
    }

    /// 中英文搜索别名
    var aliases: [String] {
        switch self {
        case .lockScreen: return ["lock screen", "锁屏", "锁定屏幕", "suoping"]
        case .sleep: return ["sleep", "睡眠", "shuimian"]
        case .displaySleep: return ["display sleep", "关闭显示器", "熄屏"]
        case .emptyTrash: return ["empty trash", "清空废纸篓", "清空回收站"]
        case .toggleDarkMode: return ["dark mode", "深色模式", "暗色模式", "夜间模式"]
        case .quitFrontApp: return ["quit app", "退出应用", "退出当前应用"]
        case .forceQuitFrontApp: return ["force quit", "强制退出"]
        }
    }

    var symbolName: String {
        switch self {
        case .lockScreen: return "lock.fill"
        case .sleep: return "moon.fill"
        case .displaySleep: return "display"
        case .emptyTrash: return "trash"
        case .toggleDarkMode: return "circle.lefthalf.filled"
        case .quitFrontApp: return "xmark.circle"
        case .forceQuitFrontApp: return "exclamationmark.octagon"
        }
    }
}

final class SystemCommandProvider: CommandProvider {
    let sectionTitle = "系统命令"
    let sectionRank = 20

    /// 命令固定，标题+别名的可搜索封装预计算一次（含拼音/首字母，如「锁屏」← "sp"/"suoping"）
    private let searchable: [SystemCommand: SearchableText] = {
        var map: [SystemCommand: SearchableText] = [:]
        for command in SystemCommand.allCases {
            map[command] = SearchableText(command.title, aliases: command.aliases)
        }
        return map
    }()

    /// 禁止休眠：行为与其它 SystemCommand 不同（有状态、管理员权限、保持面板），单独生成，
    /// 不并入 SystemCommand 枚举。SearchableText 自动为「禁止休眠」派生拼音全拼/首字母。
    private let sleepDisabledSearchable = SearchableText(
        "禁止休眠",
        aliases: ["禁止休眠", "禁止睡眠", "防睡眠", "防休眠", "不休眠", "保持唤醒",
                  "disable sleep", "disablesleep", "keep awake", "caffeinate"]
    )

    /// `@` / `@<前缀>` 分类浏览：罗列全部系统命令，或按 @ 后的前缀过滤。空 @ 即全览。
    func atEntries(for query: Query) async -> [ResultItem] {
        let filter = query.trimmed.dropFirst()
            .trimmingCharacters(in: .whitespaces).lowercased()

        let items: [ResultItem]
        if filter.isEmpty {
            // 空 @：罗列全部系统命令（不触发子进程读状态）
            items = SystemCommand.allCases.map { command in
                ResultItem(
                    id: "sys:\(command.rawValue)",
                    title: command.title,
                    subtitle: nil,
                    icon: .symbol(name: command.symbolName),
                    score: 0,
                    accessoryHint: "命令",
                    action: .runSystem(command)
                )
            }
        } else {
            items = SystemCommand.allCases.compactMap { command -> ResultItem? in
                guard let searchable = searchable[command],
                      let score = searchable.score(for: filter) else { return nil }
                return ResultItem(
                    id: "sys:\(command.rawValue)",
                    title: command.title,
                    subtitle: nil,
                    icon: .symbol(name: command.symbolName),
                    score: score,
                    accessoryHint: "命令",
                    action: .runSystem(command)
                )
            }
        }

        // 仅当 @ 后有文本且命中「禁止休眠」才读状态（否则不触发子进程）
        if !filter.isEmpty, let score = sleepDisabledSearchable.score(for: filter) {
            let status = await SleepControl.readStatus()
            return items + [ResultItem(
                id: "sys:sleepDisabled",
                title: "禁止休眠",
                subtitle: SleepControl.subtitle(for: status),
                icon: .symbol(name: status.sleepDisabled ? "moon.zzz.fill" : "moon.zzz"),
                score: score,
                accessoryHint: "⏎ 切换",
                action: .toggleSleepDisabled
            )]
        }
        return items
    }

    func results(for query: Query) async -> [ResultItem] {
        let text = query.trimmed
        guard !text.isEmpty else { return [] }

        var items = SystemCommand.allCases.compactMap { command -> ResultItem? in
            guard let score = searchable[command]?.score(for: text) else { return nil }
            return ResultItem(
                id: "sys:\(command.rawValue)",
                title: command.title,
                subtitle: nil,
                icon: .symbol(name: command.symbolName),
                score: score,
                accessoryHint: "命令",
                action: .runSystem(command)
            )
        }

        // 仅当命中「禁止休眠」才读状态（其余输入不触发子进程）。
        if let score = sleepDisabledSearchable.score(for: text) {
            let status = await SleepControl.readStatus()
            items.append(ResultItem(
                id: "sys:sleepDisabled",
                title: "禁止休眠",
                subtitle: SleepControl.subtitle(for: status),
                icon: .symbol(name: status.sleepDisabled ? "moon.zzz.fill" : "moon.zzz"),
                score: score,
                accessoryHint: "⏎ 切换",
                action: .toggleSleepDisabled
            ))
        }

        return items
    }
}

/// 系统命令执行
enum SystemCommandRunner {

    static func run(_ command: SystemCommand) {
        switch command {
        case .lockScreen:
            shell("/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession",
                  ["-suspend"])
        case .sleep:
            shell("/usr/bin/pmset", ["sleepnow"])
        case .displaySleep:
            shell("/usr/bin/pmset", ["displaysleepnow"])
        case .emptyTrash:
            runAppleScript(#"tell application "Finder" to empty trash"#)
        case .toggleDarkMode:
            runAppleScript(
                #"tell application "System Events" to tell appearance preferences to set dark mode to not dark mode"#)
        case .quitFrontApp:
            NSWorkspace.shared.frontmostApplication?.terminate()
        case .forceQuitFrontApp:
            NSWorkspace.shared.frontmostApplication?.forceTerminate()
        }
    }

    private static func shell(_ path: String, _ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        try? process.run()
    }

    /// NSAppleScript 必须主线程执行；Automation 被拒返回 -1743
    private static func runAppleScript(_ source: String) {
        guard let script = NSAppleScript(source: source) else { return }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error, (error[NSAppleScript.errorNumber] as? Int) == -1743 {
            PermissionCenter.showGuide(
                title: "需要自动化权限",
                message: "该命令需要通过「自动化」权限控制 Finder / 系统事件。请在系统设置中允许 MyRaycast。",
                openSettings: {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                        NSWorkspace.shared.open(url)
                    }
                }
            )
        }
    }
}
