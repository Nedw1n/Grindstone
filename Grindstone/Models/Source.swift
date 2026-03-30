import SwiftUI

/// Represents a feed source.
/// Designed to be extended as new sources (biotech journals, arXiv, etc.) are added.
enum Source: String, CaseIterable, Identifiable, Hashable, Codable {
    case hn = "Hacker News"
    case memo = "Memeorandum"
    case mr = "Marginal Revolution"

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .hn: return "HN"
        case .memo: return "Memo"
        case .mr: return "MR"
        }
    }

    var color: Color {
        switch self {
        case .hn: return .orange
        case .memo: return .blue
        case .mr: return .green
        }
    }

    var iconName: String {
        switch self {
        case .hn: return "flame"
        case .memo: return "newspaper"
        case .mr: return "chart.line.uptrend.xyaxis"
        }
    }
}
