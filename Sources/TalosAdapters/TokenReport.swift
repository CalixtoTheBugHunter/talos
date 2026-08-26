import Foundation

// How token usage crosses the adapter boundary: counts and a model name, as
// values. The parse that produced them stays inside the adapter, and an
// unparsable count stays absent rather than becoming a number.
// § The adapter reports tokens as structured data —
// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#when-the-log-format-changes

/// Token counts as the agent itself reported them. Nothing here is derived:
/// a count Talos reconstructed would be Talos's number wearing the agent's
/// label, and every figure derived from it inherits the error while still
/// reading as an estimate of something measured.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-cost-is-measured
public struct TokenCounts: Equatable, Hashable, Sendable {
    public let input: Int
    public let output: Int

    public init(input: Int, output: Int) {
        self.input = input
        self.output = output
    }
}

/// Why a token count is unavailable. Typed rather than a message string, on
/// the same terms as the counts: a reason core has to parse is the log-format
/// knowledge that belongs inside the adapter.
public enum TokenUsageUnavailableReason: Equatable, Hashable, Sendable {
    /// The agent's output was read but reported no usage.
    case notReported
    /// Usage was present in a shape this adapter's parse does not recognize —
    /// the drift case.
    case unrecognizedFormat
}

/// A token count that could not be produced, named. Carries the version so
/// the Monitor's banner can state "the version the parse stopped working at"
/// without learning a log format.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#when-the-log-format-changes
public struct TokenUsageUnavailable: Equatable, Hashable, Sendable {
    public let reason: TokenUsageUnavailableReason
    /// The agent CLI version the run used, as the CLI reports it. `nil` when
    /// the adapter could not determine one — an absence, again, rather than a
    /// guess.
    public let agentVersion: String?

    public init(reason: TokenUsageUnavailableReason, agentVersion: String? = nil) {
        self.reason = reason
        self.agentVersion = agentVersion
    }
}

/// What an adapter reports for a run's token usage.
///
/// Two cases rather than counts with a failure flag, so an unparsable count
/// cannot be spelled as a number: `TokenCounts(input: 0, output: 0)` is
/// indistinguishable downstream from a run that genuinely used nothing, and
/// the SPEC forbids showing an absence as zero.
///
/// > A token count Talos cannot parse is absent and named. It is never
/// > repaired, inferred, or shown as zero.
///
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#when-the-log-format-changes
public enum TokenReport: Equatable, Hashable, Sendable {
    /// Counts the agent reported, with the model name that selects a price
    /// table. The name comes from the agent's own report — never inferred,
    /// never hardcoded.
    case measured(TokenCounts, model: String)
    /// No count, and why. The run is unaffected: usage reporting gates none
    /// of the other capabilities.
    case unavailable(TokenUsageUnavailable)
}
