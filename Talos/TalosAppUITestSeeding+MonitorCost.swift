import Foundation
import TalosAdapters
import TalosOrchestration
import TalosProjectLibrary
import TalosUI

/// The Monitor cost seed, split from `TalosAppUITestSeeding` for the same
/// reason the file itself was split from `TalosApp`: to keep each type's body
/// under the line-count limits, not because the helper differs from the others.
extension TalosAppUITestSeeding {
    /// Exists only so `TalosUITests` can drive the real, mounted Monitor cost
    /// list before a project-selection flow exists to load it for real — the
    /// same reason the seeds beside it exist. Seeds three sessions so the test
    /// sees every cost line: a priced run, an unknown model (tokens known, cost
    /// unavailable — never guessed), and an unparsable token report. Forces the
    /// Monitor surface, since the persisted sidebar selection survives across
    /// launches and would otherwise leave the seeded list off screen.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-cost-is-measured
    static func seedMonitorCost(into viewModel: MonitorCostViewModel, navigation: ShellNavigationModel) {
        guard ProcessInfo.processInfo.environment["TALOS_UI_TEST_MONITOR_COST"] != nil else { return }
        viewModel.present(seededMonitorCostRecords)
        navigation.selectedSurface = .monitor
    }

    /// One seeded Monitor cost session: what ran and the token report the cost
    /// estimate is mapped from.
    private struct SeededCostSession {
        let subFunction: SubFunction
        let report: TokenReport
    }

    private static let seededMonitorCostSessions: [SeededCostSession] = [
        SeededCostSession(subFunction: .automator, report: .measured(
            TokenCounts(
                input: seededPricedInput,
                output: seededPricedOutput,
                cacheCreation: seededPricedCacheWrite,
                cacheRead: seededPricedCacheRead
            ),
            model: "global.anthropic.claude-opus-5"
        )),
        SeededCostSession(subFunction: .assistant, report: .measured(
            TokenCounts(input: seededUnknownInput, output: seededUnknownOutput),
            model: "experimental-model-x"
        )),
        SeededCostSession(subFunction: .advisor, report: .unavailable(
            TokenUsageUnavailable(reason: .unrecognizedFormat, agentVersion: "2.1.246")
        ))
    ]

    private static let seededMonitorCostRecords: [StoredSessionRecord] = {
        let base = Date(timeIntervalSince1970: seededMonitorCostEpoch)
        return seededMonitorCostSessions.enumerated().map { index, session in
            StoredSessionRecord(
                id: UUID(),
                project: ProjectIdentifier(rawValue: "ui-test-project"),
                subFunction: session.subFunction,
                agentName: "claude-code",
                outcome: .succeeded,
                startedAt: base.addingTimeInterval(Double(index) * seededMonitorCostSpacing),
                duration: seededMonitorCostDuration,
                toolCallCount: 0,
                approvalCount: 0,
                denialCount: 0,
                retryCount: 0,
                tokenOverheadRatio: seededMonitorCostOverheadRatio,
                tokenReport: session.report
            )
        }
    }()

    private static let seededPricedInput = 2
    private static let seededPricedOutput = 4
    private static let seededPricedCacheWrite = 2637
    private static let seededPricedCacheRead = 16509
    private static let seededUnknownInput = 1200
    private static let seededUnknownOutput = 340
    private static let seededMonitorCostEpoch: TimeInterval = 1_700_000_000
    private static let seededMonitorCostSpacing: TimeInterval = 120
    private static let seededMonitorCostDuration: TimeInterval = 12
    private static let seededMonitorCostOverheadRatio = 0.03
}
