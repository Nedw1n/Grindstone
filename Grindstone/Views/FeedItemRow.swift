import SwiftUI

struct FeedItemRow: View {
    @EnvironmentObject private var feedUserState: FeedUserStateStore
    let item: FeedItem
    var showPreview: Bool = true

    var body: some View {
        let isRead = feedUserState.isRead(item)
        let isSaved = feedUserState.isSaved(item)

        VStack(alignment: .leading, spacing: 6) {
            // Title
            Text(item.title)
                .font(.headline)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(isRead ? .secondary : .primary)

            // Snippet
            if showPreview, let snippet = item.snippet {
                Text(snippet)
                    .font(.subheadline)
                    .foregroundStyle(isRead ? .tertiary : .secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Metadata row
            HStack(spacing: 8) {
                SourceTag(source: item.source)

                if let outlet = item.outlet {
                    Text(outlet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let points = item.points {
                    Label("\(points)", systemImage: "arrow.up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let comments = item.commentCount {
                    Label("\(comments)", systemImage: "bubble.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSaved {
                    Image(systemName: "bookmark.fill")
                        .font(.caption2)
                        .foregroundStyle(.indigo)
                }

                Text(item.publishedAt.relativeFormatted)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Cross-reference badges
            if !item.crossRefs.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(item.crossRefs, id: \.self) { ref in
                        SourceTag(source: ref, style: .compact)
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal)
        .opacity(isRead ? 0.72 : 1)
        .contextMenu {
            Button {
                feedUserState.toggleSaved(item)
            } label: {
                Label(
                    isSaved ? "Remove Bookmark" : "Save for Later",
                    systemImage: isSaved ? "bookmark.slash" : "bookmark"
                )
            }

            Button {
                feedUserState.toggleReadState(for: item)
            } label: {
                Label(
                    isRead ? "Mark as Unread" : "Mark as Read",
                    systemImage: isRead ? "envelope.badge" : "checkmark.circle"
                )
            }

            ShareLink(item: item.url)
        }
    }
}

#Preview {
    List {
        FeedItemRow(item: FeedItem.mock[0])
        FeedItemRow(item: FeedItem.mock[1])
    }
    .listStyle(.plain)
    .environmentObject({
        let defaults = UserDefaults(suiteName: "FeedItemRowPreview")!
        let store = FeedUserStateStore(defaults: defaults)
        store.save(FeedItem.mock[0])
        store.markRead(FeedItem.mock[1])
        return store
    }())
}
