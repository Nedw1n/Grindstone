import SwiftUI

/// The three stones of the icon, from the light capstone to the dark base.
enum StoneTone: CaseIterable {
    case light
    case mid
    case dark

    /// Tones for a stack of `count` stones, top to bottom. The base is always
    /// the dark stone, so a short stack still keeps its weight at the bottom.
    static func stack(count: Int) -> [StoneTone] {
        Array(allCases.suffix(max(0, count)))
    }

    var fill: Color {
        switch self {
        case .light:
            return Color("StoneLight")
        case .mid:
            return Color("StoneMid")
        case .dark:
            return Color("StoneDark")
        }
    }

    var primaryText: Color {
        self == .light ? Color("StoneLightInk") : Theme.onStone
    }

    var secondaryText: Color {
        primaryText.opacity(0.85)
    }

    /// The mid and dark stones are dark surfaces in either appearance, so marks
    /// drawn on them (source dots, the accent) take their dark-mode variants.
    var isDarkSurface: Bool {
        self != .light
    }

    /// Each stone below is thicker than the one it carries, as in the icon.
    var heightFactor: CGFloat {
        switch self {
        case .light:
            return 1
        case .mid:
            return 1.2
        case .dark:
            return 1.45
        }
    }

    /// Slightly uneven corners, so each card reads as a pebble rather than a panel.
    var cornerRadii: RectangleCornerRadii {
        switch self {
        case .light:
            return RectangleCornerRadii(topLeading: 30, bottomLeading: 26, bottomTrailing: 32, topTrailing: 24)
        case .mid:
            return RectangleCornerRadii(topLeading: 28, bottomLeading: 30, bottomTrailing: 26, topTrailing: 34)
        case .dark:
            return RectangleCornerRadii(topLeading: 34, bottomLeading: 32, bottomTrailing: 38, topTrailing: 30)
        }
    }

    /// Mirrors the grain per stone so neighboring stones never share a pattern.
    fileprivate var grainScale: CGSize {
        switch self {
        case .light:
            return CGSize(width: 1, height: 1)
        case .mid:
            return CGSize(width: -1, height: 1)
        case .dark:
            return CGSize(width: 1, height: -1)
        }
    }
}

/// The granite grain from the icon's bottom stone, as a seamless tile.
struct GrainTexture: View {
    var body: some View {
        Image(decorative: "StoneGrain")
            .resizable(resizingMode: .tile)
            .allowsHitTesting(false)
    }
}

/// A stone's face: its tone, the icon's grain, soft light from above, a darker
/// rim toward the base, and a contact shadow on the paper.
struct StoneSurface: View {
    let tone: StoneTone

    var body: some View {
        let shape = UnevenRoundedRectangle(cornerRadii: tone.cornerRadii, style: .continuous)

        shape
            .fill(tone.fill)
            .overlay { StoneGrain(tone: tone) }
            .overlay { StoneLighting() }
            .clipShape(shape)
            .compositingGroup()
            .shadow(color: Theme.shadow.opacity(0.28), radius: 10, x: 0, y: 7)
            .accessibilityHidden(true)
    }
}

private struct StoneGrain: View {
    let tone: StoneTone

    var body: some View {
        GrainTexture()
            .scaleEffect(tone.grainScale)
            .opacity(Theme.stoneGrainOpacity)
            .blendMode(.hardLight)
    }
}

private struct StoneLighting: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.10), location: 0),
                .init(color: .clear, location: 0.35),
                .init(color: .clear, location: 0.7),
                .init(color: .black.opacity(0.14), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// The icon's cairn, drawn: three grained stones, lightest on top. Used for
/// empty and loading states and the Settings header. With `isBalancing`, the
/// upper stones lift and settle slowly while stories load.
struct CairnMark: View {
    var width: CGFloat = 88
    var isBalancing = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isLifted = false

    var body: some View {
        VStack(spacing: -width * 0.03) {
            stone(.light, widthRatio: 0.62, heightRatio: 0.23)
                .rotationEffect(.degrees(-6))
                .offset(x: width * 0.03, y: lift(2))
                .zIndex(3)

            stone(.mid, widthRatio: 0.84, heightRatio: 0.26)
                .offset(y: lift(1))
                .zIndex(2)

            stone(.dark, widthRatio: 1, heightRatio: 0.3)
                .zIndex(1)
        }
        .background(alignment: .bottom) {
            Ellipse()
                .fill(Theme.shadow.opacity(0.22))
                .frame(width: width * 0.92, height: width * 0.07)
                .blur(radius: width * 0.04)
                .offset(y: width * 0.035)
        }
        .accessibilityHidden(true)
        .onAppear {
            guard isBalancing, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                isLifted = true
            }
        }
        .onDisappear {
            isLifted = false
        }
    }

    private func lift(_ level: CGFloat) -> CGFloat {
        isLifted ? -level * width * 0.035 : 0
    }

    private func stone(_ tone: StoneTone, widthRatio: CGFloat, heightRatio: CGFloat) -> some View {
        Ellipse()
            .fill(tone.fill)
            .overlay { StoneGrain(tone: tone) }
            .overlay { StoneLighting() }
            .clipShape(Ellipse())
            .compositingGroup()
            .frame(width: width * widthRatio, height: width * heightRatio)
    }
}

/// A tiny cairn with one stone per source a story appears in. It marks
/// cross-posted stories, the app's strongest sign that something matters.
/// Drawn in the current foreground style.
struct CairnGlyph: View {
    let count: Int

    var body: some View {
        let stones = min(max(count, 2), 4)

        VStack(spacing: 1) {
            ForEach(0..<stones, id: \.self) { index in
                // `level` counts up from the base stone.
                let level = CGFloat(stones - 1 - index)
                Ellipse()
                    .frame(width: 12 - level * 2.6, height: 4 - level * 0.45)
                    .opacity(1 - level * 0.22)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Stones") {
    VStack(spacing: 32) {
        CairnMark(width: 120)

        VStack(spacing: 5) {
            ForEach(StoneTone.allCases, id: \.self) { tone in
                StoneSurface(tone: tone)
                    .frame(height: 120 * tone.heightFactor)
            }
        }

        HStack(spacing: 16) {
            CairnGlyph(count: 2)
            CairnGlyph(count: 3)
            CairnGlyph(count: 4)
        }
        .foregroundStyle(Theme.inkMuted)
    }
    .padding(24)
    .background(Theme.paper)
}
