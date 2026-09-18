import SwiftUI
import Combine

struct FeedView: View {
    @EnvironmentObject private var vm: FeedViewModel
    @EnvironmentObject private var feedUserState: FeedUserStateStore
    @EnvironmentObject private var rssStore: ManualRSSFeedStore
    @EnvironmentObject private var preferences: FeedPreferences

    @State private var isShowingRSSLibrary = false
    @State private var isConfirmingMarkAllRead = false
    @State private var now = Date()

    /// Re-renders relative timestamps ("3m ago") once a minute.
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            List {
                if vm.filter == nil, !vm.featured.isEmpty {
                    Section {
                        FeaturedStrip(items: vm.featured)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }

                Section {
                    if !vm.failures.isEmpty {
                        FeedFailureBanner(
                            failures: vm.failures,
                            onRetry: { Task { await vm.refresh() } },
                            onDismiss: { vm.dismissFailures() }
                        )
                        .listRowSeparator(.hidden)
                    }

                    if isRSSLaneUnconfigured {
                        RSSLibraryPromptRow(hasFeeds: !rssStore.feeds.isEmpty) {
                            isShowingRSSLibrary = true
                        }
                        .listRowSeparator(.hidden)
                    }

                    if visibleItems.isEmpty {
                        if !vm.isLoading, !isRSSLaneUnconfigured {
                            emptyState
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                                .listRowSeparator(.hidden)
                        }
                    } else {
                        ForEach(visibleItems) { item in
                            ArticleLink(destination: .article(item)) {
                                FeedItemRow(item: item, showPreview: preferences.showPreviews, now: now)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                SaveSwipeButton(item: item)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                ReadSwipeButton(item: item)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .safeAreaInset(edge: .top, spacing: 0) {
                FilterBar(selection: $vm.filter, sources: vm.visibleSources)
                    .padding(.vertical, 8)
                    .background(.bar)
            }
            .navigationTitle("Grindstone")
            .navigationSubtitle(subtitle)
            .toolbar {
                feedToolbar
            }
            .refreshable {
                await vm.refresh()
            }
            .overlay {
                if vm.isLoading && vm.items.isEmpty {
                    ProgressView("Loading stories…")
                }
            }
            .task {
                await vm.refreshOnLaunch()
            }
            .onReceive(clock) { date in
                now = date
            }
            .confirmationDialog(
                "Mark \(visibleItems.count) stories as read?",
                isPresented: $isConfirmingMarkAllRead,
                titleVisibility: .visible
            ) {
                Button("Mark as Read") {
                    feedUserState.markRead(visibleItems)
                }
            }
            .sheet(isPresented: $isShowingRSSLibrary) {
                RSSFeedManagerSheet()
                    .environmentObject(rssStore)
            }
            .navigationDestination(for: ArticleDestination.self) { destination in
                DetailView(destination: destination)
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var feedToolbar: some ToolbarContent {
#if os(macOS)
        ToolbarItem(placement: .automatic) {
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await vm.refresh() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(vm.isLoading)
        }
#endif

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Toggle("Hide Read Stories", systemImage: "eye.slash", isOn: $preferences.hideReadItems)
                Toggle("Show Previews", systemImage: "text.alignleft", isOn: $preferences.showPreviews)

                Divider()

                Button("Mark All as Read", systemImage: "checkmark.circle") {
                    isConfirmingMarkAllRead = true
                }
                .disabled(feedUserState.unreadCount(in: visibleItems) == 0)

                Button("Manage RSS Feeds", systemImage: "dot.radiowaves.left.and.right") {
                    isShowingRSSLibrary = true
                }
            } label: {
                Label("Options", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: Derived state

    private var visibleItems: [FeedItem] {
        let base = vm.filtered
        guard preferences.hideReadItems else { return base }
        return base.filter { !feedUserState.isRead($0) }
    }

    private var isRSSLaneUnconfigured: Bool {
        vm.filter == .rss && rssStore.enabledFeeds.isEmpty
    }

    private var subtitle: String {
        if vm.isLoading, vm.lastUpdatedAt == nil {
            return "Refreshing…"
        }

        var parts: [String] = []

        if !visibleItems.isEmpty {
            let unread = feedUserState.unreadCount(in: visibleItems)
            parts.append(unread == 0 ? "All caught up" : "\(unread) unread")
        }

        if let lastUpdatedAt = vm.lastUpdatedAt {
            parts.append("Updated \(lastUpdatedAt.relativeFormatted(relativeTo: now))")
        }

        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var emptyState: some View {
        if preferences.hideReadItems, !vm.filtered.isEmpty {
            ContentUnavailableView {
                Label("All Caught Up", systemImage: "checkmark.circle")
            } description: {
                Text("Every story here is marked read.")
            } actions: {
                Button("Show Read Stories") {
                    preferences.hideReadItems = false
                }
            }
        } else if let source = vm.filter {
            ContentUnavailableView {
                Label("Nothing from \(source.rawValue)", systemImage: source.iconName)
            } description: {
                Text("Pull to refresh, or check back in a little while.")
            }
        } else {
            ContentUnavailableView {
                Label("No Stories Yet", systemImage: "tray")
            } description: {
                Text("Pull to refresh to load the latest from your sources.")
            } actions: {
                Button("Refresh") {
                    Task { await vm.refresh() }
                }
            }
        }
    }
}

#Preview {
    FeedView()
        .previewEnvironment()
}
