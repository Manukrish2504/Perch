import AppKit
import SwiftUI

/// The stats window. Created lazily the first time it is opened and reused after,
/// so closing it costs nothing to reopen.
@MainActor
final class DashboardWindowController: NSWindowController {
    convenience init(state: AppState, initialTab: DashboardTab = .overview) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Perch"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor.black
        window.minSize = NSSize(width: 940, height: 620)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: RootView(state: state, initialTab: initialTab))
        window.center()
        self.init(window: window)
        self.state = state
        window.setFrameAutosaveName("PerchDashboard")
    }

    /// While arranging, widgets float above every window — including this one,
    /// which would bury the "Done arranging" button. Raise the dashboard above
    /// them for the duration.
    func setArranging(_ arranging: Bool) {
        window?.level = arranging
            ? NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            : .normal
    }

    private weak var state: AppState?

    func present() {
        guard let window else { return }
        // An accessory app has to activate explicitly, or the window opens behind
        // whatever the user was working in.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Every open replays the run, and every open re-reads the logs behind it.
        state?.beginDashboardIntro()
    }
}
