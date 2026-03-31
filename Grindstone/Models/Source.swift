import SwiftUI

/// Represents a feed source.
/// Designed to be extended as new sources (biotech journals, arXiv, etc.) are added.
enum Source: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case hn = "Hacker News"
    case memo = "Memeorandum"
    case biotech = "Biotech"
    case rss = "RSS"

    static let featuredSources: [Source] = [.hn, .memo, .biotech]

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .hn: return "HN"
        case .memo: return "Memo"
        case .biotech: return "Bio"
        case .rss: return "RSS"
        }
    }

    var color: Color {
        switch self {
        case .hn: return .orange
        case .memo: return .blue
        case .biotech: return .teal
        case .rss: return .indigo
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
