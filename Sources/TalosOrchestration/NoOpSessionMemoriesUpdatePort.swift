/// A ``SessionMemoriesUpdatePort`` that writes nothing. Local persistent
/// memory storage is not implemented yet — this is that honest absence
/// made concrete, mirroring ``InertContextSource``, so a real session can
/// be composed today. A future real implementation replaces this type at
/// the composition root without changing ``SessionPipeline``.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#local-persistent-memories
public struct NoOpSessionMemoriesUpdatePort: SessionMemoriesUpdatePort {
    public init() {
        // Nothing to set up — this conformance holds no state.
    }

    public func updateMemories(for _: SessionRecord) async {
        // Deliberately discarded — see the type's own doc comment.
    }
}
