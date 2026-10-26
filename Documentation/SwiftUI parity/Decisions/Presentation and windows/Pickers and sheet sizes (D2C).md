# SwiftUI API completion — lane D2C (controls): new judgement calls

*Lane D2C implemented the owner's decisions A54, B13, B14, A49 and A20
(2026-10-05). Each call below came up on the way. The safe option shipped;
the alternative and its price are given. Numbered as the main decisions
document is: A = owner decision, B = basic shipped, C = declined.*

## B. Shipped the safe option

### B-D2C-1. A segmented picker's Return chooses, where macOS's does nothing

*`SegmentedPickerStyle`, `PalettePickerStyle` (decisions B13)*

**Measured on macOS 15.8** (a SwiftUI `.segmented` picker in an
`NSHostingView`, its `NSSegmentedControl` made first responder and sent key
events): the keyboard cursor starts on the selected segment; Left and Right
move it **without choosing** — the owner's note expected macOS to choose as
the arrows move, and it does not — wrapping at either end; **Space** chooses
the segment under it; **Return does nothing**.

**Shipped:** all of that, except that Return chooses too. The control keys
through the horizontal radio group's handler, where Return and Space both
choose, and Return is the activation key of every TUI control. The
arrows wrap here as on macOS, whatever `.radioButtonGroupEdgeBehavior(_:)`
says to radio groups around it.

**The alternative:** Return passes through, as macOS's does, so a default
button can take it. A flag on the shared handler; a quarter of an hour.

### B-D2C-2. A compact date picker's calendar takes the keyboard as it opens

*`CompactDatePickerStyle` (decisions B14)*

**Shipped:** Return or a click on a `.compact` field opens the `.graphical`
calendar in a popover, and the calendar takes the focus as it appears, so
the arrows move the day at once; Return closes it on that day, Escape or a
click outside just closes it. A TUI popover otherwise leaves the focus
where it was until a first key finds its content, which would spend that
key.

**Not measured:** what macOS's keyboard does while a compact picker's
calendar overlay is up. If it stays in the field, with the calendar
following it, then matching that makes the calendar a pointer-only
surface, which TUI's rule against mouse-only interactions forbids — so
the alternative is "the field keeps the keyboard and the calendar is
reached by Tab", an hour, and worth measuring first.

### B-D2C-3. `.form` is 25 rows tall

*`FormPresentationSizing`, `PresentationSizing.form` (decisions A20)*

The owner approved `.form` at `min(64, width)` columns and `.page` at
`min(96, width)` by the content area's height. The form's height was not
named, but `.form` has to propose one — `.automatic` on macOS is
`.form.fitted(horizontal: false, vertical: true)`, which means nothing
unless `.form` has a height to fit away.

**Measured on macOS 15.8** (an offscreen window presenting a sheet of
filling content): `.form` proposes **470 by 400 points**, `.page` **520 by
735**, and a sheet is never smaller than **100 by 80**.

**Shipped:** `.form` proposes `min(25, height)` rows — the measured 400
points over a typical terminal cell of 8 by 16 points, a cell twice as
tall as it is wide. (A points-per-column scale alone does not give it:
470 points into the approved 64 columns is about 7.3 points a column, and
400 points at that scale would be some 54 rows. With the cell's 2:1
aspect, the same 7.3 points a column makes 400 points about 27 rows;
the 8-by-16 cell makes 470 points about 59 columns, which the owner's 64
rounds up.)

**The alternative:** `.form` proposes its width only and fits the height.
A one-line change.

### B-D2C-4. No minimum sheet size

*`PresentationSizing` (decisions A20)*

macOS never makes a sheet smaller than 100 by 80 points (measured, above),
about 14 columns by 5 rows. A TUI sheet has always been exactly its
content, and a sized one keeps that: a fitted axis is as small as the
content is.

**The alternative:** impose 14 by 5 on every sheet. Ten minutes, and a
drawing change for every small sheet that exists today; not recommended.

### B-D2C-5. A sized sheet's boxes share its size in a stack, and size to content in a scroll view — nowhere else

*`PresentationSizing`, `PresentationDetent` (decisions A20)*

A sheet's size — a detent's height, a sizing's width and height — goes to
its box (`EnvironmentValues.sheetDetentHeight`, `sheetProposedWidth`), and a
box clears it for what is inside it. Boxes stacked in a `VStack` or side by
side in an `HStack` take it flexibly and share it. A `ScrollView` clears it
as a box does, so the boxes in one are their content's size, as SwiftUI's are
(measured on macOS 15.6: two `GroupBox`es in a `ScrollView` in a `.form`
sheet 400 points tall are 43 points each — as they are in a `VStack`, where
TUI's share the sheet because a terminal sheet has no material and its
box is what shows the size). Every other container passes the size on to
each box below, and each takes all of it: a `ZStack`'s boxes overlap at the
sheet's size, which is what a sheet of layers wants; a `Grid`'s first box
takes the sheet and the cells after it are not drawn; a lazy stack's first box
takes it and the rest are not drawn; a lazy grid's rows each take it, so the
sheet scrolls through boxes the sheet's height each.

**The fuller version.** The grid, the lazy stacks and the lazy grids clear
the size for their children as a scroll view does, so their boxes are their
content's size, as SwiftUI's are. A lazy stack's every walk takes its rows'
context from one of two helpers (its pinned-section scope), and a grid has
two entry points; a lazy grid's paths are still to be traced. An hour or two
with the tests, and a drawing change only for sheets that hold such a
container.

**Shipped 2026-10-18 (lane LAYOUT): the fuller version.** A `Grid` clears the
size on both axes at both its entry points, and a lazy stack along its own
axis in the two helpers every lazy walk takes its rows' context from, so the
boxes in either are their content's size, and a box in a lazy column still
spans the sheet's width, as one in a vertical scroll view does
(`SheetSizeContainerTests`). A lazy grid needed nothing: run on the base, its
boxes were their content's size already, which the test now guards. A
`ZStack` passes the size on, as before.

## Found on the way

Not decisions; recorded so they are not lost.

- **A `.contextMenu` on a `List` row is a focus stop of its own.** A list
  of three rows each with `.contextMenu` puts three Tab stops *before* the
  list, which itself comes fourth (a scratch test of this lane's). That is
  why the tabs' context menus (A49) register no stop and open from the
  sidebar list's own Shift+F10. It bears on A30 (full SwiftUI context
  menus), which may want the same for list and table rows. **Done for list
  rows (2026-10-14):** a row's `.contextMenu` reports itself to the list
  (`RowEditRestrictions.rowMenus`) instead of registering a stop, and the
  list's Shift+F10 opens the cursor row's (`RowContextMenuTests`).
- **`.onKeyPress(.return)` on a popover's content did not hear Return**
  with the focus inside it (the compact picker's calendar, focused through
  `FocusManager.focus(id:)` as it appeared). Worked around inside the
  calendar's own handler; not investigated. **Fixed (lane INPUT,
  2026-10-18):** no `onKeyPress` on a popover's content heard anything, Return
  or a letter. The popover's claim on Escape grabbed the input as an open
  drop-down menu's does, and such a claim silences the whole focus path
  (`InputHandler.focusPathHearsKeys`); the popover's claim no longer grabs
  it, and its modal section still keeps the app's keys off the page behind
  it (`PopoverReturnKeyTests`). The calendar's own handling of Return stays:
  it is the control's key, as a list row's Return is.
- **A sidebar's rows are composed afresh every frame.** In a
  `.sidebarAdaptable` tab view of six tabs, 50 by 14 (`TabInteractionsMemoTests`'
  harness), every row is drawn twice per frame — once 7 by 1 and once 7 by 11
  — and on a quiet frame all twelve draws are composed, none served; only the
  measure is (the row memo keeps one entry per row, keyed by its size). That
  holds with or without the tabs' context menus. With menus the rows could not
  be served across frames anyway: a tab's menu is an `AnyView` built afresh
  whenever the body that makes the tab view runs, and an `AnyView` is keyed by
  its box. Not investigated further; it bears on what a sidebar costs, with
  the tabs' interactions (A49) or without. **Investigated (lane INPUT,
  2026-10-18), not fixed:** the second draw is the list's overflow check.
  `_ListCore.rowsOverflow` reads each row's resolved buffer to add up its
  height, and resolving a row renders it, for real, at the list's whole
  height (7 by 14 at 50 by 14 without menus, the case the lane measured);
  the drawing then renders it at its own, 7 by 1. The row memo keeps one
  entry per row, keyed by its size, so each render evicts the other's and no
  draw is ever served (on a quiet frame: 30 rows composed, 1 served while
  drawing). Either the overflow check measures the rows rather than render
  them (a row's height is all it reads), or it offers each row the height it
  will draw at. On the lists' hot path, so an A/B decides it; queued for a
  lists lane (decisions-INPUT, "Found on the way").
