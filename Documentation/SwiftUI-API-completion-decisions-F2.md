# Owner-requested fixes (F2): decisions for review

*The F2 lane's companion to
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md),
in its format. The lane fixed two bugs the owner asked for, which are not
decisions-doc items: the `StdinArrivalNotifierTests` flake and a single tap
lost after a failed double tap. 2026-10-05.*

- **A. Needs your decision.** One.
- **B. Shipped the safe option.** Four.
- **C. Declined without asking.** None.

## A. Needs your decision

### A-F2-1. ⌃4, ⌃| and ⌃⇧\\ quit the app on terminals that send ⌃\\'s byte for them

*`KeyboardShortcut.isDeliverableInTerminal`; any `.keyboardShortcut("4")`
(SwiftUI's ⌘4, ⌃4 under the default `.commandKey(.control)`), and a Control
shortcut on `|`.*

Raw mode keeps the user's quit key live (2026-10-06, the owner's request), so
the driver raises `SIGQUIT` for 0x1C. xterm, VTE (GNOME Terminal and its
kin), Konsole and the Linux console send that same 0x1C for ⌃4 and for ⌃|
(⌃⇧\\) in their legacy encodings — from those terminals' tables, not
measured here; Apple Terminal, iTerm2 and Ghostty were not checked either.
So on those terminals pressing an app's ⌘4 shortcut ends the app with
"Quit: 3". Before 2026-10-06 the byte was dropped (`KeyEvent.parse` reads no
key from 0x1C), so the shortcut never fired there either: what changed is
that an undeliverable chord now quits instead of doing nothing. Under the
kitty keyboard protocol the three arrive as themselves and fire.

**Shipped (option 1):** kept. `isDeliverableInTerminal` reports ⌃4, ⌃| and
⌃⇧\\ undeliverable, as it reports Ctrl-H (Backspace), and the C0-collision
table in `Terminal-compatibility.md` lists them, marked unmeasured.

**Options:**

1. **Keep** (shipped; recommended). The quit key stays the driver's on every
   host, which is what makes it quit a hung app; an app is told the chord is
   undeliverable. Price: nothing more.
2. **Turn the quit key off on hosts known to alias it**, recognised from the
   environment (`XTERM_VERSION`, `VTE_VERSION`, `KONSOLE_VERSION`,
   `TERM=linux`). ⌃4 then does nothing again — it still cannot fire, since
   the byte cannot be told from ⌃\\ — and ⌃\\ quits nothing there, hung or
   not. Over ssh the variables do not arrive, so a remote app would still
   quit. About an hour with tests. It trades the backup quit for an
   undeliverable shortcut doing nothing rather than quitting.
3. **Ask xterm to send Ctrl-digits apart** (`modifyOtherKeys`, `CSI > 4 ; 1 m`)
   while ⌃\\ keeps its 0x1C. Unmeasured: whether mode 1 changes the Ctrl-digit
   aliases at all, and VTE, Konsole and the Linux console would be unchanged.
   About an hour to measure on xterm (not installed here), then an hour to
   ship if it works.
4. **Read the aliases as the chord in the input chain instead**: not
   possible — the driver takes 0x1C before the app reads a byte, which is the
   point of the quit key.

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

### B-F2-2. A disabled view's gestures are given up at the next press, as a removed view's are

*`View.disabled(_:)` over a view with a gesture that is under way or waiting:
a double tap waiting for its next click, a sequence waiting for its second
gesture, a drag mid-drag.*

TUIkit gives up a gesture whose view the frame on screen no longer files —
removed or disabled alike — once the next left-button event has been decided
as if it were still there (the commit "A gesture whose view has gone waits
for the next click"). For a removed view that is what macOS 15.8 does
(F2 probes review3b, review3c, review4: R1–R5, R8–R12, R15r). For a disabled
one macOS gives the gestures up at the disable (probes review4b, review4c,
review4d):

- a `@GestureState` a disabled drag or waiting sequence updated resets at the
  disable (S1, S3), where TUIkit resets it at the next left-button event;
- a row with a double and a single tap, clicked and disabled 0.1 s later
  inside an `.onTapGesture`, runs no single tap, but the tap around it runs
  the row's click at the disable, by a button or by a timer with no click
  after (R11d, R12d, R14d, R15d, R15d'), and the next click, beside the row
  too, runs as usual. TUIkit runs that tap at the next press, and a press
  beside the row then runs nothing of its own;
- a waiting sequence disabled still keeps the tap around it, which it had
  cancelled, off the next click beside it (R6, R16d), as TUIkit does. So
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

### B-F2-4. Under the kitty keyboard protocol, ⌃\\ does not quit a hung app

*The owner's request of 2026-10-05: ⌃\\ quits, as a real `SIGQUIT`, even when
the app hangs.*

Raw mode leaves the line discipline one signal character, the user's quit
key, so the driver raises `SIGQUIT` for ⌃\\ before the app reads a byte,
hung or not, over ssh too. But where the terminal speaks the kitty keyboard
protocol, TUIkit pushes its "disambiguate" flag (with the other four, for the
keys they deliver), under which the terminal sends ⌃\\ as the report
`CSI 92;5u` instead of 0x1C. No byte reaches the line discipline, so no
signal. Which hosts: those that answer the protocol's query (kitty, Ghostty,
WezTerm, foot, iTerm2 and others, per the specification; unmeasured).

**Shipped:** the input chain takes the report of the user's quit key ahead
of every layer and raises `SIGQUIT` itself (`InputHandler.quitKey`), so ⌃\\
quits there too, and leaves the terminal as a quit does, the flags popped.
It takes the app's input loop to read the report: on those terminals a
hung app does not quit by ⌃\\. Closing the tab, or `kill -QUIT` from another
shell, still ends it cleanly.

**The fuller version, if wanted:** a watchdog that notices the main loop has
not drained stdin for a while (say two seconds with bytes pending) and reads
stdin on a thread of its own, looking for the quit report, handing every
other byte back to the loop in order should it recover. About half a day
with tests; it adds a thread and a second reader of the terminal, which is
the cost to weigh. Not pushing "disambiguate" would give the byte back to
the driver, but loses Escape without a timeout and the five C0 chords as
themselves (decisions A4), so it is not offered.

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
