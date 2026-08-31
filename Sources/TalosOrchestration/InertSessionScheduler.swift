import TalosProjectLibrary

/// The scheduler that ships at MVP: it holds registrations and emits nothing.
///
/// Inert is the whole design, not a stage of it. `emit` withholds an intent for
/// every sub-function ``SubFunction/isActiveAtMVP`` reports off, which is every
/// sub-function this scheduler will accept a schedule for — so enabling one is
/// that flag flipping, with no call site here to rewrite.
///
/// There is no clock anywhere in it. The budget row it protects is a
/// prohibition rather than a threshold — "Idle CPU | ~0%, no polling timers" —
/// so a stub that slept until the next fire would breach the gate while doing
/// nothing at all.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#budgets-that-make-the-above-testable
public actor InertSessionScheduler: SessionScheduler {
    private var schedules: [SessionSchedule] = []
    private let isEnabled: @Sendable (SubFunction) -> Bool

    /// Nothing is registered here: a schedule arrives from the layer that reads
    /// `project.yaml`, the only place that knows a project asked for one.
    ///
    /// The default enablement *is* ``SubFunction/isActiveAtMVP`` rather than a
    /// second flag beside it, so the two can never disagree. The parameter
    /// exists so the on state is reachable — a scheduler whose off state were
    /// hard-coded would satisfy every assertion a flag does, and the claim
    /// being made is that enabling one is a flag flip.
    public init(isEnabled: @escaping @Sendable (SubFunction) -> Bool = \.isActiveAtMVP) {
        self.isEnabled = isEnabled
    }

    /// Accepts a schedule for a sub-function that activates from a schedule,
    /// and rejects one for a sub-function that activates from a user selection.
    ///
    /// The rejection is not about MVP: `.assistant` and `.automator` are
    /// entered from a user action by design, so a schedule against either is a
    /// caller error rather than a feature waiting on a flag.
    ///
    /// A repeated `id` is rejected too. ``SessionSchedule`` is `Identifiable`,
    /// so accepting two entries under one id would fire that schedule twice
    /// once its sub-function is enabled.
    public func register(_ schedule: SessionSchedule) async -> ScheduleRegistration {
        guard schedule.subFunction.activatesFromSchedule else {
            return .rejected(
                reason: "\(schedule.subFunction.rawValue) is entered from a user action, "
                    + "not from a schedule. Remove the schedule and start the session from the console."
            )
        }
        guard !schedules.contains(where: { $0.id == schedule.id }) else {
            return .rejected(
                reason: "A schedule with the id '\(schedule.id)' is already registered. "
                    + "Give this one its own id, or remove the existing schedule first."
            )
        }
        schedules.append(schedule)
        return .registeredInert(schedule)
    }

    public func registeredSchedules() async -> [SessionSchedule] {
        schedules
    }

    /// The intent the schedule would fire, or `nil` while its sub-function is
    /// off.
    ///
    /// Registration is not checked here: whether a schedule is known is
    /// ``register(_:)``'s question, and this one answers only whether its
    /// sub-function is on.
    public func emit(_ schedule: SessionSchedule) async -> Intent? {
        guard isEnabled(schedule.subFunction) else { return nil }
        return schedule.intent
    }
}
