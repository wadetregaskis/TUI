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

## C. Declined without asking
