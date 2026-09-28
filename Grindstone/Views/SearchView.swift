import SwiftUI

/// Searches every fetched story (not just the merged front page) plus the saved list.
struct SearchView: View {
    @EnvironmentObject private var vm: FeedViewModel
    @EnvironmentObject private var feedUserState: FeedUserStateStore
    @EnvironmentObject private var preferences: FeedPreferences
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Group {
                if trimmedQuery.isEmpty {
                    StoneEmptyState(
                        "Search every story",
                        message: "Find stories by title, outlet, or snippet across every source and your saved list."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    StoneEmptyState(
                        "No matches for “\(trimmedQuery)”",
                        message: "Try another word, or the name of an outlet."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        SectionEyebrow(results.count == 1 ? "1 story" : "\(results.count) stories")
                            .listRowInsets(EdgeInsets.sectionEyebrow)
                            .listRowSeparator(.hidden)
                            .paperListRow()

                        ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                            ArticleLink(destination: .article(item)) {
                                FeedItemRow(item: item, showPreview: preferences.showPreviews)
                            }
                            .environment(\.storyPlacement, StoryPlacement(surface: .search, position: index))
                            .listRowInsets(EdgeInsets.storyRow)
                            .paperListRow()
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                SaveSwipeButton(item: item)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                ReadSwipeButton(item: item)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .readableMeasure()
                }
            }
            .paperBackground()
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Titles, outlets, snippets")
            .navigationDestination(for: ArticleDestination.self) { destination in
                DetailView(destination: destination)
            }
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var results: [FeedItem] {
        let query = trimmedQuery
        guard !query.isEmpty else { return [] }

        var seen = Set<String>()
        var candidates: [FeedItem] = []

        for item in vm.searchCorpus + feedUserState.savedItems where seen.insert(item.id).inserted {
            candidates.append(item)
        }

        return candidates.filter { $0.matchesSearch(query) }
    }
}

#Preview {
    SearchView()
        .previewEnvironment()
}
