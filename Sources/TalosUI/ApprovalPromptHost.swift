import SwiftUI

/// Presents an ``ApprovalPromptCenter``'s current request as a sheet — the
/// system's own chrome, never a Talos-authored material, so Liquid Glass and
/// its Reduce Transparency degradation both come for free.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Design-System#liquid-glass-is-inherited-never-applied
public extension View {
    /// Attaches the sheet described above, bound to `center`.
    @MainActor
    func approvalPromptHost(_ center: ApprovalPromptCenter) -> some View {
        sheet(item: Binding(
            get: { center.current },
            // A dismissal the two controls did not drive — the window
            // closing, the app quitting — is exactly the case the gate
            // treats as denied rather than as consent nobody gave.
            // https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-gate-fails-closed
            set: { newValue in
                if newValue == nil, let pending = center.current {
                    center.resolve(pending.id, with: .denied)
                }
            }
        )) { pending in
            SafeguardsApprovalPromptView(
                request: pending.request,
                action: pending.action,
                tier: pending.tier,
                onApprove: { center.resolve(pending.id, with: .allowed) },
                onDeny: { center.resolve(pending.id, with: .denied) }
            )
        }
    }
}
