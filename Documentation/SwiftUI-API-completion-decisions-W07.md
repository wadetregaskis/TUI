# Completing the SwiftUI API: Wave 7 (input) decisions

*Written in the format of
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md),
to be folded into it. Numbering is local to this file.*

---

## A. Needs your decision

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

**The fuller version** is the kitty keyboard protocol's "report event types"
enhancement (`CSI > flags u` with flag 2, and flag 8, "report all keys as
escape codes", so that the keys that type text are reported too). Where a
terminal speaks it, it reports press, repeat and release explicitly. kitty,
Ghostty, WezTerm and foot implement it, and recent iTerm2 and Alacritty
releases say they do; that is from their documentation, not measured here.
Apple Terminal does not.

It would cost roughly two to three days:

- negotiating it at start-up and on resume, and popping it on suspend and
  exit, beside the modes `Terminal` already manages;
- a `CSI … u` decoder, with its own modifier and lock-state bits (which would
  also make `EventModifiers.capsLock` reportable on those terminals);
- `KeyEvent` gaining a phase, and every consumer that treats an event as a
  press learning to ignore releases;
- measuring each terminal into `Terminal-compatibility.md`.

`.up` would then exist only as an honest compile-time option if the framework
can say, per terminal, whether it will ever fire. That is the open question:
whether a capability that works in Ghostty and not in Apple Terminal should
compile everywhere. I would answer it the way `EventModifiers.command` was
answered (it compiles; the documentation says where it fires), but that is a
change to the rule, so it is yours.

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
  the character, so it is the same negotiation B-W7-1 prices, plus a
  remapping table. That table is AppKit's, and it is not public, so it would
  have to be inferred per layout. I would not do it: an app that wants
  layout-aware shortcuts in a terminal is better served by bare keys.

## C. Declined without asking
