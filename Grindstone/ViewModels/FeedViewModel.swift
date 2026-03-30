import Foundation
import Combine

@MainActor
final class FeedViewModel: ObservableObject {

    @Published var items: [FeedItem] = []
    @Published var filter: Source? = nil
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// Top item per source for the featured strip.
    var featured: [FeedItem] {
        Source.allCases.compactMap { src in
            items.first { $0.source == src }
        }
    }

    /// Items filtered by the selected source tab.
    var filtered: [FeedItem] {
        guard let f = filter else { return items }
        return items.filter { $0.source == f }
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil

        do {
            async let hn = HNService.fetch()
            async let memo = RSSService.fetch(.memo)
            async let mr = RSSService.fetch(.mr)

            let allResults = try await hn + memo + mr
            let deduped = CrossRefEngine.deduplicate(allResults)
            let crossReffed = CrossRefEngine.compute(deduped)

            items = crossReffed.sorted { $0.publishedAt > $1.publishedAt }
        } catch {
            errorMessage = error.localizedDescription
            // Keep stale items visible — only clear on first load failure
            if items.isEmpty {
                items = []
            }
        }

        isLoading = false
    }
}
