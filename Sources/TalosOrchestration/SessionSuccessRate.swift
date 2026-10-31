import Foundation
import TalosProjectLibrary

/// The success rate for a set of sessions, and the coverage it was computed
/// over. The rate is `Succeeded ÷ (Succeeded + Failed)`: `Denied` and
/// `Stopped` are in neither the numerator nor the denominator, because a
/// denial is the user refusing, not a failure, and a stop is the user's own
/// act.
///
/// The exclusion is carried, never silent: `excludedCount` travels with the
/// rate so the surface that reads it can state what the figure left out, the
/// same honesty decision 50 fixed for token coverage — "a rate computed over
/// an unstated subset reads as a rate over everything."
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-task-outcome-is-classified
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#denial-is-not-failure
public struct SessionSuccessRate: Equatable, Sendable {
    /// Sessions whose agent process exited cleanly — the numerator. A clean
    /// exit, never a verified-correct result.
    public let succeeded: Int
    /// Sessions that exited abnormally or Talos could not run — the rest of
    /// the denominator.
    public let failed: Int
    /// Sessions the gate denied. Excluded from the rate, counted here.
    public let denied: Int
    /// Sessions the user stopped or quit. Excluded from the rate, counted here.
    public let stopped: Int

    public init(succeeded: Int = 0, failed: Int = 0, denied: Int = 0, stopped: Int = 0) {
        self.succeeded = succeeded
        self.failed = failed
        self.denied = denied
        self.stopped = stopped
    }

    /// The sessions the rate is computed from: `Succeeded + Failed`. The
    /// denominator, and the coverage the figure carries.
    public var ratedCount: Int {
        succeeded + failed
    }

    /// Sessions excluded from the rate — `Denied + Stopped`. Carried so the
    /// exclusion is stated wherever the rate appears, never silent.
    public var excludedCount: Int {
        denied + stopped
    }

    /// The fraction in `0...1`, or `nil` when nothing was rated. A rate over
    /// zero rated sessions is absent, not `0` and not `1`: an empty or
    /// all-excluded set has no success rate to state, and inventing one would
    /// read as a measurement nobody made.
    public var fraction: Double? {
        ratedCount == 0 ? nil : Double(succeeded) / Double(ratedCount)
    }

    /// Tallies one set of session records into a single rate. The records are
    /// already filtered to the project and time range the caller chose — this
    /// only classifies and counts.
    public init(records: some Sequence<StoredSessionRecord>) {
        var succeeded = 0, failed = 0, denied = 0, stopped = 0
        for record in records {
            switch record.outcome {
            case .succeeded: succeeded += 1
            case .failed: failed += 1
            case .denied: denied += 1
            case .stopped: stopped += 1
            }
        }
        self.init(succeeded: succeeded, failed: failed, denied: denied, stopped: stopped)
    }
}

/// The success rate across a set of sessions and broken out per sub-function,
/// which is what the Monitor's
/// [Definition of Done criterion](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#checklist)
/// reads. Computed from records a caller has already queried per
/// project and over a selectable time range, so one summary answers "over this
/// range, for this project" overall and for each sub-function at once.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#monitor-screen
public struct SessionMetricsSummary: Equatable, Sendable {
    /// The rate over every record, regardless of sub-function.
    public let overall: SessionSuccessRate
    /// The rate per sub-function. A sub-function with no sessions in range is
    /// absent from the map rather than present with a zeroed rate — the same
    /// reason `SessionSuccessRate/fraction` is `nil` on an empty set.
    public let bySubFunction: [SubFunction: SessionSuccessRate]

    public init(records: [StoredSessionRecord]) {
        overall = SessionSuccessRate(records: records)
        bySubFunction = Dictionary(grouping: records, by: \.subFunction)
            .mapValues(SessionSuccessRate.init(records:))
    }
}
