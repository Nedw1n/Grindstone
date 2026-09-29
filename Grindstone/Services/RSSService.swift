import Foundation

/// Fetches and parses generic RSS/Atom feeds.
enum RSSService {

    /// Feed URLs keyed by built-in RSS-backed sources.
    private static let feedURLs: [Source: URL] = [
        .memo: URL(string: "https://www.memeorandum.com/feed.xml")!,
    ]

    static func fetch(_ source: Source) async throws -> [FeedItem] {
        guard let feedURL = feedURLs[source] else { return [] }
        return try await fetch(url: feedURL, source: source)
    }

    static func fetch(url: URL, source: Source) async throws -> [FeedItem] {
        let (data, response) = try await FeedNetworking.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw FeedFetchError.badStatus(source: source.rawValue, statusCode: statusCode)
        }

        let parser = RSSParser(source: source)
        let items = FeedRankingEngine.assignIntraSourceRanks(to: parser.parse(data: data))

        guard !items.isEmpty else {
            throw FeedFetchError.emptyResponse(source: source.rawValue)
        }

        return items
    }
}

enum ManualRSSService {
    static func fetch(feeds: [ManualRSSFeed], limit: Int = 32) async throws -> [FeedItem] {
        let enabledFeeds = feeds.filter(\.isEnabled)
        guard !enabledFeeds.isEmpty else { return [] }

        let results = await withTaskGroup(
            of: ManualRSSLoadResult.self,
            returning: [ManualRSSLoadResult].self
        ) { group in
            for feed in enabledFeeds {
                group.addTask {
                    await load(feed: feed)
                }
            }

            var results: [ManualRSSLoadResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        let merged = CrossRefEngine.deduplicate(results.flatMap(\.items))
            .sorted { $0.publishedAt > $1.publishedAt }
        let rankedItems = FeedRankingEngine.assignIntraSourceRanks(to: merged)

        guard !rankedItems.isEmpty else {
            if let errorMessage = results.compactMap(\.errorMessage).first {
                throw ManualRSSServiceError(message: errorMessage)
            }
            throw FeedFetchError.emptyResponse(source: Source.rss.rawValue)
        }

        return Array(rankedItems.prefix(limit))
    }

    private static func load(feed: ManualRSSFeed) async -> ManualRSSLoadResult {
        guard let url = feed.url else {
            return ManualRSSLoadResult(
                items: [],
                errorMessage: "\(feed.title): invalid feed URL"
            )
        }

        do {
            let items = try await RSSService.fetch(url: url, source: .rss).map { item in
                FeedItem(
                    id: item.id,
                    title: item.title,
                    url: item.url,
                    outlet: feed.title,
                    source: .rss,
                    publishedAt: item.publishedAt,
                    commentCount: item.commentCount,
                    points: item.points,
                    snippet: item.snippet,
                    intraSourceRank: item.intraSourceRank,
                    crossRefs: [],
                    discussionURL: item.discussionURL
                )
            }

            return ManualRSSLoadResult(items: items, errorMessage: nil)
        } catch is CancellationError {
            return ManualRSSLoadResult(items: [], errorMessage: nil)
        } catch {
            return ManualRSSLoadResult(
                items: [],
                errorMessage: "\(feed.title): \(error.localizedDescription)"
            )
        }
    }
}

private struct ManualRSSLoadResult: Sendable {
    let items: [FeedItem]
    let errorMessage: String?
}

private struct ManualRSSServiceError: LocalizedError, Sendable {
    let message: String

    var errorDescription: String? { message }
}

// MARK: - SAX-style RSS/Atom Parser

final class RSSParser: NSObject, XMLParserDelegate {

    private let source: Source
    private var items: [FeedItem] = []

    // Parsing state
    private var currentElement = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentDate = ""
    private var currentSummary = ""
    private var currentContent = ""
    private var currentComments = ""
    private var isInsideItem = false

    // Tag names that delimit an item vary between RSS and Atom
    private let itemTags: Set<String> = ["item", "entry"]
    private let titleTags: Set<String> = ["title"]
    private let linkTags: Set<String> = ["link"]
    private let dateTags: Set<String> = ["pubDate", "published", "updated", "dc:date"]
    private let summaryTags: Set<String> = ["description", "summary"]
    /// Atom's full post body, used for the snippet only when there is no summary.
    private let contentTags: Set<String> = ["content"]
    private let commentsTags: Set<String> = ["comments"]

    init(source: Source) {
        self.source = source
    }

    func parse(data: Data) -> [FeedItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items
    }

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement element: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = element

        if itemTags.contains(element) {
            isInsideItem = true
            currentTitle = ""
            currentLink = ""
            currentDate = ""
            currentSummary = ""
            currentContent = ""
            currentComments = ""
        }

        // Atom uses self-closing <link href="..."/> tags, often several per
        // entry (the comments feed, an edit link). The article is the first one
        // marked rel="alternate", or with no rel at all.
        if element == "link", isInsideItem, let href = attributes["href"],
           (attributes["rel"] ?? "alternate") == "alternate",
           currentLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            currentLink = href
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInsideItem else { return }

        if titleTags.contains(currentElement) {
            currentTitle += string
        } else if linkTags.contains(currentElement) {
            currentLink += string
        } else if dateTags.contains(currentElement) {
            currentDate += string
        } else if summaryTags.contains(currentElement) {
            currentSummary += string
        } else if contentTags.contains(currentElement) {
            currentContent += string
        } else if commentsTags.contains(currentElement) {
            currentComments += string
        }
    }

    /// Text wrapped in <![CDATA[...]]> arrives here rather than in
    /// `foundCharacters`. Many feeds wrap titles and descriptions this way.
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let string = String(data: CDATABlock, encoding: .utf8) else { return }
        self.parser(parser, foundCharacters: string)
    }

    func parser(_ parser: XMLParser, didEndElement element: String,
                namespaceURI: String?, qualifiedName: String?) {
        guard itemTags.contains(element), isInsideItem else { return }

        isInsideItem = false
        let title = currentTitle
            .strippingHTML()
            .decodingHTMLEntities()
            .condensedWhitespace()
        let link = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty, let url = URL(string: link) else { return }

        let date = Self.parseDate(currentDate.trimmingCharacters(in: .whitespacesAndNewlines))
        let summary = currentSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let snippet = (summary.isEmpty ? currentContent : summary)
            .strippingHTML()
            .decodingHTMLEntities()
            .condensedWhitespace()
        let commentsLink = currentComments.trimmingCharacters(in: .whitespacesAndNewlines)
        let discussionURL = commentsLink.isEmpty ? nil : URL(string: commentsLink)

        items.append(FeedItem(
            id: url.absoluteString,
            title: title,
            url: url,
            outlet: nil,
            source: source,
            publishedAt: date,
            commentCount: nil,
            points: nil,
            snippet: snippet.isEmpty ? nil : String(snippet.prefix(280)),
            intraSourceRank: 0,
            crossRefs: [],
            discussionURL: discussionURL
        ))
    }

    // MARK: - Date Parsing

    private static let dateFormatters: [DateFormatter] = {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",     // RFC 822 (RSS)
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "yyyy-MM-dd'T'HH:mm:ssZ",           // ISO 8601
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd",
        ]
        return formats.map { format in
            let f = DateFormatter()
            f.dateFormat = format
            f.locale = Locale(identifier: "en_US_POSIX")
            return f
        }
    }()

    private static func parseDate(_ string: String) -> Date {
        for formatter in dateFormatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return Date()
    }
}
