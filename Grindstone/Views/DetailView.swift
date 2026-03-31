import SwiftUI
#if os(iOS)
import SafariServices
#elseif os(macOS)
import WebKit
#endif

struct DetailView: View {
    @EnvironmentObject private var feedUserState: FeedUserStateStore
    let item: FeedItem

    var body: some View {
        detailContent
            .navigationTitle(item.title)
            .modifier(InlineNavigationTitleDisplayMode())
            .toolbar {
#if os(iOS)
                ToolbarItemGroup(placement: .topBarTrailing) {
                    bookmarkButton
                    ShareLink(item: item.url)
                }
#else
                ToolbarItemGroup(placement: .automatic) {
                    bookmarkButton
                    ShareLink(item: item.url)
                }
#endif
            }
            .task {
                feedUserState.markRead(item)
            }
    }

    @ViewBuilder
    private var detailContent: some View {
#if os(iOS)
        SafariView(url: item.url)
            .ignoresSafeArea()
#elseif os(macOS)
        WebView(url: item.url)
#else
        Link("Open in Browser", destination: item.url)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
#endif
    }

    private var bookmarkButton: some View {
        Button {
            feedUserState.toggleSaved(item)
        } label: {
            Image(systemName: feedUserState.isSaved(item) ? "bookmark.fill" : "bookmark")
        }
    }
}

/// Wraps SFSafariViewController for in-app article reading.
#if os(iOS)
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = true
        return SFSafariViewController(url: url, configuration: config)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#elseif os(macOS)
private struct WebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url))
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
