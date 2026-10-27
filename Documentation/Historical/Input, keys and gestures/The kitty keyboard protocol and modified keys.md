# The kitty keyboard protocol and modified keys

*How TUI came to ask terminals for the kitty keyboard protocol, what it does
with ⌘, Super and Hyper chords, the legacy keys it falls back to, key-press
phases, and the quit chord. Ids: A4, B7, B12, B-D1K-1 to 4, B-D1K-8,
B-D1K-1's ruling of 2026-10-23, A-F2-1, B-F2-4, B-INPUT-2.*

## In short

Where the terminal speaks it, TUI pushes all five kitty keyboard flags, so it
hears key releases, repeats and modifiers a legacy encoding loses. A ⌘ chord
reaches `onKeyPress` with `.command`; shortcuts stay on their Control stand-in
and fire on a real ⌘ too under `.keyboardShortcutsMatchCommand()`. Ctrl-H, I,
J, M and [ fall back to their legacy keys when nothing binds them. The quit
chord ⌃\ still quits a hung app: a watchdog pops the protocol so the next ⌃\
is the driver's byte. `TUIKIT_KEYBOARD_PROTOCOL=0` keeps TUI from asking.

## How it unfolded

1. **Lane D1K** built the owner's A4 (the protocol), B7 (key-press phases) and
   B12 (button repeat by keyboard), with the calls below.
2. **2026-10-06, A-F2-1.** ⌃4, ⌃| and ⌃⇧\ share ⌃\'s byte on some
   terminals; the owner decided how the quit chord treats them.
3. **2026-10-18, lane INPUT:** a modifier-key alternate's shortcut is live only
   while the alternate is drawn (B-INPUT-2).
4. **2026-10-23, B-D1K-1.** The owner: deliver ⌘ to `onKeyPress`; default
   shortcuts stay on non-command modifiers; command shortcuts when a developer
   opts in. Built by lane KEYS, 2026-10-24.
5. **B-F2-4**, settled 2026-10-18: keep the hung-app quit at the second ⌃\
   under the protocol, and check it once on a real kitty-protocol host.

## For a future reader

- **Owed: B-F2-4's check on Ghostty**, at the next probe session (settled
  2026-10-18, never run).
- **A killed app leaves a shell that cannot read Return** while the protocol's
  flags are pushed (B-D1K-8); `reset` or the terminal's own recovery fixes it.

## The record

### B-D1K-1. Under the kitty keyboard protocol a ⌘ chord is delivered to onKeyPress, and to shortcuts on request

*`EventModifiers.command`, `KeyPress.modifiers`; the protocol's Super, Hyper
and Meta bits*

A terminal's legacy encodings never deliver a ⌘ chord: the terminal keeps it
for itself or sends nothing. Under the kitty keyboard protocol, a ⌘ chord the
terminal does not claim reaches the app, as the Super bit (kitty and Ghostty
report ⌘ that way on macOS; documented, not measured).

**Shipped:** a chord on Super, Hyper or Meta that types no text is dropped,
as the legacy encodings drop it; it still updates the modifier state, so
`onModifierKeysChanged` sees `.command` while ⌘ is held. Delivered as the
bare key, ⌘K would have typed a `k` into a text field and fired every bare-`k`
binding, and nothing that matches a key knows to look for ⌘.

**The fuller version** delivers the chord with ``EventModifiers/command`` in
its modifiers: `onKeyPress` would see `[.command]` as SwiftUI does, and a
`KeyboardShortcut` written with `.command` could match the real ⌘ where the
terminal passes it, before (or instead of) `commandKey`'s stand-in. Every
consumer that matches a bare character would have to learn to refuse ⌘ — text
fields, type select, the status bar, the theme and appearance keys, the
Example's page keys — and the stand-in rule would need a precedence: does
`KeyboardShortcut("s")` fire on ⌘S, on Ctrl-S, or both? About a day, most of
it the audit of bare-key consumers, and a question for you on the precedence.

**Ruled (owner, 2026-10-23), and built (lane KEYS, 2026-10-24):** "Deliver ⌘
to onKeyPress; default shortcuts stay on non-command modifiers; command
shortcuts when a developer opts in."

- **Delivered.** A Super chord that types no text is a `KeyEvent` with the
  new `command` set (`KittyKeyDecoder`), so `KeyPress.modifiers` holds
  `.command`, as SwiftUI's does. Hyper and Meta chords are still dropped:
  SwiftUI has no modifier for either. A ⌘ chord on a non-Latin layout is its
  base-layout key (⌘С is ⌘C), as macOS matches a key equivalent.
- **Refused centrally, not consumer by consumer.** The plan listed the
  consumers that match a bare character — text fields, type select, the
  status bar, `t` and `a`, the Example's page keys — each to learn to refuse
  ⌘. Instead the input chain gives a ⌘ chord a short chain of its own
  (`InputHandler.dispatchCommandChord(_:)`): the focus path's `onKeyPress`
  handlers, then the app's shortcuts, and nothing else. No layer that never
  heard of ⌘ can take one for a bare key, now or when a new layer is added;
  the price is that an `onKeyEvent` handler never hears a ⌘ chord, which it
  never could. TUI's own `onKeyPress` handlers that mean a typed character
  refuse ⌘ themselves: the file panel's `~` and `/`, and the text editor's
  find keys (⌃F, ⌃G).
- **Default shortcuts unchanged.** A shortcut written with ⌘ registers on its
  stand-in (`.commandKey(_:)`, Control by default) and nowhere else, so it
  fires the same on every terminal. TUI's own bindings — undo and redo and
  the row keys (written with Control), the copy, cut and paste commands and a
  split view's sidebar chords (written with ⌘) — keep to their stand-ins, the
  opt-in or not.
- **The opt-in:** `.keyboardShortcutsMatchCommand(_:)`, an environment value
  (`\.keyboardShortcutsMatchCommand`) by the modifier-first rule, read where a
  `Button`'s, a `Toggle`'s or a scene's shortcut registers. On, a shortcut
  written with ⌘ registers on its real-⌘ trigger as well as on its stand-in
  (`KeyboardShortcut.commandChord(matching:)`): both fire, the precedence this
  entry recommended, so a chord the terminal keeps stays reachable. Under
  `.commandKey(.unavailable)` nothing fires, a real ⌘ included. A shortcut
  written with Control never fires on ⌘.
- **Cost.** Off (the default), nothing per frame: the second registration is
  made only where the app asked. On, one more dictionary insert per ⌘
  shortcut per frame, replayed from a memo as the first is. Per key, a ⌘
  chord is offered to two layers instead of the whole chain.
- **Not measured:** which ⌘ chords kitty and Ghostty pass to an app comes
  from their documentation (`Terminal compatibility survey.md`, "Command is
  never reported"). Tests: `CommandChordTests`, `KittyKeyDecoderTests`.

### B-D1K-2. A modifier-key alternate in a menu does not inherit the modified view's shortcut

*`View.modifierKeyAlternate(_:_:)`*

SwiftUI turns an alternate inside a menu into an alternate menu item and
gives it the modified view's keyboard shortcut with the alternate's modifiers
added: `Button("Save").keyboardShortcut("s").modifierKeyAlternate(.option) {
Button("Save All") }` makes Save All ⌥⌘S, live whether or not the menu is
open.

**Shipped:** the alternate replaces the modified view — a row in a menu
included — while its keys are held, and takes no shortcut of its own. An app
that wants ⌥⌘S for Save All writes `.keyboardShortcut("s", modifiers:
[.command, .option])` on it, which works on every terminal.

**The fuller version** registers the alternate's derived shortcut whether or
not it is drawn. The alternate's action is only reachable by rendering it, so
this means rendering the alternate on every frame into a throwaway buffer (or
a registration-only walk), reading the modified view's resolved shortcut out
of its environment, and registering the union. Half a day, and a small cost on
every frame that has an alternate.

**Known, and left as they are** (found reading the code in the lane's second
review; not reproduced). While an alternate shows, the modified view keeps
its `@State` and gets its focus back when the keys are released, but:

1. The focus comes back by a `focus(id:)` asked during the render, before the
   control registers; the neighbour the focus recovered to has already drawn
   as focused, so for one frame two controls show the focus. The next frame
   is right.
2. An alternate shown for a single frame gives the focus back
   unconditionally: Option, Tab and Option's release read in one burst of
   input undo the Tab.
3. The modified view's lifecycle ends while the alternate shows: its
   `onDisappear` runs and its `.task` restarts at every tap of the key, as
   for any view that leaves the screen.

Each wants the alternate to stand in for the modified view without the view
leaving the tree, which is the fuller version's registration-only walk again.

**The three fixed (lane INPUT, 2026-10-18), the shortcut still not.** While
an alternate shows, the modified view is walked into a picture nobody sees,
out of the focus ring and every key channel and asking for no frame
(`ModifierKeyAlternateModifier.walkHidden`, as a backdrop renders): its state
and its lifecycle go on, so no `onDisappear` runs and no `.task` restarts
(3), and the subtree retention it replaces is gone. The focus is given back
as the keys are released, between frames (`ModifierKeyMonitor.record`), the
recovery's neighbour first letting go of it, so no frame draws two controls
focused (1); and where the recovery put the focus is taken as the frame that
first drew the alternate ends (`ModifierKeyMonitor.endFrame()`), so a Tab read
in the same burst as the keys' release is the user's move, and stands (2).
`ModifierKeyAlternateTests` pins all three through the input chain and, for
the lifecycle, the run loop; each failed before. The alternate's shortcut,
derived or explicit, is still reached only by drawing the alternate:
decisions-INPUT B-INPUT-2.

### B-D1K-3. Ctrl-H, I, J, M and [ fall back to their legacy keys when nothing binds them

*`KeyboardShortcut.isDeliverableInTerminal`, `KeyboardReporting.disambiguatesKeys`*

The protocol delivers these five as themselves, which is what makes them
bindable. But nothing binds them by default, and on every legacy terminal they
are Backspace, Tab, Return and Escape — Ctrl-[ to leave, Ctrl-H to rub out.

**Shipped:** a chord nothing in the input chain takes goes round once more as
the key it would have been. A binding on it still wins.

**The alternative** is to leave an unbound chord inert, as most of them are
in SwiftUI on macOS (the text system does bind ⌃H to delete backward, as the
fallback does; ⌃[ and ⌃M are nothing there). That would be truer to SwiftUI
and would break muscle memory on exactly the terminals that got better; I
chose the fallback. Free either way.

### B-D1K-4. `TUIKIT_KEYBOARD_PROTOCOL=0` keeps TUI from asking for the kitty protocol

*`EnvironmentValues.keyboardReporting`*

Not asked for, and nothing to decide on its own, but a new user-facing switch,
so recorded. The protocol is negotiated with every terminal that answers the
query. A terminal that answers and then encodes keys in a way TUI misreads
would leave a user unable to type into any TUI app on it, so the user gets
the same way out the hyperlink and graphics switches give:
`TUIKIT_KEYBOARD_PROTOCOL=0`, and the terminal stays in its legacy encodings.

**The fuller version** is a programmatic override for an app, as
`TerminalClient.hyperlinkSupport` is for links. Not built: nothing yet says an
app needs one. A quarter of a day.

### B-D1K-8. All five kitty flags are pushed, and a killed app leaves a shell that cannot read Return

*`EnvironmentValues.keyboardReporting`*

Chosen as the brief asked — "releases need 2, modifiers-alone need 8 … the
spec's 'report associated text' (16) and 'alternate keys' (4) exist for
exactly that" — so flag 8 is on, and with it every key, Return included, is an
escape code. Quit, Ctrl-C, a suspend, `SIGINT` and `SIGTERM` pop the flags in an
orderly teardown; the crash signals (a trap, a bad access, `abort`,
`SIGQUIT`, `SIGSYS`) and the quiet terminations nothing else handles
(`SIGHUP`, `SIGUSR1`/`2`, `SIGALRM`, `SIGVTALRM`, `SIGPROF`, `SIGXCPU`,
`SIGXFSZ`, where the app has no handler of its own) pop them from a signal
handler, which also turns off the other input modes and puts the shell's
termios back (the PTY smoke covers quit, suspend, abort, `SIGHUP`, `SIGUSR1`
and `SIGTERM`). `SIGKILL` cannot be caught: the terminal is then left on the
alternate screen with the flags pushed, and the shell cannot read Return;
closing the tab, or a terminal reset, recovers it.

**The alternative** is flags 1, 2 and 4 only: Return, Tab and Backspace stay
legacy (the specification keeps them so for exactly this reason), and
releases, repeats and the Ctrl chords still work, but modifier keys alone,
Caps Lock on text keys and the keypad's digits are lost —
`onModifierKeysChanged` and `modifierKeyAlternate` would never fire. Free to
switch; `KittyKeyboardFlags.requested` is the one place.

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
one is installed by TUI users, it should also override the SIGQUIT
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

### B-F2-4. Under the kitty keyboard protocol, a hung app quits at the second ⌃\\

*The owner's request of 2026-10-05: ⌃\\ quits, as a real `SIGQUIT`, even when
the app hangs.*

Raw mode leaves the line discipline one signal character, the user's quit
key, so the driver raises `SIGQUIT` for ⌃\\ before the app reads a byte,
hung or not, over ssh too. But where the terminal speaks the kitty keyboard
protocol, TUI pushes its "disambiguate" flag (with the other four, for the
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
  screen, where TUI pushed, a pop of an empty stack is harmless.
- Measured against the PTY smoke's terminal only; real hosts unmeasured.

**To veto:** delete `StallWatchdog` and its three call sites (the run loop,
`Terminal.refreshStallWatch`, the write gate around writes); a hung app under
the protocol then does not quit by ⌃\\ again, as before.

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
