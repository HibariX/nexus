import AppKit
import Testing
@testable import MyRaycast

@Suite("剪贴板性能边界")
struct ClipboardPerformanceTests {
    @Test("长文本只建立有界搜索预览")
    func longTextUsesBoundedSearchPreview() {
        let fullText = String(repeating: "A", count: ClipboardStore.searchPreviewLimit) + "不可索引后缀"
        let preview = ClipboardStore.makeSearchPreview(fullText)

        #expect(preview.count == ClipboardStore.searchPreviewLimit)
        #expect(preview.allSatisfy { $0 == "a" })
        #expect(fullText.hasSuffix("不可索引后缀"))
    }

    @Test("结果标题只处理有限前缀")
    func resultTitleIsBounded() {
        let text = "第一行\n" + String(repeating: "长", count: 10_000)
        let title = ClipboardProvider.resultTitle(for: text)

        #expect(title.count == 80)
        #expect(!title.contains("\n"))
        #expect(title.hasPrefix("第一行 "))
    }

    @Test("剪贴板关键词解析为独占过滤词")
    func keywordQueryExtractsFilter() {
        #expect(ClipboardProvider.keywordFilter(in: "clip") == "")
        #expect(ClipboardProvider.keywordFilter(in: "剪贴板 发票") == "发票")
        #expect(ClipboardProvider.keywordFilter(in: "clipboard image") == "image")
        #expect(ClipboardProvider.keywordFilter(in: "clipping") == nil)
    }

    @Test("缩略图缺失时异步回退到原图并限制尺寸")
    func thumbnailFallsBackToBlob() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyRaycastTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let blobURL = directory.appendingPathComponent("source.png")
        let missingThumbnailURL = directory.appendingPathComponent("missing.png")
        try makePNG(width: 1_000, height: 500).write(to: blobURL)

        let image = await ClipboardThumbnailCache.shared.image(
            id: UUID(), thumbnailURL: missingThumbnailURL, blobURL: blobURL
        )
        let loaded = try #require(image)
        #expect(loaded.width == 480)
        #expect(loaded.height == 240)
    }

    private func makePNG(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(NSColor.systemGreen.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        return try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }
}
