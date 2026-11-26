import Foundation
import Observation
import TalosAdapters
import TalosOrchestration

/// One session's line on the Monitor's cost list: what ran, the tokens it
/// reported, and the estimate mapped from them. The strings are computed here
/// so the view renders text it cannot get wrong and a test can assert the copy
/// — every cost line says "Estimated", and an absent cost says why rather than
/// reading `$0`.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice#cost-copy
public struct MonitorCostRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// What ran — sub-function and agent — as the row's heading.
    public let title: String
    /// When the session started, in the user's time zone.
    public let startedSummary: String
    /// The recorded duration, which already excludes time spent awaiting a
    /// decision — stated, so it is not read as wall-clock time.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#monitor-screen
    public let durationSummary: String
    /// The inferred outcome, in the terms the SPEC requires wherever it is read.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-task-outcome-is-classified
    public let outcomeSummary: String
    /// The token counts the estimate is mapped from, stated plainly, or their
    /// named absence. Token counts are exact, so they may be shown as numbers.
    public let tokensSummary: String
    /// The cost line, always labeled an estimate and never a bill.
    public let costSummary: String
    /// This session's Talos-added token overhead, labeled an estimate, or why
    /// it is unavailable. Never a `0%` standing in for an unmeasured session.
    public let overheadSummary: String
    /// What Talos injected, by source, so a regression is diagnosable. `nil`
    /// when the session was not measurable.
    public let overheadSources: String?
    /// Spoken and shown when this session is at or over the 5% budget. Words,
    /// not colour; the view pairs it with a symbol.
    public let overheadFlag: String?
}

/// The success rate over the shown sessions, what `Succeeded` means, and what
/// the rate left out — never a rate over an unstated subset.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-task-outcome-is-classified
public struct MonitorSuccessRateSummary: Equatable, Sendable {
    public let headline: String
    /// `nil` when there is no rate to qualify.
    public let caveat: String?
    /// `nil` when nothing was excluded.
    public let exclusions: String?
}

/// Why the Monitor has nothing to show, each with its own copy.
public enum MonitorEmptyReason: Equatable, Sendable {
    /// No project folder chosen yet.
    case noProject
    /// The chosen folder has no `.talos/`, so it has never run a session.
    case notATalosProject
    /// The project has no sessions matching the filter.
    case noSessions
}

/// Thrown by a records loader when the chosen folder has no `.talos/` — an
/// Empty state with its reason, not a failure.
public struct MonitorNotATalosProjectError: Error, Equatable, Sendable {
    public init() {
        // No payload: the type is the whole signal.
    }
}

/// The Monitor's pooled Talos-added token overhead, with the coverage it was
/// computed over. Strings are computed here so a test asserts the copy.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-token-overhead-is-computed
public struct MonitorOverheadSummary: Equatable, Sendable {
    public let headline: String
    public let coverage: String
    public let flag: String?
}

/// The Monitor's cost list: per-session estimated cost mapped from the token
/// counts the agent reported against the shipped ``PriceTable``. No network,
/// no bill — every figure is an estimate, and a model with no price row reads
/// "unavailable" rather than a guessed number.
///
/// Reachable states are Empty, Loading, Ready, and Failed. There is no Denied:
/// reading recorded sessions is not a gated action, so the user never says no
/// to it — "denial is not failure", and a state with no path is not fabricated.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#the-five-states-every-surface-owes
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-cost-is-measured
@Observable
@MainActor
public final class MonitorCostViewModel {
    public enum State: Equatable, Sendable {
        case empty(MonitorEmptyReason)
        case loading
        case ready([MonitorCostRow])
        case failed(String)
    }

    /// The surface's current state — Empty until records are presented or a
    /// load completes.
    public private(set) var state: State = .empty(.noProject)
    /// The time range and sub-function shown. Held here, not in the view, so
    /// it survives moving to another surface and back.
    public var filter = MonitorFilter()
    /// The pooled overhead across the presented sessions, or `nil` before any
    /// are presented.
    public private(set) var overhead: MonitorOverheadSummary?
    /// The success rate across the presented sessions, or `nil` before any
    /// are presented.
    public private(set) var successRate: MonitorSuccessRateSummary?
    /// The token chart's points, or `nil` before any sessions are presented.
    public private(set) var chart: MonitorTokenChartData?
    private let priceTable: PriceTable
    private let timeZone: TimeZone

    /// Creates the view model over the price table shipped with this build.
    /// `timeZone` is the user's own unless a test pins it.
    public init(priceTable: PriceTable, timeZone: TimeZone = .current) {
        self.priceTable = priceTable
        self.timeZone = timeZone
    }

    /// The date the shipped prices were set, shown so the user knows how
    /// current the estimate's basis is.
    public var pricesEffectiveDate: Date {
        priceTable.effectiveDate
    }

    /// Presents already-loaded records: computes each row's estimate and moves
    /// to Ready, or Empty when there is nothing to show. Synchronous so a test
    /// and the UI-test seed reach a deterministic state without awaiting.
    public func present(_ records: [StoredSessionRecord]) {
        let rows = records.enumerated().map { row(for: $1, position: $0 + 1) }
        overhead = records.isEmpty ? nil : Self.overheadSummary(for: OverheadAggregate(records: records))
        successRate = records.isEmpty ? nil : Self.successRateSummary(for: SessionSuccessRate(records: records))
        chart = records.isEmpty ? nil : MonitorTokenChartData(records: records)
        state = rows.isEmpty ? .empty(.noSessions) : .ready(rows)
    }

    /// Shows the Empty state for a reason that needs no load — no project
    /// chosen yet.
    public func showEmpty(_ reason: MonitorEmptyReason) {
        overhead = nil
        successRate = nil
        chart = nil
        state = .empty(reason)
    }

    /// Loads the chosen project's records over the filter's time range, then
    /// presents those the filter keeps. Moves through Loading to Ready, Empty,
    /// or Failed. A load superseded by a newer one (its task cancelled) leaves
    /// the state to the newer load rather than overwriting it.
    public func load(
        filter: MonitorFilter,
        now: Date = .now,
        from provider: @Sendable (DateInterval) async throws -> [StoredSessionRecord]
    ) async {
        state = .loading
        let interval = filter.timeRange.interval(endingAt: now)
        do {
            let records = try await provider(interval)
            guard !Task.isCancelled else { return }
            present(filter.apply(to: records, now: now))
        } catch is MonitorNotATalosProjectError {
            guard !Task.isCancelled else { return }
            showEmpty(.notATalosProject)
        } catch {
            guard !Task.isCancelled else { return }
            overhead = nil
            successRate = nil
            chart = nil
            state = .failed("Talos could not read this project's session records. Nothing was changed.")
        }
    }

    /// `position` matches the chart's "Session N" bar, so a row and its bar
    /// name each other.
    private func row(for record: StoredSessionRecord, position: Int) -> MonitorCostRow {
        // No token row means no counts to price — an absence, reported as such
        // rather than as a `$0` a user would read as a free session.
        let cost = record.tokenReport.map(priceTable.estimate)
            ?? .unavailable(.tokensUnavailable(.notReported))
        let overhead = SessionOverhead(record: record)
        return MonitorCostRow(
            id: record.id,
            title: "Session \(position) · \(record.subFunction.rawValue) · \(record.agentName)",
            startedSummary: "Started \(startedText(record.startedAt))",
            durationSummary: Self.durationSummary(record.duration),
            outcomeSummary: Self.outcomeSummary(record.outcome),
            tokensSummary: Self.tokensSummary(record.tokenReport),
            costSummary: Self.costSummary(cost),
            overheadSummary: Self.overheadLine(for: overhead),
            overheadSources: overhead.map { Self.sourcesLine($0.injected) },
            overheadFlag: overhead.flatMap { $0.exceedsBudget ? Self.flagCopy : nil }
        )
    }

    private func startedText(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    // MARK: Duration and outcome

    /// Whole seconds, hours and minutes only when present. The recorded
    /// duration is net of time awaiting a decision, so the line says so.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#monitor-screen
    public static func durationSummary(_ duration: TimeInterval) -> String {
        "Duration: \(durationText(duration)), excluding time awaiting a decision"
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let seconds = Int(duration.rounded())
        guard seconds >= 1 else { return "less than 1 s" }
        let hours = seconds / secondsPerHour
        let minutes = (seconds % secondsPerHour) / secondsPerMinute
        let remainder = seconds % secondsPerMinute
        var parts: [String] = []
        if hours > 0 {
            parts.append("\(hours) h")
        }
        if hours > 0 || minutes > 0 {
            parts.append("\(minutes) min")
        }
        parts.append("\(remainder) s")
        return parts.joined(separator: " ")
    }

    private static let secondsPerMinute = 60
    private static let secondsPerHour = 3600

    /// `Succeeded` is stated as a clean exit, never as correct work; a denial
    /// is recorded as denied, not as an error.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-task-outcome-is-classified
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#denial-is-not-failure
    public static func outcomeSummary(_ outcome: SessionOutcomeClassification) -> String {
        switch outcome {
        case .succeeded: "Outcome: Succeeded — the agent exited cleanly"
        case .failed: "Outcome: Failed"
        case .denied: "Outcome: Denied — recorded as denied, not as an error"
        case .stopped: "Outcome: Stopped by the user"
        }
    }

    /// `Succeeded ÷ (Succeeded + Failed)`, with Denied and Stopped counted
    /// where the figure appears rather than dropped silently.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-task-outcome-is-classified
    static func successRateSummary(for rate: SessionSuccessRate) -> MonitorSuccessRateSummary {
        let exclusions = exclusionsLine(for: rate)
        guard let fraction = rate.fraction else {
            return MonitorSuccessRateSummary(
                headline: "Success rate unavailable — no session in this range succeeded or failed",
                caveat: nil,
                exclusions: exclusions
            )
        }
        let percent = Int((fraction * percentScale).rounded())
        let noun = rate.ratedCount == 1 ? "rated session" : "rated sessions"
        return MonitorSuccessRateSummary(
            headline: "Success rate: \(percent)% (\(rate.succeeded) of \(rate.ratedCount) \(noun) exited cleanly)",
            caveat: "Succeeded means the agent exited cleanly, not that the task was right.",
            exclusions: exclusions
        )
    }

    private static func exclusionsLine(for rate: SessionSuccessRate) -> String? {
        guard rate.excludedCount > 0 else { return nil }
        let parts = [(rate.denied, "denied"), (rate.stopped, "stopped")]
            .filter { $0.0 > 0 }
            .map { "\($0.0) \($0.1)" }
        return "\(rate.excludedCount) excluded from the rate: \(parts.joined(separator: ", "))."
    }

    // MARK: Talos-added token overhead

    /// "Estimated" every time: the numerator is Talos's own count of what it
    /// injected, while the denominator is the agent's exact count.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-token-overhead-is-computed
    static func overheadLine(for overhead: SessionOverhead?) -> String {
        guard let overhead else {
            return "Estimated Talos-added token overhead unavailable — no session token count or injected-token record"
        }
        return "Estimated Talos-added token overhead: \(percent(overhead.ratio)) "
            + "(\(overhead.injected.total) of \(overhead.sessionTokens) session tokens)"
    }

    static func sourcesLine(_ injected: InjectedTokens) -> String {
        injected.orderedSources.map { "\($0.label) \($0.tokens)" }.joined(separator: " · ")
    }

    static func overheadSummary(for aggregate: OverheadAggregate) -> MonitorOverheadSummary {
        let coverage = "Computed from \(aggregate.measuredCount) \(sessionWord(aggregate.measuredCount)); "
            + "\(aggregate.excludedCount) excluded (no session token count or injected-token record)."
        guard let ratio = aggregate.ratio else {
            return MonitorOverheadSummary(
                headline: "Estimated Talos-added token overhead unavailable — no measurable sessions",
                coverage: coverage,
                flag: nil
            )
        }
        return MonitorOverheadSummary(
            headline: "Estimated Talos-added token overhead: \(percent(ratio)) of session tokens",
            coverage: coverage,
            flag: aggregate.exceedsBudget ? flagCopy : nil
        )
    }

    static let flagCopy = "Over the 5% token-overhead budget"

    private static func sessionWord(_ count: Int) -> String {
        count == 1 ? "session" : "sessions"
    }

    /// One decimal place, in the POSIX locale so the same figure reads the
    /// same on every host.
    private static func percent(_ ratio: Double) -> String {
        String(format: "%.1f%%", ratio * percentScale)
    }

    private static let percentScale = 100.0

    /// A run with no token row shows its absence named, never a zero.
    static func tokensSummary(_ report: TokenReport?) -> String {
        switch report {
        case let .measured(counts, model):
            "\(counts.input) input · \(counts.output) output tokens (\(model))"
        case let .unavailable(unavailable):
            "Token usage unavailable — \(tokenReasonCopy(unavailable.reason))"
        case nil:
            "No token usage recorded"
        }
    }

    /// "Estimated cost" every time — never "Cost", never a bare number a user
    /// reconciles against an invoice. An unavailable estimate says why on its
    /// own line and never inherits a neighbour's figure.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice#cost-copy
    static func costSummary(_ estimate: CostEstimate) -> String {
        switch estimate {
        case let .estimated(amount):
            "Estimated cost: \(currency(amount))"
        case let .unavailable(reason):
            "Estimated cost unavailable — \(costReasonCopy(reason))"
        }
    }

    private static func costReasonCopy(_ reason: CostUnavailableReason) -> String {
        switch reason {
        case let .unknownModel(model):
            "no price for \(model)"
        case let .tokensUnavailable(tokenReason):
            tokenReasonCopy(tokenReason)
        }
    }

    private static func tokenReasonCopy(_ reason: TokenUsageUnavailableReason) -> String {
        switch reason {
        case .notReported: "not yet reported"
        case .unrecognizedFormat: "session log format not recognized"
        }
    }

    /// USD, the currency the shipped prices are quoted in, with up to four
    /// fraction digits so a small-but-real estimate is not rounded to `$0.00`
    /// — which would read as a measured zero.
    private static func currency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = minimumCostFractionDigits
        formatter.maximumFractionDigits = maximumCostFractionDigits
        return formatter.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }

    private static let minimumCostFractionDigits = 2
    private static let maximumCostFractionDigits = 4
}
