import Foundation

/// Fetches top stories from the Hacker News Algolia API.
enum HNService {

    private static let endpoint = "https://hn.algolia.com/api/v1/search"

    static func fetch(hitsPerPage: Int = 30) async throws -> [FeedItem] {
        var components = URLComponents(string: endpoint)!
        components.queryItems = [
            URLQueryItem(name: "tags", value: "story"),
            URLQueryItem(name: "hitsPerPage", value: "\(hitsPerPage)"),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let response = try JSONDecoder().decode(HNResponse.self, from: data)
        return response.hits.compactMap { $0.toFeedItem() }
    }
}

// MARK: - API Response Types

private struct HNResponse: Decodable {
    let hits: [HNHit]
}

private struct HNHit: Decodable {
    let objectID: String
    let title: String?
    let url: String?
    let points: Int?
    let numComments: Int?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case objectID
        case title
        case url
        case points
        case numComments = "num_comments"
        case createdAt = "created_at"
    }

    func toFeedItem() -> FeedItem? {
        guard let title, !title.isEmpty else { return nil }

        // HN stories sometimes lack a URL (Ask HN, Show HN text posts).
        // Fall back to the HN item page itself.
        let itemURLString = url ?? "https://news.ycombinator.com/item?id=\(objectID)"
        guard let itemURL = URL(string: itemURLString) else { return nil }

        let date: Date = {
            guard let raw = createdAt else { return Date() }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: raw)
                ?? ISO8601DateFormatter().date(from: raw)
                ?? Date()
        }()

        return FeedItem(
            id: itemURL.absoluteString,
            title: title,
            url: itemURL,
            outlet: nil,
            source: .hn,
            publishedAt: date,
            commentCount: numComments,
            points: points,
            snippet: nil,
            crossRefs: []
        )
    }
}
