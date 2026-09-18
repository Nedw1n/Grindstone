import SwiftUI

struct SourceTag: View {
    let source: Source
    var style: Style = .normal

    enum Style {
        case normal, compact
    }

    var body: some View {
        HStack(spacing: 3) {
            if style == .normal {
                Image(systemName: source.iconName)
            }
            Text(source.shortName)
        }
        .font(style == .compact ? .caption2 : .caption)
        .fontWeight(.semibold)
        .padding(.horizontal, style == .compact ? 5 : 7)
        .padding(.vertical, 2)
        .background(source.color.opacity(0.14), in: Capsule())
        .foregroundStyle(source.color)
        .fixedSize()
        .accessibilityLabel(source.rawValue)
    }
}

#Preview {
    HStack {
        SourceTag(source: .hn)
        SourceTag(source: .memo)
        SourceTag(source: .biotech)
        SourceTag(source: .rss, style: .compact)
    }
    .padding()
}
