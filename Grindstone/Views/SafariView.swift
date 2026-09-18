#if os(iOS)
import SwiftUI
import SafariServices

/// Wraps `SFSafariViewController` for in-app reading. Presented full screen so
/// its own toolbar, Reader mode, and Done button all work as designed.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    var entersReaderIfAvailable = false

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = entersReaderIfAvailable

        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#endif
