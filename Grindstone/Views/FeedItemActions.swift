import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The long-press / right-click menu shared by feed rows and featured cards.
struct FeedItemContextMenu: ViewModifier {
    @EnvironmentObject private var router: ArticleRouter
    @EnvironmentObject private var preferences: FeedPreferences
    @EnvironmentObject private var feedUserState: FeedUserStateStore
    @Environment(\.openURL) private var openURL
    @Environment(\.storyPlacement) private var placement

    let item: FeedItem

    @ViewBuilder
    func body(content: Content) -> some View {
        let isRead = feedUserState.isRead(item)
        let isSaved = feedUserState.isSaved(item)

        content.contextMenu {
#if os(iOS)
            Button("Open", systemImage: "safari") {
                opener.open(.article(item), placement: placement)
            }

            if let discussion = ArticleDestination.discussion(item) {
                Button("Open Comments", systemImage: "bubble.left.and.bubble.right") {
                    opener.open(discussion, placement: placement)
                }
            }
#else
            Button("Open in Browser", systemImage: "safari") {
                openInBrowser(.article(item))
            }

            if let discussion = ArticleDestination.discussion(item) {
                Button("Open Comments in Browser", systemImage: "bubble.left.and.bubble.right") {
                    openInBrowser(discussion)
                }
            }
#endif

            Divider()

            Button(
                isSaved ? "Remove from Saved" : "Save for Later",
                systemImage: isSaved ? "bookmark.slash" : "bookmark"
            ) {
                EngagementLog.shared.record(isSaved ? .unsave : .save, item, placement: placement)
                feedUserState.toggleSaved(item)
            }

            Button(
                isRead ? "Mark as Unread" : "Mark as Read",
                systemImage: isRead ? "circle" : "checkmark.circle"
            ) {
                EngagementLog.shared.record(isRead ? .markUnread : .markRead, item, placement: placement)
                feedUserState.toggleReadState(for: item)
            }

            Divider()

            Button("Copy Link", systemImage: "link") {
                EngagementLog.shared.record(.copyLink, item, placement: placement)
                Pasteboard.copy(item.url)
            }

            ShareLink(item: item.url)
        }
    }

#if !os(iOS)
    /// Opens in the default browser, logged like any other open.
    private func openInBrowser(_ destination: ArticleDestination) {
        EngagementLog.shared.record(
            destination.kind == .article ? .open : .openDiscussion,
            destination.item,
            placement: placement
        )
        feedUserState.markRead(destination.item)
        openURL(destination.url)
    }
#endif

    private var opener: ArticleOpener {
        ArticleOpener(
            router: router,
            preferences: preferences,
            userState: feedUserState,
            openURL: openURL
        )
    }
}

/// Leading swipe: save or unsave.
struct SaveSwipeButton: View {
    @EnvironmentObject private var feedUserState: FeedUserStateStore
    @Environment(\.storyPlacement) private var placement
    let item: FeedItem

    var body: some View {
        let isSaved = feedUserState.isSaved(item)

        Button {
            EngagementLog.shared.record(isSaved ? .unsave : .save, item, placement: placement)
            feedUserState.toggleSaved(item)
        } label: {
            Label(
                isSaved ? "Unsave" : "Save",
                systemImage: isSaved ? "bookmark.slash" : "bookmark"
            )
        }
        .tint(isSaved ? StoneTone.dark.fill : Theme.mossDeep)
    }
}

/// Trailing swipe: toggle read state.
struct ReadSwipeButton: View {
    @EnvironmentObject private var feedUserState: FeedUserStateStore
    @Environment(\.storyPlacement) private var placement
    let item: FeedItem

    var body: some View {
        let isRead = feedUserState.isRead(item)

        Button {
            EngagementLog.shared.record(isRead ? .markUnread : .markRead, item, placement: placement)
            feedUserState.toggleReadState(for: item)
        } label: {
            Label(
                isRead ? "Unread" : "Read",
                systemImage: isRead ? "circle" : "checkmark.circle"
            )
        }
        .tint(isRead ? StoneTone.dark.fill : StoneTone.mid.fill)
    }
}

enum Pasteboard {
    static func copy(_ url: URL) {
#if canImport(UIKit)
        UIPasteboard.general.url = url
#elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        _ = NSPasteboard.general.setString(url.absoluteString, forType: .string)
#endif
    }
}
