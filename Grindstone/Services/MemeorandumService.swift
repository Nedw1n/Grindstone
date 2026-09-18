import Foundation

/// Fetches ranked top stories from the memeorandum homepage and
/// enriches them with RSS metadata for published dates and snippets.
enum MemeorandumService {

    private static let homepageURL = URL(string: "https://www.memeorandum.com/")!
    private static let topItemsMarker = #"<SPAN CLASS="rnhd2">Top Items:</SPAN>"#

    static func fetch(limit: Int = 40) async throws -> [FeedItem] {
        async let homepageItems = fetchHomepage(limit: limit)
        async let feedItems = RSSService.fetch(.memo)

        let (orderedHomepageItems, rssItems) = try await (homepageItems, feedItems)
        let rssItemsByPermalinkID: [String: FeedItem] = Dictionary(uniqueKeysWithValues: rssItems.compactMap { item in
            guard let permalinkID = permalinkID(from: item.url) else { return nil }
            return (permalinkID, item)
        })

        let items = orderedHomepageItems.map { homepageItem in
            let metadata = rssItemsByPermalinkID[homepageItem.permalinkID]
            return homepageItem.makeFeedItem(metadata: metadata)
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
            let titleMatch = firstCaptures(
                in: cluster,
                pattern: #"<DIV CLASS="ii"><STRONG CLASS="L\d"><A HREF="([^"]+)">(.*?)</A></STRONG>(.*?)</DIV>"#
            )
        else {
            return nil
        }

        let outlet = outletName(from: cluster)
        let articleURLString = titleMatch[0].decodingHTMLEntities()
        let title = titleMatch[1].decodingHTMLEntities().condensedWhitespace()
        let snippet = titleMatch[2]
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
            title: title,
            outlet: outlet,
            snippet: snippet.isEmpty ? nil : String(snippet.prefix(280))
        )
    }

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
    let title: String
    let outlet: String?
    let snippet: String?

    func makeFeedItem(metadata: FeedItem?) -> FeedItem {
        let resolvedSnippet = snippet
            ?? metadata?.snippet?.cleanedMemoSnippet(title: title, outlet: outlet ?? metadata?.outlet)

        return FeedItem(
            id: articleURL.absoluteString,
            title: title,
            url: articleURL,
            outlet: outlet ?? metadata?.outlet,
            source: .memo,
            publishedAt: metadata?.publishedAt ?? fallbackDate,
            commentCount: nil,
            points: nil,
            snippet: resolvedSnippet,
            intraSourceRank: 0,
            crossRefs: [],
            discussionURL: metadata?.url
        )
    }

    private var fallbackDate: Date {
        let rawDate = String(permalinkID.prefix(6))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: rawDate) ?? Date()
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
