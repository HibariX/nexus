import SwiftUI

struct FooterBar: View {
    var isWorkbench: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            CyberpunkBrandMark()

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

/// 赛博朋克品牌标识：霓虹六边形+瞄准镜 logo，配微 glitch 文字
struct CyberpunkBrandMark: View {
    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Image(systemName: "hexagon")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(CyberpunkTheme.matrix)
                Image(systemName: "scope")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(CyberpunkTheme.matrixBright)
            }
            .shadow(color: CyberpunkTheme.matrix.opacity(0.6), radius: 4)

            CyberpunkGlitchText(
                text: "MyRaycast",
                font: CyberpunkTheme.monoFont(size: 11, weight: .semibold),
                glitching: true
            )
            .shadow(color: CyberpunkTheme.matrix.opacity(0.4), radius: 3)
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
