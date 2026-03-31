import Foundation

struct FeedCacheSnapshot: Codable, Sendable {
    let lastUpdatedAt: Date
    private let cachedSources: [CachedSourceItems]

    init(sourceItems: [Source: [FeedItem]], lastUpdatedAt: Date) {
        self.lastUpdatedAt = lastUpdatedAt
        self.cachedSources = sourceItems
            .map { CachedSourceItems(source: $0.key, items: $0.value) }
            .sorted { $0.source.rawValue < $1.source.rawValue }
    }

    var sourceItems: [Source: [FeedItem]] {
        Dictionary(uniqueKeysWithValues: cachedSources.map { ($0.source, $0.items) })
    }
}

private struct CachedSourceItems: Codable, Sendable {
    let source: Source
    let items: [FeedItem]
}

enum FeedCacheStore {
    static func load() -> FeedCacheSnapshot? {
        do {
            let data = try Data(contentsOf: cacheURL)
            return try JSONDecoder().decode(FeedCacheSnapshot.self, from: data)
        } catch {
            return nil
        }
    }

    static func save(_ snapshot: FeedCacheSnapshot) {
        do {
            let directory = cacheDirectoryURL
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            // Ignore cache write failures; fresh network results remain available in memory.
        }
    }

    private static var cacheURL: URL {
        cacheDirectoryURL.appendingPathComponent("feed-cache.json")
    }

    private static var cacheDirectoryURL: URL {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseDirectory.appendingPathComponent("Grindstone", isDirectory: true)
    }
}
