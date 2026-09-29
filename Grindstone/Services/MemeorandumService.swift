import Foundation

/// Fetches ranked top stories from the memeorandum homepage and
/// enriches them with RSS metadata for published dates and snippets.
enum MemeorandumService {

    private static let homepageURL = URL(string: "https://www.memeorandum.com/")!
    private static let topItemsMarker = #"<SPAN CLASS="rnhd2">Top Items:</SPAN>"#

    static func fetch(limit: Int = 40) async throws -> [FeedItem] {
        async let homepageItems = fetchHomepage(limit: limit)
        async let feedItems = RSSService.fetch(.memo)

        let orderedHomepageItems = try await homepageItems
        // The feed only covers the newest hour of stories, so the homepage
        // stands on its own when the feed fails.
        let rssItems = (try? await feedItems) ?? []
        let rssItemsByPermalinkID: [String: FeedItem] = Dictionary(
            rssItems.compactMap { item in
                guard let permalinkID = permalinkID(from: item.url) else { return nil }
                return (permalinkID, item)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let anchors: [(id: String, date: Date)] = rssItemsByPermalinkID.compactMap { permalinkID, item in
            guard !item.isUndated else { return nil }
            return (permalinkID, item.publishedAt)
        }
        let clock = PermalinkClock(anchors: anchors)

        let items = orderedHomepageItems.map { homepageItem in
            homepageItem.makeFeedItem(
                metadata: rssItemsByPermalinkID[homepageItem.permalinkID],
                estimatedDate: clock.estimate(for: homepageItem.permalinkID)
            )
        }
        let rankedItems = FeedRankingEngine.assignIntraSourceRanks(to: items)

        guard !rankedItems.isEmpty else {
            throw FeedFetchError.emptyResponse(source: Source.memo.rawValue)
        }

        return rankedItems
    }

    private static func fetchHomepage(limit: Int) async throws -> [MemoHomepageItem] {
        let (data, response) = try await FeedNetworking.data(from: homepageURL)
        guard let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw FeedFetchError.badStatus(source: Source.memo.rawValue, statusCode: statusCode)
        }

        let html = String(decoding: data, as: UTF8.self)
        let items = parseHomepage(html, limit: limit)

        guard !items.isEmpty else {
            throw FeedFetchError.emptyResponse(source: Source.memo.rawValue)
        }

        return items
    }

    private static func parseHomepage(_ html: String, limit: Int) -> [MemoHomepageItem] {
        guard let markerRange = html.range(of: topItemsMarker) else { return [] }

        let topItemsHTML = String(html[markerRange.lowerBound...])
        let clusters = topItemsHTML.components(separatedBy: #"<DIV CLASS="clus">"#).dropFirst()

        var items: [MemoHomepageItem] = []
        items.reserveCapacity(min(limit, clusters.count))

        for cluster in clusters {
            if items.count == limit { break }
            if let item = parseCluster(cluster) {
                items.append(item)
            }
        }

        return items
    }

    private static func parseCluster(_ cluster: String) -> MemoHomepageItem? {
        guard
            let itemID = firstCapture(in: cluster, pattern: #"<DIV CLASS="item" ID="([^"]+)""#),
            // The headline link can carry more attributes after HREF (gift and
            // unlocked links add `searchurl`).
            let titleMatch = firstCaptures(
                in: cluster,
                pattern: #"<DIV CLASS="ii"><STRONG CLASS="L\d"><A HREF="([^"]+)"([^>]*)>(.*?)</A></STRONG>(.*?)</DIV>"#
            ),
            titleMatch.count == 4
        else {
            return nil
        }

        let outlet = outletName(from: cluster)
        let articleURLString = titleMatch[0].decodingHTMLEntities()
        // A gift link's plain article address, which identifies the story.
        let canonicalURL = firstCapture(in: titleMatch[1], pattern: #"(?i)searchurl="([^"]+)""#)
            .flatMap { URL(string: $0.decodingHTMLEntities()) }
        let title = titleMatch[2].decodingHTMLEntities().condensedWhitespace()
        let snippet = titleMatch[3]
            .strippingHTML()
            .decodingHTMLEntities()
            .condensedWhitespace()
            .trimmingLeadingDashesAndBullets()

        guard let articleURL = URL(string: articleURLString), !title.isEmpty else {
            return nil
        }

        return MemoHomepageItem(
            permalinkID: itemID,
            articleURL: articleURL,
            canonicalURL: canonicalURL,
            title: title,
            outlet: outlet,
            snippet: snippet.isEmpty ? nil : String(snippet.prefix(280)),
            relatedURLs: relatedURLs(in: cluster, excluding: articleURL)
        )
    }

    /// Every outside article a cluster links to. Memeorandum groups each story
    /// with the other outlets covering it, which lets the same story be
    /// recognized when Hacker News or an RSS feed links one of those outlets
    /// instead. Social posts and Memeorandum's own pages are left out.
    private static func relatedURLs(in cluster: String, excluding articleURL: URL) -> [URL] {
        let articleKey = FeedItem.storyKey(for: articleURL)
        var seenKeys: Set<String> = [articleKey]
        var urls: [URL] = []

        for href in allCaptures(in: cluster, pattern: #"(?i)<A\s+HREF="(https?://[^"]+)""#) {
            guard
                let url = URL(string: href.decodingHTMLEntities()),
                let host = url.host?.lowercased(),
                !excludedRelatedHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) })
            else { continue }

            guard seenKeys.insert(FeedItem.storyKey(for: url)).inserted else { continue }
            urls.append(url)
            if urls.count == 40 { break }
        }

        return urls
    }

    private static let excludedRelatedHosts = [
        "memeorandum.com", "techmeme.com", "mediagazer.com", "wesmirch.com",
        "twitter.com", "x.com", "bsky.app", "threads.net", "threads.com",
        "facebook.com", "instagram.com", "truthsocial.com", "mastodon.social",
    ]

    private static func outletName(from cluster: String) -> String? {
        guard let citeBlock = firstCapture(in: cluster, pattern: #"<CITE>(.*?)</CITE>"#) else {
            return nil
        }

        let anchorMatches = allCaptures(in: citeBlock, pattern: #"<A HREF="[^"]+">([^<]+)</A>"#)
        if let lastAnchor = anchorMatches.last {
            return lastAnchor.decodingHTMLEntities().condensedWhitespace()
        }

        let plainText = citeBlock
            .strippingHTML()
            .decodingHTMLEntities()
            .condensedWhitespace()
            .trimmingCharacters(in: CharacterSet(charactersIn: ":"))

        return plainText.isEmpty ? nil : plainText
    }

    private static func permalinkID(from url: URL) -> String? {
        if let fragment = url.fragment, fragment.hasPrefix("a") {
            return String(fragment.dropFirst())
        }

        let components = url.path.split(separator: "/")
        guard components.count >= 2 else { return nil }

        let dateComponent = String(components[0])
        let storyComponent = String(components[1])
        guard storyComponent.hasPrefix("p") else { return nil }

        return dateComponent + storyComponent
    }

    private static func firstCapture(in string: String, pattern: String) -> String? {
        firstCaptures(in: string, pattern: pattern)?.first
    }

    private static func firstCaptures(in string: String, pattern: String) -> [String]? {
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
            let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string))
        else {
            return nil
        }

        return (1 ..< match.numberOfRanges).compactMap { rangeIndex in
            guard let range = Range(match.range(at: rangeIndex), in: string) else { return nil }
            return String(string[range])
        }
    }

    private static func allCaptures(in string: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }

        return regex.matches(in: string, range: NSRange(string.startIndex..., in: string)).compactMap { match in
            guard
                match.numberOfRanges > 1,
                let range = Range(match.range(at: 1), in: string)
            else {
                return nil
            }
            return String(string[range])
        }
    }
}

private struct MemoHomepageItem {
    let permalinkID: String
    let articleURL: URL
    let canonicalURL: URL?
    let title: String
    let outlet: String?
    let snippet: String?
    let relatedURLs: [URL]

    func makeFeedItem(metadata: FeedItem?, estimatedDate: Date?) -> FeedItem {
        let resolvedSnippet = snippet
            ?? metadata?.snippet?.cleanedMemoSnippet(title: title, outlet: outlet ?? metadata?.outlet)
        // The feed dates only its newest hour of stories; the rest are placed by
        // their permalink number. With neither, the story counts as undated.
        let feedDate = metadata.flatMap { $0.isUndated ? nil : $0.publishedAt }
        let publishedAt = feedDate ?? estimatedDate

        var related = relatedURLs
        if let canonicalURL, FeedItem.storyKey(for: canonicalURL) != FeedItem.storyKey(for: articleURL) {
            related.insert(canonicalURL, at: 0)
        }

        return FeedItem(
            // The plain address stays the same when a gift link's token changes.
            id: (canonicalURL ?? articleURL).absoluteString,
            title: title,
            url: articleURL,
            outlet: outlet ?? metadata?.outlet,
            source: .memo,
            publishedAt: publishedAt ?? Date(),
            commentCount: nil,
            points: nil,
            snippet: resolvedSnippet,
            intraSourceRank: 0,
            crossRefs: [],
            discussionURL: metadata?.url ?? permalinkURL,
            relatedURLs: related,
            isUndated: publishedAt == nil,
            channel: "memo",
            isRanked: true
        )
    }

    /// The story's memeorandum page, where its discussion lives.
    private var permalinkURL: URL? {
        guard let number = PermalinkClock.parse(permalinkID) else { return nil }
        return URL(string: "https://www.memeorandum.com/\(number.day)/p\(number.index)#a\(permalinkID)")
    }
}

/// Estimates when memeorandum posted a story from its permalink ID. IDs number
/// each Eastern day's stories in posting order (260929p60 is the 60th story of
/// September 29), and the feed dates the newest ones, so the rest are placed
/// along the line from midnight through those dated anchors.
struct PermalinkClock {
    /// Posting pace assumed when the feed gives nothing to measure it from:
    /// about six stories an hour, what memeorandum posts on a weekday.
    private static let defaultPace = 6.0 / 3600

    private var anchorsByDay: [String: [(index: Int, date: Date)]] = [:]
    /// Stories per second, measured from midnight to the newest anchor.
    private var pace = PermalinkClock.defaultPace
    private let now: Date

    init(anchors: [(id: String, date: Date)], now: Date = Date()) {
        self.now = now
        for anchor in anchors {
            guard let number = Self.parse(anchor.id) else { continue }
            anchorsByDay[number.day, default: []].append((number.index, anchor.date))
        }
        for day in anchorsByDay.keys {
            anchorsByDay[day]?.sort { $0.index < $1.index }
        }
        if let newestDay = anchorsByDay.keys.max(),
           let newest = anchorsByDay[newestDay]?.last,
           let start = Self.startOfDay(newestDay) {
            let elapsed = newest.date.timeIntervalSince(start)
            if elapsed > 0, newest.index > 0 {
                pace = Double(newest.index) / elapsed
            }
        }
    }

    func estimate(for permalinkID: String) -> Date? {
        guard let number = Self.parse(permalinkID), let start = Self.startOfDay(number.day) else { return nil }
        let estimate: Date
        if let anchors = anchorsByDay[number.day], let last = anchors.last {
            // Between the anchors around it, starting from midnight; past the
            // newest anchor, no later than it.
            let points = [(index: 0, date: start)] + anchors
            if let upper = points.firstIndex(where: { $0.index >= number.index }), upper > 0 {
                let low = points[upper - 1], high = points[upper]
                let fraction = high.index == low.index
                    ? 1
                    : Double(number.index - low.index) / Double(high.index - low.index)
                estimate = low.date.addingTimeInterval(fraction * high.date.timeIntervalSince(low.date))
            } else {
                estimate = last.date
            }
        } else {
            // An earlier day with no anchor: at the measured pace, within that day.
            let offset = min(Double(number.index) / pace, 24 * 3600 - 60)
            estimate = start.addingTimeInterval(offset)
        }
        return min(estimate, now)
    }

    static func parse(_ permalinkID: String) -> (day: String, index: Int)? {
        guard permalinkID.count > 7,
              let pIndex = permalinkID.firstIndex(of: "p"),
              permalinkID.distance(from: permalinkID.startIndex, to: pIndex) == 6,
              let index = Int(permalinkID[permalinkID.index(after: pIndex)...])
        else { return nil }
        let day = String(permalinkID[..<pIndex])
        guard day.allSatisfy(\.isNumber) else { return nil }
        return (day, index)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        return formatter
    }()

    private static func startOfDay(_ day: String) -> Date? {
        dayFormatter.date(from: day)
    }
}

private extension String {
    func trimmingLeadingDashesAndBullets() -> String {
        replacingOccurrences(of: #"^(?:[—–-]\s*)+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cleanedMemoSnippet(title: String, outlet: String?) -> String? {
        var lines = replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.decodingHTMLEntities().condensedWhitespace() }
            .filter { !$0.isEmpty }

        if let first = lines.first, first.looksLikeMemoByline(for: outlet) {
            lines.removeFirst()
        }

        var cleaned = lines.joined(separator: " ")
            .trimmingLeadingDashesAndBullets()
            .condensedWhitespace()

        if cleaned.hasPrefix(title) {
            cleaned.removeFirst(title.count)
            cleaned = cleaned.trimmingLeadingDashesAndBullets().condensedWhitespace()
        }

        if let outlet {
            let outletLine = "\(outlet):"
            if cleaned == outlet || cleaned == outletLine {
                return nil
            }
        }

        return cleaned.isEmpty ? nil : String(cleaned.prefix(280))
    }

    private func looksLikeMemoByline(for outlet: String?) -> Bool {
        guard hasSuffix(":") else { return false }
        guard let outlet, !outlet.isEmpty else { return false }

        let normalizedSelf = lowercased()
        let normalizedOutlet = outlet.lowercased()
        return normalizedSelf == "\(normalizedOutlet):"
            || normalizedSelf.hasSuffix("/ \(normalizedOutlet):")
    }
}
