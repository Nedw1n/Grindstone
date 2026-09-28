import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var preferences: FeedPreferences
    @EnvironmentObject private var feedUserState: FeedUserStateStore
    @EnvironmentObject private var rssStore: ManualRSSFeedStore
    @EnvironmentObject private var vm: FeedViewModel
    @EnvironmentObject private var engagement: EngagementLog

    @State private var isConfirmingClearRead = false
    @State private var isConfirmingClearSaved = false
    @State private var isConfirmingClearSignals = false

    var body: some View {
        NavigationStack {
            Form {
                brandSection
                readingSection
                sourcesSection
                historySection
                signalsSection
                aboutSection
            }
            .formStyle(.grouped)
            .readableMeasure(Theme.formWidth)
            .paperBackground()
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
            .confirmationDialog(
                "Clear reading signals?",
                isPresented: $isConfirmingClearSignals,
                titleVisibility: .visible
            ) {
                Button("Clear Reading Signals", role: .destructive) {
                    engagement.clear()
                }
            } message: {
                Text("Grindstone starts learning from scratch. Read and saved stories are not affected.")
            }
        }
    }

    // MARK: Sections

    private var brandSection: some View {
        Section {
            VStack(spacing: 12) {
                CairnMark(width: 76)
                    .padding(.bottom, 2)

                Text("Grindstone")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.ink)

                Text("A calm front page, gathered from the places you read.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .listRowBackground(Color.clear)
            .accessibilityElement(children: .combine)
        }
    }

    private var readingSection: some View {
        Section {
            Group {
                Toggle("Open Links in App", systemImage: "safari", isOn: $preferences.opensLinksInApp)
#if os(iOS)
                Toggle("Use Reader Mode When Available", systemImage: "doc.plaintext", isOn: $preferences.prefersReaderMode)
                    .disabled(!preferences.opensLinksInApp)
#endif
                Toggle("Show Previews", systemImage: "text.alignleft", isOn: $preferences.showPreviews)
                Toggle("Hide Read Stories", systemImage: "eye.slash", isOn: $preferences.hideReadItems)
            }
            .raisedFormRow()
        } header: {
            SettingsHeader("Reading")
        } footer: {
            SettingsFooter(readingFooter)
        }
    }

    private var sourcesSection: some View {
        Section {
            Group {
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
            }
            .raisedFormRow()
        } header: {
            SettingsHeader("Sources")
        } footer: {
            SettingsFooter("Switched-off sources are skipped on refresh and hidden from the feed.")
        }
    }

    private var historySection: some View {
        Section {
            Group {
                Button("Mark Everything as Read", systemImage: "checkmark.circle") {
                    engagement.recordMarkAllRead(vm.searchCorpus, userState: feedUserState)
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
            }
            .raisedFormRow()
        } header: {
            SettingsHeader("History")
        }
    }

    private var signalsSection: some View {
        Section {
            Group {
                LabeledContent("Recorded Events", value: engagement.eventCount.formatted())

                Button("Clear Reading Signals", systemImage: "trash", role: .destructive) {
                    isConfirmingClearSignals = true
                }
                .disabled(engagement.eventCount == 0)
            }
            .raisedFormRow()
        } header: {
            SettingsHeader("Reading Signals")
        } footer: {
            SettingsFooter("Grindstone keeps a private record of what you open, save, and skip, so it can learn what you like. It doesn't change the order of your feed yet, and it never leaves this device.")
        }
    }

    private var aboutSection: some View {
        Section {
            Group {
                LabeledContent("Version", value: versionString)
                LabeledContent("Stories Loaded", value: "\(vm.searchCorpus.count)")
                if let lastUpdatedAt = vm.lastUpdatedAt {
                    LabeledContent("Last Refresh", value: lastUpdatedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .raisedFormRow()
        } header: {
            SettingsHeader("About")
        } footer: {
            SettingsFooter("Grindstone pulls Hacker News, Memeorandum, biotech journals, and your own RSS feeds into one ranked list. A story that shows up in more than one place gets a small cairn, one stone per source.")
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

/// A form section header in the app's eyebrow capitals.
struct SettingsHeader: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .eyebrowStyle()
            .foregroundStyle(Theme.inkMuted)
    }
}

/// A form section footer in muted ink.
struct SettingsFooter: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .foregroundStyle(Theme.inkMuted)
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
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
        } icon: {
            SourceDot(source: source, size: 12)
        }
    }
}

#Preview {
    SettingsView()
        .previewEnvironment()
}
