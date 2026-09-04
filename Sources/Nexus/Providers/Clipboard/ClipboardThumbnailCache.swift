import CoreGraphics
import Foundation
import ImageIO

actor ClipboardThumbnailCache {
    static let shared = ClipboardThumbnailCache()
    static let displayScale: CGFloat = 2
    private static let maxPixelSize = 480

    nonisolated(unsafe) private static let cache: NSCache<NSUUID, CGImage> = {
        let cache = NSCache<NSUUID, CGImage>()
        cache.countLimit = 96
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    private var inFlight: [UUID: Task<CGImage?, Never>] = [:]

    nonisolated static func cached(_ id: UUID) -> CGImage? {
        cache.object(forKey: id as NSUUID)
    }

    nonisolated static func invalidateCached(_ id: UUID) {
        cache.removeObject(forKey: id as NSUUID)
    }

    func image(id: UUID, thumbnailURL: URL, blobURL: URL) async -> CGImage? {
        if let cached = Self.cached(id) { return cached }
        if let task = inFlight[id] { return await task.value }
        let task = Task.detached(priority: .utility) {
            Self.loadImage(at: thumbnailURL) ?? Self.loadImage(at: blobURL)
        }
        inFlight[id] = task
        let image = await task.value
        inFlight[id] = nil
        if let image {
            Self.cache.setObject(image, forKey: id as NSUUID,
                                 cost: image.bytesPerRow * image.height)
        }
        return image
    }

    nonisolated private static func loadImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
