import Foundation

extension Date {
    /// Human-readable relative timestamp: "3m ago", "2h ago", "1d ago".
    var relativeFormatted: String {
        let now = Date()
        let interval = now.timeIntervalSince(self)

        guard interval > 0 else { return "now" }

        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)

        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m ago" }
        if hours < 24 { return "\(hours)h ago" }
        if days < 7 { return "\(days)d ago" }

        let formatter = DateFormatter()
        formatter.dateFormat = days < 365 ? "MMM d" : "MMM d, yyyy"
        return formatter.string(from: self)
    }
}
