import SwiftUI

/// A source's mineral tint as a small pebble.
struct SourceDot: View {
    let source: Source
    var size: CGFloat = 8

    var body: some View {
        Ellipse()
            .fill(source.color)
            .frame(width: size, height: size * 0.75)
            .accessibilityHidden(true)
    }
}

/// Source, outlet, and age on one quiet line above a headline. Takes its
/// color from the surrounding foreground style.
struct StoryEyebrow: View {
    let item: FeedItem
    var now: Date = Date()
    var isSaved = false
    /// The saved bookmark's color. Stones pass their own text color, since moss
    /// is too faint on the darker stones.
    var savedTint: Color = .accentColor

    var body: some View {
        HStack(spacing: 6) {
            SourceDot(source: item.source)

            Text(item.source.rawValue)
                .eyebrowStyle()
                .layoutPriority(1)

            Text(detail)
                .font(.caption2)

            Spacer(minLength: 4)

            if isSaved {
                Image(systemName: "bookmark.fill")
                    .font(.caption2)
                    .foregroundStyle(savedTint)
                    .accessibilityLabel("Saved")
            }
        }
        .lineLimit(1)
    }

    private var detail: String {
        let age = item.publishedAt.relativeFormatted(relativeTo: now)
        guard let outlet = item.displayOutlet else { return age }
        return "\(outlet) · \(age)"
    }
}

/// Points, comments, and where else the story appears. Takes its color from
/// the surrounding foreground style.
struct StoryFooter: View {
    let item: FeedItem

    static func hasContent(for item: FeedItem) -> Bool {
        item.points != nil || item.commentCount != nil || !item.crossRefs.isEmpty
    }

    var body: some View {
        HStack(spacing: 12) {
            if let points = item.points {
                metric(points.compactFormatted, systemImage: "arrow.up")
                    .accessibilityLabel("\(points) points")
            }

            if let comments = item.commentCount {
                metric(comments.compactFormatted, systemImage: "bubble.right")
                    .accessibilityLabel("\(comments) comments")
            }

            if !item.crossRefs.isEmpty {
                HStack(spacing: 5) {
                    CairnGlyph(count: item.crossRefs.count + 1)
                    Text("Also on \(crossRefNames)")
                }
                .accessibilityElement(children: .combine)
            }
        }
        .font(.caption)
        .lineLimit(1)
    }

    private var crossRefNames: String {
        item.orderedCrossRefs.map(\.shortName).joined(separator: ", ")
    }

    private func metric(_ value: String, systemImage: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .fontWeight(.semibold)
            Text(value)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        ForEach(FeedItem.mock) { item in
            VStack(alignment: .leading, spacing: 6) {
                StoryEyebrow(item: item, isSaved: item.id == FeedItem.mock[0].id)
                StoryFooter(item: item)
            }
            .foregroundStyle(Theme.inkMuted)
        }
    }
    .padding()
    .background(Theme.paper)
}
