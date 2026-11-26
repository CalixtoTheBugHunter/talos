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
        #expect(viewModel.state == .empty(.noSessions))
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
        await viewModel.load(filter: MonitorFilter(timeRange: .allTime), from: { _ in throw CancellationError() })
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
        await viewModel.load(filter: MonitorFilter(timeRange: .allTime), from: { [record] _ in [record] })
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

    // MARK: Talos-added token overhead

    private static func overheadRecord(injected: Int?, input: Int, output: Int = 0) -> StoredSessionRecord {
        StoredSessionRecord(
            id: UUID(), project: ProjectIdentifier(rawValue: "p1"), subFunction: .automator,
            agentName: "claude-code", outcome: .succeeded, startedAt: Date(timeIntervalSince1970: 1000),
            duration: 12, toolCallCount: 0, approvalCount: 0, denialCount: 0, retryCount: 0,
            tokenOverheadRatio: 0,
            tokenReport: .measured(TokenCounts(input: input, output: output), model: "test-model"),
            injectedTokens: injected.map { InjectedTokens(bySource: [.guideline: $0], framing: 0) }
        )
    }

    @MainActor
    private static func readyRows(_ viewModel: MonitorCostViewModel) -> [MonitorCostRow] {
        guard case let .ready(rows) = viewModel.state else { return [] }
        return rows
    }

    @Test("A session's overhead is labeled an estimate, shows its sources, and is not flagged under 5%")
    @MainActor
    func overheadRowUnderBudget() {
        let viewModel = MonitorCostViewModel(priceTable: Self.table)
        viewModel.present([Self.overheadRecord(injected: 30, input: 1000)])

        let row = Self.readyRows(viewModel).first
        #expect(row?.overheadSummary == "Estimated Talos-added token overhead: 3.0% (30 of 1000 session tokens)")
        #expect(row?.overheadSources == "guideline 30 · framing 0")
        #expect(row?.overheadFlag == nil)
    }

    @Test("A session at or over 5% is flagged in words")
    @MainActor
    func overheadRowOverBudgetIsFlagged() {
        let viewModel = MonitorCostViewModel(priceTable: Self.table)
        viewModel.present([Self.overheadRecord(injected: 50, input: 1000)])

        #expect(Self.readyRows(viewModel).first?.overheadFlag == "Over the 5% token-overhead budget")
    }

    @Test("A session with no injected-token record says why, rather than reading 0%")
    @MainActor
    func overheadRowUnavailable() {
        let viewModel = MonitorCostViewModel(priceTable: Self.table)
        viewModel.present([Self.overheadRecord(injected: nil, input: 1000)])

        let row = Self.readyRows(viewModel).first
        #expect(row?.overheadSummary.contains("unavailable") == true)
        #expect(row?.overheadSources == nil)
        #expect(row?.overheadFlag == nil)
    }

    @Test("The aggregate is pooled, carries its coverage, and is flagged over 5%")
    @MainActor
    func aggregateCarriesCoverageAndFlag() {
        let viewModel = MonitorCostViewModel(priceTable: Self.table)
        viewModel.present([
            Self.overheadRecord(injected: 100, input: 1000),
            Self.overheadRecord(injected: nil, input: 1000)
        ])

        #expect(viewModel.overhead?.headline == "Estimated Talos-added token overhead: 10.0% of session tokens")
        #expect(viewModel.overhead?.coverage.hasPrefix("Computed from 1 session; 1 excluded") == true)
        #expect(viewModel.overhead?.flag == "Over the 5% token-overhead budget")
    }

    @Test("With nothing measurable the aggregate is unavailable, not 0%")
    @MainActor
    func aggregateWithNothingMeasurable() {
        let viewModel = MonitorCostViewModel(priceTable: Self.table)
        viewModel.present([Self.overheadRecord(injected: nil, input: 1000)])

        #expect(viewModel.overhead?.headline.contains("unavailable") == true)
        #expect(viewModel.overhead?.flag == nil)
    }

    @Test("No records means no aggregate to show")
    @MainActor
    func noRecordsNoAggregate() {
        let viewModel = MonitorCostViewModel(priceTable: Self.table)
        viewModel.present([])
        #expect(viewModel.overhead == nil)
    }
}

/// Verifies the Monitor's duration, outcome, and success-rate copy against
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-task-outcome-is-classified
/// — `Succeeded ÷ (Succeeded + Failed)`, Denied and Stopped excluded and
/// counted, and `Succeeded` stated as a clean exit.
@Suite("Monitor outcome and duration")
struct MonitorOutcomeViewModelTests {
    private static let table = PriceTable(effectiveDate: Date(timeIntervalSince1970: 0), prices: [:])
    private static let now = Date(timeIntervalSince1970: 10_000_000)

    private static func record(
        _ outcome: SessionOutcomeClassification,
        subFunction: SubFunction = .assistant,
        duration: TimeInterval = 12,
        startedAt: Date = now.addingTimeInterval(-60)
    ) -> StoredSessionRecord {
        StoredSessionRecord(
            id: UUID(), project: ProjectIdentifier(rawValue: "p1"), subFunction: subFunction,
            agentName: "claude-code", outcome: outcome, startedAt: startedAt, duration: duration,
            toolCallCount: 0, approvalCount: 0, denialCount: 0, retryCount: 0, tokenOverheadRatio: 0
        )
    }

    @Test("The rate counts Succeeded over Succeeded + Failed, and states the excluded Denied and Stopped")
    @MainActor
    func rateExcludesDeniedAndStoppedAndCountsThem() {
        let viewModel = MonitorCostViewModel(priceTable: Self.table)
        viewModel.present([
            Self.record(.succeeded), Self.record(.succeeded), Self.record(.succeeded),
            Self.record(.failed), Self.record(.denied), Self.record(.stopped)
        ])
        #expect(viewModel.successRate?.headline == "Success rate: 75% (3 of 4 rated sessions exited cleanly)")
        #expect(viewModel.successRate?.exclusions == "2 excluded from the rate: 1 denied, 1 stopped.")
        #expect(
            viewModel.successRate?.caveat == "Succeeded means the agent exited cleanly, not that the task was right."
        )
    }

    @Test("Only Denied and Stopped sessions give no rate — unavailable, never 0% or 100%")
    @MainActor
    func allExcludedIsUnavailable() {
        let viewModel = MonitorCostViewModel(priceTable: Self.table)
        viewModel.present([Self.record(.denied)])
        #expect(
            viewModel.successRate?.headline
                == "Success rate unavailable — no session in this range succeeded or failed"
        )
        #expect(viewModel.successRate?.caveat == nil)
        #expect(viewModel.successRate?.exclusions == "1 excluded from the rate: 1 denied.")
    }

    @Test("Each outcome reads in the SPEC's terms; a denial is not an error")
    @MainActor
    func outcomeCopy() {
        #expect(MonitorCostViewModel.outcomeSummary(.succeeded) == "Outcome: Succeeded — the agent exited cleanly")
        #expect(MonitorCostViewModel.outcomeSummary(.failed) == "Outcome: Failed")
        #expect(MonitorCostViewModel.outcomeSummary(.denied) == "Outcome: Denied — recorded as denied, not as an error")
        #expect(MonitorCostViewModel.outcomeSummary(.stopped) == "Outcome: Stopped by the user")
    }

    @Test("Duration states it excludes time awaiting a decision")
    @MainActor
    func durationCopy() {
        #expect(MonitorCostViewModel.durationSummary(125) == "Duration: 2 min 5 s, excluding time awaiting a decision")
        let suffix = ", excluding time awaiting a decision"
        #expect(MonitorCostViewModel.durationSummary(3725) == "Duration: 1 h 2 min 5 s" + suffix)
        #expect(MonitorCostViewModel.durationSummary(0.2) == "Duration: less than 1 s" + suffix)
    }

    @Test("Each row shows when it started, how long it ran, and how it ended")
    @MainActor
    func rowCarriesStartDurationAndOutcome() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let viewModel = MonitorCostViewModel(priceTable: Self.table, timeZone: utc)
        viewModel.present([Self.record(.stopped, duration: 125)])
        guard case let .ready(rows) = viewModel.state, let row = rows.first else {
            Issue.record("Expected one Ready row")
            return
        }
        #expect(row.title.hasPrefix("Session 1 · assistant"))
        #expect(row.startedSummary.hasPrefix("Started "))
        #expect(row.durationSummary.hasPrefix("Duration: 2 min 5 s"))
        #expect(row.outcomeSummary == "Outcome: Stopped by the user")
    }

    @Test("The sub-function filter narrows both the rows and the rate")
    @MainActor
    func subFunctionFilterNarrowsRowsAndRate() async {
        let viewModel = MonitorCostViewModel(priceTable: Self.table)
        let records = [Self.record(.succeeded, subFunction: .automator), Self.record(.failed, subFunction: .assistant)]
        await viewModel.load(filter: MonitorFilter(subFunction: .automator), now: Self.now) { _ in records }
        guard case let .ready(rows) = viewModel.state else {
            Issue.record("Expected Ready")
            return
        }
        #expect(rows.count == 1)
        #expect(viewModel.successRate?.headline == "Success rate: 100% (1 of 1 rated session exited cleanly)")
    }

    @Test("A folder with no .talos/ is Empty with its reason, not Failed")
    @MainActor
    func notATalosProjectIsEmpty() async {
        let viewModel = MonitorCostViewModel(priceTable: Self.table)
        await viewModel.load(filter: MonitorFilter()) { _ in throw MonitorNotATalosProjectError() }
        #expect(viewModel.state == .empty(.notATalosProject))
    }

    @Test("Before any project is chosen the Monitor is Empty, asking for one")
    @MainActor
    func startsWithNoProject() {
        let viewModel = MonitorCostViewModel(priceTable: Self.table)
        #expect(viewModel.state == .empty(.noProject))
    }
}
