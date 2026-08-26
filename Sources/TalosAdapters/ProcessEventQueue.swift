/// The hand-off between the reads and the consumer of the stream: events waiting
/// for a consumer, or a consumer waiting for an event, never both.
///
/// Its depth is what the active-memory budget rests on — "< 400 MB excluding the
/// agent process" — so the deepest it ever got is recorded rather than trusted.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#budgets-that-make-the-above-testable
struct ProcessEventQueue {
    private var pending: [AgentProcessEvent] = []
    private var consumer: CheckedContinuation<AgentProcessEvent?, Never>?

    private(set) var highWaterMark = 0

    var count: Int {
        pending.count
    }

    /// Handed straight to a waiting consumer, so a stream nobody is behind on
    /// queues nothing at all.
    mutating func enqueue(_ event: AgentProcessEvent) {
        if let consumer {
            self.consumer = nil
            consumer.resume(returning: event)
            return
        }
        pending.append(event)
        highWaterMark = max(highWaterMark, pending.count)
    }

    mutating func dequeue() -> AgentProcessEvent? {
        guard !pending.isEmpty else { return nil }
        return pending.removeFirst()
    }

    mutating func park(_ continuation: CheckedContinuation<AgentProcessEvent?, Never>) {
        consumer = continuation
    }

    /// Wakes a parked consumer with no event, so it can end the stream or throw.
    mutating func wake() {
        guard let consumer else { return }
        self.consumer = nil
        consumer.resume(returning: nil)
    }
}
