import AppKit
import SwiftUI

/// Creates and tears down widget panels to match settings, and remembers where
/// the user dragged each one and at what size.
@MainActor
final class WidgetController {
    private let state: AppState
    private var panels: [WidgetKind: WidgetPanel] = [:]
    var onOpenDashboard: () -> Void = {}

    init(state: AppState) {
        self.state = state
    }

    /// Brings the on-screen set in line with settings. Safe to call repeatedly.
    func sync() {
        for kind in WidgetKind.allCases {
            let placement = state.settings.placement(kind)
            guard placement.enabled else {
                panels.removeValue(forKey: kind)?.orderOut(nil)
                continue
            }
            if let panel = panels[kind] {
                // A size change is a reframe, not a rebuild — the widget should
                // grow from where it already sits rather than jumping home.
                let target = placement.size.points
                if panel.frame.size != target {
                    panel.setFrame(
                        CGRect(origin: panel.frame.origin, size: target), display: true
                    )
                    panel.contentView = hostView(for: kind, size: placement.size, panel: panel)
                }
            } else {
                show(kind, placement: placement)
            }
        }
        for panel in panels.values {
            panel.isArranging = state.isArranging
            panel.setLevel(keepAbove: state.settings.widgetsFloat || state.isArranging)
            if state.isArranging { panel.orderFrontRegardless() }
        }
    }

    private func show(_ kind: WidgetKind, placement: WidgetPlacement) {
        let panel = WidgetPanel(
            kind: kind,
            frame: frame(for: kind, placement: placement),
            keepAbove: state.settings.widgetsFloat || state.isArranging
        )
        panel.contentView = hostView(for: kind, size: placement.size, panel: panel)
        panel.onMoved = { [weak self] origin in
            MainActor.assumeIsolated { self?.update(kind) { $0.x = origin.x; $0.y = origin.y } }
        }
        panel.onResize = { [weak self] size in
            MainActor.assumeIsolated { self?.update(kind) { $0.size = size } }
        }
        panel.onHide = { [weak self] in
            MainActor.assumeIsolated { self?.update(kind) { $0.enabled = false } }
        }
        panel.onOpenDashboard = { [weak self] in
            MainActor.assumeIsolated { self?.onOpenDashboard() }
        }
        panel.onDoneArranging = { [weak self] in
            MainActor.assumeIsolated { self?.state.isArranging = false }
        }
        panel.orderFrontRegardless()
        panels[kind] = panel
    }

    private func update(_ kind: WidgetKind, _ change: (inout WidgetPlacement) -> Void) {
        var placement = state.settings.placement(kind)
        change(&placement)
        state.settings.widgets[kind.rawValue] = placement
    }

    /// The drag surface wraps the SwiftUI content, so the whole widget face can be
    /// dragged and right-clicked the way a system widget can.
    private func hostView(for kind: WidgetKind, size: WidgetSize, panel: WidgetPanel) -> NSView {
        let container = WidgetDragView()
        container.panel = panel
        let hosting = NSHostingView(rootView: WidgetRoot(kind: kind, size: size, state: state))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    /// Saved position when there is one, else a tidy stack down the **left** edge.
    ///
    /// The right edge is where macOS puts its own desktop widgets, and defaulting
    /// there landed Perch's widgets on top of Weather and Calendar.
    private func frame(for kind: WidgetKind, placement: WidgetPlacement) -> CGRect {
        let size = placement.size.points
        if let x = placement.x, let y = placement.y {
            let candidate = CGRect(origin: CGPoint(x: x, y: y), size: size)
            // A saved position on a display that is no longer attached would put
            // the widget somewhere unreachable.
            if NSScreen.screens.contains(where: { $0.frame.intersects(candidate) }) {
                return candidate
            }
        }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return CGRect(origin: .zero, size: size)
        }
        return Self.defaultFrames(in: screen.visibleFrame, settings: state.settings)[kind]
            ?? CGRect(origin: screen.visibleFrame.origin, size: size)
    }

    /// Stacks down the left edge, starting a new column whenever the next widget
    /// would cross the bottom margin.
    static func defaultFrames(in bounds: CGRect, settings: Settings) -> [WidgetKind: CGRect] {
        let gap: CGFloat = 16
        let margin: CGFloat = 24
        var frames: [WidgetKind: CGRect] = [:]
        var columnLeft = bounds.minX + margin
        var columnWidth: CGFloat = 0
        var cursorY = bounds.maxY - margin

        for kind in WidgetKind.allCases {
            let size = settings.placement(kind).size.points
            if cursorY - size.height < bounds.minY + margin, columnWidth > 0 {
                columnLeft += columnWidth + gap
                columnWidth = 0
                cursorY = bounds.maxY - margin
            }
            frames[kind] = CGRect(
                x: columnLeft, y: cursorY - size.height,
                width: size.width, height: size.height
            )
            columnWidth = max(columnWidth, size.width)
            cursorY -= size.height + gap
        }
        return frames
    }
}
