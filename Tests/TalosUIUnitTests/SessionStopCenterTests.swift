import TalosUI
import Testing

/// Verifies ``SessionStopCenter`` against
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
/// — "the user can stop any running session immediately" — at the level this
/// center owns: the state a visible control and the `⌘.` command read, and
/// that requesting a stop calls through to what a session was tracked with.
@Suite("Session stop center")
struct SessionStopCenterTests {
    @Test("No session is running until one is tracked")
    @MainActor
    func noSessionRunsUntilTracked() {
        let center = SessionStopCenter()

        #expect(center.isSessionRunning == false)
    }

    @Test("Tracking a session publishes it as running")
    @MainActor
    func trackingPublishesRunning() {
        let center = SessionStopCenter()

        center.beginTracking(stopping: {
            // Never called by this test — only the published state is asserted.
        })

        #expect(center.isSessionRunning == true)
    }

    @Test("Requesting a stop calls the tracked session's own stop handler")
    @MainActor
    func requestingStopCallsTheTrackedHandler() async {
        let center = SessionStopCenter()
        let calls = CallRecorder()

        center.beginTracking(stopping: { await calls.record() })
        center.requestStop()
        // requestStop() runs the handler on its own task rather than
        // blocking the caller — give it a turn to complete.
        try? await Task.sleep(for: .milliseconds(20))

        #expect(await calls.invocations == 1)
    }

    @Test("Requesting a stop with no session tracked calls nothing")
    @MainActor
    func requestingStopWithNothingTrackedCallsNothing() async {
        let center = SessionStopCenter()

        center.requestStop()
        try? await Task.sleep(for: .milliseconds(20))

        #expect(center.isSessionRunning == false)
    }

    @Test("Ending the session stops publishing it as running")
    @MainActor
    func endingTheSessionStopsPublishingRunning() {
        let center = SessionStopCenter()
        center.beginTracking(stopping: {
            // Never called by this test — only the published state is asserted.
        })

        center.sessionEnded()

        #expect(center.isSessionRunning == false)
    }

    @Test("A second tracked session replaces the first as the stop target")
    @MainActor
    func aSecondTrackedSessionReplacesTheFirst() async {
        let center = SessionStopCenter()
        let first = CallRecorder()
        let second = CallRecorder()

        center.beginTracking(stopping: { await first.record() })
        center.beginTracking(stopping: { await second.record() })
        center.requestStop()
        try? await Task.sleep(for: .milliseconds(20))

        #expect(await first.invocations == 0)
        #expect(await second.invocations == 1)
    }
}

private actor CallRecorder {
    private(set) var invocations = 0

    func record() {
        invocations += 1
    }
}
