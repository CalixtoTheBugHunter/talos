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
    /// The token counts the estimate is mapped from, stated plainly, or their
    /// named absence. Token counts are exact, so they may be shown as numbers.
    public let tokensSummary: String
    /// The cost line, always labeled an estimate and never a bill.
    public let costSummary: String
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
        case empty
        case loading
        case ready([MonitorCostRow])
        case failed(String)
    }

    /// The surface's current state — Empty until records are presented or a
    /// load completes.
    public private(set) var state: State = .empty
    private let priceTable: PriceTable

    /// Creates the view model over the price table shipped with this build.
    public init(priceTable: PriceTable) {
        self.priceTable = priceTable
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
        let rows = records.map { row(for: $0) }
        state = rows.isEmpty ? .empty : .ready(rows)
    }

    /// Loads records from an async provider — the project-and-time-range query
    /// a later project-selection flow drives. Moves through Loading to Ready,
    /// Empty, or Failed. The live surface stays Empty until that flow calls
    /// this, since there is no project selected to query for yet.
    public func load(from provider: @Sendable () async throws -> [StoredSessionRecord]) async {
        state = .loading
        do {
            try await present(provider())
        } catch {
            state = .failed("Talos could not read this project's session records.")
        }
    }

    private func row(for record: StoredSessionRecord) -> MonitorCostRow {
        // No token row means no counts to price — an absence, reported as such
        // rather than as a `$0` a user would read as a free session.
        let cost = record.tokenReport.map(priceTable.estimate)
            ?? .unavailable(.tokensUnavailable(.notReported))
        return MonitorCostRow(
            id: record.id,
            title: "\(record.subFunction.rawValue) · \(record.agentName)",
            tokensSummary: Self.tokensSummary(record.tokenReport),
            costSummary: Self.costSummary(cost)
        )
    }

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
