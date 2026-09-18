import SwiftUI

@main
struct GrindstoneApp: App {
    @StateObject private var rssStore: ManualRSSFeedStore
    @StateObject private var preferences: FeedPreferences
    @StateObject private var feedViewModel: FeedViewModel
    @StateObject private var feedUserState: FeedUserStateStore
    @StateObject private var router = ArticleRouter()

    init() {
        let rssStore = ManualRSSFeedStore.shared
        let preferences = FeedPreferences.shared
        _rssStore = StateObject(wrappedValue: rssStore)
        _preferences = StateObject(wrappedValue: preferences)
        _feedViewModel = StateObject(
            wrappedValue: FeedViewModel(rssStore: rssStore, preferences: preferences)
        )
        _feedUserState = StateObject(wrappedValue: FeedUserStateStore.shared)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(feedViewModel)
                .environmentObject(rssStore)
                .environmentObject(feedUserState)
                .environmentObject(preferences)
                .environmentObject(router)
        }
    }
}
