import AppKit
import SwiftUI

/// A desktop widget window.
///
/// Sits one level above the desktop icons, so it behaves like a real desktop
/// widget: on the desktop, never covering the window you are working in.
/// `keepAbove` promotes it to floating for people who want the opposite.
final class WidgetPanel: NSPanel {
    let kind: WidgetKind
    var onMoved: ((CGPoint) -> Void)?
    var onResize: ((WidgetSize) -> Void)?
    var onHide: (() -> Void)?
    var onOpenDashboard: (() -> Void)?
    var onDoneArranging: (() -> Void)?
    var isArranging = false

    init(kind: WidgetKind, frame: CGRect, keepAbove: Bool) {
        self.kind = kind
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        // The system draws widget shadows; matching one here is what makes a panel
        // read as sitting on the desktop rather than pasted onto it.
        hasShadow = true
        isMovable = true
        hidesOnDeactivate = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        setLevel(keepAbove: keepAbove)

        NotificationCenter.default.addObserver(
            self, selector: #selector(moved),
            name: NSWindow.didMoveNotification, object: self
        )
    }

    func setLevel(keepAbove: Bool) {
        level = keepAbove
            ? .floating
            : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    @objc private func moved() { onMoved?(frame.origin) }

    // Display-only: a widget must never take focus from what you are working in.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The widget's drag surface.
///
/// Widget content is inert (`allowsHitTesting(false)` in `WidgetRoot`), so the
/// whole face is a drag handle — which is how a macOS widget behaves. Anything
/// configurable lives in the dashboard's Widgets tab or this view's context menu,
/// rather than as controls inside the widget.
final class WidgetDragView: NSView {
    weak var panel: WidgetPanel?

    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        // performDrag runs its own event loop and follows the cursor exactly,
        // which is more reliable for a non-key panel than window-background drag.
        panel?.performDrag(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let panel else { return }
        let menu = NSMenu()

        let sizes = NSMenu()
        for size in panel.kind.sizes {
            let item = NSMenuItem(
                title: size.label, action: #selector(pickSize(_:)), keyEquivalent: ""
            )
            item.target = self
            item.representedObject = size.rawValue
            item.state = panel.frame.size == size.points ? .on : .off
            sizes.addItem(item)
        }
        let sizeItem = NSMenuItem(title: "Widget Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizes
        menu.addItem(sizeItem)

        menu.addItem(.separator())
        if panel.isArranging {
            let done = NSMenuItem(title: "Done Arranging", action: #selector(doneArranging), keyEquivalent: "")
            done.target = self
            menu.addItem(done)
        }
        let open = NSMenuItem(title: "Open Dashboard", action: #selector(openDashboard), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let hide = NSMenuItem(title: "Remove Widget", action: #selector(hideWidget), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)

        menu.popUp(positioning: nil, at: convert(event.locationInWindow, from: nil), in: self)
    }

    @objc private func pickSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let size = WidgetSize(rawValue: raw) else { return }
        panel?.onResize?(size)
    }

    @objc private func openDashboard() { panel?.onOpenDashboard?() }
    @objc private func doneArranging() { panel?.onDoneArranging?() }
    @objc private func hideWidget() { panel?.onHide?() }
}

/// Real window vibrancy behind a widget, masked to the widget's corner radius so
/// it reads as a system widget rather than a rectangle with a rounded picture in it.
struct VibrantBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var cornerRadius: CGFloat = WidgetSize.cornerRadius

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.layer?.cornerRadius = cornerRadius
    }
}
