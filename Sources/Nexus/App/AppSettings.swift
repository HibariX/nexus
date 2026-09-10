import AppKit
import Carbon.HIToolbox
import Observation

/// 一个可持久化的全局快捷键（Carbon keyCode + modifiers）
struct HotkeySpec: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    /// 人类可读展示，如 "⌥Space"
    var display: String {
        var parts = ""
        if carbonModifiers & UInt32(controlKey) != 0 { parts += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { parts += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts += "⌘" }
        return parts + Self.keyName(keyCode)
    }

    /// 特殊键名表。注意 F 键的 Carbon 键码不连续也不递增（kVK_F1=122、kVK_F20=90），
    /// 不能写成 case 区间（Range 下界>上界会运行时 trap），只能查表
    private static let specialKeyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "⏎", kVK_Tab: "⇥", kVK_Escape: "⎋",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16",
        kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    static func keyName(_ keyCode: UInt32) -> String {
        if let name = specialKeyNames[Int(keyCode)] { return name }
        // 用系统键盘布局把 keyCode 转成字符
        return Self.character(for: keyCode)?.uppercased() ?? "键码\(keyCode)"
    }

    private static func character(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
        return data.withUnsafeBytes { rawBuffer -> String? in
            guard let layoutPtr = rawBuffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let err = UCKeyTranslate(layoutPtr, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                     UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                                     &deadKeyState, chars.count, &length, &chars)
            guard err == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
    }

    /// F1–F20 的键码集合（键码不连续，只能枚举）
    private static let functionKeyCodes: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    /// 允许不带修饰键单独作为全局热键的按键。
    /// 普通字符键裸注册会劫持一切输入，功能键不会，所以只放行 F1–F20。
    static func allowsBareKey(_ keyCode: UInt32) -> Bool {
        functionKeyCodes.contains(Int(keyCode))
    }

    /// NSEvent.modifierFlags → Carbon modifiers
    /// 注：Carbon 热键没有 fn 修饰位，`.function` 一律忽略
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        return mods
    }
}

/// 工作台选中项的 Focus 特效风格
enum FocusEffect: String, CaseIterable, Identifiable, Codable {
    case scanline   // 扫描线 + 故障
    case marquee    // 跑马灯追光
    case outline    // 静态霓虹描边

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .scanline: return "扫描线 + 故障"
        case .marquee: return "跑马灯"
        case .outline: return "静态描边"
        }
    }
}

/// 全局设置，settings.json 持久化
@Observable
final class AppSettings {
    var launcherHotkey: HotkeySpec {
        didSet { save() }
    }
    var snipHotkey: HotkeySpec {
        didSet { save() }
    }
    var clipboardPinHotkey: HotkeySpec {
        didSet { save() }
    }
    var todoHotkey: HotkeySpec {
        didSet { save() }
    }
    var annotateHotkey: HotkeySpec {
        didSet { save() }
    }
    /// 窗口动作 -> 快捷键。缺少某个动作即表示该动作没有全局快捷键，但仍可从菜单执行。
    var windowHotkeys: [String: HotkeySpec] {
        didSet { save() }
    }
    /// 今日待办允许保留 Rectangle 迁移来的额外快捷键。
    var todoHotkeyAliases: [HotkeySpec] {
        didSet { save() }
    }
    var clipboardEnabled: Bool {
        didSet { save() }
    }
    var clipboardMaxItems: Int {
        didSet { save() }
    }
    /// 截图保存目录（绝对路径）
    var snipSaveDirectory: String {
        didSet { save() }
    }
    /// OCR 识别语言（Vision 语言代码，如 zh-Hans / en-US）
    var ocrLanguages: [String] {
        didSet { save() }
    }
    /// 今日待办所用提醒列表的 calendarIdentifier。
    /// 记住 id 而非标题，用户在提醒事项里改名后关联不丢。
    var todoReminderListID: String? {
        didSet { save() }
    }
    /// 清理模式屏蔽输入的秒数
    var cleanupModeDuration: Int {
        didSet { save() }
    }
    /// 工作台选中项的 Focus 特效风格
    var focusEffect: FocusEffect {
        didSet { save() }
    }

    static let defaultLauncherHotkey = HotkeySpec(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(optionKey))
    static let defaultSnipHotkey = HotkeySpec(keyCode: UInt32(kVK_ANSI_A), carbonModifiers: UInt32(controlKey | cmdKey))
    static let defaultClipboardPinHotkey = HotkeySpec(keyCode: UInt32(kVK_F3), carbonModifiers: 0)
    static let defaultTodoHotkey = HotkeySpec(keyCode: UInt32(kVK_ANSI_T), carbonModifiers: UInt32(optionKey))
    static let defaultAnnotateHotkey = HotkeySpec(keyCode: UInt32(kVK_ANSI_D), carbonModifiers: UInt32(optionKey))
    static let defaultWindowHotkeys = WindowAction.alternateDefaults

    static let defaultCleanupModeDuration = 60
    static let defaultFocusEffect: FocusEffect = .scanline

    static let defaultSnipSaveDirectory =
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first?.path
        ?? (NSHomeDirectory() as NSString).appendingPathComponent("Pictures")
    static let defaultOCRLanguages = ["zh-Hans", "en-US"]

    /// OCR 可选语言（代码 → 中文名），设置界面用
    struct OCRLanguageOption: Identifiable {
        let code: String
        let name: String
        var id: String { code }
    }
    static let ocrLanguageOptions: [OCRLanguageOption] = [
        .init(code: "zh-Hans", name: "简体中文"), .init(code: "zh-Hant", name: "繁体中文"),
        .init(code: "en-US", name: "英语"), .init(code: "ja", name: "日语"),
        .init(code: "ko", name: "韩语"), .init(code: "fr", name: "法语"),
        .init(code: "de", name: "德语"), .init(code: "es", name: "西班牙语"),
        .init(code: "ru", name: "俄语"),
    ]

    private static let file = AppStorageDir.root.appendingPathComponent("settings.json")

    private struct Persisted: Codable {
        var launcherHotkey: HotkeySpec?
        var snipHotkey: HotkeySpec?
        var clipboardPinHotkey: HotkeySpec?
        var todoHotkey: HotkeySpec?
        var annotateHotkey: HotkeySpec?
        var windowHotkeys: [String: HotkeySpec]?
        var todoHotkeyAliases: [HotkeySpec]?
        var clipboardEnabled: Bool?
        var clipboardMaxItems: Int?
        var snipSaveDirectory: String?
        var ocrLanguages: [String]?
        var todoReminderListID: String?
        var cleanupModeDuration: Int?
        var focusEffect: FocusEffect?
    }

    init() {
        let persisted = (try? Data(contentsOf: Self.file))
            .flatMap { try? JSONDecoder().decode(Persisted.self, from: $0) }
        launcherHotkey = persisted?.launcherHotkey ?? Self.defaultLauncherHotkey
        snipHotkey = persisted?.snipHotkey ?? Self.defaultSnipHotkey
        clipboardPinHotkey = persisted?.clipboardPinHotkey ?? Self.defaultClipboardPinHotkey
        todoHotkey = persisted?.todoHotkey ?? Self.defaultTodoHotkey
        annotateHotkey = persisted?.annotateHotkey ?? Self.defaultAnnotateHotkey
        windowHotkeys = persisted?.windowHotkeys ?? Self.defaultWindowHotkeys
        todoHotkeyAliases = persisted?.todoHotkeyAliases ?? []
        clipboardEnabled = persisted?.clipboardEnabled ?? true
        clipboardMaxItems = persisted?.clipboardMaxItems ?? 500
        snipSaveDirectory = persisted?.snipSaveDirectory ?? Self.defaultSnipSaveDirectory
        ocrLanguages = persisted?.ocrLanguages ?? Self.defaultOCRLanguages
        todoReminderListID = persisted?.todoReminderListID
        cleanupModeDuration = persisted?.cleanupModeDuration ?? Self.defaultCleanupModeDuration
        focusEffect = persisted?.focusEffect ?? Self.defaultFocusEffect
    }

    private func save() {
        let persisted = Persisted(
            launcherHotkey: launcherHotkey,
            snipHotkey: snipHotkey,
            clipboardPinHotkey: clipboardPinHotkey,
            todoHotkey: todoHotkey,
            annotateHotkey: annotateHotkey,
            windowHotkeys: windowHotkeys,
            todoHotkeyAliases: todoHotkeyAliases,
            clipboardEnabled: clipboardEnabled,
            clipboardMaxItems: clipboardMaxItems,
            snipSaveDirectory: snipSaveDirectory,
            ocrLanguages: ocrLanguages,
            todoReminderListID: todoReminderListID,
            cleanupModeDuration: cleanupModeDuration,
            focusEffect: focusEffect
        )
        if let data = try? JSONEncoder().encode(persisted) {
            try? data.write(to: Self.file, options: .atomic)
        }
    }

    func windowHotkey(for action: WindowAction) -> HotkeySpec? {
        windowHotkeys[action.rawValue]
    }

    func setWindowHotkey(_ spec: HotkeySpec?, for action: WindowAction) {
        var updated = windowHotkeys
        updated[action.rawValue] = spec
        windowHotkeys = updated
    }
}
