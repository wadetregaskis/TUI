# Completing the SwiftUI API: Wave 17g decisions (gestures)

*Wave 17g's entries for
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md),
in its format, to be folded in and renumbered there. The wave acts on the
refusal review's P6
([`SwiftUI-API-completion-refusal-review.md`](SwiftUI-API-completion-refusal-review.md)):
SwiftUI's gesture API ships, and what stays declined keeps a reason that holds.
SwiftUI's behaviour was measured on macOS 15.8 (built against the macOS 26.2
SDK) by synthesising `NSEvent`s into a window hosting the view; the probe
sources and their output are in the session notes (`w17g/probe/`), not in the
repository. macOS 26 could not be probed.*

What the probes established, and what now holds here too:

| Question | macOS 15.8 |
|---|---|
| A parent's `gesture` vs a child's tap | the child's; the parent's gets a click elsewhere |
| A parent's `highPriorityGesture` | the parent's, on the child too |
| A parent's `simultaneousGesture` | both — the parent's callback first |
| `including:` `.gesture` / `.subviews` / `.none` | child off / parent off / both off |
| `.gesture` / `.onTapGesture` / `.onLongPressGesture` on a plain-style `Button` | the button's action; the gesture never runs |
| `.highPriorityGesture(TapGesture())` on that button | the tap; no action |
| `.simultaneousGesture(TapGesture())` on it | both, the tap first |
| `.highPriorityGesture(DragGesture())` on it | a click is the button's; a drag is the drag's |
| A tap's slop, hold and double-tap interval | 40 points (45 fails); 0.75 s; 0.35 s from release to next press |
| `onTapGesture(count: 2)` inside `onTapGesture` | a double-click runs only the double; a single click runs the single 0.35 s after its release |
| `LongPressGesture`'s defaults | 0.5 s, 10 points (Euclidean; 11 fails); `true` from the press; ends at the deadline with the button down |
| `onLongPressGesture`'s pressing callback | `true` on the press; `false` just before the action |
| `DragGesture`'s start | at `minimumDistance` (≥), the press kept as `startLocation`; a drag that never starts does not end |
| A sequence's `onEnded` | when its second gesture ends; the second takes the first event after the first ends as its start |
| `@GestureState`'s reset | on end, failure or cancellation, before `onEnded` |
| `modifiers(_:)` | read at the press; more keys than asked for satisfy it |

---

## A. Needs your decision

### A-W17g-1. `onDragGesture`, now that `DragGesture` ships

*`View.onDragGesture(_:)`, `DragGestureEvent` (TUIkit's own)*

`onDragGesture` predates the gesture API: a stream of `.began`/`.moved`/
`.ended` events with integer positions, delivered by a mouse handler that
takes the press it is offered, outside first. It does not take part in the
gestures' arbitration, so it ranks as a control would — a `Button` inside an
`.onDragGesture` view never gets its click, which is not how SwiftUI ranks a
drag. `DragGesture(minimumDistance: 0)` with `onChanged`/`onEnded` now says
the same thing in SwiftUI's words, and ranks as SwiftUI ranks it.

**Options.**

1. **Keep it as it is** (shipped): a TUI-only raw event stream beside
   SwiftUI's gesture. Free; two ways to say one thing, ranked differently.
2. **Rebuild it on `DragGesture(minimumDistance: 0)`**, so it keeps its
   signature and ranks as a gesture. An hour; the three in-repo users (the
   Mouse page, the tone- and channel-curve editors) need checking for a
   control inside the drag area.
3. **Remove it** — pre-1.0, no shims — and port the three users to
   `DragGesture`. An hour and a half.

**Recommendation:** 3. `DragGestureEvent` carries nothing `DragGesture.Value`
does not, and a TUI-only spelling that ranks differently from the SwiftUI one
beside it is a trap.

## B. Shipped the safe option

### B-W17g-1. A control takes the press once the gestures ahead of it give up; it cannot wait

*`View.gesture(_:including:)`, `View.highPriorityGesture(_:including:)`,
`View.simultaneousGesture(_:including:)` (all forms), `GestureMask`*

The arena (`Sources/TUIkit/App/GestureArena.swift`) ranks every region under
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
  long press or drag ran on it. TUIkit's buttons are drawn, and follow the
  plain-style SwiftUI button, which was measured.)

**The fuller version** makes controls recognizers: each control's press
handler reports possible, recognized and failed, and accepts a cancel. A day
and a half — fifteen-odd controls, and every mouse test that reads a
control's press.

### B-W17g-2. Distances are cells along either axis

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
in pixels (`TIOCGWINSZ`, CSI 16 t — `Terminal-compatibility.md` records both
per host), so a distance could be converted and compared as SwiftUI compares
it. Half a day, and it reopens §2.1 for these three: a distance in points
would be the only `CGFloat`-like measurement in the API.

### B-W17g-3. A drag's velocity is an average of the report-to-report speeds

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

### B-W17g-4. Timed recognizers run on the frame clock

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

### B-W17g-5. Two double-click windows: a row's and a tap's

*`TapGesture(count:)`, `SpatialTapGesture(count:coordinateSpace:)`,
`View.onTapGesture(count:perform:)`; and, for comparison,
`List`/`Table` `onRowActivate(_:)`, `MouseEvent.clickCount`*

A tap counts its own clicks, as measured: the next press within 0.35 s of the
release. The dispatcher's `clickCount`, which rows open on, counts presses
within 400 ms of each other (macOS's `NSEvent.doubleClickInterval` is 0.5 s,
and `NSTableView` uses it). **Shipped:** both, each matching its macOS
counterpart's kind.

**The alternative** is one interval for both — 0.35 s, or the dispatcher's
0.4 s for taps too. Half an hour either way; the first slows nothing, the
second departs from SwiftUI's measured taps.

### B-W17g-6. `onTapGesture` and `onLongPressGesture` are gestures now

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
  the double one has given up, and a double-click runs only the double;
- `onPressingChanged(false)` comes just before the action.

**The alternative** kept the old behaviour, which no SwiftUI app expects.
Every in-repo use was checked (the Mouse page, an outline triangle, the Stress
log rows) and the full suite passes.

## C. Declined without asking

### C-W17g-1. The multi-contact gestures, the window drag, and the recognizer bridge

*`MagnifyGesture`, `RotateGesture`, `SpatialEventGesture` (and their members);
`WindowDragGesture`; `View.gesture(_:)` (an `NSGestureRecognizerRepresentable`)*

The gesture family in `parity-map.json` now holds only the first three, with
a reason that holds: they recognize the scale and angle between two contacts,
or report every simultaneous contact with its kind, 3D location and pose, and
a terminal's mouse protocols report one pointer — its cell, its buttons, the
wheel and three modifier bits. `WindowDragGesture` is declined with the Window
family (a TUIkit app has no window to drag), and `View.gesture(_:)` with the
AppKit-bridge family. The family's old reason — "no velocity, no simultaneous
touches, nothing to arbitrate" — is gone with what it refused.

## D. Deferred

- **Shift- and Ctrl-left-clicks per terminal.** `modifiers(_:)` hears what a
  terminal forwards. The ⌥/⌘ half is recorded in `Terminal-compatibility.md`;
  Shift- and Ctrl-clicks have not been byte-captured on any host. With the
  terminal probes, an hour per host.
- **The Example app.** Its Mouse page shows `onTapGesture` and
  `onDragGesture`; a section for the gesture API — a draggable chip on
  `@GestureState`, a double-tap-or-single area, a high-priority drag over a
  button — is an hour.
- **A macOS 26 measurement pass.** Every row above was measured on macOS 15.8.
- **Performance.** Not measured. A page with no gesture pays a dictionary
  check per mouse event and per frame. A page with gestures rebuilds each
  attached gesture's recognizers every frame (a few allocations) and, for a
  high-priority or masked gesture, collects its content's handler ids. A
  gesture per row of a long `List` is where an A/B is owed, on a quiet
  machine.
