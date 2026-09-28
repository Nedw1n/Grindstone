import SwiftUI

/// Wraps a row or card so tapping it opens the story the way the user prefers.
/// On iOS that is the full-screen reader (or the system browser); on macOS and
/// visionOS it pushes `DetailView` unless links are set to open externally.
struct ArticleLink<Label: View>: View {
    @EnvironmentObject private var router: ArticleRouter
    @EnvironmentObject private var preferences: FeedPreferences
    @EnvironmentObject private var feedUserState: FeedUserStateStore
    @Environment(\.openURL) private var openURL
    @Environment(\.storyPlacement) private var placement

    private let destination: ArticleDestination
    private let label: () -> Label

    init(destination: ArticleDestination, @ViewBuilder label: @escaping () -> Label) {
        self.destination = destination
        self.label = label
    }

    var body: some View {
#if os(iOS)
        button
#else
        if preferences.opensLinksInApp {
            NavigationLink(value: destination) {
                label()
            }
            .buttonStyle(.plain)
        } else {
            button
        }
#endif
    }

    private var button: some View {
        Button(action: open) {
            label()
        }
        .buttonStyle(.plain)
    }

    private func open() {
        ArticleOpener(
            router: router,
            preferences: preferences,
            userState: feedUserState,
            openURL: openURL
        )
        .open(destination, placement: placement)
    }
}
