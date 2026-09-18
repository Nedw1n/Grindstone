import SwiftUI

struct FeedItemRow: View {
    @EnvironmentObject private var feedUserState: FeedUserStateStore
    let item: FeedItem
    var showPreview: Bool = true
    var now: Date = Date()

    var body: some View {
        let isRead = feedUserState.isRead(item)
        let isSaved = feedUserState.isSaved(item)

        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(isRead ? Color.clear : Color.accentColor)
                .frame(width: 7, height: 7)
                .padding(.top, 7)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.headline.weight(isRead ? .regular : .semibold))
                    .foregroundStyle(isRead ? .secondary : .primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if showPreview, let snippet = item.snippet {
                    Text(snippet)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    SourceTag(source: item.source)

                    if let outlet = item.displayOutlet {
                        Text(outlet)
                            .lineLimit(1)
                    }

                    Text("·")
                    Text(item.publishedAt.relativeFormatted(relativeTo: now))

                    Spacer(minLength: 8)

                    if let points = item.points {
                        Label(points.compactFormatted, systemImage: "arrow.up")
                    }

                    if let comments = item.commentCount {
                        Label(comments.compactFormatted, systemImage: "bubble.right")
                    }

                    if isSaved {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)

                if !item.crossRefs.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                        Text("Also on")
                        ForEach(item.orderedCrossRefs) { source in
                            SourceTag(source: source, style: .compact)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .modifier(FeedItemContextMenu(item: item))
    }
}

#Preview {
    List {
        FeedItemRow(item: FeedItem.mock[0])
        FeedItemRow(item: FeedItem.mock[1])
        FeedItemRow(item: FeedItem.mock[3])
    }
    .listStyle(.plain)
    .previewEnvironment()
}
