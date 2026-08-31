import Foundation
import Testing

/// Asserts nothing in the orchestration layer waits on a clock, which is what an
/// inert scheduler has to cost while it is inert.
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
/// **It reads the module root only**, where every file in the module lives
/// today. A file in a subdirectory of its own is not covered, and this suite
/// would be green if one polled.
@Suite("Nothing in the orchestration layer polls")
struct NoSchedulerPollingTests {
    /// Spellings that only appear in code that waits on a clock. Matched
    /// case-sensitively: the SPEC line quoted above is itself the phrase "no
    /// polling timers", and the module's comments cite it, so a
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
        "asyncAfter",
        "ContinuousClock",
        "SuspendingClock"
    ]

    static var moduleURL: URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
                    .appendingPathComponent("Sources")
                    .appendingPathComponent("TalosOrchestration")
            }
        }
        fatalError("Could not locate the repository root above \(#filePath)")
    }

    /// Drops everything after `//` before scanning: the module's own doc
    /// comments quote the SPEC line by name, and a comment cannot poll.
    static func code(_ source: String) -> String {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                guard let comment = line.range(of: "//") else { return line }
                return line[line.startIndex ..< comment.lowerBound]
            }
            .joined(separator: "\n")
    }

    /// Catches the regression that ships looking correct: an inert scheduler
    /// that wakes every minute to find it has nothing to fire. It emits nothing,
    /// it passes every other assertion here, and it burns CPU with no session
    /// open.
    @Test("No file in the orchestration layer waits on a clock")
    func noFileWaitsOnAClock() throws {
        let files = try FileManager.default
            .contentsOfDirectory(at: Self.moduleURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
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
