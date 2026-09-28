import SwiftUI

enum AppTab: Hashable {
    case feed
    case saved
    case settings
    case search
}

/// Top-level layout: a tab bar on iPhone, a sidebar on iPad and Mac.
struct RootView: View {
    @State private var selectedTab: AppTab = .feed

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Today", systemImage: "square.stack.3d.up", value: AppTab.feed) {
                FeedView()
            }

            Tab("Saved", systemImage: "bookmark", value: AppTab.saved) {
                SavedArticlesView()
            }

#if !os(macOS)
            // The Mac opens settings in their own window instead (⌘,).
            Tab("Settings", systemImage: "slider.horizontal.3", value: AppTab.settings) {
                SettingsView()
            }
#endif

            Tab(value: AppTab.search, role: .search) {
                SearchView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .modifier(InAppReaderPresentation())
    }
}

/// Hosts the full-screen Safari reader on iOS. Other platforms open stories by
/// pushing `DetailView`, so this is a no-op there.
private struct InAppReaderPresentation: ViewModifier {
    @EnvironmentObject private var router: ArticleRouter
    @EnvironmentObject private var preferences: FeedPreferences

    func body(content: Content) -> some View {
#if os(iOS)
        content
            .tabBarMinimizeBehavior(.onScrollDown)
            .fullScreenCover(item: $router.presentedDestination) { destination in
                SafariView(
                    url: destination.url,
                    entersReaderIfAvailable: preferences.prefersReaderMode && destination.kind == .article
                )
                .ignoresSafeArea()
            }
#else
        content
#endif
    }
}

#Preview {
    RootView()
        .previewEnvironment()
}
