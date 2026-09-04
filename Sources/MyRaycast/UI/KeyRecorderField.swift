import AppKit
import SwiftUI
import Carbon.HIToolbox

/// 快捷键录制控件：点击进入录制态，按下组合键即完成
struct KeyRecorderField: NSViewRepresentable {
    @Binding var spec: HotkeySpec
    var onBeginRecording: () -> Void
    var onEndRecording: () -> Void

    func makeNSView(context: Context) -> KeyRecorderView {
        let view = KeyRecorderView()
        view.spec = spec
        view.onChange = { newSpec in
            spec = newSpec
        }
        view.onBeginRecording = onBeginRecording
        view.onEndRecording = onEndRecording
        return view
    }

    func updateNSView(_ nsView: KeyRecorderView, context: Context) {
        if !nsView.isRecording {
            nsView.spec = spec
        }
    }
}

final class KeyRecorderView: NSView {
    var spec: HotkeySpec? {
        didSet { needsDisplay = true }
    }
    var onChange: ((HotkeySpec) -> Void)?
    var onBeginRecording: (() -> Void)?
    var onEndRecording: (() -> Void)?

    private(set) var isRecording = false {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 142, height: 30) }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            stopRecording()
        } else {
            window?.makeFirstResponder(self)
            isRecording = true
            onBeginRecording?()
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }
        let mods = HotkeySpec.carbonModifiers(from: event.modifierFlags)
        // 全局热键必须带修饰键，否则会劫持普通输入；F1–F20 例外，可以单独录制
        guard mods != 0 || HotkeySpec.allowsBareKey(UInt32(event.keyCode)) else {
            NSSound.beep()
            return
        }
        let newSpec = HotkeySpec(keyCode: UInt32(event.keyCode), carbonModifiers: mods)
        spec = newSpec
        onChange?(newSpec)
        stopRecording()
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { stopRecording() }
        return super.resignFirstResponder()
    }

    private func stopRecording() {
        isRecording = false
        onEndRecording?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let bg = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        (isRecording ? CyberpunkTheme.matrixNSColor.withAlphaComponent(0.18)
                     : CyberpunkTheme.surfaceNSColor).setFill()
        bg.fill()
        (isRecording ? CyberpunkTheme.matrixNSColor : CyberpunkTheme.borderNSColor).setStroke()
        bg.lineWidth = 1
        bg.stroke()

        let text = isRecording ? "按下新快捷键…" : (spec?.display ?? "点击录制")
        let attrs: [NSAttributedString.Key: Any] = [
            .font: CyberpunkTheme.monoNSFont(size: 13, weight: .medium),
            .foregroundColor: isRecording ? CyberpunkTheme.matrixBrightNSColor : CyberpunkTheme.secondaryTextNSColor,
        ]
        let size = text.size(withAttributes: attrs)
        let point = NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        text.draw(at: point, withAttributes: attrs)
    }
}
