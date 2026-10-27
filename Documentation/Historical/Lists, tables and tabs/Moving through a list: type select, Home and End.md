# Moving through a list: type select, Home and End

*What typing a letter does in a list or table, when a bare key reaches a
shortcut instead, and where Home and End go. Ids: B77, B77-KEYTIME,
B77-SELECT, B-LISTS2-2.*

## In short

Typed characters move the cursor to the first row they prefix (type select),
without selecting it, as the arrows do. Where type select exists — lists,
tables, open drop-downs and open menus — every bare character goes to it and
none to a shortcut; the status bar leaves out what cannot fire there. Home and
End go to the list's top and bottom.

## How it unfolded

1. **B77** shipped type select, with a prefix's first character giving way to
   bare-key bindings.
2. **2026-10-23, the owner.** B77-KEYTIME: where type select exists, bare keys
   never pass to shortcuts (built by lane KEYS, 2026-10-24). B77-SELECT: keep
   cursor-only.
3. **2026-10-19, lane LISTS2** sent Home and End to the top and bottom
   (B-LISTS2-2).

## The record

### B77. Type select moves the cursor, and a prefix's first character gives way to bare-key bindings

*`View.typeSelectEquivalent(_:)` (all four)*

macOS type select, in a focused table or outline: typing a few characters
selects the first row after the selection whose text starts with them, and a
key no row answers to beeps.

**Shipped:** with a list or table focused, a typed character without Control
or Option (and not Space, which selects) joins a prefix, which a second's
pause starts afresh; the next render moves the cursor to the first row whose
text starts with the prefix, ignoring case — after the cursor for a first
character, at it for a longer prefix — and scrolls it into view. A row's text
is its stated `typeSelectEquivalent(_:)`, else a list row's first line of text
(drawn as a measure for a row out of sight, which registers nothing) or a
table row's first column. An empty equivalent takes the row out.

Where it differs:

- **The cursor moves, not the selection.** TUI's lists and tables move the
  cursor with the arrow keys and select with Return or Space; type select
  follows them. Selecting as well is a line, if the owner prefers macOS's
  behaviour for this one gesture.
- **A prefix's first character gives way to bare-key bindings.** macOS's
  shortcuts take Command, so its type select never meets one; TUI binds
  bare keys — its own `q` (quit), `t` (theme), `a` (appearance) and help key,
  and any bare `.keyboardShortcut` an app registers. The first character of a
  prefix goes to such a binding (the Stress `themes` session presses `t` with
  a list focused, and caught it); once a prefix is under way every character
  continues it, or typing "Atlas" would cycle the theme at the `t`. So a row
  whose name starts with a bound letter is not found by typing that letter
  first. Any other character is taken whether or not a row answers to it, as
  macOS takes it. The alternative — resolve the prefix when the key arrives
  and pass on a key no row answers to — needs every row's text at key time,
  measured outside a render; a day.

**Ruled (owner, 2026-10-23, B77-KEYTIME), and built (lane KEYS, 2026-10-24):**
"Where type select exists, bare keys never pass to shortcuts." The give-way
is gone: a focused list or table, an open `Picker` drop-down and an open
pop-up menu take every character type select takes (`TypeSelectBuffer.takes`:
printable, not Space, no Control, Option or ⌘), the first of a prefix
included, whether or not a row answers to it — as macOS does, and without
needing every row's text when the key arrives. So while one has the focus no
bare-key binding hears such a character: TUI's `q`, `t`, `a` and help key,
an app's bare `.keyboardShortcut`, a menu row's bare key equivalent, and a
status-bar item with an action on one. The user leaves the list, or uses a
modified key, an F-key or the menu bar. The status bar stops advertising what
cannot fire: while type select holds the focus it leaves out the user items
with an action on such a key (which also stops them matching at layer 1,
ahead of the focused control) and its own `q`, `a` and `t`
(`StatusBarState.typeSelectHoldsTypedKeys`). An item with no action stays, as
it may name a key an `onKeyEvent` handler takes; those come before the
focused control by design and still hear it. The cost is a focus lookup per
time the bar's items are gathered, made only when an item names such a key.
The Stress `themes` session presses `t` from outside the list and the table
now. Tests: `TypeSelectKeepsBareKeysTests`, `MenuTypeSelectTests`.

### B-LISTS2-2. Home and End go to the list's top and bottom

*`List` and `Table` keys (a consequence of decisions B76's header and footer rows)*

Home put the cursor on the first row it can land on and revealed that row
alone, so a row above it the cursor cannot reach — a section's header where
it is not pinned, a row the selection cannot name, a tab view sidebar's
header — stayed out of sight, and with it any control in it, a Tab stop only
while drawn. End did the same at the bottom.

**Shipped:** Home scrolls to the top and End to the bottom before revealing
the cursor, as macOS's Home and End go to a list's top and bottom; the cursor
still wins where the rows beyond it are taller than the window. Nothing
changes for a list whose first and last rows the cursor can land on.

**The alternative:** reveal the rows beyond the cursor whenever it reaches
the first or last landable row by any key — an Up onto the first tab would
then show the sidebar's header too. The reveal runs on every cursor move, so
it is a test of the landing set on each; about an hour, if the owner prefers
it.
