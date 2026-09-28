import SwiftUI

/// Top of the Stack: up to three stories set as the icon's cairn. The stones
/// share one width and grow thicker toward the base, light on top and dark
/// below, each carrying a little of the icon's granite grain.
struct StoneStack: View {
    let items: [FeedItem]
    var showPreview = true
    var now = Date()

    var body: some View {
        VStack(spacing: 5) {
            ForEach(stones) { stone in
                ArticleLink(destination: .article(stone.item)) {
                    StoneCard(item: stone.item, tone: stone.tone, showPreview: showPreview, now: now)
                }
            }
        }
    }

    private var stones: [PlacedStone] {
        zip(items, StoneTone.stack(count: items.count)).map { item, tone in
            PlacedStone(item: item, tone: tone)
        }
    }
}

private struct PlacedStone: Identifiable {
    let item: FeedItem
    let tone: StoneTone

    var id: String { item.id }
}

private struct StoneCard: View {
    @EnvironmentObject private var feedUserState: FeedUserStateStore
    @Environment(\.colorScheme) private var colorScheme

    /// The capstone's minimum height; the stones below scale up from it.
    @ScaledMetric(relativeTo: .title3) private var capstoneHeight: CGFloat = 124
    /// Room kept at the bottom for the footer, which is pinned there.
    @ScaledMetric(relativeTo: .caption) private var footerReserve: CGFloat = 24

    let item: FeedItem
    let tone: StoneTone
    let showPreview: Bool
    let now: Date

    private let verticalPadding: CGFloat = 16

    var body: some View {
        let isRead = feedUserState.isRead(item)
        let hasFooter = StoryFooter.hasContent(for: item)
        let shape = UnevenRoundedRectangle(cornerRadii: tone.cornerRadii, style: .continuous)

        VStack(alignment: .leading, spacing: 6) {
            StoryEyebrow(
                item: item,
                now: now,
                isSaved: feedUserState.isSaved(item),
                savedTint: tone.primaryText
            )
            .foregroundStyle(tone.secondaryText)

            // Read stories drop to a regular weight; unread ones stay heavy.
            Text(item.title)
                .font(.system(.title3, design: .serif).weight(isRead ? .regular : .semibold))
                .foregroundStyle(isRead ? tone.secondaryText : tone.primaryText)
                .lineLimit(tone == .light ? 2 : 3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            // Only the base stone is thick enough to carry a preview.
            if tone == .dark, showPreview, let snippet = item.snippet {
                Text(snippet)
                    .font(.subheadline)
                    .foregroundStyle(tone.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, hasFooter ? footerReserve : 0)
        .frame(
            maxWidth: .infinity,
            minHeight: capstoneHeight * tone.heightFactor - verticalPadding * 2,
            alignment: .topLeading
        )
        .overlay(alignment: .bottomLeading) {
            if hasFooter {
                StoryFooter(item: item)
                    .foregroundStyle(tone.secondaryText)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, verticalPadding)
        .environment(\.colorScheme, tone.isDarkSurface ? .dark : colorScheme)
        .background {
            StoneSurface(tone: tone)
        }
        .contentShape(shape)
        .contentShape(.contextMenuPreview, shape)
        .animation(.easeOut(duration: 0.2), value: isRead)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isRead ? "" : "Unread")
        .modifier(FeedItemContextMenu(item: item))
    }
}

#Preview {
    ScrollView {
        StoneStack(items: Array(FeedItem.mock.prefix(3)))
            .padding(16)
    }
    .background(Theme.paper)
    .previewEnvironment()
}
