# Gestures, taps and the press a control takes

*How gestures were built for a terminal's pointer: what a control's press
does beside a gesture, distances in cells, drag velocity, timed recognizers,
double-click windows, taps and long presses as gestures, Shift-clicks, lost
taps, removed and disabled views, swipe actions, and what was declined. Ids:
B89 to B94, C15, A48, B-F2-1 to 3, B-ST3-1, B-INPUT-1, B-INPUT-3.*

## In short

`onTapGesture` and `onLongPressGesture` are gestures; timed recognizers run
on the frame clock; distances are cells; a drag's velocity is an average of
report-to-report speeds; a row and a tap have separate double-click windows.
A control takes a press once the gestures ahead of it give up, and cannot
wait for them. Shift-clicks are asked for app-wide (not on Apple Terminal).
Multi-contact gestures and the window drag are declined.

## How it unfolded

1. **B89 to B94** shipped the gesture system's terminal readings; lane INPUT
   (2026-10-18) built B91's velocity and B92's frame-clock timing, and fixed a
   disabled view's gestures (B-F2-2).
2. **Lanes F2 and ST3** fixed lost taps after a failed double tap and a
   removed view's gestures.
3. **2026-10-23, the owner** kept cells for distances (B90), asked what real
   benefit full recognizers would bring (B89), and preferred revealed in-row
   buttons for swipe actions (A48).
4. **2026-10-26, the owner:** build full gesture recognisers for every control
   now (B89); swipe actions as revealed buttons, ⇧→ / ⇧← to reveal, again for
   the full swipe, Ctrl-L / Ctrl-T fallbacks, `RowAction` rebindable, with a
   PTY trackpad-burst test (A48). A48 was built that night, its wheel replayed
   from representative bytes; B89 is not built yet.

## Where it stands

Shipped as the record says; **owed:** B89's full recognizers (ruled on
2026-10-26), and a real trackpad swipe recorded for A48's burst gap.

## For a future reader

- **B93's suggestion, unasked:** the row's double-click window could move from
  0.4 s to macOS's 0.5 s.

## The record

### B89. A control takes the press once the gestures ahead of it give up; it cannot wait

*`View.gesture(_:including:)`, `View.highPriorityGesture(_:including:)`,
`View.simultaneousGesture(_:including:)` (all forms), `GestureMask`*

The arena (`Sources/TUIFoundation/App/GestureArena.swift`) ranks every region under
a press: gestures, and the ordinary controls' regions — a `Button`'s press is
one of the view's own gestures and ranks as one, as measured. A gesture is a
recognizer: it sees every event, is held back while anything ahead of it is
undecided, and reports what it held back once released. A control is not: its
press handler acts at once. So a control is given the press when everything
ranked ahead of it has given up, and from then on owns the press as it always
did.

Where that differs from macOS:

- **A control never fails.** macOS's plain-style button fails when its press
  is released off it, and a `.gesture(DragGesture())` attached to it then
  reports its end. Here the button owns the press, and the drag never hears
  it.
- **A control behind an undecided gesture gets the press late.** Under a
  high-priority tap, a button draws no pressed state until the tap fails; a
  `.gesture(TapGesture(count: 2))` on a `List` row holds the row's selection
  back by the double-tap interval, since the list waits for the double tap to
  fail. (macOS's bordered `Button` is an AppKit control that ignores attached
  gestures altogether — measured: none of tap, high-priority, simultaneous,
  long press or drag ran on it. TUI's buttons are drawn, and follow the
  plain-style SwiftUI button, which was measured.)

**The fuller version** makes controls recognizers: each control's press
handler reports possible, recognized and failed, and accepts a cancel. A day
and a half — fifteen-odd controls, and every mouse test that reads a
control's press.

### B90. Distances are cells along either axis

*`DragGesture.minimumDistance`, `LongPressGesture.maximumDistance`, the tap's
slop*

SwiftUI counts Euclidean points: a drag starts at 10, a long press fails past
10, a tap fails past 40. **Shipped:** whole cells counted along either axis,
as `onLongPressGesture` already counted — one cell by default for the first
two (the smallest move a terminal reports), and five columns or two rows for
a tap (40 points over a typical 8×17-point cell). `DragGesture(minimumDistance:
10)` written for SwiftUI therefore asks for ten cells here, the §2.1 porting
note.

**The fuller version** measures in points: the terminal reports its cell size
in pixels (`TIOCGWINSZ`, CSI 16 t — `Terminal compatibility survey.md` records both
per host), so a distance could be converted and compared as SwiftUI compares
it. Half a day, and it reopens §2.1 for these three: a distance in points
would be the only `CGFloat`-like measurement in the API.

### B91. A drag's velocity is an average of the report-to-report speeds

*`DragGesture.Value.velocity`, `.predictedEndLocation`,
`.predictedEndTranslation`*

**Shipped:** each motion report's speed since the last one, in cells per
second from the times the reports arrived, averaged with the estimate so far.
A pointer held still sends no reports, so its velocity is the last motion's —
macOS keeps it too (measured: 658 points per second after 0.3 s still). The
predicted end is a quarter of a second on at that velocity, the horizon
SwiftUI defines its own velocity against (four times the predicted end's
distance from the location). macOS's estimator itself is unknown; on a
synthetic drag of 20 ms steps it runs below the instantaneous speed, a
smoothed estimate.

**The fuller version** fits the last 100 ms of reports by least squares, as
UIKit's pan recognizer does. Two hours; it matters only to fling physics.

**Fuller version shipped (lane INPUT, 2026-10-18; settled by the owner's
earlier rulings, open to veto).** The velocity is the least-squares slope of
the press and the moves of the last 100 ms up to the last report
(`DragSample.fit`), anchored at that report, so a pointer held still keeps
its velocity as on macOS. Where the window holds one report (a move after a
pause) or a burst read at once (reports under 1 ms apart, since TUI stamps
a report at dispatch), the fit reaches back to the report before. A pair read
at once no longer spikes it: 500,000 cells a second between two such reports
went into the average halved, where the fit reads the steady speed around them
(`LongPressAndDragGestureTests.dragVelocityThroughABurst`). At most 64 reports
are kept per drag.

### B92. Timed recognizers run on the frame clock

*`LongPressGesture`, `TapGesture` (its hold limit and its multi-tap wait),
`View.onLongPressGesture(minimumDuration:maximumDistance:perform:onPressingChanged:)`*

**Shipped:** the run loop ticks the arena at the start of each frame and wakes
for the next deadline, so a long press ends — and a double tap gives up — on
the first frame at or past its deadline, as `onLongPressGesture` already did.
A deadline starts at the first frame after the event that armed it rather
than at the event's own report time, a few milliseconds later; event-to-event
intervals (a tap's hold, a multi-tap's gap) use the report times.

**The fuller version** starts the deadline at the report time. In an app the
two clocks are one; in a test harness they are not, which is why they are
kept apart. An hour, with the harness's clocks joined.

**Fuller version shipped (lane INPUT, 2026-10-18; settled by the owner's
earlier rulings, open to veto).** A deadline runs from the time of the event
that armed it (`GestureTimer.arm(seconds:at:)`), and the first frame at or
past it ends the gesture. `InputChainHarness` reads its events on its frame
clock, as `HeadlessApp` already did, so the two clocks are one in every
harness too (its `syncEventClock()` is gone). `GestureDeadlineTests`.

### B93. Two double-click windows: a row's and a tap's

*`TapGesture(count:)`, `SpatialTapGesture(count:coordinateSpace:)`,
`View.onTapGesture(count:perform:)`; and, for comparison,
`List`/`Table` `onRowActivate(_:)`, `MouseEvent.clickCount`*

A tap counts its own clicks, as measured: the next click released within
0.35 s of the last release (a press in time but held past that gives the tap
up then, with the button still down). The dispatcher's `clickCount`, which rows open on, counts presses
within 400 ms of each other (macOS's `NSEvent.doubleClickInterval` is 0.5 s,
and `NSTableView` uses it). **Shipped:** both, each matching its macOS
counterpart's kind.

**The alternative** is one interval for both — 0.35 s, or the dispatcher's
0.4 s for taps too. Half an hour either way; the first slows nothing, the
second departs from SwiftUI's measured taps.

### B94. `onTapGesture` and `onLongPressGesture` are gestures now

*`View.onTapGesture(count:perform:)`, `View.onTapGesture(count:coordinateSpace:perform:)`,
`View.onLongPressGesture(minimumDuration:maximumDistance:perform:onPressingChanged:)`*

They were mouse handlers that took the press outside-first, tapped wherever
the release landed, and ran a long press's action before its pressing
callback's `false`. **Shipped:** each is the `TapGesture`, `SpatialTapGesture`
or `LongPressGesture` it is on macOS, attached with `gesture`, so:

- a gesture inside the view, or the view's own press, comes first — a tap on
  a `Button` no longer takes its click;
- a release off the view, past the slop, or after 0.75 s is no tap;
- `.onTapGesture(count: 2)` inside `.onTapGesture` delays the single tap until
  the double one has given up, and a double-click runs only the double; a
  click on another view meanwhile does not give the double tap up, and the
  single tap still runs for the first click when it does;
- `onPressingChanged(false)` comes just before the action.

**The alternative** kept the old behaviour, which no SwiftUI app expects.
Every in-repo use was checked (the Mouse page, an outline triangle, the Stress
log rows) and the full suite passes.

*Lane 17m's entry (B95), `MeshGradient` (refusal review P11): measured on macOS 15.8 (SDK 26.2) against offscreen renders, with the fitting scripts in `Tools/SwiftUIProbes/Mesh gradient fits (lane 17m)/`.*

### A48. Swipe actions: which keys and which pointer gesture?

*`View.swipeActions(edge:allowsFullSwipe:content:)`,
`TabContent.swipeActions(edge:allowsFullSwipe:content:)`*

A macOS list row reveals its swipe actions on a two-finger trackpad swipe
toward the edge they belong to; a full swipe performs the first. A terminal
has no swipe, and an action only the pointer reaches breaks the
no-mouse-only rule, so the route has to be chosen.

**Options.**

1. **A menu, from a chord and a horizontal scroll.** On the focused row, a
   row shortcut (bindable through `.rowShortcuts`, say Ctrl-L for the
   leading edge and Ctrl-T for the trailing) opens the edge's actions as the
   context-menu engine's menu, anchored at that edge of the row; a
   horizontal wheel event over a row (what a trackpad swipe sends in a
   terminal that reports the wheel) opens the same menu, and a full swipe is
   not modelled. Half a day: the menu, the shortcuts and the wheel are all
   there.
2. **Revealed buttons in the row.** The chord or the horizontal wheel slides
   the actions in at the row's edge, over its trailing cells, as macOS draws
   them; Tab moves through them and Escape slides them away; a second
   horizontal wheel in the same direction is the full swipe. Closer to
   macOS, and a day and a half: the row needs a revealed state the list draws
   and memoises, and its focus ring has to admit the buttons.
3. **Decline** by reason: a gesture the terminal does not have.

**Recommendation:** 1. A swipe action is a context menu for one edge, and the
menu brings its keyboard handling, dismissal and colours with it.

**You asked (2026-10-04)** whether any terminal reports swipes. None reports
a swipe as a gesture. Terminal.app and iTerm2 report a trackpad's horizontal
scroll as the horizontal wheel buttons (Terminal compatibility survey.md), which is
what option 1 uses, and a full swipe could be inferred from a long burst
(answer of 2026-10-05).

**Decided (2026-10-23 and 26):** option 2, revealed buttons, with ⇧→ / ⇧←
(again for the full swipe), ⌃L / ⌃T where Shift does not arrive on the arrows,
both rebindable `RowAction`s, and a PTY test replaying a recorded trackpad
burst.

**Built (2026-10-26, keyboard and click):** `swipeActions(edge:allowsFullSwipe:content:)`.
A row reports its edges to its list as it renders (replayed from the effect
journal for a memoised row, as a row's context menu is). The list's swipe
keys reveal an edge of the cursor row; the list tells that row alone, through
its per-frame collector rather than the environment, and drops that row's
cached render as the reveal comes and goes. The row draws its actions over
its edge as an overlay in `.borderedProminent`'s look, each a menu row of a
sink of its own (the pop-up menus' `MenuRowSink`), so the highlight and the
full swipe can press them; while revealed they hold the keyboard as a menu
does (`claimKeyboardAsMenu`). ← and →, Tab and Shift-Tab move, Return or Space
press, Escape, ↑ or ↓ slide them away, the same chord again presses the first
where a full swipe is allowed, and the other edge's chord slides them away. A
click on one presses it; a click elsewhere slides them away and is spent, as a
click outside a menu is. The cursor stays on the row throughout.

**The horizontal wheel (built the same night):** a burst of sideways ticks
over a row is one swipe — ticks less than 250 ms apart (an estimate; the
proposal's range was 150 to 300 ms, unmeasured). The first burst toward an
edge with actions moves the cursor to that row and reveals them; a second the
same way is the full swipe, pressed by the list from the event (the revealed
row hands it a closure through the collector, so nothing is pressed during a
render); a burst the other way slides them away. Sideways ticks within 250 ms
of a vertical one reveal nothing (the axis lock), and a list whose row has no
actions on that edge leaves the wheel alone. `SwipeWheelTests` replays a
swipe as SGR bytes through the terminal's own parser, several reports per
read and one split across two.

**For a future reader:** the burst gap and the replayed bytes are
representative, not recorded: a recording needs a person at a trackpad, in
Apple Terminal and iTerm2. Record one and set `swipeBurstGapNanos` from it.

**Not built yet:** a narrow form when the actions are wider than the row;
`TabContent.swipeActions`.

### C15. The multi-contact gestures, the window drag, and the recognizer bridge

*`MagnifyGesture`, `RotateGesture`, `SpatialEventGesture` (and their members);
`WindowDragGesture`; `View.gesture(_:)` (an `NSGestureRecognizerRepresentable`)*

The gesture family in `parity-map.json` now holds only the first three, with
a reason that holds: they recognize the scale and angle between two contacts,
or report every simultaneous contact with its kind, 3D location and pose, and
a terminal's mouse protocols report one pointer — its cell, its buttons, the
wheel and three modifier bits. `WindowDragGesture` is declined with the Window
family (a TUI app has no window to drag), and `View.gesture(_:)` with the
AppKit-bridge family. The family's old reason — "no velocity, no simultaneous
touches, nothing to arbitrate" — is gone with what it refused.

### B-F2-1. A press drained before the frame that fails a double tap restarts it

*`TapGesture(count:)`, `SpatialTapGesture(count:coordinateSpace:)`,
`View.onTapGesture(count:perform:)`, and a gesture held back behind one —
`.onTapGesture(count: 2)` inside `.onTapGesture`.*

A multi-tap gives up on the frame clock: the run loop ticks the arena at the
start of each frame, and wakes for the deadline (B92). It drains input before
it renders, though, and the frame-rate cap can hold that frame back by up to a
frame; and the deadline itself counted from the first frame after the release
(B92) until 2026-10-18, up to a frame late already. So a press that comes just after the
double tap's deadline, within about a frame of it (17 ms at 60 Hz; two
frames until 2026-10-18), or one
slow frame in a heavy app, is fed to the double tap before the tick that
would have failed it. The press is too late to continue the
double tap, which restarts at it. A single tap held back behind the double tap still holds the first
click: macOS keeps a waiting tap's click (measured; see the commit "A gesture
held back keeps the end it reached"), and TUI now does too. The single tap
then runs late, when the restarted double tap gives up, or not at all if that
double tap succeeds. The late click itself is no single tap. On macOS the
first click's single tap would have run at the deadline, and the late click
would have started a new double tap and a single tap of its own.

**Shipped:** as above. Hitting it takes a second click landing within a
frame or two after the 0.35 s window closes. Before this lane the first
click's single tap was lost in more cases than this one, among them a click
on any other view while the double tap waited: that press gave the double tap
up and dropped the single tap's click with it. A press elsewhere now leaves a
waiting gesture to wait out its interval, as macOS does (the commit "A press
elsewhere does not give a waiting gesture up"), so this is the one case left
in which the first click's single tap runs late or not at all.

**The fuller version:** tick the arena to the press's own time before a press
is routed (`MouseEventDispatcher.beginGestureArena`), so a deadline the press
has passed fails its gesture first. In an app the event clock and the frame
clock are one clock, and since B92's fuller version shipped (2026-10-18) the
test harnesses' are too, so the press's own time can be ticked to. About an
hour now.
It adds a branch to the press path only, not to frames.

### B-F2-2. A disabled view's gestures are given up at the next press, as a removed view's are

*`View.disabled(_:)` over a view with a gesture that is under way or waiting:
a double tap waiting for its next click, a sequence waiting for its second
gesture, a drag mid-drag.*

TUI gives up a gesture whose view the frame on screen no longer files —
removed or disabled alike — once the next left-button event has been decided
as if it were still there (the commit "A gesture whose view has gone waits
for the next click"). For a removed view that is what macOS 15.8 does
(F2 probes review3b, review3c, review4: R1–R5, R8–R12, R15r). For a disabled
one macOS gives the gestures up at the disable (probes review4b, review4c,
review4d):

- a `@GestureState` a disabled drag or waiting sequence updated resets at the
  disable (S1, S3), where TUI resets it at the next left-button event;
- a row with a double and a single tap, clicked and disabled 0.1 s later
  inside an `.onTapGesture`, runs no single tap, but the tap around it runs
  the row's click at the disable, by a button or by a timer with no click
  after (R11d, R12d, R14d, R15d, R15d'), and the next click, beside the row
  too, runs as usual. TUI runs that tap at the next press, and a press
  beside the row then runs nothing of its own;
- a waiting sequence disabled still keeps the tap around it, which it had
  cancelled, off the next click beside it (R6, R16d), as TUI does. So
  macOS does not simply cancel at the disable either: a gesture that has won
  the press (a sequence waiting, a drag under way) still holds the next
  left-button event, while one that has not (a double tap waiting, a tap held
  back behind it) lets go at once.

**Shipped:** the removed-view rule for both. What differs is when the
gestures around a disabled row run (at the next press, not at the disable)
and when a `@GestureState` resets. `GestureArenaLifetimeTests.disabledRow`
pins macOS's results under `withKnownIssue`.

**The fuller version:** file a disabled gesture attachment's participant
(looked up, never created) as disabled rather than not at all; at the first
arena input after the walk, cancel a disabled contender (its
`@GestureState` resets), take one that has not won out of the running and
process its arena so what it held runs, and keep one that has won holding
the arena, as a departed one does, until the next left-button event; and
ask the run loop for one more frame when a disable released something, so
it runs at the disable rather than at the next tick. About three hours with
tests. Per frame it costs a lookup per disabled gesture attachment, and only
while an arena exists.

**Fuller version shipped (lane INPUT, 2026-10-18).** A disabled view's
attachment files the participant it already has as disabled
(`MouseEventDispatcher.fileDisabledGesture(_:in:)`, a state lookup per
disabled attachment per walk; replayed by a memo that serves it). The first
arena input after that walk — the next frame's tick, which the walk asks the
run loop for (`hasPendingGestureDisable`), or an event that comes first —
cancels each such gesture, so its `@GestureState` resets; one that had not
won its press goes out of the running and what it held back runs, and one
that had won holds the next left-button event, as a departed one does
(`GestureArena.cancelDisabled(_:)`). `GestureArenaLifetimeTests.disabledRow`
now passes as measured on macOS, without its known issues;
`GestureDisableTests` pins the drag's reset (S1) and the frame asked for.

### B-F2-3. A gesture whose view has gone lives until the next left-button event

*Every attached gesture: `gesture`, `highPriorityGesture`,
`simultaneousGesture`, `onTapGesture`, `onLongPressGesture`.*

A gesture whose view the frame on screen did not file is frozen, not dropped:
it hears no clock and no event, reports nothing and keeps what it holds back
held, until the next left-button event (a press anywhere, or the move or
release of a drag under way) has been decided as if it were still there.
That is what macOS 15.8 does for a removed view (B-F2-2 has the probes), and
a frame-time give-up made a click's outcome depend on whether a frame came
first. Its cost is the lifetime:

- the departed contender and its arena live until that event, which in a
  session driven by the keyboard alone may be never: the participant, its
  gesture's closures and whatever they capture, and whatever it holds back
  (the tap around it, a control owed a click) with theirs;
- while the arena lives, every rendered frame rebuilds the set of
  participants the frame filed and ticks the arena: work in the gestures on
  screen, where the earlier frame-time give-up dropped the arena at the next
  frame;
- no wake: a departed gesture has no deadline, so it never keeps the run
  loop awake.

What counts as departed is what the last walk did not file, which takes in
cases no probe has measured:

- a gesture turned off by `gesture(_:isEnabled: false)` (or the
  `name:isEnabled:` forms) or by its mask, which files its role with no
  participant;
- a gesture under a background a modal renders isolated;
- a gesture on a row a scroll view windows out of its viewport;
- a gesture whose view is disabled and then enabled again before the next
  left-button event: it is filed again, so it is no longer departed, and
  carries on where it was, as a removed one never does.

**Shipped:** as above, documented on `GestureArena` and
`GestureArena.Contender.isDeparted`.

**The fuller version:** measure the four unmeasured cases with the probe
(about an hour) and match what they show; if a long-lived departed arena
matters in practice, drop the arena's closures early by giving a departed
gesture up at a keyboard event too, which is itself unmeasured on macOS.

### B-ST3-1. `renderOnce` empties its focus manager without telling the focused control

*`ViewRenderer.render(_:atRow:column:)`, `FocusManager.clearWithoutNotifying()`*

A `renderOnce` snapshot used to keep its whole render alive for the life of the
process: what the walk registered held closures over its `RenderContext`, whose
environment holds the services those closures were kept in. The fix empties the
services once the frame is written, as `App.cleanup` does at quit. `App.cleanup`
empties the focus manager with `clear()`, which first tells the focused control
it lost the focus: that is where a focused field's edit is committed at quit.
In a snapshot it ran the control's code after the frame was on the terminal. A
`TextField` the snapshot had auto-focused reported `onEditingChanged(false)`.

**Shipped:** the snapshot's teardown runs no view's code, as before the fix
existed. It empties the focus manager without telling anyone, so a snapshot of a
`TextField` reports `onEditingChanged(true)`, from its auto-focus, and never
`false`. That matches the type's documented snapshot semantics: no teardown
pass, and no side effects on shared state. A test pins it
(`ViewRendererTests.snapshotTeardownIsSilent`).

**The alternatives, and their price.**

- **Tell the control** (what `clear()` does): the arrival and departure would
  balance. The price is user callbacks running after the frame is drawn, from a
  renderer that otherwise runs no view code once it has drawn. One line to
  change.
- **Send neither:** suppress the snapshot's focus *arrival* as well, so nothing
  is announced at all. This is the more consistent version. Its price is
  unmeasured: auto-focus also decides which control draws its focus indicator,
  so the arrival's notice would have to be separated from the focus itself in
  `FocusManager`'s auto-focus path, which every live frame runs.

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

### B-INPUT-3. Shift-clicks are asked for app-wide, not on Apple Terminal, and `TUIKIT_SHIFT_CLICKS=0` turns them off

*XTSHIFTESCAPE (`CSI > Ps s`); the Ghostty study's C5, phase 3's V6*

The policy was settled (the study's Q1, owner 2026-10-04: only while a
Shift-click consumer is focused now, app-wide once A13's own drag selection
shipped; A13 has). Two calls the study left open:

- **Not on Apple Terminal.** Its reading of `CSI > … s` is unmeasured, and a
  parser that ignored the `>` would take it for SCOSC and save the cursor.
  It needs nothing either: it has no Shift bypass, and reports the Shift bit
  on a click. So TUI sends nothing there, rather than risk a sequence for
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
