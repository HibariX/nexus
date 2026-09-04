import AppKit
import SwiftUI

/// MyRaycast 的赛博朋克霓虹主题。颜色集中在这里，避免不同面板各自漂移。
/// 克制高级风：冷灰蓝夜空底 + 电光青点缀。用色克制、色相统一，突出干净的质感。
enum CyberpunkTheme {
    // 冷灰蓝背景（不艳、干净）
    static let windowBackground = Color(red: 0.043, green: 0.055, blue: 0.090)
    static let panelBackground = Color(red: 0.063, green: 0.082, blue: 0.133)
    static let surface = Color(red: 0.090, green: 0.114, blue: 0.173)
    static let raisedSurface = Color(red: 0.129, green: 0.161, blue: 0.224)

    // 电光青：主高亮（聚焦、选中、输入文字）
    static let matrix = Color(red: 0.243, green: 0.812, blue: 1.0)
    static let matrixBright = Color(red: 0.651, green: 0.914, blue: 1.0)
    // 深青蓝：辅助/悬停
    static let cyan = Color(red: 0.274, green: 0.718, blue: 0.878)
    // 克制的琥珀与危险色
    static let amber = Color(red: 0.843, green: 0.753, blue: 0.353)
    static let danger = Color(red: 1.0, green: 0.361, blue: 0.424)

    static let text = Color(red: 0.933, green: 0.953, blue: 0.973)
    static let secondaryText = Color(red: 0.663, green: 0.718, blue: 0.784)
    static let mutedText = Color(red: 0.427, green: 0.478, blue: 0.541)
    // 冷蓝灰描边
    static let border = Color(red: 0.227, green: 0.341, blue: 0.439)

    static let windowNSColor = NSColor(calibratedRed: 0.043, green: 0.055, blue: 0.090, alpha: 1)
    static let panelNSColor = NSColor(calibratedRed: 0.063, green: 0.082, blue: 0.133, alpha: 1)
    static let surfaceNSColor = NSColor(calibratedRed: 0.090, green: 0.114, blue: 0.173, alpha: 1)
    static let matrixNSColor = NSColor(calibratedRed: 0.243, green: 0.812, blue: 1.0, alpha: 1)
    static let matrixBrightNSColor = NSColor(calibratedRed: 0.651, green: 0.914, blue: 1.0, alpha: 1)
    static let textNSColor = NSColor(calibratedRed: 0.933, green: 0.953, blue: 0.973, alpha: 1)
    static let secondaryTextNSColor = NSColor(calibratedRed: 0.663, green: 0.718, blue: 0.784, alpha: 1)
    static let mutedTextNSColor = NSColor(calibratedRed: 0.427, green: 0.478, blue: 0.541, alpha: 1)
    static let borderNSColor = NSColor(calibratedRed: 0.227, green: 0.341, blue: 0.439, alpha: 1)

    static func monoFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func monoNSFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }
}

struct CyberpunkPanelBackground: View {
    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow)
            CyberpunkTheme.windowBackground.opacity(0.96)
            // 顶部一束极淡的冷光晕：克制的纵深，不打扰内容
            RadialGradient(
                colors: [
                    CyberpunkTheme.cyan.opacity(0.05),
                    Color.clear,
                ],
                center: .top,
                startRadius: 0,
                endRadius: 420
            )
            .offset(y: -260)
        }
    }
}

struct CyberpunkSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat = 8
    var elevated = false

    func body(content: Content) -> some View {
        content
            .background(
                (elevated ? CyberpunkTheme.raisedSurface : CyberpunkTheme.surface)
                    .opacity(0.92),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(CyberpunkTheme.border.opacity(0.72), lineWidth: 1)
            }
            .shadow(
                color: CyberpunkTheme.border.opacity(0.18),
                radius: 10
            )
    }
}

extension View {
    func cyberpunkSurface(cornerRadius: CGFloat = 8, elevated: Bool = false) -> some View {
        modifier(CyberpunkSurfaceModifier(cornerRadius: cornerRadius, elevated: elevated))
    }
}

/// 故障风文字：选中时叠一层红/青错位色差，制造赛博 glitch 质感。
/// 关闭「减少动态」时退化为普通文字。
struct CyberpunkGlitchText: View {
    let text: String
    var font: Font
    var glitching: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if glitching && !reduceMotion {
            ZStack {
                Text(text)
                    .font(font)
                    .foregroundStyle(CyberpunkTheme.matrix.opacity(0.85))
                    .offset(x: 1.0, y: 0)
                Text(text)
                    .font(font)
                    .foregroundStyle(CyberpunkTheme.cyan.opacity(0.85))
                    .offset(x: -1.0, y: 0)
                Text(text)
                    .font(font)
                    .foregroundStyle(CyberpunkTheme.text)
            }
        } else {
            Text(text)
                .font(font)
                .foregroundStyle(CyberpunkTheme.text)
        }
    }
}
