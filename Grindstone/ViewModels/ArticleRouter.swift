import SwiftUI
import Combine

/// Drives the full-screen in-app reader on iOS. Other platforms push a
/// `DetailView` through navigation instead, so the router stays idle there.
@MainActor
final class ArticleRouter: ObservableObject {
    @Published var presentedDestination: ArticleDestination?

    func present(_ destination: ArticleDestination) {
        presentedDestination = destination
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

    func open(_ destination: ArticleDestination) {
        userState.markRead(destination.item)

#if os(iOS)
        if preferences.opensLinksInApp {
            router.present(destination)
        } else {
            openURL(destination.url)
        }
#else
        openURL(destination.url)
#endif
    }
}
