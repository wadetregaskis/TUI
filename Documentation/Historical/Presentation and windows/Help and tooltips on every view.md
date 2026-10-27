# Help and tooltips on every view

*How `.help(_:)` came to work on views that cannot take the focus, how hover
help behaves in the status bar, the keyboard route to it, and `HelpLink`.
Ids: A-HELP-1, B-HELP-1, B-HELP-2, B-BUGS13-2, C5. The live design is
[Tooltips and help in a terminal](<../../Controls and presentation/Tooltips and help in a terminal.md>).*

## In short

Any view's help shows when the pointer rests on it; `.tooltips(.always)` shows
every panel at once, avoiding one another. The keyboard route is ⌥? (where
Option arrives), Shift-F1 at the lowest priority, and a menu-bar item.

## How it unfolded

1. **2026-10-12, the owner:** "non-focusable views should support it, too. At
   the very least they can show the tooltip when hovered over by the mouse."
   Lane HELP built it that day; a flicker in the status bar was fixed (A-HELP-1,
   decided: option 1).
2. **2026-10-13, lane BUGS13** fixed hover leftovers (B-BUGS13-2).
3. **2026-10-23 and 26, B-HELP-2:** '?' reveals all where nothing has help; then
   Shift-F1 at the lowest priority, ⌥? toggling all help, and a menu-bar item
   (built 2026-10-26).

## For a future reader

- **Owed:** what each terminal sends for Shift-F1, measured with
  `key_probe.py` (the survey's help-key table has the row).

## The record

### A-HELP-1. A hover tooltip in the status bar flickers over a page laid out in the middle — decided: option 1, fixed for a page the bar moves

**Decided 2026-10-12 by the coordinator: option 1. Fixed for a page the bar
moves; for the last rows of a page that fills the window since lane BUGS13
("Left open", below, says what is fixed and what is still open).**

**Found while pinning hover on a non-focusable view through the run loop**
(`HelpRunLoopTests.hoverOverACentredPage`; not caused by this lane, and older
than it). The status bar grows upwards for a tooltip (Tooltips §4, "Bar grows
and shrinks with the tooltip"), so the page above it loses a row or more. A
page laid out in the middle of the window (as a `WindowGroup` lays out one
that does not fill it) moves up with it; the view slides out from under the
resting pointer; the dispatcher re-resolves the hover after the reshape and
reports `.exited`; the tooltip goes, the page moves back under the pointer,
`.entered` arrives, and the delay starts again. Measured headless at 50 × 14
with the default style and delay: the help was on screen for one frame in
every 0.6 s. Once a walk's change to the bar asked for its frame (the review
fix e73abfced), it was on screen for one frame and did not come back while
the pointer rested: the re-entry came after the walk, and nothing woke for its
delay. A page laid out from the top (most pages: a title, then a scroll view)
does not move, but its last row is covered: see "Left open" below. The
popover moves nothing and was not affected.

Options, as offered:

1. **Hold the hover through the tooltip's own reflow (recommended; chosen).**
   In a frame whose bar rows changed because of a tooltip, the hover
   transitions the reshape synthesises are not hover changes: the candidate
   stays, marked displaced, until the pointer next moves and does not land on
   its view again. No visual change. It covers anything the bar's growth
   moves, but not a row the bar's growth covers ("Left open", below).
2. **Reserve the row always**, §4's own fallback: one row of every app's page,
   permanently, and a help text that wraps to two rows still moves the page.
3. **Draw a hover tooltip's bar over the foot of the page** instead of
   shrinking it: a change to the presentation §4 chose.

**What was built.** The run loop notes a frame whose status-bar tooltip
changed the rows the bar takes from the page
(`RenderLoop.resolveStatusBarTooltip`, `StatusBarState.linesAboveItems`) and
marks the reshape that publishing the frame's regions makes
(`RenderLoop.publishHitTestRegions`). An exit in that reshape moves the hover
candidate to `TooltipState.held`, which is shown in preference to the
candidate the pointer is really over, until:

- the pointer moves to another cell (`TooltipState.notePointerMoved`, told by
  the dispatcher), and the move does not put it on the held view again; one
  that does takes it back, its delay served;
- or no pointer could rest on the held view any more: gone from the screen,
  or behind something that takes the hover, such as a sheet's backdrop
  (`MouseEventDispatcher.reachesHoverObserver`, asked as the reshape closes).

Only the tooltip holds: the controls and the other hover observers
(`.onHover`) hear the transitions as before, since the pointer is over
something else. While the help is held, the view now under the pointer may
light its own hover face, and a view with help that the reshape put under the
pointer becomes the candidate once the held one goes. A related gap closed
in the same round: a view with help that a reshape slides under a resting
pointer gets the wake at the end of its delay (`RenderLoop.requestTooltipFrames`).
Pinned by `HelpRunLoopTests`: `hoverOverACentredPage` (every frame drawn),
`hoverRestsOverACentredPage` (only the frames something asks for),
`heldHelpStaysOnItsView`, `heldHelpGoesWithItsView`.

**Left open** (found by the lane's last review; queued):

- **The last row of a page that fills the window — fixed (lane BUGS13).**
  There the bar's new row does not move the page; it covers the page's last
  visible row. The hold found the hovered view unreachable
  (`TooltipState.endReshape`) and dropped it in the same frame. The next
  frame emptied the bar and the row came back under the pointer, but no
  `.entered` arrived (next item), so the help was on screen for one frame
  and did not return while the pointer rested; once the next item was fixed,
  the row's re-entry restarted the delay, and the help showed in every
  other frame drawn and the app never idled. A bordered chrome style's bar
  can take up to three rows, so up to three rows are affected. The review's
  input: `WindowGroup { ScrollView { VStack(alignment: .leading, spacing: 0)
  { ForEach(0..<40, id: \.self) { Text("row \($0)").help("HELP-\($0)") } }
  } }.mouseSupport(.full)` at 50 × 14, the pointer resting on the last
  visible row. Now a row covered by the tooltip's own bar still counts as
  its view's: the chrome host records the rows the bar took from the page
  for its tooltip (`WindowChromeState.tooltipRows`), and a held help stays
  while the pointer rests on one of them. Pinned for every chrome style and
  a help of one line and of two (`HelpRunLoopTests.hoverOnARowTheBarCovers`).
  A sheet, docked under the page or not, an alert, a popover or a menu
  presented over the page while the pointer rests there takes the help
  away: the hold on the covered rows lasts while as many surfaces are
  presented over the page as when it began, counted from the layers the
  window composites, which every presentation is drawn as
  (`TooltipState.heldPresentations`,
  `WindowChromeState.presentationsOverPage`; the lane's review found the
  help left in the bar over a sheet a key presented, and its second review
  over a sheet docked live, which never holds the input,
  `HelpRunLoopTests.heldHelpOnACoveredRowGoesUnderASheet`).
  Left: a pointer that moves along a covered row lets the help go, the row
  comes back under it, and the help returns after its delay — fixed (lane
  INPUT, 2026-10-18): a move along the rows the bar took keeps the hold
  (`TooltipState.notePointerMoved(toRow:)`); a frame that takes one surface
  down as it puts another up kept the help, the count unchanged — fixed
  too: the surfaces are compared, each by its kind and the identity of its
  content (`WindowChromeState.presentationsOverPage`, `PresentedSurface`,
  `OverlayLayer.surfaceIdentity`; by its first hit region until the lane's
  review found a cover's to be its first control's, which changes while the
  cover stays up); and a
  view removed from the page while the pointer rests on its covered row
  keeps its help up until the pointer moves — still open (decisions-INPUT
  B-INPUT-1): a covered row has no region to probe, and a row a scroll view
  windows out registers nothing either, so nothing yet tells a covered
  view from a removed one (`HeldHelpResidualTests`).
- **No `.entered` for a view a reshape slides under a pointer resting on
  nothing — fixed (lane BUGS13).** The dispatcher re-resolved the hover
  after a reshape only for a lane that was already hovering something (the
  guard in `MouseEventDispatcher.reconciled`). Older than this lane; it
  affected `.onHover` too, whose view heard `.entered` only when the pointer
  next moved. Now a lane resting on nothing enters the control or hover
  observer a reshape puts under the pointer, once, while motion is reported
  (`HoverReshapeTests.reshapeEntersFromNothing`,
  `HelpRunLoopTests.reshapeSlidesAViewUnderAPointerOnNothing`). Reported as
  of the last frame, which an `.onHover` or a help asked for motion in: the
  review found the first fix asked the scene's base instead, which the walk
  sets mid-frame and which has no motion unless the scene declares it, so it
  did nothing in such an app
  (`HoverReshapeRunLoopTests.slidUnderWithoutDeclaredMotion`). Only where
  the pointer is known to rest: the lane's second review found the reshape
  entering what it slid under the cell of the last move after a page that
  asked for no motion, a Ctrl-Z or a drag had left that cell behind, so a
  help showed for a view the pointer was not on. The dispatcher keeps where
  the pointer rests from every report of its motion, a drag's included, and
  forgets it when the reporting stops covering motion and at a suspend
  (`MouseEventDispatcher.restingPosition`,
  `HoverReshapeRunLoopTests.noEntryAfterAGapInReporting`,
  `HoverReshapeTests.reshapeEntersOnlyWhereThePointerIsKnown`). Not the
  control a reshape took the lane off, until the pointer moves: the lane's
  review found that an `.onHover` whose change moves its own view out from
  under the pointer then flickered at frame rate, entered, exited and
  entered again, and the app never idled
  (`MouseEventDispatcher.leftByReshape`, since 2026-10-18 every control
  since the last input, and one resting under the pointer until it moves,
  `HoverReshapeTests.reshapeDoesNotReenterWhatItLeft`,
  `HoverReshapeRunLoopTests.selfDisplacingHoverSettles`; decisions-BUGS13
  B-BUGS13-2).
- Smaller: under the popover style, when a reshape slides a second view
  with help under a pointer resting on a shown panel, the old panel stayed
  up for at most the delay — fixed (lane BUGS13): the frame after the
  reshape is asked for (`RenderLoop.publishHitTestRegions`,
  `HelpRunLoopTests.popoverGoesWhenAReshapeReplacesItsView`); held help
  outlives reshapes the bar did not cause while its view stays reachable —
  fixed (lane INPUT, 2026-10-18): the hold records where the bar's last
  reflow left its view, and a reshape the bar did not cause that finds the
  view elsewhere lets it go (`TooltipState.endReshape`, `heldRegion`). The
  bar's moves are told from the page's own by whether the reshape's frame
  changed the rows the bar takes. A centred page that re-centres (a change
  of width anywhere on it) moves the view too, so its help goes, and if the
  bar's giving back its rows slides the view under the pointer again the
  help returns after its delay, once: the price this item named, taken; and
  `MouseEventDispatcher.reachesHoverObserver` probed only the top-left cell
  of the held view's region — fixed (lane BUGS13): it probes every cell of
  the view's regions until one is heard by the view
  (`HoverReshapeTests.hoverObserverReachablePastACoveredCell`).

### B-HELP-1. Under `.always` the panels are popovers whatever `tooltipStyle` says, and the bar lists nothing

The brief asked how the status-bar style should show `.always`'s many
tooltips: the hovered or focused one, or a list. Neither: `.always` keeps
drawing every panel as a popover (Tooltips §6, as before), and the panels now
avoid one another (§5, "Many panels at once"). Why not the bar:

- `.statusBar` is the **default** style, so most apps that turn on `.always`
  never chose the bar. A list there would make `.always` mean a different
  thing depending on a setting the app did not touch.
- The bar's rows are reserved **before** the walk that finds the views with
  help, so a list would be a frame late, and its height would move the page
  that decides which views are on screen: a list that resizes the content it
  lists.
- A list loses where each view is; the panels keep it.

The hovered view's and the focused view's panels are placed first instead
(`TooltipState.placementRank`), so on a page too dense for every panel,
pointing at a view or focusing it brings its panel back.

**Fuller version and price.** A legend: a short numbered marker drawn beside
each view with help and the texts listed against the numbers in the bar,
taking the bar's rows from last frame's list. About one to one and a half
lane-days, mostly the feedback between the list's height and the page.

### B-HELP-2. No keyboard route to a non-focusable view's help beyond `.always`

A keyboard reader reaches a `Text`'s help only while the app shows every panel
(`.tooltips(.always)`); `?` and `.onFocus` act on the focused control. The owner
punted a "help browse" mode, and it is not built. One route nearly falls out
now that the panels avoid one another: **`?` when the focused control has no
help** (today it falls through unconsumed, case C of MISC12 §3.2) **could show
the screen's panels, and `?` again hide them.** Not built here because it is
more than the key: the reveal must reach views stored in the render cache (a
screen-wide flag whose change clears what the memo kept), and the key may only
be consumed when there is help on screen to show, which needs every
`help(_:)` to register itself in a way that replays when its row is served
from the memo, as `requestFeature` does. About half a lane-day to one, with
tests; and whether `?` should take on that meaning is yours to say.

What an app can do today is what the Example's Help & Tooltips page does: offer
the trigger as a setting the keyboard can reach, so `.always` is one choice
away.

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

**Fuller version shipped (lane INPUT, 2026-10-18).** The event funnel notes
every input it dispatches — a key, a modifier key, any report from the mouse
(`MouseEventDispatcher.noteInput()`, from `AppRunner`, `HeadlessApp.send` and
`dispatch(_:)` itself) — and the dispatcher remembers every control a reshape
has taken a hover lane off since the last one
(`MouseEventDispatcher.leftByReshape`, replacing the per-lane
`HoverSlot.leftByReshape`). No reshape enters one of them, whether the lane
rests on nothing or on another control, so the loop through two hover views
goes round once and settles, and a row a key scrolls away and back is
entered again without waiting for the pointer
(`HoverReshapeTests.reshapeLoopThroughTwoControlsSettles`,
`.inputLetsALeftControlBeEnteredAgain`;
`HoverReshapeRunLoopTests.twoViewLoopSettles`, `.keyMovedRowIsEnteredAgain`).
An input forgets only the controls that are not under the resting pointer:
the lane's review found that forgetting the one an `.onHover` had settled
on, resting under the pointer unentered, entered it again at every key
typed anywhere, and it flickered once per key
(`HoverReshapeTests.inputDoesNotReenterWhatSettledUnderThePointer`,
`HoverReshapeRunLoopTests.selfDisplacingHoverStaysSettledThroughKeys`).

### C5. `HelpLink(anchor:)` and `HelpLink(anchor:book:)`

*`HelpLink.init(anchor:)`, `HelpLink.init(anchor:book:)`*

Both open an anchor in an Apple Help book, through AppKit's `NSHelpManager`
and the Help Viewer. A terminal app has no help viewer to open, and Linux and
Windows have no help books. `HelpLink(action:)` and `HelpLink(destination:)`
ship, so a help button that runs code or opens a URL ports as written.
