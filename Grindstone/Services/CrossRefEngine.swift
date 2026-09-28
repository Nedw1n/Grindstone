import Foundation

/// Identifies stories that appear across multiple sources.
/// A story carried by two or more sources is the app's strongest signal that
/// it matters, so each merged story records every other source it appeared on.
enum CrossRefEngine {

    /// The merged front page: one entry per story, plus which sources carried
    /// each fetched item's story.
    struct MergedStories {
        let items: [FeedItem]
        /// Every source a fetched item's story appeared on, keyed by the item's
        /// ID. Covers items folded into another entry too, so a source's own
        /// lane can show where else its stories ran.
        let storySources: [String: Set<Source>]
        /// The merged entry each fetched item was folded into, keyed by item ID.
        let leadIDs: [String: String]
    }

    /// Folds stories from every source into one list. Items are the same story
    /// when their links match once normalized, when one source lists the
    /// other's link as coverage of the story (Memeorandum clusters), or when
    /// their headlines share most of their words. Each group becomes a single
    /// entry: the item with the richest metadata, carrying the best front-page
    /// placement any member had and every other source as a cross-reference.
    static func mergeStories(_ items: [FeedItem]) -> MergedStories {
        guard !items.isEmpty else { return MergedStories(items: [], storySources: [:], leadIDs: [:]) }

        var groups = UnionFind(count: items.count)
        let keys = items.map(\.normalizedURL)

        // The same link, however it was dressed up.
        var firstIndexByKey: [String: Int] = [:]
        for (index, key) in keys.enumerated() {
            if let first = firstIndexByKey[key] {
                groups.union(first, index)
            } else {
                firstIndexByKey[key] = index
            }
        }

        // Links another source lists as coverage of the same story.
        for (index, item) in items.enumerated() {
            for related in item.relatedURLs {
                guard
                    let other = firstIndexByKey[FeedItem.storyKey(for: related)],
                    items[other].source != item.source
                else { continue }
                groups.union(index, other)
            }
        }

        // Headlines that say the same thing on different sources.
        let titles = items.map { HeadlineWords($0.title) }
        for first in items.indices {
            for second in items.indices where second > first {
                guard items[first].source != items[second].source,
                      titles[first].matches(titles[second]) else { continue }
                groups.union(first, second)
            }
        }

        var membersByRoot: [Int: [Int]] = [:]
        var rootOrder: [Int] = []
        for index in items.indices {
            let root = groups.find(index)
            if membersByRoot[root] == nil {
                rootOrder.append(root)
            }
            membersByRoot[root, default: []].append(index)
        }

        var merged: [FeedItem] = []
        var storySources: [String: Set<Source>] = [:]
        var leadIDs: [String: String] = [:]

        for root in rootOrder {
            let members = (membersByRoot[root] ?? []).map { items[$0] }
            guard var lead = members.max(by: isLessPreferredLead) else { continue }

            let sources = Set(members.map(\.source))
            lead.crossRefs = Source.allCases.filter { $0 != lead.source && sources.contains($0) }

            // A story's placement is the best front-page position it holds anywhere.
            if let bestPlacement = members.filter(\.source.hasEditorialOrder).map(\.intraSourceRank).max(),
               lead.source.hasEditorialOrder {
                lead.intraSourceRank = max(lead.intraSourceRank, bestPlacement)
            }

            if lead.discussionURL == nil {
                lead.discussionURL = members.first { $0.discussionURL != nil }?.discussionURL
            }

            merged.append(lead)
            for member in members {
                storySources[member.id] = sources
                leadIDs[member.id] = lead.id
            }
        }

        return MergedStories(items: merged, storySources: storySources, leadIDs: leadIDs)
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

    /// Orders candidates for a merged story's lead: editorially ranked sources
    /// first (they carry placement and discussion), then richer metadata, then
    /// better placement.
    private static func isLessPreferredLead(_ lhs: FeedItem, _ rhs: FeedItem) -> Bool {
        if lhs.source.hasEditorialOrder != rhs.source.hasEditorialOrder {
            return !lhs.source.hasEditorialOrder
        }
        let lhsMetadata = metadataScore(lhs)
        let rhsMetadata = metadataScore(rhs)
        if lhsMetadata != rhsMetadata {
            return lhsMetadata < rhsMetadata
        }
        if lhs.intraSourceRank != rhs.intraSourceRank {
            return lhs.intraSourceRank < rhs.intraSourceRank
        }
        return lhs.publishedAt < rhs.publishedAt
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

/// The meaningful words of a headline, for spotting the same story told by
/// two outlets. Deliberately strict: a false match hides a story, while a
/// missed one only loses a cross-reference.
private struct HeadlineWords {
    let words: Set<String>

    init(_ title: String) {
        words = Set(
            title.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .compactMap { word -> String? in
                    guard word.count >= 3, !Self.stopWords.contains(word) else { return nil }
                    // Fold simple plurals so "tariffs" meets "tariff".
                    return word.count > 4 && word.hasSuffix("s") ? String(word.dropLast()) : word
                }
        )
    }

    /// At least three shared words that make up half of all the words used.
    func matches(_ other: HeadlineWords) -> Bool {
        guard words.count >= 4, other.words.count >= 4 else { return false }
        let shared = words.intersection(other.words).count
        guard shared >= 3 else { return false }
        return Double(shared) / Double(words.union(other.words).count) >= 0.5
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "from", "that", "this", "into", "over", "after",
        "about", "are", "was", "were", "has", "have", "had", "its", "his", "her",
        "their", "they", "you", "your", "not", "but", "can", "will", "what", "who",
        "how", "why", "when", "new", "says", "say", "said", "than", "more", "just",
        "out", "all", "now", "may", "could", "would", "should", "been", "being",
    ]
}

/// Disjoint sets over item indices, for grouping items into stories.
private struct UnionFind {
    private var parent: [Int]

    init(count: Int) {
        parent = Array(0 ..< count)
    }

    mutating func find(_ index: Int) -> Int {
        var root = index
        while parent[root] != root {
            root = parent[root]
        }
        var node = index
        while parent[node] != root {
            let next = parent[node]
            parent[node] = root
            node = next
        }
        return root
    }

    mutating func union(_ first: Int, _ second: Int) {
        let firstRoot = find(first)
        let secondRoot = find(second)
        guard firstRoot != secondRoot else { return }
        parent[max(firstRoot, secondRoot)] = min(firstRoot, secondRoot)
    }
}
