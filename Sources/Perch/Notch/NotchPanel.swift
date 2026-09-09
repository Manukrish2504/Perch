import AppKit
import SwiftUI

/// The window that lives on the notch.
///
/// An `NSPanel`, not an `NSWindow`: it must never take key focus when clicked, and
/// it must sit above the menu bar on every Space. See
/// `agent-os/standards/ui/notch-windows.md`.
final class NotchPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // .statusBar (25) is one level above the menu bar (24) and well below the
        // shielding level, so it never covers screen savers or security prompts.
        level = .statusBar
        // Deliberately no `.fullScreenAuxiliary`: that behaviour is what puts a
        // window on a full-screen app's space, and the shelf hanging over
        // full-screen content is exactly what it must not do. `NotchController`
        // additionally orders the panel out, because the collection behaviour alone
        // is not reliable once `.canJoinAllSpaces` is in play.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        // A panel with no title bar still reports itself to the window list unless
        // told otherwise; excluding it keeps it out of Mission Control and screenshots.
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
    }

    // A borderless panel refuses key status by default, which would break the
    // expanded panel's buttons; accepting it while staying non-activating is the
    // behaviour we want.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosts the shelf and reports hover, since a non-activating panel gets no
/// `mouseEntered` from SwiftUI's `onHover` reliably while another app is active.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var onHoverChange: ((Bool) -> Void)?
    var onClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }

    // These only fire for clicks SwiftUI did not already consume, so the expanded
    // panel's own buttons keep working.
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) { onRightClick?(event) }
}
