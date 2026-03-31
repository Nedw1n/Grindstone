import SwiftUI

struct FeedItemRow: View {
    let item: FeedItem
    var showPreview: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title
            Text(item.title)
                .font(.headline)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.primary)

            // Snippet
            if showPreview, let snippet = item.snippet {
                Text(snippet)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
        .contextMenu {
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
}
