# Completing the SwiftUI API: Wave 11a decisions (live time text)

*Wave 11a's entries, in the format of
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md),
for folding into it. The wave covers SwiftUI's live time text: `Text(_:style:)`,
`Text(timerInterval:…)`, their `LocalizedStringKey` interpolations,
`SystemFormatStyle`, `TimeDataSource` and the text-variant preference.*

Every string below was measured on SwiftUI, macOS 15, by rendering the text
with `ImageRenderer` and reading the picture back with Vision; the probes and
their output are in the session notes (`w11a/probe/`). macOS 26 was not
available, so nothing here is checked against it.

---

## A. Needs your decision

## B. Shipped the safe option

### B-W11a-1. On Linux, a span of a month or more is spelt in English

*`Text(_:style: .relative)` and `.offset`*

SwiftUI spells a span in units: `2 min, 5 sec`, `1 yr, 3 mths`, `−2 minutes`.
Under a month TUIkit spells them with Foundation's `Duration.UnitsFormatStyle`,
which is localised, pluralised and list-joined on every platform (`1 Std.,
2 Min.` in German, as SwiftUI draws it). `Duration` has no years or months,
though. On Apple platforms those go through `Date.ComponentsFormatStyle`,
which matches SwiftUI's strings. The open-source Foundation declares that type
with no initialiser (only its `Field` exists), so on Linux years and months are
spelt from a small English table, CLDR's English abbreviations included
(`yr`/`yrs`, `mth`/`mths`).

**Fuller version:** the unit names for years and months (wide and abbreviated,
one and other) in the framework's own translation tables, joined with each
language's list pattern. About sixteen strings for each of the seven
languages, plus plural rules for French (where 0 is singular) and none for
Japanese and Chinese. Half a day; worth it only if an app on Linux shows
spans that long in a language other than English.

## C. Declined without asking

## D. Deferred
