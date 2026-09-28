import SwiftUI
import UniformTypeIdentifiers

/// The RSS library. Push it from Settings, or present `RSSFeedManagerSheet`
/// from the feed.
struct RSSFeedManagerView: View {
    @EnvironmentObject private var rssStore: ManualRSSFeedStore

    @State private var draftTitle = ""
    @State private var draftURL = ""
    @State private var composerErrorMessage: String?
    @State private var transferStatus: RSSLibraryTransferStatus?
    @State private var isShowingOPMLImporter = false
    @State private var isShowingOPMLExporter = false
    @State private var pendingExport: RSSOPMLExport?

    var body: some View {
        Form {
            composerSection
            feedsSection
            backupSection
        }
        .formStyle(.grouped)
        .paperBackground()
        .navigationTitle("RSS Feeds")
        .fileImporter(
            isPresented: $isShowingOPMLImporter,
            allowedContentTypes: [.opml, .xml]
        ) { result in
            importOPML(result)
        }
        .fileExporter(
            isPresented: $isShowingOPMLExporter,
            item: pendingExport,
            contentTypes: [.opml],
            defaultFilename: "grindstone-rss-library",
            onCompletion: { result in
                exportOPML(result)
            },
            onCancellation: {
                pendingExport = nil
            }
        )
    }

    // MARK: Sections

    private var composerSection: some View {
        Section {
            Group {
                TextField("https://example.com/feed.xml", text: $draftURL)
                    .autocorrectionDisabled()
#if os(iOS)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
#endif
                    .onSubmit(addFeed)

                TextField("Name (optional)", text: $draftTitle)
                    .onSubmit(addFeed)

                if let composerErrorMessage {
                    Text(composerErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button("Add Feed", systemImage: "plus.circle.fill", action: addFeed)
                    .disabled(draftURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .raisedFormRow()
        } header: {
            SettingsHeader("Add a Feed")
        } footer: {
            SettingsFooter("Paste an RSS or Atom link. Leave the name blank to use the site's domain.")
        }
    }

    private var feedsSection: some View {
        Section {
            if rssStore.feeds.isEmpty {
                Text("No feeds yet. Add one above, or import an OPML file below.")
                    .foregroundStyle(Theme.inkMuted)
                    .raisedFormRow()
            } else {
                ForEach(rssStore.feeds) { feed in
                    Toggle(isOn: enabledBinding(for: feed)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feed.title)
                                .foregroundStyle(Theme.ink)
                            Text(feed.displayHost)
                                .font(.caption)
                                .foregroundStyle(Theme.inkMuted)
                        }
                    }
                    .raisedFormRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            rssStore.removeFeed(id: feed.id)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button("Copy Feed Link", systemImage: "link") {
                            if let url = feed.url {
                                Pasteboard.copy(url)
                            }
                        }
                        Button("Remove Feed", systemImage: "trash", role: .destructive) {
                            rssStore.removeFeed(id: feed.id)
                        }
                    }
                }
            }
        } header: {
            HStack {
                SettingsHeader("Your Feeds")
                Spacer()
                if !rssStore.feeds.isEmpty {
                    SettingsHeader("\(rssStore.enabledFeeds.count) of \(rssStore.feeds.count) on")
                }
            }
        }
    }

    private var backupSection: some View {
        Section {
            Group {
                Button("Import OPML…", systemImage: "square.and.arrow.down") {
                    transferStatus = nil
                    isShowingOPMLImporter = true
                }

                Button("Export OPML…", systemImage: "square.and.arrow.up", action: prepareOPMLExport)
                    .disabled(rssStore.feeds.isEmpty)

                if let transferStatus {
                    Text(transferStatus.message)
                        .font(.footnote)
                        .foregroundStyle(transferStatus.tone.color)
                }
            }
            .raisedFormRow()
        } header: {
            SettingsHeader("Backup")
        } footer: {
            SettingsFooter("OPML is the standard format for moving a feed list between readers.")
        }
    }

    // MARK: Actions

    private func enabledBinding(for feed: ManualRSSFeed) -> Binding<Bool> {
        Binding(
            get: { feed.isEnabled },
            set: { rssStore.setEnabled($0, for: feed.id) }
        )
    }

    private func addFeed() {
        do {
            _ = try rssStore.addFeed(title: draftTitle, urlString: draftURL)
            draftTitle = ""
            draftURL = ""
            composerErrorMessage = nil
        } catch {
            composerErrorMessage = error.localizedDescription
        }
    }

    private func prepareOPMLExport() {
        transferStatus = nil
        pendingExport = RSSOPMLExport(text: rssStore.exportOPMLString())
        isShowingOPMLExporter = true
    }

    private func importOPML(_ result: Result<URL, Error>) {
        do {
            let fileURL = try result.get()
            let data = try readSecurityScopedData(from: fileURL)
            let importResult = try rssStore.importOPML(data: data)
            transferStatus = RSSLibraryTransferStatus(message: importResult.summary, tone: .success)
        } catch {
            transferStatus = RSSLibraryTransferStatus(message: error.localizedDescription, tone: .error)
        }
    }

    private func exportOPML(_ result: Result<URL, Error>) {
        defer { pendingExport = nil }

        do {
            let fileURL = try result.get()
            transferStatus = RSSLibraryTransferStatus(
                message: "Exported to \(fileURL.lastPathComponent).",
                tone: .success
            )
        } catch {
            transferStatus = RSSLibraryTransferStatus(message: error.localizedDescription, tone: .error)
        }
    }

    private func readSecurityScopedData(from fileURL: URL) throws -> Data {
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        return try Data(contentsOf: fileURL)
    }
}

/// Modal wrapper used from the feed's Options menu.
struct RSSFeedManagerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            RSSFeedManagerView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
#if os(macOS)
        .frame(minWidth: 480, minHeight: 540)
#endif
    }
}

private struct RSSLibraryTransferStatus {
    let message: String
    let tone: RSSLibraryTransferTone
}

private enum RSSLibraryTransferTone {
    case success
    case error

    var color: Color {
        switch self {
        case .success:
            return Theme.inkMuted
        case .error:
            return .red
        }
    }
}

#Preview {
    NavigationStack {
        RSSFeedManagerView()
    }
    .previewEnvironment()
}
