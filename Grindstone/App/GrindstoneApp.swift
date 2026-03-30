import SwiftUI

@main
struct GrindstoneApp: App {
    @StateObject private var feedViewModel = FeedViewModel()

    var body: some Scene {
        WindowGroup {
            FeedView()
                .environmentObject(feedViewModel)
        }
    }
}
