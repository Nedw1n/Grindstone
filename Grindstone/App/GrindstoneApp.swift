import SwiftUI

@main
struct GrindstoneApp: App {
    @StateObject private var rssStore: ManualRSSFeedStore
    @StateObject private var feedViewModel: FeedViewModel

    init() {
        let rssStore = ManualRSSFeedStore.shared
        _rssStore = StateObject(wrappedValue: rssStore)
        _feedViewModel = StateObject(wrappedValue: FeedViewModel(rssStore: rssStore))
    }

    var body: some Scene {
        WindowGroup {
            FeedView()
                .environmentObject(feedViewModel)
                .environmentObject(rssStore)
        }
    }
}
