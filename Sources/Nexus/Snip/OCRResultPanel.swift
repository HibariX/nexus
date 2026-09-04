import AppKit
import SwiftUI

/// OCR 结果浮窗：可编辑文本 + 复制。可同时存在多个，用静态数组持有避免被释放。
final class OCRResultPanel: NSPanel {
    private static var panels: [OCRResultPanel] = []

    /// 在 location 附近弹出结果窗。text 为空时显示占位提示。
    static func show(text: String, near location: NSPoint) {
        let panel = OCRResultPanel(text: text)
        panels.append(panel)

        // 定位到鼠标附近，避免超出屏幕
        let screen = NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
        var origin = NSPoint(x: location.x + 12, y: location.y - panel.frame.height - 12)
        if let vf = screen?.visibleFrame {
            origin.x = min(max(origin.x, vf.minX + 8), vf.maxX - panel.frame.width - 8)
            origin.y = min(max(origin.y, vf.minY + 8), vf.maxY - panel.frame.height - 8)
        }
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
    }

    private init(text: String) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 320),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        title = "OCR 识别结果"
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua)
        backgroundColor = CyberpunkTheme.windowNSColor
        isOpaque = false

        let root = OCRResultView(
            text: text,
            onCopy: { copied in
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(copied, forType: .string)
            },
            onClose: { [weak self] in self?.close() }
        )
        contentViewController = NSHostingController(rootView: root)
    }

    override var canBecomeKey: Bool { true }

    override func close() {
        super.close()
        Self.panels.removeAll { $0 === self }
    }
}

private struct OCRResultView: View {
    @State var text: String
    var onCopy: (String) -> Void
    var onClose: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(text.isEmpty ? "未识别到文字" : "共 \(text.count) 字，可编辑后复制")
                    .font(CyberpunkTheme.monoFont(size: 11))
                    .foregroundStyle(CyberpunkTheme.secondaryText)
                Spacer()
            }

            TextEditor(text: $text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(CyberpunkTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(CyberpunkTheme.border.opacity(0.8)))
                .frame(minHeight: 180)

            HStack {
                Spacer()
                Button("关闭", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button(copied ? "已复制" : "复制文字") {
                    onCopy(text)
                    copied = true
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.isEmpty)
            }
        }
        .padding(12)
        .frame(minWidth: 380, minHeight: 260)
        .background(CyberpunkTheme.panelBackground)
        .tint(CyberpunkTheme.matrix)
        .preferredColorScheme(.dark)
    }
}
