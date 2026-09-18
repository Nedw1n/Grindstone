import SwiftUI

struct FilterBar: View {
    @Binding var selection: Source?
    let sources: [Source]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                FilterChip(
                    title: "All",
                    systemImage: "square.grid.2x2",
                    tint: nil,
                    isSelected: selection == nil
                ) {
                    selection = nil
                }

                ForEach(sources) { source in
                    FilterChip(
                        title: source.shortName,
                        systemImage: source.iconName,
                        tint: source.color,
                        isSelected: selection == source
                    ) {
                        selection = source
                    }
                }
            }
            .padding(.horizontal)
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

private struct FilterChip: View {
    let title: String
    let systemImage: String
    /// `nil` renders the neutral "All" chip.
    let tint: Color?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(foreground)
                .background(background, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(baseColor.opacity(isSelected ? 0 : 0.2), lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var baseColor: Color {
        tint ?? .primary
    }

    private var foreground: AnyShapeStyle {
        if isSelected {
            return tint == nil ? AnyShapeStyle(.background) : AnyShapeStyle(.white)
        }
        return AnyShapeStyle(baseColor)
    }

    private var background: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(baseColor)
        }
        return AnyShapeStyle(baseColor.opacity(0.10))
    }
}

#Preview {
    FilterBar(selection: .constant(.hn), sources: Source.allCases)
        .padding(.vertical)
}
