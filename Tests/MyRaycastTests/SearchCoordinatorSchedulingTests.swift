import Foundation
import Testing
@testable import MyRaycast

@Suite("搜索调度")
struct SearchCoordinatorSchedulingTests {
    @Test("明确算式只运行独占 Provider")
    func expressionRunsOnlyExclusiveProvider() {
        let unrelated = SchedulingProbeProvider(title: "无关", rank: 10, exclusive: false)
        let calculator = SchedulingProbeProvider(title: "计算", rank: 20, exclusive: true)
        let provider = SearchCoordinator.exclusiveProvider(
            for: Query(raw: "26461-21440"), in: [unrelated, calculator]
        )

        #expect(provider?.sectionTitle == "计算")
    }
}

private final class SchedulingProbeProvider: CommandProvider {
    let sectionTitle: String
    let sectionRank: Int
    private let exclusive: Bool

    init(title: String, rank: Int, exclusive: Bool) {
        sectionTitle = title
        sectionRank = rank
        self.exclusive = exclusive
    }

    func prefersExclusiveResults(for query: Query) -> Bool { exclusive }

    func results(for query: Query) async -> [ResultItem] {
        return [ResultItem(
            id: "probe:\(sectionTitle)", title: query.trimmed, subtitle: nil,
            icon: .symbol(name: "equal.circle"), score: 1,
            accessoryHint: nil, action: .copyText(query.trimmed)
        )]
    }
}
