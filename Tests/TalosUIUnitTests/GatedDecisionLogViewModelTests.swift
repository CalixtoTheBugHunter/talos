import Foundation
import TalosOrchestration
import TalosProjectLibrary
import TalosSafeguards
import TalosUI
import Testing

/// The four states a surface owes — Loading, Empty, Ready, Failed — driven
/// from a ``GatedDecisionLogReader`` rather than asserted directly, since the
/// view renders whatever ``GatedDecisionLogViewModel/state`` holds.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#the-five-states-every-surface-owes
@Suite("Gated decision log view model")
struct GatedDecisionLogViewModelTests {
    private static let project = ProjectIdentifier(rawValue: "p1")

    @Test("Loading a range with entries reaches Ready with those entries")
    @MainActor
    func loadingWithEntriesReachesReady() async {
        let entry = Self.makeEntry(id: 1)
        let model = GatedDecisionLogViewModel(
            reader: FixedGatedDecisionLogReader(.success([entry])),
            project: Self.project,
            from: .distantPast,
            to: .distantFuture
        )

        await model.load()

        #expect(model.state == .ready([entry]))
    }

    @Test("Loading an empty range reaches Empty, not Ready with zero entries")
    @MainActor
    func loadingWithNoEntriesReachesEmpty() async {
        let model = GatedDecisionLogViewModel(
            reader: FixedGatedDecisionLogReader(.success([])),
            project: Self.project,
            from: .distantPast,
            to: .distantFuture
        )

        await model.load()

        #expect(model.state == .empty)
    }

    @Test("A reader failure reaches Failed rather than throwing out of load()")
    @MainActor
    func readerFailureReachesFailed() async {
        let model = GatedDecisionLogViewModel(
            reader: FixedGatedDecisionLogReader(.failure(GatedDecisionLogReaderTestError.unreadable)),
            project: Self.project,
            from: .distantPast,
            to: .distantFuture
        )

        await model.load()

        guard case .failed = model.state else {
            Issue.record("Expected .failed, got \(model.state)")
            return
        }
    }

    @Test("Calling load() again after a failure can reach Ready — the Failed state is retryable")
    @MainActor
    func retryingAfterFailureCanReachReady() async {
        let entry = Self.makeEntry(id: 2)
        let reader = FixedGatedDecisionLogReader(.failure(GatedDecisionLogReaderTestError.unreadable))
        let model = GatedDecisionLogViewModel(
            reader: reader,
            project: Self.project,
            from: .distantPast,
            to: .distantFuture
        )

        await model.load()
        guard case .failed = model.state else {
            Issue.record("Expected .failed before retry, got \(model.state)")
            return
        }

        reader.result = .success([entry])
        await model.load()

        #expect(model.state == .ready([entry]))
    }

    private static func makeEntry(id: Int) -> StoredGatedDecisionEntry {
        StoredGatedDecisionEntry(
            id: id,
            project: project,
            sessionID: UUID(),
            timestamp: Date(timeIntervalSince1970: 1000),
            subFunction: .automator,
            requestID: "r\(id)",
            requestPrompt: "Delete 4 files in Sources/",
            action: .fileDelete,
            classification: .tier(.irreversible),
            actor: .user,
            outcome: .denied
        )
    }
}

private enum GatedDecisionLogReaderTestError: Error {
    case unreadable
}

/// A reader whose result is fixed at init and mutable afterward, so a test
/// can drive the same view model through a failure and then a success.
private final class FixedGatedDecisionLogReader: GatedDecisionLogReader, @unchecked Sendable {
    var result: Result<[StoredGatedDecisionEntry], any Error>

    init(_ result: Result<[StoredGatedDecisionEntry], any Error>) {
        self.result = result
    }

    func entries(project _: ProjectIdentifier, from _: Date, to _: Date) async throws -> [StoredGatedDecisionEntry] {
        try result.get()
    }
}
