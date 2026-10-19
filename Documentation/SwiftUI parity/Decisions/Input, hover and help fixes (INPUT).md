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

### B-INPUT-2. A modifier-key alternate's shortcut is live only while the alternate is drawn

*`View.modifierKeyAlternate(_:_:)`, `View.keyboardShortcut(_:modifiers:)` on
the alternate*

The three known defects of decisions-D1K B-D1K-2 are fixed: the modified view
is walked unseen while its alternate shows, and the focus goes back as the
keys are released. The shortcut half of that entry's fuller version is not.
SwiftUI makes an alternate in a menu an alternate menu item, live whether or
not the menu is open, with the modified view's shortcut plus the alternate's
modifiers (⌥⌘S for Save All under Save's ⌘S), or with a shortcut written on
the alternate itself. Here the alternate's control, and any shortcut on it,
exists only while its keys are held and it is drawn.

**Shipped:** as before: write the shortcut on the alternate where it should
be reachable, and it is live while the alternate is drawn.

**The fuller version:** walk each alternate unseen while the modified view is
drawn, as the modified view is now while its alternate is, with the real
shortcut registry and every other channel thrown away; plant the derived
shortcut (the modified view's claimed shortcut read through its
`KeyboardShortcutModifier`, with the alternate's modifiers added) where the
alternate names none, in a menu only, as SwiftUI does; and keep that walk's
lifecycle from running, since an alternate's `onAppear` must wait until it is
drawn — a render mode no walk has yet. About half a day, and a hidden render
of every alternate on every frame that has one.

### B-INPUT-3. Shift-clicks are asked for app-wide, not on Apple Terminal, and `TUIKIT_SHIFT_CLICKS=0` turns them off

*XTSHIFTESCAPE (`CSI > Ps s`); the Ghostty study's C5, phase 3's V6*

The policy was settled (the study's Q1, owner 2026-10-04: only while a
Shift-click consumer is focused now, app-wide once A13's own drag selection
shipped; A13 has). Two calls the study left open:

- **Not on Apple Terminal.** Its reading of `CSI > … s` is unmeasured, and a
  parser that ignored the `>` would take it for SCOSC and save the cursor.
  It needs nothing either: it has no Shift bypass, and reports the Shift bit
  on a click. So TUIkit sends nothing there, rather than risk a sequence for
  no gain. The other hosts get it whatever they document: one that ignores it
  is unchanged.
- **`TUIKIT_SHIFT_CLICKS=0`** keeps it from being sent anywhere: the user's
  way back to the terminal's own Shift-click and Shift-drag, as
  `TUIKIT_KEYBOARD_PROTOCOL=0` is for the kitty protocol (B-D1K-4). A new
  user-facing switch, so recorded.

**Shipped:** as above (`Terminal.capturesShiftClicks`, `applyMouseSupport`,
`inputModesOwed`; `TerminalOutputTests`).

**The fuller version:** measure it per host by hand (`mouse_probe.py` with
`PROBE_SHIFT_ESCAPE=1`, Shift-click and Shift-drag with and without), and a
programmatic override for an app, as `TerminalClient.hyperlinkSupport` is for
links. About an hour of hand measurement on five hosts and tmux; the override
a quarter of a day, and nothing yet says an app needs one.

## Found on the way

Not decisions; recorded so they are not lost.

- **A list's rows are composed twice a frame, and never served while
  drawing** (decisions-D2C's "sidebar rows composed afresh", investigated
  here). `_ListCore.rowsOverflow` resolves each row's buffer to add up the
  rows' heights, which renders the row at the list's whole height, and the
  drawing renders it again at its own height; the row memo, one entry per row
  keyed by size, never keeps the one the next draw asks for. Measured on a
  six-tab `.sidebarAdaptable` sidebar at 50 by 14: 30 rows composed and 1
  served while drawing on a quiet frame. A plain `List` whose rows fit its
  height reaches the same check (read from the code, not measured): more
  rows than lines answer it by counting, without resolving any. The fix — measure the rows in the overflow check, or offer them
  their drawing height — is on the lists' hot path and wants an A/B, so it is
  queued for a lists lane rather than made here.
- **`HeadlessApp.focusedID`**: added for `PopoverReturnKeyTests`, the focused
  control's id, so a script can ask where the focus is.
