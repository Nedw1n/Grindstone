import Foundation

extension FeedItem {
    func matchesSearch(_ query: String) -> Bool {
        let normalizedQuery = query.condensedWhitespace().lowercased()
        guard !normalizedQuery.isEmpty else { return true }

        let haystack = [
            title,
            outlet ?? "",
            snippet ?? "",
            source.rawValue,
        ]
        .joined(separator: "\n")
        .lowercased()

        return haystack.contains(normalizedQuery)
    }
}
