import Foundation

/// Something the reader can open: an article, or the discussion attached to it.
struct ArticleDestination: Hashable, Identifiable, Sendable {
    enum Kind: Hashable, Sendable {
        case article
        case discussion
    }

    let item: FeedItem
    let kind: Kind

    var id: String { "\(kind)-\(item.id)" }

    var url: URL {
        switch kind {
        case .article:
            return item.url
        case .discussion:
            return item.discussionURL ?? item.url
        }
    }

    var title: String {
        switch kind {
        case .article:
            return item.title
        case .discussion:
            return "Comments"
        }
    }

    static func article(_ item: FeedItem) -> ArticleDestination {
        ArticleDestination(item: item, kind: .article)
    }

    static func discussion(_ item: FeedItem) -> ArticleDestination? {
        guard item.discussionURL != nil else { return nil }
        return ArticleDestination(item: item, kind: .discussion)
    }
}
