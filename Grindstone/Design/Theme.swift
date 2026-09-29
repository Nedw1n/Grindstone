import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Stone & Paper, the app's visual language. It comes straight from the icon:
/// three granite stones balanced on warm paper. Surfaces are paper, text is
/// ink, and the only color beyond the stones is a muted moss accent and a
/// mineral tint per source. Every color lives in the asset catalog with a
/// light and a dark variant.
enum Theme {
    // MARK: Surfaces

    /// The page behind everything.
    static let paper = Color("Paper")
    /// Cards, banners, form rows, and the selected filter chip.
    static let paperRaised = Color("PaperRaised")
    static let hairline = Color("Hairline")

    // MARK: Text

    static let ink = Color("Ink")
    static let inkMuted = Color("InkMuted")

    // MARK: Accents

    // The moss accent itself is the asset catalog's AccentColor, so it reaches
    // toggles, links, and the tab bar as the system tint.

    /// Moss that stays deep in both appearances, for fills under white text
    /// such as swipe actions. The dark-mode accent is too light for that.
    static let mossDeep = Color(red: 0.302, green: 0.416, blue: 0.231)
    /// Warnings, such as a source that failed to refresh.
    static let ochre = Color("Ochre")

    /// A warm brown for soft shadows, so stones rest on the paper rather than
    /// float above it.
    static let shadow = Color(red: 0.20, green: 0.15, blue: 0.09)

    /// Text on the mid and dark stones, which stay dark in both appearances.
    static let onStone = Color(red: 0.969, green: 0.957, blue: 0.933)

    /// Strength of the granite grain on stone surfaces.
    static let stoneGrainOpacity = 0.3

    /// The widest a column of stories gets on iPad and Mac.
    static let readableWidth: CGFloat = 720
    /// The widest a settings form gets on iPad and Mac.
    static let formWidth: CGFloat = 640
}

extension EdgeInsets {
    /// Margins for a story row, shared by every list of stories.
    static let storyRow = EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
    /// Margins for a section label that heads a list of stories.
    static let sectionEyebrow = EdgeInsets(top: 22, leading: 20, bottom: 6, trailing: 20)
}

extension View {
    /// Small tracked capitals, like lettering cut into stone. Used for source
    /// names and section labels.
    func eyebrowStyle() -> some View {
        font(.caption2.weight(.semibold))
            .tracking(1)
            .textCase(.uppercase)
    }

    /// Paper behind a list, form, or empty state. visionOS keeps its system glass.
    func paperBackground() -> some View {
        modifier(PaperBackground())
    }

    /// A list row that sits directly on the paper, divided by hairlines.
    func paperListRow() -> some View {
        modifier(PaperListRow())
    }

    /// A form row on a raised paper card.
    func raisedFormRow() -> some View {
        modifier(RaisedFormRow())
    }

    /// Caps a list or form at `maxWidth` and centers it, with paper on either
    /// side. iPhone screens are narrower than the cap, so nothing changes there.
    func readableMeasure(_ maxWidth: CGFloat = Theme.readableWidth) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

/// Where the app may use layouts of its own for large screens.
enum LayoutPlatform {
    /// iPad, Mac, and Vision Pro. iPhone keeps its layout at every width,
    /// including a large iPhone in landscape.
    static var allowsWideLayouts: Bool {
#if os(iOS)
        return UIDevice.current.userInterfaceIdiom != .phone
#else
        return true
#endif
    }
}

private struct PaperBackground: ViewModifier {
    func body(content: Content) -> some View {
#if os(visionOS)
        content
#else
        content
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
#endif
    }
}

private struct PaperListRow: ViewModifier {
    func body(content: Content) -> some View {
#if os(visionOS)
        content
#else
        content
            .listRowBackground(Theme.paper)
            .listRowSeparatorTint(Theme.hairline)
#endif
    }
}

private struct RaisedFormRow: ViewModifier {
    func body(content: Content) -> some View {
#if os(visionOS)
        content
#else
        content
            .listRowBackground(Theme.paperRaised)
            .listRowSeparatorTint(Theme.hairline)
#endif
    }
}

/// The primary button: an ink pebble with paper-colored text. It inverts
/// cleanly in dark mode, unlike white text on a tint.
struct PebbleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.paper)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Theme.ink, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PebbleButtonStyle {
    static var pebble: PebbleButtonStyle { PebbleButtonStyle() }
}
