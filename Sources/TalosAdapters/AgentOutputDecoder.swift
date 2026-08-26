import Foundation

// Turning pipe bytes into text without corrupting either. The rule it protects:
// the console shows the agent's output as-is.
// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is

/// Incremental UTF-8 decoding for output that arrives in arbitrary byte-sized
/// pieces.
///
/// Reads land on byte boundaries rather than scalar boundaries, so decoding each
/// buffer as it arrives turns a split character into replacement characters —
/// corruption Talos introduced, indistinguishable from the agent's own.
enum AgentOutputDecoder {
    /// The longest incomplete UTF-8 sequence that can straddle two reads: a
    /// four-byte scalar missing three of its bytes.
    static let maximumContinuationBytes = 3

    /// Takes everything that decodes as UTF-8 and leaves an incomplete trailing
    /// scalar behind for the next read.
    static func take(_ bytes: inout [UInt8]) -> String {
        let limit = max(0, bytes.count - maximumContinuationBytes)
        var boundary = bytes.count
        while boundary > limit {
            if let text = String(bytes: bytes[0 ..< boundary], encoding: .utf8) {
                bytes.removeFirst(boundary)
                return text
            }
            boundary -= 1
        }
        // Bytes that are not UTF-8 at all rather than a split scalar. The lossy
        // initializer is the point: a failable one would return nil and the
        // stream would stall on output that will never decode.
        // swiftlint:disable:next optional_data_string_conversion
        let text = String(decoding: bytes[0 ..< limit], as: UTF8.self)
        bytes.removeFirst(limit)
        return text
    }

    /// Renders whatever is left at end of output. It cannot become a complete
    /// scalar now, and bytes discarded here are the last thing the agent said
    /// going missing.
    static func flush(_ bytes: inout [UInt8]) -> String {
        guard !bytes.isEmpty else { return "" }
        // swiftlint:disable:next optional_data_string_conversion
        let text = String(decoding: bytes, as: UTF8.self)
        bytes.removeAll()
        return text
    }
}
