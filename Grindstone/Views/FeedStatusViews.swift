import SwiftUI

/// Compact banner for sources that failed to refresh. Collapsed by default so a
/// flaky source never buries the stories that did load.
struct FeedFailureBanner: View {
    let failures: [SourceFailure]
    let onRetry: () -> Void
    let onDismiss: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.ochre)

                Text(headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)

                Spacer(minLength: 0)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isExpanded ? "Hide details" : "Show details")
            }

            if isExpanded {
                ForEach(failures) { failure in
                    Text("\(failure.source.rawValue): \(failure.message)")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 18) {
                Button("Try Again", action: onRetry)
                Button("Dismiss", action: onDismiss)
                    .tint(Theme.inkMuted)
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderless)
        }
        .padding(14)
        .background(Theme.paperRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        }
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SourceDot(source: .rss, size: 11)
                Text(hasFeeds ? "All RSS feeds are switched off" : "No RSS feeds yet")
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(Theme.ink)
            }

            Text(
                hasFeeds
                    ? "Turn a feed back on to see its stories here."
                    : "Add blogs, newsletters, and publications by pasting their RSS or Atom links."
            )
            .font(.subheadline)
            .foregroundStyle(Theme.inkMuted)
            .fixedSize(horizontal: false, vertical: true)

            Button(hasFeeds ? "Manage Feeds" : "Add a Feed", action: action)
                .buttonStyle(.pebble)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.paperRaised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        }
    }
}

/// Closes the feed: a small cairn and a way to clear what's left.
struct FeedEndMarker: View {
    let unreadCount: Int
    let onMarkAllRead: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            CairnGlyph(count: 3)
                .scaleEffect(1.4)
                .foregroundStyle(Theme.inkMuted)
                .padding(.bottom, 2)

            Text("You've reached the bottom of the stack.")
                .font(.system(.subheadline, design: .serif).italic())
                .foregroundStyle(Theme.inkMuted)

            if unreadCount > 0 {
                Button("Mark \(unreadCount) as Read", action: onMarkAllRead)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
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
        .paperListRow()

        RSSLibraryPromptRow(hasFeeds: false) {}
            .listRowSeparator(.hidden)
            .paperListRow()

        FeedEndMarker(unreadCount: 4) {}
            .listRowSeparator(.hidden)
            .paperListRow()
    }
    .listStyle(.plain)
    .paperBackground()
}
