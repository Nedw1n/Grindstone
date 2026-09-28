import SwiftUI

/// Source filters as a row of quiet text tabs. The selected tab rests on a
/// raised paper pebble that slides between them.
struct FilterBar: View {
    @Binding var selection: Source?
    let sources: [Source]

    @Namespace private var pebble

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                FilterTab(title: "All", source: nil, isSelected: selection == nil, namespace: pebble) {
                    selection = nil
                }

                ForEach(sources) { source in
                    FilterTab(
                        title: source.shortName,
                        source: source,
                        isSelected: selection == source,
                        namespace: pebble
                    ) {
                        selection = source
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            // Scoped to the bar, so the pebble slides without animating the list.
            .animation(.snappy(duration: 0.28), value: selection)
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

private struct FilterTab: View {
    let title: String
    /// `nil` is the "All" tab, which has no source dot.
    let source: Source?
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let source {
                    SourceDot(source: source)
                }
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? Theme.ink : Theme.inkMuted)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Theme.paperRaised)
                        .overlay {
                            Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5)
                        }
                        .shadow(color: Theme.shadow.opacity(0.12), radius: 4, x: 0, y: 2)
                        .matchedGeometryEffect(id: "selection", in: namespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    FilterBar(selection: .constant(nil), sources: Source.allCases)
        .padding(.vertical)
        .background(Theme.paper)
}
