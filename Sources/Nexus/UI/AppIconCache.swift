import AppKit
import CoreGraphics

/// 在后台加载并栅格化文件/应用图标，避免 LazyVGrid 首次显示新行时在主线程解码 ICNS。
/// 统一缓存 64pt @2x 位图；约 145 个应用占 10 MB 左右，也能减少滚动时上传大纹理的开销。
actor AppIconCache {
    static let shared = AppIconCache()
    static let displayScale: CGFloat = 2
    static let renderedPointSize: CGFloat = 64
    static let renderedPixelSize = Int(renderedPointSize * displayScale)

    // NSCache 的读写是线程安全的。同步读取让回滚到已浏览区域时无需等待一次 actor hop。
    nonisolated(unsafe) private static let cache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 512
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()

    private var inFlight: [String: Task<CGImage?, Never>] = [:]

    nonisolated static func cachedIcon(forFile path: String) -> CGImage? {
        cache.object(forKey: path as NSString)
    }

    func icon(forFile path: String) async -> CGImage? {
        if let cached = Self.cachedIcon(forFile: path) { return cached }
        if let task = inFlight[path] { return await task.value }

        let task = Task.detached(priority: .utility) {
            Self.loadAndRasterize(path: path)
        }
        inFlight[path] = task
        let icon = await task.value
        inFlight[path] = nil

        if let icon {
            let cost = icon.bytesPerRow * icon.height
            Self.cache.setObject(icon, forKey: path as NSString, cost: cost)
        }
        return icon
    }

    /// 最多同时准备两个图标，避免预热抢占滚动与输入所需的 CPU。
    func prefetch(paths: [String]) async {
        for start in stride(from: 0, to: paths.count, by: 2) {
            guard !Task.isCancelled else { return }
            let end = min(start + 2, paths.count)
            await withTaskGroup(of: Void.self) { group in
                for path in paths[start..<end] where Self.cachedIcon(forFile: path) == nil {
                    group.addTask { _ = await self.icon(forFile: path) }
                }
            }
            await Task.yield()
        }
    }

    nonisolated private static func loadAndRasterize(path: String) -> CGImage? {
        let image = NSWorkspace.shared.icon(forFile: path)
        var proposedRect = NSRect(
            origin: .zero,
            size: NSSize(width: renderedPointSize, height: renderedPointSize)
        )
        guard let source = image.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: [.interpolation: NSImageInterpolation.high]
        ) else { return nil }

        let pixelSize = renderedPixelSize
        guard let context = CGContext(
            data: nil,
            width: pixelSize,
            height: pixelSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        let scale = min(
            CGFloat(pixelSize) / CGFloat(source.width),
            CGFloat(pixelSize) / CGFloat(source.height)
        )
        let size = CGSize(width: CGFloat(source.width) * scale, height: CGFloat(source.height) * scale)
        let rect = CGRect(
            x: (CGFloat(pixelSize) - size.width) / 2,
            y: (CGFloat(pixelSize) - size.height) / 2,
            width: size.width,
            height: size.height
        )
        context.draw(source, in: rect)
        return context.makeImage()
    }
}
