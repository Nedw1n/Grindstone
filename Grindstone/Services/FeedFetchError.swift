import Foundation

enum FeedFetchError: LocalizedError {
    case badStatus(source: String, statusCode: Int)
    case emptyResponse(source: String)

    var errorDescription: String? {
        switch self {
        case let .badStatus(source, statusCode):
            return "\(source) returned HTTP \(statusCode)."
        case let .emptyResponse(source):
            return "\(source) returned no items."
        }
    }
}
