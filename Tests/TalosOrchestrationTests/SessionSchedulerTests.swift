import TalosOrchestration
import TalosProjectLibrary
import Testing

/// Verifies the stubbed scheduler surface: a schedule registers, the intent it
/// would fire is scheduler-sourced, and nothing is emitted while the flag is
/// off.
///
/// > The **scheduler interface** is designed and stubbed.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Sub-function-Advisor#what-the-mvp-must-deliver
@Suite("Session scheduler")
struct SessionSchedulerTests {
    static let hourly = Duration.seconds(3600)

    static func schedule(
        _ subFunction: SubFunction,
        project: ProjectIdentifier = .generate(),
        content: String = "Look for accessibility gaps in the project."
    ) -> SessionSchedule {
        SessionSchedule(
            id: "schedule-1",
            project: project,
            subFunction: subFunction,
            intentContent: content,
            interval: hourly
        )
    }

    // MARK: - Registering a schedule

    @Test("A schedule for a scheduled sub-function registers, and registers inert")
    func schedulingASubFunctionRegistersItInert() async {
        let scheduler = InertSessionScheduler()
        let schedule = Self.schedule(.advisor)

        let registration = await scheduler.register(schedule)

        #expect(registration == .registeredInert(schedule))
        #expect(await scheduler.registeredSchedules() == [schedule])
    }

    /// Both post-MVP sub-functions are registrable, not just the one the issue's
    /// spec page is named after.
    @Test("Self-improver registers on the same surface as Advisor")
    func selfImproverRegistersToo() async {
        let scheduler = InertSessionScheduler()

        let registration = await scheduler.register(Self.schedule(.selfImprover))

        guard case let .registeredInert(registered) = registration else {
            Issue.record("Expected self-improver to register: \(registration)")
            return
        }
        #expect(registered.subFunction == .selfImprover)
    }

    /// The regression: a scheduler that accepted anything would make "enters
    /// the pipeline from a user action" a comment rather than a constraint.
    @Test("A schedule for a user-activated sub-function is rejected, and says why")
    func userActivatedSubFunctionsAreRejected() async {
        let scheduler = InertSessionScheduler()

        for subFunction in [SubFunction.assistant, .automator] {
            let registration = await scheduler.register(Self.schedule(subFunction))

            guard case let .rejected(reason) = registration else {
                Issue.record("Expected \(subFunction.rawValue) to be rejected: \(registration)")
                continue
            }
            #expect(reason.contains(subFunction.rawValue))
            #expect(await scheduler.registeredSchedules().isEmpty)
        }
    }

    @Test("Exactly the two post-MVP sub-functions activate from a schedule")
    func onlyPostMVPSubFunctionsActivateFromASchedule() {
        let scheduled = SubFunction.allCases.filter(\.activatesFromSchedule)

        #expect(Set(scheduled) == Set([.advisor, .selfImprover]))
    }

    // MARK: - The intent a schedule fires

    @Test("The intent a schedule fires is scheduler-sourced and carries the schedule's project")
    func firedIntentIsSchedulerSourced() {
        let project = ProjectIdentifier.generate()
        let schedule = Self.schedule(.advisor, project: project, content: "Suggest cost improvements.")

        let intent = schedule.intent

        #expect(intent.source == .scheduler)
        #expect(intent.project == project)
        #expect(intent.requestingSubFunction == .advisor)
        #expect(intent.content == "Suggest cost improvements.")
    }

    // MARK: - The flag is off

    /// The off state, which is the state that ships: every sub-function this
    /// scheduler accepts is one ``SubFunction/isActiveAtMVP`` reports off, so
    /// nothing registrable can emit.
    ///
    /// > Advisor and Self-improver **running** (their structure ships; their
    /// > schedulers do not)
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#deliberately-out-of-scope-for-v10
    @Test("No registrable sub-function emits an intent while it is off")
    func nothingEmitsWhileTheFlagIsOff() async {
        let scheduler = InertSessionScheduler()
        let registrable = SubFunction.allCases.filter(\.activatesFromSchedule)
        // A filter that found nothing would make the loop below vacuous.
        #expect(!registrable.isEmpty)

        for subFunction in registrable {
            #expect(!subFunction.isActiveAtMVP)
            let schedule = Self.schedule(subFunction)
            _ = await scheduler.register(schedule)

            #expect(await scheduler.emit(schedule) == nil)
        }
    }

    /// A withheld intent is not a dropped registration: the surface exists and
    /// is inert, which is a different claim from the surface being absent.
    @Test("A schedule stays registered after emitting nothing")
    func aWithheldIntentLeavesTheScheduleRegistered() async {
        let scheduler = InertSessionScheduler()
        let schedule = Self.schedule(.advisor)
        _ = await scheduler.register(schedule)

        #expect(await scheduler.emit(schedule) == nil)
        #expect(await scheduler.registeredSchedules() == [schedule])
    }
}
