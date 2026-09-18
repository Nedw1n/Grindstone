import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var preferences: FeedPreferences
    @EnvironmentObject private var feedUserState: FeedUserStateStore
    @EnvironmentObject private var rssStore: ManualRSSFeedStore
    @EnvironmentObject private var vm: FeedViewModel

    @State private var isConfirmingClearRead = false
    @State private var isConfirmingClearSaved = false

    var body: some View {
        NavigationStack {
            Form {
                readingSection
                sourcesSection
                historySection
                aboutSection
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .confirmationDialog(
                "Clear read history?",
                isPresented: $isConfirmingClearRead,
                titleVisibility: .visible
            ) {
                Button("Clear Read History", role: .destructive) {
                    feedUserState.clearReadHistory()
                }
            } message: {
                Text("Every story will show as unread again. Saved stories are not affected.")
            }
            .confirmationDialog(
                "Remove all saved stories?",
                isPresented: $isConfirmingClearSaved,
                titleVisibility: .visible
            ) {
                Button("Remove All Saved Stories", role: .destructive) {
                    feedUserState.clearSavedItems()
                }
            }
        }
    }

    // MARK: Sections

    private var readingSection: some View {
        Section {
            Toggle("Open Links in App", systemImage: "safari", isOn: $preferences.opensLinksInApp)
#if os(iOS)
            Toggle("Use Reader Mode When Available", systemImage: "doc.plaintext", isOn: $preferences.prefersReaderMode)
                .disabled(!preferences.opensLinksInApp)
#endif
            Toggle("Show Previews", systemImage: "text.alignleft", isOn: $preferences.showPreviews)
            Toggle("Hide Read Stories", systemImage: "eye.slash", isOn: $preferences.hideReadItems)
        } header: {
            Text("Reading")
        } footer: {
            Text(readingFooter)
        }
    }

    private var sourcesSection: some View {
        Section {
            ForEach(Source.builtInSources) { source in
                Toggle(isOn: binding(for: source)) {
                    SourceSettingsLabel(
                        source: source,
                        title: source.rawValue,
                        subtitle: source.summary
                    )
                }
            }

            NavigationLink {
                RSSFeedManagerView()
            } label: {
                SourceSettingsLabel(
                    source: .rss,
                    title: "RSS Feeds",
                    subtitle: rssSummary
                )
            }
        } header: {
            Text("Sources")
        } footer: {
            Text("Switched-off sources are skipped on refresh and hidden from the feed.")
        }
    }

    private var historySection: some View {
        Section {
            Button("Mark Everything as Read", systemImage: "checkmark.circle") {
                feedUserState.markRead(vm.searchCorpus)
            }
            .disabled(feedUserState.unreadCount(in: vm.searchCorpus) == 0)

            Button("Clear Read History", systemImage: "arrow.counterclockwise", role: .destructive) {
                isConfirmingClearRead = true
            }
            .disabled(feedUserState.readItemIDs.isEmpty)

            Button("Remove All Saved Stories", systemImage: "bookmark.slash", role: .destructive) {
                isConfirmingClearSaved = true
            }
            .disabled(feedUserState.savedItems.isEmpty)
        } header: {
            Text("History")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: versionString)
            LabeledContent("Stories Loaded", value: "\(vm.searchCorpus.count)")
            if let lastUpdatedAt = vm.lastUpdatedAt {
                LabeledContent("Last Refresh", value: lastUpdatedAt.formatted(date: .abbreviated, time: .shortened))
            }
        } header: {
            Text("About")
        } footer: {
            Text("Grindstone pulls Hacker News, Memeorandum, biotech journals, and your own RSS feeds into one ranked list, and flags stories that show up in more than one place.")
        }
    }

    // MARK: Helpers

    private func binding(for source: Source) -> Binding<Bool> {
        Binding(
            get: { preferences.isEnabled(source) },
            set: { preferences.setEnabled($0, for: source) }
        )
    }

    private var readingFooter: String {
#if os(iOS)
        return preferences.opensLinksInApp
            ? "Stories open in an in-app Safari view. Reader mode strips pages down to the article text."
            : "Stories open in Safari."
#else
        return preferences.opensLinksInApp
            ? "Stories open inside Grindstone."
            : "Stories open in your default browser."
#endif
    }

    private var rssSummary: String {
        let total = rssStore.feeds.count
        let enabled = rssStore.enabledFeeds.count

        switch total {
        case 0:
            return "No feeds added yet"
        case 1:
            return enabled == 1 ? "1 feed" : "1 feed, switched off"
        default:
            return enabled == total ? "\(total) feeds" : "\(enabled) of \(total) feeds on"
        }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        if let build = info?["CFBundleVersion"] as? String, build != version {
            return "\(version) (\(build))"
        }
        return version
    }
}

private struct SourceSettingsLabel: View {
    let source: Source
    let title: String
    let subtitle: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: source.iconName)
                .foregroundStyle(source.color)
        }
    }
}

#Preview {
    SettingsView()
        .previewEnvironment()
}
