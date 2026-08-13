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

    @Test("A long opaque token with no recognized prefix is still redacted")
    func opaqueLongTokenIsRedacted() {
        let token = String(repeating: "x9Z", count: 12)
        let redacted = LogRedaction.redacted("session token \(token) accepted")
        #expect(!redacted.contains(token))
    }
}
