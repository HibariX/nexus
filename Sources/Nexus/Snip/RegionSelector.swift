import AppKit

/// 自绘全屏框选：替代 `screencapture -i`，这样能拿到选区的精确屏幕坐标，
/// 贴图才能钉在框选的原位。每个屏幕铺一个遮罩窗，拖拽画选区，
/// 不拖直接单击则截取光标下的整个窗口，Esc 取消。
///
/// 遮罩铺的是**定格画面**而不是活的屏幕：按下热键那一刻就已经截好了，
/// 框选期间画面不再变化，一闪而过的 tooltip、动画、下拉菜单才截得到。
/// 框完直接从定格图里裁，不需要二次截图。
final class RegionSelector {
    private var windows: [SelectorWindow] = []
    private var continuation: CheckedContinuation<NSRect?, Never>?

    /// 返回选区的全局 Cocoa 坐标（左下原点），取消返回 nil。
    /// frozen 必须是遮罩上屏之前抓的，否则会把遮罩自己定格进去
    func select(frozen: [FrozenScreen]) async -> NSRect? {
        guard windows.isEmpty else { return nil }
        // 同样必须赶在遮罩窗上屏之前，否则遮罩窗自己就是最前面那个「窗口」
        let snapshot = WindowSnapshot.capture()
        return await withCheckedContinuation { cont in
            continuation = cont
            for screen in NSScreen.screens {
                let window = SelectorWindow(
                    screen: screen,
                    snapshot: snapshot,
                    // 找不到对应定格图时留空，退化成半透明遮罩，功能不受影响
                    frozen: frozen.first { $0.frame == screen.frame }?.image
                )
                window.onFinish = { [weak self] rect in self?.finish(rect) }
                window.onOverlayChange = { [weak self] overlay in self?.broadcast(overlay) }
                windows.append(window)
                window.makeKeyAndOrderFront(nil)
            }
            // 遮罩铺好就按当前光标位置高亮一次，鼠标不动也能直接单击选窗
            broadcast(snapshot.window(at: NSEvent.mouseLocation).map(OverlaySelection.window) ?? .none)
        }
    }

    /// 高亮区域可能跨屏，每块遮罩窗各画自己那一段，所以状态要广播给全部
    private func broadcast(_ overlay: OverlaySelection) {
        for window in windows {
            window.setOverlay(overlay)
        }
    }

    private func finish(_ rect: NSRect?) {
        guard continuation != nil else { return }
        for window in windows {
            window.orderOut(nil)
        }
        windows = []
        continuation?.resume(returning: rect)
        continuation = nil
    }
}

// MARK: - 遮罩上要画的高亮区域

/// 全局 Cocoa 坐标。所有遮罩窗共享同一份，跨屏时各画各的一段
enum OverlaySelection: Equatable {
    case none
    /// 悬停命中的整窗
    case window(NSRect)
    /// 手动拖出来的选区
    case dragged(NSRect)

    var rect: NSRect? {
        switch self {
        case .none: return nil
        case .window(let rect), .dragged(let rect): return rect
        }
    }
}

// MARK: - 遮罩窗

private final class SelectorWindow: NSPanel {
    var onFinish: ((NSRect?) -> Void)?
    var onOverlayChange: ((OverlaySelection) -> Void)?

    private let selectorView: SelectorView

    init(screen: NSScreen, snapshot: WindowSnapshot, frozen: CGImage?) {
        let bounds = NSRect(origin: .zero, size: screen.frame.size)
        selectorView = SelectorView(frame: bounds, snapshot: snapshot)
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver  // 盖住一切，包括其他浮窗
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true

        selectorView.onFinish = { [weak self] rect in self?.onFinish?(rect) }
        selectorView.onOverlayChange = { [weak self] overlay in self?.onOverlayChange?(overlay) }

        // 定格图交给 layer 做 GPU 合成：鼠标一动 SelectorView 就要重绘，
        // 每帧再画一遍这张全屏位图太亏。SelectorView 铺在它上面，
        // 挖洞用 .clear，露出来的就是下面这张定格图
        let backdrop = NSView(frame: bounds)
        backdrop.wantsLayer = true
        backdrop.layer?.contents = frozen
        backdrop.layer?.contentsGravity = .resize
        backdrop.autoresizingMask = [.width, .height]
        selectorView.autoresizingMask = [.width, .height]
        backdrop.addSubview(selectorView)
        contentView = backdrop
    }

    func setOverlay(_ overlay: OverlaySelection) {
        selectorView.setOverlay(overlay)
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onFinish?(nil)
    }
}

// MARK: - 选区绘制视图

private final class SelectorView: NSView {
    var onFinish: ((NSRect?) -> Void)?
    var onOverlayChange: ((OverlaySelection) -> Void)?

    private let snapshot: WindowSnapshot

    /// 以下坐标全部是全局 Cocoa 坐标，只有 draw 里才换算成视图本地坐标。
    /// 窗口 frame 天生是全局的，统一到全局能少两道来回转换
    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?
    /// 拖动超过阈值才算自由框选，在此之前仍停在选窗模式
    private var isFreeSelecting = false
    private var overlay: OverlaySelection = .none

    /// 手抖一两像素不该丢掉窗口高亮
    private static let dragThreshold: CGFloat = 3
    /// 拖出的选区太小视为误触
    private static let minimumSelectionSide: CGFloat = 4

    init(frame: NSRect, snapshot: WindowSnapshot) {
        self.snapshot = snapshot
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var draggedRect: NSRect? {
        guard let start = dragStart, let current = dragCurrent else { return nil }
        return NSRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(current.x - start.x), height: abs(current.y - start.y))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
        NSCursor.crosshair.set()
    }

    // 遮罩窗是 nonactivatingPanel，光靠 key window 的事件流拿不稳 mouseMoved，
    // 用 activeAlways 的 tracking area 兜底
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    /// 外部广播来的状态：只更新自己，不再往回喊，否则会绕成死循环
    func setOverlay(_ new: OverlaySelection) {
        guard new != overlay else { return }
        overlay = new
        needsDisplay = true
    }

    private func changeOverlay(_ new: OverlaySelection) {
        guard new != overlay else { return }
        setOverlay(new)
        onOverlayChange?(new)
    }

    override func mouseMoved(with event: NSEvent) {
        guard !isFreeSelecting else { return }
        changeOverlay(snapshot.window(at: NSEvent.mouseLocation).map(OverlaySelection.window) ?? .none)
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        dragCurrent = dragStart
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = NSEvent.mouseLocation
        if !isFreeSelecting, let start = dragStart, let current = dragCurrent,
           abs(current.x - start.x) >= Self.dragThreshold || abs(current.y - start.y) >= Self.dragThreshold {
            isFreeSelecting = true
        }
        guard isFreeSelecting, let rect = draggedRect else { return }
        changeOverlay(.dragged(rect))
    }

    override func mouseUp(with event: NSEvent) {
        dragCurrent = NSEvent.mouseLocation
        defer {
            dragStart = nil
            dragCurrent = nil
        }
        guard isFreeSelecting else {
            // 没拖动，截取光标下的整窗；落在桌面空白处则当作取消
            onFinish?(overlay.rect)
            return
        }
        if let rect = draggedRect,
           rect.width >= Self.minimumSelectionSide, rect.height >= Self.minimumSelectionSide {
            onFinish?(rect)
        } else {
            onFinish?(nil)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {  // Esc
            onFinish?(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // 半透明遮罩
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()

        switch overlay {
        case .none:
            drawHint()
        case .window(let rect):
            // 用强调色和手动选区区分开，让人一眼看出这是「整窗」
            drawSelection(rect, color: CyberpunkTheme.matrixNSColor)
        case .dragged(let rect):
            drawSelection(rect, color: .white)
        }
    }

    /// globalRect 是全局坐标，这里转成本地绘制；跨屏时每块屏各画自己那一段
    private func drawSelection(_ globalRect: NSRect, color: NSColor) {
        let origin = window?.frame.origin ?? .zero
        let rect = globalRect.offsetBy(dx: -origin.x, dy: -origin.y)
        guard rect.intersects(bounds) else { return }

        // 选区挖洞（透出原屏内容）
        rect.fill(using: .clear)

        let border = NSBezierPath(rect: rect)
        border.lineWidth = 2
        color.setStroke()
        border.stroke()

        // 尺寸标签按整体尺寸显示，跨屏时两块屏上是同一个数
        let label = "\(Int(globalRect.width)) × \(Int(globalRect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: CyberpunkTheme.matrixBrightNSColor,
        ]
        let size = label.size(withAttributes: attrs)
        var labelOrigin = NSPoint(x: rect.minX, y: rect.maxY + 6)
        if labelOrigin.y + size.height > bounds.maxY {
            labelOrigin.y = rect.maxY - size.height - 6
        }
        let padding: CGFloat = 5
        let bg = NSRect(x: labelOrigin.x - padding, y: labelOrigin.y - 3,
                        width: size.width + padding * 2, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 4, yRadius: 4).fill()
        label.draw(at: labelOrigin, withAttributes: attrs)
    }

    private func drawHint() {
        let hint = "拖拽框选 · 单击截取整个窗口 · Esc 取消"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: CyberpunkTheme.matrixBrightNSColor.withAlphaComponent(0.9),
        ]
        let size = hint.size(withAttributes: attrs)
        let origin = NSPoint(x: bounds.midX - size.width / 2, y: bounds.maxY - 120)
        let padding: CGFloat = 10
        let bg = NSRect(x: origin.x - padding, y: origin.y - 6,
                        width: size.width + padding * 2, height: size.height + 12)
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 6, yRadius: 6).fill()
        hint.draw(at: origin, withAttributes: attrs)
    }
}
