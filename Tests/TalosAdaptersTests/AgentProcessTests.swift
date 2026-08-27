import Foundation
@testable import TalosAdapters
import Testing

/// Verifies ``AgentProcess`` against the SPEC lines it implements, using real
/// child processes: the claims under test are about a process tree, a working
/// directory, an environment, and an exit status, none of which a fake can be
/// wrong about. § The suite installs nothing still holds — every child is
/// `/bin/sh` and its standard tools, and no credential or network is reached.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-suite-installs-nothing
@Suite("Agent process lifecycle")
struct AgentProcessTests {
    /// Reachable on every macOS, so the suite installs nothing.
    static let shell = "/bin/sh"

    static func makeProcess(_ script: String, in directory: URL? = nil) -> AgentProcess {
        AgentProcess(
            executablePath: shell,
            arguments: ["-c", script],
            configuration: directory.map { Self.configuration(in: $0) } ?? TestLaunch.configuration()
        )
    }

    static func configuration(in directory: URL) -> AgentLaunchConfiguration {
        AgentLaunchConfiguration(workingDirectory: directory, environment: ["PATH": "/usr/bin:/bin"])
    }

    static func makeTemporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("talos-process-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Drains a stream to its termination, mirroring
    /// ``AgentAdapterProtocolTests/collect(_:)``.
    static func collect(
        _ stream: AsyncThrowingStream<AgentProcessEvent, any Error>
    ) async throws -> [AgentProcessEvent] {
        var events: [AgentProcessEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    static func text(_ events: [AgentProcessEvent], on channel: AgentOutputChannel) -> String {
        events
            .compactMap { event -> AgentOutputChunk? in
                guard case let .output(chunk) = event, chunk.channel == channel else { return nil }
                return chunk
            }
            .map(\.text)
            .joined()
    }

    static func termination(_ events: [AgentProcessEvent]) throws -> AgentTermination {
        let terminations = events.compactMap { event -> AgentTermination? in
            guard case let .terminated(termination) = event else { return nil }
            return termination
        }
        return try #require(terminations.last, "the stream ended without a termination event")
    }

    // MARK: - An explicit working directory and environment (AC1)

    /// § How a message actually flows into Talos workflow — Talos hands the
    /// prompt to "a process it spawns", and the directory it runs in is the
    /// project's, never whatever Talos happened to be launched from.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
    ///
    /// Catches an inherited working directory, which is green wherever the two
    /// happen to match and writes into the wrong project everywhere else.
    @Test("A process runs in the working directory it was given")
    func processRunsInTheConfiguredWorkingDirectory() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let process = Self.makeProcess("pwd", in: directory)

        let events = try await Self.collect(process.start())

        // Both sides normalized the same way: the shell prints the physical
        // path, `/private/var/…`, and `resolvingSymlinksInPath()` strips that
        // prefix, so resolving one side only compares two spellings of one
        // directory.
        let reported = URL(fileURLWithPath: Self.text(events, on: .standardOutput)
            .trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(reported.resolvingSymlinksInPath().path == directory.resolvingSymlinksInPath().path)
    }

    // MARK: - Streaming, incrementally and without blocking (AC2)

    /// > Never a buffered whole: the console shows output as it happens and
    /// > cannot be fed by an adapter that waits for completion.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing
    ///
    /// Catches reading both pipes to the end before yielding anything, which is
    /// indistinguishable from correct on a child that exits immediately — so
    /// this child deliberately does not.
    @Test("Output arrives while the process is still running")
    func outputArrivesWhileTheProcessIsStillRunning() async throws {
        let process = Self.makeProcess("echo first; sleep 5")
        var events = try await process.start().makeAsyncIterator()

        let first = try await events.next()

        guard case let .output(chunk) = try #require(first) else {
            Issue.record("Expected output, got \(String(describing: first))")
            return
        }
        #expect(chunk.text == "first\n")
        #expect(chunk.channel == .standardOutput)
        // Still running: the chunk above was not the product of a finished run.
        #expect(await process.processIdentifier != nil)

        await process.stop()
    }

    /// > one incremental piece, on `standardOutput` or `standardError`, as it
    /// > arrived
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing
    ///
    /// The channel is part of the chunk, so merging the two cannot happen by
    /// accident and order holds within each.
    @Test("Standard output and standard error stay on their own channels")
    func outputAndErrorStayOnTheirOwnChannels() async throws {
        let process = Self.makeProcess("echo one; echo problem 1>&2; echo two")

        let events = try await Self.collect(process.start())

        #expect(Self.text(events, on: .standardOutput) == "one\ntwo\n")
        #expect(Self.text(events, on: .standardError) == "problem\n")
    }

    /// A scalar split across two reads must not become replacement characters:
    /// the console shows the agent's output as-is. Catches decoding each read in
    /// isolation, and the output is long enough that a scalar lands on a buffer
    /// boundary rather than by luck.
    @Test("A multi-byte character split across two reads survives intact")
    func aMultiByteCharacterSplitAcrossReadsSurvives() async throws {
        let repeats = AgentProcess.readBufferSize
        let process = Self.makeProcess("i=0; while [ $i -lt \(repeats) ]; do printf '√ç'; i=$((i+1)); done")

        let events = try await Self.collect(process.start())

        #expect(Self.text(events, on: .standardOutput) == String(repeating: "√ç", count: repeats))
    }

    // MARK: - Abnormal exit, typed, with the code and the last output (AC4)

    /// Both the code and the agent's own last words: "a Talos-authored summary
    /// of an agent crash is a guess presented as a diagnosis".
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#errors
    @Test("An abnormal exit carries its code and the last output")
    func anAbnormalExitCarriesItsCodeAndLastOutput() async throws {
        let process = Self.makeProcess("echo half an answer; exit 3")

        let events = try await Self.collect(process.start())
        let termination = try Self.termination(events)

        #expect(termination.reason == .exited(code: 3))
        #expect(termination.lastOutput == "half an answer\n")
    }

    /// A clean run is the same shape with a zero code, so a caller cannot tell
    /// success from failure by which case arrived — only by the code.
    @Test("A clean exit is reported with a zero code")
    func aCleanExitIsReportedWithAZeroCode() async throws {
        let process = Self.makeProcess("exit 0")

        let termination = try await Self.termination(Self.collect(process.start()))

        #expect(termination.reason == .exited(code: 0))
    }

    /// A child killed by a signal has no exit status of its own, so `SIGKILL`
    /// reads as 137 — the POSIX shell's spelling rather than one Talos coined.
    @Test("A process killed by a signal reports 128 plus the signal")
    func aProcessKilledBySignalReportsOneHundredAndTwentyEightPlusTheSignal() async throws {
        let process = Self.makeProcess("kill -9 $$")

        let termination = try await Self.termination(Self.collect(process.start()))

        #expect(termination.reason == .exited(code: 137))
    }

    /// The exit is the agent's, so nothing else may hold the run open.
    ///
    /// "An agent CLI runs build tools, test runners, package managers, and
    /// language servers", and one left running in the background inherits the
    /// write end of stdout — so end of output never arrives. Waiting for it
    /// leaves a finished session with no termination event, which is the exit
    /// code going missing rather than arriving late.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#stop-kills-the-tree
    ///
    /// The time limit is the assertion's other half: the regression this catches
    /// hangs rather than fails.
    @Test("A run ends when the agent exits, even with a descendant holding its output open", .timeLimit(.minutes(1)))
    func aRunEndsWhenTheAgentExitsDespiteASurvivingDescendant() async throws {
        // The pid first, so the grandchild can be cleaned up: this run ends
        // without a stop, so nothing here kills the tree. `sleep 120` outlasts
        // the time limit, because a grandchild that exits inside it releases the
        // pipe and lets the regression pass late instead of failing.
        let process = Self.makeProcess("sleep 120 & echo $!; echo done; exit 7")

        let events = try await Self.collect(process.start())
        let termination = try Self.termination(events)
        let grandchild = pid_t(Self.text(events, on: .standardOutput)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? "")
        if let grandchild {
            kill(grandchild, SIGKILL)
        }

        #expect(termination.reason == .exited(code: 7))
    }

    /// A process that never started is a thrown failure, not a run that produced
    /// nothing: the same event stream, and different things to tell the user.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#errors
    @Test("A process that cannot start throws instead of reporting an empty run")
    func aProcessThatCannotStartThrows() async throws {
        let process = AgentProcess(
            executablePath: "/nonexistent/agent-cli",
            configuration: TestLaunch.configuration()
        )

        await #expect(throws: AgentSpawnFailure.self) {
            _ = try await process.start()
        }
    }

    /// The failure names the fix, because the path came from a file a user wrote
    /// by hand and "not installed" is fixed differently from "wrong path".
    @Test("A failure to start names the executable and a fix")
    func aFailureToStartNamesTheExecutableAndAFix() async throws {
        let process = AgentProcess(
            executablePath: "/nonexistent/agent-cli",
            configuration: TestLaunch.configuration()
        )

        do {
            _ = try await process.start()
            Issue.record("Expected a spawn failure")
        } catch let failure as AgentSpawnFailure {
            #expect(failure.executablePath == "/nonexistent/agent-cli")
            #expect(failure.code == ENOENT)
            #expect(failure.fix.contains("/nonexistent/agent-cli"))
            #expect(failure.fix.contains("agents.yaml"))
        }
    }

    // MARK: - Bounded buffering while a large output streams (AC6)

    /// > Active memory (one running agent session) | < 400 MB excluding the
    /// > agent process
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#budgets-that-make-the-above-testable
    ///
    /// **This does not measure Talos's memory.** That budget is a release gate
    /// under Instruments `Allocations`, in `Scripts/verify-local.sh`.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Verification
    ///
    /// It asserts the property the budget rests on: however much the agent
    /// writes, what Talos holds is bounded and nothing is dropped to keep it so.
    /// Both halves matter — staying bounded by discarding chunks would pass the
    /// first assertion alone.
    @Test("A multi-megabyte stream stays bounded and loses nothing")
    func aLargeStreamStaysBoundedAndLosesNothing() async throws {
        let blockSize = 65536
        let blocks = 64
        let process = Self.makeProcess(
            "dd if=/dev/zero bs=\(blockSize) count=\(blocks) 2>/dev/null | tr '\\0' 'a'"
        )
        let stream = try await process.start()

        // Delayed so the queue actually reaches the bound: draining immediately
        // would satisfy the assertion below without backpressure engaging.
        try await Task.sleep(for: .milliseconds(200))

        var received = 0
        var lastOutput: String?
        for try await event in stream {
            switch event {
            case let .output(chunk):
                received += chunk.text.utf8.count
            case let .terminated(termination):
                lastOutput = termination.lastOutput
            }
        }

        #expect(received == blockSize * blocks)
        // Otherwise the bound below would hold on a run small enough to fit
        // inside it, which asserts nothing.
        #expect(received / AgentProcess.readBufferSize > AgentProcess.maximumQueuedChunks)
        // The bound, not an exact depth: how full the queue gets before the
        // consumer starts is the runner's timing. `+ 2` because the final
        // flush and the terminated event are enqueued past the point where
        // reading stops — the bound suspends the reads, it does not refuse
        // an enqueue.
        #expect(await process.highWaterMark <= AgentProcess.maximumQueuedChunks + 2)
        // The last chunk, not the whole run.
        #expect(try #require(lastOutput).utf8.count <= AgentProcess.readBufferSize)
    }

    // MARK: - Concurrent sessions do not interfere (AC8)

    /// Each session owns its own process handle. Catches state shared between
    /// instances — a static pid, a shared queue, a single monitor — none of which
    /// shows up until two sessions run at once.
    @Test("Stopping one session leaves another running and streaming")
    func stoppingOneSessionLeavesAnotherRunning() async throws {
        let first = Self.makeProcess("echo first; sleep 5")
        let second = Self.makeProcess("echo second; sleep 5")
        var firstEvents = try await first.start().makeAsyncIterator()
        var secondEvents = try await second.start().makeAsyncIterator()

        let firstOutput = try await firstEvents.next()
        let secondOutput = try await secondEvents.next()
        let secondIdentifier = try #require(await second.processIdentifier)
        #expect(await first.processIdentifier != secondIdentifier)

        await first.stop()

        // Untouched, and its output was never mixed into the first's stream.
        #expect(kill(secondIdentifier, 0) == 0)
        #expect(firstOutput == .output(AgentOutputChunk(channel: .standardOutput, text: "first\n")))
        #expect(secondOutput == .output(AgentOutputChunk(channel: .standardOutput, text: "second\n")))

        await second.stop()
    }
}
