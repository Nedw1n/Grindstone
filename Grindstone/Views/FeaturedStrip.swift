import SwiftUI

struct FeaturedStrip: View {
    let items: [FeedItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
                Text("Top Stories")
                    .font(.headline)
                Spacer()
                Text("Cross-posted first")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        ArticleLink(destination: .article(item)) {
                            FeaturedCard(item: item)
                        }
                    }
                }
                .padding(.horizontal)
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

private struct FeaturedCard: View {
    @EnvironmentObject private var feedUserState: FeedUserStateStore
    let item: FeedItem

    var body: some View {
        let isRead = feedUserState.isRead(item)
        let isSaved = feedUserState.isSaved(item)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                SourceTag(source: item.source)

                if !item.crossRefs.isEmpty {
                    Image(systemName: "link")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(item.orderedCrossRefs) { source in
                        SourceTag(source: source, style: .compact)
                    }
                }

                Spacer(minLength: 0)

                if isSaved {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }

            Text(item.title)
                .font(.headline)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .foregroundStyle(isRead ? .secondary : .primary)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if let outlet = item.displayOutlet {
                    Text(outlet)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if let points = item.points {
                    Label(points.compactFormatted, systemImage: "arrow.up")
                }

                if let comments = item.commentCount {
                    Label(comments.compactFormatted, systemImage: "bubble.right")
                }

                Text(item.publishedAt.relativeFormatted)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
        }
        .padding(14)
        .frame(width: 264, height: 160, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [item.source.color.opacity(0.22), item.source.color.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(item.source.color.opacity(0.25), lineWidth: 1)
        )
        .opacity(isRead ? 0.75 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .modifier(FeedItemContextMenu(item: item))
    }
}

#Preview {
    NavigationStack {
        FeaturedStrip(items: Array(FeedItem.mock.prefix(4)))
    }
    .previewEnvironment()
}
