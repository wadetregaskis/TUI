# Completing the SwiftUI API: lane BUGS13's judgement calls

*Lane BUGS13, 2026-10-13, fixed five defects the last lanes' agents and
reviews found: an idle render storm while a sheet is up, the hover help
leftovers of decisions-HELP A-HELP-1, an alert's buttons and a windowed
stack's off-window row drawing their overflow over the views after them, and
a frame placing a ragged `Text` line by line. One of them, and one fix its
review asked for, needed a judgement no earlier decision settles; they are
written up here.*

*The format is that of
[`SwiftUI API completion decisions.md`](<SwiftUI API completion decisions.md>):*

- **A-BUGS13-n — needs your decision.**
- **B-BUGS13-n — shipped the safe option.** Says what the fuller version
  would be, and its price.
- **C-BUGS13-n — declined.** With the reason.

There is no A or C entry.

## B. Shipped the safe option

### B-BUGS13-1. A `@FocusedValue` drawn as a backdrop reads the values for the live focus

*`@FocusedValue`, `@FocusedBinding`; the page beneath a sheet, an alert or a
context menu, a `.dimmed()` view, a covered navigation page*

A view drawn as a backdrop renders under a throwaway focus manager that
focuses nothing (`RenderContext.isolatedForBackground()`), which shares the
live manager's focused values. Its own `@FocusedValue` read them at the
throwaway's focus, so it was handed the scene values alone, while the end of
the pass repeated every reading at the live focus. With a focused value on the
live focus's path (the sheet's focused control publishing one), every pass
found the backdrop's reading stale and asked for another frame: the app never
idled while the sheet was up (measured headless before the fix: a frame asked
for on every frame).

The page beneath a sheet has to read one of two things, and the choice is
what it shows:

1. **The values for the live focus (shipped).** A reader on the page shows
   what a reader on the live page shows: while a sheet is up, whatever the
   sheet's focus path publishes, and the scene values. The registry knows the
   manager that made it, and a reading follows that manager's focus, which is
   the focus the end of the pass repeats it at, so the two cannot disagree
   (`FocusedValueRegistry.owner`, `tableAtTheFocus()`). It is also what a class
   property's `@FocusedValue` already read behind a sheet: it never takes a
   backdrop's manager (75c2c226c), so the two spellings of one reader now agree.
2. **The scene values alone, as if nothing were focused.** The page would show
   what it shows with the focus nowhere; the end-of-pass check would have to
   repeat each reading at the focus it was made for. A reader that showed the
   selected note beside a list would show "nothing selected" behind every
   sheet, since the list is not on the sheet's focus path either way, and the
   two spellings of one reader would disagree.

SwiftUI is unmeasured here: on macOS a sheet is a window of its own, and
which window's focus a view in the window beneath it reads was not probed.

**Fuller version and price.** A backdrop that shows the page as it was when
the sheet came up, its readers frozen at that frame's values: a snapshot of
the registry's reading per presentation, kept while it is up and dropped with
it. About half a day with tests; it would make the page beneath a sheet
honest about being a picture, but it is a different contract from SwiftUI's
live window beneath, whichever focus that window reads.

### B-BUGS13-2. A view a reshape took out from under a resting pointer is not entered again by a reshape until the pointer moves

*`.onHover`, `help(_:)`, a control's hover face; a reshape under a resting
pointer (`MouseEventDispatcher.reconciled`)*

The lane made a reshape enter a view it slides under a pointer resting on
nothing (decisions-HELP A-HELP-1, "Left open"). Its review found the loop
that opened: an `.onHover` whose change moves its own view out from under the
pointer, such as one that shows a line of details above its row, was entered,
moved away and exited, moved back and entered again, a frame each, and the
app never idled. Before, a lane resting on nothing was never re-resolved, so
the exit ended it.

A lane a reshape took off a control now remembers that control, and no
reshape puts it back on it until the pointer next reports motion
(`HoverSlot.leftByReshape`, by the control's interned id). Any other view a
reshape slides under the pointer is entered. So the page above enters once,
exits once and settles with the row unlit under the pointer, as it did before
the lane, until the pointer moves.

What it does not catch, and did not before the lane either: a loop through
two hover views, an `.onHover` whose change puts ANOTHER view with hover under
the pointer and takes it away again as it leaves. Each reshape moves the lane
from one control to the other, and the lane never rests on nothing. SwiftUI is
unmeasured: the probes host SwiftUI offscreen and cannot rest a pointer.

**Fuller version and price.** Tell a reshape that the hover handlers' own
changes caused from one an input caused: a count of the inputs dispatched
(keys, clicks, the wheel, a pointer move) that the event funnel bumps, and a
lane that remembers every control a reshape took it off since the last input,
so that neither loop goes round twice, while a page the keyboard scrolls until
blank space is under the resting pointer, and back, lights the row it brings
back (today that row waits for the pointer to move). About half a day with
tests, mostly wiring the event funnel's entry points (`AppRunner`,
`HeadlessApp`).
