import Foundation

extension Int {
    /// "342", "1.2K", "15K" – keeps point and comment counts to a few characters.
    var compactFormatted: String {
        guard self >= 1000 else { return String(self) }
        return formatted(.number.notation(.compactName))
    }
}
