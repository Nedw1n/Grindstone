import SwiftUI

struct SavedArticlesView: View {
    @EnvironmentObject private var feedUserState: FeedUserStateStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if feedUserState.savedItems.isEmpty {
                    ContentUnavailableView(
                        "No Saved Articles",
                        systemImage: "bookmark",
                        description: Text("Save stories from the feed to keep a short reading list here.")
                    )
                } else {
                    List {
                        ForEach(feedUserState.savedItems) { item in
                            NavigationLink(value: item) {
                                FeedItemRow(item: item)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    feedUserState.unsave(item)
                                } label: {
                                    Label("Remove", systemImage: "bookmark.slash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Saved")
            .navigationDestination(for: FeedItem.self) { item in
                DetailView(item: item)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
#if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
#endif
    }
}

#Preview {
    SavedArticlesView()
        .environmentObject({
            let defaults = UserDefaults(suiteName: "SavedArticlesViewPreview")!
            let store = FeedUserStateStore(defaults: defaults)
            store.save(FeedItem.mock[0])
            store.save(FeedItem.mock[1])
            return store
        }())
}
