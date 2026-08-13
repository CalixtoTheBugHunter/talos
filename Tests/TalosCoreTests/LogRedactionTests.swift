@testable import TalosCore
import Testing

/// Verifies "Secrets, tokens, and prompt contents are never logged; a
/// redaction helper exists" from
/// https://github.com/CalixtoTheBugHunter/talos/issues/39.
@Suite("LogRedaction")
struct LogRedactionTests {
    @Test(
        "Secret-shaped substrings are redacted",
        arguments: [
            "sk-ant-api03-" + String(repeating: "A", count: 28),
            "sk-" + String(repeating: "A", count: 40),
            "AIza" + String(repeating: "B", count: 35),
            "AKIA" + String(repeating: "C", count: 16),
            "ghp_" + String(repeating: "D", count: 20),
            "github_pat_" + String(repeating: "E", count: 22),
            "glpat-" + String(repeating: "F", count: 20),
            "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9abcdefghijklmnop"
        ]
    )
    func secretShapedLiteralsAreRedacted(secret: String) {
        let redacted = LogRedaction.redacted("token=\(secret)")
        #expect(!redacted.contains(secret))
        #expect(redacted.contains("<redacted>"))
    }

    @Test("Ordinary prose passes through unchanged")
    func ordinaryProseIsUnchanged() {
        let text = "Session started for project talos, agent claude-code, tool call file.read"
        #expect(LogRedaction.redacted(text) == text)
    }

    /// A UUID and a hex digest are the same shape a blanket "long
    /// alphanumeric run" filter would also catch — and exactly the kind of
    /// non-secret diagnostic identifier a log line exists to carry. This is
    /// the regression test for that false positive: neither identifier
    /// carries a recognized secret prefix, so both must survive intact.
    @Test(
        "Benign long identifiers with no secret shape are not redacted",
        arguments: [
            "550e8400-e29b-41d4-a716-446655440000",
            String(repeating: "a1b2c3d4", count: 5)
        ]
    )
    func benignLongIdentifiersAreNotRedacted(identifier: String) {
        let text = "session \(identifier) started"
        #expect(LogRedaction.redacted(text) == text)
    }
}
