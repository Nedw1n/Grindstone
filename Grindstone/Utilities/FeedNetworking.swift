import Foundation

enum FeedNetworking {
    nonisolated static let requestTimeout: TimeInterval = 12
    nonisolated static let sourceTimeout: TimeInterval = 15

    nonisolated private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = sourceTimeout
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    nonisolated static func data(from url: URL) async throws -> (Data, URLResponse) {
        try await session.data(from: url)
    }

    nonisolated static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        var request = request
        request.timeoutInterval = request.timeoutInterval > 0
            ? min(request.timeoutInterval, requestTimeout)
            : requestTimeout
        return try await session.data(for: request)
    }
}

enum FeedRequestTimeout {
    nonisolated static func run<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(FeedNetworking.sourceTimeout * 1_000_000_000))
                throw URLError(.timedOut)
            }

            defer { group.cancelAll() }

            guard let result = try await group.next() else {
                throw URLError(.unknown)
            }

            return result
        }
    }
}
