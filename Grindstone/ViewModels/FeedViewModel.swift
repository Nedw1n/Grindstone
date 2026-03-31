import Foundation
import Combine

@MainActor
final class FeedViewModel: ObservableObject {

    @Published var items: [FeedItem] = []
    @Published var filter: Source? = nil
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private var sourceItems: [Source: [FeedItem]] = [:]
    private let rssStore: ManualRSSFeedStore
    private var cancellables: Set<AnyCancellable> = []

    init(rssStore: ManualRSSFeedStore) {
        self.rssStore = rssStore

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

        let results = await FeedLoader.loadAll(from: sourceDefinitions)
        guard !Task.isCancelled else {
            items = previousItems
            sourceItems = previousSourceItems
            return
        }

        let nonCancelledResults = results.filter { !$0.wasCancelled }
        guard !nonCancelledResults.isEmpty else {
            items = previousItems
            sourceItems = previousSourceItems
            return
        }

        let effectiveSourceItems = effectiveItems(
            from: nonCancelledResults,
            previousSourceItems: previousSourceItems
        )
        sourceItems = effectiveSourceItems
        items = mergedItems(from: effectiveSourceItems)

        let failures = nonCancelledResults.compactMap(\.errorMessage)
        let hasFreshItems = nonCancelledResults.contains { !$0.items.isEmpty }

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
            if !result.items.isEmpty {
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
        return crossReffed.sorted { $0.publishedAt > $1.publishedAt }
    }
}

private struct SourceLoadResult: Sendable {
    let source: Source
    let items: [FeedItem]
    let errorMessage: String?
    let wasCancelled: Bool
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
                items: try await definition.fetch(),
                errorMessage: nil,
                wasCancelled: false
            )
        } catch is CancellationError {
            return SourceLoadResult(
                source: definition.source,
                items: [],
                errorMessage: nil,
                wasCancelled: true
            )
        } catch {
            return SourceLoadResult(
                source: definition.source,
                items: [],
                errorMessage: "\(definition.source.rawValue): \(error.localizedDescription)",
                wasCancelled: false
            )
        }
    }
}
