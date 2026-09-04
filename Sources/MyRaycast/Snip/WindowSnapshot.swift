import AppKit

/// 框选开始那一刻冻结的屏上窗口列表，用于「悬停高亮整窗」。
/// 冻结而不是每次鼠标移动实时查询：遮罩窗盖住全屏后 z-order 不会再变，
/// 实时调 CGWindowListCopyWindowInfo 只是白白耗时。
struct WindowSnapshot {
    /// 全局 Cocoa 坐标（左下原点），按 z-order 从前到后
    private let frames: [NSRect]

    static let empty = WindowSnapshot(frames: [])

    /// 太小的窗口没有框选价值，多半是 1×1 的隐形辅助窗
    private static let minimumSide: CGFloat = 20

    /// Dock 的窗口 bounds 是**整块屏幕**（那片空间留给自动隐藏和放大动画），
    /// 而它的层级又高过所有普通窗口——照搬 bounds 的话，光标落在屏幕任何位置
    /// 都会先命中 Dock，永远只高亮全屏。这里用 visibleFrame 反推它真正占的那一条。
    /// 返回 nil 表示这块屏上没有 Dock（在别的屏，或开了自动隐藏）。
    private static func dockRect(on screen: NSScreen) -> NSRect? {
        let frame = screen.frame
        let visible = screen.visibleFrame
        let tolerance: CGFloat = 1
        if visible.minY - frame.minY > tolerance {  // 底部
            return NSRect(x: frame.minX, y: frame.minY,
                          width: frame.width, height: visible.minY - frame.minY)
        }
        if visible.minX - frame.minX > tolerance {  // 左侧
            return NSRect(x: frame.minX, y: frame.minY,
                          width: visible.minX - frame.minX, height: frame.height)
        }
        if frame.maxX - visible.maxX > tolerance {  // 右侧
            return NSRect(x: visible.maxX, y: frame.minY,
                          width: frame.maxX - visible.maxX, height: frame.height)
        }
        return nil
    }

    /// 必须赶在遮罩窗上屏之前调用：遮罩窗一旦显示就会排在列表最前面，
    /// 之后光标落在哪里都只会命中它。也正因为抓得早，不必按 pid 排除自己，
    /// 已经钉在屏幕上的贴图窗反而可以被正常框选。
    static func capture() -> WindowSnapshot {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first else {
            return .empty
        }
        // CG 以主屏左上角为原点、y 向下，Cocoa 以左下角为原点、y 向上。
        // 这里的翻转与 ScreenshotService.capture(rect:) 里的换算互为逆运算
        let flipHeight = primary.frame.maxY
        let screens = NSScreen.screens
        // 窗口可能有一截在屏幕外，不裁掉的话 screencapture -R 会在那一侧截出黑边
        let screenBounds = screens.dropFirst().reduce(screens[0].frame) { $0.union($1.frame) }
        let dockLayer = Int(CGWindowLevelForKey(.dockWindow))
        let cursorLayer = Int(CGWindowLevelForKey(.cursorWindow))

        let frames = list.compactMap { info -> NSRect? in
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let cgRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                return nil
            }
            // 完全透明的窗口在屏幕上看不见，高亮它只会让人困惑
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0 else { return nil }

            var rect = NSRect(x: cgRect.minX, y: flipHeight - cgRect.maxY,
                              width: cgRect.width, height: cgRect.height)

            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            // 鼠标光标自己也是一个窗口（Window Server/Cursor，28x40 左右），
            // 层级是所有窗口里最高的。不排掉的话它永远排在 z-order 第一，
            // 鼠标移到哪就高亮那一小块，底下真正的窗口一个也选不中
            guard layer < cursorLayer else { return nil }

            // 铺满整块屏幕、层级又在 Dock 之上的，都是给动画和背景用的容器窗口
            // （Dock 本体、Window Server 的 Backstop Menubar 等）。留着它们，
            // 后面所有普通窗口都会被挡住，一个也选不中
            if layer >= dockLayer, let screen = screens.first(where: { $0.frame == rect }) {
                // 只有 Dock 值得救回来，换成它真正占的那一条；其余直接丢弃
                guard layer == dockLayer, let dock = dockRect(on: screen) else { return nil }
                rect = dock
            }

            let clipped = rect.intersection(screenBounds)
            guard clipped.width >= minimumSide, clipped.height >= minimumSide else { return nil }
            return clipped
        }
        return WindowSnapshot(frames: frames)
    }

    /// 光标下最靠前的窗口，全局 Cocoa 坐标；落在桌面空白处返回 nil
    func window(at point: NSPoint) -> NSRect? {
        frames.first { $0.contains(point) }
    }
}
