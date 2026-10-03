# Completing the SwiftUI API: Wave 7 (input) decisions

*Written in the format of
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md),
to be folded into it. Numbering is local to this file.*

---

## A. Needs your decision

### A-W7-1. Speak the kitty keyboard protocol where the terminal does?

*`KeyPress.Phases.up` (and a real `.repeat`), `View.onModifierKeysChanged(mask:initial:_:)`,
`View.modifierKeyAlternate(_:_:)`; and, as by-products, `EventModifiers.capsLock`
and `.numericPad`, and `KeyboardShortcut.Localization`'s remapping*

Four of this wave's gaps share one cause. A terminal's legacy key encoding
reports a key going down and nothing else:

- no release;
- no repeat flag;
- no modifier pressed on its own;
- no lock state.

The kitty keyboard protocol reports all of those, once an app asks for it with
`CSI > flags u`. Flag 2 reports event types (press, repeat, release). Flag 8
reports every key as an escape code, including the modifiers themselves. kitty,
Ghostty, WezTerm and foot implement it, and recent iTerm2 and Alacritty
releases say they do. That is from their documentation, not measured here.
Apple Terminal does not.

Until this is decided:

- `.up` is absent, and every press is `.down` (B-W7-1).
- `onModifierKeysChanged` and `modifierKeyAlternate` are absent: on a legacy
  terminal they could never fire.
- Caps Lock and the numeric pad never match (the `EventModifiers.command`
  precedent).

**Options.**

1. **Stay on the legacy encoding.** Free. The four APIs stay absent for good,
   on every terminal, including the ones that could honour them.
2. **Negotiate flags 1 + 2 + 8 where the terminal answers the `CSI ? u`
   query, and keep the legacy decoder for the rest.** Roughly three to four
   days:
   - the negotiation and its teardown on suspend, exit and crash, beside the
     modes `Terminal` already restores;
   - a `CSI … u` decoder;
   - `KeyEvent` gaining a phase, and every consumer learning to ignore
     releases;
   - a per-terminal survey into `Terminal-compatibility.md`.

   It also fixes things outside this wave. Ctrl-H, Ctrl-I, Ctrl-J, Ctrl-M and
   Ctrl-[ become deliverable shortcuts. Shift on a printable key becomes a real
   bit. A held key's repeats become identifiable.
3. **Option 2 with flag 1 only (disambiguate).** About a day and a half. Fixes
   the C0 collisions and nothing in this wave.

Under option 2 a second question follows, and it is about the rule rather
than the code. Should `.up`, `onModifierKeysChanged` and `modifierKeyAlternate`
**compile everywhere** and fire only where the protocol is spoken, documented
per terminal as `EventModifiers.command` is? Or should they stay absent, since
on Apple Terminal they would be silent?

**Recommendation:** option 2. On the second question: compile everywhere, with
a runtime query (a `\.keyboardReportsReleases`-style environment value) so an
app can offer its own fallback. Leaving the APIs absent would deny them to
every terminal that can honour them in order to protect the one that cannot.

### A-W7-2. `onInteractiveResizeChange`: synthesise a live resize from `SIGWINCH`?

*`View.onInteractiveResizeChange(_:)`*

macOS calls the action with `true` when the user starts dragging a window edge
and `false` when they let go. Its documented use is to throttle expensive
drawing during the drag.

A terminal sends `SIGWINCH` once per size change and says nothing about a
drag. Dragging a terminal window's edge sends a burst of them. So do a font
size change and a tmux pane resize, as one or a few.

**Options.**

1. **Decline.** A terminal has no notion of a live resize, so nothing can say
   when one begins or ends.
2. **Synthesise it.** `true` at the first `SIGWINCH` after a quiet period;
   `false` once none has arrived for about 200 ms. That is the same kind of
   inference the dispatcher already makes for double-clicks, which a terminal
   does not report either. Roughly half a day: the signal path already wakes
   the run loop, and the quiet-period timer needs a wake of its own.

**Recommendation:** 2. A TUI re-lays out the whole screen on every
`SIGWINCH`, which is exactly the cost the API exists to manage. It would be
documented as "a burst of resizes", because a font-size change counts as
one.

## B. Shipped the safe option

### B-W7-1. Key-press phases: every press is `.down`, and there is no `.up`

*`KeyPress.Phases.down`, `.repeat`, `.up`, `.all`; `KeyPress.phase`*

SwiftUI tells three phases apart: the press, each auto-repeat of a held key,
and the release. Measured on macOS 15, a `phases: .up` handler hears only the
release, and the default `[.down, .repeat]` hears the press and its repeats.

A terminal in its legacy encoding reports none of that. A held key's repeats
arrive as more copies of the same bytes, and a release sends nothing at all.

**Shipped:**

- `.down`, `.repeat` and `.all` exist, with SwiftUI's raw values (1, 2,
  `Int.max`).
- Every press is reported as `.down`.
- A handler whose phases include `.down` or `.repeat` hears every press. So
  the default, and an explicit `[.down, .repeat]`, mean exactly what they mean
  in SwiftUI. A `.down`-only handler also hears the repeats, and a
  `.repeat`-only one also hears the first press. Both over-fire visibly; neither
  drops anything silently.
- `.up` is absent, so `onKeyPress(phases: .up)` and `press.phase == .up` fail
  to compile. A release handler could never run.

**The fuller version** is the kitty keyboard protocol, which reports press,
repeat and release explicitly on the terminals that speak it. It is priced in
A-W7-1, together with the open question of whether `.up` should then compile
on terminals that will never fire it.

### B-W7-2. `KeyboardShortcut.Localization` is recorded, and every strategy behaves as `.custom`

*`KeyboardShortcut.Localization` (`.automatic`, `.withoutMirroring`,
`.custom`), `KeyboardShortcut.localization`,
`KeyboardShortcut.init(_:modifiers:localization:)`,
`View.keyboardShortcut(_:modifiers:localization:)`*

On macOS, `.automatic` (the default) does two things.

- It remaps a shortcut whose character is awkward on the user's layout. `⌘[`
  needs ⌥5 on a German keyboard, so it becomes `⌘Ö`.
- It mirrors a directional shortcut under a right-to-left layout.

`.withoutMirroring` remaps but does not mirror, and `.custom` does neither.

**Shipped:** the type, the three values, the stored property (compared, so
`KeyboardShortcut("a", localization: .custom) != KeyboardShortcut("a")` as on
macOS), the initializer and the modifier. All three behave as `.custom`.

That is honest on its own, because neither half has anything to act on:

- A terminal reports the character a key typed, never the key's place on
  the keyboard. A shortcut already matches its character however the
  layout types it, and there is no US-layout position to remap from.
- TUIkit lays out left to right only (B1 in the main decisions doc), so
  there is nothing to mirror.

**The fuller version:**

- *Mirroring* comes free with right-to-left layout, if B1 is ever taken up.
  Mirror `[`/`]` and `{`/`}` under `.automatic` and leave them under the
  other two.
- *Remapping* would need the key's position. The kitty keyboard protocol's
  "report alternate keys" enhancement sends the base-layout key alongside
  the character, so it is the same negotiation A-W7-1 prices, plus a
  remapping table. That table is AppKit's, and it is not public, so it would
  have to be inferred per layout. I would not do it: an app that wants
  layout-aware shortcuts in a terminal is better served by bare keys.

### B-W7-3. Copy, cut and paste commands carry text, and exist only where `NSItemProvider` does

*`View.onCopyCommand(perform:)`, `View.onCutCommand(perform:)`,
`View.onPasteCommand(of:perform:)`, `View.onPasteCommand(of:validator:perform:)`*

**Shipped:**

- On Apple platforms, all four, on the focus path's command stage.
- The keys are SwiftUI's ⌘C, ⌘X and ⌘V resolved through `\.commandKey`
  (Control by default). A paste is also the terminal's own bracketed paste.
- A copy or cut writes the text of every item that loads as a string, one
  per line. A paste offers one item, the clipboard's text, and triggers only
  for a type that accepts text.

The terminal's clipboard holds one string, so what does not read as text (an
image, a file promise) is not written. That is the medium, not a stub: the
action still runs, and a cut still deletes.

**Absent on Linux**, because swift-corelibs-foundation has no `NSItemProvider`
and there is no `UniformTypeIdentifiers`. Gated
`#if canImport(UniformTypeIdentifiers)`, so the same source fails to compile
there rather than compiling to nothing.

**The fuller version** would be a TUIkit-specific spelling that takes and
returns `String`s and works on every platform: `onCopyCommand(text:)`, say.
That is an addition, not a fix, so I have not made it. Say if you want it.

### B-W7-4. Item-provider drag and drop stays in the app, and only cancel and forbidden change a drop

*`View.onDrag(_:)`, `View.onDrag(_:preview:)`, `View.itemProvider(_:)`, `View.onDrop(of:isTargeted:perform:)`,
`View.onDrop(of:delegate:)`, `DropDelegate`, `DropInfo.hasItemsConforming(to:)`,
`DropInfo.itemProviders(for:)`, `DropOperation` (+ `.Set`), `DropProposal`*

**Shipped:**

- On Apple platforms, the four modifiers and the delegate, riding TUIkit's
  in-app drag session. An `onDrag` provider, or a `draggable` string or URL
  wrapped as SwiftUI wraps a `Transferable`, lands in an `onDrop` whose types
  it conforms to.
- The delegate is called in SwiftUI's order: validate once, enter, update on
  each move, then exit or perform.
- `DropOperation`, its `Set` and `DropProposal` are values everywhere.

Two things SwiftUI's drop does are not here:

- *The operation's meaning.* A proposal of `.cancel` or `.forbidden` refuses
  the drop, and the drag goes home. `.copy`, `.move`, `.delete` and `.alias`
  all accept it. On macOS they differ in the pointer's badge and in what the
  source application is told. A TUIkit drag has no badge and never leaves the
  app, so the delegate's `performDrop` is where any difference has to be
  made.
- *`operationOutsideApplication`.* It is recorded and never applies.

`DropOperation.Set`'s raw values are TUIkit's own: SwiftUI does not document
its own, and it is macOS 26 only, so it could not be probed on this machine.

**The fuller version:** a badge beside the drag preview naming the proposed
operation (`+` for copy, as Finder draws), and a source-side callback when a
drop completes with `.move` or `.delete`. SwiftUI's is `onDragSessionUpdated`,
which the `DragSession*` family rule declines. About half a day for the
badge; the callback belongs with that family's re-examination in Wave 17.

## C. Declined without asking

### C-W7-1. `KeyEquivalent.clear`

*`KeyEquivalent.clear`*

SwiftUI's `.clear` is AppKit's Clear key, U+F739: the keypad key in Num
Lock's position on a full-size Mac keyboard. A shortcut or `onKeyPress` on it
fires only if a terminal sends that key as a key of its own. The legacy
encodings TUIkit parses have no sequence for it, and the parser has nothing
to map to it. So `.clear` would name a key no event can carry, and a
shortcut on it would compile and never fire. Rule 2 says leave it out.

Not byte-captured: this machine has no extended keyboard. If a terminal turns
out to send the key, distinctly from Num Lock, the parser gains a case and
this entry goes. The kitty keyboard protocol of A-W7-1 is the likeliest
route: it reports keypad keys by their own codes.
