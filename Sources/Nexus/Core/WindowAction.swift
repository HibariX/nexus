import AppKit
import Carbon.HIToolbox

/// Nexus 首版支持的常用窗口操作。rawValue 与 Rectangle 的偏好键保持一致，便于导入。
enum WindowAction: String, CaseIterable, Codable, Identifiable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case firstThird, centerThird, lastThird
    case maximize, center, restore, alwaysOnTop
    case previousDisplay, nextDisplay
    case moveLeft, moveRight, moveUp, moveDown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftHalf: return "左半屏"
        case .rightHalf: return "右半屏"
        case .topHalf: return "上半屏"
        case .bottomHalf: return "下半屏"
        case .topLeft: return "左上角"
        case .topRight: return "右上角"
        case .bottomLeft: return "左下角"
        case .bottomRight: return "右下角"
        case .firstThird: return "首个三分屏"
        case .centerThird: return "中间三分屏"
        case .lastThird: return "末个三分屏"
        case .maximize: return "最大化"
        case .center: return "居中"
        case .restore: return "还原窗口"
        case .previousDisplay: return "移到上一显示器"
        case .nextDisplay: return "移到下一显示器"
        case .moveLeft: return "移到左边缘"
        case .moveRight: return "移到右边缘"
        case .moveUp: return "移到上边缘"
        case .moveDown: return "移到下边缘"
        case .alwaysOnTop: return "切换窗口置顶"
        }
    }

    var section: String {
        switch self {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf: return "半屏"
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return "四角"
        case .firstThird, .centerThird, .lastThird: return "三分屏"
        case .maximize, .center, .restore, .alwaysOnTop: return "窗口"
        case .previousDisplay, .nextDisplay: return "显示器"
        case .moveLeft, .moveRight, .moveUp, .moveDown: return "仅移动"
        }
    }

    /// Rectangle 已启用的 alternateDefaultShortcuts（Magnet）方案。
    var alternateDefaultHotkey: HotkeySpec? {
        let mods = UInt32(controlKey | optionKey)
        switch self {
        case .leftHalf: return .init(keyCode: UInt32(kVK_LeftArrow), carbonModifiers: mods)
        case .rightHalf: return .init(keyCode: UInt32(kVK_RightArrow), carbonModifiers: mods)
        case .topHalf: return .init(keyCode: UInt32(kVK_UpArrow), carbonModifiers: mods)
        case .bottomHalf: return .init(keyCode: UInt32(kVK_DownArrow), carbonModifiers: mods)
        case .topLeft: return .init(keyCode: UInt32(kVK_ANSI_U), carbonModifiers: mods)
        case .topRight: return .init(keyCode: UInt32(kVK_ANSI_I), carbonModifiers: mods)
        case .bottomLeft: return .init(keyCode: UInt32(kVK_ANSI_J), carbonModifiers: mods)
        case .bottomRight: return .init(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: mods)
        case .firstThird: return .init(keyCode: UInt32(kVK_ANSI_D), carbonModifiers: mods)
        case .centerThird: return .init(keyCode: UInt32(kVK_ANSI_F), carbonModifiers: mods)
        case .lastThird: return .init(keyCode: UInt32(kVK_ANSI_G), carbonModifiers: mods)
        case .maximize: return .init(keyCode: UInt32(kVK_Return), carbonModifiers: mods)
        case .center: return .init(keyCode: UInt32(kVK_ANSI_C), carbonModifiers: mods)
        case .restore: return .init(keyCode: UInt32(kVK_Delete), carbonModifiers: mods)
        case .previousDisplay:
            return .init(keyCode: UInt32(kVK_LeftArrow), carbonModifiers: mods | UInt32(cmdKey))
        case .nextDisplay:
            return .init(keyCode: UInt32(kVK_RightArrow), carbonModifiers: mods | UInt32(cmdKey))
        case .moveLeft, .moveRight, .moveUp, .moveDown:
            return nil
        case .alwaysOnTop:
            return nil
        }
    }

    static var alternateDefaults: [String: HotkeySpec] {
        Dictionary(uniqueKeysWithValues: allCases.compactMap { action in
            action.alternateDefaultHotkey.map { (action.rawValue, $0) }
        })
    }
}
