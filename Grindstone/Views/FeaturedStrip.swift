import SwiftUI

struct FeaturedStrip: View {
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
    let item: FeedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SourceTag(source: item.source)
                Spacer()
                if !item.crossRefs.isEmpty {
                    Image(systemName: "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(3)
                .foregroundStyle(.primary)

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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(item.source.color.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    NavigationStack {
        FeaturedStrip(items: Array(FeedItem.mock.prefix(3)))
    }
}
