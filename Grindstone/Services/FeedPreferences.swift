import Foundation
import Combine

/// User-facing reading preferences. Persisted to `UserDefaults` on every change
/// so the app opens exactly the way it was left.
@MainActor
final class FeedPreferences: ObservableObject {
    static let shared = FeedPreferences()

    /// Built-in sources that should be fetched and shown. RSS is not tracked here
    /// because it is curated feed by feed in the RSS library.
    @Published var enabledSources: Set<Source> {
        didSet { persistEnabledSources() }
    }

    @Published var showPreviews: Bool {
        didSet { defaults.set(showPreviews, forKey: Keys.showPreviews) }
    }

    @Published var hideReadItems: Bool {
        didSet { defaults.set(hideReadItems, forKey: Keys.hideReadItems) }
    }

    /// `true` opens stories inside the app (Safari view on iOS, web view on macOS).
    /// `false` hands them to the system browser.
    @Published var opensLinksInApp: Bool {
        didSet { defaults.set(opensLinksInApp, forKey: Keys.opensLinksInApp) }
    }

    /// Ask the in-app Safari view to enter Reader mode when the page supports it.
    @Published var prefersReaderMode: Bool {
        didSet { defaults.set(prefersReaderMode, forKey: Keys.prefersReaderMode) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let enabledSources = "prefs.enabledSources"
        // Kept from the previous version so an existing preference survives the upgrade.
        static let showPreviews = "showPreviews"
        static let hideReadItems = "prefs.hideReadItems"
        static let opensLinksInApp = "prefs.opensLinksInApp"
        static let prefersReaderMode = "prefs.prefersReaderMode"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let stored = defaults.stringArray(forKey: Keys.enabledSources) {
            enabledSources = Set(stored.compactMap(Source.init(rawValue:)))
        } else {
            enabledSources = Set(Source.builtInSources)
        }

        showPreviews = defaults.object(forKey: Keys.showPreviews) as? Bool ?? true
        hideReadItems = defaults.object(forKey: Keys.hideReadItems) as? Bool ?? false
        opensLinksInApp = defaults.object(forKey: Keys.opensLinksInApp) as? Bool ?? true
        prefersReaderMode = defaults.object(forKey: Keys.prefersReaderMode) as? Bool ?? true
    }

    func isEnabled(_ source: Source) -> Bool {
        source == .rss || enabledSources.contains(source)
    }

    func setEnabled(_ isEnabled: Bool, for source: Source) {
        guard source != .rss else { return }
        if isEnabled {
            enabledSources.insert(source)
        } else {
            enabledSources.remove(source)
        }
    }

    /// Every source that should appear in filters and the feed, in canonical order.
    var visibleSources: [Source] {
        Source.allCases.filter(isEnabled)
    }

    private func persistEnabledSources() {
        let stored = Source.allCases
            .filter { enabledSources.contains($0) }
            .map(\.rawValue)
        defaults.set(stored, forKey: Keys.enabledSources)
    }
}
