import SwiftUI
import Combine

/// Drives the full-screen in-app reader on iOS. Other platforms push a
/// `DetailView` through navigation instead, so the router stays idle there.
@MainActor
final class ArticleRouter: ObservableObject {
    @Published var presentedDestination: ArticleDestination?

    /// The open reader, for timing how long a story was read.
    private var reading: (destination: ArticleDestination, placement: StoryPlacement?, since: Date)?

    func present(_ destination: ArticleDestination, placement: StoryPlacement? = nil) {
        reading = (destination, placement, Date())
        presentedDestination = destination
    }

    /// Called when the reader is dismissed; logs how long it was open.
    func readerDidClose() {
        guard let reading else { return }
        self.reading = nil
        EngagementLog.shared.record(
            .closeReader,
            reading.destination.item,
            placement: reading.placement,
            readingSeconds: Int(Date().timeIntervalSince(reading.since))
        )
    }
}

/// Opens a destination the way the user asked for in Settings: in the app, or
/// in the system browser. Marks the story read either way.
@MainActor
struct ArticleOpener {
    let router: ArticleRouter
    let preferences: FeedPreferences
    let userState: FeedUserStateStore
    let openURL: OpenURLAction

    func open(_ destination: ArticleDestination, placement: StoryPlacement? = nil) {
        EngagementLog.shared.record(
            destination.kind == .article ? .open : .openDiscussion,
            destination.item,
            placement: placement
        )
        userState.markRead(destination.item)

#if os(iOS)
        if preferences.opensLinksInApp {
            router.present(destination, placement: placement)
        } else {
            openURL(destination.url)
        }
#else
        openURL(destination.url)
#endif
    }
}
