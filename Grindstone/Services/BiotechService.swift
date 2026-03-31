import Foundation

enum BiotechService {
    private static let providers: [BiotechProviderDefinition] = [
        BiotechProviderDefinition(name: "bioRxiv") {
            try await BioRxivService.fetch(limit: 12)
        },
        BiotechProviderDefinition(name: "STAT") {
            try await StatNewsBiotechService.fetch(limit: 10)
        },
        BiotechProviderDefinition(name: "Nature") {
            try await NatureBiotechService.fetch(limit: 8)
        },
    ]

    static func fetch(limit: Int = 24) async throws -> [FeedItem] {
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

        guard !merged.isEmpty else {
            if let errorMessage = results.compactMap(\.errorMessage).first {
                throw BiotechProviderError(message: errorMessage)
            }
            throw FeedFetchError.emptyResponse(source: Source.biotech.rawValue)
        }

        return Array(merged.prefix(limit))
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
    private static let feedURL = URL(string: "https://www.nature.com/subjects/biotechnology.rss")!

    static func fetch(limit: Int) async throws -> [FeedItem] {
        let items = try await RSSService.fetch(url: feedURL, source: .biotech)

        return Array(items.prefix(limit)).map { item in
            FeedItem(
                id: item.id,
                title: item.title,
                url: item.url,
                outlet: "Nature",
                source: .biotech,
                publishedAt: item.publishedAt,
                commentCount: nil,
                points: nil,
                snippet: item.snippet,
                crossRefs: []
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
        let (data, response) = try await URLSession.shared.data(from: feedURL)
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
                FeedItem(
                    id: item.url.absoluteString,
                    title: item.title.replacingOccurrences(of: "STAT+: ", with: ""),
                    url: item.url,
                    outlet: "STAT",
                    source: .biotech,
                    publishedAt: item.publishedAt,
                    commentCount: nil,
                    points: nil,
                    snippet: item.snippet,
                    crossRefs: []
                )
            }

        guard !items.isEmpty else {
            throw FeedFetchError.emptyResponse(source: Source.biotech.rawValue)
        }

        return Array(items)
    }

    private static func isRelevant(_ item: ParsedRSSItem) -> Bool {
        let categories = Set(item.categories.map { $0.lowercased() })
        if !categories.isDisjoint(with: categoryKeywords) {
            return true
        }

        let haystack = "\(item.title) \(item.snippet ?? "")".lowercased()
        return textKeywords.contains { haystack.contains($0) }
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

        guard !items.isEmpty else {
            if let errorMessage = results.compactMap(\.errorMessage).first {
                throw BiotechProviderError(message: errorMessage)
            }
            throw FeedFetchError.emptyResponse(source: Source.biotech.rawValue)
        }

        return Array(items.prefix(limit))
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
        var components = URLComponents(
            string: "https://api.biorxiv.org/details/biorxiv/\(startDate)/\(endDate)/0/json"
        )!
        components.queryItems = [
            URLQueryItem(name: "category", value: category),
        ]

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw FeedFetchError.badStatus(source: Source.biotech.rawValue, statusCode: statusCode)
        }

        let decoded = try JSONDecoder().decode(BioRxivResponse.self, from: data)
        let items = decoded.collection.compactMap { record in
            record.toFeedItem()
        }

        guard !items.isEmpty else {
            throw FeedFetchError.emptyResponse(source: Source.biotech.rawValue)
        }

        return items
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

private struct BioRxivResponse: Decodable {
    let collection: [BioRxivRecord]
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
            crossRefs: []
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

private extension String {
    func condensedWhitespace() -> String {
        replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func strippingHTML() -> String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    func decodingHTMLEntities() -> String {
        var decoded = self
        let namedEntities: [String: String] = [
            "&amp;": "&",
            "&quot;": "\"",
            "&apos;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&nbsp;": " ",
            "&hellip;": "...",
            "&mdash;": "-",
            "&ndash;": "-",
            "&ldquo;": "\"",
            "&rdquo;": "\"",
            "&lsquo;": "'",
            "&rsquo;": "'",
        ]

        for (entity, replacement) in namedEntities {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }

        guard let regex = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#) else {
            return decoded
        }

        let matches = regex.matches(in: decoded, range: NSRange(decoded.startIndex..., in: decoded))
        guard !matches.isEmpty else { return decoded }

        var output = decoded
        for match in matches.reversed() {
            guard
                match.numberOfRanges > 1,
                let tokenRange = Range(match.range(at: 1), in: output),
                let fullRange = Range(match.range(at: 0), in: output)
            else {
                continue
            }

            let token = String(output[tokenRange])
            let value: UInt32?

            if token.hasPrefix("x") || token.hasPrefix("X") {
                value = UInt32(token.dropFirst(), radix: 16)
            } else {
                value = UInt32(token, radix: 10)
            }

            guard let value, let scalar = UnicodeScalar(value) else { continue }
            output.replaceSubrange(fullRange, with: String(Character(scalar)))
        }

        return output
    }
}
