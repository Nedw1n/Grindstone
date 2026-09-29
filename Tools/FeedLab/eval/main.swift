import Foundation

// Replays each collected snapshot through the app's real refresh (services,
// cross-posting, ranking) and reports how the merged feed came out.
//
//   run <data-dir> <report.md>
//
// Also writes <report.md>.json with the headline numbers, for comparing a
// change to the ranking against the same snapshots.

struct SnapshotInfo: Decodable {
    let id: String
    let time: String
    let notes: [String]
    let files: [String: String]
    let analysis: [String: BioRxivAnalysis]?
}

struct BioRxivAnalysis: Decodable {
    let total: Int
    let first_page_dates: [String]
    let all_dates: [String]
}

struct Summary: Codable {
    var snapshot: String
    var top10BySource: [String: Int]
    var top20BySource: [String: Int]
    var firstPositionBySource: [String: Int]
    var crossPostedStories: Int
    var crossPostedInTop10: Int
    var editorialTau: [String: Double]
    var medianAgeTop10Hours: Double
    var over24hInTop20: Int
    var featuredSources: [String]
    var top10Keys: [String]
    var frontPageCount: Int
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("usage: run <data-dir> <report.md>")
    exit(2)
}
let dataDirectory = URL(fileURLWithPath: arguments[1])
let reportURL = URL(fileURLWithPath: arguments[2])

let isoFormatter = ISO8601DateFormatter()
isoFormatter.formatOptions = [.withInternetDateTime]

let snapshotDirectories = (try FileManager.default.contentsOfDirectory(
    at: dataDirectory, includingPropertiesForKeys: nil
))
.filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("snapshot.json").path) }
.sorted { $0.lastPathComponent < $1.lastPathComponent }

guard !snapshotDirectories.isEmpty else {
    print("no snapshots in \(dataDirectory.path)")
    exit(2)
}

let cacheURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    .appendingPathComponent("Grindstone/feed-cache.json")

var report = "# Feed replay\n\n"
var summaries: [Summary] = []
var allGroups: [String: String] = [:]
var allNearMisses: [String: String] = [:]

func hours(_ interval: TimeInterval) -> Double { interval / 3600 }
func format(_ value: Double) -> String { String(format: "%.1f", value) }
func short(_ text: String, _ length: Int = 90) -> String {
    text.count > length ? String(text.prefix(length - 1)) + "…" : text
}
func label(_ source: Source) -> String { source.shortName }

for directory in snapshotDirectories {
    let info = try JSONDecoder().decode(
        SnapshotInfo.self, from: Data(contentsOf: directory.appendingPathComponent("snapshot.json"))
    )
    guard let moment = isoFormatter.date(from: info.time) else {
        print("skipping \(info.id): bad time \(info.time)")
        continue
    }

    Replay.load(directory: directory, files: info.files)
    ReplayClock.now = moment
    try? FileManager.default.removeItem(at: cacheURL)

    let suite = "feedlab.replay"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let viewModel = FeedViewModel(
        rssStore: ManualRSSFeedStore(defaults: defaults),
        preferences: FeedPreferences(defaults: defaults)
    )
    await viewModel.refresh()

    var lanes: [Source: [FeedItem]] = [:]
    for source in Source.allCases {
        viewModel.filter = source
        lanes[source] = viewModel.filtered
    }
    viewModel.filter = nil

    let front = viewModel.items
    let featured = viewModel.featured

    report += "## \(info.id)  (\(info.time))\n\n"
    report += info.notes.map { "- \($0)" }.joined(separator: "\n") + "\n"
    if !viewModel.failures.isEmpty {
        report += viewModel.failures.map { "- **Failed:** \($0.source.rawValue): \($0.message)" }
            .joined(separator: "\n") + "\n"
    }
    if !Replay.missing.isEmpty {
        report += "- Requests with no saved response: \(Set(Replay.missing).sorted().joined(separator: ", "))\n"
    }
    report += "- Lanes: " + Source.allCases.map { "\(label($0)) \(lanes[$0]?.count ?? 0)" }.joined(separator: ", ")
        + "; front page \(front.count)\n\n"

    // Front page.
    report += "| # | Src | Also | Age h | Place | Score | Title | Outlet |\n|---|---|---|---|---|---|---|---|\n"
    for (index, item) in front.prefix(25).enumerated() {
        let age = hours(moment.timeIntervalSince(item.publishedAt))
        report += "| \(index + 1) | \(label(item.source)) | \(item.orderedCrossRefs.map(label).joined(separator: ",")) "
            + "| \(format(age)) | \(String(format: "%.2f", FeedRankingEngine.placementSignal(for: item))) "
            + "| \(String(format: "%.3f", FeedRankingEngine.score(for: item, now: moment))) "
            + "| \(short(item.title).replacingOccurrences(of: "|", with: "/")) | \(item.displayOutlet ?? "") |\n"
    }
    report += "\n"

    // Composition.
    func counts(_ items: ArraySlice<FeedItem>) -> [String: Int] {
        Dictionary(grouping: items, by: { label($0.source) }).mapValues(\.count)
    }
    let top10 = counts(front.prefix(10))
    let top20 = counts(front.prefix(20))
    var firstPosition: [String: Int] = [:]
    for source in Source.allCases {
        if let index = front.firstIndex(where: { $0.source == source }) {
            firstPosition[label(source)] = index + 1
        }
    }
    report += "- Top 10 by source: \(top10.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))\n"
    report += "- Top 20 by source: \(top20.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))\n"
    report += "- First position: \(firstPosition.sorted { $0.value < $1.value }.map { "\($0.key) #\($0.value)" }.joined(separator: ", "))\n"

    // Editorial order: does the merged page keep each ranked source's order?
    var tau: [String: Double] = [:]
    for source in Source.allCases where source.hasEditorialOrder {
        let led = front.enumerated().filter { $0.element.source == source }
        var concordant = 0, discordant = 0
        for i in led.indices {
            for j in led.indices where j > i {
                let a = led[i], b = led[j]
                if a.element.intraSourceRank == b.element.intraSourceRank { continue }
                if (a.element.intraSourceRank > b.element.intraSourceRank) == (a.offset < b.offset) {
                    concordant += 1
                } else {
                    discordant += 1
                }
            }
        }
        if concordant + discordant > 0 {
            tau[label(source)] = Double(concordant - discordant) / Double(concordant + discordant)
        }
    }
    report += "- Editorial order kept (Kendall τ, 1 = same order): \(tau.sorted { $0.key < $1.key }.map { "\($0.key) \(String(format: "%.2f", $0.value))" }.joined(separator: ", "))\n"

    // Freshness.
    let topAges = front.prefix(10).map { hours(moment.timeIntervalSince($0.publishedAt)) }.sorted()
    let medianAge = topAges.isEmpty ? 0 : topAges[topAges.count / 2]
    let stale = front.prefix(20).filter { moment.timeIntervalSince($0.publishedAt) > 24 * 3600 }.count
    report += "- Median age of top 10: \(format(medianAge)) h; top 20 older than a day: \(stale)\n"

    // Top of the Stack.
    report += "- Top of the Stack: " + featured.map { "[\(label($0.source))\($0.crossRefs.isEmpty ? "" : "+" + $0.orderedCrossRefs.map(label).joined(separator: "+"))] \(short($0.title, 60))" }.joined(separator: " · ") + "\n"

    // Lane health.
    for source in [Source.biotech, .rss] {
        let lane = lanes[source] ?? []
        guard !lane.isEmpty else { continue }
        let ages = lane.map { hours(moment.timeIntervalSince($0.publishedAt)) }
        let outlets = Dictionary(grouping: lane, by: { $0.displayOutlet ?? "?" }).mapValues(\.count)
        report += "- \(source.rawValue) lane: \(lane.count) stories, newest \(format(ages.min() ?? 0)) h, oldest \(format(ages.max() ?? 0)) h; "
            + outlets.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ") + "\n"
    }
    for (key, analysis) in (info.analysis ?? [:]).sorted(by: { $0.key < $1.key }) {
        report += "- \(key): \(analysis.total) in window; app's first page covers \(analysis.first_page_dates.first ?? "?")…\(analysis.first_page_dates.last ?? "?"), window runs to \(analysis.all_dates.last ?? "?")\n"
    }

    // Cross-posted stories, with every member, for checking by hand.
    let everything = Source.allCases.flatMap { lanes[$0] ?? [] }
    let merged = CrossRefEngine.mergeStories(everything)
    let membersByLead = Dictionary(grouping: everything, by: { merged.leadIDs[$0.id] ?? $0.id })
    let frontIDs = Set(front.map(\.id))
    var crossPosted = 0
    var crossPostedTop10 = 0
    let top10IDs = Set(front.prefix(10).map(\.id))
    report += "\n**Cross-posted stories**\n\n"
    for (leadID, members) in membersByLead.sorted(by: { $0.key < $1.key }) {
        let sources = Set(members.map(\.source))
        guard sources.count > 1 else { continue }
        crossPosted += 1
        if top10IDs.contains(leadID) { crossPostedTop10 += 1 }
        let line = members.map { "\(label($0.source)): \(short($0.title, 70)) <\($0.url.host ?? "")>" }.joined(separator: " ⟷ ")
        report += "- \(frontIDs.contains(leadID) ? "" : "(off front page) ")\(line)\n"
        allGroups[members.map(\.id).sorted().joined(separator: "|")] = line
    }

    // Near misses: similar headlines on different sources that were not merged.
    func words(_ title: String) -> Set<String> {
        Set(title.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).compactMap { word in
            guard word.count >= 3 else { return nil }
            return word.count > 4 && word.hasSuffix("s") ? String(word.dropLast()) : word
        })
    }
    let wordSets = everything.map { words($0.title) }
    var nearMisses: [(Double, String)] = []
    for i in everything.indices {
        for j in everything.indices where j > i {
            let a = everything[i], b = everything[j]
            guard a.source != b.source, merged.leadIDs[a.id] != merged.leadIDs[b.id] else { continue }
            let shared = wordSets[i].intersection(wordSets[j]).count
            guard shared >= 2 else { continue }
            let jaccard = Double(shared) / Double(wordSets[i].union(wordSets[j]).count)
            guard jaccard >= 0.2 else { continue }
            let line = "\(String(format: "%.2f", jaccard)) \(label(a.source)): \(short(a.title, 70)) ⟷ \(label(b.source)): \(short(b.title, 70))"
            nearMisses.append((jaccard, line))
            allNearMisses[[a.id, b.id].sorted().joined(separator: "|")] = line
        }
    }
    if !nearMisses.isEmpty {
        report += "\n**Similar headlines not merged**\n\n"
        report += nearMisses.sorted { $0.0 > $1.0 }.prefix(12).map { "- \($0.1)" }.joined(separator: "\n") + "\n"
    }
    report += "\n"

    summaries.append(Summary(
        snapshot: info.id,
        top10BySource: top10,
        top20BySource: top20,
        firstPositionBySource: firstPosition,
        crossPostedStories: crossPosted,
        crossPostedInTop10: crossPostedTop10,
        editorialTau: tau,
        medianAgeTop10Hours: medianAge,
        over24hInTop20: stale,
        featuredSources: featured.map { label($0.source) + ($0.crossRefs.isEmpty ? "" : "+") },
        top10Keys: front.prefix(10).map(\.normalizedURL),
        frontPageCount: front.count
    ))
    print("replayed \(info.id): front page \(front.count), cross-posted \(crossPosted), failures \(viewModel.failures.count)")
}

// Overview across snapshots.
var overview = "## Overview\n\n| Snapshot | Top 10 HN/Memo/Bio/RSS | Top 20 HN/Memo/Bio/RSS | First Bio | First RSS | Cross-posted (top 10) | τ HN | τ Memo | Median age top 10 | Stale in top 20 | Top-10 kept from previous |\n|---|---|---|---|---|---|---|---|---|---|---|\n"
var previous: Summary?
for summary in summaries {
    func split(_ counts: [String: Int]) -> String {
        Source.allCases.map { String(counts[label($0)] ?? 0) }.joined(separator: "/")
    }
    var kept = "–"
    if let previous, previous.snapshot.prefix(10) == summary.snapshot.prefix(10) {
        kept = String(Set(previous.top10Keys).intersection(summary.top10Keys).count)
    }
    overview += "| \(summary.snapshot) | \(split(summary.top10BySource)) | \(split(summary.top20BySource)) "
        + "| \(summary.firstPositionBySource["Bio"].map { "#\($0)" } ?? "–") | \(summary.firstPositionBySource["RSS"].map { "#\($0)" } ?? "–") "
        + "| \(summary.crossPostedStories) (\(summary.crossPostedInTop10)) "
        + "| \(summary.editorialTau["HN"].map { String(format: "%.2f", $0) } ?? "–") | \(summary.editorialTau["Memo"].map { String(format: "%.2f", $0) } ?? "–") "
        + "| \(format(summary.medianAgeTop10Hours)) | \(summary.over24hInTop20) | \(kept) |\n"
    previous = summary
}
overview += "\n**Every cross-posted story (for checking by hand)**\n\n" + allGroups.values.sorted().map { "- \($0)" }.joined(separator: "\n") + "\n"
overview += "\n**Every near miss**\n\n" + allNearMisses.values.sorted(by: >).map { "- \($0)" }.joined(separator: "\n") + "\n\n"

let fullReport = report.replacingOccurrences(of: "# Feed replay\n\n", with: "# Feed replay\n\n" + overview)
try fullReport.write(to: reportURL, atomically: true, encoding: .utf8)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(summaries).write(to: URL(fileURLWithPath: reportURL.path + ".json"))
print("wrote \(reportURL.path)")
