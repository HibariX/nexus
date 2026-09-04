import AppKit

/// 标注期间铺在贴图窗下方的暗遮罩：选区之外压暗，选区本身挖空。
/// 接着框选的遮罩往下演，视觉上是「选区还留在原地继续编辑」，
/// 而不是「已经贴好图了再回头改」——去向要等标注完才选。
final class AnnotationDimming {
    private var windows: [DimmingWindow] = []

    /// hole 是挖空区域的全局 Cocoa 坐标，通常就是贴图窗的 frame
    func show(hole: NSRect) {
        guard windows.isEmpty else {
            update(hole: hole)
            return
        }
        for screen in NSScreen.screens {
            let window = DimmingWindow(screen: screen)
            window.setHole(hole)
            windows.append(window)
            window.orderFront(nil)
        }
    }

    func update(hole: NSRect) {
        for window in windows {
            window.setHole(hole)
        }
    }

    func hide() {
        for window in windows {
            window.orderOut(nil)
        }
        windows = []
    }
}

// MARK: - 单屏遮罩窗

private final class DimmingWindow: NSPanel {
    private let dimmingView = DimmingView()

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // 压在贴图窗（.floating）下面一级：盖得住普通窗口，
        // 又不会挡住正在编辑的图和它的标注工具栏
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isFloatingPanel = true
        hidesOnDeactivate = false  // app 失活时遮罩不能跟着消失
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // 吞掉点击而不是让它穿透：标注中误点遮罩不该把别的 app 切到前台
        ignoresMouseEvents = false
        contentView = dimmingView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func setHole(_ hole: NSRect) {
        dimmingView.hole = hole.offsetBy(dx: -frame.minX, dy: -frame.minY)
    }
}

private final class DimmingView: NSView {
    /// 视图本地坐标；落在别的屏幕上时与 bounds 无交集，自然什么都不挖
    var hole: NSRect = .zero {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        // 浓度与 RegionSelector 的框选遮罩一致，两段衔接时不会有明暗跳变
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()
        hole.intersection(bounds).fill(using: .clear)
    }
}
