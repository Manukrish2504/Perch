import SwiftUI

struct WidgetsTab: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            intro
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                spacing: 14
            ) {
                ForEach(WidgetKind.allCases) { kind in
                    card(kind)
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pin any of these to the desktop.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.primaryText)
            Text("""
                 They use the same size families as macOS widgets and sit just above \
                 the desktop icons, on the left so they don't land on top of Weather \
                 and Calendar. Like system widgets they live *under* your windows, so \
                 use Arrange below to lift them up and drag them into place. \
                 Right-click a widget to change its size or remove it.
                 """)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    state.isArranging.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: state.isArranging
                              ? "checkmark"
                              : "arrow.up.and.down.and.arrow.left.and.right")
                            .font(.system(size: 10, weight: .semibold))
                        Text(state.isArranging ? "Done arranging" : "Arrange on desktop")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(state.isArranging ? .black : Theme.primaryText)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(
                        Capsule().fill(state.isArranging ? Theme.accent : Color.white.opacity(0.10))
                    )
                }
                .buttonStyle(.plain)

                Text(state.isArranging
                     ? "Drag each widget where you want it, then click Done."
                     : "Lifts widgets above your windows so you can drag them into place.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.tertiaryText)
                Spacer()
            }

            Toggle(isOn: $state.settings.widgetsFloat) {
                Text("Keep widgets above every window")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.primaryText)
            }
            .toggleStyle(.switch)

            Toggle(isOn: $state.settings.heatmap3D) {
                Text("Extrude activity grids into 3D")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.primaryText)
            }
            .toggleStyle(.switch)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .perchCard()
    }

    private func card(_ kind: WidgetKind) -> some View {
        let placement = state.settings.placement(kind)
        let on = placement.enabled
        let size = resolvedSize(kind, placement)

        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text(kind.blurb)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Toggle("", isOn: Binding(
                    get: { on },
                    set: { newValue in
                        var next = state.settings.placement(kind)
                        next.enabled = newValue
                        next.size = resolvedSize(kind, next)
                        state.settings.widgets[kind.rawValue] = next
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            if kind.sizes.count > 1 {
                PillSegmented(
                    selection: Binding(
                        get: { size },
                        set: { newValue in
                            var next = state.settings.placement(kind)
                            next.size = newValue
                            state.settings.widgets[kind.rawValue] = next
                        }
                    ),
                    options: kind.sizes.map { .init($0, $0.label, $0.icon) },
                    compact: true
                )
            }

            // A live preview at true widget size, scaled to fit — what you toggle
            // is exactly what lands on the desktop.
            preview(kind, size: size, enabled: on)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius)
                .strokeBorder(on ? Theme.accent.opacity(0.45) : Theme.hairline, lineWidth: 1)
        )
    }

    private func preview(_ kind: WidgetKind, size: WidgetSize, enabled: Bool) -> some View {
        let points = size.points
        let scale = min(1, 292 / points.width)
        return WidgetRoot(kind: kind, size: size, state: state)
            .frame(width: points.width, height: points.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: points.width * scale, height: points.height * scale, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .center)
            .opacity(enabled ? 1 : 0.5)
    }

    /// Settings may hold a family this widget no longer offers.
    private func resolvedSize(_ kind: WidgetKind, _ placement: WidgetPlacement) -> WidgetSize {
        kind.sizes.contains(placement.size) ? placement.size : kind.defaultSize
    }
}
