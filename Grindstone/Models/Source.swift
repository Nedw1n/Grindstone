import SwiftUI

/// Represents a feed source.
/// Designed to be extended as new sources (biotech journals, arXiv, etc.) are added.
enum Source: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case hn = "Hacker News"
    case memo = "Memeorandum"
    case biotech = "Biotech"
    case rss = "RSS"

    /// Sources that get a card in the featured strip.
    static let featuredSources: [Source] = [.hn, .memo, .biotech]

    /// Sources with a fixed upstream that the user can switch on or off in Settings.
    /// RSS is always present because the user curates it feed by feed.
    static let builtInSources: [Source] = [.hn, .memo, .biotech]

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .hn: return "HN"
        case .memo: return "Memo"
        case .biotech: return "Bio"
        case .rss: return "RSS"
        }
    }

    /// One-line description shown under the source name in Settings.
    var summary: String {
        switch self {
        case .hn: return "Front page stories, ranked as on the site"
        case .memo: return "Top political and media stories of the moment"
        case .biotech: return "bioRxiv, arXiv q-bio, STAT, and Nature Biotechnology"
        case .rss: return "Blogs and publications you add yourself"
        }
    }

    /// A muted mineral tint (rust, slate, verdigris, heather) that sits with the
    /// stone palette. Sources are told apart by name first; color only backs it up.
    var color: Color {
        switch self {
        case .hn: return Color("SourceHN")
        case .memo: return Color("SourceMemo")
        case .biotech: return Color("SourceBio")
        case .rss: return Color("SourceRSS")
        }
    }

    var iconName: String {
        switch self {
        case .hn: return "flame"
        case .memo: return "newspaper"
        case .biotech: return "cross.vial"
        case .rss: return "dot.radiowaves.left.and.right"
        }
    }
}
