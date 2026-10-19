# Completing the SwiftUI API: decisions from lane INPUT

*Lane INPUT, 2026-10-18, worked through the open input, hover and help
items: the input parser's nested edges, a right-drag over a text editor,
timed gestures and drag velocity (B91, B92), a disabled view's gestures
(B-F2-2), the pointer leaving the window, a reshape loop through two hover
views (B-BUGS13-2), nested hover observers (semantic audit item 31), the held
help's residual cases (decisions-HELP A-HELP-1, "Left open"), and the items
listed below. Where a call needed judgement the safe option shipped, and is
written up here.*

*The format is that of
[`SwiftUI API completion decisions.md`](<SwiftUI API completion decisions.md>):*

- **A-INPUT-n — needs your decision.**
- **B-INPUT-n — shipped the safe option.** Says what the fuller version
  would be, and its price.
- **C-INPUT-n — declined.** With the reason.

## B. Shipped the safe option

### B-INPUT-1. A view removed from under the rows the status bar covers keeps its help until the pointer moves

*`help(_:)` under the default status-bar presentation, on a page that fills
the window (decisions-HELP A-HELP-1, "Left open")*

A help shown for a view on a page's last visible row makes the status bar
grow over that row, and the help is held while the pointer rests on the rows
the bar took (`TooltipState.held`). Of that hold's three residual cases, two
are fixed: a pointer moving along the covered rows keeps the help, and a
frame that swaps one presented surface for another lets it go. The third is
not: a view removed from the page (a key, a timer) while the pointer rests on
its covered row keeps its help up until the pointer moves.

Nothing tells a covered view from a removed one today. A covered row draws no
region the dispatcher could probe (`reachesHoverObserver` finds none), and a
row a scroll view windows out is not rendered at all, so it registers nothing
either: asking whether the help's handler was registered this frame would let
the hold go for every covered row, the case lane BUGS13 fixed.

**Shipped:** the hold as it was, for this case.

**The fuller version:** one of two.

1. **Let a covered-row hold go on any reshape the page makes on its own**: a
   frame whose bar rows did not change and whose regions did. Cheap (an
   equality test of the frame's regions against the last frame's, only while
   a help is held), but anything on the page that files changing regions —
   an animation with a hover face, a live list — would take the help away and
   bring it back after its delay. About two hours with tests.
2. **Keep every help view's identity filed per walk, replayed by a memo** (as
   gesture filings are, `EffectJournal`), and have a scroll view that windows
   rows out still file the helps of the rows next to its window: the hold then
   asks whether its view is still in the tree. Also what B-HELP-2's `?`
   reveal needs. About half a day, and a set insert per help view per frame.
