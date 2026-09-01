import TalosCore
import TalosUI
import Testing

@Suite("Denied action notice center: notify publishes")
struct DeniedActionNoticeCenterNotifyTests {
    @Test("Notifying a denial publishes it as current")
    @MainActor
    func notifyPublishesTheNotice() async {
        let center = DeniedActionNoticeCenter(dismissAfter: .seconds(60))

        await center.notify(action: .fileWrite, requestPrompt: "Write Secrets.swift")

        #expect(center.current?.action == .fileWrite)
        #expect(center.current?.requestPrompt == "Write Secrets.swift")
    }

    @Test("A second notify replaces the first rather than queuing behind it")
    @MainActor
    func secondNotifyReplacesTheFirst() async {
        let center = DeniedActionNoticeCenter(dismissAfter: .seconds(60))

        await center.notify(action: .fileWrite, requestPrompt: "Write Secrets.swift")
        await center.notify(action: .fileDelete, requestPrompt: "Delete build/")

        #expect(center.current?.action == .fileDelete)
        #expect(center.current?.requestPrompt == "Delete build/")
    }
}

/// A denial the user never asked about is still owed a visible trace, and
/// that trace must not linger, since nothing here is a decision left pending.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#denial-is-not-failure
@Suite("Denied action notice center: clears itself")
struct DeniedActionNoticeCenterDismissalTests {
    @Test("The notice clears itself after the configured duration")
    @MainActor
    func noticeClearsAfterItsDuration() async {
        let center = DeniedActionNoticeCenter(dismissAfter: .milliseconds(20))

        await center.notify(action: .fileWrite, requestPrompt: "Write Secrets.swift")
        #expect(center.current != nil)

        try? await Task.sleep(for: .milliseconds(200))

        #expect(center.current == nil)
    }

    @Test("A newer notice is not cleared by an older notice's scheduled dismissal")
    @MainActor
    func newerNoticeSurvivesAnOlderDismissal() async {
        let center = DeniedActionNoticeCenter(dismissAfter: .milliseconds(20))

        await center.notify(action: .fileWrite, requestPrompt: "Write Secrets.swift")
        try? await Task.sleep(for: .milliseconds(15))
        await center.notify(action: .fileDelete, requestPrompt: "Delete build/")

        try? await Task.sleep(for: .milliseconds(15))

        #expect(center.current?.action == .fileDelete)
    }
}
