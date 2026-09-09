# Notch Windows

## Geometry facts (do not re-derive these)
- The notch cutout has **no pixels**. You cannot draw inside it.
- `NSScreen.safeAreaInsets.top` == notch height. `0` means no notch on that screen.
- `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` are the usable menu-bar strips
  either side of the cutout. Notch width = `frame.width - left.width - right.width`.
- Screen coordinates are bottom-left origin. The notch top edge is `frame.maxY`.

## The window
An `NSPanel`, never an `NSWindow`:
- `styleMask: [.borderless, .nonactivatingPanel]` — clicking must not steal focus.
- `level = .statusBar` (25) — above the menu bar (24), below the shielding level.
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`
- `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`.
- `isMovable = false` — it is pinned to the notch, users must not drag it away.

## The blocking rule
The idle window must be **no wider than the notch cutout**. One pixel wider and it
eats menu-bar clicks or status-item clicks, which users experience as the app being
broken. Everything Perch draws while idle lives in the cutout's own width, or in the
rows *below* the menu bar where nothing else lives.

## Full screen
The shelf hangs *below* the notch, over whatever is underneath — so on a
full-screen app it covers the top of the content. It must withdraw.

Two things are needed, and neither is sufficient alone:
- **No `.fullScreenAuxiliary`** in `collectionBehavior`. That behaviour is
  precisely what places a window on a full-screen app's space.
- **Order the panel out** when the display is showing a full-screen app, because
  `.canJoinAllSpaces` still lands it there otherwise.

Detecting it: look for an ordinary (layer 0) window covering the display's full
width, running from the menu bar height down to the very bottom edge. That is the
direct form of the question — "is app content occupying the strip I am about to
draw over?" — and it separates full screen from merely zoomed, which stops short
at the Dock.

`NSScreen.visibleFrame` does **not** work for this: it reports the same menu bar
inset in both states (measured — 33pt either way). Its origin does move, but only
because the Dock is unreserved, which is not the same question.

Re-evaluate on `NSWorkspace.activeSpaceDidChangeNotification` — entering or
leaving full screen always changes space, so that is the precise signal. Poll only
as a slow backstop; scanning the window list at hover cadence is far too costly.

## Fallback
No notch (external display, non-notch Mac) → render the same shelf as a floating
pill centred at the top of the main screen, inset below the menu bar.

## Activation
`NSApp.setActivationPolicy(.accessory)` — no Dock icon, no menu bar of its own.
The dashboard window calls `NSApp.activate()` explicitly when opened.
