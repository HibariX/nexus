import Foundation

struct ClipItem: Codable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case text
        case image
    }

    let id: UUID
    let kind: Kind
    var text: String?          // kind == .text
    var imageFile: String?     // kind == .image，blobs/ 下文件名
    var sourceApp: String?     // 来源应用名
    var date: Date
}
