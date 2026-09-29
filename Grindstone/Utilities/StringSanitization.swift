import Foundation

extension String {
    func condensedWhitespace() -> String {
        replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func strippingHTML() -> String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    /// Whether `word` (or a phrase) appears as whole words, ignoring case, with
    /// an optional plural "s": "gene" matches "genes" but not "generative".
    func containsWord(_ word: String) -> Bool {
        let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: word) + #"s?\b"#
        return range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    func decodingHTMLEntities() -> String {
        var decoded = self
        let namedEntities: [String: String] = [
            "&amp;": "&",
            "&quot;": "\"",
            "&apos;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&nbsp;": " ",
            "&hellip;": "...",
            "&mdash;": "-",
            "&ndash;": "-",
            "&ldquo;": "\"",
            "&rdquo;": "\"",
            "&lsquo;": "'",
            "&rsquo;": "'",
        ]

        for (entity, replacement) in namedEntities {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }

        guard let regex = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#) else {
            return decoded
        }

        let matches = regex.matches(in: decoded, range: NSRange(decoded.startIndex..., in: decoded))
        guard !matches.isEmpty else { return decoded }

        var output = decoded
        for match in matches.reversed() {
            guard
                match.numberOfRanges > 1,
                let tokenRange = Range(match.range(at: 1), in: output),
                let fullRange = Range(match.range(at: 0), in: output)
            else {
                continue
            }

            let token = String(output[tokenRange])
            let value: UInt32?

            if token.hasPrefix("x") || token.hasPrefix("X") {
                value = UInt32(token.dropFirst(), radix: 16)
            } else {
                value = UInt32(token, radix: 10)
            }

            guard let value, let scalar = UnicodeScalar(value) else { continue }
            output.replaceSubrange(fullRange, with: String(Character(scalar)))
        }

        return output
    }
}
