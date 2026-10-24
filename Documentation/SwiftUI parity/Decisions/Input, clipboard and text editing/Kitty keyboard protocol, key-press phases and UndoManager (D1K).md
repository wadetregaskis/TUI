# Completing the SwiftUI API: decisions from lane D1K

*Lane D1K implemented the owner's decisions A4 (the kitty keyboard protocol),
B7 (key-press phases), B12 (button repeat by keyboard) and A1 (`UndoManager`).
Where that work reached a judgement call the decisions did not settle, the
safe option shipped and is written up here, in the format of
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>):
A for the owner to decide, B for a basic form shipped with its fuller version
priced, C for a refusal recorded in `parity-map.json`.*

## B. Shipped the safe option

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
  never could. TUIkit's own `onKeyPress` handlers that mean a typed character
  refuse ⌘ themselves: the file panel's `~` and `/`, and the text editor's
  find keys (⌃F, ⌃G).
- **Default shortcuts unchanged.** A shortcut written with ⌘ registers on its
  stand-in (`.commandKey(_:)`, Control by default) and nowhere else, so it
  fires the same on every terminal. TUIkit's own bindings — undo and redo and
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

### B-D1K-4. `TUIKIT_KEYBOARD_PROTOCOL=0` keeps TUIkit from asking for the kitty protocol

*`EnvironmentValues.keyboardReporting`*

Not asked for, and nothing to decide on its own, but a new user-facing switch,
so recorded. The protocol is negotiated with every terminal that answers the
query. A terminal that answers and then encodes keys in a way TUIkit misreads
would leave a user unable to type into any TUIkit app on it, so the user gets
the same way out the hyperlink and graphics switches give:
`TUIKIT_KEYBOARD_PROTOCOL=0`, and the terminal stays in its legacy encodings.

**The fuller version** is a programmatic override for an app, as
`TerminalClient.hyperlinkSupport` is for links. Not built: nothing yet says an
app needs one. A quarter of a day.

### B-D1K-5. `UndoManager` on Linux is TUIkit's own, without notifications or selectors

*`UndoManager` (where Foundation has none), `EnvironmentValues.undoManager`*

Decision A1 asked to check swift-corelibs-foundation's `UndoManager` on Linux.
It has none: against Swift 6.3.3's static Linux SDK `UndoManager()` is "cannot
find 'UndoManager' in scope", and `libFoundation.a` holds no undo symbols. So
`\.undoManager: UndoManager?` could not even be typed there.

**Shipped:** where Objective-C is absent, TUIkit declares `@MainActor open
class UndoManager` with Foundation's Swift surface — grouping (by event, by
default), registration with a target and a handler, undo, redo, nested undo,
enabling and disabling, levels of undo, removing actions (all, or a target's),
action names, menu titles in the app's language, discardability, and since
2026-10-18 an action's user info (macOS 15's API, which a text control's
typing run asks of the newest step, B-D1K-6) — backed by
`UndoStack`, which is tested on macOS against what `NSUndoManager` was
measured to do. Where `NSUndoManager` raises (an unbalanced end, undo inside an
explicit group, a top-level registration with grouping by event off), it does
nothing, or gives the action a step of its own: a TUI that raised would die
holding the terminal in raw mode. Inside an undo or redo's own handler too: an
unbalanced end does nothing, and a group the handler opened and left open is
closed with the undo, into its redo (until the review it trapped, and wedged
the stack, respectively); and `removeAllActions()` forgets every step but the
undo or redo that is running, which finishes, with what the handler registers
after it as its inverse (`NSUndoManager` raises there, measured on macOS 15;
until the second review this trapped). Absent, so failing to compile rather than
doing nothing: `registerUndo(withTarget:selector:object:)` and
`prepare(withInvocationTarget:)` (Objective-C only), `runLoopModes`, and the
`NSUndoManager…` notifications.

**The fuller version** posts the eight notifications through
`NotificationCenter` under Foundation's names, for an app that observes them
(`checkpoint`, `didOpenUndoGroup`, `willCloseUndoGroup`, `didCloseUndoGroup`,
`willUndoChange`, `didUndoChange`, `willRedoChange`, `didRedoChange`). Half a
day; nothing in the SwiftUI surface needs them.

If swift-corelibs-foundation ever ships an `UndoManager`, the two would clash
on Linux; the declaration's `#if` would then need a version condition.

### B-D1K-6. A text control's undo steps are per event, they last as long as the control, and a secure field has none

*`TextField`, `TextEditor`, `SecureField`, `EnvironmentValues.undoManager`*

**Shipped:** `TextField` and `TextEditor` register every edit with the app's
undo manager; each event's edits are one step (the manager's grouping by
event) — one key while keys arrive one per pass of the run loop, several
when they arrive together, a fast typist or a burst over ssh. A control's
steps stay in the app's history until the control leaves the screen, or
its own history lets them go (past its 50, or when the app replaces the
text), and then leave it, so the manager does not offer an undo that does
nothing. A control that leaves the screen is let go of as the next frame
begins, and its steps leave then, before that frame sizes the status bar:
its deinitialiser, which promises no isolation, leaves them on a list the
frame empties on the main actor. That holds for a control the focus ring no
longer lists, too (checked for a field disabled for two frames before it
went, 2026-10-05): the focus manager still holds it until the next frame
begins, so nothing is let go of at a frame's end for a second emptying
there to catch. Until then a Ctrl-Z still reaches the field that has just
gone — its binding changes, and the redo step leaves with the control. Every other removal is made at once: its
callers (a render, a key, a click) are on the main actor, which is asked of
the isolation, not the thread. Until the third review it asked
`Thread.isMainThread`, which on Linux is false on the main actor after its
first suspension (measured in `StackGuard`), so there every removal went to
a task that ran after the frame, the bar went on offering the steps, and
the tests of all this would have failed. A replacement — a field cleared on
submit, another document loaded into the editor — is seen where the control
renders, in the frame that draws the new text, before the status bar is
built and before the next key (until the second review it was seen only at
the control's next key, and `onSubmit { draft = "" }` left five dead undos
ahead of the app's older steps, with "undo" on the bar). The one exception
is an undo read in the
same burst of input as the replacement, before any frame: it finds the text
replaced and does nothing, and the control's other steps leave at the
frame. Taking them out from inside that undo is the one thing not done:
`NSUndoManager` keeps an emptied step for good when a handler removes others
(measured on macOS 15). A field's stay after it loses the focus: the lane first removed
them there, believing a macOS field editor drops its actions on resigning,
but nothing measured or documented says so, and the field's own Ctrl-Z
history had always outlived a change of focus. A `SecureField` registers
nothing and keeps the private Ctrl-Z it had: a password's keystrokes in the
app's history would be undoable from anywhere, which is not a thing a
secure field should offer (AppKit's secure text field is believed to keep
its typing out of the window's undo too; not measured).

**The fuller version** coalesces a typing run into one step, as the macOS text
system does: consecutive insertions with no caret move or pause between them
undo together. About half a day, with a timer or a "next non-typing key"
boundary to choose; the per-key step is what the controls already did on
their own.

**Fuller version shipped (lane INPUT, 2026-10-18; settled by the owner's
earlier rulings, open to veto).** Measured first, on macOS 15.8 with an
offscreen `NSTextView` (`Tools/SwiftUIProbes/Undo and the pointer leaving (INPUT)/`): typed
characters — a space, a newline and a tab among them — and Backspace undo as
one step while each is made at the caret the edit before it left, a pause of
two seconds included, so the boundary is neither a timer nor the next
non-typing key exactly, but the next edit that is not typing or a caret moved
elsewhere (one moved away and back does not end the run); Delete, a word's
deletion and a paste are steps of their own and end it; typing or Backspace
over a selection starts a new run that the typing after it continues; an undo
ends it. `TextUndoHistory` keeps the state the run's last edit left
(`record(text:caret:continuingTyping:)`, `noteTyped(text:caret:)`), and both
controls classify their keys the same way; a key that continues a run
registers nothing with the app's undo manager, so the run is one step there
too (`TextUndoCoalescingTests`, every measured case in a field and an
editor).

The lane's review found the run going on under a step registered after it:
"ab" in one field, "x" in another, and "c" back in the first undid "x" first
and then "abc", the "c" after the "x" it was typed before. Measured again,
with two `NSTextView`s sharing a window's undo manager: there "c" is a step
of its own, undone first, and so is typing after an action the app
registers mid-run, while the focus going away and back with nothing
registered meanwhile leaves the run going. So a run goes on only while its
step is the newest in the app's undo manager: each text step carries its
mark in the step's user info (macOS 15's `setActionUserInfoValue(_:forKey:)`,
which TUIkit's own `UndoManager` keeps too), and a key that would continue a
run asks whether the newest step is still its own
(`TextUndoBridge.isNewestStep(_:on:)`,
`TextUndoHistory.endTypingRun(unlessNewestIn:)`;
`TextUndoCoalescingTests.runEndsUnderAnotherControlsStep`,
`.runEndsUnderTheAppsStep`, `.runGoesOnPastAnotherControlsKeys`). Before
macOS 15 the step cannot be asked, and the run goes on as before.

The review also found the two controls classifying chords differently: a
vertical field's Ctrl-O and Option-Return insert their newline as typing,
and the editor took every Control and Option chord for a step of its own.
Measured on a plain-text `NSTextView`, the field is right: Option-Return's
newline and Option-Tab's tab join the run, and so does Ctrl-O's newline,
though the caret the chord moves back before it ends the run for the typing
after. The editor now does the same
(`TextUndoCoalescingTests.openLineInARun`, `.optionTabInARun`;
`.newlineChordsInAVerticalField` pins the field).

### B-D1K-7. The undo and redo keys are data, Ctrl-Z among them; redo's reach only some terminals, and the status bar is the route everywhere

*`EnvironmentValues.undoManager`, `UndoCommand`, `UndoShortcuts`,
`Scene.undoShortcuts(_:)`, `StatusBarState.showUndoItems`*

Decision A1 named the keys; the owner added Ctrl-Z on 2026-10-04 ("If
control-z works for undo, let's make that a shortcut for it too (with
control--). Just so long as there's a way to customise those shortcuts
app-wide, such as to remove control-z for apps which want to actually receive
the SIGTSTP signal."). In a legacy encoding Ctrl-_ is the same byte as
Ctrl-minus and Ctrl-Shift-Z the same as Ctrl-Z, both undo, so redo is on the
keyboard only where Option is sent as Meta (`ESC _`, delivered after the
parser's dead-sequence wait, about 200 ms, because `ESC _` also starts an APC
reply) or where the kitty protocol is spoken.

**Shipped:** the keys are `UndoCommand.defaultShortcuts` — undo on Ctrl-Z,
Ctrl-minus and Ctrl-/, redo on Ctrl-Shift-Z, Ctrl-_ and Option-_ — and the
TUI-only scene modifier `.undoShortcuts([.undo: …, .redo: …])` replaces
either list app-wide, with `rowShortcuts`' rules (the two tables share their
engine, `ShortcutTable`). A bound key is its command's whether or not there
is a step: Ctrl-Z with nothing to undo does nothing, never "sometimes
suspends"; taken out of undo, Ctrl-Z suspends exactly as before. The suspend
key is the pre-lane one, any Control chord on `z` that nothing took, so
Ctrl-Option-Z still suspends with the default keys, and under the kitty
protocol a redo list without Ctrl-Shift-Z (`.redo: .unbound`) gives that
chord back to the suspend; both are what a shell does with them. An app's own
shortcut on a chord still wins, and a focused text control's Ctrl-Z stays its
undo. The status bar's "undo" and "redo" appear while each has a step and
perform it on a click — on every terminal — each naming the first of its keys
the terminal can deliver as itself: `^-` for undo, `^_` for redo where the
protocol tells Ctrl-_ apart and `M-_` elsewhere, with the defaults. They name
the key and do not bind it: no key fires them, so a key an app binds is
matched only by the undo keys, at the bottom of the chain, step or no step
(the lane first let the bar read the name as a bare key, so an Option-←
undo made a plain ← undo). `showUndoItems` turns them off. Shown only while there is a step — but
`TextField` and `TextEditor` register their edits (B-D1K-6), so every app with
one shows "undo" once the user has typed in it; only an app with neither,
registering nothing of its own, never sees them. That is the point (the owner
wants undo), and an app with its own undo affordance turns them off.

**Their cost** is two reads of the manager per frame, `canUndo` and
`canRedo`, while the bar is shown. Kept: both are O(1), and a cache would
need to know when a step might have changed, which is not only on a key —
an app registers from a task or a timer too — so it would need the manager
to say so, and `NSUndoManager`'s checkpoint notifications have no
counterpart in the `UndoManager` TUIkit provides on Linux (B-D1K-5). While
there is a step, the bar also names its key: the table's chords for the
command, sorted and filtered by what the terminal can deliver, rebuilt in
every build of the bar and on every key that reaches layer 1. A handful of
chords, unmeasured and not cached; a cache would key on the table and the
terminal's reporting, both of which change only between frames.

**The alternative** is to show them always (greyed when empty): steadier, but
two more permanent entries in every app's bar. Free either way.

**⌃Y redoes (owner's ruling FB9-REDO, 2026-10-23, option (a) "with the
shortcut hint following focus"; built by lane KEYS, 2026-10-24).** Ctrl-Y
joins redo's defaults: `0x19` on every terminal in raw mode, so a redo key
reaches the app on Apple Terminal at its defaults, where none did. A focused
`TextField`, `SecureField` or `TextEditor` takes it first, as it takes every
key it edits with, and yanks — with or without a kill to yank — so the
emacs pair ⌃K/⌃Y is kept. The hint follows the focus: the status bar's
"redo" and the menu bar's Edit ▸ Redo name ⌃Y (after ⌃⇧Z, where the kitty
protocol sends that) and, while a text control has the focus, the next key
it does not keep (`TextInputFocusHandler.keepsFromUndoKeys(_:)`,
`AppUndoKeys.hint(for:sparing:)`): ⌥_ on a legacy terminal. Each command's
deliverable keys are kept in hint order until the table, the ⌘ binding or
the reporting changes, and the focus is asked only about those few kept
keys: a focus lookup per frame while there is a step.

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
