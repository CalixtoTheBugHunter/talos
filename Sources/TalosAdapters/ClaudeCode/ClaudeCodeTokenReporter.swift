import Foundation

/// Accumulates ``TokenReport`` across every `claude` process one
/// ``ClaudeCodeAdapter`` session runs — one per turn, since each is a fresh
/// headless invocation reporting only its own turn's usage.
///
/// Each number is `result`'s own reported field — `usage.input_tokens`,
/// `usage.output_tokens`, and the two cache counts kept distinct from them.
/// Cache is never folded into input/output: that would be Talos doing
/// arithmetic the agent didn't report. A cache count stays `nil` until a turn
/// reports one, so an agent that names no cache is an absence rather than zero.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-cost-is-measured
struct ClaudeCodeTokenReporter: Equatable, Sendable {
    private var input = 0
    private var output = 0
    private var cacheCreation: Int?
    private var cacheRead: Int?
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

    mutating func recordUsage(input: Int, output: Int, cacheCreation: Int?, cacheRead: Int?) {
        hasMeasuredAnyTurn = true
        self.input += input
        self.output += output
        if let cacheCreation {
            self.cacheCreation = (self.cacheCreation ?? 0) + cacheCreation
        }
        if let cacheRead {
            self.cacheRead = (self.cacheRead ?? 0) + cacheRead
        }
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
        let counts = TokenCounts(input: input, output: output, cacheCreation: cacheCreation, cacheRead: cacheRead)
        return .measured(counts, model: model)
    }
}
