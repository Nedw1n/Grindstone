import Foundation

struct FeedItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let url: URL
    let outlet: String?
    let source: Source
    let publishedAt: Date
    let commentCount: Int?
    let points: Int?
    let snippet: String?
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
            crossRefs: [.hn, .memo]
        ),
    ]
}
