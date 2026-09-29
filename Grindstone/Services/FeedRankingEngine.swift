import Foundation

/// Builds Today from every source's stories by weighted fair share.
///
/// It knows nothing about any particular source. Each story says which
/// channel (feed) it came from, which source that channel belongs to, and
/// whether the channel publishes its own order (`FeedItem.isRanked`). So a
/// new source or feed works without changes here: it gets a share of Today,
/// and a quiet feed isn't buried by a busy one.
enum FeedRankingEngine {
    /// Ranked channels are placed by position on a page this long, whatever
    /// their fetch size, so the same position counts the same everywhere.
    static let pageLength = 30

    /// A newest-first channel's freshness halves every twice its typical gap
    /// between posts, within these bounds, so a weekly blog and a wire feed
    /// are each judged by their own rhythm.
    private static let halfLifeBounds: ClosedRange<Double> = 3 ... 24
    /// Used when a channel has too few stories to measure its rhythm.
    private static let defaultHalfLifeHours = 12.0
    /// A newest-first channel is judged from its own newest story, forgiving
    /// up to this much lag: feeds that post in batches (arXiv) or date stories
    /// only by day (bioRxiv, Nature) shouldn't look stale for how they publish.
    private static let maxForgivenLagHours = 24.0
    /// Ranked front pages have already chosen what matters, so by default a
    /// source of them gets this much more of Today than a newest-first one.
    private static let rankedSourceWeight = 2.0
    /// Newest-first stories stay in Today while they stand at least this high,
    /// about one and a half of their channel's half-lives…
    private static let freshnessFloor = 0.35
    /// …and never past this age. Ranked pages decide for themselves.
    private static let maxAgeHours = 36.0
    /// Standing added for each other source carrying the same story.
    private static let crossPostBonus = 0.25

    struct Ranking {
        /// Today's order.
        let items: [FeedItem]
        /// Each story's standing on its own channel, before any cross-post bonus.
        let standings: [String: Double]
    }

    /// Places stories by position on their own page: 1 for the first, falling
    /// to 0 at `pageLength`.
    static func assignIntraSourceRanks(to orderedItems: [FeedItem]) -> [FeedItem] {
        orderedItems.enumerated().map { index, item in
            var rankedItem = item
            rankedItem.intraSourceRank = max(0, 1 - Double(index) / Double(pageLength))
            return rankedItem
        }
    }

    /// A newest-first channel's rhythm: how fast its stories fade, and its
    /// newest story, which its freshness is judged from.
    struct ChannelClock {
        let halfLifeHours: Double
        let newest: Date
    }

    /// How strongly a story stands on its own channel, from 0 to 1: its page
    /// position when the channel is ranked, otherwise its freshness on the
    /// channel's own clock.
    static func standing(of item: FeedItem, clock: ChannelClock? = nil, now: Date = Date()) -> Double {
        if item.isRanked {
            return item.intraSourceRank
        }
        let ageHours = max(0, now.timeIntervalSince(item.publishedAt) / 3600)
        let lagHours = clock.map { min(max(0, now.timeIntervalSince($0.newest) / 3600), maxForgivenLagHours) } ?? 0
        return pow(0.5, max(0, ageHours - lagHours) / (clock?.halfLifeHours ?? defaultHalfLifeHours))
    }

    /// Each newest-first channel's clock. Its half-life is twice its median gap
    /// between posts, within `halfLifeBounds`.
    static func channelClocks(for items: [FeedItem]) -> [String: ChannelClock] {
        var datesByChannel: [String: [Date]] = [:]
        for item in items where !item.isRanked {
            datesByChannel[item.channelKey, default: []].append(item.publishedAt)
        }
        return datesByChannel.compactMapValues { dates in
            let newestFirst = dates.sorted(by: >)
            guard let newest = newestFirst.first else { return nil }
            let gaps = zip(newestFirst, newestFirst.dropFirst())
                .map { $0.timeIntervalSince($1) / 3600 }
                .filter { $0 > 0 }
                .sorted()
            let halfLife = gaps.isEmpty
                ? defaultHalfLifeHours
                : min(max(2 * gaps[gaps.count / 2], halfLifeBounds.lowerBound), halfLifeBounds.upperBound)
            return ChannelClock(halfLifeHours: halfLife, newest: newest)
        }
    }

    /// Orders stories for Today. Each position goes to the source furthest
    /// below its share of the list so far, and that source takes its best
    /// remaining story, its channels taking turns the same way. Shares follow
    /// `weights`; a source without one gets `rankedSourceWeight` when its
    /// stories come from ranked pages and 1 otherwise. A source with nothing
    /// fresh gives up its turn, and stale newest-first stories are left to
    /// their source's own lane. A story carried by several sources stands
    /// higher and counts toward whichever of them takes it.
    static func fairShare(
        _ stories: [FeedItem],
        weights: [Source: Double] = [:],
        now: Date = Date()
    ) -> Ranking {
        let clocks = channelClocks(for: stories)
        var standings: [String: Double] = [:]
        var pool: [Candidate] = []

        for (order, story) in stories.enumerated() {
            let base = standing(of: story, clock: clocks[story.channelKey], now: now)
            standings[story.id] = base
            let sources = Set([story.source] + story.crossRefs)
            let boosted = min(1, base + crossPostBonus * Double(sources.count - 1))
            guard isEligible(story, standing: boosted, now: now) else { continue }
            pool.append(Candidate(item: story, sources: sources, standing: boosted, order: order))
        }

        let rankedSources = Set(stories.filter(\.isRanked).map(\.source))
        func weight(_ source: Source) -> Double {
            max(weights[source] ?? (rankedSources.contains(source) ? rankedSourceWeight : 1), 0.001)
        }
        let totalWeight = Source.allCases
            .filter { source in pool.contains { $0.sources.contains(source) } }
            .reduce(0) { $0 + weight($1) }

        var takenBySource: [Source: Int] = [:]
        var takenByChannel: [String: Int] = [:]
        var ordered: [FeedItem] = []

        while !pool.isEmpty {
            let position = Double(ordered.count + 1)
            var chosen: (source: Source, deficit: Double, best: Double)?
            for source in Source.allCases {
                let best = pool.filter { $0.sources.contains(source) }.map(\.standing).max()
                guard let best else { continue }
                let deficit = weight(source) / totalWeight * position - Double(takenBySource[source, default: 0])
                // Furthest below its share first, then the stronger story;
                // remaining ties keep the sources' usual order.
                if let current = chosen,
                   deficit < current.deficit - 1e-9
                    || (abs(deficit - current.deficit) <= 1e-9 && best <= current.best) {
                    continue
                }
                chosen = (source, deficit, best)
            }
            guard let source = chosen?.source else { break }

            let inSource = pool.indices.filter { pool[$0].sources.contains(source) }
            func channelKey(_ index: Int) -> String { "\(source.rawValue)|\(pool[index].item.channelKey)" }
            // The channel with the fewest turns so far, then the one with the stronger story.
            let channel = inSource.min { a, b in
                let takenA = takenByChannel[channelKey(a), default: 0]
                let takenB = takenByChannel[channelKey(b), default: 0]
                if takenA != takenB { return takenA < takenB }
                if pool[a].standing != pool[b].standing { return pool[a].standing > pool[b].standing }
                return pool[a].order < pool[b].order
            }.map(channelKey)
            let pickIndex = inSource
                .filter { channelKey($0) == channel }
                .min { a, b in
                    if pool[a].standing != pool[b].standing { return pool[a].standing > pool[b].standing }
                    if pool[a].item.publishedAt != pool[b].item.publishedAt {
                        return pool[a].item.publishedAt > pool[b].item.publishedAt
                    }
                    return pool[a].order < pool[b].order
                }
            guard let pickIndex, let channel else { break }

            let pick = pool.remove(at: pickIndex)
            ordered.append(pick.item)
            for carrier in pick.sources {
                takenBySource[carrier, default: 0] += 1
            }
            takenByChannel[channel, default: 0] += 1
        }

        return Ranking(items: ordered, standings: standings)
    }

    private static func isEligible(_ item: FeedItem, standing: Double, now: Date) -> Bool {
        if item.isRanked {
            return true
        }
        let ageHours = now.timeIntervalSince(item.publishedAt) / 3600
        return ageHours <= maxAgeHours && standing >= freshnessFloor
    }
}

private struct Candidate {
    let item: FeedItem
    /// The sources carrying the story: its own and any cross-posts.
    let sources: Set<Source>
    let standing: Double
    /// Position in the input, for stable ties.
    let order: Int
}
