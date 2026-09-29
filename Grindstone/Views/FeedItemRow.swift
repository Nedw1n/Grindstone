import SwiftUI

struct FeedItemRow: View {
    @EnvironmentObject private var feedUserState: FeedUserStateStore
    @Environment(\.storyPlacement) private var placement
    let item: FeedItem
    var showPreview: Bool = true
    var now: Date = Date()

    var body: some View {
        let isRead = feedUserState.isRead(item)

        VStack(alignment: .leading, spacing: 6) {
            StoryEyebrow(item: item, now: now, isSaved: feedUserState.isSaved(item))
                .foregroundStyle(Theme.inkMuted)

            // Read state lives in the type: unread headlines are set heavy in
            // ink, read ones drop to a regular weight in muted ink.
            Text(item.title)
                .font(.system(.headline, design: .serif).weight(isRead ? .regular : .semibold))
                .foregroundStyle(isRead ? Theme.inkMuted : Theme.ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if showPreview, let snippet = item.snippet {
                Text(snippet)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if StoryFooter.hasContent(for: item) {
                StoryFooter(item: item)
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.2), value: isRead)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isRead ? "" : "Unread")
        .modifier(FeedItemContextMenu(item: item))
        .onAppear {
            guard let placement else { return }
            EngagementLog.shared.recordImpression(item, placement: placement)
        }
    }
}

#Preview {
    List {
        FeedItemRow(item: FeedItem.mock[0])
            .paperListRow()
        FeedItemRow(item: FeedItem.mock[1])
            .paperListRow()
        FeedItemRow(item: FeedItem.mock[3])
            .paperListRow()
    }
    .listStyle(.plain)
    .paperBackground()
    .previewEnvironment()
}
