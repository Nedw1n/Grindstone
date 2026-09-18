import Foundation
import Combine

@MainActor
final class FeedUserStateStore: ObservableObject {
    static let shared = FeedUserStateStore()

    @Published private(set) var readItemIDs: Set<String>
    @Published private(set) var savedItems: [FeedItem]

    private let defaults: UserDefaults
    private let readItemIDsKey = "feed.readItemIDs"
    private let savedItemsKey = "feed.savedItems"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.readItemIDs = Set(defaults.stringArray(forKey: readItemIDsKey) ?? [])

        if let data = defaults.data(forKey: savedItemsKey),
           let decoded = try? JSONDecoder().decode([FeedItem].self, from: data) {
            self.savedItems = decoded
        } else {
            self.savedItems = []
        }
    }

    // MARK: Read state

    func isRead(_ item: FeedItem) -> Bool {
        readItemIDs.contains(item.id)
    }

    func unreadCount(in items: [FeedItem]) -> Int {
        items.reduce(into: 0) { count, item in
            if !readItemIDs.contains(item.id) {
                count += 1
            }
        }
    }

    func markRead(_ item: FeedItem) {
        guard readItemIDs.insert(item.id).inserted else { return }
        persistReadState()
    }

    func markRead(_ items: [FeedItem]) {
        let before = readItemIDs.count
        for item in items {
            readItemIDs.insert(item.id)
        }
        guard readItemIDs.count != before else { return }
        persistReadState()
    }

    func markUnread(_ item: FeedItem) {
        guard readItemIDs.remove(item.id) != nil else { return }
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
        guard !readItemIDs.isEmpty else { return }
        readItemIDs.removeAll()
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
        defaults.set(Array(readItemIDs).sorted(), forKey: readItemIDsKey)
    }

    private func persistSavedItems() {
        guard let data = try? JSONEncoder().encode(savedItems) else { return }
        defaults.set(data, forKey: savedItemsKey)
    }
}
