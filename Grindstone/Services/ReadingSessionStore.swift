import Foundation
import Combine

/// Remembers when each story first arrived and when you last left the app, so
/// the feed can put what's new since your last visit above what you've
/// already had the chance to see.
@MainActor
final class ReadingSessionStore: ObservableObject {
    static let shared = ReadingSessionStore()

    /// Stories that first arrived after this moment count as new. `nil` until
    /// there has been a previous visit to compare against.
    @Published private(set) var newSince: Date?
    @Published private(set) var firstSeen: [String: Date]

    private let defaults: UserDefaults

    /// Leaving for less than this (Control Center, a quick reply) doesn't
    /// start a new visit.
    private let visitGap: TimeInterval = 5 * 60
    /// First-arrival times are kept this long, well past any story's life on the feed.
    private let retention: TimeInterval = 14 * 24 * 3600

    private enum Keys {
        static let lastVisitEndedAt = "session.lastVisitEndedAt"
        static let firstSeen = "session.firstSeen"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        newSince = defaults.object(forKey: Keys.lastVisitEndedAt) as? Date

        if let data = defaults.data(forKey: Keys.firstSeen),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            firstSeen = decoded
        } else {
            firstSeen = [:]
        }
    }

    /// Call when the app comes to the foreground. Returns `true` when this
    /// starts a new visit, which moves the "new since" line up to the end of
    /// the previous one.
    @discardableResult
    func beginVisit(now: Date = Date()) -> Bool {
        guard let lastEnded = defaults.object(forKey: Keys.lastVisitEndedAt) as? Date else {
            return newSince == nil
        }
        guard now.timeIntervalSince(lastEnded) >= visitGap else { return false }
        newSince = lastEnded
        return true
    }

    /// Call when the app leaves the foreground.
    func endVisit(now: Date = Date()) {
        defaults.set(now, forKey: Keys.lastVisitEndedAt)
    }

    /// Notes the arrival time of any story not seen before.
    func recordArrivals(_ items: [FeedItem], now: Date = Date()) {
        var updated = firstSeen
        for item in items where updated[item.id] == nil {
            updated[item.id] = now
        }
        guard updated.count != firstSeen.count else { return }

        let cutoff = now.addingTimeInterval(-retention)
        firstSeen = updated.filter { $0.value > cutoff }

        if let data = try? JSONEncoder().encode(firstSeen) {
            defaults.set(data, forKey: Keys.firstSeen)
        }
    }

    func isNew(_ item: FeedItem) -> Bool {
        guard let newSince, let arrived = firstSeen[item.id] else { return false }
        return arrived > newSince
    }
}
