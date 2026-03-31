import Foundation

struct FeedSourceDefinition: Sendable {
    let source: Source
    let mergeLimit: Int
    let fetch: @Sendable () async throws -> [FeedItem]
}

enum FeedSourceCatalog {
    private static let builtInDefinitions: [FeedSourceDefinition] = [
        FeedSourceDefinition(source: .hn, mergeLimit: 20) {
            try await HNService.fetch(limit: 60)
        },
        FeedSourceDefinition(source: .memo, mergeLimit: 20) {
            try await MemeorandumService.fetch(limit: 40)
        },
        FeedSourceDefinition(source: .biotech, mergeLimit: 15) {
            try await BiotechService.fetch(limit: 24)
        },
    ]

    static func definitions(rssFeeds: [ManualRSSFeed]) -> [FeedSourceDefinition] {
        builtInDefinitions + [
            FeedSourceDefinition(source: .rss, mergeLimit: 20) {
                try await ManualRSSService.fetch(feeds: rssFeeds, limit: 32)
            },
        ]
    }
}
