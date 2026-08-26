/// One output channel of a running child: the pipe it is read from, the source
/// that says when to read it, and what has been read but not yet decoded.
struct ChannelState {
    let descriptor: Int32
    let reads: ReadSource
    /// Bytes read but not yet decodable — the tail of a multi-byte scalar split
    /// across two reads.
    var carryOver: [UInt8] = []
    /// Held back because the consumer is behind, not because it is done.
    /// ``ReadSource`` owns whether the source is *actually* suspended.
    var isSuspended = false
    /// End of output seen; the pipe is closed by the source's cancel handler.
    var isClosed = false
}
