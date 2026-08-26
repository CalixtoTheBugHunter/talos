import Dispatch
import Synchronization

/// A `DispatchSourceRead` and the fact that it is suspended, behind one lock.
///
/// The read handler runs on the monitor queue and cannot write actor state, so a
/// flag on the actor recording its suspend goes stale — and `cancel` on a
/// suspended source is never delivered, which strands the descriptor the cancel
/// handler was going to close. Suspending and recording it under the same lock
/// is what keeps every resume balanced.
final class ReadSource: Sendable {
    let source: DispatchSourceRead
    /// `true` at birth: a `DispatchSource` is created suspended.
    private let isSuspended = Mutex(true)

    init(_ source: DispatchSourceRead) {
        self.source = source
    }

    func suspend() {
        isSuspended.withLock { suspended in
            guard !suspended else { return }
            source.suspend()
            suspended = true
        }
    }

    func resume() {
        isSuspended.withLock { suspended in
            guard suspended else { return }
            source.resume()
            suspended = false
        }
    }

    /// Cancels, then resumes if the source was suspended: the cancel handler is
    /// what closes the descriptor, and it does not run until the source does.
    func cancel() {
        source.cancel()
        resume()
    }
}
