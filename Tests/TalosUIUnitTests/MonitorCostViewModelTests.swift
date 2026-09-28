import Foundation
import TalosAdapters
import TalosOrchestration
import TalosProjectLibrary
import TalosUI
import Testing

/// Verifies the Monitor's cost list against
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice#cost-copy
/// — every figure labeled an estimate, an unavailable cost named rather than
/// shown as `$0`, and the reachable states Empty/Loading/Ready/Failed.
@Suite("Monitor cost view model")
struct MonitorCostViewModelTests {
    private static let table = PriceTable(
        effectiveDate: Date(timeIntervalSince1970: 1_000_000),
        prices: [
            "test-model": ModelPrice(
                inputPerMillion: 10, outputPerMillion: 20,
                cacheWritePerMillion: 30, cacheReadPerMillion: 5
            )
        ]
    )

    private static func record(
        model: String? = "test-model",
        report override: TokenReport?? = nil
    ) -> StoredSessionRecord {
        let tokenReport: TokenReport? = if let override {
            override
        } else if let model {
            .measured(TokenCounts(input: 1_000_000, output: 0), model: model)
        } else {
            nil
        }
        return StoredSessionRecord(
            id: UUID(),
            project: ProjectIdentifier(rawValue: "p1"),
            subFunction: .automator,
            agentName: "claude-code",
            outcome: .succeeded,
            startedAt: Date(timeIntervalSince1970: 1000),
            duration: 12,
            toolCallCount: 0,
            approvalCount: 0,
            denialCount: 0,
            retryCount: 0,
            tokenOverheadRatio: 0.03,
            tokenReport: tokenReport
        )
    }

    @Test("No records is the Empty state")
    @MainActor
    func noRecordsIsEmpty() {
        let viewModel = MonitorCostViewModel(priceTable: Self.table)
        viewModel.present([])
        #expect(viewModel.state == .empty)
    }

    @Test("A priced session labels its cost an estimate, never a bare figure")
    @MainActor
    func pricedSessionIsLabeledEstimate() {
        let viewModel = MonitorCostViewModel(priceTable: Self.table)
        viewModel.present([Self.record()])
        let rows = readyRows(viewModel)
        #expect(rows.count == 1)
        #expect(rows[0].costSummary.hasPrefix("Estimated cost: "))
        #expect(!rows[0].costSummary.contains("unavailable"))
    }

    /// "An unknown model reports tokens with cost marked unavailable, never
    /// guessed" — and never `$0`.
    @Test("An unknown model reads cost unavailable, not a zero")
    @MainActor
    func unknownModelReadsUnavailable() {
        let viewModel = MonitorCostViewModel(priceTable: Self.table)
        viewModel.present([Self.record(model: "unlisted-model")])
        let rows = readyRows(viewModel)
        #expect(rows[0].costSummary == "Estimated cost unavailable — no price for unlisted-model")
        #expect(!rows[0].costSummary.contains("$0"))
    }

    @Test("An unavailable token report makes the cost line unavailable with its reason")
    @MainActor
    func unavailableTokensReadUnavailable() {
        let viewModel = MonitorCostViewModel(priceTable: Self.table)
        let report = TokenReport.unavailable(TokenUsageUnavailable(reason: .unrecognizedFormat))
        viewModel.present([Self.record(report: .some(report))])
        let rows = readyRows(viewModel)
        #expect(rows[0].costSummary == "Estimated cost unavailable — session log format not recognized")
    }

    @Test("A session with no token row shows absence, never a zero cost")
    @MainActor
    func noTokenRowShowsAbsence() {
        let viewModel = MonitorCostViewModel(priceTable: Self.table)
        viewModel.present([Self.record(report: .some(nil))])
        let rows = readyRows(viewModel)
        #expect(rows[0].tokensSummary == "No token usage recorded")
        #expect(rows[0].costSummary == "Estimated cost unavailable — not yet reported")
    }

    /// AC3: every cost figure in the list is labeled an estimate — across all
    /// three report kinds shown together.
    @Test("Every cost line is labeled an estimate")
    @MainActor
    func everyCostLineIsLabeledEstimate() {
        let viewModel = MonitorCostViewModel(priceTable: Self.table)
        viewModel.present([
            Self.record(),
            Self.record(model: "unlisted-model"),
            Self.record(report: .some(.unavailable(TokenUsageUnavailable(reason: .notReported))))
        ])
        let rows = readyRows(viewModel)
        #expect(rows.count == 3)
        #expect(rows.allSatisfy { $0.costSummary.hasPrefix("Estimated cost") })
    }

    @Test("The price table's effective date is exposed for display")
    @MainActor
    func effectiveDateIsExposed() {
        let viewModel = MonitorCostViewModel(priceTable: Self.table)
        #expect(viewModel.pricesEffectiveDate == Date(timeIntervalSince1970: 1_000_000))
    }

    @Test("A failing load reaches the Failed state")
    @MainActor
    func failingLoadReachesFailed() async {
        let viewModel = MonitorCostViewModel(priceTable: Self.table)
        await viewModel.load(from: { throw CancellationError() })
        guard case .failed = viewModel.state else {
            Issue.record("Expected a Failed state after a throwing load")
            return
        }
    }

    @Test("A successful load presents its records")
    @MainActor
    func successfulLoadPresentsRecords() async {
        let viewModel = MonitorCostViewModel(priceTable: Self.table)
        let record = Self.record()
        await viewModel.load(from: { [record] in [record] })
        let rows = readyRows(viewModel)
        #expect(rows.count == 1)
    }

    @MainActor
    private func readyRows(_ viewModel: MonitorCostViewModel) -> [MonitorCostRow] {
        guard case let .ready(rows) = viewModel.state else {
            Issue.record("Expected the Ready state, got \(viewModel.state)")
            return []
        }
        return rows
    }
}
