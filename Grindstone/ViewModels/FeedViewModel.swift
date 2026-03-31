import Foundation
import Combine

@MainActor
final class FeedViewModel: ObservableObject {

    @Published var items: [FeedItem] = []
    @Published var filter: Source? = nil
    @Published var isLoading = false
    @Published var lastUpdatedAt: Date?
    @Published var errorMessage: String?
    @Published private var sourceItems: [Source: [FeedItem]] = [:]
    private let rssStore: ManualRSSFeedStore
    private var cancellables: Set<AnyCancellable> = []
    private var hasPerformedInitialRefresh = false

    init(rssStore: ManualRSSFeedStore) {
        self.rssStore = rssStore
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
    }

    func refreshOnLaunch() async {
        guard !hasPerformedInitialRefresh else { return }
        hasPerformedInitialRefresh = true
        await refresh()
    }

    /// Top item per source for the featured strip.
    var featured: [FeedItem] {
        Source.featuredSources.compactMap { source in
            sourceItems[source]?.first
                ?? items.first { $0.source == source }
        }
    }

    /// Items filtered by the selected source tab.
    var filtered: [FeedItem] {
        guard let f = filter else { return items }
        return sourceItems[f] ?? items.filter { $0.source == f }
    }

    func refresh() async {
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        errorMessage = nil
        let previousItems = items
        let previousSourceItems = sourceItems
        let previousLastUpdatedAt = lastUpdatedAt

        let results = await FeedLoader.loadAll(from: sourceDefinitions)
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
            previousSourceItems: previousSourceItems
        )
        sourceItems = effectiveSourceItems
        items = mergedItems(from: effectiveSourceItems)

        let successfulResults = nonCancelledResults.filter(\.wasSuccessful)
        if !successfulResults.isEmpty {
            let refreshedAt = Date()
            lastUpdatedAt = refreshedAt
            persistCache(sourceItems: effectiveSourceItems, lastUpdatedAt: refreshedAt)
        } else {
            lastUpdatedAt = previousLastUpdatedAt
        }

        let failures = nonCancelledResults.compactMap(\.errorMessage)
        let hasFreshItems = successfulResults.contains { !$0.items.isEmpty }

        if !failures.isEmpty {
            errorMessage = failures.joined(separator: "\n")
        } else if !hasFreshItems, items.isEmpty {
            errorMessage = "No feed items were returned."
        }
    }

    private var sourceDefinitions: [FeedSourceDefinition] {
        FeedSourceCatalog.definitions(rssFeeds: rssStore.feeds)
    }

    private func effectiveItems(
        from results: [SourceLoadResult],
        previousSourceItems: [Source: [FeedItem]]
    ) -> [Source: [FeedItem]] {
        var updated = previousSourceItems

        for result in results {
            if result.wasSuccessful {
                updated[result.source] = result.items
            } else {
                updated[result.source] = updated[result.source] ?? []
            }
        }

        return updated
    }

    private func mergedItems(from sourceItems: [Source: [FeedItem]]) -> [FeedItem] {
        let mergeCandidates = sourceDefinitions.flatMap { definition in
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
        items = mergedItems(from: snapshot.sourceItems)
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
                errorMessage: "\(definition.source.rawValue): \(error.localizedDescription)",
                wasCancelled: false,
                wasSuccessful: false
            )
        }
    }
}
