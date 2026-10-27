# One owner for what the app sets on the terminal

*How the title, progress, pointer shape and the rest of what an app sets on
its terminal came to have one owner: a ledger kept by the terminal, told each
frame what it wants. Ids: B-HOSTLEDGER-1 to 3.*

## In short

The terminal keeps the ledger of what it was last sent; the render loop says
what each frame wants, and only differences are written. Each value is a
`TerminalHostSetting`; a request for attention is a queue the frame drains,
not a setting.

## The record

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

### B-HOSTLEDGER-3. Every value is a `TerminalHostSetting`, generic over what it holds

*`TerminalHostSetting<Value>`, `TerminalHostState.windowTitle`,
`.progressBar`, `.pointerShape`*

O12 built `TerminalHostSetting` for the pointer (what was last sent, the
mid-run unset, the reset, and whether it is owed), on bytes. The title and the
bar each kept the same logic in fields of their own.

**Shipped:** all three are settings. A setting holds the value last sent (the
sanitised title, the progress report, the host's name for the shape), not its
bytes, so the ledger can still say what the terminal shows
(`writtenTitle`, `writtenProgress`); the caller spells a value as it asks for
it (`update(to:spelling:)`). Two things genuinely differ between the values,
and each is said where its setting is made:

- **A lead** before a value set where the terminal shows its own: the
  title's save on the terminal's title stack, which its restore pops. Empty
  for the others.
- **Whether an unset settles the debt** (`unsetSettles`). The title's restore
  pops the save, so nothing is owed after it, and a second would pop a title
  that is not the app's to give; the bar taken down owes nothing either. The
  pointer's unset is the host's name for its own pointer, which Ghostty reads
  as its arrow rather than the shell's I-beam, so O12 keeps the reset owed
  from the first shape until it goes out (B-O12-4). It has to be said, not
  worked out: on every host but Ghostty the pointer's unset is the same bytes
  as its reset, so "an unset that is the reset settles" would have dropped a
  reset O12 sends.

Two things stay beside the settings, on the ledger, because they are about
when to ask rather than what was sent: the title's cache of what was last
asked (one comparison a frame, before sanitising), and the bar's keep-alive
clock (only the bar is sent again unchanged).

**The fuller version.** The keep-alive as a setting's own (a period, and the
instant last sent), so any value could be kept alive. About an hour, for one
value that has it. Not done.
