import Foundation
import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable

enum RSSOPMLError: LocalizedError {
    case invalidDocument
    case noFeeds
    case noImportableFeeds

    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            return "That file is not a valid OPML document."
        case .noFeeds:
            return "No RSS feeds were found in that OPML file."
        case .noImportableFeeds:
            return "That OPML file did not contain any new importable feeds."
        }
    }
}

struct RSSOPMLImportedFeed: Sendable {
    let title: String?
    let urlString: String
    let isEnabled: Bool
}

enum RSSOPMLCodec {
    static func export(feeds: [ManualRSSFeed]) -> String {
        let createdAt = ISO8601DateFormatter().string(from: Date())
        let outlines = feeds.map { feed in
            let title = xmlEscaped(feed.title)
            let url = xmlEscaped(feed.urlString)
            return """
                <outline text="\(title)" title="\(title)" type="rss" xmlUrl="\(url)" grindstoneEnabled="\(feed.isEnabled)" />
            """
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head>
            <title>Grindstone RSS Library</title>
            <dateCreated>\(createdAt)</dateCreated>
          </head>
          <body>
        \(outlines.indented(by: 4))
          </body>
        </opml>
        """
    }

    static func importFeeds(from data: Data) throws -> [RSSOPMLImportedFeed] {
        let parser = RSSOPMLParser()
        let feeds = try parser.parse(data: data)
        guard !feeds.isEmpty else {
            throw RSSOPMLError.noFeeds
        }
        return feeds
    }

    private static func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// An OPML export handed to `fileExporter` (and usable with `ShareLink`).
/// Uses `Transferable` rather than `FileDocument`, which the 27 SDKs deprecate.
struct RSSOPMLExport: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .opml) { export in
            Data(export.text.utf8)
        }
    }
}

extension UTType {
    static var opml: UTType {
        UTType(filenameExtension: "opml") ?? UTType(exportedAs: "org.opml.opml")
    }
}

private final class RSSOPMLParser: NSObject, XMLParserDelegate {
    private var feeds: [RSSOPMLImportedFeed] = []
    private var parseError: Error?

    func parse(data: Data) throws -> [RSSOPMLImportedFeed] {
        let parser = XMLParser(data: data)
        parser.delegate = self

        guard parser.parse(), parseError == nil else {
            throw parseError ?? parser.parserError ?? RSSOPMLError.invalidDocument
        }

        return feeds
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "outline" else { return }

        guard let xmlURL = attributeDict["xmlUrl"] ?? attributeDict["xmlurl"] else { return }

        let title = attributeDict["title"]?
            .decodingHTMLEntities()
            .condensedWhitespace()
            .nonEmpty
            ?? attributeDict["text"]?
                .decodingHTMLEntities()
                .condensedWhitespace()
                .nonEmpty

        feeds.append(
            RSSOPMLImportedFeed(
                title: title,
                urlString: xmlURL.decodingHTMLEntities().condensedWhitespace(),
                isEnabled: Self.parseEnabledFlag(from: attributeDict)
            )
        )
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }

    private static func parseEnabledFlag(from attributes: [String: String]) -> Bool {
        guard let rawValue = attributes["grindstoneEnabled"] ?? attributes["enabled"] else {
            return true
        }

        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "false", "0", "no":
            return false
        default:
            return true
        }
    }
}

private extension String {
    func indented(by spaces: Int) -> String {
        let prefix = String(repeating: " ", count: spaces)
        return split(separator: "\n", omittingEmptySubsequences: false)
            .map { prefix + $0 }
            .joined(separator: "\n")
    }

    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
