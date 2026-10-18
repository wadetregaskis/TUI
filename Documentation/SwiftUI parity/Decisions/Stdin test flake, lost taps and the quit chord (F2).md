# Owner-requested fixes (F2): decisions for review

*The F2 lane's companion to
[`SwiftUI API completion decisions.md`](<SwiftUI API completion decisions.md>),
in its format. The lane fixed two bugs the owner asked for, which are not
decisions-doc items: the `StdinArrivalNotifierTests` flake and a single tap
lost after a failed double tap. 2026-10-05.*

- **A. Needs your decision.** None open; A-F2-1 is decided (below).
- **B. Shipped the safe option.** Four (B-F2-4 now ships the fuller version).
- **C. Declined without asking.** None.

## A. Needs your decision

### A-F2-1. ⌃4, ⌃| and ⌃⇧\\ share ⌃\\'s byte on some terminals — DECIDED by the owner, 2026-10-06

*`KeyboardShortcut.isDeliverableInTerminal`; any `.keyboardShortcut("4")`
(SwiftUI's ⌘4, ⌃4 under the default `.commandKey(.control)`), a Control
shortcut on `|`, and any binding on ⌃\\ itself.*

Raw mode keeps the user's quit key live (2026-10-06, the owner's request), so
the driver raises `SIGQUIT` for 0x1C. xterm, VTE (GNOME Terminal and its
kin), Konsole and the Linux console send that same 0x1C for ⌃4 and for ⌃|
(⌃⇧\\) in their legacy encodings — from those terminals' tables, not
measured here. So for a while an app's ⌘4 quit the app there.

**The owner's decision** (2026-10-06, about 09:00): "Ideally ^4 would be
handled by our key handler, if one is installed for that combination.
Without disturbing ^\\, which should be an independent shortcut (but also, if
one is installed by TUIkit users, it should also override the SIGQUIT
behaviour). But if we can't disambiguate the two, then… if we can detect the
aliasing, or otherwise that ^4 — or any shortcut — needs SIGQUIT to be
masked, then let's do that."

**Shipped:**

- Under the kitty keyboard protocol the keys arrive apart: a ⌃4 binding
  fires, and ⌃\\'s report goes to the app's bindings first and raises
  `SIGQUIT` only if none takes it.
- In the legacy encoding the driver's quit stays live — a hung app's way
  out — unless the app DECLARES a binding on a chord the quit key's byte
  could be: ⌃\\, and ⌃4, ⌃| and ⌃⇧\\ (with or without Option). Declared is
  what the framework can read without running the app's code:
  `.keyboardShortcut` (resolved through `.commandKey`; menu items' too),
  `onKeyPress` on keys on the path to the focused view (not on a set of
  characters: it asks for typed text, not chords, and `.decimalDigits` would
  claim ⌃4 — the coordinator's ruling, round 6; and for a Control chord only
  on a key that names one, `KeyEquivalent.namesControlChord` — `"|"` for ⌃|,
  never a digit for ⌃4, so a PIN field's `onKeyPress(keys:)` on "0"…"9"
  neither masks the quit nor takes the retry — the coordinator's ruling,
  2026-10-06),
  status-bar items and the status bar's quit key, the scene's undo keys.
  Recomputed after every frame; `tcsetattr` only when it changes; the
  user's termios restored on every exit as before.
- With the quit masked, 0x1C arrives as ⌃\\; unclaimed, it is offered as
  ⌃4, ⌃| and ⌃⇧\\ (the alias retry, as for Ctrl-H) to the bindings declared
  for them alone — not round the whole chain, so a handler that hears every
  key, or a field's `.decimalDigits`, hears the byte once, as ⌃\\ (the
  coordinator's ruling, round 6); still
  unclaimed, the chain raises `SIGQUIT` (`kill(0, …)`), so ⌃\\ quits a
  responsive app.
- Aliasing cannot be read from the byte: every terminal is assumed to alias
  in its legacy encoding until measured not to — per chord, by the owner's
  `cat -v` readings of 2026-10-06 (`TerminalClient.quitByteAliases`): Apple
  Terminal 2.14 ⌃⇧\\ only (⌃4 sends nothing), iTerm2 3.7.3 and Warp
  0.2026.09.30 both, Ghostty 1.3.1 ⌃4 only (⌃⇧\\ is `CSI 124;5u`); tmux and
  unidentified hosts both (Terminal compatibility survey.md, "Which hosts send 0x1C
  for which chord").

**The ambiguity rule (the coordinator's call):** on an aliasing terminal an
app that binds BOTH ⌃\\ and ⌃4 gets ⌃\\'s binding for either key — the bytes
are identical, and ⌃\\ is the canonical reading. `isDeliverableInTerminal` is
`true` for ⌃\\ and `false` for ⌃4, ⌃| and ⌃⇧\\ (as for Ctrl-H), its doc
saying when they do arrive.

**What remains:**

- A handler that hears every key (`onKeyEvent`, `onKeyPress(phases:action:)`)
  cannot be known without running it: it does not mask the quit, and does
  not see ⌃\\ while the driver has it. Nor does an `onKeyPress` on a set of
  characters, by the ruling above. Documented.
- While a masking binding is on screen, a hung app does not quit by ⌃\\
  (`kill -QUIT` still ends it) — the trade the rule makes.
- The alias retry is 0x1C's only. xterm's other digit aliases (⌃2 NUL,
  ⌃3 ESC, ⌃5…⌃7 0x1D…0x1F, ⌃8 DEL) matter to the quit key only for a user
  who moved it to one of those bytes; a moved quit key is masked for its own
  chord.

## B. Shipped the safe option

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
clock are one clock, and since B92's fuller version shipped (2026-10-18) the
test harnesses' are too, so the press's own time can be ticked to. About an
hour now.
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

### B-F2-4. Under the kitty keyboard protocol, a hung app quits at the second ⌃\\

*The owner's request of 2026-10-05: ⌃\\ quits, as a real `SIGQUIT`, even when
the app hangs.*

Raw mode leaves the line discipline one signal character, the user's quit
key, so the driver raises `SIGQUIT` for ⌃\\ before the app reads a byte,
hung or not, over ssh too. But where the terminal speaks the kitty keyboard
protocol, TUIkit pushes its "disambiguate" flag (with the other four, for the
keys they deliver: flags 31), under which the terminal sends ⌃\\ as the
report `CSI 92;5u` instead of 0x1C. No byte reaches the line discipline, so
no signal. Which hosts: those that answer the protocol's query (kitty,
Ghostty, WezTerm, foot, iTerm2 and others, per the specification;
unmeasured). The input chain quits on the report (after the app's bindings,
A-F2-1), which takes a loop that reads its input.

**Shipped (2026-10-06, the reviewer's watchdog, on the coordinator's
recommendation; yours to veto):** a thread of its own, the stall watchdog
(`StallWatchdog`, umbrella module, POSIX), sleeps in `poll` on standard
input; when input has waited unread for 1.5 s with the loop draining
nothing, it writes `CSI < u`. The terminal then sends keys in the legacy
encoding, and the next ⌃\\ is 0x1C, which the driver quits on, hung or not.
The main loop pushes the flags back at its next drain if it was only slow;
the parser reads both encodings meanwhile. The pop is written under the one
lock every terminal write takes, so never inside a frame, and counts only
when the terminal was sent it whole (none at all where a non-blocking
standard output is full; tried again a grace later). Armed only while it can
help: flags pushed, the quit key live, and no binding that the LEGACY
encoding — where the pop puts the terminal — would mask it for: ⌃\\, and on
a host that may alias, ⌃4, ⌃| and ⌃⇧\\, though under the protocol those
three leave the driver's quit live (round-6 fix: armed on the protocol's
mask, a ⌘4 shortcut's ⌃4 pressed during a slow frame was the driver's 0x1C
after the pop, and quit the app). Not during a suspend, whose own pop
disarms it and takes back a pop of the watchdog's in one step; stopped at
the teardown. Cost to a running app: a counter stored per loop iteration, an
uncontended lock per terminal write, and, while input arrives, a wake of the
thread per key burst (looked at four times a second for as long as it waits
unread).

**The residual:**

- The report that trips it is never read: a hung app quits at the SECOND
  ⌃\\, about two seconds after the first. Nothing is popped for a hung app
  nobody types at — there is no way to tell a hang from an idle loop without
  a heartbeat that would wake an idle app.
- A main thread hung INSIDE a write (a terminal that stopped reading its
  output) holds the lock: the watchdog waits behind it and pops nothing.
  Writing over a frame half sent would corrupt it, and that terminal would
  not read the pop either.
- A frame slower than 1.5 s with keys pending pops and pushes the flags back:
  harmless, but each modifier the decoder thought held is released (as at
  any pop), and a key's release in that window is not reported.
- With a binding that masks the quit key the watchdog stays disarmed, and a
  hung app does not quit by ⌃\\ (A-F2-1's trade) — under the protocol too
  for a binding on ⌃4, ⌃| or ⌃⇧\\ on a host that may alias, where the
  driver's quit is live but a pop would make the binding's key quit.
- The quit's debt pops again after the watchdog's pop: on the alternate
  screen, where TUIkit pushed, a pop of an empty stack is harmless.
- Measured against the PTY smoke's terminal only; real hosts unmeasured.

**To veto:** delete `StallWatchdog` and its three call sites (the run loop,
`Terminal.refreshStallWatch`, the write gate around writes); a hung app under
the protocol then does not quit by ⌃\\ again, as before.

## For the main decisions doc

Three corrections the coordinator owes `SwiftUI API completion decisions.md`,
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
