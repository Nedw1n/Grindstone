import Foundation

struct FeedItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let url: URL
    let outlet: String?
    let source: Source
    var publishedAt: Date
    let commentCount: Int?
    let points: Int?
    let snippet: String?
    var intraSourceRank: Double
    var crossRefs: [Source]
    /// Where the conversation about this story lives (Hacker News thread,
    /// Memeorandum cluster, blog comments). `nil` when the source has none.
    var discussionURL: URL? = nil
    /// Other articles the source groups with this one as the same story
    /// (Memeorandum lists every outlet covering a story). Used only to spot
    /// the story on other sources.
    var relatedURLs: [URL] = []
    /// `true` when the feed gave no usable date. `publishedAt` is then when
    /// Grindstone first saw the story, carried across refreshes by
    /// `FeedViewModel` so the story ages instead of looking brand new each time.
    var isUndated: Bool = false

    /// The link reduced to what identifies the article, for matching the same
    /// story across sources. See `FeedItem.storyKey(for:)`.
    var normalizedURL: String {
        FeedItem.storyKey(for: url)
    }

    /// Reduces a link to what identifies the article: no scheme, no `www.`,
    /// mobile, or AMP variants, no fragment, no trailing slash or index page,
    /// and no tracking parameters. The remaining query is sorted, so parameter
    /// order doesn't matter.
    static func storyKey(for url: URL) -> String {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            var host = components.host?.lowercased()
        else {
            return url.absoluteString.lowercased()
        }

        for prefix in ["www.", "m.", "mobile.", "amp."] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
            break
        }

        var path = components.path
        if path.lowercased().hasPrefix("/amp/") {
            path.removeFirst(4)
        }
        for suffix in ["/amp", ".amp", "/index.html", "/index.htm", "/index.php"]
        where path.lowercased().hasSuffix(suffix) {
            path.removeLast(suffix.count)
            break
        }
        while path.hasSuffix("/") {
            path.removeLast()
        }

        let query = (components.queryItems ?? [])
            .filter { !isTrackingParameter($0.name) }
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value ?? "")" }

        return query.isEmpty ? host + path : host + path + "?" + query.joined(separator: "&")
    }

    private static let trackingParameters: Set<String> = [
        "ref", "source", "fbclid", "gclid", "dclid", "msclkid", "mc_cid", "mc_eid",
        "ocid", "cmpid", "smid", "smtyp", "sref", "igshid", "_ga", "_gl", "spm",
        "share", "via", "rss", "outputtype", "at_medium", "at_campaign", "ito", "s_cid",
    ]

    private static func isTrackingParameter(_ name: String) -> Bool {
        let name = name.lowercased()
        return name.hasPrefix("utm_") || trackingParameters.contains(name)
    }

    /// The outlet name when the source supplied one, otherwise the article's host
    /// (e.g. "github.com"). Hacker News items never carry an outlet, so this keeps
    /// every row labelled with where the link actually goes.
    var displayOutlet: String? {
        if let outlet, !outlet.isEmpty {
            return outlet
        }
        guard let host = url.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Cross-references in the app's canonical source order, so badges never shuffle.
    var orderedCrossRefs: [Source] {
        Source.allCases.filter { crossRefs.contains($0) }
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
            crossRefs: [.memo],
            discussionURL: URL(string: "https://news.ycombinator.com/item?id=1")
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
            id: "https://github.com/rust-for-linux/linux",
            title: "Rust in the Linux Kernel: Year Two",
            url: URL(string: "https://github.com/rust-for-linux/linux")!,
            outlet: nil,
            source: .hn,
            publishedAt: Date().addingTimeInterval(-14400),
            commentCount: 287,
            points: 512,
            snippet: nil,
            intraSourceRank: 0.61,
            crossRefs: [],
            discussionURL: URL(string: "https://news.ycombinator.com/item?id=2")
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
        case discussionURL
        case relatedURLs
        case isUndated
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
            crossRefs: try container.decodeIfPresent([Source].self, forKey: .crossRefs) ?? [],
            discussionURL: try container.decodeIfPresent(URL.self, forKey: .discussionURL),
            relatedURLs: try container.decodeIfPresent([URL].self, forKey: .relatedURLs) ?? [],
            isUndated: try container.decodeIfPresent(Bool.self, forKey: .isUndated) ?? false
        )
    }
}
