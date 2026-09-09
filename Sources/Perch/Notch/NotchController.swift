import AppKit
import SwiftUI

/// Drives expansion so the SwiftUI tree animates without the controller having to
/// rebuild the root view on every hover.
@MainActor
final class ShelfModel: ObservableObject {
    @Published var expanded = false
}

private struct ShelfRoot: View {
    @ObservedObject var state: AppState
    @ObservedObject var shelf: ShelfModel
    let geometry: NotchGeometry
    var onOpenDashboard: () -> Void

    var body: some View {
        NotchShelfView(
            state: state,
            geometry: geometry,
            expanded: shelf.expanded,
            onOpenDashboard: onOpenDashboard
        )
        // Lay the shelf out at its *current* size. Sizing it to the expanded
        // bounds and shrinking the window around it pushes the idle content off
        // the window and clips the rounded corners away.
        .frame(
            width: shelf.expanded ? NotchGeometry.expandedWidth : geometry.notchWidth,
            height: geometry.notchHeight + (shelf.expanded ? NotchGeometry.expandedDrop : NotchGeometry.idleDrop),
            alignment: .top
        )
        // The window stays at expanded bounds until the collapse animation ends,
        // so centre the shelf inside whatever the window currently is.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Theme.expand, value: shelf.expanded)
    }
}

@MainActor
final class NotchController: NSObject {
    private let state: AppState
    private let shelf = ShelfModel()
    private var panel: NotchPanel?
    private var hosting: NotchHostingView<ShelfRoot>?
    private var geometry: NotchGeometry?
    private var collapseWork: DispatchWorkItem?
    private var mouseMonitor: Any?
    private var localMonitor: Any?
    private var hoverTimer: Timer?
    private var spaceObserver: NSObjectProtocol?
    /// True while the shelf is withheld because the display is showing a
    /// full-screen app.
    private var hiddenForFullscreen = false
    private var fullscreenPollTick = 0

    var onOpenDashboard: () -> Void = {}

    init(state: AppState) {
        self.state = state
        super.init()
    }

    func install() {
        rebuild()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }

        // Tracking areas are unreliable for a non-activating accessory panel — the
        // app is usually not frontmost, so enter/exit simply never arrive. Cursor
        // position is the source of truth instead. Mouse-move monitors need no
        // accessibility permission; the local one covers the case where Perch's own
        // dashboard is focused, since global monitors skip your own app's events.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncHoverWithCursor() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated { self?.syncHoverWithCursor() }
            return event
        }
        // A poll backstops both: the cursor can enter the strip without any move
        // event reaching us (Space switches, warps, wake from sleep).
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.syncHoverWithCursor()
                // Scanning the window list is far too costly at hover cadence, and
                // entering full screen always changes space anyway — this is only a
                // backstop for in-place full screen that raises no space change.
                self.fullscreenPollTick += 1
                if self.fullscreenPollTick % 6 == 0 { self.updateFullscreenVisibility() }
            }
        }

        // Entering or leaving full screen moves to another space, which is the
        // precise signal; the poll above only covers apps that go full screen
        // without one.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateFullscreenVisibility() }
        }
        updateFullscreenVisibility()
    }

    // MARK: - Full screen

    /// Withdraws the shelf while a full-screen app owns the display, and brings it
    /// back afterwards.
    private func updateFullscreenVisibility() {
        guard let panel, let geometry else { return }
        let shouldHide = state.settings.hideInFullscreen
            && Self.displayIsFullscreen(geometry)
        guard shouldHide != hiddenForFullscreen else { return }
        hiddenForFullscreen = shouldHide
        Log.debug("fullscreen=\(shouldHide) — \(shouldHide ? "hiding" : "showing") shelf")

        if shouldHide {
            collapseWork?.cancel()
            shelf.expanded = false
            panel.setFrame(geometry.frame(expanded: false), display: false)
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// Is an ordinary window covering this display's full width, from the menu bar
    /// down to the bottom edge?
    ///
    /// That is the direct form of the question the shelf cares about — "is app
    /// content occupying the strip I am about to draw over?" — and it is what a
    /// full-screen window looks like: on a notched display it sits at the menu bar
    /// height and runs to the very bottom, whereas a merely zoomed window stops
    /// short at the Dock. Checking `visibleFrame` does not work; it reports the
    /// same menu bar inset either way.
    private static func displayIsFullscreen(_ geometry: NotchGeometry) -> Bool {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return false }

        // CGWindow bounds are top-left origin, measured from the primary display.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? geometry.screenFrame.height
        let screen = CGRect(
            x: geometry.screenFrame.minX,
            y: primaryHeight - geometry.screenFrame.maxY,
            width: geometry.screenFrame.width,
            height: geometry.screenFrame.height
        )
        let tolerance: CGFloat = 3

        for window in list {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat, let y = bounds["Y"] as? CGFloat,
                  let width = bounds["Width"] as? CGFloat,
                  let height = bounds["Height"] as? CGFloat
            else { continue }

            let spansWidth = abs(width - screen.width) < tolerance
                && abs(x - screen.minX) < tolerance
            let reachesBottom = abs((y + height) - screen.maxY) < tolerance
            let startsAtMenuBar = y <= screen.minY + geometry.notchHeight + tolerance
            if spansWidth, reachesBottom, startsAtMenuBar { return true }
        }
        return false
    }

    private func rebuild() {
        guard let geometry = NotchGeometry.current() else { return }
        self.geometry = geometry
        Log.debug("geometry notch=\(geometry.notchWidth)x\(geometry.notchHeight) hasNotch=\(geometry.hasNotch) idle=\(geometry.frame(expanded: false))")

        let root = ShelfRoot(
            state: state, shelf: shelf, geometry: geometry,
            onOpenDashboard: { [weak self] in self?.onOpenDashboard() }
        )

        if let panel, let hosting {
            hosting.rootView = root
            panel.setFrame(frame(for: geometry), display: true)
            return
        }

        let panel = NotchPanel(contentRect: frame(for: geometry))
        let hosting = NotchHostingView(rootView: root)
        hosting.onHoverChange = { [weak self] inside in
            MainActor.assumeIsolated { self?.setExpanded(inside) }
        }
        hosting.onClick = { [weak self] in
            MainActor.assumeIsolated {
                // Only a click on the already-expanded panel opens the dashboard;
                // the idle strip is too easy to hit by accident.
                guard let self, self.shelf.expanded else { return }
                self.onOpenDashboard()
            }
        }
        hosting.onRightClick = { [weak self] event in
            MainActor.assumeIsolated { self?.showContextMenu(event) }
        }
        panel.contentView = hosting
        panel.orderFrontRegardless()

        self.panel = panel
        self.hosting = hosting
    }

    /// While expanded the window occupies the full expanded bounds; while idle it
    /// shrinks back to the cutout's own width so it blocks nothing.
    private func frame(for geometry: NotchGeometry) -> CGRect {
        geometry.frame(expanded: shelf.expanded)
    }

    private func setExpanded(_ expanded: Bool) {
        guard let panel, let geometry, shelf.expanded != expanded else { return }
        collapseWork?.cancel()

        if expanded {
            // Grow the window first so the animating content is never clipped.
            panel.setFrame(geometry.frame(expanded: true), display: true)
            shelf.expanded = true
        } else {
            shelf.expanded = false
            // Shrink only once the collapse animation has finished.
            let work = DispatchWorkItem { [weak self] in
                guard let self, let panel = self.panel, let geometry = self.geometry,
                      !self.shelf.expanded else { return }
                panel.setFrame(geometry.frame(expanded: false), display: true)
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }
    }

    /// The shelf has no menu bar item, so the right-click menu is the only always
    /// available place for Quit.
    private func showContextMenu(_ event: NSEvent) {
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Dashboard", action: #selector(menuOpen), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let rescan = NSMenuItem(title: "Rescan Now", action: #selector(menuRescan), keyEquivalent: "")
        rescan.target = self
        menu.addItem(rescan)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Perch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        if let view = hosting {
            menu.popUp(positioning: nil, at: view.convert(event.locationInWindow, from: nil), in: view)
        }
    }

    @objc private func menuOpen() { onOpenDashboard() }
    @objc private func menuRescan() { state.rescanNow() }

    /// Single source of hover truth: is the cursor inside the shelf right now?
    private func syncHoverWithCursor() {
        guard let geometry, !hiddenForFullscreen else { return }
        // Test against the *idle* strip when collapsed and the full panel when
        // expanded, so the trigger zone never depends on the in-flight window size.
        let zone = geometry.frame(expanded: shelf.expanded)
        let mouse = NSEvent.mouseLocation
        let inside = zone.insetBy(dx: -2, dy: -2).contains(mouse)
        Log.debug("hover zone=\(zone) mouse=\(mouse) inside=\(inside) expanded=\(shelf.expanded)")
        if inside != shelf.expanded { setExpanded(inside) }
    }
}
