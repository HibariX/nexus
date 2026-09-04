import AppKit
import Carbon.HIToolbox
import CoreFoundation
import CoreGraphics
import Observation

/// 清理模式（擦拭屏幕/键盘时防误触）的核心控制器。
///
/// 职责拆成两块：
/// - 输入屏蔽：全屏遮罩窗（视觉 + 吞鼠标 + 接收 Esc）+ 全局 CGEventTap（真正屏蔽键鼠/系统热键）。
/// - 状态机：idle → active(倒计时) → 恢复。进入创建资源，退出销毁，避免重复触发/并发。
///
/// tap 只在该次清理期间存在（进入创建 / 退出销毁），回调只做「消费/放行」的纯判断，
/// 不读 @MainActor 状态 —— 天然无并发与卡键问题。
@Observable
final class CleanupModeController {
    // MARK: - 状态（provider 直接读）

    private(set) var phase: CleanupMode.Phase = .idle
    var isActive: Bool {
        if case .active = phase { return true }
        return false
    }

    // MARK: - 注入（AppDelegate 接线）

    /// 时长提供者，设置变化实时生效；测试可注入固定值。默认 60 秒。
    var durationProvider: (() -> Int)? = { 60 }
    /// 进入/退出时挂起/恢复全局热键（作为 tap 失效时的兜底）。
    var suspendHotkeys: (() -> Void)?
    var resumeHotkeys: (() -> Void)?

    // MARK: - 私有资源

    private var masks: [CleanupMaskWindow] = []
    private var deadline: Date?
    private var timer: Timer?
    private var tapPort: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var tapContext: CleanupTapContext?
    private var modifiersAtStart: CGEventFlags = []
    private var totalDuration: Double = 60

    private func durationSeconds() -> Double {
        Double(max(1, durationProvider?() ?? 60))
    }

    // MARK: - 对外入口

    /// 面板命令入口：进入/退出切换。「已激活则退出」作为极端兜底（面板此时已被遮罩盖住，正常无法触发）。
    func toggle() {
        isActive ? exit() : start()
    }

    func start() {
        guard !isActive else { return }
        totalDuration = durationSeconds()

        // 辅助功能权限：缺失则引导，无论成败都降级为「纯遮罩」（吞鼠标点击，但不屏蔽系统级快捷键）。
        if !PermissionCenter.hasAccessibility {
            PermissionCenter.requestAccessibility()
            PermissionCenter.showGuide(
                title: "需要辅助功能权限",
                message: "清理模式需要「辅助功能」权限来临时屏蔽键盘与鼠标输入。\n\n若不授权，仍可启动纯遮罩模式：鼠标无法点击，但系统级快捷键（如 ⌥空格）不会被屏蔽。",
                openSettings: PermissionCenter.openAccessibilitySettings
            )
        }
        let canBlockKeys = PermissionCenter.hasAccessibility  // 引导后再判一次

        // 记录启动瞬间按住的修饰键：清理中途松开会被吞，退出时补发 keyUp 复位（防卡键）。
        modifiersAtStart = CGEventSource.flagsState(.combinedSessionState)

        installMasks()
        if canBlockKeys { installTap() }
        suspendHotkeys?()
        scheduleCountdown()
        phase = .active(remaining: totalDuration)
    }

    func exit() {
        guard isActive else { return }
        cancelCountdown()
        tearDownTap()
        destroyMasks()
        resumeHotkeys?()
        releaseModifiersIfHeld()
        phase = .idle
    }

    // MARK: - 遮罩窗（每屏一个）

    private func installMasks() {
        destroyMasks()
        var keyTarget: CleanupMaskWindow?
        for screen in NSScreen.screens {
            let window = CleanupMaskWindow(screen: screen)
            window.onExit = { [weak self] in self?.exit() }
            window.setCountdown(remaining: totalDuration, total: totalDuration)
            masks.append(window)
            window.orderFront(nil)
            // 鼠标所在的那块屏成为 key，保证 Esc 能进到遮罩窗（nonactivating panel 可成 key）
            if NSMouseInRect(NSEvent.mouseLocation, screen.frame, false) { keyTarget = window }
        }
        (keyTarget ?? masks.first)?.makeKeyAndOrderFront(nil)
    }

    private func destroyMasks() {
        for window in masks { window.orderOut(nil) }
        masks = []
    }

    // MARK: - 倒计时

    private func scheduleCountdown() {
        deadline = Date().addingTimeInterval(totalDuration)
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer
        // 挂 common modes：模态 runloop（如 NSAlert）期间也走
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelCountdown() {
        timer?.invalidate()
        timer = nil
        deadline = nil
    }

    private func tick() {
        guard let deadline else { return }
        let remaining = max(0, deadline.timeIntervalSinceNow)
        phase = .active(remaining: remaining)
        for window in masks { window.setCountdown(remaining: remaining, total: totalDuration) }
        if remaining <= 0 {
            exit()
        }
    }

    // MARK: - CGEventTap（真正屏蔽输入）

    private func installTap() {
        let context = CleanupTapContext(port: nil)
        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap,          // 最低层：能挡住包括系统全局快捷键在内的所有输入
            place: .headInsertEventTap,   // 抢占最前，先于其它 tap
            options: .defaultTap,         // 非 listenOnly：回调返回 nil 即真正阻断
            eventsOfInterest: CleanupMode.cleanupEventMask,
            callback: cleanupTapCallback,
            userInfo: Unmanaged.passUnretained(context).toOpaque()
        ) else {
            tapContext = nil              // 授权刚被撤/创建失败 → 退化为纯遮罩，靠倒计时兜底
            return
        }
        context.port = port
        tapPort = port
        tapContext = context

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            tapPort = nil
            tapContext = nil
            return
        }
        tapSource = source
        // 挂到主 runloop 的 common modes：app 是常驻菜单栏应用，主 loop 一直在跑
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private func tearDownTap() {
        if let source = tapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let port = tapPort {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        tapPort = nil
        tapSource = nil
        tapContext = nil
    }

    // MARK: - 修饰键复位（best-effort）

    /// 启动瞬间若已按住某修饰键、清理中途松开，其 flagsChanged/keyUp 会被吞，导致前台 app 「卡键」。
    /// 退出时对被按住的修饰键补发一次合成 keyUp 复位。
    private func releaseModifiersIfHeld() {
        guard PermissionCenter.hasAccessibility, !modifiersAtStart.isEmpty else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let held: [(CGEventFlags, UInt32)] = [
            (.maskCommand, UInt32(kVK_Command)),
            (.maskAlternate, UInt32(kVK_Option)),
            (.maskControl, UInt32(kVK_Control)),
            (.maskShift, UInt32(kVK_Shift)),
        ]
        for (flag, keyCode) in held where modifiersAtStart.contains(flag) {
            CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: false)?
                .post(tap: .cghidEventTap)
        }
        modifiersAtStart = []
    }
}

// MARK: - 事件 tap 回调

/// 事件 tap 回调只读的上下文。仅存 CFMachPort，且所有访问都在主线程
/// （回调与 timer 都挂主 runloop），故 @unchecked 安全。
private final class CleanupTapContext: @unchecked Sendable {
    var port: CFMachPort?
    init(port: CFMachPort? = nil) { self.port = port }
}

/// C 函数指针回调：不捕获任何非 Sendable，仅调静态纯函数与系统 API。
private let cleanupTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    // 系统出于 Secure Input / 用户输入而禁用了 tap：尝试恢复（恢复失败则 tap 静默失效，退化为纯遮罩）
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let ctx = userInfo.map({ Unmanaged<CleanupTapContext>.fromOpaque($0).takeUnretainedValue() }),
           let port = ctx.port {
            CGEvent.tapEnable(tap: port, enable: true)
        }
        return nil
    }

    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    if CleanupMode.shouldConsume(type: type, keyCode: keyCode) {
        return nil                  // 吞掉：真正阻断
    }
    // 仅 Esc 走到这儿：放行，交给遮罩窗的 keyDown 触发 exit() 手动恢复
    return Unmanaged.passUnretained(event)
}

// MARK: - 全屏遮罩窗（视觉 + 吞鼠标 + 接收 Esc）

private final class CleanupMaskWindow: NSPanel {
    var onExit: (() -> Void)?
    private let maskView = CleanupMaskView()

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver                      // 盖住一切，包括其他浮窗与全屏 app
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false               // 吞点击，不穿透
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false                 // app 失活时遮罩不能跟着消失
        appearance = NSAppearance(named: .darkAqua)
        maskView.onExit = { [weak self] in self?.onExit?() }
        contentView = maskView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { true }

    /// Esc 走 responder chain 的 cancelOperation 也视为「按下」，进入长按 3 秒逻辑
    override func cancelOperation(_ sender: Any?) {
        maskView.beginEscapeHold()
    }

    func setCountdown(remaining: Double, total: Double) {
        maskView.updateCountdown(remaining: remaining, total: total)
    }
}

private final class CleanupMaskView: NSView {
    var onExit: (() -> Void)?
    private var remaining: Double = 0
    private var total: Double = 1
    /// Esc 长按开始时间：nil 表示当前未按住 Esc。长按满 3 秒才退出，中途松开取消。
    private var escHoldStartedAt: Date?
    private var holdExitRequested = false

    func updateCountdown(remaining: Double, total: Double) {
        self.remaining = remaining
        self.total = max(1, total)
        needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 吞掉所有 key equivalent（⌘Q/⌘W/⌘H…），Esc 例外放行到 keyDown 处理长按退出。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, event.keyCode == CleanupMode.escapeKeyCode { return false }
        return true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == CleanupMode.escapeKeyCode {
            beginEscapeHold()
        }
        // 其余按键也吞掉（tap 已挡，此处是降级/无 tap 时的兜底）
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == CleanupMode.escapeKeyCode {
            // 松开 Esc：取消长按（未满 3 秒不退出）
            escHoldStartedAt = nil
            holdExitRequested = false
            needsDisplay = true
        }
    }

    override func cancelOperation(_ sender: Any?) {
        // responder chain 兜底：Esc 也视为「按下」
        beginEscapeHold()
    }

    /// 进入 Esc 长按态（若尚未开始）。重复的 Escape 自动重复 keyDown 不会重置计时。
    func beginEscapeHold() {
        if escHoldStartedAt == nil {
            escHoldStartedAt = Date()
            holdExitRequested = false
        }
        needsDisplay = true
    }

    // 吞掉所有鼠标事件（降级路径兜底；有 tap 时 tap 在更高层就已拦截）
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func otherMouseUp(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}

    override func draw(_ dirtyRect: NSRect) {
        // 冷灰蓝夜空底（带一点点通透，营造「模式中」的氛围）
        CyberpunkTheme.windowNSColor.withAlphaComponent(0.92).setFill()
        bounds.fill()

        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius: CGFloat = min(bounds.width, bounds.height) / 5

        // 倒计时圆环：从顶部顺时针收拢
        let progress = CGFloat(min(max(remaining / total, 0), 1))
        let ringPath = NSBezierPath()
        ringPath.appendArc(withCenter: center, radius: radius,
                           startAngle: 90, endAngle: 90 - 360 * progress, clockwise: true)
        ringPath.lineWidth = 6
        CyberpunkTheme.matrixNSColor.setStroke()
        ringPath.stroke()

        let secs = Int(max(0, remaining).rounded(.up))
        let title = "擦拭中"

        // 长按 Esc 进度：满 3 秒则触发退出（draw 由倒计时 timer 每 0.1s 触发，逐帧刷新进度）
        let holdElapsed = escHoldStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        if escHoldStartedAt != nil, !holdExitRequested, holdElapsed >= CleanupMode.escHoldDuration {
            holdExitRequested = true
            // 不直接在 draw 里销毁窗口（TearDown 会重建视图树），延后到下一轮 runloop。
            // DispatchQueue.main.async 的闭包不在 @MainActor 隔离区，编译器无法证明，用 assumeIsolated 兜底
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.onExit?() }
            }
        }

        let sub: String
        if escHoldStartedAt != nil {
            sub = CleanupMode.holdSubtitle(elapsed: holdElapsed)
        } else {
            sub = "按住 Esc 3 秒退出 · 剩余 \(secs)s"
        }

        (title as NSString).draw(
            at: NSPoint(x: center.x - title.size(withAttributes: [.font: CyberpunkTheme.monoNSFont(size: 34, weight: .bold)]).width / 2, y: center.y + 14),
            withAttributes: [
                .font: CyberpunkTheme.monoNSFont(size: 34, weight: .bold),
                .foregroundColor: CyberpunkTheme.textNSColor,
            ]
        )
        (sub as NSString).draw(
            at: NSPoint(x: center.x - sub.size(withAttributes: [.font: CyberpunkTheme.monoNSFont(size: 14)]).width / 2, y: center.y - 34),
            withAttributes: [
                .font: CyberpunkTheme.monoNSFont(size: 14),
                .foregroundColor: CyberpunkTheme.secondaryTextNSColor,
            ]
        )

        // 按住 Esc 时画一条长按进度条（满格即退出）
        if escHoldStartedAt != nil {
            drawHoldProgress(CleanupMode.holdProgress(holdElapsed), centerY: center.y - 60)
        }
    }

    private func drawHoldProgress(_ percent: Double, centerY: CGFloat) {
        let barWidth: CGFloat = min(bounds.width * 0.4, 280)
        let barHeight: CGFloat = 5
        let originX = bounds.midX - barWidth / 2
        let rect = NSRect(x: originX, y: centerY, width: barWidth, height: barHeight)
        let bg = NSBezierPath(roundedRect: rect, xRadius: barHeight / 2, yRadius: barHeight / 2)
        CyberpunkTheme.borderNSColor.withAlphaComponent(0.6).setFill()
        bg.fill()

        let fillRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width * CGFloat(percent), height: rect.height)
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: barHeight / 2, yRadius: barHeight / 2)
        CyberpunkTheme.matrixNSColor.setFill()
        fill.fill()
    }
}
