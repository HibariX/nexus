import AppKit
import SwiftUI

/// MyRaycast 的终端硬核主题。颜色集中在这里，避免不同面板各自漂移。
enum CyberpunkTheme {
    static let windowBackground = Color(red: 0.024, green: 0.039, blue: 0.031)
    static let panelBackground = Color(red: 0.043, green: 0.071, blue: 0.055)
    static let surface = Color(red: 0.063, green: 0.110, blue: 0.083)
    static let raisedSurface = Color(red: 0.082, green: 0.145, blue: 0.105)

    static let matrix = Color(red: 0.224, green: 1.0, blue: 0.533)
    static let matrixBright = Color(red: 0.620, green: 1.0, blue: 0.753)
    static let cyan = Color(red: 0.396, green: 0.851, blue: 1.0)
    static let amber = Color(red: 1.0, green: 0.706, blue: 0.286)
    static let danger = Color(red: 1.0, green: 0.365, blue: 0.420)

    static let text = Color(red: 0.906, green: 0.969, blue: 0.925)
    static let secondaryText = Color(red: 0.612, green: 0.733, blue: 0.651)
    static let mutedText = Color(red: 0.392, green: 0.502, blue: 0.431)
    static let border = Color(red: 0.165, green: 0.420, blue: 0.267)

    static let windowNSColor = NSColor(calibratedRed: 0.024, green: 0.039, blue: 0.031, alpha: 1)
    static let panelNSColor = NSColor(calibratedRed: 0.043, green: 0.071, blue: 0.055, alpha: 1)
    static let surfaceNSColor = NSColor(calibratedRed: 0.063, green: 0.110, blue: 0.083, alpha: 1)
    static let matrixNSColor = NSColor(calibratedRed: 0.224, green: 1.0, blue: 0.533, alpha: 1)
    static let matrixBrightNSColor = NSColor(calibratedRed: 0.620, green: 1.0, blue: 0.753, alpha: 1)
    static let textNSColor = NSColor(calibratedRed: 0.906, green: 0.969, blue: 0.925, alpha: 1)
    static let secondaryTextNSColor = NSColor(calibratedRed: 0.612, green: 0.733, blue: 0.651, alpha: 1)
    static let mutedTextNSColor = NSColor(calibratedRed: 0.392, green: 0.502, blue: 0.431, alpha: 1)
    static let borderNSColor = NSColor(calibratedRed: 0.165, green: 0.420, blue: 0.267, alpha: 1)

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
            CyberpunkTheme.windowBackground.opacity(0.92)
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
    }
}

extension View {
    func cyberpunkSurface(cornerRadius: CGFloat = 8, elevated: Bool = false) -> some View {
        modifier(CyberpunkSurfaceModifier(cornerRadius: cornerRadius, elevated: elevated))
    }
}
