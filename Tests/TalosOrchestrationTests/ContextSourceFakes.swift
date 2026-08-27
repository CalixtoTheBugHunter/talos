import TalosOrchestration

/// A test double for the three droppable content-source protocols, sharing
/// one implementation since all three have the identical shape. Counts
/// calls so a test can assert assembly fetches each source at most once per
/// `assemble(_:)` call — the "measurably cheap" acceptance criterion.
final class FakeContextSource: @unchecked Sendable {
    private let fragment: ContextFragment
    private(set) var fetchCount = 0

    init(_ fragment: ContextFragment) {
        self.fragment = fragment
    }

    func fetch(for _: Intent) -> ContextFragment {
        fetchCount += 1
        return fragment
    }
}

extension FakeContextSource: SpecDriveContextSource {}
extension FakeContextSource: BoardStateContextSource {}
extension FakeContextSource: MemoriesContextSource {}
