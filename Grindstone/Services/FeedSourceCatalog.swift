import Foundation

struct FeedSourceDefinition: Sendable {
    let source: Source
    let fetch: @Sendable () async throws -> [FeedItem]
}

enum FeedSourceCatalog {
    private static let builtInDefinitions: [FeedSourceDefinition] = [
        FeedSourceDefinition(source: .hn) {
            try await HNService.fetch(limit: 60)
        },
        FeedSourceDefinition(source: .memo) {
            try await MemeorandumService.fetch(limit: 40)
        },
        FeedSourceDefinition(source: .biotech) {
            try await BiotechService.fetch()
        },
    ]

    /// Definitions for every source the user has switched on. RSS is included
    /// whenever at least one manual feed is enabled.
    static func definitions(
        rssFeeds: [ManualRSSFeed],
        enabledSources: Set<Source>
    ) -> [FeedSourceDefinition] {
        var definitions = builtInDefinitions.filter { enabledSources.contains($0.source) }

        if rssFeeds.contains(where: \.isEnabled) {
            definitions.append(
                FeedSourceDefinition(source: .rss) {
                    try await ManualRSSService.fetch(feeds: rssFeeds)
                }
            )
        }

        return definitions
    }
}
