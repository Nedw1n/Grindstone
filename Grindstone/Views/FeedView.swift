import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var vm: FeedViewModel
    @EnvironmentObject private var rssStore: ManualRSSFeedStore
    @AppStorage("showPreviews") private var showPreviews = true
    @State private var isShowingRSSLibrary = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if !vm.featured.isEmpty {
                        FeaturedStrip(items: vm.featured)
                            .padding(.bottom, 8)
                    }

                    FilterBar(selection: $vm.filter)
                        .padding(.horizontal)
                        .padding(.bottom, 4)

                    if let errorMessage = vm.errorMessage {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }

                    if vm.filter == .rss {
                        RSSLibrarySummaryCard(
                            feedCount: rssStore.feeds.count,
                            enabledCount: rssStore.enabledFeeds.count,
                            actionTitle: rssStore.feeds.isEmpty ? "Add Feed" : "Manage"
                        ) {
                            isShowingRSSLibrary = true
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 10)
                    }

                    if vm.filtered.isEmpty {
                        FeedEmptyStateCard(
                            filter: vm.filter,
                            hasRSSFeeds: !rssStore.feeds.isEmpty
                        ) {
                            isShowingRSSLibrary = true
                        }
                        .padding(.horizontal)
                        .padding(.top, 24)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(vm.filtered) { item in
                                NavigationLink(value: item) {
                                    FeedItemRow(item: item, showPreview: showPreviews)
                                }
                                .buttonStyle(.plain)
                                Divider().padding(.leading)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Grindstone")
            .navigationDestination(for: FeedItem.self) { item in
                DetailView(item: item)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if vm.filter == .rss || !rssStore.feeds.isEmpty {
                        Button {
                            isShowingRSSLibrary = true
                        } label: {
                            Image(systemName: "dot.radiowaves.left.and.right")
                        }
                    }

                    Button {
                        showPreviews.toggle()
                    } label: {
                        Image(systemName: showPreviews ? "text.below.photo" : "list.bullet")
                    }
                }
            }
            .refreshable {
                await vm.refresh()
            }
            .overlay {
                if vm.isLoading && vm.items.isEmpty {
                    ProgressView("Loading…")
                }
            }
            .task {
                if vm.items.isEmpty {
                    await vm.refresh()
                }
            }
            .sheet(isPresented: $isShowingRSSLibrary) {
                RSSFeedManagerView()
                    .environmentObject(rssStore)
            }
        }
    }
}

private struct FeedEmptyStateCard: View {
    let filter: Source?
    let hasRSSFeeds: Bool
    let onManageRSS: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: iconName)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if filter == .rss {
                Button(hasRSSFeeds ? "Manage RSS Feeds" : "Add Your First Feed", action: onManageRSS)
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var title: String {
        switch filter {
        case .rss:
            return hasRSSFeeds ? "No RSS items yet" : "RSS library is empty"
        case let source?:
            return "No \(source.rawValue) items"
        case nil:
            return "No feed items yet"
        }
    }

    private var message: String {
        switch filter {
        case .rss:
            return hasRSSFeeds
                ? "Your enabled RSS feeds did not return any recent items right now. You can add more feeds or toggle existing ones back on."
                : "Paste in blog or publication feed URLs here. Marginal Revolution now lives in this manual RSS lane by default."
        case let source?:
            return "There isn’t anything to show for \(source.rawValue) right now. Pull to refresh and try again."
        case nil:
            return "The aggregator hasn’t returned any stories yet. Pull to refresh and we’ll try again."
        }
    }

    private var iconName: String {
        filter?.iconName ?? "tray"
    }
}

#Preview {
    let rssStore = ManualRSSFeedStore.shared

    FeedView()
        .environmentObject({
            let vm = FeedViewModel(rssStore: rssStore)
            vm.items = FeedItem.mock
            return vm
        }())
        .environmentObject(rssStore)
}
