import AppKit
import Testing
@testable import MyRaycast

@Suite("剪贴板贴图内容")
struct ClipboardPinContentTests {
    @Test("图片与文字并存时图片优先")
    func imageBeatsText() throws {
        let item = NSPasteboardItem()
        item.setData(try pngData(), forType: .png)
        item.setString("备用文字", forType: .string)
        let content = try #require(read(item))

        guard case .image(let image) = content else {
            Issue.record("应解析为图片")
            return
        }
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }

    @Test("TIFF 图片可以直接贴出")
    func readsTIFFImage() throws {
        let item = NSPasteboardItem()
        item.setData(try tiffData(), forType: .tiff)
        let content = try #require(read(item))

        guard case .image(let image) = content else {
            Issue.record("应解析为 TIFF 图片")
            return
        }
        #expect(image.size == NSSize(width: 2, height: 2))
    }

    @Test("富文本优先于纯文本并保留格式")
    func richTextBeatsPlainText() throws {
        let rich = NSAttributedString(
            string: "富文本",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 18)]
        )
        let data = try rich.data(
            from: NSRange(location: 0, length: rich.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let item = NSPasteboardItem()
        item.setData(data, forType: .rtf)
        item.setString("纯文本", forType: .string)
        let content = try #require(read(item))

        guard case .text(let text) = content else {
            Issue.record("应解析为富文本")
            return
        }
        #expect(text.string == "富文本")
        let font = text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @Test("低对比度富文本会恢复为系统正文色")
    func unreadableRichTextUsesLabelColor() throws {
        let rich = NSAttributedString(
            string: "浅色文字",
            attributes: [.foregroundColor: NSColor.white]
        )
        let data = try rich.data(
            from: NSRange(location: 0, length: rich.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let item = NSPasteboardItem()
        item.setData(data, forType: .rtf)
        let content = try #require(read(item))

        guard case .text(let text) = content,
              let color = text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor else {
            Issue.record("应解析出带可读颜色的富文本")
            return
        }
        let actual = try #require(color.usingColorSpace(.sRGB))
        let expected = try #require(NSColor.labelColor.usingColorSpace(.sRGB))
        #expect(abs(actual.redComponent - expected.redComponent) < 0.001)
        #expect(abs(actual.greenComponent - expected.greenComponent) < 0.001)
        #expect(abs(actual.blueComponent - expected.blueComponent) < 0.001)
        #expect(actual.alphaComponent >= expected.alphaComponent)
    }

    @Test("文本面板完成正文布局并隐藏窗口按钮")
    func textPanelLaysOutVisibleText() throws {
        let panel = PinTextPanel(
            text: NSAttributedString(string: "可见文本", attributes: [.foregroundColor: NSColor.labelColor]),
            near: NSPoint(x: 400, y: 400)
        )
        panel.contentView?.layoutSubtreeIfNeeded()
        let textView = try #require(findTextView(in: panel.contentView))

        #expect(textView.string == "可见文本")
        #expect(textView.frame.width > 0)
        #expect(textView.frame.height > 0)
        #expect(textView.layoutManager?.numberOfGlyphs == 4)
        #expect(panel.standardWindowButton(.closeButton)?.isHidden == true)
        #expect(panel.standardWindowButton(.miniaturizeButton)?.isHidden == true)
        #expect(panel.standardWindowButton(.zoomButton)?.isHidden == true)
        panel.close()
    }

    @Test("损坏图片会回退到文本")
    func brokenImageFallsBackToText() throws {
        let item = NSPasteboardItem()
        item.setData(Data([0x00, 0x01, 0x02]), forType: .png)
        item.setString("仍可贴出", forType: .string)
        let content = try #require(read(item))

        guard case .text(let text) = content else {
            Issue.record("应回退到纯文本")
            return
        }
        #expect(text.string == "仍可贴出")
        #expect(text.attribute(.font, at: 0, effectiveRange: nil) != nil)
    }

    @Test("HTML 优先于纯文本")
    func htmlBeatsPlainText() throws {
        let item = NSPasteboardItem()
        item.setData(Data("<p><strong>网页内容</strong></p>".utf8), forType: .html)
        item.setString("网页内容（纯文本）", forType: .string)
        let content = try #require(read(item))

        guard case .text(let text) = content else {
            Issue.record("应解析为 HTML 富文本")
            return
        }
        #expect(text.string.contains("网页内容"))
        #expect(!text.string.contains("纯文本"))
    }

    @Test("文件 URL 和空白文本均不支持")
    func filesAndBlankTextAreUnsupported() {
        let file = NSPasteboardItem()
        file.setString("file:///tmp/example.png", forType: .fileURL)
        #expect(read(file) == nil)

        let blank = NSPasteboardItem()
        blank.setString(" \n\t ", forType: .string)
        #expect(read(blank) == nil)
    }

    @Test("空剪贴板不产生内容")
    func emptyPasteboardIsUnsupported() {
        let pasteboard = makePasteboard()
        #expect(ClipboardPinContentReader.read(from: pasteboard) == nil)
    }

    private func read(_ item: NSPasteboardItem) -> ClipboardPinContent? {
        let pasteboard = makePasteboard()
        pasteboard.writeObjects([item])
        return ClipboardPinContentReader.read(from: pasteboard)
    }

    private func makePasteboard() -> NSPasteboard {
        let name = NSPasteboard.Name("MyRaycastTests.\(UUID().uuidString)")
        let pasteboard = NSPasteboard(name: name)
        pasteboard.clearContents()
        return pasteboard
    }

    private func findTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NSTextView { return textView }
        return view.subviews.lazy.compactMap(findTextView).first
    }

    private func pngData() throws -> Data {
        let tiff = try tiffData()
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    private func tiffData() throws -> Data {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()
        return try #require(image.tiffRepresentation)
    }
}
