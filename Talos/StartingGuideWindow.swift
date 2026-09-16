import SwiftUI

/// The identifier of the one auxiliary window. The Starting Guide is "its own
/// window, not a sidebar surface", because it is skippable and re-openable and
/// so cannot displace the work in the content area.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/App-Shell-and-Navigation#every-surface-placed
enum StartingGuideWindow {
    static let id = "starting-guide"
}

/// The auxiliary window's content. The gamified Starting Guide itself is its
/// own board item; this establishes the scene and its re-open path, with a
/// placeholder until that content lands.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#starting-guide
struct StartingGuideWindowContent: View {
    var body: some View {
        ContentUnavailableView(
            "Starting Guide",
            systemImage: "sparkles",
            description: Text("The Starting Guide is not available yet.")
        )
    }
}
