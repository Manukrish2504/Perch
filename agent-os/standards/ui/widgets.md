# Desktop Widgets

## Window level
A widget is an `NSPanel` at `CGWindowLevelForKey(.desktopIconWindow) + 1` — above
the desktop icons, below every real window. That is what makes it a *desktop*
widget rather than a floating palette that covers the thing you are working in.
`settings.widgetsFloat` promotes them all to `.floating` for people who want the
opposite; nothing else changes.

- `canBecomeKey` is **false**. A widget is display-only and must never take focus.
- `isMovableByWindowBackground = true`, and the moved position is written back to
  settings from `NSWindow.didMoveNotification`. Widgets stay where they are put.
- A saved position is only reused if some attached screen still intersects it,
  otherwise the widget would open on a display that is no longer there.

## Size families
A widget is **not** freely resizable on macOS — you pick a family — so Perch does
the same. `WidgetSize` carries the real point sizes (small 155x155, medium
329x155, large 329x329) and one continuous 24pt corner radius. Content is written
per family; a medium that just clips the large layout is a bug (the Limits widget
shipped that way once and lost its reset line off the bottom).

Chrome is vibrancy + a black wash + the system shadow, and **no stroked border**.
An outline is what made the first version read as "small app window" rather than
"widget".

## Layout
Default placement stacks down the **left** edge of `visibleFrame` and starts a new
column when the next widget would cross the bottom margin. Two reasons: the stack
does not fit in one column on a 14" display, and the right edge is where macOS
puts its own desktop widgets — defaulting there landed Perch on top of Weather
and Calendar.

## Placement is the hard part
A desktop-level window sits **under** every ordinary window, so a click meant for
it lands on whatever is in front and the widget cannot be dragged at all. Native
widgets have the same property; users reach them by exposing the desktop.

Perch solves it with **arrange mode** (`AppState.isArranging`, deliberately not
persisted): every widget lifts to `.floating`, gains a labelled outline so it is
obvious what can be dragged, and drops back when done. Two things follow from
that and must not regress:
- the dashboard window is raised above `.floating` while arranging, or the very
  button that ends the mode gets buried under the widgets it lifted;
- each widget's context menu also carries "Done Arranging", so the flow never
  depends on reaching the dashboard at all.

## Content rules
- A widget reads `AppState` and renders. It owns no state of its own beyond view
  toggles, and it never triggers a scan.
- Sizes live in `WidgetKind.size` and are the single source of truth: the picker in
  the dashboard renders each widget at that exact size, scaled down, so the preview
  is the real thing rather than an approximation of it.
- Background is `VibrantBackground` (`NSVisualEffectView`, `.behindWindow`) over a
  black wash. A flat rectangle on a desktop reads as a bug.

## Reporting quota
`LimitWindow` carries whatever the tool actually wrote to disk, and the two
providers write different things: Codex logs a live `used_percent` per window,
Claude Code logs nothing until a request is rejected and then only a reset time.
Render each for what it is — a bar for Codex, "hit N× / 7d" for Claude — and mark
any reading older than a day with its age. Never synthesise a percentage for a
provider that does not publish one.
