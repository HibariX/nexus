import AppKit

struct RectangleImport: Equatable {
    var windowHotkeys: [String: HotkeySpec]
    var todoHotkey: HotkeySpec?
    var todoAliases: [HotkeySpec]

    var summary: String {
        let windowCount = windowHotkeys.count
        let todoCount = (todoHotkey == nil ? 0 : 1) + todoAliases.count
        return "将导入 \(windowCount) 个窗口快捷键，以及 \(todoCount) 个今日待办快捷键。"
    }
}

enum RectangleImporter {
    static let suiteName = "com.knollsoft.Rectangle"

    static func readCurrentConfiguration() -> RectangleImport? {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        return parse(defaults.dictionaryRepresentation())
    }

    /// 纯解析入口，供测试使用；不会读取或修改用户偏好。
    static func parse(_ values: [String: Any]) -> RectangleImport {
        let useAlternate = values["alternateDefaultShortcuts"] as? Bool ?? false
        var windowHotkeys = useAlternate ? WindowAction.alternateDefaults : [:]
        for action in WindowAction.allCases {
            if let spec = hotkey(from: values[action.rawValue]) {
                windowHotkeys[action.rawValue] = spec
            }
        }

        let toggleTodo = hotkey(from: values["toggleTodo"])
        let reflowTodo = hotkey(from: values["reflowTodo"])
        let aliases = [reflowTodo].compactMap { $0 }.filter { $0 != toggleTodo }
        return RectangleImport(windowHotkeys: windowHotkeys, todoHotkey: toggleTodo, todoAliases: aliases)
    }

    static func disableLaunchAtLoginPreference() {
        UserDefaults(suiteName: suiteName)?.set(false, forKey: "launchOnLogin")
    }

    static func occupiedHotkeys(in imported: RectangleImport) -> [HotkeySpec] {
        Array(imported.windowHotkeys.values) + [imported.todoHotkey].compactMap { $0 } + imported.todoAliases
    }

    private static func hotkey(from value: Any?) -> HotkeySpec? {
        guard let dict = value as? [String: Any],
              let keyCode = dict["keyCode"] as? NSNumber,
              let flags = dict["modifierFlags"] as? NSNumber else { return nil }
        let modifiers = HotkeySpec.carbonModifiers(from: NSEvent.ModifierFlags(rawValue: flags.uintValue))
        return HotkeySpec(keyCode: keyCode.uint32Value, carbonModifiers: modifiers)
    }
}
