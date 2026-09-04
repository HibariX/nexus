import AppKit

// 生成 App 图标：菜单栏同款 command 符号 + 蓝色圆角背景，各尺寸精确离屏渲染
// 用法：swift Support/gen-icon.swift  → build/AppIcon.iconset/*.png
_ = NSApplication.shared  // 确保 AppKit 初始化（SF Symbol 加载）

let specs: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func render(px: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx

    let size = CGFloat(px)
    let rect = NSRect(x: 0, y: 0, width: size, height: size)

    // squircle 圆角矩形背景 + 竖向蓝色渐变
    let radius = size * 0.2237
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
    let gradient = NSGradient(starting: NSColor(srgbRed: 0.40, green: 0.52, blue: 0.96, alpha: 1),
                              ending: NSColor(srgbRed: 0.22, green: 0.34, blue: 0.85, alpha: 1))
    gradient?.draw(in: rect, angle: -90)

    // command 符号，白色，居中约占一半
    let conf = NSImage.SymbolConfiguration(pointSize: size * 0.5, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "command", accessibilityDescription: nil)?
        .withSymbolConfiguration(conf) {
        let ss = symbol.size
        let sr = NSRect(x: (size - ss.width) / 2, y: (size - ss.height) / 2,
                        width: ss.width, height: ss.height)
        symbol.draw(in: sr)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
var ok = 0
for (name, px) in specs {
    if let data = render(px: px) {
        try? data.write(to: iconset.appendingPathComponent("\(name).png"))
        ok += 1
    }
}
print("generated \(ok)/\(specs.count) pngs into \(iconset.path)")
