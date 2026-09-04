import AppKit
import ApplicationServices
import Darwin

enum WindowActionResult: Equatable {
    case success
    case pinned
    case unpinned
    case accessibilityRequired
    case noFocusedWindow
    case unsupportedWindow
    case noRestorePosition
    case failed
}

/// 当前屏幕在 Accessibility 全局坐标系中的可用区域。
private struct WindowScreen: Equatable {
    let visibleFrame: CGRect
}

/// 通过辅助功能 API 操作其他应用的前台窗口。
final class WindowManager {
    private struct WindowIdentity: Hashable {
        let pid: pid_t
        let number: Int
    }

    private var restoreFrames: [WindowIdentity: CGRect] = [:]
    private var pinnedWindows: [WindowIdentity: CGWindowID] = [:]
    var iPhoneMirrorController: IPhoneMirrorController?

    func execute(_ action: WindowAction) -> WindowActionResult {
        guard PermissionCenter.hasAccessibility else { return .accessibilityRequired }
        guard let window = focusedWindow(), let frame = frame(of: window) else { return .noFocusedWindow }
        guard let identity = identity(of: window) else { return .unsupportedWindow }

        if action == .alwaysOnTop {
            guard let windowID = WindowPinningBridge.windowID(for: window) else { return .unsupportedWindow }
            if let app = NSRunningApplication(processIdentifier: identity.pid),
               app.bundleIdentifier == "com.apple.ScreenContinuity",
               let iPhoneMirrorController {
                let wasActive = iPhoneMirrorController.isActive
                let primaryMaxY = NSScreen.main?.frame.maxY ?? frame.maxY
                let cocoaFrame = NSRect(x: frame.minX, y: primaryMaxY - frame.maxY,
                                        width: frame.width, height: frame.height)
                iPhoneMirrorController.toggle(windowID: windowID, pid: identity.pid,
                                               frame: cocoaFrame, sourceWindow: window)
                return wasActive ? .unpinned : .pinned
            }
            if let pinnedID = pinnedWindows[identity] {
                guard WindowPinningBridge.setLevel(.normal, for: pinnedID) else { return .failed }
                pinnedWindows.removeValue(forKey: identity)
                return .unpinned
            }
            guard WindowPinningBridge.setLevel(.floating, for: windowID) else { return .failed }
            pinnedWindows[identity] = windowID
            return .pinned
        }

        if action == .restore {
            guard let previous = restoreFrames.removeValue(forKey: identity) else { return .noRestorePosition }
            return set(frame: previous, on: window) ? .success : .failed
        }

        let screens = currentScreens()
        guard let screenIndex = currentScreenIndex(for: frame, screens: screens) else { return .failed }
        let target: CGRect?
        switch action {
        case .previousDisplay:
            target = movedToAdjacentDisplay(frame, from: screenIndex, offset: -1, screens: screens)
        case .nextDisplay:
            target = movedToAdjacentDisplay(frame, from: screenIndex, offset: 1, screens: screens)
        default:
            target = WindowLayout.target(for: action, current: frame, visibleFrame: screens[screenIndex].visibleFrame)
        }
        guard let target else { return .failed }

        // 同一窗口连续排版时，只保留最初的手工位置，保证“还原”符合直觉。
        if restoreFrames[identity] == nil {
            restoreFrames[identity] = frame
        }
        return set(frame: target, on: window) ? .success : .failed
    }

    private func focusedWindow() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var appValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &appValue) == .success,
              let appValue else { return nil }
        let app = appValue as! AXUIElement
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
              let windowValue else { return nil }
        return (windowValue as! AXUIElement)
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue else { return nil }
        let positionAX = positionValue as! AXValue
        let sizeAX = sizeValue as! AXValue
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAX, .cgPoint, &position),
              AXValueGetValue(sizeAX, .cgSize, &size), size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func set(frame: CGRect, on element: AXUIElement) -> Bool {
        var position = frame.origin
        var size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return false }
        // 先改尺寸再改位置可减少部分 Electron/AppKit 窗口的跳动。
        let sizeResult = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        let positionResult = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        return sizeResult == .success && positionResult == .success
    }

    private func identity(of element: AXUIElement) -> WindowIdentity? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        // kAXWindowNumberAttribute 不是公开常量；CFHash 对同一 AX 元素在进程存活期间稳定。
        return WindowIdentity(pid: pid, number: Int(CFHash(element)))
    }

    private func currentScreens() -> [WindowScreen] {
        let primaryMaxY = NSScreen.main?.frame.maxY ?? 0
        return NSScreen.screens.map { screen in
            let visible = screen.visibleFrame
            // AX 的全局坐标原点位于主屏左上角，而 AppKit 位于左下角。
            return WindowScreen(visibleFrame: CGRect(
                x: visible.minX,
                y: primaryMaxY - visible.maxY,
                width: visible.width,
                height: visible.height
            ))
        }
        .sorted { lhs, rhs in
            lhs.visibleFrame.minX == rhs.visibleFrame.minX
                ? lhs.visibleFrame.minY < rhs.visibleFrame.minY
                : lhs.visibleFrame.minX < rhs.visibleFrame.minX
        }
    }

    private func currentScreenIndex(for frame: CGRect, screens: [WindowScreen]) -> Int? {
        screens.indices.max { lhs, rhs in
            frame.intersection(screens[lhs].visibleFrame).area < frame.intersection(screens[rhs].visibleFrame).area
        }
    }

    private func movedToAdjacentDisplay(_ frame: CGRect, from index: Int, offset: Int,
                                        screens: [WindowScreen]) -> CGRect? {
        guard screens.count > 1 else { return nil }
        let destination = (index + offset + screens.count) % screens.count
        return WindowLayout.constrained(frame, to: screens[destination].visibleFrame)
    }
}

/// 通过 SkyLight 的运行时符号调整其他应用窗口层级。系统未提供对应的公开 AX 属性，
/// 因此所有符号均为可选；在未来系统移除接口时会优雅地回退为“不支持”。
private enum WindowPinningBridge {
    private typealias ConnectionID = UInt32
    private typealias MainConnection = @convention(c) () -> ConnectionID
    private typealias SetWindowLevel = @convention(c) (ConnectionID, CGWindowID, Int32) -> Int32
    private typealias AXGetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private static let skyLightHandle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let applicationServicesHandle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY)

    private static let mainConnection: MainConnection? = symbol("CGSMainConnectionID", in: skyLightHandle)
    private static let setWindowLevel: SetWindowLevel? = symbol("CGSSetWindowLevel", in: skyLightHandle)
    private static let axGetWindow: AXGetWindow? = symbol("_AXUIElementGetWindow", in: applicationServicesHandle)

    enum Level {
        case normal
        case floating
    }

    static func windowID(for element: AXUIElement) -> CGWindowID? {
        if let axGetWindow {
            var windowID: CGWindowID = 0
            if axGetWindow(element, &windowID) == .success, windowID != 0 {
                return windowID
            }
        }

        // 新版系统可能隐藏私有 _AXUIElementGetWindow，AXWindowNumber 仍可作为回退。
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXWindowNumber" as CFString, &value) == .success,
              let number = value as? NSNumber else { return nil }
        let windowID = CGWindowID(number.uint32Value)
        return windowID == 0 ? nil : windowID
    }

    static func setLevel(_ level: Level, for windowID: CGWindowID) -> Bool {
        guard let mainConnection, let setWindowLevel else { return false }
        let key: CGWindowLevelKey = level == .floating ? .floatingWindow : .normalWindow
        let cgLevel = Int32(CGWindowLevelForKey(key))
        return setWindowLevel(mainConnection(), windowID, cgLevel) == 0
    }

    private static func symbol<T>(_ name: String, in handle: UnsafeMutableRawPointer?) -> T? {
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)
        let pointer = handle.flatMap { dlsym($0, name) } ?? dlsym(defaultHandle, name)
        guard let pointer else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}

private extension CGRect {
    var area: CGFloat { max(0, width) * max(0, height) }
}
