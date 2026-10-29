# Selecting screen text from the keyboard

**Status:** proposal, shelved by the owner on 2026-10-29. Screen selection
stays a pointer-only feature, an extra rather than a function anything
depends on. This page records the options, so the question need not be
worked out again if it comes back. The [Future options](<../Future options.md#selecting-screen-text-from-the-keyboard>)
entry links here.

**The gap.** TUI's screen selection, a drag across what is drawn and then
Copy (A13, shipped 2026-10-05; since 2026-10-28 it keeps its highlight to the
`Text` frames it crosses), starts only with the pointer. The project's rule is
that every pointer interaction has a keyboard route, or is a recorded
exception. Text that can be edited already has its own keyboard selection
(Shift and the arrows, select-all). What has no keyboard route is copying
text the app only *shows*: a label, a value in a table, a log line, an error
message.

**What already exists to build on:**

- Every `Text` files its frame while a selection is being made or shown
  (`HitTestRegion.HandlerID.textFrame`, `filesTextFrames`), so the screen can
  be read as blocks of text, not only as cells.
- `textSelection(_:)` and `TextSelectability` are SwiftUI's API for marking
  text as selectable, and TUI has them.
- The keyboard carry (A53-KEYBOARD-DRAG) shows a modal keyboard mode done
  well: one chord enters it, the focus ring is restricted to the mode's
  places, Escape leaves it, and the status line says what the keys do.
- Two earlier designs are near this one: handing the mouse to the terminal
  (A13.2, deferred for want of a key) and selection that follows one `Text`
  (A13.5, D2 of the 2026-10-04 text-editing study). Both are in Future
  options.

**Entering any of the modes below** is the old A13.2 problem: no chord is
free. Control letters are the text controls' editing keys and, under the
default command key, the app's ⌘ shortcuts. Option does not arrive everywhere.
F-keys are prime. The way out that Customize Toolbar takes (2026-10-29) works
here too: put a menu item, Edit ▸ Select Text on Screen…, in TUI's own Edit
menu. The keyboard reaches it through the menu bar (F10, then ← or → to Edit),
and no chord is spent. An app that wants a chord can bind one to the same
action.

---

## Option A: selectable `Text` as focus stops (the SwiftUI-parity route)

**What it is.** A `Text` under `.textSelection(.enabled)` becomes a focus
stop. With it focused, Shift and the arrows select within it, by character
and with Option by word; ⌃⌥A selects all of it; ⌘C (⌃C by default) copies.
The selection is drawn with the screen selection's highlight.

**Why it fits.** It is SwiftUI's own API, it works in a terminal with no new
mode, and the app chooses what is selectable, as on macOS: an app marks its
values and log lines, and not its chrome.

**Costs and risks.** About a day. Focus stops are added to the Tab order, so
a page with many selectable texts gets a long ring, and SwiftUI on macOS
doesn't put selectable `Text` in the key loop by default either. The fix is
for such texts to be reachable by arrows within their section, not by Tab
(the focus-section machinery has that). It covers only text the app opted
in.

## Option B: hints (kitty's hints kitten, Vimium)

**What it is.** The menu item, or a chord, labels every block of text on
screen with one or two letters drawn over its first cells, using the filed
`Text` frames, and cells of other drawing grouped into runs by blanks.
Typing a label copies that block, and a note on the status line says so.
Typing it with Shift (or pressing Return after it) instead starts a screen
selection there, which Shift and the arrows extend, by character, or with
Option by word, and Return copies. Escape leaves.

**Why it fits.** It is the most terminal-native option and the quickest to
use: "copy that value" is two keystrokes after entering. It works on
anything drawn, without the app's cooperation, as the pointer's selection
does.

**Costs and risks.** About a day. Labels are drawn as an overlay layer after
the frame, as the carry's markers are. On a dense screen the labels can hide
what they label, so two-letter labels and a blank cell's offset are needed.
The text of a block is the screen selection's reading of those cells, so it
copies what is drawn, truncation ellipses included, as the pointer does.

## Option C: copy mode (tmux, screen)

**What it is.** A cell cursor appears on the screen. The arrows, Page Up and
Page Down, Home and End, and Option with the arrows for words move it.
Space marks the start, the cursor extends the selection as the pointer's drag
would (by character, or a rectangle with Option held as the drag's
Option-drag does), Return copies and leaves, and Escape leaves.

**Why it fits.** It is the most complete: anything a drag can select, the
keys can, cell for cell, and it is familiar to tmux users.

**Costs and risks.** One to two days. It is modal for longer than the
others, and it moves through cells, not meaning, so selecting a value takes
many keystrokes. It has to suspend the app's own key handling while it runs,
as the carry does. A scrolling view under the cursor would want to scroll to
let the cursor past the edge, which the screen selection never does (it
reads only what is drawn), so the first version would stop at the visible
edge.

## Option D: Copy on the focused control

**What it is.** ⌘C (⌃C by default) with a non-text control focused, and
nothing selected anywhere, copies that control's text: a button's title, a
row's text, a label-value pair's value.

**Why it fits.** It is the smallest (half a day), it needs no mode, and it
covers the commonest case, copying the value of the thing you're on. macOS
itself does not do this for controls; some apps do it for table rows.

**Costs and risks.** "The control's text" has to be defined for every
control, so most of the work is a per-control answer. It overlaps the
clipboard keys, which today pass an unclaimed ⌃C on to the app (and to
`QuitShortcut.ctrlC`), so it must take ⌃C only where there is something to
copy.

---

## If this is revisited

**Recommendation, as of 2026-10-29:** B, entered from the Edit menu item.
It is the cheapest option that covers anything drawn, it fits the terminal
(kitty, Vimium and tmux's own "copy mode with hints" plugins all converge
on it), and it reuses the text frames and the carry's overlay. A follows if
apps ask for SwiftUI's selectable-text behaviour from the keyboard. C is the
fallback for exact cell selections. D is a separate small convenience.

**What would reopen it:** a user who cannot use a pointer (an accessibility
need, or a terminal or remote session without mouse reporting) and needs to
copy text an app only shows, or an app that ports SwiftUI code relying on
`textSelection(.enabled)`.
