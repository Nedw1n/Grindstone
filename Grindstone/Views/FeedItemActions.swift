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

    let item: FeedItem

    @ViewBuilder
    func body(content: Content) -> some View {
        let isRead = feedUserState.isRead(item)
        let isSaved = feedUserState.isSaved(item)

        content.contextMenu {
#if os(iOS)
            Button("Open", systemImage: "safari") {
                opener.open(.article(item))
            }

            if let discussion = ArticleDestination.discussion(item) {
                Button("Open Comments", systemImage: "bubble.left.and.bubble.right") {
                    opener.open(discussion)
                }
            }
#else
            Link(destination: item.url) {
                Label("Open in Browser", systemImage: "safari")
            }

            if let discussionURL = item.discussionURL {
                Link(destination: discussionURL) {
                    Label("Open Comments in Browser", systemImage: "bubble.left.and.bubble.right")
                }
            }
#endif

            Divider()

            Button(
                isSaved ? "Remove from Saved" : "Save for Later",
                systemImage: isSaved ? "bookmark.slash" : "bookmark"
            ) {
                feedUserState.toggleSaved(item)
            }

            Button(
                isRead ? "Mark as Unread" : "Mark as Read",
                systemImage: isRead ? "circle" : "checkmark.circle"
            ) {
                feedUserState.toggleReadState(for: item)
            }

            Divider()

            Button("Copy Link", systemImage: "link") {
                Pasteboard.copy(item.url)
            }

            ShareLink(item: item.url)
        }
    }

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
    let item: FeedItem

    var body: some View {
        let isSaved = feedUserState.isSaved(item)

        Button {
            feedUserState.toggleSaved(item)
        } label: {
            Label(
                isSaved ? "Unsave" : "Save",
                systemImage: isSaved ? "bookmark.slash" : "bookmark"
            )
        }
        .tint(.accentColor)
    }
}

/// Trailing swipe: toggle read state.
struct ReadSwipeButton: View {
    @EnvironmentObject private var feedUserState: FeedUserStateStore
    let item: FeedItem

    var body: some View {
        let isRead = feedUserState.isRead(item)

        Button {
            feedUserState.toggleReadState(for: item)
        } label: {
            Label(
                isRead ? "Unread" : "Read",
                systemImage: isRead ? "circle" : "checkmark.circle"
            )
        }
        .tint(isRead ? .gray : .blue)
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
