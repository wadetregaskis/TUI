# Geometric arrow focus

Status, 2026-11-08: **an experiment, off by default**, on with `TUI_ARROW_FOCUS=geometric`. The owner asked to try it
"configurable (app-wide, e.g. with an environment variable for now)", and to know what keeping both approaches costs
compared with having one. The design was settled on the 2026-11-07 morning page. Since 2026-11-08 the arrows reach
controls scrolled out of sight too ([Controls out of sight](#controls-out-of-sight)).

## How to try it

```sh
TUI_ARROW_FOCUS=geometric swift run Example     # then the Focus page's grid of buttons
```

Any other value, or none, keeps today's arrows.

## What it does

An arrow key the focused control leaves unused (a list, a slider, a text field, a picker and a menu use their own) goes
to the nearest focusable control in its direction, on screen or scrolled out of sight, in the active section
(`FocusManagerGeometricArrows.swift`):

1. **Candidates** are the section's focusable controls the last frame laid out, drawn or clipped by a scroll view,
   whose frames lie wholly beyond the focused control's edge in that direction (touching counts).
2. **Beam first.** A candidate overlapping the focused control on the other axis (its columns for ↑ ↓, its rows for
   ← →) beats any that doesn't, however far.
3. **Then distance**: the squared distance between the nearest edges, a row counting as two columns, since a terminal
   cell is about twice as tall as it is wide.
4. **Then Tab order**, so the choice depends on the layout alone.
5. **No wrap**: with no candidate, the focus stays, at the end of a row or the foot of a column, wherever Tab order
   would go next ([The edges](#the-edges-no-wrap)).
6. **Fallback**, only where geometry cannot decide: nothing focused, the focused control not laid out, or no candidate
   while the next (→ ↓) or previous (← ↑) control in Tab order has no frame, so could lie that way. Then the arrow does
   what it does today, and goes to that control.

Tab and Shift-Tab are unchanged. Left and Right between a split view's columns (`FocusManagerColumns.swift`) still come
first. Like today's arrows it never leaves the active section, so a sheet, an alert or a popover keeps the arrows. ↓
then ↑ need not return where you started; SwiftTUI and tvOS don't promise that either.

**Frames** come from what the frame already records: every hit-test region a focusable control draws carries its focus
id (`HitTestRegion.focusID`, which `ScrollView`'s reveal and the cursor-follows-focus experiment read too). The render
loop hands the frame's region array to the focus manager, only in geometric mode. A control drawn in pieces is the
smallest rectangle holding them. A control a scroll view has clipped is where its corners say (below). A control with
no region this frame (a custom `Focusable` that draws none, one cut by a clip that isn't a scroll view's, a lazy row not
built) is not a candidate, and the fallback reaches it in Tab order where it is the next control that way.

## Controls out of sight

The owner, 2026-11-08: "it should work no matter whether the destination control is in frame or not, and irrespective
of whether it was drawn in the previous frame. e.g. in a long and wide grid inside a much smaller ScrollView, arrow keys
should be sufficient to move amongst all items in the grid, scrolling as necessary."

So the arrows go by where a control is in the layout, not by where the last frame showed it.

**What TUI knows about a control it doesn't show.** A `ScrollView` lays out and draws its content, then keeps the
viewport's window of it. A plain `VStack` or `HStack` inside draws every row, as SwiftUI builds every child of an eager
stack, and a flat `LazyVGrid` measures and draws every cell ("lazy" there is the API's shape). So every control has a
frame in the scroll view's content, and the clip is what throws it away: the hit-test region of a control past the
viewport's edge is dropped, and that of one half past it trimmed. A lazy stack (`LazyVStack`, `LazyHStack`, a sectioned
grid) builds only its window: the rows meeting the viewport, one more past each edge, and the focused row with its
neighbours ([Locating things without drawing them](<../Layout and scrolling/Locating things without drawing them.md>), §5d
and §5g). `List` and `Table` are one focus stop each; their rows are not stops, and their own arrows move between them.

**Frames past the edge.** Under `TUI_ARROW_FOCUS=geometric` a scroll view's clip leaves, for each focusable control's
region it trims or drops, two geometry markers at the corners the region had before the clip, carrying the control's
focus id (`FocusFrameMarkers.swift`). A geometry marker is a point that every later clip keeps whole and every shift
moves (it is how `GeometryReader` and pictures find themselves), so at the root they say where the control lies in
screen coordinates, beyond the viewport's edge: an enclosing scroll view's clip keeps the inner one's markers and adds
its own. The arrows' frame for a control is the union of the cells it drew and its corners. The markers have no area,
so nothing hit-tests them, and the readers that look a control up by its focus id (the reveal, the caret, a keyboard
drag's target) skip markers, so they still see only drawn cells.

**Scrolling.** Moving the focus is all the arrow does. The scroll views around the control see the focus change on the
next frame and reveal it as they reveal a control Tab reached, by as little as shows it, on both axes; the innermost
first, since it draws first, and then the one around it, which by then finds the control drawn in its content. No
second path.

**Lazy stacks: the honest limit.** Nothing is computed for rows a lazy stack has not built: no index-to-position
arithmetic, no measuring on demand. It isn't needed for the moves an arrow makes: the next row each way is always
built (the margin past the viewport, and the focused row's neighbours), and an arrow goes to the nearest control, which
in a grid or a column is in the next row. Where the next row holds no control (a header, a blank row), the one after
it may be unbuilt: geometry then has no candidate that way, and the arrow stops, as Tab order would short of the
unbuilt rows too. A lazy stack whose rows hold controls only every second row or more can stop an arrow
short; a uniform grid or list of controls cannot.

**Tests** (`GeometricArrowScrollingTests`): twenty rows of twenty buttons in a 30 × 10 `ScrollView` that scrolls both
ways, as a `VStack` of `HStack`s, a `LazyVStack` of them and a `LazyVGrid` of twenty fixed columns. From the top-left,
→ reaches the end of the row and ↓ the bottom of the column, and a walk along every row with ← → and ↓ visits all four
hundred, each one drawn whole on screen once focused. Through a horizontal scroll view inside a vertical one, ↓ from a
button at the top goes to the button below it at the end of the inner row, past both views' edges, and both scroll to
show it.

### The edges: no wrap

The first version fell back to Tab order whenever no candidate lay that way, and noted that repeated ↓ in three rows of
three walked the first column and then the bottom row, and asked whether ↓ should wrap from the foot of a column to the
top of the next. The owner, 2026-11-08: "no, it should not wrap".

That fallback was itself a wrap wherever the Tab order turns a corner: → at the end of a row went to the next row's
start, and in a grid laid out as columns ↓ at the foot of one went to the top of the next, exactly the move ruled out.
It existed to reach controls the frame had not drawn; once controls scrolled out of sight are candidates, at an edge of
the layout the Tab-order neighbour is almost always a control geometry can place, lying some other way. So at an edge
the focus now stays, and Tab order is the fallback only to a control with no frame, which might lie that way (rule 6).
One arrow alone now walks one row or one column; the four together reach every control, in a grid on screen or one
far larger than its scroll view (`GeometricArrowFocusTests.noWrap`, `.reachable`; `GeometricArrowFallbackTests`;
`GeometricArrowScrollingTests`).

## What having both modes costs

Measured on the commit that added it, counting code lines (no comments, no blank lines):

| | Sources | Tests |
|---|---:|---:|
| **Geometry itself**: candidates, ranking, frames (`FocusManagerGeometricArrows.swift`), the regions kept and handed over, the arrow calling it first | ~80 | ~170 |
| **Only to keep both modes**: the `ArrowFocus` enum and its reading of `TUI_ARROW_FOCUS` (7), the manager's mode and its accessor (5), the app runner setting it (1), the headless app's and `TestApp`'s accessors (8), the variable's documentation entry (4); and two conditions on existing lines, the render loop's and the geometric arrow's | ~25 | ~15 |

- **Deleting the old mode**, were geometry to be the only one, would remove the ~25 and ~15 lines above and nothing of
  today's arrow code: Tab-order arrows *are* the fallback (now only to a control geometry cannot place), so
  `focusNextInSection()` and `focusPreviousInSection()` stay exactly as they are.
- **Deleting geometry** removes the one file (190 lines with comments) but for today's arrow switch, which moved into it
  from `Focus.swift` (`moveFocus(byArrow:)`, a dozen lines) and would move back; about 20 lines elsewhere; the test suite
  (238) and this note. Nothing else depends on it.

Reaching controls out of sight (2026-11-08) added about 45 lines of sources, all geometry but one: the corner markers
(`FocusFrameMarkers.swift`, 31), the scroll view's two clips leaving them (about 10), and the readers that skip them
(3); the one line that is the mode, `keepsFocusFrames`, goes with the plumbing above. Its tests are another 177.

So having both costs about a third as much code as geometry itself, all of it plumbing that a decision either way
removes in one commit. No third mode is hidden in it: the fallback is the old mode, not a copy of it.

**Run time.** With the default: one enum comparison per frame and one per arrow no control used, and no frames kept.
Geometric: per frame, the region array the mouse dispatcher already holds is shared (a reference, not a copy); per
arrow, one pass over the frame's regions into a dictionary by focus id and one over the active section's controls,
so a few hundred small steps, done once per key press, not per frame.

**Frames out of sight.** With the default, a scroll view's frame asks the environment's focus manager for the mode
once (`RenderContext.keepsFocusFrames`) and adds nothing; the readers that look a control up by focus id test one bit
more, on the regions that carry that id. In geometric mode, each scroll view's frame makes a second pass over its
content's regions and leaves two zero-area regions for each focusable control it cuts: 800 for a 20 × 20 grid of
buttons in a 30 × 10 viewport. Measured on that grid (`GeometricArrowScrollingTests`'s, debug build, 400 frames each
moving the focus, three runs of each mode alternating, 2026-11-08, with another lane's gate on the machine): 5.70 to
5.76 s in Tab-order mode against 5.64 to 5.82 s geometric, about 14 ms a frame either way: the difference is inside the
noise.
