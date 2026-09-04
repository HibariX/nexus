import AppKit

/// 一条标注。坐标统一用「图像归一化坐标」（0…1，原点左下），
/// 与窗口缩放解耦：窗口任意缩放时标注跟随图片。
struct Annotation: Identifiable {
    enum Tool: CaseIterable {
        case rect
        case line
        case arrow
        case text
        case highlight   // 半透明高亮色块
        case blur        // 像素化打码（遮挡敏感信息）
        case number      // 步骤编号徽标（点标注，自增）

        var symbolName: String {
            switch self {
            case .rect: return "rectangle"
            case .line: return "line.diagonal"
            case .arrow: return "arrow.up.right"
            case .text: return "character.cursor.ibeam"
            case .highlight: return "highlighter"
            case .blur: return "square.grid.3x3.fill"
            case .number: return "number.circle.fill"
            }
        }

        var title: String {
            switch self {
            case .rect: return "矩形"
            case .line: return "直线"
            case .arrow: return "箭头"
            case .text: return "文字"
            case .highlight: return "高亮"
            case .blur: return "模糊"
            case .number: return "编号"
            }
        }

        /// 填充类工具（整片命中、无边框判定）
        var isFilled: Bool { self == .highlight || self == .blur }

        /// 拖出矩形区域的工具。按住 ⇧ 拖拽时约束为正方形
        var isRectangular: Bool { self == .rect || self == .highlight || self == .blur }

        /// 工具条中的序号（1 起），用于 ⌘数字 快捷键
        var shortcutIndex: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

        /// ⌘数字 → 对应工具（越界返回 nil）
        static func from(shortcutIndex index: Int) -> Tool? {
            let i = index - 1
            return allCases.indices.contains(i) ? allCases[i] : nil
        }
    }

    /// 线宽/字号档位
    enum Weight: CaseIterable {
        case thin, regular, bold

        var lineWidth: CGFloat {
            switch self {
            case .thin: return 1.5
            case .regular: return 2.5
            case .bold: return 4.5
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .thin: return 13
            case .regular: return 18
            case .bold: return 26
            }
        }

        var title: String {
            switch self {
            case .thin: return "细"
            case .regular: return "中"
            case .bold: return "粗"
            }
        }

        var dotSize: CGFloat {
            switch self {
            case .thin: return 4
            case .regular: return 6
            case .bold: return 9
            }
        }

        /// 编号徽标半径（图像 point）
        var numberRadius: CGFloat {
            switch self {
            case .thin: return 9
            case .regular: return 12
            case .bold: return 16
            }
        }
    }

    let id = UUID()
    var tool: Tool
    var start: CGPoint      // 归一化
    var end: CGPoint        // 归一化
    var color: NSColor
    var weight: Weight = .regular
    var text: String = ""   // tool == .text
    var number: Int = 0     // tool == .number（创建时赋值，end == start）

    static let palette: [NSColor] = [.systemRed, .systemOrange, .systemYellow,
                                     .systemGreen, .systemBlue, .white, .black]

    // MARK: - 绘制

    /// 在指定视图尺寸下绘制自己（视图坐标 = 归一化 × 尺寸）
    func draw(in size: NSSize, scale: CGFloat = 1) {
        let p1 = NSPoint(x: start.x * size.width, y: start.y * size.height)
        let p2 = NSPoint(x: end.x * size.width, y: end.y * size.height)
        let lineWidth = max(weight.lineWidth * scale, 1)

        color.setStroke()

        switch tool {
        case .rect:
            let path = NSBezierPath(roundedRect: normalizedRect(p1, p2),
                                    xRadius: 2 * scale, yRadius: 2 * scale)
            path.lineWidth = lineWidth
            path.stroke()

        case .line:
            let path = NSBezierPath()
            path.move(to: p1)
            path.line(to: p2)
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.stroke()

        case .arrow:
            drawArrow(from: p1, to: p2, lineWidth: lineWidth)

        case .text:
            guard !text.isEmpty else { return }
            text.draw(at: p1, withAttributes: textAttributes(scale: scale))

        case .highlight:
            color.withAlphaComponent(0.3).setFill()
            normalizedRect(p1, p2).fill()

        case .blur:
            // 像素化由 BlurRenderer 采样底图完成，这里只在无底图场景兜底描个框
            break

        case .number:
            drawNumberBadge(at: p1, scale: scale)
        }
    }

    /// 编号徽标：实心圆 + 白色数字居中
    private func drawNumberBadge(at center: NSPoint, scale: CGFloat) {
        let r = max(weight.numberRadius * scale, 6)
        let circle = NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        color.setFill()
        NSBezierPath(ovalIn: circle).fill()

        let str = "\(number)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: r),
            .foregroundColor: color.isLight ? NSColor.black : NSColor.white,
        ]
        let textSize = str.size(withAttributes: attrs)
        str.draw(at: NSPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2),
                 withAttributes: attrs)
    }

    func textAttributes(scale: CGFloat) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.boldSystemFont(ofSize: max(weight.fontSize * scale, 10)),
            .foregroundColor: color,
            .strokeColor: color.isLight ? NSColor.black : NSColor.white,
            .strokeWidth: -2.0,  // 负值 = 描边+填充，保证任意背景可读
        ]
    }

    private func normalizedRect(_ p1: NSPoint, _ p2: NSPoint) -> NSRect {
        NSRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y),
               width: abs(p2.x - p1.x), height: abs(p2.y - p1.y))
    }

    private func drawArrow(from p1: NSPoint, to p2: NSPoint, lineWidth: CGFloat) {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 1 else { return }

        let headLength = min(max(length * 0.25, 10), 28 * max(lineWidth / 2, 1))
        let angle = atan2(dy, dx)
        let tip = p2
        let barb1 = NSPoint(x: tip.x - headLength * cos(angle - .pi / 7),
                            y: tip.y - headLength * sin(angle - .pi / 7))
        let barb2 = NSPoint(x: tip.x - headLength * cos(angle + .pi / 7),
                            y: tip.y - headLength * sin(angle + .pi / 7))
        // 线止于箭头根部，避免穿出箭头尖
        let lineEnd = NSPoint(x: tip.x - headLength * 0.6 * cos(angle),
                              y: tip.y - headLength * 0.6 * sin(angle))

        let shaft = NSBezierPath()
        shaft.move(to: p1)
        shaft.line(to: lineEnd)
        shaft.lineWidth = lineWidth
        shaft.lineCapStyle = .round
        shaft.stroke()

        let head = NSBezierPath()
        head.move(to: tip)
        head.line(to: barb1)
        head.line(to: barb2)
        head.close()
        color.setFill()
        head.fill()
    }

    // MARK: - 命中测试 / 选中框 / 手柄（编辑用，视图坐标）

    enum Handle {
        case start   // 线/箭头起点，矩形左下角
        case end     // 线/箭头终点，矩形右上角
    }

    /// 视图坐标下的两个端点
    func endpoints(in size: NSSize) -> (start: NSPoint, end: NSPoint) {
        (NSPoint(x: start.x * size.width, y: start.y * size.height),
         NSPoint(x: end.x * size.width, y: end.y * size.height))
    }

    /// 文字的包围盒（视图坐标）
    func textBounds(in size: NSSize, scale: CGFloat) -> NSRect {
        let origin = NSPoint(x: start.x * size.width, y: start.y * size.height)
        let textSize = text.size(withAttributes: textAttributes(scale: scale))
        return NSRect(origin: origin, size: textSize)
    }

    /// 编号徽标的包围盒（视图坐标）
    func numberBounds(in size: NSSize, scale: CGFloat) -> NSRect {
        let c = NSPoint(x: start.x * size.width, y: start.y * size.height)
        let r = max(weight.numberRadius * scale, 6)
        return NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
    }

    /// 整体包围盒（视图坐标，选中框用）
    func bounds(in size: NSSize, scale: CGFloat) -> NSRect {
        switch tool {
        case .text:
            return textBounds(in: size, scale: scale)
        case .number:
            return numberBounds(in: size, scale: scale)
        default:
            let (p1, p2) = endpoints(in: size)
            return normalizedRect(p1, p2)
        }
    }

    /// 点击是否命中（tolerance 为容差，视图坐标）。
    /// 矩形优先判边框；interior=true 时矩形内部也算命中（第二轮兜底用）
    func hitTest(_ point: NSPoint, in size: NSSize, scale: CGFloat,
                 tolerance: CGFloat = 9, interior: Bool = false) -> Bool {
        let (p1, p2) = endpoints(in: size)
        switch tool {
        case .rect:
            let rect = normalizedRect(p1, p2)
            let outer = rect.insetBy(dx: -tolerance, dy: -tolerance)
            if interior { return outer.contains(point) }
            let inner = rect.insetBy(dx: tolerance, dy: tolerance)
            return outer.contains(point) && !(inner.width > 0 && inner.height > 0 && inner.contains(point))
        case .line, .arrow:
            return Self.distance(from: point, toSegment: p1, p2) <= tolerance + weight.lineWidth
        case .text:
            return textBounds(in: size, scale: scale).insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .highlight, .blur:
            // 填充区整片可点选
            return normalizedRect(p1, p2).insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .number:
            let c = NSPoint(x: start.x * size.width, y: start.y * size.height)
            let r = max(weight.numberRadius * scale, 6)
            return hypot(point.x - c.x, point.y - c.y) <= r + tolerance
        }
    }

    /// 命中的手柄（优先于整体命中判定）
    func hitHandle(_ point: NSPoint, in size: NSSize, scale: CGFloat) -> Handle? {
        guard tool != .text, tool != .number else { return nil }  // 文字/编号无手柄
        let (p1, p2) = handlePositions(in: size, scale: scale)
        let r: CGFloat = Self.handleRadius + 7
        if hypot(point.x - p1.x, point.y - p1.y) <= r { return .start }
        if hypot(point.x - p2.x, point.y - p2.y) <= r { return .end }
        return nil
    }

    /// 手柄坐标：矩形用左下/右上角（即 start/end 本身），线/箭头用端点
    func handlePositions(in size: NSSize, scale: CGFloat) -> (NSPoint, NSPoint) {
        let (p1, p2) = endpoints(in: size)
        return (p1, p2)
    }

    static let handleRadius: CGFloat = 5

    /// 绘制选中态：虚线包围盒 + 手柄圆点
    func drawSelection(in size: NSSize, scale: CGFloat) {
        let box = bounds(in: size, scale: scale).insetBy(dx: -4, dy: -4)
        let path = NSBezierPath(rect: box)
        path.lineWidth = 1
        path.setLineDash([4, 3], count: 2, phase: 0)
        CyberpunkTheme.matrixNSColor.setStroke()
        path.stroke()

        guard tool != .text, tool != .number else { return }
        let (p1, p2) = handlePositions(in: size, scale: scale)
        for p in [p1, p2] {
            let dot = NSRect(x: p.x - Self.handleRadius, y: p.y - Self.handleRadius,
                             width: Self.handleRadius * 2, height: Self.handleRadius * 2)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: dot).fill()
            let ring = NSBezierPath(ovalIn: dot)
            ring.lineWidth = 1.5
            CyberpunkTheme.matrixNSColor.setStroke()
            ring.stroke()
        }
    }

    /// 悬停高亮：淡色包围盒，提示该标注可点选
    func drawHover(in size: NSSize, scale: CGFloat) {
        let box = bounds(in: size, scale: scale).insetBy(dx: -4, dy: -4)
        let path = NSBezierPath(rect: box)
        path.lineWidth = 1.5
        CyberpunkTheme.matrixNSColor.withAlphaComponent(0.5).setStroke()
        path.stroke()
    }

    private static func distance(from p: NSPoint, toSegment a: NSPoint, _ b: NSPoint) -> CGFloat {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let lengthSq = abx * abx + aby * aby
        guard lengthSq > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = min(max(((p.x - a.x) * abx + (p.y - a.y) * aby) / lengthSq, 0), 1)
        let proj = NSPoint(x: a.x + t * abx, y: a.y + t * aby)
        return hypot(p.x - proj.x, p.y - proj.y)
    }
}

extension NSColor {
    /// 粗略判断亮色（文字描边选反色用）
    var isLight: Bool {
        guard let rgb = usingColorSpace(.deviceRGB) else { return false }
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luminance > 0.6
    }
}

/// 聚焦遮罩：矩形标注之外的区域压暗（Snipaste「聚焦」效果）。
/// 实现：整图盖半透明黑，再把每个矩形区域的原图重绘回来（天然支持多框/重叠）。
enum MaskRenderer {
    static let dimAlpha: CGFloat = 0.45

    static func draw(annotations: [Annotation], draft: Annotation?,
                     image: NSImage, in size: NSSize) {
        var rects = annotations.filter { $0.tool == .rect }
        if let draft, draft.tool == .rect { rects.append(draft) }
        guard !rects.isEmpty else { return }

        NSColor.black.withAlphaComponent(dimAlpha).setFill()
        NSRect(origin: .zero, size: size).fill()

        for annotation in rects {
            let (p1, p2) = annotation.endpoints(in: size)
            let hole = NSRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y),
                              width: abs(p2.x - p1.x), height: abs(p2.y - p1.y))
            guard hole.width > 0, hole.height > 0 else { continue }
            // 视图坐标 → 原图 point 坐标
            let source = NSRect(x: hole.minX / size.width * image.size.width,
                                y: hole.minY / size.height * image.size.height,
                                width: hole.width / size.width * image.size.width,
                                height: hole.height / size.height * image.size.height)
            image.draw(in: hole, from: source, operation: .sourceOver, fraction: 1)
        }
    }
}

/// 像素化打码：采样底图区域 → 降采样 → 最近邻放大，遮挡敏感信息。
/// 采样底图（非合成画布），块数按「图像空间」算，保证显示预览与 bake（2×）完全一致。
enum BlurRenderer {
    static let cell: CGFloat = 8   // 图像 point / 每个马赛克块（可调 6–12）

    static func draw(annotations: [Annotation], draft: Annotation?,
                     image: NSImage, in size: NSSize) {
        var rects = annotations.filter { $0.tool == .blur }
        if let draft, draft.tool == .blur { rects.append(draft) }
        guard !rects.isEmpty else { return }

        for annotation in rects {
            let (p1, p2) = annotation.endpoints(in: size)
            let hole = NSRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y),
                              width: abs(p2.x - p1.x), height: abs(p2.y - p1.y))
            guard hole.width > 1, hole.height > 1 else { continue }
            // 目标坐标 → 原图 point 坐标（同 MaskRenderer 换算，对 bounds 与 pixelSize 都成立）
            let src = NSRect(x: hole.minX / size.width * image.size.width,
                             y: hole.minY / size.height * image.size.height,
                             width: hole.width / size.width * image.size.width,
                             height: hole.height / size.height * image.size.height)
            let cols = max(1, Int((src.width / cell).rounded()))
            let rows = max(1, Int((src.height / cell).rounded()))
            guard let mosaic = pixelate(image: image, from: src, cols: cols, rows: rows) else { continue }

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.imageInterpolation = .none  // 最近邻放大成方块
            mosaic.draw(in: hole, from: NSRect(origin: .zero, size: mosaic.size),
                        operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    /// 把 image 的 src 区域降采样到 cols×rows 位图。用显式像素数的 NSBitmapImageRep，
    /// 而非 lockFocus（后者按屏幕 backing scale 分配，会让块数翻倍、打码变弱）。
    private static func pixelate(image: NSImage, from src: NSRect, cols: Int, rows: Int) -> NSImage? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: cols, pixelsHigh: rows,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: cols, height: rows)
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: cols, height: rows), from: src,
                   operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let mosaic = NSImage(size: NSSize(width: cols, height: rows))
        mosaic.addRepresentation(rep)
        return mosaic
    }
}

/// 把标注烘焙进图片，产出新 NSImage
enum AnnotationRenderer {
    /// 分层绘制标注内容（不含 base 与 selection），显示与 bake 共用以保证 z-order 一致。
    /// 顺序：focus mask → highlight → blur → rect/line/arrow/text/number。
    /// 关键：blur 必须在 focus mask 之上——否则聚焦洞会把干净底图重绘回来、反打码泄密。
    static func drawContent(annotations: [Annotation], draft: Annotation?,
                            image: NSImage, in size: NSSize, scale: CGFloat, masked: Bool) {
        if masked {
            MaskRenderer.draw(annotations: annotations, draft: draft, image: image, in: size)
        }
        // 高亮填充（盖在遮罩之上保持醒目）
        for a in annotations where a.tool == .highlight { a.draw(in: size, scale: scale) }
        if let draft, draft.tool == .highlight { draft.draw(in: size, scale: scale) }
        // 打码（压在最上层的填充，确保完全遮挡）
        BlurRenderer.draw(annotations: annotations, draft: draft, image: image, in: size)
        // 线条 / 文字 / 编号（按创建序）
        for a in annotations where !a.tool.isFilled { a.draw(in: size, scale: scale) }
        if let draft, !draft.tool.isFilled { draft.draw(in: size, scale: scale) }
    }

    static func bake(annotations: [Annotation], into image: NSImage, masked: Bool = false) -> NSImage {
        guard !annotations.isEmpty else { return image }
        // 用像素尺寸渲染保持清晰度；scale 让线宽/字号与显示时观感一致
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return image }
        let pixelSize = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        let scale = pixelSize.width / max(image.size.width, 1)

        let result = NSImage(size: pixelSize)
        result.lockFocus()
        rep.draw(in: NSRect(origin: .zero, size: pixelSize))
        drawContent(annotations: annotations, draft: nil, image: image,
                    in: pixelSize, scale: scale, masked: masked)
        result.unlockFocus()

        // 尺寸语义还原为 point（保持 Retina 1:1 显示）
        result.size = image.size
        return result
    }
}
