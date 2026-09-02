import Foundation
@testable import TalosAdapters
import Testing

/// Verifies that ``AgentProcess/stop()`` leaves nothing alive, against a real
/// process tree.
///
/// > **A surviving child is a failed stop, not a partial one.**
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#stop-kills-the-tree
///
/// **This retires the disclaimer at ``StopTests`` (`StopTests.swift:11`)**,
/// which says it does not assert "a real process and its descendants are dead,
/// because nothing here spawns one" and assigns that to "the first adapter that
/// spawns". The two stay separate because they fail for different reasons: a
/// contract that lost its guarantee, and a kill that missed a descendant.
///
/// § The suite installs nothing still holds — every child is `/bin/sh`.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-suite-installs-nothing
@Suite("Agent process stop kills the tree")
struct AgentProcessStopTests {
    /// Spawns a long-lived grandchild, prints its pid, then waits — so the pid is
    /// readable before the stop and the shell is still alive to be stopped.
    /// `sleep 300` rather than shorter: a grandchild that exited on its own would
    /// make the assertions below pass without `stop()` killing anything.
    static let spawnsAGrandchild = "sleep 300 & echo $!; wait"

    /// Reads the grandchild's pid from the first line the shell prints.
    static func firstLine(of events: [AgentProcessEvent]) -> String {
        AgentProcessTests.text(events, on: .standardOutput)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
    }

    /// Re-checks after a stop, and the gap between them — two seconds in total.
    static let attemptsAllowed = 200
    static let intervalBetweenAttempts = Duration.milliseconds(10)

    /// Repeats `check` — a `kill` or `killpg` with signal 0 — until it answers
    /// `ESRCH`, returning `false` if the deadline passes first.
    ///
    /// A deadline rather than one immediate check because the grandchild's parent
    /// is the shell this stop also killed and reaped, so the grandchild is
    /// reparented to `launchd` and its process-table entry lingers until
    /// `launchd` reaps it. For those milliseconds `kill(pid, 0)` answers 0 about
    /// a process already dead.
    ///
    /// The wait does not weaken the claim: it is "that **nothing survives**, not
    /// that a termination signal was sent", and a `sleep 300` that genuinely
    /// survived is still there two seconds later. The immediate check was the
    /// weaker one — it asserted `launchd`'s timing as much as Talos's kill.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#stop-kills-the-tree
    static func waitUntilGone(_ check: () -> Int32) async -> Bool {
        for _ in 0 ..< attemptsAllowed {
            errno = 0
            if check() == -1, errno == ESRCH {
                return true
            }
            try? await Task.sleep(for: intervalBetweenAttempts)
        }
        return false
    }

    /// > Stop means the agent process **and every process it started** is dead.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#stop-kills-the-tree
    ///
    /// Catches the regression that looks correct in every manual test: killing
    /// only the pid Talos spawned, leaving the grandchild running outside the
    /// gate. The grandchild is asserted alive *before* the stop, because
    /// otherwise a stop that killed nothing and a grandchild that was never
    /// there produce the same `ESRCH`.
    @Test("Stopping kills the grandchild the agent started, not only the agent")
    func stoppingKillsEveryDescendant() async throws {
        let process = AgentProcessTests.makeProcess(Self.spawnsAGrandchild)
        var events: [AgentProcessEvent] = []
        var stream = try await process.start().makeAsyncIterator()

        // The first chunk carries the pid, so the shell has reached `wait` and
        // the grandchild exists.
        try events.append(#require(await stream.next()))
        let grandchild = try #require(pid_t(Self.firstLine(of: events)))
        #expect(kill(grandchild, 0) == 0, "the grandchild was not running before the stop")

        await process.stop()

        let gone = await Self.waitUntilGone { kill(grandchild, 0) }
        #expect(gone, "a descendant survived the stop")
    }

    /// The group is the mechanism the guarantee rests on: one `killpg` reaches
    /// descendants Talos never learned the pids of. Asserted separately because a
    /// single visible grandchild can be cleared by luck, while an empty group
    /// holds for descendants the test never enumerated.
    @Test("Stopping leaves no member of the process group alive")
    func stoppingLeavesNoMemberOfTheGroupAlive() async throws {
        let process = AgentProcessTests.makeProcess(Self.spawnsAGrandchild)
        var stream = try await process.start().makeAsyncIterator()
        _ = try await stream.next()

        let identifier = try #require(await process.processIdentifier)
        let group = getpgid(identifier)
        #expect(group == identifier, "the child is not the leader of its own group")

        await process.stop()

        let gone = await Self.waitUntilGone { killpg(group, 0) }
        #expect(gone, "the process group outlived the stop")
    }

    /// Stop is a guarantee rather than a request, so the caller is told the run
    /// is over — and told it was stopped, not that it failed.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
    @Test("A stopped run ends with the stopped reason and a closed stream")
    func aStoppedRunEndsWithTheStoppedReason() async throws {
        let process = AgentProcessTests.makeProcess("echo working; \(Self.spawnsAGrandchild)")
        let stream = try await process.start()
        var iterator = stream.makeAsyncIterator()
        _ = try await iterator.next()

        await process.stop()

        // The terminated event and then the end: a stream still open after a
        // stop is a session the console cannot report as over.
        var reason: AgentTerminationReason?
        while let event = try await iterator.next() {
            if case let .terminated(termination) = event {
                reason = termination.reason
            }
        }
        #expect(reason == .stopped)
    }

    /// Enough stops that the losing side of the race below is reached: whether a
    /// read source has already seen the end of output when the stop tears it
    /// down is the monitor queue's timing, and one stop can miss it.
    static let stopsToRepeat = 20

    /// A stop that leaks the pipes it opened costs the user a session, not a
    /// descriptor: once the process limit is reached, `pipe(2)` fails and the
    /// next launch reports a spawn failure telling them to check
    /// `.talos/agents.yaml` — a fault of Talos's, named as theirs.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#errors
    ///
    /// Asserted on the descriptors this process opened rather than on a count of
    /// the whole table, which every other test in this suite is concurrently
    /// changing. `fstat` after the fact is what distinguishes a closed
    /// descriptor from one the cancel handler never reached.
    @Test("Stopping closes the pipes it opened")
    func stoppingClosesThePipesItOpened() async throws {
        for _ in 0 ..< Self.stopsToRepeat {
            let process = AgentProcessTests.makeProcess(Self.spawnsAGrandchild)
            var stream = try await process.start().makeAsyncIterator()
            _ = try await stream.next()
            let descriptors = await process.openDescriptors
            #expect(descriptors.count == 2, "expected a read end for each of the child's two channels")

            await process.stop()

            for descriptor in descriptors {
                let closed = await Self.waitUntilClosed(descriptor)
                #expect(closed, "descriptor \(descriptor) is still an open pipe after the stop")
            }
        }
    }

    /// The cancel handler closes the descriptor on the monitor queue, so the
    /// close lands just after `stop()` returns rather than inside it. Same
    /// deadline as ``waitUntilGone(_:)`` and for the same reason.
    static func waitUntilClosed(_ descriptor: Int32) async -> Bool {
        for _ in 0 ..< attemptsAllowed {
            var information = stat()
            if fstat(descriptor, &information) != 0 || information.st_mode & S_IFMT != S_IFIFO {
                return true
            }
            try? await Task.sleep(for: intervalBetweenAttempts)
        }
        return false
    }

    /// Diagnostic, not a claim this issue makes: proves empirically whether
    /// merely cancelling the task consuming ``AgentProcess/start()``'s stream —
    /// never calling ``AgentProcess/stop()`` — already kills the tree, or
    /// whether it takes the SPEC's guarantee with it.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#stop-kills-the-tree
    @Test("Cancelling the consuming task, with no explicit stop, still kills the tree")
    func cancellingTheConsumingTaskStillKillsTheTree() async throws {
        let process = AgentProcessTests.makeProcess(Self.spawnsAGrandchild)
        let stream = try await process.start()
        let (pids, pidContinuation) = AsyncStream<pid_t>.makeStream()

        let consumer = Task {
            var iterator = stream.makeAsyncIterator()
            guard let first = try? await iterator.next(), case let .output(chunk) = first,
                  let pid = pid_t(chunk.text.split(separator: "\n", omittingEmptySubsequences: true).first ?? "")
            else { return }
            pidContinuation.yield(pid)
            // Suspended here until the tree is actually killed: the shell is
            // parked at `wait` and produces nothing more on its own.
            _ = try? await iterator.next()
        }

        var pidIterator = pids.makeAsyncIterator()
        let grandchild = try #require(await pidIterator.next())
        #expect(kill(grandchild, 0) == 0, "the grandchild was not running before cancellation")

        consumer.cancel()
        _ = await consumer.value

        let gone = await Self.waitUntilGone { kill(grandchild, 0) }
        #expect(gone, "cancelling the consumer, with no explicit stop(), left a descendant running")
    }

    /// Not an error, and it does not rewrite what happened: a `stop()` that
    /// overwrote the exit code would hide a failure behind a user action.
    @Test("Stopping an already finished process changes nothing")
    func stoppingAnAlreadyFinishedProcessChangesNothing() async throws {
        let process = AgentProcessTests.makeProcess("exit 4")
        let events = try await AgentProcessTests.collect(process.start())

        await process.stop()

        let termination = try AgentProcessTests.termination(events)
        #expect(termination.reason == .exited(code: 4))
    }
}
