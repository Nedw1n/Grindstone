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
        .fontWeight(.medium)
        .padding(.horizontal, style == .compact ? 5 : 7)
        .padding(.vertical, 2)
        .background(source.color.opacity(0.12))
        .foregroundStyle(source.color)
        .clipShape(Capsule())
    }
}

#Preview {
    HStack {
        SourceTag(source: .hn)
        SourceTag(source: .memo)
        SourceTag(source: .mr, style: .compact)
    }
    .padding()
}
