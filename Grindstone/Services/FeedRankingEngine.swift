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
    private static let recencyDecayAlpha = 0.4

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
        let recencySignals = items.map { rawRecencySignal(for: $0, now: now) }
        let normalizedRecency = normalize(recencySignals)
        let crossRefDenominator = Double(max(Source.allCases.count - 1, 1))

        let rankedItems = items.enumerated().map { index, item in
            let crossReferenceSignal = Double(Set(item.crossRefs).count) / crossRefDenominator
            let score = (sourceRankWeight * item.intraSourceRank)
                + (crossReferenceWeight * crossReferenceSignal)
                + (recencyWeight * normalizedRecency[index])

            return RankedMergedFeedItem(
                originalIndex: index,
                score: score,
                item: item
            )
        }

        return rankedItems
            .sorted(by: areInDescendingOrder)
            .map(\.item)
    }

    private static func rawRecencySignal(for item: FeedItem, now: Date) -> Double {
        let ageHours = max(0, now.timeIntervalSince(item.publishedAt) / 3600)
        return 1 / pow(ageHours + 2, recencyDecayAlpha)
    }

    private static func normalize(_ values: [Double]) -> [Double] {
        guard
            let minimum = values.min(),
            let maximum = values.max()
        else {
            return []
        }

        let range = maximum - minimum
        guard range > .ulpOfOne else {
            return Array(repeating: 1, count: values.count)
        }

        return values.map { ($0 - minimum) / range }
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
