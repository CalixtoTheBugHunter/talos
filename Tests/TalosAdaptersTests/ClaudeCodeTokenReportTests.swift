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
        reporter.recordUsage(input: 2, output: 89)

        let expected = TokenReport.measured(TokenCounts(input: 2, output: 89), model: "global.anthropic.claude-opus-5")
        #expect(reporter.report() == expected)
    }

    @Test("Usage across two turns accumulates rather than replacing")
    func accumulatesAcrossTurns() {
        var reporter = ClaudeCodeTokenReporter()
        reporter.recordSessionStart(model: "global.anthropic.claude-opus-5", version: "2.1.246")
        reporter.recordUsage(input: 2, output: 89)
        reporter.recordUsage(input: 2, output: 4)

        let expected = TokenReport.measured(TokenCounts(input: 4, output: 93), model: "global.anthropic.claude-opus-5")
        #expect(reporter.report() == expected)
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
        reporter.recordUsage(input: 2, output: 89)
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
