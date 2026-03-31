import Foundation
import Combine

struct ManualRSSFeed: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var title: String
    var urlString: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        title: String,
        urlString: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.isEnabled = isEnabled
    }

    var url: URL? {
        URL(string: urlString)
    }

    var displayHost: String {
        guard let host = url?.host?.replacingOccurrences(of: "www.", with: "") else {
            return urlString
        }
        return host
    }

    static let seededFeeds: [ManualRSSFeed] = [
        ManualRSSFeed(
            title: "Marginal Revolution",
            urlString: "https://marginalrevolution.com/feed"
        ),
    ]
}

enum ManualRSSFeedStoreError: LocalizedError {
    case invalidURL
    case duplicateFeed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid RSS or Atom feed URL."
        case .duplicateFeed:
            return "That feed is already in your RSS library."
        }
    }
}

@MainActor
final class ManualRSSFeedStore: ObservableObject {
    static let shared = ManualRSSFeedStore()

    @Published private(set) var feeds: [ManualRSSFeed]

    var enabledFeeds: [ManualRSSFeed] {
        feeds.filter(\.isEnabled)
    }

    private let defaults: UserDefaults
    private let storageKey = "manualRSSFeeds"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([ManualRSSFeed].self, from: data) {
            feeds = decoded
        } else {
            feeds = ManualRSSFeed.seededFeeds
            persist()
        }
    }

    @discardableResult
    func addFeed(title: String?, urlString: String) throws -> ManualRSSFeed {
        let normalizedURLString = try Self.normalizedURLString(from: urlString)
        guard !feeds.contains(where: { Self.normalizedURLString(for: $0.urlString) == normalizedURLString }) else {
            throw ManualRSSFeedStoreError.duplicateFeed
        }

        let resolvedURL = URL(string: normalizedURLString)!
        let resolvedTitle = title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ?? Self.defaultTitle(for: resolvedURL)

        let feed = ManualRSSFeed(title: resolvedTitle, urlString: normalizedURLString)
        feeds.append(feed)
        persist()
        return feed
    }

    func removeFeed(id: ManualRSSFeed.ID) {
        feeds.removeAll { $0.id == id }
        persist()
    }

    func setEnabled(_ isEnabled: Bool, for id: ManualRSSFeed.ID) {
        guard let index = feeds.firstIndex(where: { $0.id == id }) else { return }
        feeds[index].isEnabled = isEnabled
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(feeds) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func normalizedURLString(from rawValue: String) throws -> String {
        guard let normalized = normalizedURLString(for: rawValue) else {
            throw ManualRSSFeedStoreError.invalidURL
        }
        return normalized
    }

    private static func normalizedURLString(for rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty else {
            return nil
        }

        components.scheme = scheme
        components.host = host.lowercased()

        if components.queryItems?.isEmpty == true {
            components.queryItems = nil
        }

        guard var normalized = components.url?.absoluteString else { return nil }
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }

    private static func defaultTitle(for url: URL) -> String {
        let host = url.host?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
        return host
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
