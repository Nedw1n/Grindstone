import Foundation
import Combine

/// Where a story was when someone acted on it.
enum StorySurface: String, Codable, Sendable {
    /// Top of the Stack, in the list on iPhone or the rail on iPad and Mac.
    case stack
    /// The story list on Today.
    case feed
    case saved
    case search
}

/// A story's place on screen: the surface, and its position there (0 is first).
struct StoryPlacement: Equatable, Sendable {
    let surface: StorySurface
    let position: Int?
}

/// One thing that happened to one story.
struct EngagementEvent: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// The story came on screen (once per story per visit).
        case impression
        case open
        case openDiscussion
        /// The in-app reader closed; `readingSeconds` says how long it was open.
        case closeReader
        case save
        case unsave
        /// Marked read without being opened: a skip.
        case markRead
        case markUnread
        /// Swept up by Mark All as Read while still unread.
        case markAllRead
        case copyLink
    }

    let kind: Kind
    let at: Date
    let itemID: String
    let title: String
    let source: Source
    let host: String?
    let outlet: String?
    let crossRefs: [Source]
    let points: Int?
    let commentCount: Int?
    /// The story's age when this happened.
    let storyAgeMinutes: Int
    /// The front-page score it had at the time, for comparing against later rankings.
    let rankScore: Double
    let surface: StorySurface?
    let position: Int?
    /// Whether the story was in the "new since your last visit" section.
    let wasNew: Bool?
    let readingSeconds: Int?
}

/// A private, on-device record of how stories are read: what comes on screen,
/// what gets opened and for how long, and what gets saved or skipped. It
/// exists so personalized ranking can be tried later against real history.
/// Nothing here affects ranking yet, and nothing leaves the device.
///
/// Events are appended to a JSON Lines file in Application Support and
/// written in small batches.
@MainActor
final class EngagementLog: ObservableObject {
    static let shared = EngagementLog()

    @Published private(set) var eventCount: Int

    private let fileURL: URL?
    private var pending: [EngagementEvent] = []
    private var impressionsThisVisit: Set<String> = []
    private var flushTask: Task<Void, Never>?

    /// Past this size, the oldest half of the log is dropped.
    private let maxFileBytes = 8 * 1024 * 1024

    init(fileURL: URL? = EngagementLog.defaultFileURL) {
        self.fileURL = fileURL
        eventCount = Self.countLines(at: fileURL)
    }

    // MARK: Recording

    func record(
        _ kind: EngagementEvent.Kind,
        _ item: FeedItem,
        placement: StoryPlacement? = nil,
        readingSeconds: Int? = nil
    ) {
        let now = Date()
        let event = EngagementEvent(
            kind: kind,
            at: now,
            itemID: item.id,
            title: item.title,
            source: item.source,
            host: item.displayHost,
            outlet: item.outlet,
            crossRefs: item.orderedCrossRefs,
            points: item.points,
            commentCount: item.commentCount,
            storyAgeMinutes: max(0, Int(now.timeIntervalSince(item.publishedAt) / 60)),
            rankScore: FeedRankingEngine.score(for: item, now: now),
            surface: placement?.surface,
            position: placement?.position,
            wasNew: ReadingSessionStore.shared.isNew(item),
            readingSeconds: readingSeconds
        )

        pending.append(event)
        eventCount += 1
        scheduleFlush()
    }

    /// Records that a story came on screen, once per story per visit.
    func recordImpression(_ item: FeedItem, placement: StoryPlacement?) {
        guard impressionsThisVisit.insert(item.id).inserted else { return }
        record(.impression, item, placement: placement)
    }

    /// Records a bulk Mark All as Read, for the stories that were still unread.
    func recordMarkAllRead(_ items: [FeedItem], userState: FeedUserStateStore) {
        for item in items where !userState.isRead(item) {
            record(.markAllRead, item)
        }
    }

    /// A new visit may show the same stories again, and that counts.
    func beginVisit() {
        impressionsThisVisit.removeAll()
    }

    // MARK: Storage

    /// Writes pending events now. Called when the app leaves the foreground.
    func flush() {
        flushTask?.cancel()
        flushTask = nil
        guard !pending.isEmpty, let fileURL else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = Data()
        for event in pending {
            guard let line = try? encoder.encode(event) else { continue }
            data.append(line)
            data.append(0x0A)
        }
        pending.removeAll()

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                _ = try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: fileURL, options: .atomic)
            }
            trimIfNeeded(fileURL)
        } catch {
            // Losing a batch of signals is harmless; the feed never depends on them.
        }
    }

    /// Deletes every recorded event.
    func clear() {
        flushTask?.cancel()
        flushTask = nil
        pending.removeAll()
        impressionsThisVisit.removeAll()
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        eventCount = 0
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    private func trimIfNeeded(_ fileURL: URL) {
        guard
            let data = try? Data(contentsOf: fileURL),
            data.count > maxFileBytes,
            let cut = data[(data.count / 2)...].firstIndex(of: 0x0A)
        else { return }

        let kept = data[(cut + 1)...]
        try? Data(kept).write(to: fileURL, options: .atomic)
        eventCount = kept.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
    }

    private static func countLines(at fileURL: URL?) -> Int {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return 0 }
        return data.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
    }

    nonisolated static var defaultFileURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Grindstone", isDirectory: true)
            .appendingPathComponent("engagement.jsonl")
    }
}

private extension FeedItem {
    /// The article's site without `www.`, e.g. "github.com".
    var displayHost: String? {
        guard let host = url.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
