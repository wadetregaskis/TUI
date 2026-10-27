# Undo

*How TUI came to have undo: `UndoManager` on every platform, a text control's
undo steps, the undo and redo keys, undoable reorders, and what the owner has
asked for since. Ids: A1, B-D1K-5 to 7, FB9-REDO, B-TEXT2-3,
B-PASTE-1-EDITOR.*

## In short

`UndoManager` is Foundation's on Apple platforms and TUI's own on Linux,
without notifications or selectors. `TextField` and `TextEditor` register
every edit, one step per event, for as long as the control lives; a secure
field has none. Undo is Ctrl-Z; ⌃Y redoes app-wide while text controls keep
it as yank, and the hints name another key while one has the focus. The
Example's reorders, deletions and drops are undoable through a TUI-only
helper.

## How it unfolded

1. **Lane D1K** built the owner's A1 (`UndoManager`), with B-D1K-5 to 7.
2. **2026-10-23, FB9-REDO:** (a), ⌃Y redoes app-wide; built 2026-10-24.
3. **2026-10-24, lane TEXT2:** the Example's reorders undoable (B-TEXT2-3).
4. **2026-10-26, the owner:** undo as edits rather than whole-text snapshots,
   rigorously tested against a whole-text model so the stack can never drift
   from the text (B-PASTE-1-EDITOR); and undo for every built-in control that
   changes a value — Toggle, radio, Picker, Slider, Stepper, DatePicker,
   ColorPicker and the rest. Both were built that night.

## Where it stands

Shipped as above, a text control's steps kept as edits, and the built-in
controls' values undoable (2026-10-26) but for the graphical `DatePicker`
calendar and the curve editors, which are owed.

## For a future reader

- **Undo as edits is checked against the snapshots it replaced.**
  `TextUndoHistoryDifferentialTests` keeps the snapshot history as its
  reference and drives both through 200 seeded random runs (edits, typing
  runs, undo, redo, replacements from outside, the step limit), comparing
  text, bytes, caret and marks after every operation. A change to the
  history's rules changes the reference with it, or the test fails.
- **A recorded step costs a scan of the text** (the common start and end of
  the text before and after it), once per step — a run of typing is one — not
  per key.

## The record

### B-D1K-5. `UndoManager` on Linux is TUI's own, without notifications or selectors

*`UndoManager` (where Foundation has none), `EnvironmentValues.undoManager`*

Decision A1 asked to check swift-corelibs-foundation's `UndoManager` on Linux.
It has none: against Swift 6.3.3's static Linux SDK `UndoManager()` is "cannot
find 'UndoManager' in scope", and `libFoundation.a` holds no undo symbols. So
`\.undoManager: UndoManager?` could not even be typed there.

**Shipped:** where Objective-C is absent, TUI declares `@MainActor open
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
which TUI's own `UndoManager` keeps too), and a key that would continue a
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
counterpart in the `UndoManager` TUI provides on Linux (B-D1K-5). While
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

### B-TEXT2-3. The Example's reorders, deletions and drops are undoable, through a TUI-only helper

*#16. The Lists page's editable list (`onMove`, `onDelete`), the Table page's
reorderable table, the rows that travel between two lists (`onMove`, a drop),
the Mouse page's shelf and basket (three drops) and its filing tag, and the
Focus page's command board (`onDeleteCommand`, `onExitCommand`)*

SwiftUI registers no undo for `onMove`, `onDelete` or a drop: the app owns
the data. Neither does TUI, and neither did the Example, so none of these
could be taken back. Each now registers its inverse with
`@Environment(\.undoManager)`, named "Move", "Delete", "Copy", "Discard" or
"Reset" (seven languages), which Edit ▸ Undo and Redo show. Checked live
under a PTY: two Ctrl-Down moves in the editable list, then two Ctrl-Z, put
the rows back one move at a time, the status bar offering "undo" and then
"redo".

The helper, `UndoManager.registerRestoring(_:to:actionName:)` in
`TUIFoundation/Undo/`, is TUI's own name, documented as such:
Foundation's `registerUndo(withTarget:handler:)` wants a class to call back,
which a `@State` array is not, so the step holds the binding and the old value
in a main-actor class, and its undo registers the redo, keeping the name. Two
values that change together (a row moved between lists) restore through one
binding to both. A drop that changed nothing registers nothing.

**The fuller version:** a diff-based step that undoes only what the change
did (a moved row moved back), so an undo does not also revert other edits
made to the same value since. *Price:* a day — a step per collection
operation (move, remove, insert) with its inverse, for `RangeReplaceableCollection`
and `MutableCollection`; the snapshot is exact for state a person edits a step
at a time, which is every case in the Example.

### B-PASTE-1-EDITOR. A text control's undo keeps edits, not the whole text

*`TextField`, `TextEditor` (their undo)*

A text control kept every undo step as the whole text before it: fifty steps
over a 16 MiB document held 800 MiB. Measured on that document, a
`Character` array took 0.51 s and 305 MiB to build and 0.25 s to join on
every edit, where a line table over UTF-8 took 0.009 s and 1.4 MiB; the
owner (2026-10-26): undo as edits, rigorously tested so the stack can never
drift from the text.

**Built (2026-10-26):** a step is kept as the edit it made (`TextEdit`): the
byte offset where the text changed, the bytes it lost and the bytes it
gained, found by scanning the text before and after for their common start
and end. Only the newest step keeps its text whole, until the step after it
shows where it ended. Undo splices the lost bytes back over the gained ones,
redo the other way, so each gives back exactly the bytes there were, whatever
grapheme clusters they straddled. A text that does not hold the bytes an edit
expects is one the history did not produce: it forgets itself rather than
splice into it. Every rule of the snapshot history stands — one step per edit,
a run of typing one step, the 50-step limit, the replacement check — and the
differential test holds the two to the same answers, but two, which the test
found and which changed in the reference too:

- **Texts compare by their bytes.** Swift's `==` takes canonically equivalent
  texts for one (a precomposed "é" and an "e" with a combining accent), so a
  text replaced by an equivalent one went unseen as a replacement — harmless
  while undo put back whole snapshots, not once it splices bytes.
- **An edit made where the record was not, because the text was unchanged,
  still forgets redo.** The snapshot history kept redo there, and a redo then
  brought back a text without the edit.

**Not done:** the editor's own storage (`[Character]`) is unchanged; the
owner's order was undo first, then, if memory still matters, one `String`
with a line table.

### B-PASTE-1-EDITOR (2). Undo for every built-in control that changes a value

*`Toggle`, `Picker`, `Slider`, `Stepper`, `DatePicker`, `ColorPicker` (their
values, from a person's input)*

SwiftUI's controls register nothing with the undo manager. The owner
(2026-10-26) asked for undo for every built-in control that changes a value.

**Built (2026-10-26):** `ControlValueUndo`. A control hands its input — its
key and pointer handlers — its binding wrapped (`RenderContext.undoable`), and
a person's write through it registers the step that puts the old value back
(`registerRestoring`), and its redo. A discrete control makes a step of every
change: `Toggle` (keys, clicks, a menu row), the menu, segmented and radio
`Picker`s. A continuous one makes one step of a run, as a text field does of
typing: a change made while its step is still the newest in the manager
(the text controls' mark, `TextUndoBridge.isNewestStep`) joins it, so the
undo goes back to where the run began — `Slider`, `Stepper`, a `DatePicker`'s
fields, a `ColorPicker`'s 256-colour and swatch grids (its channel sliders
are `Slider`s). Writes no person made are no step: the app's own, and a
control's clamp into range, which goes through the binding unwrapped. A write
of the value already there is none either. No action name, as the text
controls' steps have none.

**Not built:** the graphical `DatePicker` calendar (a style with a body,
where no render context holds a run), the curve editors, a `Toggle` governing
several sources (its undo restores the combined value, setting every source
alike). **For a future reader:** a new control with a value adopts it in one
line, `context.undoable(binding, coalescing:, propertyIndex:)`, at the point
its input handlers get the binding.

