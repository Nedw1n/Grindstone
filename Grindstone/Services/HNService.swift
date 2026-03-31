import Foundation

/// Fetches ranked stories from the official Hacker News homepage API.
enum HNService {

    private static let topStoriesURL = URL(string: "https://hacker-news.firebaseio.com/v0/topstories.json")!

    static func fetch(limit: Int = 60) async throws -> [FeedItem] {
        let (data, response) = try await URLSession.shared.data(from: topStoriesURL)
        guard let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw FeedFetchError.badStatus(source: Source.hn.rawValue, statusCode: statusCode)
        }

        let storyIDs = try JSONDecoder().decode([Int].self, from: data)
        let rankedStoryIDs = Array(storyIDs.prefix(limit).enumerated())

        let items = await withTaskGroup(of: RankedFeedItem?.self) { group in
            for (rank, storyID) in rankedStoryIDs {
                group.addTask {
                    await fetchRankedItem(id: storyID, rank: rank)
                }
            }

            var rankedItems: [RankedFeedItem] = []
            for await rankedItem in group {
                if let rankedItem {
                    rankedItems.append(rankedItem)
                }
            }

            return rankedItems
                .sorted { $0.rank < $1.rank }
                .map(\.item)
        }

        guard !items.isEmpty else {
            throw FeedFetchError.emptyResponse(source: Source.hn.rawValue)
        }

        return items
    }

    private static func fetchRankedItem(id: Int, rank: Int) async -> RankedFeedItem? {
        do {
            let itemURL = URL(string: "https://hacker-news.firebaseio.com/v0/item/\(id).json")!
            let (data, response) = try await URLSession.shared.data(from: itemURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  200 ..< 300 ~= httpResponse.statusCode else {
                return nil
            }

            let item = try JSONDecoder().decode(HNItem.self, from: data)
            guard let feedItem = item.toFeedItem() else { return nil }
            return RankedFeedItem(rank: rank, item: feedItem)
        } catch {
            return nil
        }
    }
}

// MARK: - API Response Types

private struct RankedFeedItem: Sendable {
    let rank: Int
    let item: FeedItem
}

private struct HNItem: Decodable {
    let id: Int
    let title: String?
    let url: String?
    let score: Int?
    let descendants: Int?
    let time: TimeInterval?
    let type: String?
    let deleted: Bool?
    let dead: Bool?

    func toFeedItem() -> FeedItem? {
        guard deleted != true, dead != true else { return nil }
        guard type == nil || type == "story" else { return nil }
        guard let title, !title.isEmpty else { return nil }

        // HN stories sometimes lack a URL (Ask HN, Show HN text posts).
        // Fall back to the HN item page itself.
        let itemURLString = url ?? "https://news.ycombinator.com/item?id=\(id)"
        guard let itemURL = URL(string: itemURLString) else { return nil }

        let date = time.map(Date.init(timeIntervalSince1970:)) ?? Date()

        return FeedItem(
            id: itemURL.absoluteString,
            title: title,
            url: itemURL,
            outlet: nil,
            source: .hn,
            publishedAt: date,
            commentCount: descendants,
            points: score,
            snippet: nil,
            crossRefs: []
        )
    }
}
