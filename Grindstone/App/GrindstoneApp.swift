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
#if os(macOS)
        .defaultSize(width: 1080, height: 780)
#endif
        .commands {
            feedCommands
        }

#if os(macOS)
        // On the Mac, settings live in their own window under ⌘, rather than
        // in a sidebar tab.
        Settings {
            SettingsView()
                .environmentObject(feedViewModel)
                .environmentObject(rssStore)
                .environmentObject(feedUserState)
                .environmentObject(preferences)
                .environmentObject(router)
                .frame(minWidth: 480, idealWidth: 540, minHeight: 560, idealHeight: 680)
        }
#endif
    }

    /// A Feed menu on the Mac, and keyboard shortcuts on iPad.
    @CommandsBuilder
    private var feedCommands: some Commands {
        CommandMenu("Feed") {
            Button("Refresh") {
                Task { await feedViewModel.refresh() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(feedViewModel.isLoading)

            Divider()

            Button("All Sources") {
                feedViewModel.filter = nil
            }
            .keyboardShortcut("1", modifiers: .command)

            ForEach(Source.allCases) { source in
                Button(source.rawValue) {
                    feedViewModel.filter = source
                }
                .keyboardShortcut(source.filterShortcut, modifiers: .command)
                .disabled(!preferences.isEnabled(source))
            }

            Divider()

            Toggle("Hide Read Stories", isOn: $preferences.hideReadItems)
                .keyboardShortcut("h", modifiers: [.command, .shift])

            Toggle("Show Previews", isOn: $preferences.showPreviews)
        }
    }
}

private extension Source {
    /// ⌘2 to ⌘5 pick a source; ⌘1 is All.
    var filterShortcut: KeyEquivalent {
        switch self {
        case .hn: return "2"
        case .memo: return "3"
        case .biotech: return "4"
        case .rss: return "5"
        }
    }
}
