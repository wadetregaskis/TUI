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

### A-W11a-1. `.textVariant(.sizeDependent)`: the narrower spellings of every live text

*`SizeDependentTextVariant`, `TextVariantPreference.sizeDependent`*

**Shipped:** `TextVariantPreference`, `FixedTextVariant`, `.fixed` and
`Text.textVariant(_:)`. Fixed is SwiftUI's default — always the widest
variant — and what every TUIkit text does, so `textVariant(.fixed)` returns
the text as it is. `.sizeDependent` is absent, so asking for it does not
compile.

It is not a no-op in SwiftUI. Measured on macOS 15 (one line, the width
falling in 6 pt steps), a size-dependent text chooses the widest of a ladder of
spellings that fits:

| Text | Ladder, widest first |
|---|---|
| `.offset(to:)` | `1 hour, 2 minutes` → `1 hr, 2 min` → `1h 2m` |
| `.reference(to:)`, relative | `2 minutes ago` → `2 min. ago` → `2m ago`; `in 1 hour` → `in 1 hr.` → `in 1h`; `yesterday` has none |
| `.reference(to:)`, absolute | `Friday, May 8` → `Fri, May 8` → `5/8`; `June 2025` → `Jun 2025` → `6/25`; with three fields `Friday, May 8 at 11 PM` → `Fri, May 8 at 11 PM` → `5/8, 11` |
| `.timer`, in units | `1 hour, 2 minutes` → `1 hr 2 min` → `1:02` |
| `.stopwatch` | `01:02:05.50` → `1:02:05` → `1:02` → `1h` |
| `Text(_:style: .relative)` | `1 hr, 2 min` → `1h 2m` |
| `Text(_:style: .offset)` | `+1 hour` → `+1 hr` → `+1h` |
| `Text(_:style: .date)` | `May 8, 2026` → `May 2026` → `2026` |
| `Text(_:style: .time)` | `11:13 PM` → `11 PM` |
| `Text(_:style: .timer)`, the timer on its face | none |

Without a line limit the widest always fits by wrapping, and nothing changes
(measured the same way).

**Options:**

1. **Build it.** Each live source offers its ladder (Foundation spells most
   rungs: `Duration.UnitsFormatStyle` and `Date.ComponentsFormatStyle` have
   abbreviated and narrow widths, `Date.FormatStyle` has abbreviated and
   numeric months, and the anchored relative style abbreviated units); a
   `.sizeDependent` text measures its rungs against the proposal and its line
   limit and draws the first that fits, the measure and the render choosing
   alike. About a day, most of it the per-rung measurements (German among
   them) and the tests. Only a text that asks pays: a measure per rung tried.
2. **Build the unit spellings only** (offset, relative, the timer's units):
   the abbreviated and narrow widths, half a day. The reference's absolute
   form and the date and time styles stay fixed — a quiet difference from
   SwiftUI for those, which the parity rules argue against.
3. **Leave it absent** (as now): ported code that asks for it does not
   compile.

**Recommendation:** 1, later — after the waves, since it touches every live
source and nothing else depends on it. 2 is the kind of partial honour the
parity rules warn about.

### A-W11a-2. `\(accessibilityName: color)`: a colour's spoken name

*`LocalizedStringKey.StringInterpolation.appendInterpolation(accessibilityName:)`*

SwiftUI interpolates "a localized description of a color for accessibility".
Measured on macOS 15, in light mode: `.red` reads `dark red`, `.blue` and
`Color(red: 0.2, green: 0.4, blue: 0.8)` `dark blue`, `Color(white: 0.5)`
`dark gray`, `.primary` `black`, the accent colour `dark blue`. The names
come from Apple's accessibility colour naming, which is private and has no
counterpart in the open-source Foundation.

**Options:**

1. **A namer of TUIkit's own:** a colour's resolved RGB in OKLCH, bucketed to
   a dozen hue names with `dark`/`light`/`vivid` qualifiers, in the
   framework's seven languages. It would not say what SwiftUI says for every
   colour (`.red` is `dark red` there, which no simple rule predicts); a
   palette colour names its resolved value. Half a day with the
   translations.
2. **Decline** (a `notImplemented` entry): code that uses it does not
   compile, and the app says what it means in words.
3. **Interpolate the colour's own description** (`String(describing:)`):
   compiles, and reads `Color(…)` to a screen reader — the quiet wrong answer
   the parity rules forbid.

**Recommendation:** 2 now; 1 if a screen-reader user of a TUIkit app asks for
it. Shipped: nothing, so it does not compile.

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

### B-W11a-3. On macOS, SwiftUI's own `.offset(to:)` and the rest are visible beside TUIkit's

*`FormatStyle.offset(to:…)`, `.reference(to:…)`, `.timer(countingDownIn:…)`,
`.timer(countingUpIn:…)`, `.stopwatch(startingAt:…)`*

TUIkit imports AppKit publicly (its `NSColor` bridges are public API), and
from the macOS 15 SDK AppKit imports SwiftUICore. Until an app opts into
Swift's member-import-visibility rule, an extension member of any module
imported however indirectly is visible, so every app that imports TUIkit sees
SwiftUICore's five statics on Foundation's `FormatStyle` beside TUIkit's. The
types do not leak; these extension members do. Measured with a two-module
probe:

- both on `FormatStyle`: `Text(.currentDate, format: .offset(to: d))` is
  ambiguous and does not compile;
- TUIkit's only on `DiscreteFormatStyle`: a context that takes any
  `FormatStyle` picks SwiftUI's, which then fails to LINK (SwiftUICore admits
  no direct clients);
- both (shipped): a `DiscreteFormatStyle` context picks TUIkit's (the
  refining protocol's extension is the more specialised), and a plain
  `FormatStyle` context is ambiguous — a compile error, not a link error.

So TUIkit declares each static twice, and takes these styles as
`DiscreteFormatStyle` everywhere: `Text(_:format:)` over a time data source
already does, and `Text(_:format:)` and `appendInterpolation(_:format:)` for
an `AttributedString` output gained a discrete overload beside the
`FormatStyle` one. What stays ambiguous on macOS is a `FormatStyle` context
outside TUIkit, such as `Date.now.formatted(.offset(to: d))`; spelling the type
(`SystemFormatStyle.DateOffset(to: d)`) settles it. Linux has no SwiftUICore.

**Fuller version:** move the AppKit bridges (`Color(nsColor:)`,
`NSColor(_:)`, the `CGColor` pair) into a module of their own, so TUIkit can
import AppKit `internal`ly and nothing of SwiftUICore reaches an app. That
fixes this for every Foundation extension SwiftUI declares, not only these
five, at the price of one more product to import for the bridges (half a day
with the documentation). Your call whether that is worth it now; nothing else
in this wave needs it.

### B-W11a-4. A live text read for its string is read once, when it is built

*`Text(_:style:)`, `Text(timerInterval:…)`, the live interpolations,
`Text(_:format:)` over a `TimeDataSource`*

A live `Text` draws its words at each frame. But some of TUIkit's API takes a
`Text` only for its string — `navigationTitle(Text)`, `help(Text)`,
`dismissalConfirmationDialog`'s title — and a `LocalizedStringKey` handed to a
control other than `Text` (a button's title) is resolved to a string where the
control is built. Those read a live text or a live interpolation once, as it
read when built; it moves only when the view around it is rebuilt. SwiftUI
keeps them live, since its titles are `Text` all the way down.

To give those consumers a reading at all, a live text formats once when it is
built, as well as at each frame it is drawn. Only live texts pay it (about
6 µs for a unit spelling, 30 µs for `.time`/`.date`, which use a
`DateFormatter`).

**Fuller version:** the string-taking consumers keep the `Text` and draw it,
which each of them could (a title is drawn by a `Text` in the end); a title
that changes would then also have to re-measure the bar it sits in. About two
hours a consumer, and none has asked. **A/B owed:** the build-time reading
could be deferred to the first consumer that asks, saving it for every live
text drawn only as a view — worth measuring on a list of a few hundred
`Text(date, style: .relative)` rows before deciding.

## C. Declined without asking

None. The two symbols nothing shipped for are the owner's (A-W11a-1,
A-W11a-2) and stay in the baseline as gaps.

## D. Deferred

- **The attributes of an `AttributedString` output** (`SystemFormatStyle`,
  `Text(_:format:)` with an attributed style, `appendInterpolation(_:format:)`):
  the characters are drawn and the attributes wait on `Text(AttributedString)`
  (P8). SwiftUI's system styles carry only semantic attributes (which field a
  run is), so nothing visible is lost for them today.
- **SwiftUI's reduced-luminance redaction** of live text has nothing to act on
  in a terminal, which has no always-on display; `TimelineView` already
  reports the `.live` cadence for the same reason.
- **An Example page for live time text:** the Example's pages are pinned by
  golden snapshots and a PTY walk, and a live text makes a page's bytes depend
  on the clock. It wants a frozen-clock hook in the walk first.
- **macOS 26:** every measurement here is macOS 15's. A pass over the same
  probes on macOS 26 is owed before the owner's review closes the wave.
