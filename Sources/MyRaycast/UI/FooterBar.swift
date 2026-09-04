import SwiftUI

struct FooterBar: View {
    var isWorkbench: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Label("MyRaycast", systemImage: "command.circle.fill")
                .font(CyberpunkTheme.monoFont(size: 12, weight: .medium))
                .foregroundStyle(CyberpunkTheme.mutedText)
                .labelStyle(.titleAndIcon)

            Spacer()

            KeyHint(label: "打开", key: "⏎")
            if isWorkbench {
                KeyHint(label: "选择", key: "↑↓←→")
                KeyHint(label: "别名", key: "⇥")
            } else {
                KeyHint(label: "选择", key: "↑↓")
                KeyHint(label: "别名", key: "⇥")
            }
            KeyHint(label: "设置", key: "⌘,")
            KeyHint(label: "关闭", key: "esc")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(CyberpunkTheme.panelBackground.opacity(0.95))
        .overlay(alignment: .top) {
            Divider().overlay(CyberpunkTheme.border.opacity(0.55))
        }
    }
}

struct KeyHint: View {
    let label: String
    let key: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(CyberpunkTheme.monoFont(size: 12))
                .foregroundStyle(CyberpunkTheme.mutedText)
            Text(key)
                .font(CyberpunkTheme.monoFont(size: 11, weight: .medium))
                .foregroundStyle(CyberpunkTheme.matrixBright)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(CyberpunkTheme.surface)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(CyberpunkTheme.border.opacity(0.75), lineWidth: 1)
                }
        }
    }
}
