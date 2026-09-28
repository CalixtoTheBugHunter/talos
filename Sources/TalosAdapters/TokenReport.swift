import Foundation

/// Token counts as the agent itself reported them. Nothing here is derived:
/// a count Talos reconstructed would be Talos's number wearing the agent's
/// label, and every figure derived from it inherits the error while still
/// reading as an estimate of something measured.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-cost-is-measured
public struct TokenCounts: Equatable, Hashable, Sendable {
    public let input: Int
    public let output: Int
    /// Cache-write and cache-read counts, distinguished only where the agent
    /// reports them: `nil` means the agent named no cache usage, never a
    /// measured zero. Kept apart from `input`/`output` because a cache read is
    /// priced far below a fresh input token, so folding them together would
    /// make the cost estimate derived from these wrong.
    public let cacheCreation: Int?
    public let cacheRead: Int?

    public init(input: Int, output: Int, cacheCreation: Int? = nil, cacheRead: Int? = nil) {
        self.input = input
        self.output = output
        self.cacheCreation = cacheCreation
        self.cacheRead = cacheRead
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
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
public enum TokenReport: Equatable, Hashable, Sendable {
    /// Counts the agent reported, with the model name that selects a price
    /// table. The name comes from the agent's own report — never inferred,
    /// never hardcoded.
    case measured(TokenCounts, model: String)
    /// No count, and why. The run is unaffected: usage reporting gates none
    /// of the other capabilities.
    case unavailable(TokenUsageUnavailable)
}
