import Darwin
import Foundation

/// One agent CLI process: started once, streamed incrementally, and killed
/// along with everything it started — the spawn, the stream, and the kill,
/// the whole lifetime. This is the only file in Talos that starts a process.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
///
/// Machinery an adapter uses *inside* its own `launch`, not a seventh
/// capability — ``AgentAdapter`` is unchanged by it.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#agent-adapters
///
/// `posix_spawn` rather than `Foundation.Process`, because the child must lead
/// its own process group *from birth* (`POSIX_SPAWN_SETPGROUP`), which `Process`
/// cannot ask for and which cannot be set afterwards without losing the race
/// against a child that forks immediately.
actor AgentProcess {
    /// Bytes per readable event, and so the ceiling on one ``AgentOutputChunk``.
    /// Internal, so the test asserting the bound reads it rather than a literal.
    static let readBufferSize = 16384
    /// Chunks that may wait for the consumer before the read sources are
    /// suspended, the pipe fills, and the child blocks in `write`. Nothing is
    /// dropped — the active-memory budget, "< 400 MB excluding the agent process".
    static let maximumQueuedChunks = 64
    /// One channel's descriptor, asked without waiting — see ``isReadable(_:)``.
    private static let oneDescriptor: nfds_t = 1
    private static let withoutWaiting: Int32 = 0

    private let executablePath: String
    private let arguments: [String]
    private let configuration: AgentLaunchConfiguration
    /// Serial, so a channel's events arrive in the order the child produced them.
    private let monitorQueue: DispatchQueue

    private var channels: [AgentOutputChannel: ChannelState] = [:]
    private var exitSource: DispatchSourceProcess?
    private var stream: AsyncThrowingStream<AgentProcessEvent, any Error>?

    private var queue = ProcessEventQueue()
    private var exitStatus: Int32?
    private var lastOutput = ""
    private var hasFinished = false
    /// A Talos-side read failure, waiting to be thrown from the stream — the one
    /// thing the stream throws for.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing
    private var readFailure: AgentReadFailure?

    /// The child's pid, which is also its process group id: the spawn makes it
    /// the group leader, so one number identifies the process and the tree under
    /// it. `nil` before ``start()`` and after the run has ended.
    private(set) var processIdentifier: pid_t?

    /// The deepest the queue ever got, so the bound above is asserted by a test
    /// rather than trusted.
    var highWaterMark: Int {
        queue.highWaterMark
    }

    /// The pipe read ends still open, so a test can assert a stop closed them
    /// rather than trusting that the cancel handler ran.
    var openDescriptors: [Int32] {
        channels.values.filter { !$0.isClosed }.map(\.descriptor)
    }

    /// - Parameters:
    ///   - executablePath: An absolute path. Nothing here searches `PATH` —
    ///     resolving a name is the adapter's work.
    ///   - arguments: Passed through unchanged.
    ///   - configuration: The working directory and the *complete* environment.
    init(executablePath: String, arguments: [String] = [], configuration: AgentLaunchConfiguration) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.configuration = configuration
        monitorQueue = DispatchQueue(label: "talos.adapters.agent-process")
    }

    // MARK: - Starting

    /// Spawns the child and returns its event stream. Calling it again returns
    /// the same stream rather than a second process, so one ``AgentProcess`` is
    /// one process for its whole life.
    ///
    /// Unfolding rather than continuation-backed: a continuation cannot suspend
    /// in `yield`, so a consumer slower than the child would force a choice
    /// between dropping an event and buffering without a bound.
    ///
    /// `onCancel` is what makes stop reachable "at all times" rather than only
    /// while a caller happens to be holding this actor's own reference: the
    /// consumer's call into ``next()`` can be parked on the pipe for as long as
    /// the child produces nothing, and unfolding's own cancellation handling
    /// only stops it from calling `produce` *again* — it does not reach into an
    /// already-suspended call and end it. Registering this closure is what
    /// does: cancelling the task consuming this stream is, by itself, a stop.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#stop-kills-the-tree
    ///
    /// - Throws: ``AgentSpawnFailure`` when the process never started, so a
    ///   failure to launch is not reported as a run that produced nothing.
    func start() throws -> AsyncThrowingStream<AgentProcessEvent, any Error> {
        if let stream {
            return stream
        }
        try spawn()
        let stream = AsyncThrowingStream<AgentProcessEvent, any Error>(unfolding: {
            try await withTaskCancellationHandler(
                operation: { try await self.next() },
                onCancel: { Task { await self.stop() } }
            )
        })
        self.stream = stream
        return stream
    }

    private func spawn() throws {
        let standardOutput = try makePipe()
        let standardError: [Int32]
        do {
            standardError = try makePipe()
        } catch {
            close(standardOutput[0])
            close(standardOutput[1])
            throw error
        }

        let spawned: pid_t
        do {
            spawned = try spawnLeadingItsOwnProcessGroup(
                executablePath: executablePath,
                arguments: arguments,
                configuration: configuration,
                standardOutputWrite: standardOutput[1],
                standardErrorWrite: standardError[1]
            )
        } catch {
            closeAll(standardOutput, standardError)
            throw error
        }

        // While the parent holds a write end open, the reader never sees end of
        // output and the run never terminates.
        close(standardOutput[1])
        close(standardError[1])
        processIdentifier = spawned
        channels[.standardOutput] = makeChannel(.standardOutput, descriptor: standardOutput[0])
        channels[.standardError] = makeChannel(.standardError, descriptor: standardError[0])
        exitSource = makeExitSource(for: spawned)
    }

    private func closeAll(_ pipes: [Int32]...) {
        for descriptors in pipes {
            for descriptor in descriptors {
                close(descriptor)
            }
        }
    }

    private func makePipe() throws -> [Int32] {
        var descriptors: [Int32] = [-1, -1]
        guard pipe(&descriptors) == 0 else {
            throw AgentSpawnFailure(executablePath: executablePath, code: errno)
        }
        return descriptors
    }

    /// `nonisolated`, like the handlers it installs: a closure created inside an
    /// isolated method is inferred isolated to this actor, and Dispatch calls it
    /// on `monitorQueue` regardless — which traps at runtime as an incorrect
    /// executor assumption.
    private nonisolated func makeChannel(_ channel: AgentOutputChannel, descriptor: Int32) -> ChannelState {
        // Non-blocking, so a read after the child exited answers rather than
        // parking this actor on a pipe a descendant is holding open.
        _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: monitorQueue)
        let reads = ReadSource(source)
        source.setEventHandler { [self] in
            channelBecameReadable(channel, on: reads)
        }
        source.setCancelHandler { close(descriptor) }
        reads.resume()
        return ChannelState(descriptor: descriptor, reads: reads)
    }

    private nonisolated func makeExitSource(for identifier: pid_t) -> DispatchSourceProcess {
        let source = DispatchSource.makeProcessSource(
            identifier: identifier,
            eventMask: .exit,
            queue: monitorQueue
        )
        source.setEventHandler { [self] in
            childDidExit()
        }
        source.resume()
        return source
    }

    /// The two source handlers, and the only code here that runs off the actor.
    /// `nonisolated` rather than inferred: an isolation the compiler assumed but
    /// Dispatch does not honour is a data race that type-checks.
    private nonisolated func channelBecameReadable(_ channel: AgentOutputChannel, on reads: ReadSource) {
        // Synchronously, before the hop: one read in flight per channel, so
        // chunks cannot overtake each other and a stalled consumer stops the
        // reads instead of growing the queue.
        reads.suspend()
        Task { await readAvailable(channel) }
    }

    private nonisolated func childDidExit() {
        Task { await processDidExit() }
    }

    // MARK: - Stopping

    /// Kills the child and every descendant it started, then ends the run.
    ///
    /// > **A surviving child is a failed stop, not a partial one.**
    ///
    /// `SIGKILL` to the whole group rather than `SIGTERM` to the child: a
    /// terminated parent leaves its children running, and an orphan "keeps
    /// writing files, spending money, and holding locks after the user has been
    /// told the session is over".
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#stop-kills-the-tree
    ///
    /// Calling it twice ends the run once. Calling it after the child exited on
    /// its own leaves the recorded reason as the one that actually ended it.
    func stop() {
        guard !hasFinished, let identifier = processIdentifier else { return }
        killpg(identifier, SIGKILL)
        reap(identifier)
        finish(AgentTermination(reason: .stopped, lastOutput: lastOutput))
    }

    private func processDidExit() {
        guard !hasFinished, let identifier = processIdentifier, exitStatus == nil else { return }
        reap(identifier)
        // Not finished here: the pipes may still hold output the child wrote
        // before exiting, which is what a failed run is diagnosed from.
        for channel in channels.keys {
            closeIfDrained(channel)
        }
        finishIfDrained()
    }

    /// Ends a channel once the child is gone and its pipe holds nothing more:
    /// everything the agent wrote is in the pipe already, because it exited.
    ///
    /// Waiting for end of output instead hangs on a descendant that inherited the
    /// write end and outlived the agent — the normal case, since "an agent CLI
    /// runs build tools, test runners, package managers, and language servers".
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#stop-kills-the-tree
    private func closeIfDrained(_ channel: AgentOutputChannel) {
        guard exitStatus != nil, var state = channels[channel], !state.isClosed,
              !isReadable(state.descriptor) else { return }
        emit(AgentOutputDecoder.flush(&state.carryOver), on: channel)
        state.isSuspended = false
        state.isClosed = true
        state.reads.cancel()
        channels[channel] = state
    }

    /// Whether a read would answer immediately, end of output included.
    ///
    /// Not a poll in the § Nothing polls sense and no timer: asked once when a
    /// read completes or the child exits, with a zero timeout, never on a clock.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#nothing-polls
    private func isReadable(_ descriptor: Int32) -> Bool {
        var query = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        return poll(&query, Self.oneDescriptor, Self.withoutWaiting) > 0
    }

    private func reap(_ identifier: pid_t) {
        guard exitStatus == nil else { return }
        var status: Int32 = 0
        var result: pid_t
        repeat {
            result = waitpid(identifier, &status, 0)
        } while result < 0 && errno == EINTR
        exitStatus = status
    }

    private func finishIfDrained() {
        guard let status = exitStatus, channels.values.allSatisfy(\.isClosed) else { return }
        finish(AgentTermination(reason: WaitStatus.reason(for: status), lastOutput: lastOutput))
    }

    private func finish(_ termination: AgentTermination) {
        guard !hasFinished else { return }
        hasFinished = true
        queue.enqueue(.terminated(termination))
        teardown()
    }

    private func teardown() {
        for key in Array(channels.keys) {
            guard var channel = channels[key] else { continue }
            // ``ReadSource/cancel()`` resumes if it has to: a cancel reaches a
            // suspended source only once it runs, and its handler is the close.
            channel.reads.cancel()
            channel.isSuspended = false
            channel.isClosed = true
            channels[key] = channel
        }
        exitSource?.cancel()
        exitSource = nil
        processIdentifier = nil
        // Breaks the cycle with the stream that pulls from this actor; the
        // consumer's own reference keeps it alive.
        stream = nil
    }

    // MARK: - Reading

    private func readAvailable(_ channel: AgentOutputChannel) {
        guard !hasFinished, var state = channels[channel], !state.isClosed else { return }

        var buffer = [UInt8](repeating: 0, count: Self.readBufferSize)
        let count = read(state.descriptor, &buffer, Self.readBufferSize)

        if count > 0 {
            state.carryOver.append(contentsOf: buffer[0 ..< count])
            emit(AgentOutputDecoder.take(&state.carryOver), on: channel)
        } else if count == 0 {
            state.isClosed = true
        } else if errno != EINTR, errno != EAGAIN {
            // "The stream throws only for a Talos-side read failure", so the
            // errno is carried out rather than folded into an end of output.
            // https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing
            recordReadFailure(AgentReadFailure(channel: channel, code: errno))
            state.isClosed = true
        }

        if state.isClosed {
            emit(AgentOutputDecoder.flush(&state.carryOver), on: channel)
            state.isSuspended = false
            state.reads.cancel()
        } else if queue.count >= Self.maximumQueuedChunks {
            state.isSuspended = true
        } else {
            state.reads.resume()
        }

        channels[channel] = state
        closeIfDrained(channel)
        finishIfDrained()
    }

    /// The consumer may already be suspended with nothing more coming, so it is
    /// woken to take the throw.
    private func recordReadFailure(_ failure: AgentReadFailure) {
        guard readFailure == nil else { return }
        readFailure = failure
        queue.wake()
    }

    private func emit(_ text: String, on channel: AgentOutputChannel) {
        guard !text.isEmpty else { return }
        // The *last* chunk, not an accumulation: retaining the whole stream to
        // answer `AgentTermination.lastOutput` is how the memory budget is lost.
        lastOutput = text
        queue.enqueue(.output(AgentOutputChunk(channel: channel, text: text)))
    }

    // MARK: - The queue between the child and the consumer

    private func next() async throws -> AgentProcessEvent? {
        if let event = queue.dequeue() {
            resumeReadingIfDrained()
            return event
        }
        try throwPendingReadFailure()
        if hasFinished {
            return nil
        }
        let event = await withCheckedContinuation { queue.park($0) }
        if event == nil {
            try throwPendingReadFailure()
        }
        return event
    }

    /// Queued events first, then the throw: the exit status is still the agent's
    /// outcome, and only the read failure is Talos's.
    private func throwPendingReadFailure() throws {
        guard let failure = readFailure else { return }
        readFailure = nil
        throw failure
    }

    /// Reads suspended by the bound are resumed as the consumer takes events, so
    /// backpressure lets go by itself rather than on a later read completing.
    private func resumeReadingIfDrained() {
        guard queue.count < Self.maximumQueuedChunks else { return }
        for key in Array(channels.keys) {
            guard var channel = channels[key], channel.isSuspended else { continue }
            channel.isSuspended = false
            channels[key] = channel
            channel.reads.resume()
        }
    }
}
