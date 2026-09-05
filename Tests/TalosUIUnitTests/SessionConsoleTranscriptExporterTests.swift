import TalosAdapters
import TalosSafeguards
import TalosUI
import Testing

/// "Export produces a readable file (Markdown) including tool calls and
/// approvals" and "export never includes secret values."
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
@Suite("Session console transcript exporter")
struct SessionConsoleTranscriptExporterTests {
    @Test("Output lines render as prose, in order")
    func outputRendersAsProse() {
        let lines = [
            SessionConsoleLine(id: 0, content: .output(OutputElement(kind: .markdown, payload: "First line."))),
            SessionConsoleLine(id: 1, content: .output(OutputElement(kind: .markdown, payload: "Second line.")))
        ]

        let markdown = SessionConsoleTranscriptExporter.markdown(for: lines)

        #expect(markdown.contains("First line."))
        #expect(markdown.contains("Second line."))
        guard let firstRange = markdown.range(of: "First line."), let secondRange = markdown.range(of: "Second line.")
        else {
            Issue.record("Expected both lines to appear in the exported text")
            return
        }
        #expect(firstRange.lowerBound < secondRange.lowerBound)
    }

    @Test("A resolved tool call names its outcome and tier")
    func resolvedToolCallNamesOutcomeAndTier() {
        let call = SessionConsoleToolCall(
            callID: "t1",
            name: "Delete",
            targets: ["build/"],
            approval: .resolved(action: .fileDelete, tier: .irreversible, outcome: .denied)
        )
        let lines = [SessionConsoleLine(id: 0, content: .toolCall(call))]

        let markdown = SessionConsoleTranscriptExporter.markdown(for: lines)

        #expect(markdown.contains("Delete build/"))
        #expect(markdown.contains("Denied"))
        #expect(markdown.contains("Irreversible"))
    }

    @Test("A never-gated tool call names no outcome")
    func notGatedToolCallNamesNoOutcome() {
        let call = SessionConsoleToolCall(callID: "t1", name: "Read", targets: ["README.md"])
        let lines = [SessionConsoleLine(id: 0, content: .toolCall(call))]

        let markdown = SessionConsoleTranscriptExporter.markdown(for: lines)

        #expect(markdown.contains("Read README.md"))
        #expect(!markdown.contains("Allowed"))
        #expect(!markdown.contains("Denied"))
    }

    @Test("A secret-shaped string in output is redacted in the exported text")
    func secretShapedOutputIsRedacted() {
        let secret = "sk-ant-\(String(repeating: "a", count: 20))"
        let lines = [
            SessionConsoleLine(id: 0, content: .output(OutputElement(kind: .markdown, payload: "Key: \(secret)")))
        ]

        let markdown = SessionConsoleTranscriptExporter.markdown(for: lines)

        #expect(!markdown.contains(secret))
        #expect(markdown.contains("<redacted>"))
    }
}
