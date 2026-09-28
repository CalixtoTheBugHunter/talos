@testable import TalosAdapters
import Testing

/// Asserts ``ClaudeCodeTokenReporter`` and the `result`-line parse behind it —
/// measured, absent-and-named, or drift, never a repaired or zeroed count.
/// > A token count Talos cannot parse is absent and named. It is never
/// > repaired, inferred, or shown as zero.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#when-the-log-format-changes
@Suite("Claude Code token report")
struct ClaudeCodeTokenReportTests {
    @Test("A turn's usage is measured, with the model read at session start")
    func measuredReport() {
        var reporter = ClaudeCodeTokenReporter()
        reporter.recordSessionStart(model: "global.anthropic.claude-opus-5", version: "2.1.246")
        reporter.recordUsage(input: 2, output: 89, cacheCreation: nil, cacheRead: nil)

        let expected = TokenReport.measured(TokenCounts(input: 2, output: 89), model: "global.anthropic.claude-opus-5")
        #expect(reporter.report() == expected)
    }

    @Test("Usage across two turns accumulates rather than replacing")
    func accumulatesAcrossTurns() {
        var reporter = ClaudeCodeTokenReporter()
        reporter.recordSessionStart(model: "global.anthropic.claude-opus-5", version: "2.1.246")
        reporter.recordUsage(input: 2, output: 89, cacheCreation: nil, cacheRead: nil)
        reporter.recordUsage(input: 2, output: 4, cacheCreation: nil, cacheRead: nil)

        let expected = TokenReport.measured(TokenCounts(input: 4, output: 93), model: "global.anthropic.claude-opus-5")
        #expect(reporter.report() == expected)
    }

    /// Cache-write and cache-read are distinguished from input/output where the
    /// agent reports them, and accumulate across turns on their own axes rather
    /// than being folded into the input count.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-cost-is-measured
    @Test("Cache counts are distinguished and accumulate on their own axes")
    func cacheDistinguishedAndAccumulated() {
        var reporter = ClaudeCodeTokenReporter()
        reporter.recordSessionStart(model: "global.anthropic.claude-opus-5", version: "2.1.246")
        reporter.recordUsage(input: 2, output: 4, cacheCreation: 2637, cacheRead: 16509)
        reporter.recordUsage(input: 3, output: 7, cacheCreation: 100, cacheRead: 900)

        let expected = TokenReport.measured(
            TokenCounts(input: 5, output: 11, cacheCreation: 2737, cacheRead: 17409),
            model: "global.anthropic.claude-opus-5"
        )
        #expect(reporter.report() == expected)
    }

    /// A turn that names no cache leaves the counts absent, not a measured zero —
    /// the same honesty the report owes input/output.
    @Test("Absent cache is nil, never a zero")
    func absentCacheIsNilNotZero() {
        var reporter = ClaudeCodeTokenReporter()
        reporter.recordSessionStart(model: "global.anthropic.claude-opus-5", version: "2.1.246")
        reporter.recordUsage(input: 2, output: 4, cacheCreation: nil, cacheRead: nil)

        guard case let .measured(counts, _) = reporter.report() else {
            Issue.record("expected a measured report")
            return
        }
        #expect(counts.cacheCreation == nil)
        #expect(counts.cacheRead == nil)
    }

    /// The `result` line's own cache fields decode into the usage value —
    /// distinguished at the parse, not reconstructed downstream.
    @Test("A result line's cache counts decode onto the usage value")
    func decodeResultCarriesCacheCounts() {
        let line = #"{"type":"result","usage":{"input_tokens":2,"output_tokens":4,"#
            + #""cache_creation_input_tokens":2637,"cache_read_input_tokens":16509}}"#
        let value = ClaudeCodeStreamDecoder.decode(line)
        #expect(value == .usage(input: 2, output: 4, cacheCreation: 2637, cacheRead: 16509))
    }

    /// A `result` line reporting input/output but no cache fields decodes with
    /// nil cache — present where the agent reports it, absent where it does not.
    @Test("A result line without cache fields decodes with nil cache")
    func decodeResultWithoutCacheIsNil() {
        let value = ClaudeCodeStreamDecoder.decode(
            #"{"type":"result","usage":{"input_tokens":2,"output_tokens":4}}"#
        )
        #expect(value == .usage(input: 2, output: 4, cacheCreation: nil, cacheRead: nil))
    }

    @Test("No turn measured yet is absent and named, never a zero")
    func notReported() {
        var reporter = ClaudeCodeTokenReporter()
        reporter.recordSessionStart(model: "global.anthropic.claude-opus-5", version: "2.1.246")

        #expect(reporter.report() == .unavailable(TokenUsageUnavailable(reason: .notReported, agentVersion: "2.1.246")))
    }

    @Test("A usage shape this parse does not recognize is a drift, and carries the version")
    func unrecognizedFormatCarriesTheVersion() {
        var reporter = ClaudeCodeTokenReporter()
        reporter.recordSessionStart(model: "global.anthropic.claude-opus-5", version: "2.1.246")
        reporter.recordUsage(input: 2, output: 89, cacheCreation: nil, cacheRead: nil)
        reporter.recordUnrecognizedUsage()

        let unavailable = TokenUsageUnavailable(reason: .unrecognizedFormat, agentVersion: "2.1.246")
        #expect(reporter.report() == .unavailable(unavailable))
    }

    @Test("A result line missing usage entirely decodes to nothing rather than a drift")
    func missingUsageKeyIsIgnoredNotUnrecognized() {
        let value = ClaudeCodeStreamDecoder.decode(#"{"type":"result","subtype":"success","stop_reason":"end_turn"}"#)
        #expect(value == .ignored)
    }

    @Test("A result line whose usage counts are not integers is a drift")
    func malformedUsageShapeIsUnrecognized() {
        let value = ClaudeCodeStreamDecoder.decode(#"{"type":"result","usage":{"input_tokens":"a lot"}}"#)
        #expect(value == .unrecognizedUsage)
    }
}
