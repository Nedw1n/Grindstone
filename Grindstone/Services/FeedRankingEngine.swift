import Foundation

enum FeedRankingMethod {
    case legacyPublishedAt
    case sourcePercentileBlend
}

enum FeedRankingEngine {
    /// Toggle this back to `.legacyPublishedAt` to restore the previous merged-feed ordering.
    static let currentMethod: FeedRankingMethod = .sourcePercentileBlend

    private static let sourceRankWeight = 0.5
    private static let crossReferenceWeight = 0.35
    private static let recencyWeight = 0.15

    /// Hours for a story's freshness to halve.
    private static let recencyHalfLifeHours = 6.0

    /// The placement given to stories from date-ordered sources: about halfway
    /// down a front page. Their position only says how new they are, and
    /// recency already scores that.
    private static let chronologicalPlacement = 0.5

    static func assignIntraSourceRanks(to orderedItems: [FeedItem]) -> [FeedItem] {
        guard !orderedItems.isEmpty else { return [] }

        let itemCount = orderedItems.count
        return orderedItems.enumerated().map { index, item in
            var rankedItem = item
            // The requested formula uses the native source position divided by the
            // source count, so the first item is 1.0 and the last item trends toward 0.
            rankedItem.intraSourceRank = itemCount == 1
                ? 1
                : 1 - (Double(index) / Double(itemCount))
            return rankedItem
        }
    }

    static func sortMergedItems(
        _ items: [FeedItem],
        using method: FeedRankingMethod = currentMethod
    ) -> [FeedItem] {
        switch method {
        case .legacyPublishedAt:
            return items.sorted { $0.publishedAt > $1.publishedAt }
        case .sourcePercentileBlend:
            return weightedSourceBlend(items)
        }
    }

    private static func weightedSourceBlend(_ items: [FeedItem]) -> [FeedItem] {
        guard !items.isEmpty else { return [] }

        let now = Date()
        let rankedItems = items.enumerated().map { index, item in
            RankedMergedFeedItem(
                originalIndex: index,
                score: score(for: item, now: now),
                item: item
            )
        }

        return rankedItems
            .sorted(by: areInDescendingOrder)
            .map(\.item)
    }

    /// A story's score on the merged front page, from 0 to 1.
    static func score(for item: FeedItem, now: Date = Date()) -> Double {
        let crossRefDenominator = Double(max(Source.allCases.count - 1, 1))
        let crossReferenceSignal = Double(Set(item.crossRefs).count) / crossRefDenominator

        return (sourceRankWeight * placementSignal(for: item))
            + (crossReferenceWeight * crossReferenceSignal)
            + (recencyWeight * recencySignal(for: item, now: now))
    }

    /// Front-page placement for editorially ranked sources; a neutral middle
    /// for sources that only list the newest first.
    static func placementSignal(for item: FeedItem) -> Double {
        item.source.hasEditorialOrder ? item.intraSourceRank : chronologicalPlacement
    }

    /// Freshness on an absolute scale: 1 when published, halving every
    /// `recencyHalfLifeHours`. Unlike a scale relative to the batch, a stale
    /// cache never makes its least-old story look fresh.
    static func recencySignal(for item: FeedItem, now: Date) -> Double {
        let ageHours = max(0, now.timeIntervalSince(item.publishedAt) / 3600)
        return pow(0.5, ageHours / recencyHalfLifeHours)
    }

    nonisolated private static func areInDescendingOrder(
        lhs: RankedMergedFeedItem,
        rhs: RankedMergedFeedItem
    ) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }

        if lhs.item.publishedAt != rhs.item.publishedAt {
            return lhs.item.publishedAt > rhs.item.publishedAt
        }

        if lhs.item.intraSourceRank != rhs.item.intraSourceRank {
            return lhs.item.intraSourceRank > rhs.item.intraSourceRank
        }

        return lhs.originalIndex < rhs.originalIndex
    }
}

private struct RankedMergedFeedItem {
    let originalIndex: Int
    let score: Double
    let item: FeedItem
}
