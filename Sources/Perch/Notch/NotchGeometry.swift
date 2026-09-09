import AppKit

/// Notch metrics for a screen. See `agent-os/standards/ui/notch-windows.md` —
/// the facts encoded here are deliberately not re-derived elsewhere.
struct NotchGeometry {
    let screenFrame: CGRect
    /// Height of the cutout, which equals the menu bar height on a notched Mac.
    let notchHeight: CGFloat
    /// Width of the cutout. On a screen without one this is the fallback pill width.
    let notchWidth: CGFloat
    let hasNotch: Bool

    /// How far the idle shelf hangs below the cutout. Deep enough to read the
    /// pet and the numbers at a glance, without hovering.
    static let idleDrop: CGFloat = 34
    static let expandedWidth: CGFloat = 412
    static let expandedDrop: CGFloat = 168
    /// Used when no screen has a notch, so the shelf still has somewhere to live.
    static let fallbackWidth: CGFloat = 210
    static let fallbackTopInset: CGFloat = 6

    /// Prefers a screen with a real notch; otherwise falls back to the main screen.
    static func current() -> NotchGeometry? {
        let screens = NSScreen.screens
        if let notched = screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return NotchGeometry(screen: notched)
        }
        guard let main = NSScreen.main ?? screens.first else { return nil }
        return NotchGeometry(screen: main)
    }

    init(screen: NSScreen) {
        screenFrame = screen.frame
        let inset = screen.safeAreaInsets.top
        if inset > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            hasNotch = true
            notchHeight = inset
            notchWidth = max(120, screen.frame.width - left.width - right.width)
        } else {
            hasNotch = false
            // Without a cutout there is nothing to hug, so the shelf becomes a pill
            // that hangs just under the menu bar.
            notchHeight = NSStatusBar.system.thickness + Self.fallbackTopInset
            notchWidth = Self.fallbackWidth
        }
    }

    /// Window frame for a given state, in screen coordinates (bottom-left origin).
    ///
    /// The idle frame is never wider than the cutout — one pixel more and it starts
    /// eating menu bar clicks.
    func frame(expanded: Bool) -> CGRect {
        let width = expanded ? Self.expandedWidth : notchWidth
        let height = notchHeight + (expanded ? Self.expandedDrop : Self.idleDrop)
        return CGRect(
            x: (screenFrame.midX - width / 2).rounded(),
            y: screenFrame.maxY - height,
            width: width,
            height: height
        )
    }
}
