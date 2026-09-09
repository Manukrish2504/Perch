import SwiftUI

/// A pill segmented control: every option shows its icon, and the selected one
/// expands to reveal its label.
///
/// The moving highlight is a single capsule shared across options via
/// `matchedGeometryEffect`, so it slides between them instead of cross-fading —
/// one object moving reads as one control, where per-button backgrounds read as
/// several. Label width and the highlight animate on the same spring so the whole
/// thing lands as a single motion.
struct PillSegmented<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let label: String
        let icon: String
        var id: Value { value }

        init(_ value: Value, _ label: String, _ icon: String) {
            self.value = value
            self.label = label
            self.icon = icon
        }
    }

    @Binding var selection: Value
    let options: [Option]
    var compact: Bool = false

    @Namespace private var highlight
    @Local private var hovered: Value?

    private var height: CGFloat { compact ? 28 : 34 }
    private var iconSize: CGFloat { compact ? 11 : 12.5 }
    private var labelSize: CGFloat { compact ? 11 : 12.5 }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                item(option)
            }
        }
        .padding(4)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.raised)
                .overlay(Capsule(style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        )
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: selection)
    }

    private func item(_ option: Option) -> some View {
        let isSelected = selection == option.value
        let isHovered = hovered == option.value

        return Button {
            selection = option.value
        } label: {
            HStack(spacing: isSelected ? 6 : 0) {
                Image(systemName: option.icon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .frame(width: iconSize + 3)

                // The label is clipped to zero width when inactive rather than
                // removed, so the capsule grows smoothly instead of jumping.
                Text(option.label)
                    .font(.system(size: labelSize, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: isSelected ? nil : 0, alignment: .leading)
                    .opacity(isSelected ? 1 : 0)
                    .clipped()
            }
            .foregroundStyle(
                isSelected ? Theme.primaryText
                    : (isHovered ? Theme.secondaryText : Theme.tertiaryText)
            )
            .padding(.horizontal, isSelected ? 13 : 10)
            .frame(height: height)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(Theme.accent.opacity(0.22))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1)
                        )
                        .matchedGeometryEffect(id: "pill", in: highlight)
                } else if isHovered {
                    Capsule(style: .continuous).fill(Color.white.opacity(0.06))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressScale())
        .onHover { inside in
            withAnimation(.easeInOut(duration: 0.15)) {
                hovered = inside ? option.value : nil
            }
        }
        .help(option.label)
    }
}

/// A small press response — the control should feel like it takes the click.
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
