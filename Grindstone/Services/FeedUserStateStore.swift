import Foundation
import Combine

@MainActor
final class FeedUserStateStore: ObservableObject {
    static let shared = FeedUserStateStore()

    /// Read stories, keyed by ID, with when each was marked read or last
    /// turned up in a refresh. See `renewReadMarks(for:)`.
    @Published private(set) var readDates: [String: Date]
    @Published private(set) var savedItems: [FeedItem]

    private let defaults: UserDefaults
    private let readDatesKey = "feed.readDates"
    /// Earlier versions kept a bare list of read IDs under this key.
    private let legacyReadItemIDsKey = "feed.readItemIDs"
    private let savedItemsKey = "feed.savedItems"

    /// A read mark is forgotten once its story has been gone from every source
    /// this long. Saved stories keep theirs.
    private let readRetention: TimeInterval = 30 * 24 * 3600
    /// Marks are renewed at most this often, so most refreshes write nothing.
    private let readRenewalInterval: TimeInterval = 24 * 3600

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let legacyReadItemIDs = defaults.stringArray(forKey: legacyReadItemIDsKey)
        if let data = defaults.data(forKey: readDatesKey),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            self.readDates = decoded
        } else {
            let now = Date()
            self.readDates = Dictionary(
                (legacyReadItemIDs ?? []).map { ($0, now) },
                uniquingKeysWith: { first, _ in first }
            )
        }

        if let data = defaults.data(forKey: savedItemsKey),
           let decoded = try? JSONDecoder().decode([FeedItem].self, from: data) {
            self.savedItems = decoded
        } else {
            self.savedItems = []
        }

        if legacyReadItemIDs != nil {
            persistReadState()
            defaults.removeObject(forKey: legacyReadItemIDsKey)
        }
    }

    // MARK: Read state

    func isRead(_ item: FeedItem) -> Bool {
        readDates[item.id] != nil
    }

    func unreadCount(in items: [FeedItem]) -> Int {
        items.reduce(into: 0) { count, item in
            if readDates[item.id] == nil {
                count += 1
            }
        }
    }

    func markRead(_ item: FeedItem) {
        guard readDates[item.id] == nil else { return }
        readDates[item.id] = Date()
        persistReadState()
    }

    func markRead(_ items: [FeedItem]) {
        let now = Date()
        var updated = readDates
        for item in items where updated[item.id] == nil {
            updated[item.id] = now
        }
        guard updated.count != readDates.count else { return }
        readDates = updated
        persistReadState()
    }

    func markUnread(_ item: FeedItem) {
        guard readDates.removeValue(forKey: item.id) != nil else { return }
        persistReadState()
    }

    /// Call with every fetched story after a refresh, so read history doesn't
    /// grow forever. Marks on stories still being served are renewed; marks
    /// on stories gone for longer than `readRetention` are forgotten.
    func renewReadMarks(for items: [FeedItem], now: Date = Date()) {
        var updated = readDates
        for item in items {
            guard let markedAt = updated[item.id],
                  now.timeIntervalSince(markedAt) > readRenewalInterval else { continue }
            updated[item.id] = now
        }

        let cutoff = now.addingTimeInterval(-readRetention)
        let savedIDs = Set(savedItems.map(\.id))
        updated = updated.filter { $0.value > cutoff || savedIDs.contains($0.key) }

        guard updated != readDates else { return }
        readDates = updated
        persistReadState()
    }

    func toggleReadState(for item: FeedItem) {
        if isRead(item) {
            markUnread(item)
        } else {
            markRead(item)
        }
    }

    func clearReadHistory() {
        guard !readDates.isEmpty else { return }
        readDates.removeAll()
        persistReadState()
    }

    // MARK: Saved stories

    func isSaved(_ item: FeedItem) -> Bool {
        savedItems.contains { $0.id == item.id }
    }

    func save(_ item: FeedItem) {
        if let index = savedItems.firstIndex(where: { $0.id == item.id }) {
            savedItems.remove(at: index)
        }

        savedItems.insert(item, at: 0)
        persistSavedItems()
    }

    func unsave(_ item: FeedItem) {
        guard let index = savedItems.firstIndex(where: { $0.id == item.id }) else { return }
        savedItems.remove(at: index)
        persistSavedItems()
    }

    func toggleSaved(_ item: FeedItem) {
        if isSaved(item) {
            unsave(item)
        } else {
            save(item)
        }
    }

    func clearSavedItems() {
        guard !savedItems.isEmpty else { return }
        savedItems.removeAll()
        persistSavedItems()
    }

    // MARK: Persistence

    private func persistReadState() {
        guard let data = try? JSONEncoder().encode(readDates) else { return }
        defaults.set(data, forKey: readDatesKey)
    }

    private func persistSavedItems() {
        guard let data = try? JSONEncoder().encode(savedItems) else { return }
        defaults.set(data, forKey: savedItemsKey)
    }
}
