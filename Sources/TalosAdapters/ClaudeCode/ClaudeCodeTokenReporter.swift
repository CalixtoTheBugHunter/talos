import Foundation

// Turning what Claude Code itself reported into a ``TokenReport``. The two
// numbers come from one `result` line's own `usage.input_tokens` and
// `usage.output_tokens` — never summed from the sub-fields cache reads and
// cache writes are broken into, which would be Talos doing arithmetic the
// agent did not report.
// § Token counts — Accurate — reported by the agent itself —
// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-cost-is-measured

/// Accumulates ``TokenReport`` across every `claude` process one
/// ``ClaudeCodeAdapter`` session runs — one per turn, since each is a fresh
/// headless invocation reporting only its own turn's usage.
struct ClaudeCodeTokenReporter: Equatable, Sendable {
    private var counts = TokenCounts(input: 0, output: 0)
    private var model: String?
    private var agentVersion: String?
    private var hasMeasuredAnyTurn = false
    private var sawUnrecognizedUsage = false

    /// Read once, from the most recent `system/init` — the model the run so
    /// far actually used, never inferred or hardcoded.
    mutating func recordSessionStart(model: String, version: String) {
        self.model = model
        agentVersion = version
    }

    /// Adds one turn's counts to the running total.
    mutating func recordUsage(input: Int, output: Int) {
        hasMeasuredAnyTurn = true
        counts = TokenCounts(input: counts.input + input, output: counts.output + output)
    }

    /// A `result` line reported usage in a shape this parse does not
    /// recognize. Sticky for the rest of the session: a report that flips
    /// back to measured after a drift would hide the turn it could not read.
    mutating func recordUnrecognizedUsage() {
        sawUnrecognizedUsage = true
    }

    func report() -> TokenReport {
        guard !sawUnrecognizedUsage else {
            return .unavailable(TokenUsageUnavailable(reason: .unrecognizedFormat, agentVersion: agentVersion))
        }
        guard hasMeasuredAnyTurn, let model else {
            return .unavailable(TokenUsageUnavailable(reason: .notReported, agentVersion: agentVersion))
        }
        return .measured(counts, model: model)
    }
}
