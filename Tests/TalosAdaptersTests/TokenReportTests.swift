import Foundation
@testable import TalosAdapters
import Testing

/// Verifies ``TokenReport`` against § The adapter reports tokens as structured
/// data, and § When the log format changes.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#when-the-log-format-changes
///
/// > **Token usage crosses the adapter boundary as structured data — counts and
/// > a model name — never as text for Talos core to parse.**
@Suite("Token report")
struct TokenReportTests {
    // MARK: - Structured data, with the agent's own model name (AC4)

    /// The counts and the model name are both values. The name is what selects
    /// a price table, and it comes from the agent's own report — never inferred
    /// and never hardcoded, because counts are "Accurate — reported by the
    /// agent itself".
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-cost-is-measured
    @Test("A measured report carries counts and the model name the agent reported")
    func aMeasuredReportCarriesCountsAndTheModelName() {
        let report = TokenReport.measured(TokenCounts(input: 1200, output: 340), model: "reported-model-name")

        guard case let .measured(counts, model) = report else {
            Issue.record("Expected a measured report")
            return
        }
        #expect(counts.input == 1200)
        #expect(counts.output == 340)
        #expect(model == "reported-model-name")
    }

    // MARK: - An absence stays an absence (AC4)

    /// > A token count Talos cannot parse is absent and named. It is never
    /// > repaired, inferred, or shown as zero.
    ///
    /// The regression this asserts: an unavailable report is not equal to a
    /// zeroed measured one, so no downstream reader can mistake one for the
    /// other. `TokenCounts(input: 0, output: 0)` type-checks and aggregates,
    /// which is exactly why it must not be reachable as the failure spelling.
    @Test("An unavailable report is not a zeroed measured report")
    func anUnavailableReportIsNotAZeroedMeasuredReport() {
        let unavailable = TokenReport.unavailable(TokenUsageUnavailable(reason: .unrecognizedFormat))
        let zeroed = TokenReport.measured(TokenCounts(input: 0, output: 0), model: "reported-model-name")

        #expect(unavailable != zeroed)
    }

    /// > On every affected number, wherever it is read: the figure is
    /// > unavailable, **and the reason**.
    ///
    /// The reason is typed rather than a message string, so producing the label
    /// never requires core to learn a log format.
    @Test("An unavailable report names why, as a typed reason")
    func anUnavailableReportNamesWhyAsATypedReason() {
        let report = TokenReport.unavailable(TokenUsageUnavailable(reason: .notReported))

        guard case let .unavailable(absence) = report else {
            Issue.record("Expected an unavailable report")
            return
        }
        #expect(absence.reason == .notReported)
        #expect(absence.reason != .unrecognizedFormat)
    }

    /// > One persistent banner on the Monitor … the agent, **the version the
    /// > parse stopped working at**, and how many sessions are affected.
    ///
    /// An adapter that knew only *that* the parse failed could not support that
    /// banner, so the version travels with the absence.
    @Test("An unavailable report carries the agent version the parse stopped working at")
    func anUnavailableReportCarriesTheAgentVersion() {
        let report = TokenReport.unavailable(
            TokenUsageUnavailable(reason: .unrecognizedFormat, agentVersion: "3.4.1")
        )

        guard case let .unavailable(absence) = report else {
            Issue.record("Expected an unavailable report")
            return
        }
        #expect(absence.agentVersion == "3.4.1")
    }

    /// Two absences that differ only in reason are different values, so a
    /// reason is never lost by being folded into a generic failure.
    @Test("Two absences with different reasons are different values")
    func twoAbsencesWithDifferentReasonsDiffer() {
        let notReported = TokenReport.unavailable(TokenUsageUnavailable(reason: .notReported, agentVersion: "3.4.1"))
        let drifted = TokenReport.unavailable(TokenUsageUnavailable(reason: .unrecognizedFormat, agentVersion: "3.4.1"))

        #expect(notReported != drifted)
    }

    // MARK: - Usage reporting gates nothing (AC4)

    /// > **The session still runs.** A failed parse is the Monitor losing an
    /// > input, not the agent losing the right to work.
    ///
    /// Reporting an unavailable count leaves every other capability working —
    /// the run keeps streaming and keeps accepting prompts.
    @Test("A run whose token usage cannot be parsed keeps running")
    func aRunWhoseUsageCannotBeParsedKeepsRunning() async throws {
        let adapter = FakeAdapter()
        let stream = try await adapter.launch(TestLaunch.configuration())
        var events = stream.makeAsyncIterator()

        await adapter.setUsage(.unavailable(TokenUsageUnavailable(reason: .unrecognizedFormat, agentVersion: "3.4.1")))

        guard case .unavailable = await adapter.tokenUsage() else {
            Issue.record("Expected the usage to be unavailable")
            return
        }
        #expect(await adapter.isTerminated == false)

        try await adapter.send(AgentPrompt(text: "keep going"))
        await adapter.emit(.output(AgentOutputChunk(channel: .standardOutput, text: "still streaming")))
        #expect(try await events.next() == .output(AgentOutputChunk(channel: .standardOutput, text: "still streaming")))
    }

    /// ``tokenUsage()`` cannot throw and cannot fail, so no caller has to treat
    /// a missing count as an error condition of the run.
    @Test("Reporting usage never fails, it reports an absence")
    func reportingUsageNeverFails() async throws {
        let adapter = FakeAdapter(usage: .unavailable(TokenUsageUnavailable(reason: .notReported)))
        _ = try await adapter.launch(TestLaunch.configuration())

        #expect(await adapter.tokenUsage() == .unavailable(TokenUsageUnavailable(reason: .notReported)))
    }
}
