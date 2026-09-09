# Controls

## Pill segmented control
`PillSegmented` replaces every `Picker(.segmented)` in the app. Each option always
shows its icon; the selected one expands to reveal its label.

- The moving highlight is **one capsule shared via `matchedGeometryEffect`**, so it
  slides between options. Per-option backgrounds that fade in and out read as
  several controls; one object moving reads as one control.
- The label is **clipped to zero width** when inactive, never removed from the
  hierarchy — removing it makes the capsule jump instead of grow.
- Label width, highlight position and padding all animate on the **same spring**
  (`response 0.34, dampingFraction 0.78`), so the change lands as a single motion
  rather than three things happening near each other.
- Every option carries an SF Symbol *and* a `help()` tooltip, so a collapsed option
  is still identifiable without clicking it.

## Search
`SearchBar` lives in the dashboard header on every page.

It is **always wide enough to type in** (232pt) and grows on focus (380pt). A
search box that must be opened before it can be used is a button pretending to be
a field; the collapse-to-pill pattern looks good in a demo and costs a click every
time in real use.

Queries are debounced 220ms and match projects (by name *and* path, so
`org/service` is found by either) and models. Selecting a project navigates to
Analysis scoped to it; selecting a model opens Models.

### Height gotcha
`.background()` sizes to the view it decorates, so a capsule applied *before* the
height frame wraps the text's own height and the field renders as a thin outline
next to the full-height controls beside it. The inner frame needs
`maxHeight: .infinity` so the decoration fills the height the outer frame sets.
This looked like a design preference ("make it bigger") and was a layout bug.

### The gooey panel
The results panel appears extruded from the field. That is a real metaball, not a
drop shadow: a `Canvas` draws the field's stub and the panel body, blurs them
together, then re-hardens the edge with `alphaThreshold` — overlapping shapes fuse
instead of stacking.

**The rows are drawn normally on top.** Thresholding text destroys it, so the
filter only ever runs on the backdrop shapes. Keep it that way.
