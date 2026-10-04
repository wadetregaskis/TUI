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

*`Text(_:style: .relative)` and `.offset`; `SystemFormatStyle.DateOffset`*

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

### B-W11a-2. `SystemFormatStyle`: where the rules go beyond the measurements

*`SystemFormatStyle.Timer`, `.Stopwatch`, `.DateOffset`, `.DateReference`*

The four styles reproduce every reading measured (about 200, pinned in
`SystemFormatStyleClockTests` and `SystemFormatStyleDateTests`). Between the
measurements, these were chosen:

- **`DateReference`'s absolute form is drawn in the calendar's time zone.**
  SwiftUI's keeps a zone of its own beside the calendar, set from the current
  zone and not reachable through its API; `calendar(_:)` with a calendar in
  another zone therefore moves TUIkit's absolute form and not SwiftUI's. With
  the default calendar the two agree.
- **`now`.** Foundation's anchored relative style says "this minute" (or
  "this hour") where SwiftUI's reference says "now"; TUIkit says "now" when
  the finest allowed unit is a minute or an hour and the offset rounds to
  nothing in it. With seconds allowed Foundation says "now" itself; with days
  the finest, "today" is left alone (unmeasured).
- **`DateOffset` on a clock face** only when exactly minutes and seconds are
  allowed. SwiftUI's documentation says hours, minutes and seconds use it too;
  measured, with two fields, they did not, and three fields were not tried.
- **Boundaries.** `discreteInput(after:)` and `(before:)` return the instant the
  reading changes, at a boundary or one representable `Date` past it. SwiftUI's
  `before` sometimes returns the boundary itself, where the reading has not yet
  changed, which its protocol allows; TUIkit's never does. `DateReference`
  turns between its forms half a second before a period begins (the point of
  reference is rounded to the second), where SwiftUI's turn at a new year was
  measured at the year's first instant.

**Fuller version:** a macOS 26 measurement pass over the same probes, and the
three-field clock face. An hour each.

## C. Declined without asking

## D. Deferred
