import AppKit
import ApplicationServices
import AVFoundation
import ScreenCaptureKit

/// iPhone Mirroring 的实时、可置顶预览。预览只负责显示；点击后交还真实窗口。
@MainActor
final class IPhoneMirrorController: NSObject, SCStreamDelegate {
    private var stream: SCStream?
    private var streamOutput: MirrorStreamOutput?
    private var panel: IPhoneMirrorPanel?
    private var sourceWindowID: CGWindowID?
    private var sourcePID: pid_t?
    private var sourceWindow: AXUIElement?
    private var startToken: UUID?
    private let sampleQueue = DispatchQueue(label: "com.hibarix.nexus.iphone-mirror.frames",
                                            qos: .userInteractive)
    var isActive: Bool { startToken != nil || panel != nil }

    func toggle(windowID: CGWindowID, pid: pid_t, frame: NSRect, sourceWindow: AXUIElement) {
        if panel != nil {
            stop()
            return
        }
        if !PermissionCenter.hasScreenCapture {
            let granted = PermissionCenter.requestScreenCapture()
            if !granted && !PermissionCenter.hasScreenCapture {
                PermissionCenter.showGuide(title: "需要屏幕录制权限",
                                           message: "iPhone 镜像预览需要屏幕录制权限。请在系统设置中允许\(PermissionCenter.appName)，授权后请重试。",
                                           openSettings: PermissionCenter.openScreenCaptureSettings)
                return
            }
        }
        sourceWindowID = windowID
        sourcePID = pid
        self.sourceWindow = sourceWindow
        let token = UUID()
        startToken = token
        Task { await start(frame: frame, token: token) }
    }

    func stop() {
        let currentStream = stream
        let currentOutput = streamOutput
        let currentPanel = panel
        stream = nil
        streamOutput = nil
        panel = nil
        startToken = nil
        sourceWindowID = nil
        sourcePID = nil
        sourceWindow = nil
        currentOutput?.stop()
        currentStream?.stopCapture()
        currentPanel?.onClose = nil
        currentPanel?.flushVideo()
        currentPanel?.close()
    }

    private func start(frame: NSRect, token: UUID) async {
        guard let sourceWindowID, let sourcePID else { return }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            NSLog("iPhone 镜像：无法读取可捕获窗口：%@", String(describing: error))
            stop()
            return
        }
        guard startToken == token else { return }
        let source = content.windows.first(where: { $0.windowID == sourceWindowID })
            ?? Self.bestWindow(in: content.windows, pid: sourcePID, matching: frame.size)
        guard let source else {
            NSLog("iPhone 镜像：找不到对应窗口，windowID=%u pid=%d", sourceWindowID, sourcePID)
            stop()
            return
        }
        let configuration = SCStreamConfiguration()
        configuration.width = max(320, Int(frame.width * 2))
        configuration.height = max(240, Int(frame.height * 2))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 3
        configuration.showsCursor = true
        let filter = SCContentFilter(desktopIndependentWindow: source)
        let mirror = IPhoneMirrorPanel(frame: frame)
        mirror.onActivateSource = { [weak self] in self?.activateSource() }
        mirror.onClose = { [weak self] in self?.stop() }
        mirror.onMove = { [weak self] frame in self?.moveSourceWindow(toMatch: frame) }
        let output = MirrorStreamOutput(displayLayer: mirror.displayLayer)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: sampleQueue)
            try await stream.startCapture()
            guard startToken == token else {
                try? await stream.stopCapture()
                return
            }
            self.stream = stream
            streamOutput = output
            panel = mirror
            mirror.orderFrontRegardless()
            NSLog("iPhone 镜像：置顶预览已启动，sourceWindowID=%u", source.windowID)
        } catch {
            NSLog("iPhone 镜像：启动捕获失败：%@", String(describing: error))
            stop()
        }
    }

    private static func bestWindow(in windows: [SCWindow], pid: pid_t, matching size: NSSize) -> SCWindow? {
        windows
            .filter { $0.owningApplication?.processID == pid && $0.frame.width > 100 && $0.frame.height > 100 }
            .min { lhs, rhs in
                abs(lhs.frame.width - size.width) + abs(lhs.frame.height - size.height)
                    < abs(rhs.frame.width - size.width) + abs(rhs.frame.height - size.height)
            }
    }

    private func activateSource() {
        guard let sourcePID else { return }
        panel?.orderOut(nil)
        NSRunningApplication(processIdentifier: sourcePID)?.activate(options: [])
        stop()
    }

    private func moveSourceWindow(toMatch mirrorFrame: NSRect) {
        guard let sourceWindow else { return }
        let primaryMaxY = NSScreen.main?.frame.maxY ?? mirrorFrame.maxY
        var position = CGPoint(x: mirrorFrame.minX, y: primaryMaxY - mirrorFrame.maxY)
        guard let value = AXValueCreate(.cgPoint, &position) else { return }
        let result = AXUIElementSetAttributeValue(sourceWindow, kAXPositionAttribute as CFString, value)
        if result != .success {
            NSLog("iPhone 镜像：同步真实窗口位置失败，AXError=%d", result.rawValue)
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let message = String(describing: error)
        Task { @MainActor [weak self] in
            NSLog("iPhone 镜像：捕获已停止：%@", message)
            self?.stop()
        }
    }
}

private nonisolated final class MirrorStreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let renderer: AVSampleBufferVideoRenderer
    private let stateLock = NSLock()
    private var stopped = false

    init(displayLayer: AVSampleBufferDisplayLayer) {
        renderer = displayLayer.sampleBufferRenderer
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        stateLock.lock()
        let shouldStop = stopped
        stateLock.unlock()
        guard !shouldStop, outputType == .screen, sampleBuffer.isValid,
              renderer.isReadyForMoreMediaData else { return }
        renderer.enqueue(sampleBuffer)
    }

    func stop() {
        stateLock.lock()
        stopped = true
        stateLock.unlock()
    }
}

@MainActor
private final class IPhoneMirrorPanel: NSPanel {
    var onActivateSource: (() -> Void)?
    var onClose: (() -> Void)?
    var onMove: ((NSRect) -> Void)?
    private let mirrorView = IPhoneMirrorSurfaceView()
    var displayLayer: AVSampleBufferDisplayLayer { mirrorView.displayLayer }

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        isReleasedWhenClosed = false
        backgroundColor = .black
        hasShadow = true
        mirrorView.autoresizingMask = [.width, .height]
        mirrorView.frame = contentView?.bounds ?? .zero
        mirrorView.onClick = { [weak self] in self?.onActivateSource?() }
        mirrorView.onMove = { [weak self] in
            guard let self else { return }
            self.onMove?(self.frame)
        }
        contentView = mirrorView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func flushVideo() {
        displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
    }

    override func close() {
        onClose?()
        super.close()
    }
}

@MainActor
private final class IPhoneMirrorSurfaceView: NSView {
    var onClick: (() -> Void)?
    var onMove: (() -> Void)?
    let displayLayer = AVSampleBufferDisplayLayer()
    private var mouseDownScreenPoint: NSPoint?
    private var mouseDownWindowOrigin: NSPoint?
    private var isDraggingWindow = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(displayLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        displayLayer.frame = bounds
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        mouseDownScreenPoint = NSEvent.mouseLocation
        mouseDownWindowOrigin = window.frame.origin
        isDraggingWindow = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let start = mouseDownScreenPoint, let origin = mouseDownWindowOrigin else { return }
        let current = NSEvent.mouseLocation
        if MirrorPointerGesture.isDrag(from: start, to: current) {
            isDraggingWindow = true
        }
        guard isDraggingWindow else { return }
        window.setFrameOrigin(MirrorPointerGesture.windowOrigin(from: origin, mouseStart: start, mouseNow: current))
        onMove?()
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownScreenPoint = nil
            mouseDownWindowOrigin = nil
            isDraggingWindow = false
        }
        if !isDraggingWindow {
            onClick?()
        }
    }
}

enum MirrorPointerGesture {
    static let dragThreshold: CGFloat = 3

    static func isDrag(from start: NSPoint, to current: NSPoint) -> Bool {
        hypot(current.x - start.x, current.y - start.y) >= dragThreshold
    }

    static func windowOrigin(from origin: NSPoint, mouseStart: NSPoint, mouseNow: NSPoint) -> NSPoint {
        NSPoint(x: origin.x + mouseNow.x - mouseStart.x,
                y: origin.y + mouseNow.y - mouseStart.y)
    }
}
