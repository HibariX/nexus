import AppKit
import Vision

/// 基于 Vision 的截图文字识别（OCR）。
enum OCRService {

    /// 识别图片中的文字，按阅读顺序（上→下，左→右）拼接。空串表示未识别到文字。
    /// Vision 较重且同步阻塞，放到 detached 后台任务跑，别占主线程。
    /// 直接传 CGImage：早先为了绕开 Swift 6 跨隔离约束而先编码成 PNG，
    /// 白白多出一次 TIFF 编码、一次 PNG 编码和 Vision 内部的一次解码；
    /// CGImage 本身已是 Sendable，这条弯路不必要
    static func recognize(image: CGImage, languages: [String]) async -> String {
        await Task.detached(priority: .userInitiated) {
            Self.recognizeSync(image: image, languages: languages)
        }.value
    }

    /// 预热：Vision 首次调用要加载识别模型，实测冷启动 640ms、热态 300ms。
    /// 语言必须和实际识别时一致，否则加载的不是同一个模型，热了也白热
    static func prewarm(languages: [String]) {
        Task.detached(priority: .utility) {
            let width = 32, height = 32
            guard let ctx = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let blank = ctx.makeImage() else { return }
            _ = Self.recognizeSync(image: blank, languages: languages)
        }
    }

    nonisolated private static func recognizeSync(image: CGImage, languages: [String]) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if !languages.isEmpty { request.recognitionLanguages = languages }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }

        let observations = request.results ?? []
        // boundingBox 为归一化、左下原点：y 大者在上方；同一行按 x 从左到右
        let sorted = observations.sorted { a, b in
            if abs(a.boundingBox.minY - b.boundingBox.minY) > 0.01 {
                return a.boundingBox.minY > b.boundingBox.minY
            }
            return a.boundingBox.minX < b.boundingBox.minX
        }
        return sorted
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
