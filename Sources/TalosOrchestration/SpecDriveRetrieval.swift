import TalosProjectLibrary

/// The real ``SpecDriveContextSource`` for a project, resolved from its parsed
/// ``SpecManifest``. Fetching the wiki and building the index is the agent's
/// out-of-band work per
/// [decision 83](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions),
/// landing in later issues; until an index exists this reports the honest
/// absence, distinguishing a project that declares no Spec Drive from one whose
/// content is not indexed yet. Either way the caller gets a labeled
/// ``ContextFragment/unavailable(reason:)`` — a missing part "is labeled where
/// the output is read", never guessed at.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#how-specs-are-retrieved
public struct SpecDriveRetrieval: SpecDriveContextSource {
    private let specDrive: SpecDrive

    public init(specDrive: SpecDrive) {
        self.specDrive = specDrive
    }

    public func fetch(for _: Intent) -> ContextFragment {
        switch specDrive {
        case .absent:
            .unavailable(reason: "This project declares no Spec Drive.")
        case .locations:
            .unavailable(reason: "Spec Drive content is not indexed yet.")
        }
    }
}
