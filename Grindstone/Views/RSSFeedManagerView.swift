import SwiftUI

struct RSSLibrarySummaryCard: View {
    let feedCount: Int
    let enabledCount: Int
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("RSS Library", systemImage: "dot.radiowaves.left.and.right")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Keep built-ins focused, then drop blogs, newsletters, and niche feeds here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
            }

            HStack(spacing: 10) {
                RSSLibraryStatPill(value: "\(feedCount)", label: "Total")
                RSSLibraryStatPill(value: "\(enabledCount)", label: "Enabled")
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color.indigo.opacity(0.16),
                    Color.teal.opacity(0.10),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color.indigo.opacity(0.15), lineWidth: 1)
        )
    }
}

struct RSSFeedManagerView: View {
    @EnvironmentObject private var rssStore: ManualRSSFeedStore
    @Environment(\.dismiss) private var dismiss

    @State private var draftTitle = ""
    @State private var draftURL = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    RSSLibrarySummaryCard(
                        feedCount: rssStore.feeds.count,
                        enabledCount: rssStore.enabledFeeds.count,
                        actionTitle: "Done"
                    ) {
                        dismiss()
                    }

                    RSSComposerCard(
                        title: $draftTitle,
                        urlString: $draftURL,
                        errorMessage: errorMessage,
                        onAdd: addFeed
                    )

                    RSSFeedCollectionCard(
                        feeds: rssStore.feeds,
                        onToggle: { feed, isEnabled in
                            rssStore.setEnabled(isEnabled, for: feed.id)
                        },
                        onDelete: { feed in
                            rssStore.removeFeed(id: feed.id)
                        }
                    )
                }
                .padding()
            }
            .navigationTitle("RSS Feeds")
            .modifier(RSSInlineNavigationTitleDisplayMode())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
#if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
#endif
    }

    private func addFeed() {
        do {
            _ = try rssStore.addFeed(title: draftTitle, urlString: draftURL)
            draftTitle = ""
            draftURL = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RSSComposerCard: View {
    @Binding var title: String
    @Binding var urlString: String
    let errorMessage: String?
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Add Feed", systemImage: "plus.circle.fill")
                .font(.headline)

            Text("Paste an RSS or Atom URL. A custom name is optional, but useful when the feed title is messy.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                TextField("Display name (optional)", text: $title)
                    .textFieldStyle(.roundedBorder)

                TextField("https://example.com/feed.xml", text: $urlString)
                    .textFieldStyle(.roundedBorder)
#if os(iOS)
                    .textInputAutocapitalization(.never)
#endif
                    .autocorrectionDisabled()
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button(action: onAdd) {
                Label("Add to RSS Library", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct RSSFeedCollectionCard: View {
    let feeds: [ManualRSSFeed]
    let onToggle: (ManualRSSFeed, Bool) -> Void
    let onDelete: (ManualRSSFeed) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Your Feeds", systemImage: "tray.full.fill")
                .font(.headline)

            if feeds.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No manual feeds yet.")
                        .font(.subheadline.weight(.semibold))
                    Text("Marginal Revolution normally lives here by default. Add more feeds whenever you want a custom lane.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 12) {
                    ForEach(feeds) { feed in
                        RSSFeedRowCard(
                            feed: feed,
                            onToggle: { onToggle(feed, $0) },
                            onDelete: { onDelete(feed) }
                        )
                    }
                }
            }
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct RSSFeedRowCard: View {
    let feed: ManualRSSFeed
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.title3)
                    .foregroundStyle(feed.isEnabled ? .indigo : .secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(feed.title)
                        .font(.subheadline.weight(.semibold))
                    Text(feed.displayHost)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(feed.urlString)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 0)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            Toggle(isOn: Binding(get: { feed.isEnabled }, set: onToggle)) {
                Text(feed.isEnabled ? "Enabled" : "Disabled")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct RSSLibraryStatPill: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.55), in: Capsule())
    }
}

private struct RSSInlineNavigationTitleDisplayMode: ViewModifier {
    func body(content: Content) -> some View {
#if os(iOS)
        content.navigationBarTitleDisplayMode(.inline)
#else
        content
#endif
    }
}
