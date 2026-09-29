import Foundation

enum BiotechService {
    private static let providers: [BiotechProviderDefinition] = [
        BiotechProviderDefinition(name: "bioRxiv") {
            try await BioRxivService.fetch(limit: 12)
        },
        BiotechProviderDefinition(name: "arXiv") {
            try await ArXivBiotechService.fetch(limit: 10)
        },
        BiotechProviderDefinition(name: "STAT") {
            try await StatNewsBiotechService.fetch(limit: 10)
        },
        BiotechProviderDefinition(name: "Nature") {
            try await NatureBiotechService.fetch(limit: 8)
        },
    ]

    /// Every provider's stories, newest first. Each provider keeps its own
    /// limit and channel, so none can push the others out of the lane.
    static func fetch() async throws -> [FeedItem] {
        let results = await withTaskGroup(
            of: BiotechProviderResult.self,
            returning: [BiotechProviderResult].self
        ) { group in
            for provider in providers {
                group.addTask {
                    await loadProvider(named: provider.name, provider.fetch)
                }
            }

            var results: [BiotechProviderResult] = []
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
                throw BiotechProviderError(message: errorMessage)
            }
            throw FeedFetchError.emptyResponse(source: Source.biotech.rawValue)
        }

        return rankedItems
    }

    private static func loadProvider(
        named providerName: String,
        _ operation: @escaping @Sendable () async throws -> [FeedItem]
    ) async -> BiotechProviderResult {
        do {
            return BiotechProviderResult(items: try await operation(), errorMessage: nil)
        } catch is CancellationError {
            return BiotechProviderResult(items: [], errorMessage: nil)
        } catch {
            return BiotechProviderResult(
                items: [],
                errorMessage: "\(providerName): \(error.localizedDescription)"
            )
        }
    }
}

private struct BiotechProviderDefinition: Sendable {
    let name: String
    let fetch: @Sendable () async throws -> [FeedItem]
}

private struct BiotechProviderResult: Sendable {
    let items: [FeedItem]
    let errorMessage: String?
}

private struct BiotechProviderError: LocalizedError, Sendable {
    let message: String

    var errorDescription: String? { message }
}

private enum NatureBiotechService {
    /// The journal's own feed. The biotechnology subject feed mixes in every
    /// Nature Portfolio title, mostly Scientific Reports.
    private static let feedURL = URL(string: "https://www.nature.com/nbt.rss")!
    /// Notices about earlier papers, not stories in their own right.
    private static let noticePrefixes = [
        "author correction", "publisher correction", "correction", "retraction",
        "editorial expression of concern",
    ]

    static func fetch(limit: Int) async throws -> [FeedItem] {
        let items = try await RSSService.fetch(url: feedURL, source: .biotech)
            .filter { item in
                let title = item.title.lowercased()
                return !noticePrefixes.contains { title.hasPrefix($0 + ":") }
            }

        return Array(items.prefix(limit)).map { item in
            FeedItem(
                id: item.id,
                title: item.title,
                url: item.url,
                outlet: "Nature Biotechnology",
                source: .biotech,
                publishedAt: item.publishedAt,
                commentCount: nil,
                points: nil,
                snippet: item.snippet,
                intraSourceRank: item.intraSourceRank,
                crossRefs: [],
                isUndated: item.isUndated,
                channel: "nature"
            )
        }
    }
}

private enum StatNewsBiotechService {
    private static let feedURL = URL(string: "https://www.statnews.com/feed/")!
    private static let categoryKeywords: Set<String> = [
        "biotech",
        "biotechnology",
        "pharmaceuticals",
        "genetics",
        "gene therapy",
        "cell therapy",
        "crispr",
        "biopharma",
    ]

    private static let textKeywords = [
        "biotech",
        "biotechnology",
        "biopharma",
        "pharma",
        "pharmaceutical",
        "gene therapy",
        "cell therapy",
        "crispr",
        "genome",
        "genomic",
        "drug",
        "therapeutic",
        "trial",
        "fda",
    ]

    static func fetch(limit: Int) async throws -> [FeedItem] {
        let (data, response) = try await FeedNetworking.data(from: feedURL)
        guard let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw FeedFetchError.badStatus(source: Source.biotech.rawValue, statusCode: statusCode)
        }

        let parser = StatNewsRSSParser()
        let items = parser.parse(data: data)
            .filter(isRelevant)
            .prefix(limit)
            .map { item in
                // Subscriber-only stories keep their mark as the outlet, so the
                // title stays clean but the paywall is still visible.
                let isSubscriberOnly = item.title.hasPrefix("STAT+: ")
                return FeedItem(
                    id: item.url.absoluteString,
                    title: isSubscriberOnly ? String(item.title.dropFirst("STAT+: ".count)) : item.title,
                    url: item.url,
                    outlet: isSubscriberOnly ? "STAT+" : "STAT",
                    source: .biotech,
                    publishedAt: item.publishedAt,
                    commentCount: nil,
                    points: nil,
                    snippet: item.snippet,
                    intraSourceRank: 0,
                    crossRefs: [],
                    channel: "stat"
                )
            }
        let rankedItems = FeedRankingEngine.assignIntraSourceRanks(to: Array(items))

        guard !rankedItems.isEmpty else {
            throw FeedFetchError.emptyResponse(source: Source.biotech.rawValue)
        }

        return rankedItems
    }

    private static func isRelevant(_ item: ParsedRSSItem) -> Bool {
        let categories = Set(item.categories.map { $0.lowercased() })
        if !categories.isDisjoint(with: categoryKeywords) {
            return true
        }

        let haystack = "\(item.title) \(item.snippet ?? "")"
        return textKeywords.contains { haystack.containsWord($0) }
    }
}

private enum BioRxivService {
    private static let categories = ["bioengineering", "genetics", "genomics"]
    private static let windowInDays = 7

    static func fetch(limit: Int) async throws -> [FeedItem] {
        let dateRange = recentDateRange(daysBack: windowInDays)

        let results = await withTaskGroup(
            of: BiotechProviderResult.self,
            returning: [BiotechProviderResult].self
        ) { group in
            for category in categories {
                group.addTask {
                    await loadCategory(
                        category,
                        startDate: dateRange.start,
                        endDate: dateRange.end
                    )
                }
            }

            var results: [BiotechProviderResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        let items = CrossRefEngine.deduplicate(results.flatMap(\.items))
            .sorted { $0.publishedAt > $1.publishedAt }
        let rankedItems = FeedRankingEngine.assignIntraSourceRanks(to: items)

        guard !rankedItems.isEmpty else {
            if let errorMessage = results.compactMap(\.errorMessage).first {
                throw BiotechProviderError(message: errorMessage)
            }
            throw FeedFetchError.emptyResponse(source: Source.biotech.rawValue)
        }

        return Array(rankedItems.prefix(limit))
    }

    private static func loadCategory(
        _ category: String,
        startDate: String,
        endDate: String
    ) async -> BiotechProviderResult {
        do {
            return BiotechProviderResult(
                items: try await fetchCategory(category, startDate: startDate, endDate: endDate),
                errorMessage: nil
            )
        } catch is CancellationError {
            return BiotechProviderResult(items: [], errorMessage: nil)
        } catch {
            return BiotechProviderResult(
                items: [],
                errorMessage: "bioRxiv/\(category): \(error.localizedDescription)"
            )
        }
    }

    private static func fetchCategory(
        _ category: String,
        startDate: String,
        endDate: String
    ) async throws -> [FeedItem] {
        // The API lists the window oldest first, a page at a time. The first
        // page gives the total; the last page holds the newest preprints.
        let first = try await fetchPage(category, startDate: startDate, endDate: endDate, cursor: 0)
        var records = first.collection
        if let total = first.total, total > records.count, !records.isEmpty {
            let newest = try await fetchPage(
                category, startDate: startDate, endDate: endDate, cursor: total - records.count
            )
            if !newest.collection.isEmpty {
                records = newest.collection
            }
        }

        let items = records.compactMap { record in
            record.toFeedItem()
        }

        guard !items.isEmpty else {
            throw FeedFetchError.emptyResponse(source: Source.biotech.rawValue)
        }

        return items
    }

    private static func fetchPage(
        _ category: String,
        startDate: String,
        endDate: String,
        cursor: Int
    ) async throws -> BioRxivResponse {
        var components = URLComponents(
            string: "https://api.biorxiv.org/details/biorxiv/\(startDate)/\(endDate)/\(cursor)/json"
        )!
        components.queryItems = [
            URLQueryItem(name: "category", value: category),
        ]

        let request = URLRequest(url: components.url!)
        let (data, response) = try await FeedNetworking.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw FeedFetchError.badStatus(source: Source.biotech.rawValue, statusCode: statusCode)
        }

        return try JSONDecoder().decode(BioRxivResponse.self, from: data)
    }

    private static func recentDateRange(daysBack: Int) -> (start: String, end: String) {
        let calendar = Calendar(identifier: .gregorian)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"

        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -daysBack, to: endDate) ?? endDate
        return (formatter.string(from: startDate), formatter.string(from: endDate))
    }
}

private enum ArXivBiotechService {
    private static let apiURL = URL(string: "https://export.arxiv.org/api/query")!
    private static let qBioCategories = [
        "q-bio.BM",
        "q-bio.CB",
        "q-bio.GN",
        "q-bio.MN",
        "q-bio.QM",
        "q-bio.SC",
        "q-bio.TO",
    ]

    private static let searchQuery = [
        qBioCategories.map { "cat:\($0)" }.joined(separator: " OR "),
        "(cat:cs.LG AND (all:biology OR all:biological OR all:bioinformatics OR all:genomics OR all:protein OR all:proteomics OR all:drug OR all:cell OR all:gene OR all:biomedical))",
    ]
    .map { "(\($0))" }
    .joined(separator: " OR ")

    private static let bioKeywords = [
        "biology",
        "biological",
        "bioinformatics",
        "biomedical",
        "biotech",
        "cell",
        "crispr",
        "drug",
        "gene",
        "genome",
        "genomic",
        "molecule",
        "protein",
        "proteomics",
        "therapeutic",
    ]

    static func fetch(limit: Int) async throws -> [FeedItem] {
        var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "search_query", value: searchQuery),
            URLQueryItem(name: "start", value: "0"),
            URLQueryItem(name: "max_results", value: String(max(limit * 2, 18))),
            URLQueryItem(name: "sortBy", value: "submittedDate"),
            URLQueryItem(name: "sortOrder", value: "descending"),
        ]

        let request = URLRequest(url: components.url!)
        let (data, response) = try await FeedNetworking.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw FeedFetchError.badStatus(source: Source.biotech.rawValue, statusCode: statusCode)
        }

        let parser = ArXivAtomParser()
        let parsedItems = parser.parse(data: data)
            .filter(isRelevant)
            .map(\.feedItem)
            .sorted { $0.publishedAt > $1.publishedAt }

        let dedupedItems = CrossRefEngine.deduplicate(parsedItems)
        let finalItems = Array(dedupedItems.prefix(limit))
        let rankedItems = FeedRankingEngine.assignIntraSourceRanks(to: finalItems)

        guard !rankedItems.isEmpty else {
            throw FeedFetchError.emptyResponse(source: Source.biotech.rawValue)
        }

        return rankedItems
    }

    private static func isRelevant(_ item: ParsedArXivItem) -> Bool {
        let loweredCategories = Set(item.categories.map { $0.lowercased() })
        if loweredCategories.contains(where: { $0.hasPrefix("q-bio.") }) {
            return true
        }

        if loweredCategories.contains("cs.lg") || loweredCategories.contains("stat.ml") {
            // Whole words only: "gene" must not match "generative" or "general".
            let haystack = "\(item.feedItem.title) \(item.feedItem.snippet ?? "")"
            return bioKeywords.contains { haystack.containsWord($0) }
        }

        return false
    }
}

private struct BioRxivResponse: Decodable {
    let messages: [BioRxivMessage]?
    let collection: [BioRxivRecord]

    /// Records in the whole window, across every page.
    var total: Int? { messages?.first?.total }
}

private struct BioRxivMessage: Decodable {
    let total: Int?

    private enum CodingKeys: String, CodingKey {
        case total
    }

    init(from decoder: Decoder) throws {
        // The API sends the total as a string ("65"); accept a number too.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let number = try? container.decode(Int.self, forKey: .total) {
            total = number
        } else if let text = try? container.decode(String.self, forKey: .total) {
            total = Int(text)
        } else {
            total = nil
        }
    }
}

private struct BioRxivRecord: Decodable {
    let title: String
    let doi: String
    let date: String
    let version: String
    let category: String
    let abstract: String?

    func toFeedItem() -> FeedItem? {
        guard let url = URL(string: "https://www.biorxiv.org/content/\(doi)v\(version)") else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let publishedAt = formatter.date(from: date) ?? Date()
        let snippet = abstract?
            .condensedWhitespace()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return FeedItem(
            id: url.absoluteString,
            title: title.condensedWhitespace(),
            url: url,
            outlet: "bioRxiv",
            source: .biotech,
            publishedAt: publishedAt,
            commentCount: nil,
            points: nil,
            snippet: snippet?.isEmpty == true ? nil : String((snippet ?? "").prefix(280)),
            intraSourceRank: 0,
            crossRefs: [],
            channel: "biorxiv"
        )
    }
}

private struct ParsedRSSItem {
    let title: String
    let url: URL
    let publishedAt: Date
    let snippet: String?
    let categories: [String]
}

private struct ParsedArXivItem {
    let feedItem: FeedItem
    let categories: [String]
}

private final class ArXivAtomParser: NSObject, XMLParserDelegate {
    private var items: [ParsedArXivItem] = []
    private var currentElement = ""
    private var currentTitle = ""
    private var currentSummary = ""
    private var currentPublished = ""
    private var currentIdentifier = ""
    private var currentPrimaryLink = ""
    private var currentCategories: [String] = []
    private var isInsideEntry = false

    func parse(data: Data) -> [ParsedArXivItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items
    }

    func parser(
        _ parser: XMLParser,
        didStartElement element: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        currentElement = element

        if element == "entry" {
            isInsideEntry = true
            currentTitle = ""
            currentSummary = ""
            currentPublished = ""
            currentIdentifier = ""
            currentPrimaryLink = ""
            currentCategories = []
            return
        }

        guard isInsideEntry else { return }

        if element == "link" {
            let rel = attributes["rel"]?.lowercased()
            let type = attributes["type"]?.lowercased()
            if (rel == nil || rel == "alternate"), type == nil || type == "text/html" {
                currentPrimaryLink = attributes["href"] ?? currentPrimaryLink
            }
        } else if element == "category", let term = attributes["term"]?.condensedWhitespace(), !term.isEmpty {
            currentCategories.append(term)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInsideEntry else { return }

        switch currentElement {
        case "title":
            currentTitle += string
        case "summary":
            currentSummary += string
        case "published":
            currentPublished += string
        case "id":
            currentIdentifier += string
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement element: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        guard element == "entry", isInsideEntry else { return }
        isInsideEntry = false

        let title = currentTitle.condensedWhitespace()
        let summary = currentSummary.condensedWhitespace()
        let identifier = currentIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString = currentPrimaryLink.isEmpty ? identifier : currentPrimaryLink

        guard
            !title.isEmpty,
            let url = URL(string: urlString)
        else {
            return
        }

        let publishedAt = Self.iso8601DateFormatter.date(
            from: currentPublished.trimmingCharacters(in: .whitespacesAndNewlines)
        ) ?? Self.fallbackDateFormatter.date(
            from: currentPublished.trimmingCharacters(in: .whitespacesAndNewlines)
        ) ?? Date()

        items.append(
            ParsedArXivItem(
                feedItem: FeedItem(
                    id: url.absoluteString,
                    title: title,
                    url: url,
                    outlet: "arXiv",
                    source: .biotech,
                    publishedAt: publishedAt,
                    commentCount: nil,
                    points: nil,
                    snippet: summary.isEmpty ? nil : String(summary.prefix(280)),
                    intraSourceRank: 0,
                    crossRefs: [],
                    channel: "arxiv"
                ),
                categories: currentCategories
            )
        )
    }

    private static let iso8601DateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let fallbackDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

private final class StatNewsRSSParser: NSObject, XMLParserDelegate {
    private var items: [ParsedRSSItem] = []
    private var currentElement = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentDate = ""
    private var currentSnippet = ""
    private var currentCategories: [String] = []
    private var currentCategory = ""
    private var isInsideItem = false

    func parse(data: Data) -> [ParsedRSSItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items
    }

    func parser(
        _ parser: XMLParser,
        didStartElement element: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        currentElement = element

        if element == "item" {
            isInsideItem = true
            currentTitle = ""
            currentLink = ""
            currentDate = ""
            currentSnippet = ""
            currentCategories = []
            currentCategory = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInsideItem else { return }

        switch currentElement {
        case "title":
            currentTitle += string
        case "link":
            currentLink += string
        case "pubDate":
            currentDate += string
        case "description":
            currentSnippet += string
        case "category":
            currentCategory += string
        default:
            break
        }
    }

    /// STAT's WordPress feed wraps descriptions and categories in CDATA, which
    /// arrives here rather than in `foundCharacters`.
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let string = String(data: CDATABlock, encoding: .utf8) else { return }
        self.parser(parser, foundCharacters: string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement element: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        if element == "category", isInsideItem {
            let category = currentCategory.condensedWhitespace()
            if !category.isEmpty {
                currentCategories.append(category)
            }
            currentCategory = ""
            return
        }

        guard element == "item", isInsideItem else { return }
        isInsideItem = false

        let title = currentTitle.condensedWhitespace()
        let link = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let url = URL(string: link) else { return }

        let publishedAt = Self.dateFormatter.date(
            from: currentDate.trimmingCharacters(in: .whitespacesAndNewlines)
        ) ?? Date()

        let snippet = currentSnippet
            .strippingHTML()
            .decodingHTMLEntities()
            .condensedWhitespace()

        items.append(
            ParsedRSSItem(
                title: title,
                url: url,
                publishedAt: publishedAt,
                snippet: snippet.isEmpty ? nil : String(snippet.prefix(280)),
                categories: currentCategories.map { $0.condensedWhitespace() }
            )
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
