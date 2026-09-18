import SwiftUI

struct SavedArticlesView: View {
    @EnvironmentObject private var feedUserState: FeedUserStateStore
    @EnvironmentObject private var preferences: FeedPreferences
    @State private var isConfirmingRemoveAll = false

    var body: some View {
        NavigationStack {
            Group {
                if feedUserState.savedItems.isEmpty {
                    ContentUnavailableView {
                        Label("No Saved Stories", systemImage: "bookmark")
                    } description: {
                        Text("Swipe a story to the right, or hold it and choose Save for Later. It will wait for you here.")
                    }
                } else {
                    List {
                        ForEach(feedUserState.savedItems) { item in
                            ArticleLink(destination: .article(item)) {
                                FeedItemRow(item: item, showPreview: preferences.showPreviews)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    feedUserState.unsave(item)
                                } label: {
                                    Label("Remove", systemImage: "bookmark.slash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                ReadSwipeButton(item: item)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Saved")
            .navigationSubtitle(subtitle)
            .toolbar {
                if !feedUserState.savedItems.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Mark All as Read", systemImage: "checkmark.circle") {
                                feedUserState.markRead(feedUserState.savedItems)
                            }
                            .disabled(feedUserState.unreadCount(in: feedUserState.savedItems) == 0)

                            Button("Remove All", systemImage: "trash", role: .destructive) {
                                isConfirmingRemoveAll = true
                            }
                        } label: {
                            Label("Options", systemImage: "ellipsis.circle")
                        }
                    }
                }
            }
            .confirmationDialog(
                "Remove all saved stories?",
                isPresented: $isConfirmingRemoveAll,
                titleVisibility: .visible
            ) {
                Button("Remove All", role: .destructive) {
                    feedUserState.clearSavedItems()
                }
            }
            .navigationDestination(for: ArticleDestination.self) { destination in
                DetailView(destination: destination)
            }
        }
    }

    private var subtitle: String {
        let items = feedUserState.savedItems
        guard !items.isEmpty else { return "" }

        let unread = feedUserState.unreadCount(in: items)
        let countText = items.count == 1 ? "1 story" : "\(items.count) stories"
        return unread == 0 ? countText : "\(countText) · \(unread) unread"
    }
}

#Preview {
    SavedArticlesView()
        .previewEnvironment()
}
