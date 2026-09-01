import SwiftUI

/// Attaches `center`'s current notice as a passive overlay — never a sheet,
/// since nothing here asks the user to decide anything.
public extension View {
    /// Attaches the overlay described above, bound to `center`.
    @MainActor
    func deniedActionNoticeHost(_ center: DeniedActionNoticeCenter) -> some View {
        overlay(alignment: .bottom) {
            if let notice = center.current {
                DeniedActionNoticeView(notice: notice)
            }
        }
    }
}
