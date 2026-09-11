import Foundation
import Testing

/// Asserts nothing in the orchestration layer polls — no timer, no scheduler,
/// no interval wait — which is what an inert scheduler has to cost while it is
/// inert. The one sanctioned clock use is the response-liveness deadline of
/// decision 81 (see ``sleepSpellings``): a one-shot wait cancelled the instant
/// an event arrives, not a poll.
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
/// It reads the module's whole subtree rather than its root: a scan a new
/// directory can step outside of guarantees only as much as the layout it
/// happened to be written against.
@Suite("Nothing in the orchestration layer polls")
struct NoSchedulerPollingTests {
    /// Periodic-wait spellings — a timer, a scheduler, an interval sleep.
    /// Forbidden throughout the layer with no exception: these are the shape of
    /// a poll. Matched case-sensitively, since the SPEC line quoted above is
    /// itself "no polling timers" and the module's comments cite it, so a
    /// case-insensitive scan would flag the citation rather than a poll.
    static let pollingSpellings = [
        "Timer",
        "DispatchSourceTimer",
        "makeTimerSource",
        "usleep",
        "nanosleep",
        "DispatchQueue.main.asyncAfter",
        "asyncAfter",
        "ContinuousClock",
        "SuspendingClock"
    ]

    /// The one-shot-wait spellings. Forbidden everywhere too, except the single
    /// response-liveness deadline decision 81 sanctions: a wait that races the
    /// next event and is cancelled the instant it arrives, never a periodic
    /// wake, and gone entirely when no session is open. The exception is
    /// confined to one call in one file, so a second wait anywhere — including
    /// elsewhere in that file — is still the finding.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
    static let sleepSpellings = ["Task.sleep", "sleep("]
    static let responseLivenessDeadlineFile = "AgentEventReader.swift"

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

    /// Every Swift file under the module, at any depth.
    static func sourceFiles() throws -> [URL] {
        guard let walk = FileManager.default.enumerator(at: moduleURL, includingPropertiesForKeys: nil) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return walk
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
    }

    /// Catches the regression that ships looking correct: an inert scheduler
    /// that wakes every minute to find it has nothing to fire. It emits nothing,
    /// it passes every other assertion here, and it burns CPU with no session
    /// open.
    @Test("No file in the orchestration layer waits on a clock")
    func noFileWaitsOnAClock() throws {
        let files = try Self.sourceFiles()
        // A discovery that found nothing would make every assertion below
        // vacuous.
        #expect(!files.isEmpty)

        for file in files {
            let source = try Self.code(String(contentsOf: file, encoding: .utf8))
            let isDeadlineFile = file.lastPathComponent == Self.responseLivenessDeadlineFile

            for spelling in Self.pollingSpellings {
                #expect(
                    !source.contains(spelling),
                    "\(file.lastPathComponent) contains '\(spelling)' — this layer wakes on events, never on a clock"
                )
            }

            for spelling in Self.sleepSpellings {
                // The one Decision-81 `Task.sleep(for:)` in `AgentEventReader.swift`
                // (see `responseLivenessDeadlineFile`) accounts for exactly one
                // of each sleep spelling — `sleep(` matches within `Task.sleep(`.
                // Anything more is a wait this layer does not get.
                let occurrences = source.components(separatedBy: spelling).count - 1
                let allowed = isDeadlineFile ? 1 : 0
                #expect(
                    occurrences == allowed,
                    "\(file.lastPathComponent): unexpected '\(spelling)' — only decision 81's deadline waits here"
                )
            }
        }
    }
}
