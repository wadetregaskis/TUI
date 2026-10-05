# Completing the SwiftUI API: decisions from lane KS

*Lane KS carried out the owner's request of 2026-10-05: "Keyboard shortcuts
should use the appropriate Unicode characters wherever possible, e.g. "⌘",
"⎋", "⇧", "⌥", "⌃" (control), etc. And in the correct (macOS) order." It is an
owner request, not a decisions-document item. This file holds the judgement
calls the work reached that the request did not already settle, in the format
of [`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md):*

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
`Documentation/Terminal-compatibility.md`, "Key symbols", for the glyphs'
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

**The fuller version:** draw a single-character item's key through the
formatter (`Q`, `⇧N`), with the bound key unchanged. Half a day once the bar
draws an item's key from the key rather than from the string — which is the
A28 chrome lane's restructuring of the status bar into views, and is better
done there than beside it. It changes every app's status bar.
