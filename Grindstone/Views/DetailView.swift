import SwiftUI
#if os(macOS)
import WebKit
#endif

/// In-app reader used when a story is pushed onto a navigation stack (macOS,
/// visionOS). iOS presents `SafariView` full screen through `ArticleRouter`.
struct DetailView: View {
    @EnvironmentObject private var feedUserState: FeedUserStateStore
    let destination: ArticleDestination
    @State private var kind: ArticleDestination.Kind
    @State private var openedAt: Date?

    init(destination: ArticleDestination) {
        self.destination = destination
        kind = destination.kind
    }

    private var item: FeedItem { destination.item }

    private var currentURL: URL {
        switch kind {
        case .article:
            return item.url
        case .discussion:
            return item.discussionURL ?? item.url
        }
    }

    var body: some View {
        content
            .navigationTitle(item.title)
            .modifier(InlineNavigationTitleDisplayMode())
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    if item.discussionURL != nil {
                        Picker("View", selection: $kind) {
                            Text("Article").tag(ArticleDestination.Kind.article)
                            Text("Comments").tag(ArticleDestination.Kind.discussion)
                        }
                        .pickerStyle(.segmented)
                    }

                    Button {
                        EngagementLog.shared.record(feedUserState.isSaved(item) ? .unsave : .save, item)
                        feedUserState.toggleSaved(item)
                    } label: {
                        Label(
                            feedUserState.isSaved(item) ? "Unsave" : "Save",
                            systemImage: feedUserState.isSaved(item) ? "bookmark.fill" : "bookmark"
                        )
                    }

                    Link(destination: currentURL) {
                        Label("Open in Browser", systemImage: "safari")
                    }

                    ShareLink(item: currentURL)
                }
            }
            .task {
                EngagementLog.shared.record(destination.kind == .article ? .open : .openDiscussion, item)
                openedAt = Date()
                feedUserState.markRead(item)
            }
            .onDisappear {
                guard let openedAt else { return }
                self.openedAt = nil
                EngagementLog.shared.record(
                    .closeReader,
                    item,
                    readingSeconds: Int(Date().timeIntervalSince(openedAt))
                )
            }
    }

    @ViewBuilder
    private var content: some View {
#if os(macOS)
        WebView(url: currentURL)
#elseif os(iOS)
        SafariView(url: currentURL)
            .ignoresSafeArea()
#else
        ContentUnavailableView {
            Label(item.title, systemImage: "safari")
        } description: {
            Text(item.displayOutlet ?? "")
        } actions: {
            Link("Open in Browser", destination: currentURL)
                .buttonStyle(.borderedProminent)
        }
#endif
    }
}

#if os(macOS)
private struct WebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        webView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(loadedURL: url)
    }

    final class Coordinator {
        var loadedURL: URL

        init(loadedURL: URL) {
            self.loadedURL = loadedURL
        }
    }
}
#endif

private struct InlineNavigationTitleDisplayMode: ViewModifier {
    func body(content: Content) -> some View {
#if os(iOS)
        content.navigationBarTitleDisplayMode(.inline)
#else
        content
#endif
    }
}
