import AppKit

/// 管理多个贴图窗
final class PinWindowController {
    private var panels: [PinPanel] = []
    private var textPanels: [PinTextPanel] = []
    private(set) var arePinsHidden = false
    private let screenshot = ScreenshotService()
    private let selector = RegionSelector()
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// 临时切换所有贴图的可见性，窗口和内容仍保留在内存中。
    func toggleHiddenPins() {
        arePinsHidden.toggle()
        if arePinsHidden {
            panels.forEach { $0.orderOut(nil) }
            textPanels.forEach { $0.orderOut(nil) }
        } else {
            panels.forEach { $0.orderFrontRegardless() }
            textPanels.forEach { $0.orderFrontRegardless() }
        }
    }

    private func revealPinsForNewContent() {
        guard arePinsHidden else { return }
        arePinsHidden = false
        panels.forEach { $0.orderFrontRegardless() }
        textPanels.forEach { $0.orderFrontRegardless() }
    }

    /// 定格 → 框选 → 原位贴图 → 直接进入标注模式（Snipaste 流程：
    /// 截图钉在框选的位置，编辑完成才算贴图完成，全程不挪窝）
    func captureAndPin() {
        Task {
            guard screenshot.ensurePermission() else { return }
            // 先把画面定格，之后框选的都是这一刻的静态图。
            // 必须赶在遮罩上屏之前，否则会把遮罩自己定格进去
            let frozen = await screenshot.freezeAllScreens()
            guard let rect = await selector.select(frozen: frozen) else { return }
            // 直接从定格图裁，不再二次截图：既省掉等遮罩消失的 40ms 和 78ms 截图，
            // 也保证截到的就是按下热键那一刻的画面
            guard let image = frozen.crop(to: rect) else { return }
            let panel = pin(image: image, exactFrame: rect)
            // 截完就进剪贴板，不必等标注结束就能直接 ⌘V；
            // 之后若真画了标注，endAnnotation 会用最终图覆盖这一份
            panel.copyImage()
            panel.beginAnnotation()
        }
    }

    /// 演讲标注：把鼠标所在那块屏定住，直接在整屏上圈画讲解。
    /// 不框选、不落文件——讲完 Esc 抹掉就走，要翻页就退出再进
    func annotateScreen() {
        Task {
            guard screenshot.ensurePermission() else { return }
            let mouse = NSEvent.mouseLocation
            guard let target = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                    ?? NSScreen.main else { return }
            let frozen = await screenshot.freezeAllScreens()
            guard let image = frozen.crop(to: target.frame) else { return }

            let panel = pin(image: image, exactFrame: target.frame)
            // 贴图窗默认的 .floating(3) 比菜单栏(24) 和 Dock(20) 低，
            // 整屏标注得盖住它们，否则那两条会浮在定格画面之上
            panel.level = .screenSaver
            panel.beginAnnotation(dimmed: false)
        }
    }

    /// 原位贴图：窗口 frame 与截图区域完全重合
    @discardableResult
    func pin(image: NSImage, exactFrame: NSRect) -> PinPanel {
        revealPinsForNewContent()
        let panel = PinPanel(image: image, exactFrame: exactFrame, settings: settings)
        panel.onClose = { [weak self] closed in
            self?.panels.removeAll { $0 === closed }
        }
        panels.append(panel)
        panel.makeKeyAndOrderFront(nil)
        return panel
    }

    /// 剪贴板图片或文本直接贴出（会触发 macOS 26 剪贴板隐私授权）。
    func pinFromClipboard() {
        guard let content = ClipboardPinContentReader.read(from: .general) else { return }
        let location = NSEvent.mouseLocation
        switch content {
        case .image(let image):
            pin(image: image, at: location)
        case .text(let text):
            pin(text: text, at: location)
        }
    }

    @discardableResult
    func pin(image: NSImage, at location: NSPoint) -> PinPanel {
        revealPinsForNewContent()
        let panel = PinPanel(image: image, near: location, settings: settings)
        panel.onClose = { [weak self] closed in
            self?.panels.removeAll { $0 === closed }
        }
        panels.append(panel)
        panel.makeKeyAndOrderFront(nil)
        return panel
    }

    @discardableResult
    func pin(text: NSAttributedString, at location: NSPoint) -> PinTextPanel {
        revealPinsForNewContent()
        let panel = PinTextPanel(text: text, near: location)
        panel.onClose = { [weak self] closed in
            self?.textPanels.removeAll { $0 === closed }
        }
        textPanels.append(panel)
        panel.makeKeyAndOrderFront(nil)
        return panel
    }
}
