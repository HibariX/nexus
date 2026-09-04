import Foundation

struct FileHit {
    let path: String
    let name: String
}

/// NSMetadataQuery（Spotlight）async 封装。依赖主 run loop，全类 MainActor。
/// 用 selector 式 observer 而非闭包式：后者要求 @Sendable，会与
/// 非 Sendable 的 NSMetadataQuery 冲突。
final class MetadataSearch: NSObject {
    private var currentQuery: NSMetadataQuery?
    private var continuation: CheckedContinuation<[FileHit], Never>?
    private var limit = 20
    private var generation = 0

    func search(_ text: String, limit: Int = 20) async -> [FileHit] {
        finish([])  // 立即了结上一个未完成的查询

        self.limit = limit
        generation += 1
        let gen = generation

        return await withCheckedContinuation { cont in
            continuation = cont

            let query = NSMetadataQuery()
            query.predicate = NSPredicate(format: "kMDItemDisplayName LIKE[cd] %@", "*\(text)*")
            query.searchScopes = [NSMetadataQueryUserHomeScope]
            query.sortDescriptors = [
                NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)
            ]

            NotificationCenter.default.addObserver(
                self, selector: #selector(gatheringDidFinish(_:)),
                name: .NSMetadataQueryDidFinishGathering, object: query
            )

            currentQuery = query
            guard query.start() else {
                finish([])
                return
            }

            // Spotlight 索引被禁用等情况下永不回调，1.5s 超时兜底
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                guard let self, self.generation == gen else { return }
                self.finish([])
            }
        }
    }

    @objc private func gatheringDidFinish(_ notification: Notification) {
        guard let query = currentQuery else { return }
        query.disableUpdates()
        var hits: [FileHit] = []
        for i in 0..<min(query.resultCount, limit) {
            guard let item = query.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            let name = item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String
                ?? (path as NSString).lastPathComponent
            hits.append(FileHit(path: path, name: name))
        }
        finish(hits)
    }

    /// 停查询、摘 observer、resume continuation，幂等
    private func finish(_ hits: [FileHit]) {
        if let query = currentQuery {
            query.stop()
            NotificationCenter.default.removeObserver(
                self, name: .NSMetadataQueryDidFinishGathering, object: query)
            currentQuery = nil
        }
        continuation?.resume(returning: hits)
        continuation = nil
    }
}
