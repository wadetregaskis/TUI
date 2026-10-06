# Owner-requested fixes (F2): decisions for review

*The F2 lane's companion to
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md),
in its format. The lane fixed two bugs the owner asked for, which are not
decisions-doc items: the `StdinArrivalNotifierTests` flake and a single tap
lost after a failed double tap. 2026-10-05.*

- **A. Needs your decision.** None.
- **B. Shipped the safe option.** One.
- **C. Declined without asking.** None.

## B. Shipped the safe option

### B-F2-1. A press drained before the frame that fails a double tap restarts it

*`TapGesture(count:)`, `SpatialTapGesture(count:coordinateSpace:)`,
`View.onTapGesture(count:perform:)`, and a gesture held back behind one —
`.onTapGesture(count: 2)` inside `.onTapGesture`.*

A multi-tap gives up on the frame clock: the run loop ticks the arena at the
start of each frame, and wakes for the deadline (B92). It drains input before
it renders, though, and the frame-rate cap can hold that frame back by up to a
frame; and the deadline itself counts from the first frame after the release
(B92), up to a frame late already. So a press that comes just after the
double tap's deadline, within about two frames of it (33 ms at 60 Hz), or one
slow frame in a heavy app, is fed to the double tap before the tick that
would have failed it. The press is too late to continue the
double tap, which restarts at it. A single tap held back behind the double tap still holds the first
click: macOS keeps a waiting tap's click (measured; see the commit "A gesture
held back keeps the end it reached"), and TUIkit now does too. The single tap
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
clock are one clock. Under the test harness they are kept apart (B92), and
every test that clicks a timed gesture without `syncEventClock()` would read
real monotonic time against `harness.now`. So that half needs the harness's
clocks joined, which is B92's fuller version. About two hours with B92's hour.
It adds a branch to the press path only, not to frames.

## For the main decisions doc

Three corrections the coordinator owes `SwiftUI-API-completion-decisions.md`,
which this lane does not edit:

- **B93** ("the next press within 0.35 s of the release") and the measurement
  table's row "A tap's slop, hold and double-tap interval" ("0.35 s from
  release to next press") describe the rule before the commit "A multi-tap's
  next click has to be released within 0.35 s of the last release". Measured
  on macOS 15.8, and shipped: the next click has to be *released* within
  0.35 s of the last release; a press in time but held past that gives the
  tap up then, with the button still down.
- **B94**'s third bullet could add what the commit "A press elsewhere does not
  give a waiting gesture up" ships: a click on another view does not give a
  waiting double tap up, and the single tap behind it still runs for the first
  click when the double tap gives up.
- The measurement table's row "A sequence's `onEnded`" says the second
  gesture "takes the first event after the first ends as its start". Measured
  on macOS 15.8 since, and shipped by the commit "A sequence's second gesture
  starts with the event that ended the first": the event that ends the first
  gesture is the second's first, so a tap before a tap ends at one click and
  a drag after a zero-duration long press starts at the press; only a first
  gesture that ends on its clock leaves the second to the next event. And,
  by the commit "A sequence's second gesture started by a release reports
  only how it ends": a release is a press already over, so a tap before a
  drag or a long press fails at the tap's release and never ends, while a
  tap before a zero-duration long press ends there, `false`, with no
  `onChanged`.
