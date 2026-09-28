import SwiftUI

/// A section label in eyebrow capitals, with an optional detail on the right.
struct SectionEyebrow: View {
    private let title: String
    private let detail: String?

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .eyebrowStyle()
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            if let detail {
                Text(detail)
                    .font(.caption2.weight(.medium))
                    .tracking(0.6)
                    .textCase(.uppercase)
            }
        }
        .foregroundStyle(Theme.inkMuted)
    }
}

/// Empty, caught-up, and loading states: the drawn cairn, a serif line, a
/// quiet explanation, and an optional action.
struct StoneEmptyState<Actions: View>: View {
    private let title: String
    private let message: String
    private let isBalancing: Bool
    private let actions: Actions

    init(
        _ title: String,
        message: String,
        isBalancing: Bool = false,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.message = message
        self.isBalancing = isBalancing
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 18) {
            CairnMark(width: 84, isBalancing: isBalancing)
                .padding(.bottom, 4)

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.ink)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)

            actions
        }
        .frame(maxWidth: 340)
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
    }
}

extension StoneEmptyState where Actions == EmptyView {
    init(_ title: String, message: String, isBalancing: Bool = false) {
        self.init(title, message: message, isBalancing: isBalancing) {
            EmptyView()
        }
    }
}

#Preview {
    StoneEmptyState("The stack is clear", message: "Every story here has been read.") {
        Button("Show Read Stories") {}
            .buttonStyle(.pebble)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.paper)
}
