import Foundation

struct FeedItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let url: URL
    let outlet: String?
    let source: Source
    let publishedAt: Date
    let commentCount: Int?
    let points: Int?
    let snippet: String?
    var intraSourceRank: Double
    var crossRefs: [Source]

    /// URL normalized for cross-reference matching.
    /// Strips tracking parameters, trailing slashes, and lowercases the host.
    var normalizedURL: String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.queryItems = components.queryItems?
            .filter { item in
                let name = item.name.lowercased()
                return !name.hasPrefix("utm_") && name != "ref" && name != "source"
            }
        if components.queryItems?.isEmpty == true {
            components.queryItems = nil
        }
        var result = components.string ?? url.absoluteString
        while result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    static func == (lhs: FeedItem, rhs: FeedItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        // Feed items are enriched after creation, so hash on stable identity only.
        hasher.combine(id)
    }
}

// MARK: - Mock Data

extension FeedItem {
    static let mock: [FeedItem] = [
        FeedItem(
            id: "https://example.com/ai-chip-race",
            title: "The AI Chip Race Is Heating Up",
            url: URL(string: "https://example.com/ai-chip-race")!,
            outlet: "TechCrunch",
            source: .hn,
            publishedAt: Date().addingTimeInterval(-3600),
            commentCount: 142,
            points: 340,
            snippet: "NVIDIA, AMD, and a wave of startups are competing for dominance in the AI accelerator market.",
            intraSourceRank: 1.0,
            crossRefs: [.memo]
        ),
        FeedItem(
            id: "https://example.com/fed-rate-hold",
            title: "Fed Signals Rate Hold Through Q3",
            url: URL(string: "https://example.com/fed-rate-hold")!,
            outlet: "Bloomberg",
            source: .memo,
            publishedAt: Date().addingTimeInterval(-7200),
            commentCount: nil,
            points: nil,
            snippet: "Federal Reserve officials indicated they expect to keep rates steady as inflation cools slower than projected.",
            intraSourceRank: 0.88,
            crossRefs: [.hn, .rss]
        ),
        FeedItem(
            id: "https://example.com/remote-work-study",
            title: "New Study: Remote Workers Are More Productive",
            url: URL(string: "https://example.com/remote-work-study")!,
            outlet: "Marginal Revolution",
            source: .rss,
            publishedAt: Date().addingTimeInterval(-10800),
            commentCount: nil,
            points: nil,
            snippet: "A Stanford study tracking 2,000 workers found a 13% productivity gain for remote employees.",
            intraSourceRank: 0.72,
            crossRefs: []
        ),
        FeedItem(
            id: "https://example.com/rust-linux-kernel",
            title: "Rust in the Linux Kernel: Year Two",
            url: URL(string: "https://example.com/rust-linux-kernel")!,
            outlet: nil,
            source: .hn,
            publishedAt: Date().addingTimeInterval(-14400),
            commentCount: 287,
            points: 512,
            snippet: nil,
            intraSourceRank: 0.61,
            crossRefs: []
        ),
        FeedItem(
            id: "https://example.com/biotech-crispr-trial",
            title: "First In-Vivo CRISPR Trial Shows Promising Results",
            url: URL(string: "https://example.com/biotech-crispr-trial")!,
            outlet: "Nature",
            source: .biotech,
            publishedAt: Date().addingTimeInterval(-18000),
            commentCount: nil,
            points: nil,
            snippet: "Verve Therapeutics reports positive Phase 1 data for its gene-editing heart disease treatment.",
            intraSourceRank: 0.94,
            crossRefs: [.hn, .memo]
        ),
    ]
}

extension FeedItem {
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case url
        case outlet
        case source
        case publishedAt
        case commentCount
        case points
        case snippet
        case intraSourceRank
        case crossRefs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = FeedItem(
            id: try container.decode(String.self, forKey: .id),
            title: try container.decode(String.self, forKey: .title),
            url: try container.decode(URL.self, forKey: .url),
            outlet: try container.decodeIfPresent(String.self, forKey: .outlet),
            source: try container.decode(Source.self, forKey: .source),
            publishedAt: try container.decode(Date.self, forKey: .publishedAt),
            commentCount: try container.decodeIfPresent(Int.self, forKey: .commentCount),
            points: try container.decodeIfPresent(Int.self, forKey: .points),
            snippet: try container.decodeIfPresent(String.self, forKey: .snippet),
            intraSourceRank: try container.decodeIfPresent(Double.self, forKey: .intraSourceRank) ?? 0,
            crossRefs: try container.decodeIfPresent([Source].self, forKey: .crossRefs) ?? []
        )
    }
}
