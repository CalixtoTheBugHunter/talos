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

    /// The cadence is the field that makes a schedule a schedule, and nothing
    /// in production reads it while the scheduler is inert — so without this,
    /// storing any interval at all would pass.
    @Test("A schedule keeps the cadence it was given, through registration")
    func aScheduleKeepsTheCadenceItWasGiven() async {
        let scheduler = InertSessionScheduler()
        let schedule = Self.schedule(.advisor)

        #expect(schedule.interval == Self.hourly)
        _ = await scheduler.register(schedule)

        #expect(await scheduler.registeredSchedules().first?.interval == Self.hourly)
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

    /// Two entries under one id would fire the same schedule twice once its
    /// sub-function is enabled, which `Identifiable` says cannot happen.
    @Test("A second schedule reusing a registered id is rejected, and names the id")
    func aDuplicateScheduleIdIsRejected() async {
        let scheduler = InertSessionScheduler()
        let first = Self.schedule(.advisor)
        _ = await scheduler.register(first)

        let registration = await scheduler.register(Self.schedule(.selfImprover))

        guard case let .rejected(reason) = registration else {
            Issue.record("Expected a reused id to be rejected: \(registration)")
            return
        }
        #expect(reason.contains(first.id))
        #expect(await scheduler.registeredSchedules() == [first])
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

    /// The other side of the flag, and the reason it is a flag at all: with the
    /// sub-function on, the same schedule on the same scheduler emits. A
    /// scheduler whose off state were hard-coded would pass every assertion
    /// above this one.
    ///
    /// > Enabling Advisor later must require **no refactor of Talos core**.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Sub-function-Advisor#what-the-mvp-must-deliver
    @Test("A schedule emits its scheduler-sourced intent once its sub-function is on")
    func anEnabledSubFunctionEmitsItsScheduledIntent() async {
        let scheduler = InertSessionScheduler(isEnabled: { _ in true })
        let schedule = Self.schedule(.advisor, content: "Review the project for missing edge cases.")
        _ = await scheduler.register(schedule)

        let intent = await scheduler.emit(schedule)

        #expect(intent == schedule.intent)
        #expect(intent?.source == .scheduler)
        #expect(intent?.requestingSubFunction == .advisor)
        #expect(intent?.content == "Review the project for missing edge cases.")
    }

    /// What ships is the default, so the default is what has to be pinned: a
    /// scheduler constructed with no argument gates on nothing but
    /// ``SubFunction/isActiveAtMVP``. Catches a default hard-coded either way.
    @Test("The enablement a scheduler ships with is the MVP flag and nothing else")
    func theDefaultEnablementIsTheMVPFlagAndNothingElse() async {
        let scheduler = InertSessionScheduler()

        for subFunction in SubFunction.allCases {
            let emitted = await scheduler.emit(Self.schedule(subFunction))

            #expect(
                (emitted != nil) == subFunction.isActiveAtMVP,
                "\(subFunction.rawValue): emitted \(emitted != nil), isActiveAtMVP \(subFunction.isActiveAtMVP)"
            )
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
