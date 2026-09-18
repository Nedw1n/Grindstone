import SwiftUI

/// Compact banner for sources that failed to refresh. Collapsed by default so a
/// flaky source never buries the stories that did load.
struct FeedFailureBanner: View {
    let failures: [SourceFailure]
    let onRetry: () -> Void
    let onDismiss: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)

                Text(headline)
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 0)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isExpanded ? "Hide details" : "Show details")
            }

            if isExpanded {
                ForEach(failures) { failure in
                    Text("\(failure.source.rawValue): \(failure.message)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 16) {
                Button("Try Again", action: onRetry)
                Button("Dismiss", action: onDismiss)
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var headline: String {
        let names = failures.map { $0.source.rawValue }
        return "Couldn't refresh \(ListFormatter.localizedString(byJoining: names))"
    }
}

/// Shown in the RSS lane when there is nothing to fetch yet.
struct RSSLibraryPromptRow: View {
    let hasFeeds: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                hasFeeds ? "All RSS feeds are switched off" : "No RSS feeds yet",
                systemImage: "dot.radiowaves.left.and.right"
            )
            .font(.headline)

            Text(
                hasFeeds
                    ? "Turn a feed back on to see its stories here."
                    : "Add blogs, newsletters, and publications by pasting their RSS or Atom links."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Button(hasFeeds ? "Manage Feeds" : "Add a Feed", action: action)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.indigo.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    List {
        FeedFailureBanner(
            failures: [
                SourceFailure(source: .hn, message: "The request timed out."),
                SourceFailure(source: .biotech, message: "bioRxiv returned HTTP 503."),
            ],
            onRetry: {},
            onDismiss: {}
        )
        .listRowSeparator(.hidden)

        RSSLibraryPromptRow(hasFeeds: false) {}
            .listRowSeparator(.hidden)
    }
    .listStyle(.plain)
}
