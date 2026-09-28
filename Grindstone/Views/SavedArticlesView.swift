import SwiftUI

struct SavedArticlesView: View {
    @EnvironmentObject private var feedUserState: FeedUserStateStore
    @EnvironmentObject private var preferences: FeedPreferences
    @State private var isConfirmingRemoveAll = false

    var body: some View {
        NavigationStack {
            Group {
                if feedUserState.savedItems.isEmpty {
                    StoneEmptyState(
                        "Nothing set aside",
                        message: "Swipe right on a story, or press and hold it and choose Save for Later. It will keep here until you're ready."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(feedUserState.savedItems) { item in
                            ArticleLink(destination: .article(item)) {
                                FeedItemRow(item: item, showPreview: preferences.showPreviews)
                            }
                            .listRowInsets(EdgeInsets.storyRow)
                            .paperListRow()
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
            .paperBackground()
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
                            Label("Options", systemImage: "ellipsis")
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
