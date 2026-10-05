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
choose, and Return is the activation key of every TUIkit control. The
arrows wrap here as on macOS, whatever `.radioButtonGroupEdgeBehavior(_:)`
says to radio groups around it.

**The alternative:** Return passes through, as macOS's does, so a default
button can take it. A flag on the shared handler; a quarter of an hour.

### B-D2C-2. A compact date picker's calendar takes the keyboard as it opens

*`CompactDatePickerStyle` (decisions B14)*

**Shipped:** Return or a click on a `.compact` field opens the `.graphical`
calendar in a popover, and the calendar takes the focus as it appears, so
the arrows move the day at once; Return closes it on that day, Escape or a
click outside just closes it. A TUIkit popover otherwise leaves the focus
where it was until a first key finds its content, which would spend that
key.

**Not measured:** what macOS's keyboard does while a compact picker's
calendar overlay is up. If it stays in the field, with the calendar
following it, then matching that makes the calendar a pointer-only
surface, which TUIkit's rule against mouse-only interactions forbids — so
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
about 14 columns by 5 rows. A TUIkit sheet has always been exactly its
content, and a sized one keeps that: a fitted axis is as small as the
content is.

**The alternative:** impose 14 by 5 on every sheet. Ten minutes, and a
drawing change for every small sheet that exists today; not recommended.

## Found on the way

Not decisions; recorded so they are not lost.

- **A `.contextMenu` on a `List` row is a focus stop of its own.** A list
  of three rows each with `.contextMenu` puts three Tab stops *before* the
  list, which itself comes fourth (a scratch test of this lane's). That is
  why the tabs' context menus (A49) register no stop and open from the
  sidebar list's own Shift+F10. It bears on A30 (full SwiftUI context
  menus), which may want the same for list and table rows.
- **`.onKeyPress(.return)` on a popover's content did not hear Return**
  with the focus inside it (the compact picker's calendar, focused through
  `FocusManager.focus(id:)` as it appeared). Worked around inside the
  calendar's own handler; not investigated.
- **A sidebar's rows are composed afresh every frame.** In a
  `.sidebarAdaptable` tab view of six tabs, 50 by 14 (`TabInteractionsMemoTests`'
  harness), every row is drawn twice per frame — once 7 by 1 and once 7 by 11
  — and on a quiet frame all twelve draws are composed, none served; only the
  measure is (the row memo keeps one entry per row, keyed by its size). That
  holds with or without the tabs' context menus. With menus the rows could not
  be served across frames anyway: a tab's menu is an `AnyView` built afresh
  whenever the body that makes the tab view runs, and an `AnyView` is keyed by
  its box. Not investigated further; it bears on what a sidebar costs, with
  the tabs' interactions (A49) or without.
