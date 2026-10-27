# How keys are named: shortcut symbols and spellings

*How a shortcut is drawn — the macOS symbols in macOS's order — how a key is
spelled out, how a status-bar item's own key is drawn, and the localization
strategies. Ids: B8, B-KS-1 to 5, B-KS-1's ruling of 2026-10-23, C4.*

## In short

Shortcuts are drawn with the Unicode symbols (⌃ ⌥ ⇧ ⌘ ⎋ …) in macOS's order,
the owner's request of 2026-10-05. Spelled out, keys take their English
terminal names. A status-bar item's key is drawn in a menu's spelling (`Q
quit`, `⇧N`) unless the app asks `.statusBarKeySpelling(.asTyped)`.
`KeyboardShortcut.Localization` is recorded and every strategy behaves as
`.custom` until right-to-left lands.

## How it unfolded

1. **2026-10-05, the owner:** "Keyboard shortcuts should use the appropriate
   Unicode characters wherever possible … And in the correct (macOS) order."
   Lane KS built it, with the calls below.
2. **2026-10-12, B8:** mirror the localization strategies once right-to-left
   lands.
3. **2026-10-23, B-KS-1:** menu spelling by default, with an option for the
   case-sensitive one; built by lane KEYS, 2026-10-24.

## The record

### B8. `KeyboardShortcut.Localization` is recorded, and every strategy behaves as `.custom`

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
- TUI lays out left to right only (B1 in the main decisions doc), so
  there is nothing to mirror.

**The fuller version:**

- *Mirroring* comes free with right-to-left layout, if B1 is ever taken up.
  Mirror the directional pairs under `.automatic` and leave them under the
  other two.
- *Remapping* would need the key's position. The kitty keyboard protocol's
  "report alternate keys" enhancement sends the base-layout key alongside
  the character, so it is the same negotiation as the kitty protocol's
  (A4, shipped 2026-10-05), plus a
  remapping table. That table is AppKit's, and it is not public, so it would
  have to be inferred per layout. I would not do it: an app that wants
  layout-aware shortcuts in a terminal is better served by bare keys.

**Decided 2026-10-12: mirror once right-to-left lands** (B1); one commit then,
the pairs under `.automatic` in a right-to-left environment. You asked how big
AppKit's tables are, and whether TUI could copy them:

- **The mirroring table is 10 characters, 5 pairs** (measured on macOS 15.8
  through AppKit's own mirroring call over U+0020–U+2FFF): `(`↔`)`, `<`↔`>`,
  `[`↔`]`, `{`↔`}`, `←`↔`→`. `NSMenuItem.h` in the macOS SDK documents the
  same list, so TUI can write it from the documentation and copy nothing.
- **The remapping is not a data file.** It is compiled AppKit code
  (`NSKeyboardShortcut`'s localization methods, found through the Objective-C
  runtime), possibly an algorithm over the layout's key map plus a cache of
  well-known shortcuts; its size is unknown, since sizing it would mean
  switching the system's input source through many layouts. It is Apple's
  proprietary code, so it cannot be copied.
- **Matching AppKit is not table-free either.** AppKit remaps only a shortcut
  the current layout cannot type (`NSMenuItem.h`). The kitty protocol's
  base-layout key gives a positional fallback, which TUI already uses for a
  Ctrl or Alt chord on a non-Latin key, but matching every shortcut by
  position would also move the reachable ones (⌘Z on the key labelled W on
  AZERTY), and a terminal does not say which characters the user's layout can
  type. Over ssh the local machine's layout is not the user's either. So the
  remap stays out until there is a source for that.

### B-KS-1. A status bar item's own string is drawn as the app wrote it

*`StatusBarItem(shortcut:label:)`*

The formatter names a key wherever TUI names one: a menu row's shortcut
column, `KeyboardShortcut.displayString`, the undo and redo hints, every
``Shortcut`` constant (so `Shortcut.enter` is now `↩` and `Shortcut.ctrl("q")`
is `⌃Q`). An item's `shortcut` string that an app typed itself — `"q"`, `"N"`,
`"c|C"`, `"1-9"` — is drawn as typed. So TUI's own quit item still reads
`q quit`, where a macOS menu would draw the key `Q`, and an app's `"N"` item
(Shift-N, in the status bar's vocabulary, where Shift is the case) still reads
`N`, not `⇧N`.

Why: the string is three things at once — what is drawn, the key it is bound to
(`"N"` matches Shift-N only), and the item's identity — and the bar's
vocabulary spells Shift as the case. Drawing `"q"` as `Q` would make every
status bar read as if it wanted Shift, and drawing `"N"` as `⇧N` needs the
drawn text to come apart from the string that binds the key.

The framework's own undo and redo hints follow the bar, not the menu, for the
same reason: a hint on a letter held with nothing but Shift is written in the
case it types (`u redo`, and `U redo` for Shift-U), where a menu would draw
`U` and `⇧U`. Drawn the menu's way, a redo on a bare u read `U` beside an
app's Shift-letter items, and the bar — which tells its items apart by that
string — hid it behind an app's `"U"` item (another key) and showed it beside
an app's `"u"` (the same key). A hint with ⌃, ⌥ or ⌘ is the menu's (`⌃Z`,
`⌃⇧Z`). The fuller version below takes the hints with it.

**The fuller version:** draw a single-character item's key through the
formatter (`Q`, `⇧N`), with the bound key unchanged. Half a day once the bar
draws an item's key from the key rather than from the string — which is the
A28 chrome lane's restructuring of the status bar into views, and is better
done there than beside it. It changes every app's status bar.

**Ruled (owner, 2026-10-23), and built (lane KEYS, 2026-10-24):** "menu
spelling by default, with an option for the case-sensitive one." The bar
draws a one-letter item key through `StatusBarKeySpelling.spelling(_:)`:
`.menu`, the default, draws a lower-case letter as its key cap (`Q quit`) and
an upper-case one as `⇧` and the letter (`⇧N`); `.asTyped` draws the string as
typed, as before. The string is untouched — it still binds the key, names the
item and is what the bar's de-duplication compares — so only the drawing
changed, and no restructuring of the bar into views was needed after all:
the bar spells the string as it writes it, after the spelling and before the
`KeyNotation` (`Shift-N` when spelled out). Anything but one letter with a
case (`1-9`, `c|C`, `?`, `⌃Z`, `ß`) is drawn as written. The undo and redo
hints, which are written as the bar's own items are (`KeySymbols.statusBarName(of:)`),
follow the same drawing, so a hint on a bare u reads `U` under `.menu` and
`u` under `.asTyped`. The option is an environment value with a view
modifier, `.statusBarKeySpelling(_:)`, by the modifier-first rule. Every
app's bar changes; the chrome snapshots were re-recorded (`S save`, `Q quit`).
Tests: `KeyNotationTests.statusBar`, `StatusBarKeySpellingTests`.

### B-KS-2. Spelled out, the keys have their English terminal names

*`KeyNotation.spelledOut`, `TUIKIT_KEY_SYMBOLS=0`*

The fallback for a font with no glyph for the symbols writes `Ctrl`, `Alt`,
`Shift` and `Cmd`, joined to the key by a hyphen (`Ctrl-Shift-Z`), and `Esc`,
`Return`, `Tab`, `Backspace`, `Del`, `Home`, `End`, `PgUp`, `PgDn`, in every
language; the arrows stay arrows. Option is `Alt` and the backspace key
`Backspace`, as a PC keyboard labels them, because a font without the macOS
symbols is most often on a host that is not a Mac. The space bar keeps its
translated name, as it does under the symbols.

**The fuller version:** the names in the app's language, as a German keyboard
labels them (`Strg`, `Umschalt`, `Entf`, `Pos1`, `Bild↑`), which the Example's
own German text already uses. Thirteen names in six languages, through the
framework's translation tables, and a translator's check of each — about two
hours, plus the check.

### B-KS-3. The names reach the framework's own chrome; an app's text follows them only if it asks

*`EnvironmentValues.keyNotation`, `KeyNotation.spelling(_:)`*

Under `.spelledOut` the status bar (every item's key, the app's own included)
and a menu's shortcut column write the names. Text an app wrote itself — a
`Text("Press ⌃S to save")`, the Example's help lines — keeps the symbols; an
app that builds such text from `KeyboardShortcut.displayString` can pass it
through `keyNotation.spelling(_:)`, reading `@Environment(\.keyNotation)`.

**The fuller version:** a `Text` interpolation for a shortcut,
`Text("Press \(shortcut) to save")`, drawn in the notation in force at render
time, as the live date interpolations are. About half a day; SwiftUI has no
such interpolation, so it would be TUI-specific.

### B-KS-4. The app's setting only ever spells keys out

*`Scene.keyNotation(_:)`*

`.keyNotation(.spelledOut)` turns the names on for everything the scene draws;
`.keyNotation(.symbols)` asks for nothing, and cannot hand the symbols back to a
user who set `TUIKIT_KEY_SYMBOLS=0`, the user being the one who knows what
their font can draw. This is `Scene.reduceMotion(_:)`'s rule. No host defaults
to the names, none having been measured unable to draw the symbols.

### B-KS-5. The Example names a key with its symbol, except where "Tab" is a verb

*The Example's and Stress's text, in all seven languages*

Every key the Example's text names as a key — its help lines (`[⇥] Move focus`,
`[⌃K] Kill to end of line`, `[↖] [↘] Jump to start/end`), and its prose
(`press ↩ to confirm`, `⌃R`, `⇧F10`, `⎋ closes all three`, `⌥↖/↘`) — is now
its symbol, in the language's sentence: `[Leertaste]`, `[Barra spaziatrice]`
and `[空格键]` for the space bar, as macOS names it in those languages. A
modifier held with the pointer is a symbol too (`⇧-click`, `hold ⌃ at the
drop`), as the text already wrote `⌘-click` and `⌥-click`. What stays a word:
"Tab" used as a verb or in "Tab stop" ("Tab to the list"), the space bar in
running prose ("Select a row (Space or click)"), and an on-screen key that is
not this keyboard's (SwiftUI's `.submitLabel` "labels an on-screen Return
key").

Apple's own guides spell keys out in running prose ("press Return") and draw
the symbols in menus; the owner's "wherever possible" is read as the symbols
throughout, the verb aside. **The fuller version** is the other reading: words
in running prose, symbols only in the key legends: a scripted change of the
prose strings, about an hour.

### C4. `KeyEquivalent.clear`

*`KeyEquivalent.clear`*

SwiftUI's `.clear` is AppKit's Clear key, U+F739: the keypad key in Num
Lock's position on a full-size Mac keyboard. A shortcut or `onKeyPress` on it
fires only if a terminal sends that key as a key of its own. The legacy
encodings TUI parses have no sequence for it, and the parser has nothing
to map to it. So `.clear` would name a key no event can carry, and a
shortcut on it would compile and never fire. Rule 2 says leave it out.

Not byte-captured: this machine has no extended keyboard. If a terminal turns
out to send the key, distinctly from Num Lock, the parser gains a case and
this entry goes. The kitty keyboard protocol (A4, shipped 2026-10-05) is the likeliest
route: it reports keypad keys by their own codes.
