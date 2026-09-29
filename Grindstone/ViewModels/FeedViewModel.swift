import Foundation
import Combine

/// A source that failed to refresh, with the reason shown in the feed's banner.
struct SourceFailure: Identifiable, Equatable, Sendable {
    let source: Source
    let message: String

    var id: String { source.rawValue }
}

@MainActor
final class FeedViewModel: ObservableObject {

    @Published var items: [FeedItem] = []
    @Published var filter: Source? = nil
    @Published var isLoading = false
    @Published var lastUpdatedAt: Date?
    @Published var failures: [SourceFailure] = []
    @Published private var sourceItems: [Source: [FeedItem]] = [:]
    /// Every source each fetched story appeared on, keyed by item ID.
    @Published private var storySources: [String: Set<Source>] = [:]
    /// How strongly each front-page story stands on its own channel, by ID.
    private var standings: [String: Double] = [:]

    private let rssStore: ManualRSSFeedStore
    private let preferences: FeedPreferences
    private var cancellables: Set<AnyCancellable> = []
    private var hasPerformedInitialRefresh = false
    /// Set when feeds or sources change during a refresh. That refresh fetched
    /// with the old settings, so it fetches again once it lands.
    private var isRefreshStale = false

    init(rssStore: ManualRSSFeedStore, preferences: FeedPreferences) {
        self.rssStore = rssStore
        self.preferences = preferences
        restoreCachedItems()

        rssStore.$feeds
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshAfterSettingsChange()
            }
            .store(in: &cancellables)

        // `@Published` emits before the property is written, so the new value is
        // taken from the publisher rather than read back from `preferences`.
        preferences.$enabledSources
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabledSources in
                guard let self else { return }
                self.applyEnabledSources(enabledSources)
                self.refreshAfterSettingsChange()
            }
            .store(in: &cancellables)
    }

    func refreshOnLaunch() async {
        guard !hasPerformedInitialRefresh else { return }
        hasPerformedInitialRefresh = true
        await refresh()
    }

    /// Refreshes when the app comes back to the foreground and the last
    /// refresh is older than `staleInterval`. Launch has its own refresh.
    func refreshIfStale(now: Date = Date()) async {
        guard hasPerformedInitialRefresh else { return }
        if let lastUpdatedAt, now.timeIntervalSince(lastUpdatedAt) < Self.staleInterval {
            return
        }
        await refresh()
    }

    private static let staleInterval: TimeInterval = 15 * 60

    // MARK: Derived collections

    /// Sources that currently appear in filters, in canonical order.
    var visibleSources: [Source] {
        preferences.visibleSources
    }

    /// Top of the Stack: up to three stories from different sources, in
    /// Today's order. A story carried by several sources leads, but only when
    /// it also stands in the top half of its own page.
    var featured: [FeedItem] {
        var picks: [FeedItem] = []
        var usedSources = Set<Source>()

        let crossPosted = items.first { item in
            !item.crossRefs.isEmpty && (standings[item.id] ?? 0) >= Self.featuredCrossPostStanding
        }
        if let crossPosted {
            picks.append(crossPosted)
            usedSources.insert(crossPosted.source)
            usedSources.formUnion(crossPosted.crossRefs)
        }

        for item in items where picks.count < 3 && !usedSources.contains(item.source) {
            picks.append(item)
            usedSources.insert(item.source)
        }

        return picks
    }

    private static let featuredCrossPostStanding = 0.5

    /// Items filtered by the selected source tab.
    var filtered: [FeedItem] {
        guard let f = filter else { return items }
        guard preferences.isEnabled(f) else { return [] }
        if f == .rss, !rssStore.feeds.contains(where: \.isEnabled) { return [] }
        guard let laneItems = sourceItems[f] else {
            return items.filter { $0.source == f }
        }
        // A source's own lane shows where else each story ran, too.
        return laneItems.map { item in
            var annotated = item
            let sources = storySources[item.id] ?? []
            annotated.crossRefs = Source.allCases.filter { $0 != item.source && sources.contains($0) }
            return annotated
        }
    }

    /// Everything fetched from every source, deduplicated. Search runs over this
    /// so it can find stories that did not make the merged front page.
    var searchCorpus: [FeedItem] {
        var seen = Set<String>()
        var corpus: [FeedItem] = []

        for item in items where seen.insert(item.id).inserted {
            corpus.append(item)
        }

        for source in Source.allCases {
            for item in sourceItems[source] ?? [] where seen.insert(item.id).inserted {
                corpus.append(item)
            }
        }

        return corpus
    }

    // MARK: Refresh

    func refresh() async {
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        repeat {
            isRefreshStale = false
            await fetchAndMerge()
        } while isRefreshStale && !Task.isCancelled
    }

    /// Refreshes after feeds or sources change. A refresh already under way
    /// fetched with the old settings, so it is marked to run again.
    private func refreshAfterSettingsChange() {
        isRefreshStale = true
        Task {
            await refresh()
        }
    }

    private func fetchAndMerge() async {
        let definitions = sourceDefinitions(enabledSources: preferences.enabledSources)
        let results = await FeedLoader.loadAll(from: definitions)
        guard !Task.isCancelled else { return }

        // Settings may have changed while fetching. Merge against the current
        // ones so a source switched off in the meantime doesn't come back.
        let currentDefinitions = sourceDefinitions(enabledSources: preferences.enabledSources)
        let activeSources = Set(currentDefinitions.map(\.source))
        let nonCancelledResults = results.filter { !$0.wasCancelled && activeSources.contains($0.source) }
        guard !nonCancelledResults.isEmpty else { return }

        let effectiveSourceItems = effectiveItems(
            from: nonCancelledResults,
            previousSourceItems: sourceItems,
            activeSources: activeSources
        )
        sourceItems = effectiveSourceItems
        applyMerge(from: effectiveSourceItems, definitions: currentDefinitions)

        let successfulResults = nonCancelledResults.filter(\.wasSuccessful)
        if !successfulResults.isEmpty {
            let refreshedAt = Date()
            lastUpdatedAt = refreshedAt
            persistCache(sourceItems: effectiveSourceItems, lastUpdatedAt: refreshedAt)
        }

        failures = nonCancelledResults.compactMap { result in
            result.errorMessage.map { SourceFailure(source: result.source, message: $0) }
        }
    }

    func dismissFailures() {
        failures = []
    }

    // MARK: Private helpers

    private func sourceDefinitions(enabledSources: Set<Source>) -> [FeedSourceDefinition] {
        FeedSourceCatalog.definitions(rssFeeds: rssStore.feeds, enabledSources: enabledSources)
    }

    private func applyEnabledSources(_ enabledSources: Set<Source>) {
        if let filter, filter != .rss, !enabledSources.contains(filter) {
            self.filter = nil
        }

        let definitions = sourceDefinitions(enabledSources: enabledSources)
        applyMerge(from: sourceItems, definitions: definitions)
    }

    private func effectiveItems(
        from results: [SourceLoadResult],
        previousSourceItems: [Source: [FeedItem]],
        activeSources: Set<Source>
    ) -> [Source: [FeedItem]] {
        var updated = previousSourceItems

        for result in results {
            if result.wasSuccessful {
                updated[result.source] = Self.keepingFirstSeenDates(
                    in: result.items,
                    previous: previousSourceItems[result.source] ?? []
                )
            } else {
                updated[result.source] = updated[result.source] ?? []
            }
        }

        // Sources that were switched off (or RSS with no enabled feeds) no longer
        // fetch, so their cached stories must not linger.
        for source in Source.allCases where !activeSources.contains(source) {
            updated[source] = nil
        }

        return updated
    }

    /// Stories whose feed gives no date are stamped with the time they were
    /// fetched. Keeps the stamp from the first fetch, so they age like any
    /// other story instead of looking brand new on every refresh.
    private static func keepingFirstSeenDates(
        in items: [FeedItem],
        previous: [FeedItem]
    ) -> [FeedItem] {
        guard items.contains(where: \.isUndated) else { return items }

        let firstSeen = Dictionary(
            previous.filter(\.isUndated).map { ($0.id, $0.publishedAt) },
            uniquingKeysWith: { first, _ in first }
        )
        let restamped = items.map { item -> FeedItem in
            guard item.isUndated, let firstSeenAt = firstSeen[item.id] else { return item }
            var copy = item
            copy.publishedAt = firstSeenAt
            return copy
        }

        // Newest-first lanes put restamped stories back in their place by age;
        // a ranked page keeps its own order.
        guard !restamped.contains(where: \.isRanked) else { return restamped }
        return FeedRankingEngine.assignIntraSourceRanks(
            to: restamped.sorted { $0.publishedAt > $1.publishedAt }
        )
    }

    /// Builds the merged front page. Stories are matched across the whole of
    /// each source's fetch, so a story low on one source still counts as
    /// cross-posted, and then ordered by fair share (see `FeedRankingEngine`).
    private func applyMerge(
        from sourceItems: [Source: [FeedItem]],
        definitions: [FeedSourceDefinition]
    ) {
        let allFetched = definitions.flatMap { sourceItems[$0.source] ?? [] }
        guard !allFetched.isEmpty else {
            items = []
            storySources = [:]
            standings = [:]
            return
        }

        let merged = CrossRefEngine.mergeStories(allFetched)
        storySources = merged.storySources

        let ranking = FeedRankingEngine.fairShare(merged.items)
        standings = ranking.standings
        items = ranking.items
    }

    private func restoreCachedItems() {
        guard let snapshot = FeedCacheStore.load() else { return }
        sourceItems = snapshot.sourceItems
        applyMerge(
            from: snapshot.sourceItems,
            definitions: sourceDefinitions(enabledSources: preferences.enabledSources)
        )
        lastUpdatedAt = snapshot.lastUpdatedAt
    }

    private func persistCache(sourceItems: [Source: [FeedItem]], lastUpdatedAt: Date) {
        let snapshot = FeedCacheSnapshot(sourceItems: sourceItems, lastUpdatedAt: lastUpdatedAt)
        FeedCacheStore.save(snapshot)
    }
}

private struct SourceLoadResult: Sendable {
    let source: Source
    let items: [FeedItem]
    let errorMessage: String?
    let wasCancelled: Bool
    let wasSuccessful: Bool
}

private enum FeedLoader {
    static func loadAll(from definitions: [FeedSourceDefinition]) async -> [SourceLoadResult] {
        await withTaskGroup(of: SourceLoadResult.self, returning: [SourceLoadResult].self) { group in
            for definition in definitions {
                group.addTask {
                    await load(definition)
                }
            }

            var results: [SourceLoadResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    private static func load(_ definition: FeedSourceDefinition) async -> SourceLoadResult {
        do {
            return SourceLoadResult(
                source: definition.source,
                items: try await FeedRequestTimeout.run {
                    try await definition.fetch()
                },
                errorMessage: nil,
                wasCancelled: false,
                wasSuccessful: true
            )
        } catch is CancellationError {
            return SourceLoadResult(
                source: definition.source,
                items: [],
                errorMessage: nil,
                wasCancelled: true,
                wasSuccessful: false
            )
        } catch {
            return SourceLoadResult(
                source: definition.source,
                items: [],
                errorMessage: error.localizedDescription,
                wasCancelled: false,
                wasSuccessful: false
            )
        }
    }
}
