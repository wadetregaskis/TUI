# One owner for what the app sets on the terminal: decisions for review

*The HOSTLEDGER lane's companion to
[`SwiftUI API completion decisions.md`](<SwiftUI API completion decisions.md>),
in its format. The Ghostty adoption study asked for one ledger of the state
the app sets outside the grid
([§1.2](<../../Terminals/Ghostty VT reference adoption study.md#12-capability>),
C2), and three lanes built it at once: O9 the window title and GHOSTTY the
progress bar and attention, on an instance the render loop owned; O12 the
pointer's shape, on an instance the terminal owned. The integration of
2026-10-19 made them one type with two instances. This lane gives it one
owner. 2026-10-19.*

- **A. Needs your decision.** None.
- **B. Shipped the safe option.** Two.
- **C. Declined without asking.** None.

Nothing the terminal is sent while the app runs changed: every byte, in the
same order, at the same moment. What a fatal signal pays changed only within
windows of microseconds, said in B-HOSTLEDGER-1. The tests that pin the
ledger, the runner's keep-alive and farewell, the debt's fit, the pointer's
output, progress, attention and the published features pass as they were,
but for two that posed a debt through the hand-off this lane removed: they
pose the same debt through the ledger, and assert what they asserted.

## B. Shipped the safe option

### B-HOSTLEDGER-1. The terminal keeps the ledger; the render loop says what each frame wants

*`TerminalHostState`, `Terminal.hostState`, `HostStateKeeping`,
`RenderLoop+HostState.swift`*

**The two cases.** O9's for the render loop: it knows what each frame wants
(the title of the window in front, the progress the views drawn state), and
it writes them inside the frame. O12's for the terminal: it is what the bytes
go to, what composes the debt a signal pays, and what changes the mouse
modes, which on Ghostty reset the pointer's shape.

**Weighed.** Wanting and keeping are different jobs. What is wanted is asked
once a frame by whoever knows it: the loop for the title and the bar, the
app runner (from the views under the pointer) for the pointer's shape. What
was sent, and what that owes, is the terminal's state, and three things only
the terminal sees act on it: the debt a signal pays is composed and armed
there; raw mode's teardown puts the pointer back in the middle of its own
writes, before the mouse modes go off; and a mouse-mode change makes the
pointer's last shape unknown. With the loop as owner, the terminal would
call back into the loop at each of those, and the pointer's tests could no
longer drive a bare terminal. With the terminal as owner, the loop needs
nothing it lacks: it tells the ledger of the terminal it draws on what the
frame wants, at the same place in the frame. So the terminal owns it.

**Shipped:**

- `Terminal.hostState` is the one instance. Every terminal the render loop
  draws on keeps one (`HostStateKeeping`, which refines `TerminalProtocol`):
  a test's terminal and the headless app's keep a plain one, with no signal
  to owe it to. The loop reads it as `hostState`, and writes the frame's
  title and bar through it in one write, where it wrote them before.
- The hand-off of the debt (`Terminal.oweHostState(_:)`, which the app
  runner called after every frame and every hand-back) is gone:
  `Terminal.signalDebt` reads the ledger, and the terminal arms the debt
  again whenever what the ledger owes changes (`TerminalHostState.owed`). At
  once outside a frame: the pointer's first shape is owed before it is
  written, as O12 had it, and a hand-back's restore as the runner had it.
  Inside a frame, once the frame has gone out (`Terminal.endFrame()`): a title
  saved or restored, a bar put up or taken down.
- Whether the bar is sent again to keep it up stays the loop's call, as
  whether it is sent at all is (`sendsProgressReports`): the loop sets
  `keepsProgressAlive` on its terminal's ledger as it is made, off under tmux.

**What a fatal signal pays, and when.** The same bytes, in the same order
(`signalDebt` reads the title and the bar where it read the copy the runner
handed it). Two moments moved, by microseconds:

1. A frame that saves or restores the title, or puts the bar up or takes it
   down, is owed as the frame goes out. The runner owed it a moment later,
   after the frame's mouse mode, pointer shape and image bookkeeping. A frame
   drawn outside the pacer (the one before a Ctrl-Z, the debug frame dump),
   which the runner never owed, is owed too.
2. Raw mode's teardown, once it has put the pointer back, arms the debt again
   without the pointer's reset, a few instructions before it disarms.

**The fuller version.** Owe a frame's new title BEFORE the frame goes out, as
the pointer's first shape is owed before its write (B-O12-4's rule): a signal
between the flush and the arm then finds the title owed. That means arming in
`endFrame()` before the flush when the debt grew and after it when it shrank,
with a frame that does both needing the union. About an hour, for a window
of microseconds. Not done: it changes what a signal pays, which this lane
was asked not to do.

### B-HOSTLEDGER-2. A request for attention is not kept on the ledger: the frame drains its queue

*`TerminalBell`, `RenderLoop.attentionWrites()`,
`TerminalHostState.notification(_:)`, `TerminalHostState.bell`*

A request for the person's attention has nothing to want, keep or owe. It is
sent once and forgotten, and nothing is given back as the app leaves. So it
has no place among the values, and the ledger keeps what it already kept for
it: how it is spelled (`notification(_:)`, `bell`). Its queue stays with the
views' services (`TUIContext.terminalBell`), where `\.requestAttention` and
the input chain's refusal bell reach it from a module below the terminal's.
The frame drains it as it drains the clipboard's and the images' pending
writes, ahead of the title and the bar, as before; the exit's farewell drains
what is left.

**The fuller version.** A queue on the terminal's ledger. The environment
action would need a way to the terminal through the context (a closure, as
`synthesizeKeyEvent` is). About an hour, for no change in what is sent.
