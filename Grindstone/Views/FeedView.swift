import SwiftUI
import Combine

struct FeedView: View {
    @EnvironmentObject private var vm: FeedViewModel
    @EnvironmentObject private var feedUserState: FeedUserStateStore
    @EnvironmentObject private var rssStore: ManualRSSFeedStore
    @EnvironmentObject private var preferences: FeedPreferences
    @EnvironmentObject private var session: ReadingSessionStore

    @State private var isShowingRSSLibrary = false
    @State private var isConfirmingMarkAllRead = false
    @State private var now = Date()
    @State private var availableWidth: CGFloat = 0

    /// Re-renders relative timestamps ("3m ago") once a minute.
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Group {
                if usesWideLayout {
                    wideLayout
                } else {
                    storyList(showsStack: true)
                }
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                availableWidth = width
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
            .onChange(of: vm.searchCorpus.map(\.id), initial: true) { _, _ in
                session.recordArrivals(vm.searchCorpus)
            }
            .confirmationDialog(
                markAllReadTitle,
                isPresented: $isConfirmingMarkAllRead,
                titleVisibility: .visible
            ) {
                Button("Mark as Read") {
                    EngagementLog.shared.recordMarkAllRead(onScreenItems, userState: feedUserState)
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

    // MARK: Layouts

    /// iPad and Mac: Top of the Stack gets a rail of its own beside the
    /// stories, so the stones keep the proportions of pebbles instead of
    /// stretching across the window. The pair is centered on very wide windows.
    private var wideLayout: some View {
        HStack(spacing: 0) {
            StackRail(items: railItems, showPreview: preferences.showPreviews, now: now)

            Rectangle()
                .fill(Theme.hairline)
                .frame(width: 0.5)

            storyList(showsStack: false)
                .frame(maxWidth: FeedWideLayout.storyColumnMaxWidth)
        }
        .frame(maxWidth: FeedWideLayout.maxWidth)
        .frame(maxWidth: .infinity)
        .background(Theme.paper)
    }

    /// The story list. On iPhone it carries the stack at the top; in the wide
    /// layout the stack lives in the rail instead.
    private func storyList(showsStack: Bool) -> some View {
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

            if showsStack, !stackItems.isEmpty {
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
                let sections = streamSections

                if let newSince = session.newSince, !sections.new.isEmpty, !sections.earlier.isEmpty {
                    // What arrived since your last visit comes first, so the
                    // "Earlier" line marks where you left off.
                    SectionEyebrow(newSinceTitle(newSince), detail: "\(sections.new.count)")
                        .listRowInsets(FeedInsets.eyebrow)
                        .listRowSeparator(.hidden)
                        .paperListRow()

                    storyRows(sections.new, positionOffset: 0)

                    SectionEyebrow("Earlier", detail: "\(sections.earlier.count)")
                        .listRowInsets(FeedInsets.eyebrow)
                        .listRowSeparator(.hidden)
                        .paperListRow()

                    storyRows(sections.earlier, positionOffset: sections.new.count)
                } else {
                    SectionEyebrow(streamTitle, detail: "\(streamItems.count)")
                        .listRowInsets(FeedInsets.eyebrow)
                        .listRowSeparator(.hidden)
                        .paperListRow()

                    storyRows(streamItems, positionOffset: 0)
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
        .paperBackground()
        .safeAreaInset(edge: .top, spacing: 0) {
            filterBar
        }
        .refreshable {
            await vm.refresh()
        }
    }

    /// Story rows, each tagged with its position on the feed for the engagement log.
    private func storyRows(_ items: [FeedItem], positionOffset: Int) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            ArticleLink(destination: .article(item)) {
                FeedItemRow(item: item, showPreview: preferences.showPreviews, now: now)
            }
            .environment(\.storyPlacement, StoryPlacement(surface: .feed, position: positionOffset + index))
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

    // MARK: Filter bar

    private var filterBar: some View {
        FilterBar(selection: $vm.filter, sources: vm.visibleSources)
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

    /// The rail's stones in the wide layout. Unlike the in-list stack, the
    /// rail stays put when a source filter is chosen.
    private var railItems: [FeedItem] {
        let featured = vm.featured
        guard preferences.hideReadItems else { return featured }
        return featured.filter { !feedUserState.isRead($0) }
    }

    private var usesWideLayout: Bool {
        LayoutPlatform.allowsWideLayouts
            && availableWidth >= FeedWideLayout.minimumWidth
            && !railItems.isEmpty
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

    /// The stream split by arrival: stories new since the last visit, then the rest.
    private var streamSections: (new: [FeedItem], earlier: [FeedItem]) {
        var new: [FeedItem] = []
        var earlier: [FeedItem] = []
        for item in streamItems {
            if session.isNew(item) {
                new.append(item)
            } else {
                earlier.append(item)
            }
        }
        return (new, earlier)
    }

    /// "New since 9:40 AM", "New since yesterday", or "New since Monday".
    private func newSinceTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "New since \(date.formatted(date: .omitted, time: .shortened))"
        }
        if calendar.isDateInYesterday(date) {
            return "New since yesterday"
        }
        return "New since \(date.formatted(.dateTime.weekday(.wide)))"
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

/// Measurements for the iPad and Mac layout.
private enum FeedWideLayout {
    /// Below this width the phone layout is used, rail and all folded into one list.
    static let minimumWidth: CGFloat = 760
    static let railWidth: CGFloat = 340
    static let storyColumnMaxWidth: CGFloat = 760
    static let maxWidth: CGFloat = railWidth + storyColumnMaxWidth
}

/// The wide layout's left column: a dated masthead over Top of the Stack.
private struct StackRail: View {
    let items: [FeedItem]
    let showPreview: Bool
    let now: Date

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(now.formatted(.dateTime.weekday(.wide)))
                        .font(.system(.largeTitle, design: .serif).weight(.semibold))
                        .foregroundStyle(Theme.ink)

                    Text(now.formatted(.dateTime.month(.wide).day()))
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(Theme.inkMuted)
                }
                .padding(.horizontal, 4)
                .accessibilityElement(children: .combine)

                SectionEyebrow("Top of the Stack")
                    .padding(.horizontal, 4)
                    .padding(.top, 28)
                    .padding(.bottom, 12)

                StoneStack(items: items, showPreview: showPreview, now: now)

                Text("Cross-posted stories come first, then the top story from each source.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, 16)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .scrollIndicators(.hidden)
        .frame(width: FeedWideLayout.railWidth)
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
