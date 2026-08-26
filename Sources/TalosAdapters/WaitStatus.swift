/// A `waitpid` status, read as the reason a run ended.
///
/// Decoded by hand because `WIFSIGNALED` and friends are C macros and do not
/// import into Swift.
enum WaitStatus {
    /// 128 + the signal is the POSIX shell's spelling for a signal death, so 137
    /// reads as `SIGKILL` rather than as a number Talos invented.
    private static let signalExitCodeBase: Int32 = 128
    private static let signalMask: Int32 = 0x7F
    private static let exitCodeShift: Int32 = 8
    private static let exitCodeMask: Int32 = 0xFF

    /// A code of any value is the agent's own outcome: this layer never decides
    /// that a non-zero code is a failure, because only the adapter reading the
    /// output can tell a denial from a crash.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#denial-is-not-failure
    static func reason(for status: Int32) -> AgentTerminationReason {
        let signalNumber = status & signalMask
        if signalNumber != 0 {
            return .exited(code: signalExitCodeBase + signalNumber)
        }
        return .exited(code: (status >> exitCodeShift) & exitCodeMask)
    }
}
