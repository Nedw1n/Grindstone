import Foundation

/// Identifies stories that appear across multiple sources.
/// Items referenced by 2+ sources get their `crossRefs` populated,
/// providing a signal of traction / importance.
enum CrossRefEngine {

    static func compute(_ items: [FeedItem]) -> [FeedItem] {
        let urlIndex = Dictionary(grouping: items, by: \.normalizedURL)

        return items.map { item in
            var copy = item
            let otherSources = urlIndex[item.normalizedURL]?
                .map(\.source)
                .filter { $0 != item.source } ?? []
            // Deduplicate — a URL might appear twice from the same source
            copy.crossRefs = Array(Set(otherSources))
            return copy
        }
    }

    /// Removes duplicate items that share the same normalized URL,
    /// preferring the version with the most metadata (points, comments, snippet).
    static func deduplicate(_ items: [FeedItem]) -> [FeedItem] {
        var seen = [String: Int]()
        var result: [FeedItem] = []

        for item in items {
            let key = item.normalizedURL
            if let existingIndex = seen[key] {
                let existing = result[existingIndex]
                if shouldReplace(existing: existing, with: item) {
                    result[existingIndex] = item
                }
            } else {
                seen[key] = result.count
                result.append(item)
            }
        }
        return result
    }

    private static func metadataScore(_ item: FeedItem) -> Int {
        var score = 0
        if item.points != nil { score += 2 }
        if item.commentCount != nil { score += 1 }
        if item.snippet != nil { score += 1 }
        if item.outlet != nil { score += 1 }
        return score
    }

    private static func shouldReplace(existing: FeedItem, with candidate: FeedItem) -> Bool {
        let existingMetadataScore = metadataScore(existing)
        let candidateMetadataScore = metadataScore(candidate)

        if candidateMetadataScore != existingMetadataScore {
            return candidateMetadataScore > existingMetadataScore
        }

        if candidate.intraSourceRank != existing.intraSourceRank {
            return candidate.intraSourceRank > existing.intraSourceRank
        }

        return candidate.publishedAt > existing.publishedAt
    }
}
