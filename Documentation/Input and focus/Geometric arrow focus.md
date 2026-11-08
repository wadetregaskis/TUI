# Geometric arrow focus

Status, 2026-11-08: **an experiment, off by default**, on with `TUI_ARROW_FOCUS=geometric`. The owner asked to try it
"configurable (app-wide, e.g. with an environment variable for now)", and to know what keeping both approaches costs
compared with having one. The design was settled on the 2026-11-07 morning page.

## How to try it

```sh
TUI_ARROW_FOCUS=geometric swift run Example     # then the Focus page's grid of buttons
```

Any other value, or none, keeps today's arrows.

## What it does

An arrow key the focused control leaves unused (a list, a slider, a text field, a picker and a menu use their own) goes
to the nearest focusable control on screen in its direction, in the active section
(`FocusManagerGeometricArrows.swift`):

1. **Candidates** are the section's focusable controls the last frame drew whose frames lie wholly beyond the focused
   control's edge in that direction (touching counts).
2. **Beam first.** A candidate overlapping the focused control on the other axis (its columns for ↑ ↓, its rows for
   ← →) beats any that doesn't, however far.
3. **Then distance**: the squared distance between the nearest edges, a row counting as two columns, since a terminal
   cell is about twice as tall as it is wide.
4. **Then Tab order**, so the choice depends on the layout alone.
5. **Fallback**: with no candidate, the arrow does what it does today, the next (→ ↓) or previous (← ↑) control in Tab
   order, stopping at the section's ends.

Tab and Shift-Tab are unchanged. Left and Right between a split view's columns (`FocusManagerColumns.swift`) still come
first. Like today's arrows it never leaves the active section, so a sheet, an alert or a popover keeps the arrows. ↓
then ↑ need not return where you started; SwiftTUI and tvOS don't promise that either.

**Frames** come from what the frame already records: every hit-test region a focusable control draws carries its focus
id (`HitTestRegion.focusID`, which `ScrollView`'s reveal and the cursor-follows-focus experiment read too). The render
loop hands the frame's region array to the focus manager, only in geometric mode. A control drawn in pieces is the
smallest rectangle holding them. A control with no region this frame (scrolled out of a viewport, or a custom
`Focusable` that draws none) is not a candidate, and the fallback reaches it in Tab order.

### Reachability: a correction to the design note

The design said repeated ↓ still visits every control, because the fallback walks the Tab order. That holds where Tab
order runs down the screen (a column, a form, a grid laid out as columns), but not for a grid laid out as rows: in
three rows of three, repeated ↓ from the first button walks the first column, then the fallback walks the bottom row,
and stops. Repeated → visits all nine, and every control is reachable with the four arrows together. Tests pin both
(`GeometricArrowFocusTests.reachable`). A fallback that wraps ↓ to the top of the next column would make repeated ↓ visit
everything in a grid too, at the price of a second rule and a departure from "arrows fall back to what they do today";
not done, pending the owner.

## What having both modes costs

Measured on the commit that added it, counting code lines (no comments, no blank lines):

| | Sources | Tests |
|---|---:|---:|
| **Geometry itself**: candidates, ranking, frames (`FocusManagerGeometricArrows.swift`), the regions kept and handed over, the arrow calling it first | ~80 | ~170 |
| **Only to keep both modes**: the `ArrowFocus` enum and its reading of `TUI_ARROW_FOCUS` (7), the manager's mode and its accessor (5), the app runner setting it (1), the headless app's and `TestApp`'s accessors (8), the variable's documentation entry (4); and two conditions on existing lines, the render loop's and the geometric arrow's | ~25 | ~15 |

- **Deleting the old mode**, were geometry to be the only one, would remove the ~25 and ~15 lines above and nothing of
  today's arrow code: Tab-order arrows *are* the fallback, so `focusNextInSection()` and `focusPreviousInSection()`
  stay exactly as they are.
- **Deleting geometry** removes the one file (190 lines with comments) but for today's arrow switch, which moved into it
  from `Focus.swift` (`moveFocus(byArrow:)`, a dozen lines) and would move back; about 20 lines elsewhere; the test suite
  (238) and this note. Nothing else depends on it.

So having both costs about a third as much code as geometry itself, all of it plumbing that a decision either way
removes in one commit. No third mode is hidden in it: the fallback is the old mode, not a copy of it.

**Run time.** With the default: one enum comparison per frame and one per arrow no control used, and no frames kept.
Geometric: per frame, the region array the mouse dispatcher already holds is shared (a reference, not a copy); per
arrow, one pass over the frame's regions into a dictionary by focus id and one over the active section's controls,
so a few hundred small steps, done once per key press, not per frame. Not benchmarked: there is nothing per frame to
measure, and a key press already costs a whole frame.
