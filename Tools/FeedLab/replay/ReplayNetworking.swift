import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Stands in for Utilities/FeedNetworking.swift. Every request the app's
// services make is answered from the current snapshot's saved responses, so
// the real services, merging, and ranking run over what the sources looked
// like at that moment. A request with no saved response gets a 404, which the
// app treats like any failed source.

enum Replay {
    static var directory = URL(fileURLWithPath: ".")
    static var files: [String: String] = [:]
    static var missing: [String] = []

    static func load(directory: URL, files: [String: String]) {
        self.directory = directory
        self.files = files
        missing = []
    }

    /// Must match the keys `collect.py` writes.
    static func key(for url: URL) -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let host = components?.host ?? ""
        switch host {
        case "api.biorxiv.org":
            // /details/biorxiv/<start>/<end>/<cursor>/json: the dates follow the
            // real clock, so only the category and page identify a response.
            let category = components?.queryItems?.first { $0.name == "category" }?.value ?? ""
            let parts = (components?.path ?? "").split(separator: "/")
            let cursor = parts.count >= 5 ? String(parts[4]) : "0"
            return "biorxiv/\(category)/\(cursor)"
        case "export.arxiv.org":
            return "arxiv"
        default:
            return host + (components?.path ?? "")
        }
    }

    static func respond(to url: URL) throws -> (Data, URLResponse) {
        let key = key(for: url)
        guard let name = files[key],
              let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else {
            missing.append(key)
            return (Data(), HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }
        return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

/// The moment being replayed. The ranking engine reads its clock from here
/// (prep.sh points its `Date()` calls at it), so recency is scored as it would
/// have been then.
enum ReplayClock {
    static var now = Date()
}

enum FeedNetworking {
    nonisolated static let requestTimeout: TimeInterval = 12
    nonisolated static let sourceTimeout: TimeInterval = 15

    static func data(from url: URL) async throws -> (Data, URLResponse) {
        try Replay.respond(to: url)
    }

    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try Replay.respond(to: request.url!)
    }
}

enum FeedRequestTimeout {
    nonisolated static func run<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await operation()
    }
}
