import SwiftUI

struct FeaturedStrip: View {
    @EnvironmentObject private var feedUserState: FeedUserStateStore
    let items: [FeedItem]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        FeaturedCard(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

private struct FeaturedCard: View {
    @EnvironmentObject private var feedUserState: FeedUserStateStore
    let item: FeedItem

    var body: some View {
        let isRead = feedUserState.isRead(item)
        let isSaved = feedUserState.isSaved(item)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SourceTag(source: item.source)
                Spacer()
                HStack(spacing: 6) {
                    if isSaved {
                        Image(systemName: "bookmark.fill")
                            .font(.caption)
                            .foregroundStyle(.indigo)
                    }
                    if !item.crossRefs.isEmpty {
                        Image(systemName: "link")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(3)
                .foregroundStyle(isRead ? .secondary : .primary)

            Spacer()

            HStack {
                if let points = item.points {
                    Label("\(points)", systemImage: "arrow.up")
                        .font(.caption2)
                }
                if let comments = item.commentCount {
                    Label("\(comments)", systemImage: "bubble.right")
                        .font(.caption2)
                }
                Spacer()
                Text(item.publishedAt.relativeFormatted)
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 220, height: 150, alignment: .topLeading)
        .opacity(isRead ? 0.74 : 1)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(item.source.color.opacity(0.3), lineWidth: 1)
        )
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
    NavigationStack {
        FeaturedStrip(items: Array(FeedItem.mock.prefix(3)))
    }
    .environmentObject({
        let defaults = UserDefaults(suiteName: "FeaturedStripPreview")!
        let store = FeedUserStateStore(defaults: defaults)
        store.save(FeedItem.mock[0])
        store.markRead(FeedItem.mock[1])
        return store
    }())
}
