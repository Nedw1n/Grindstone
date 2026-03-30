import SwiftUI
import SafariServices

struct DetailView: View {
    let item: FeedItem

    var body: some View {
        SafariView(url: item.url)
            .ignoresSafeArea()
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: item.url)
                }
            }
    }
}

/// Wraps SFSafariViewController for in-app article reading.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = true
        return SFSafariViewController(url: url, configuration: config)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
