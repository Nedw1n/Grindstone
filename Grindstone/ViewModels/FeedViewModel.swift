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

    private let rssStore: ManualRSSFeedStore
    private let preferences: FeedPreferences
    private var cancellables: Set<AnyCancellable> = []
    private var hasPerformedInitialRefresh = false

    init(rssStore: ManualRSSFeedStore, preferences: FeedPreferences) {
        self.rssStore = rssStore
        self.preferences = preferences
        restoreCachedItems()

        rssStore.$feeds
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                Task {
                    await self.refresh()
                }
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
                Task {
                    await self.refresh()
                }
            }
            .store(in: &cancellables)
    }

    func refreshOnLaunch() async {
        guard !hasPerformedInitialRefresh else { return }
        hasPerformedInitialRefresh = true
        await refresh()
    }

    // MARK: Derived collections

    /// Sources that currently appear in filters, in canonical order.
    var visibleSources: [Source] {
        preferences.visibleSources
    }

    /// Stories for the featured strip: cross-posted stories first (the app's
    /// strongest signal that something matters), then the top story of each source.
    var featured: [FeedItem] {
        var picks: [FeedItem] = []
        var seen = Set<String>()

        for item in items where !item.crossRefs.isEmpty {
            guard seen.insert(item.id).inserted else { continue }
            picks.append(item)
            if picks.count == 3 { break }
        }

        for source in Source.featuredSources where preferences.isEnabled(source) {
            guard let top = sourceItems[source]?.first ?? items.first(where: { $0.source == source }),
                  seen.insert(top.id).inserted else { continue }
            picks.append(top)
        }

        return Array(picks.prefix(6))
    }

    /// Items filtered by the selected source tab.
    var filtered: [FeedItem] {
        guard let f = filter else { return items }
        guard preferences.isEnabled(f) else { return [] }
        if f == .rss, !rssStore.feeds.contains(where: \.isEnabled) { return [] }
        return sourceItems[f] ?? items.filter { $0.source == f }
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

        let previousItems = items
        let previousSourceItems = sourceItems
        let previousLastUpdatedAt = lastUpdatedAt
        let definitions = sourceDefinitions(enabledSources: preferences.enabledSources)

        let results = await FeedLoader.loadAll(from: definitions)
        guard !Task.isCancelled else {
            items = previousItems
            sourceItems = previousSourceItems
            lastUpdatedAt = previousLastUpdatedAt
            return
        }

        let nonCancelledResults = results.filter { !$0.wasCancelled }
        guard !nonCancelledResults.isEmpty else {
            items = previousItems
            sourceItems = previousSourceItems
            lastUpdatedAt = previousLastUpdatedAt
            return
        }

        let effectiveSourceItems = effectiveItems(
            from: nonCancelledResults,
            previousSourceItems: previousSourceItems,
            activeSources: Set(definitions.map(\.source))
        )
        sourceItems = effectiveSourceItems
        items = mergedItems(from: effectiveSourceItems, definitions: definitions)

        let successfulResults = nonCancelledResults.filter(\.wasSuccessful)
        if !successfulResults.isEmpty {
            let refreshedAt = Date()
            lastUpdatedAt = refreshedAt
            persistCache(sourceItems: effectiveSourceItems, lastUpdatedAt: refreshedAt)
        } else {
            lastUpdatedAt = previousLastUpdatedAt
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
        items = mergedItems(from: sourceItems, definitions: definitions)
    }

    private func effectiveItems(
        from results: [SourceLoadResult],
        previousSourceItems: [Source: [FeedItem]],
        activeSources: Set<Source>
    ) -> [Source: [FeedItem]] {
        var updated = previousSourceItems

        for result in results {
            if result.wasSuccessful {
                updated[result.source] = result.items
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

    private func mergedItems(
        from sourceItems: [Source: [FeedItem]],
        definitions: [FeedSourceDefinition]
    ) -> [FeedItem] {
        let mergeCandidates = definitions.flatMap { definition in
            Array((sourceItems[definition.source] ?? []).prefix(definition.mergeLimit))
        }

        guard !mergeCandidates.isEmpty else { return [] }

        let deduped = CrossRefEngine.deduplicate(mergeCandidates)
        let crossReffed = CrossRefEngine.compute(deduped)
        return FeedRankingEngine.sortMergedItems(crossReffed)
    }

    private func restoreCachedItems() {
        guard let snapshot = FeedCacheStore.load() else { return }
        sourceItems = snapshot.sourceItems
        items = mergedItems(
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
