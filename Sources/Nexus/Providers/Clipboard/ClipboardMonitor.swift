import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 轮询 NSPasteboard.changeCount（读 changeCount 是元数据，不触发 macOS 26 剪贴板隐私弹窗；
/// 只在变化时才真正读内容）
final class ClipboardMonitor {
    private let store: ClipboardStore
    private var timer: Timer?
    private var lastChangeCount: Int
    private var ignoreCount = 0

    /// 密码管理器约定类型，一律跳过
    private static let skipTypes: [NSPasteboard.PasteboardType] = [
        .init("org.nspasteboard.ConcealedType"),
        .init("org.nspasteboard.TransientType"),
    ]

    /// 设置里关闭剪贴板历史时置 false：轮询照跑（开销可忽略），但不记录
    var isEnabled = true

    init(store: ClipboardStore) {
        self.store = store
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        let timer = Timer(timeInterval: 0.4, repeats: true) { _ in
            MainActor.assumeIsolated {
                self.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// 自己写回剪贴板（粘贴历史条目）前调用，避免把自己的写入再记一遍
    func ignoreNextChange() {
        ignoreCount += 1
    }

    private func tick() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        if ignoreCount > 0 {
            ignoreCount -= 1
            return
        }

        guard isEnabled else { return }

        let types = pb.types ?? []
        guard !types.contains(where: { Self.skipTypes.contains($0) }) else { return }

        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName

        if types.contains(.string), let text = pb.string(forType: .string) {
            store.addText(text, sourceApp: sourceApp)
        } else if let imageData = imageData(from: pb) {
            Task {
                let pngData = await Task.detached(priority: .utility) {
                    ClipboardImageNormalizer.pngData(from: imageData)
                }.value
                guard let pngData else { return }
                await store.addImage(pngData, sourceApp: sourceApp)
            }
        }
    }

    private func imageData(from pb: NSPasteboard) -> ClipboardImageData? {
        if let png = pb.data(forType: .png) { return .png(png) }
        if let tiff = pb.data(forType: .tiff) { return .encoded(tiff) }
        return nil
    }
}

private enum ClipboardImageData: Sendable {
    case png(Data)
    case encoded(Data)
}

private nonisolated enum ClipboardImageNormalizer {
    static func pngData(from image: ClipboardImageData) -> Data? {
        switch image {
        case .png(let data):
            return data
        case .encoded(let data):
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                output, UTType.png.identifier as CFString, 1, nil
            ) else { return nil }
            CGImageDestinationAddImageFromSource(destination, source, 0, nil)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return output as Data
        }
    }
}
