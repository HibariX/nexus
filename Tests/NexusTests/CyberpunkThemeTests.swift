import AppKit
import Testing
@testable import Nexus

@Suite("赛博朋克主题")
struct CyberpunkThemeTests {
    @Test("矩阵绿在终端背景上保持可读")
    func matrixContrast() throws {
        let foreground = try #require(CyberpunkTheme.matrixNSColor.usingColorSpace(.sRGB))
        let background = try #require(CyberpunkTheme.windowNSColor.usingColorSpace(.sRGB))
        let lighter = max(luminance(foreground), luminance(background))
        let darker = min(luminance(foreground), luminance(background))
        #expect((lighter + 0.05) / (darker + 0.05) >= 4.5)
    }

    @Test("关键主题字体为等宽字体")
    func keyTextUsesMonospacedFont() {
        let font = CyberpunkTheme.monoNSFont(size: 14)
        #expect(font.fontDescriptor.symbolicTraits.contains(.monoSpace))
    }

    private func luminance(_ color: NSColor) -> CGFloat {
        func linearized(_ component: CGFloat) -> CGFloat {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearized(color.redComponent)
            + 0.7152 * linearized(color.greenComponent)
            + 0.0722 * linearized(color.blueComponent)
    }
}
