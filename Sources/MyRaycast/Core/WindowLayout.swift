import CoreGraphics

/// 不依赖 AppKit/Accessibility 的窗口布局计算，便于覆盖多显示器和不同方向的屏幕。
enum WindowLayout {
    static func target(for action: WindowAction, current: CGRect, visibleFrame: CGRect) -> CGRect? {
        let x = visibleFrame.minX
        let y = visibleFrame.minY
        let w = visibleFrame.width
        let h = visibleFrame.height

        switch action {
        case .leftHalf: return CGRect(x: x, y: y, width: w / 2, height: h)
        case .rightHalf: return CGRect(x: x + w / 2, y: y, width: w / 2, height: h)
        case .topHalf: return CGRect(x: x, y: y, width: w, height: h / 2)
        case .bottomHalf: return CGRect(x: x, y: y + h / 2, width: w, height: h / 2)
        case .topLeft: return CGRect(x: x, y: y, width: w / 2, height: h / 2)
        case .topRight: return CGRect(x: x + w / 2, y: y, width: w / 2, height: h / 2)
        case .bottomLeft: return CGRect(x: x, y: y + h / 2, width: w / 2, height: h / 2)
        case .bottomRight: return CGRect(x: x + w / 2, y: y + h / 2, width: w / 2, height: h / 2)
        case .firstThird, .centerThird, .lastThird:
            return third(for: action, in: visibleFrame)
        case .maximize:
            return visibleFrame
        case .center:
            return centered(current, in: visibleFrame)
        case .moveLeft:
            return CGRect(x: x, y: clampedY(current, in: visibleFrame), width: current.width, height: current.height)
        case .moveRight:
            return CGRect(x: x + w - current.width, y: clampedY(current, in: visibleFrame), width: current.width, height: current.height)
        case .moveUp:
            return CGRect(x: clampedX(current, in: visibleFrame), y: y, width: current.width, height: current.height)
        case .moveDown:
            return CGRect(x: clampedX(current, in: visibleFrame), y: y + h - current.height, width: current.width, height: current.height)
        case .restore, .previousDisplay, .nextDisplay:
            return nil
        case .alwaysOnTop:
            return nil
        }
    }

    static func third(for action: WindowAction, in visibleFrame: CGRect) -> CGRect {
        let index: CGFloat
        switch action {
        case .firstThird: index = 0
        case .centerThird: index = 1
        case .lastThird: index = 2
        default: return visibleFrame
        }
        // 竖屏按高度切分，横屏按宽度切分，符合 Rectangle 的方向感知行为。
        if visibleFrame.height > visibleFrame.width {
            let height = visibleFrame.height / 3
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY + height * index,
                          width: visibleFrame.width, height: height)
        }
        let width = visibleFrame.width / 3
        return CGRect(x: visibleFrame.minX + width * index, y: visibleFrame.minY,
                      width: width, height: visibleFrame.height)
    }

    static func centered(_ current: CGRect, in visibleFrame: CGRect) -> CGRect {
        let width = min(current.width, visibleFrame.width)
        let height = min(current.height, visibleFrame.height)
        return CGRect(x: visibleFrame.midX - width / 2, y: visibleFrame.midY - height / 2,
                      width: width, height: height)
    }

    static func constrained(_ current: CGRect, to visibleFrame: CGRect) -> CGRect {
        let width = min(current.width, visibleFrame.width)
        let height = min(current.height, visibleFrame.height)
        return CGRect(x: min(max(current.minX, visibleFrame.minX), visibleFrame.maxX - width),
                      y: min(max(current.minY, visibleFrame.minY), visibleFrame.maxY - height),
                      width: width, height: height)
    }

    private static func clampedX(_ rect: CGRect, in bounds: CGRect) -> CGFloat {
        min(max(rect.minX, bounds.minX), bounds.maxX - min(rect.width, bounds.width))
    }

    private static func clampedY(_ rect: CGRect, in bounds: CGRect) -> CGFloat {
        min(max(rect.minY, bounds.minY), bounds.maxY - min(rect.height, bounds.height))
    }
}
