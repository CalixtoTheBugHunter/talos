import TalosProjectLibrary

/// One registered request for a sub-function to enter the session pipeline on
/// its own cadence rather than from a user action.
///
/// The scheduler is the *only* thing that differs between the two MVP
/// sub-functions and the two post-MVP ones, so this type deliberately produces
/// nothing but an ``Intent``: enabling a schedule later hands that intent to the
/// same `SessionPipeline.run` a typed message already goes through.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-shared-session-model
public struct SessionSchedule: Identifiable, Equatable, Sendable {
    public let id: String
    public let project: ProjectIdentifier
    public let subFunction: SubFunction
    /// What the schedule asks for, in the same natural language a user would
    /// type — the pipeline's first stage cannot tell the two apart, and that is
    /// the property being preserved.
    public let intentContent: String
    /// How often the schedule would fire. Nothing reads it while the scheduler
    /// is inert; it is held so a schedule is a complete value rather than one
    /// missing the field that makes it a schedule.
    public let interval: Duration

    public init(
        id: String,
        project: ProjectIdentifier,
        subFunction: SubFunction,
        intentContent: String,
        interval: Duration
    ) {
        self.id = id
        self.project = project
        self.subFunction = subFunction
        self.intentContent = intentContent
        self.interval = interval
    }

    /// The intent this schedule submits when it fires.
    public var intent: Intent {
        Intent(
            content: intentContent,
            source: .scheduler,
            project: project,
            requestingSubFunction: subFunction
        )
    }
}

/// What registering a ``SessionSchedule`` produced.
///
/// A registration never yields a running schedule: the structure ships and the
/// schedulers do not, so the accepted case names its own inertness rather than
/// leaving a caller to assume something now fires.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#deliberately-out-of-scope-for-v10
public enum ScheduleRegistration: Equatable, Sendable {
    case registeredInert(SessionSchedule)
    case rejected(reason: String)
}

/// Registers schedules and emits the intents they fire, for the sub-functions
/// that activate from an automatic schedule.
///
/// Emission returns an optional deliberately: a scheduler that cannot fire has
/// to be distinguishable from one that fired, and the absent intent is what a
/// caller observes while the sub-function is off.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Sub-function-Advisor#what-the-mvp-must-deliver
public protocol SessionScheduler: Sendable {
    func register(_ schedule: SessionSchedule) async -> ScheduleRegistration
    func registeredSchedules() async -> [SessionSchedule]
    func emit(_ schedule: SessionSchedule) async -> Intent?
}

public extension SubFunction {
    /// Whether this sub-function activates from an automatic schedule rather
    /// than from a user selection.
    ///
    /// Distinct from ``isActiveAtMVP``, which answers whether it does anything
    /// at all: `.assistant` is active and never scheduled, `.advisor` is
    /// scheduled and not active. Lives in this module because a sub-function's
    /// activation route is the scheduler's concern and not the Project
    /// Library's.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Home#how-talos-works
    var activatesFromSchedule: Bool {
        switch self {
        case .assistant, .automator: false
        case .advisor, .selfImprover: true
        }
    }
}
