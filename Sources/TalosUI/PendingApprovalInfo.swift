import TalosCore
import TalosSafeguards

/// What ``SessionConsoleViewModel/currentPendingApproval`` reports about the
/// one row currently pending — a named type rather than a tuple, since it
/// crosses back into ``SessionConsoleViewModel/resolvePendingApproval(with:)``
/// and ``SessionConsoleViewModel/cancelPendingApproval(requestID:)`` as a
/// single value.
struct PendingApprovalInfo {
    let callID: String
    let action: SafeguardsActionType
    let tier: SafeguardsTier
}
