import SwiftUI

/// Shared, in-memory state for Xcode previews. Backed by a throwaway
/// `UserDefaults` suite so previews never touch real user data.
@MainActor
enum PreviewWorld {
    private static let suiteName = "GrindstonePreviews"

    static let defaults: UserDefaults = {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }()

    static let rssStore = ManualRSSFeedStore(defaults: defaults)
    static let preferences = FeedPreferences(defaults: defaults)
    static let router = ArticleRouter()
    static let session = ReadingSessionStore(defaults: defaults)
    static let engagement = EngagementLog(fileURL: nil)

    static let userState: FeedUserStateStore = {
        let store = FeedUserStateStore(defaults: defaults)
        store.save(FeedItem.mock[0])
        store.markRead(FeedItem.mock[1])
        return store
    }()

    static let viewModel: FeedViewModel = {
        let viewModel = FeedViewModel(rssStore: rssStore, preferences: preferences)
        viewModel.items = FeedItem.mock
        viewModel.lastUpdatedAt = Date().addingTimeInterval(-180)
        return viewModel
    }()
}

extension View {
    func previewEnvironment() -> some View {
        environmentObject(PreviewWorld.viewModel)
            .environmentObject(PreviewWorld.rssStore)
            .environmentObject(PreviewWorld.userState)
            .environmentObject(PreviewWorld.preferences)
            .environmentObject(PreviewWorld.router)
            .environmentObject(PreviewWorld.session)
            .environmentObject(PreviewWorld.engagement)
    }
}
