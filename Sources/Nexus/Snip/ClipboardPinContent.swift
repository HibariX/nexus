import AppKit
import UniformTypeIdentifiers

enum ClipboardPinContent {
    case image(NSImage)
    case text(NSAttributedString)
}

/// 将系统剪贴板中可贴出的内容归一化。文件 URL 不在支持范围内，避免隐式读取磁盘文件。
enum ClipboardPinContentReader {
    static func read(from pasteboard: NSPasteboard) -> ClipboardPinContent? {
        let items = pasteboard.pasteboardItems ?? []

        if let image = firstImage(in: items) {
            return .image(image)
        }
        if let text = firstRichText(in: items) {
            return .text(text)
        }
        if let string = items.compactMap({ $0.string(forType: .string) }).first(where: hasVisibleContent) {
            return .text(normalizedPlainText(string))
        }
        return nil
    }

    private static func firstImage(in items: [NSPasteboardItem]) -> NSImage? {
        for item in items {
            for type in item.types where isDirectImageType(type) {
                guard let data = item.data(forType: type),
                      let image = NSImage(data: data), image.isValid,
                      image.size.width > 0, image.size.height > 0 else { continue }
                return image
            }
        }
        return nil
    }

    private static func isDirectImageType(_ type: NSPasteboard.PasteboardType) -> Bool {
        guard type != .fileURL, let contentType = UTType(type.rawValue) else { return false }
        return contentType.conforms(to: .image)
    }

    private static func firstRichText(in items: [NSPasteboardItem]) -> NSAttributedString? {
        let formats: [(NSPasteboard.PasteboardType, NSAttributedString.DocumentType)] = [
            (.rtfd, .rtfd),
            (.rtf, .rtf),
            (.html, .html),
        ]
        for (pasteboardType, documentType) in formats {
            for item in items {
                guard let data = item.data(forType: pasteboardType) else { continue }
                var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                    .documentType: documentType,
                ]
                if documentType == .html {
                    options[.characterEncoding] = String.Encoding.utf8.rawValue
                }
                guard
                      let attributed = try? NSAttributedString(
                        data: data,
                        options: options,
                        documentAttributes: nil
                      ),
                      hasVisibleContent(attributed.string) else { continue }
                return normalizedRichText(attributed)
            }
        }
        return nil
    }

    private static func normalizedPlainText(_ string: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        return NSAttributedString(string: string, attributes: [
            .font: NSFont.preferredFont(forTextStyle: .body),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ])
    }

    private static func normalizedRichText(_ source: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: source)
        let fullRange = NSRange(location: 0, length: result.length)
        guard fullRange.length > 0 else { return result }

        result.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            if value == nil {
                result.addAttribute(.font, value: NSFont.preferredFont(forTextStyle: .body), range: range)
            }
        }
        result.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
            if let color = value as? NSColor {
                if !hasReadableContrast(color, against: .windowBackgroundColor) {
                    result.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
                }
            } else {
                result.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
            }
        }
        result.enumerateAttribute(.paragraphStyle, in: fullRange) { value, range, _ in
            if value == nil {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineSpacing = 2
                result.addAttribute(.paragraphStyle, value: paragraph, range: range)
            }
        }
        return result
    }

    private static func hasReadableContrast(_ foreground: NSColor, against background: NSColor) -> Bool {
        guard let foreground = foreground.usingColorSpace(.sRGB),
              let background = background.usingColorSpace(.sRGB) else { return false }
        let lighter = max(relativeLuminance(foreground), relativeLuminance(background))
        let darker = min(relativeLuminance(foreground), relativeLuminance(background))
        return (lighter + 0.05) / (darker + 0.05) >= 4.5
    }

    private static func relativeLuminance(_ color: NSColor) -> CGFloat {
        func linearized(_ component: CGFloat) -> CGFloat {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearized(color.redComponent)
            + 0.7152 * linearized(color.greenComponent)
            + 0.0722 * linearized(color.blueComponent)
    }

    private static func hasVisibleContent(_ string: String) -> Bool {
        !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
