import AppKit

/// 剪贴板历史存储：index.json + blobs/*.png + thumbs/*.png，500 条 FIFO
final class ClipboardStore {
    static var shared: ClipboardStore?

    private(set) var items: [ClipItem] = []

    private let indexFile = AppStorageDir.subdirectory("Clipboard").appendingPathComponent("index.json")
    private let blobsDir = AppStorageDir.subdirectory("Clipboard/blobs")
    private let thumbsDir = AppStorageDir.subdirectory("Clipboard/thumbs")

    private var searchPreviews: [UUID: String] = [:]
    private var textFingerprintIndex: [Int: [UUID]] = [:]
    private var saveTask: Task<Void, Never>?
    private var saveGeneration = 0
    private let indexWriter = ClipboardIndexWriter()
    nonisolated static let searchPreviewLimit = 16_384
    var maxItems = 500 {
        didSet {
            if maxItems < oldValue { trimAndSave() }
        }
    }
    nonisolated private static let thumbnailHeight: CGFloat = 240

    init() {
        load()
    }

    // MARK: - 写入

    func addText(_ text: String, sourceApp: String?) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // 文本去重：相同内容提升到顶
        let fingerprint = text.hashValue
        let candidates = Set(textFingerprintIndex[fingerprint] ?? [])
        if let existing = items.firstIndex(where: { candidates.contains($0.id) && $0.text == text }) {
            var item = items.remove(at: existing)
            item.date = .now
            items.insert(item, at: 0)
        } else {
            let item = ClipItem(id: UUID(), kind: .text, text: text,
                                imageFile: nil, sourceApp: sourceApp, date: .now)
            items.insert(item, at: 0)
            searchPreviews[item.id] = Self.makeSearchPreview(text)
            textFingerprintIndex[fingerprint, default: []].append(item.id)
        }
        trimAndSave()
    }

    func addImage(_ pngData: Data, sourceApp: String?) async {
        let id = UUID()
        let filename = "\(id.uuidString).png"
        let blobURL = blobsDir.appendingPathComponent(filename)
        let wroteBlob = await Task.detached(priority: .utility) {
            do {
                try pngData.write(to: blobURL, options: .atomic)
                return true
            } catch {
                return false
            }
        }.value
        guard wroteBlob else { return }
        // 缩略图后台生成，避免大图卡主线程
        Task.detached { [thumbsDir] in
            if let thumb = Self.makeThumbnail(from: pngData) {
                try? thumb.write(to: thumbsDir.appendingPathComponent(filename), options: .atomic)
            }
        }
        items.insert(ClipItem(id: id, kind: .image, text: nil,
                              imageFile: filename, sourceApp: sourceApp, date: .now), at: 0)
        trimAndSave()
    }

    func remove(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        removeSearchMetadata(for: items[index])
        deleteBlobs(for: items[index])
        items.remove(at: index)
        scheduleSave()
    }

    // MARK: - 读取

    func imageData(for id: UUID) -> Data? {
        guard let item = items.first(where: { $0.id == id }), let file = item.imageFile else { return nil }
        return try? Data(contentsOf: blobsDir.appendingPathComponent(file))
    }

    func thumbnailURLs(for id: UUID) -> (thumbnail: URL, blob: URL)? {
        guard let item = items.first(where: { $0.id == id }), let file = item.imageFile else { return nil }
        return (thumbsDir.appendingPathComponent(file), blobsDir.appendingPathComponent(file))
    }

    func searchPreview(for item: ClipItem) -> String {
        searchPreviews[item.id] ?? ""
    }

    // MARK: - 持久化

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: indexFile),
              let decoded = try? decoder.decode([ClipItem].self, from: data) else { return }
        items = decoded
        rebuildSearchMetadata()
    }

    private func trimAndSave() {
        while items.count > maxItems {
            let removed = items.removeLast()
            removeSearchMetadata(for: removed)
            deleteBlobs(for: removed)
        }
        scheduleSave()
    }

    private func deleteBlobs(for item: ClipItem) {
        guard let file = item.imageFile else { return }
        try? FileManager.default.removeItem(at: blobsDir.appendingPathComponent(file))
        try? FileManager.default.removeItem(at: thumbsDir.appendingPathComponent(file))
        ClipboardThumbnailCache.invalidateCached(item.id)
    }

    /// 防抖 2s 写盘
    private func scheduleSave() {
        saveTask?.cancel()
        saveGeneration += 1
        let generation = saveGeneration
        let snapshot = items
        saveTask = Task { [indexFile, indexWriter] in
            await indexWriter.schedule(snapshot, generation: generation, to: indexFile)
        }
    }

    func flush() {
        saveTask?.cancel()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(items) {
            try? data.write(to: indexFile, options: .atomic)
        }
    }

    // MARK: - 缩略图

    nonisolated private static func makeThumbnail(from pngData: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailHeight * 2,  // Retina
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }

    nonisolated static func makeSearchPreview(_ text: String) -> String {
        String(text.prefix(searchPreviewLimit)).lowercased()
    }

    private func rebuildSearchMetadata() {
        searchPreviews.removeAll(keepingCapacity: true)
        textFingerprintIndex.removeAll(keepingCapacity: true)
        for item in items where item.kind == .text {
            guard let text = item.text else { continue }
            searchPreviews[item.id] = Self.makeSearchPreview(text)
            textFingerprintIndex[text.hashValue, default: []].append(item.id)
        }
    }

    private func removeSearchMetadata(for item: ClipItem) {
        searchPreviews[item.id] = nil
        guard let text = item.text else { return }
        let fingerprint = text.hashValue
        textFingerprintIndex[fingerprint]?.removeAll { $0 == item.id }
        if textFingerprintIndex[fingerprint]?.isEmpty == true {
            textFingerprintIndex[fingerprint] = nil
        }
    }
}

private actor ClipboardIndexWriter {
    private var latestGeneration = 0

    func schedule(_ items: [ClipItem], generation: Int, to file: URL) async {
        guard generation >= latestGeneration else { return }
        latestGeneration = generation
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled, generation == latestGeneration else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items), generation == latestGeneration else { return }
        try? data.write(to: file, options: .atomic)
    }
}
