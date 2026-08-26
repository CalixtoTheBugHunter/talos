import Foundation
import Testing

/// Asserts the adapter layer wakes on events and never on a clock.
///
/// > A live indicator updates from an **event** — a streamed token, a tool call,
/// > a session record — never from a timer that wakes to check. A spinner that
/// > costs CPU while idle fails a release gate.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#nothing-polls
///
/// The budget row it protects is a prohibition rather than a threshold — "Idle
/// CPU | ~0%, **no polling timers**" — so the presence of the timer is the
/// finding and there is no interval to measure.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#budgets-that-make-the-above-testable
///
/// Checked by reading the source because measuring idle CPU is a release gate
/// under Instruments rather than something a unit test can claim. This asserts
/// the design that gate depends on: there is no poll to measure.
///
/// **It reads the module root only** — the scope set by
/// https://github.com/CalixtoTheBugHunter/talos/issues/52, and where every file
/// in the module lives today. A concrete adapter in a subdirectory of its own is
/// not covered, and this suite would be green if one polled.
@Suite("Nothing in the adapter layer polls")
struct NoPollingTimerTests {
    /// Spellings that only appear in code that waits on a clock. Matched
    /// case-sensitively: the SPEC line quoted above is itself the phrase
    /// "no polling timers", and the module's comments cite it, so a
    /// case-insensitive scan would flag the citation rather than a poll.
    static let forbiddenSpellings = [
        "Timer",
        "DispatchSourceTimer",
        "makeTimerSource",
        "Task.sleep",
        "sleep(",
        "usleep",
        "nanosleep",
        "DispatchQueue.main.asyncAfter",
        "asyncAfter"
    ]

    /// Drops everything after `//` before scanning: the module's own doc comments
    /// quote the SPEC line by name, and a comment cannot poll.
    static func code(_ source: String) -> String {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                guard let comment = line.range(of: "//") else { return line }
                return line[line.startIndex ..< comment.lowerBound]
            }
            .joined(separator: "\n")
    }

    /// Discovered rather than listed;
    /// ``NoAgentOrProviderReferenceTests/everyRootFileIsAListedContractFile()``
    /// keeps that set honest.
    static var moduleFiles: [URL] {
        get throws {
            try FileManager.default
                .contentsOfDirectory(
                    at: NoAgentOrProviderReferenceTests.moduleURL,
                    includingPropertiesForKeys: nil
                )
                .filter { $0.pathExtension == "swift" }
        }
    }

    /// Catches the regression that ships looking correct: a `DispatchSourceTimer`
    /// checking every 100 ms whether the child wrote anything. It streams, it
    /// passes every other assertion here, and it burns CPU with no session open.
    @Test("No file in the adapter layer waits on a clock")
    func noFileWaitsOnAClock() throws {
        let files = try Self.moduleFiles
        // A discovery that found nothing would make every assertion below
        // vacuous.
        #expect(!files.isEmpty)

        for file in files {
            let source = try Self.code(String(contentsOf: file, encoding: .utf8))
            for spelling in Self.forbiddenSpellings {
                #expect(
                    !source.contains(spelling),
                    "\(file.lastPathComponent) contains '\(spelling)' — this layer wakes on events, never on a clock"
                )
            }
        }
    }
}
