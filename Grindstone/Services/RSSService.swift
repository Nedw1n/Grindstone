import Foundation

/// Fetches and parses RSS/Atom feeds for Memeorandum and Marginal Revolution.
enum RSSService {

    /// Feed URLs keyed by source. Add new RSS-backed sources here.
    private static let feedURLs: [Source: URL] = [
        .memo: URL(string: "https://www.memeorandum.com/feed.atom")!,
        .mr: URL(string: "https://marginalrevolution.com/feed")!,
    ]

    static func fetch(_ source: Source) async throws -> [FeedItem] {
        guard let feedURL = feedURLs[source] else { return [] }
        let (data, _) = try await URLSession.shared.data(from: feedURL)
        let parser = RSSParser(source: source)
        return parser.parse(data: data)
    }
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
    private var currentSnippet = ""
    private var isInsideItem = false

    // Tag names that delimit an item vary between RSS and Atom
    private let itemTags: Set<String> = ["item", "entry"]
    private let titleTags: Set<String> = ["title"]
    private let linkTags: Set<String> = ["link"]
    private let dateTags: Set<String> = ["pubDate", "published", "updated", "dc:date"]
    private let snippetTags: Set<String> = ["description", "summary", "content"]

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
            currentSnippet = ""
        }

        // Atom uses <link href="..."/> as a self-closing tag
        if element == "link", isInsideItem, let href = attributes["href"] {
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
        } else if snippetTags.contains(currentElement) {
            currentSnippet += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement element: String,
                namespaceURI: String?, qualifiedName: String?) {
        guard itemTags.contains(element), isInsideItem else { return }

        isInsideItem = false
        let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let link = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty, let url = URL(string: link) else { return }

        let date = Self.parseDate(currentDate.trimmingCharacters(in: .whitespacesAndNewlines))
        let snippet = currentSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
            .strippingHTML()

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
            crossRefs: []
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

// MARK: - HTML Stripping

private extension String {
    func strippingHTML() -> String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}
