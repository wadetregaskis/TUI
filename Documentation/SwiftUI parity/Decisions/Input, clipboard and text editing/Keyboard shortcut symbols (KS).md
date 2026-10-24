# Completing the SwiftUI API: decisions from lane KS

*Lane KS carried out the owner's request of 2026-10-05: "Keyboard shortcuts
should use the appropriate Unicode characters wherever possible, e.g. "⌘",
"⎋", "⇧", "⌥", "⌃" (control), etc. And in the correct (macOS) order." It is an
owner request, not a decisions-document item. This file holds the judgement
calls the work reached that the request did not already settle, in the format
of [`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>):*

- **A-KS-n — needs your decision.** Nothing has shipped for these.
- **B-KS-n — shipped the safe option.** Says what the fuller version would be,
  and its price.
- **C-KS-n — declined.** With the reason.

What shipped, in one paragraph: one formatter (`KeySymbols`) names every key
TUIkit shows, as a macOS menu names a key equivalent — the modifiers in the
order ⌃ ⌥ ⇧ ⌘, then the key, a letter in upper case, the non-printing keys as
⎋ ↩ ⇥ ⌫ ⌦ ↖ ↘ ⇞ ⇟ and the arrows, the function keys and the space bar as
words. The spelling was read from AppKit's `NSKeyboardShortcut` on macOS 15
for every key and modifier set, in all seven of TUIkit's languages. See
`Documentation/Terminals/Terminal compatibility survey.md`, "Key symbols", for the glyphs'
widths and what is still to measure.

## B. Shipped the safe option

### B-KS-1. A status bar item's own string is drawn as the app wrote it

*`StatusBarItem(shortcut:label:)`*

The formatter names a key wherever TUIkit names one: a menu row's shortcut
column, `KeyboardShortcut.displayString`, the undo and redo hints, every
``Shortcut`` constant (so `Shortcut.enter` is now `↩` and `Shortcut.ctrl("q")`
is `⌃Q`). An item's `shortcut` string that an app typed itself — `"q"`, `"N"`,
`"c|C"`, `"1-9"` — is drawn as typed. So TUIkit's own quit item still reads
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
