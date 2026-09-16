import SwiftUI

/// The content-area placeholder for a sidebar surface whose own view is built
/// by its own board item. The shell reaches the surface; the surface's content
/// arrives with the surface's issue.
///
/// Built on `ContentUnavailableView` rather than hand-rolled so the whole
/// accessibility gate is inherited: a real label and role, semantic colors,
/// and a layout that holds at 200% text size come from the platform. It is a
/// surface's Empty state, which "VoiceOver reads ... and its action".
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#what-each-state-answers-to
public struct PlaceholderSurfaceView: View {
    private let surface: ShellSurface

    public init(surface: ShellSurface) {
        self.surface = surface
    }

    public var body: some View {
        ContentUnavailableView(
            surface.title,
            systemImage: surface.systemImage,
            description: Text("This surface is not available yet.")
        )
        .navigationTitle(surface.title)
    }
}
