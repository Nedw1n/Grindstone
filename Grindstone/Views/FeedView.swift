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
                if !vm.failures.isEmpty {
                    FeedFailureBanner(
                        failures: vm.failures,
                        onRetry: { Task { await vm.refresh() } },
                        onDismiss: { vm.dismissFailures() }
                    )
                    .listRowInsets(FeedInsets.card)
                    .listRowSeparator(.hidden)
                    .paperListRow()
                }

                if isRSSLaneUnconfigured {
                    RSSLibraryPromptRow(hasFeeds: !rssStore.feeds.isEmpty) {
                        isShowingRSSLibrary = true
                    }
                    .listRowInsets(FeedInsets.card)
                    .listRowSeparator(.hidden)
                    .paperListRow()
                }

                if !stackItems.isEmpty {
                    SectionEyebrow("Top of the Stack", detail: "Cross-posted first")
                        .listRowInsets(FeedInsets.eyebrow)
                        .listRowSeparator(.hidden)
                        .paperListRow()

                    StoneStack(items: stackItems, showPreview: preferences.showPreviews, now: now)
                        .listRowInsets(FeedInsets.stack)
                        .listRowSeparator(.hidden)
                        .paperListRow()
                }

                if !streamItems.isEmpty {
                    SectionEyebrow(streamTitle, detail: "\(streamItems.count)")
                        .listRowInsets(FeedInsets.eyebrow)
                        .listRowSeparator(.hidden)
                        .paperListRow()

                    ForEach(streamItems) { item in
                        ArticleLink(destination: .article(item)) {
                            FeedItemRow(item: item, showPreview: preferences.showPreviews, now: now)
                        }
                        .listRowInsets(FeedInsets.story)
                        .paperListRow()
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            SaveSwipeButton(item: item)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            ReadSwipeButton(item: item)
                        }
                    }
                }

                if !onScreenItems.isEmpty {
                    FeedEndMarker(unreadCount: feedUserState.unreadCount(in: onScreenItems)) {
                        isConfirmingMarkAllRead = true
                    }
                    .listRowSeparator(.hidden)
                    .paperListRow()
                } else if !vm.isLoading, !isRSSLaneUnconfigured {
                    emptyState
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                        .paperListRow()
                }
            }
            .listStyle(.plain)
            .readableMeasure()
            .paperBackground()
            .safeAreaInset(edge: .top, spacing: 0) {
                filterBar
            }
            .navigationTitle("Grindstone")
            .navigationSubtitle(subtitle)
#if os(iOS)
            // A large title leaves a tall empty header above the filter bar's
            // safe-area inset until the list scrolls, so keep it compact.
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                feedToolbar
            }
            .refreshable {
                await vm.refresh()
            }
            .overlay {
                if vm.isLoading && vm.items.isEmpty {
                    StoneEmptyState(
                        "Gathering stories",
                        message: "Checking your sources for the latest.",
                        isBalancing: true
                    )
                }
            }
            .task {
                await vm.refreshOnLaunch()
            }
            .onReceive(clock) { date in
                now = date
            }
            .confirmationDialog(
                markAllReadTitle,
                isPresented: $isConfirmingMarkAllRead,
                titleVisibility: .visible
            ) {
                Button("Mark as Read") {
                    feedUserState.markRead(onScreenItems)
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

    // MARK: Filter bar

    private var filterBar: some View {
        FilterBar(selection: $vm.filter, sources: vm.visibleSources)
            // Lines the tabs up with the story column on iPad and Mac.
            .frame(maxWidth: Theme.readableWidth)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
#if os(visionOS)
            .background(.bar)
#else
            .background(Theme.paper)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(height: 0.5)
            }
#endif
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var feedToolbar: some ToolbarContent {
#if os(macOS)
        ToolbarItem(placement: .automatic) {
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await vm.refresh() }
            }
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
                .disabled(feedUserState.unreadCount(in: onScreenItems) == 0)

                Button("Manage RSS Feeds", systemImage: "dot.radiowaves.left.and.right") {
                    isShowingRSSLibrary = true
                }
            } label: {
                Label("Options", systemImage: "ellipsis")
            }
        }
    }

    // MARK: Derived state

    /// The source filter applied, with read stories dropped when they are hidden.
    private var visibleItems: [FeedItem] {
        let base = vm.filtered
        guard preferences.hideReadItems else { return base }
        return base.filter { !feedUserState.isRead($0) }
    }

    /// Top of the Stack, shown only on the unfiltered front page.
    private var stackItems: [FeedItem] {
        guard vm.filter == nil else { return [] }
        let featured = vm.featured
        guard preferences.hideReadItems else { return featured }
        return featured.filter { !feedUserState.isRead($0) }
    }

    /// Everything below the stack. Stories already on a stone are left out.
    private var streamItems: [FeedItem] {
        let stackIDs = Set(stackItems.map(\.id))
        guard !stackIDs.isEmpty else { return visibleItems }
        return visibleItems.filter { !stackIDs.contains($0.id) }
    }

    /// Every story on screen, stack and stream together, without repeats.
    private var onScreenItems: [FeedItem] {
        stackItems + streamItems
    }

    private var streamTitle: String {
        if let source = vm.filter {
            return source.rawValue
        }
        return stackItems.isEmpty ? "All Stories" : "More Stories"
    }

    private var isRSSLaneUnconfigured: Bool {
        vm.filter == .rss && rssStore.enabledFeeds.isEmpty
    }

    private var markAllReadTitle: String {
        let unread = feedUserState.unreadCount(in: onScreenItems)
        return unread == 1 ? "Mark 1 story as read?" : "Mark \(unread) stories as read?"
    }

    private var subtitle: String {
        if vm.isLoading, vm.lastUpdatedAt == nil {
            return "Refreshing…"
        }

        var parts: [String] = []

        if !onScreenItems.isEmpty {
            let unread = feedUserState.unreadCount(in: onScreenItems)
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
            StoneEmptyState("The stack is clear", message: "Every story here has been read.") {
                Button("Show Read Stories") {
                    preferences.hideReadItems = false
                }
                .buttonStyle(.pebble)
            }
        } else if let source = vm.filter {
            StoneEmptyState(
                "Nothing from \(source.rawValue)",
                message: "Pull to refresh, or check back in a little while."
            )
        } else {
            StoneEmptyState("No stories yet", message: "Pull down to gather the latest from your sources.") {
                Button("Refresh") {
                    Task { await vm.refresh() }
                }
                .buttonStyle(.pebble)
            }
        }
    }
}

/// Row insets for the feed's list, so every row lines up on the same margins.
private enum FeedInsets {
    static let story = EdgeInsets.storyRow
    static let eyebrow = EdgeInsets.sectionEyebrow
    static let stack = EdgeInsets(top: 4, leading: 16, bottom: 14, trailing: 16)
    static let card = EdgeInsets(top: 10, leading: 16, bottom: 6, trailing: 16)
}

#Preview {
    FeedView()
        .previewEnvironment()
}
