import SwiftUI

/// Attaches `center`'s control as a passive overlay, visible whenever a
/// session is running — never a sheet, since nothing here asks the user to
/// decide anything.
public extension View {
    /// Attaches the overlay described above, bound to `center`.
    @MainActor
    func sessionStopHost(_ center: SessionStopCenter) -> some View {
        overlay(alignment: .topTrailing) {
            if center.isSessionRunning {
                SessionStopControlView(onStop: center.requestStop)
            }
        }
    }
}
