# Formatting and live text

*How numbers and dates are formatted into text, the typed interpolations,
what is read once and what stays live, and the formatter forms refused. Ids:
B49, B51, B51-LIVE, B-TEXTFMT-1 to 3, C-TEXTFMT-1, DEPR-CATCHALL, NUMFMT,
FORMATTER (O11).*

## In short

`LocalizedStringKey.StringInterpolation` has SwiftUI's typed interpolations,
and the old catch-all warns with SwiftUI's message. A number without a
specifier is drawn in the locale. A live text (a timer, a relative date) stays
live where SwiftUI's does — a button's title, a field's placeholder, a table
header — and is read once in a navigation title and an alert, as measured. The
`Formatter` forms stay refused: an inferior API with a better replacement
(`format:`), and on Linux a custom `Formatter` does not parse.

## How it unfolded

1. **B49 and B51** shipped `SystemFormatStyle` and read-once live text.
2. **2026-10-23, the owner:** live everywhere it makes sense, measured first
   (B51-LIVE); typed interpolations, then mark the catch-all deprecated
   (DEPR-CATCHALL). Lane TEXTFMT built both on 2026-10-24; NUMFMT followed.
3. **2026-10-26, FORMATTER:** skip both forms, and document why.

## The record

### B49. `SystemFormatStyle`: where the rules go beyond the measurements

*`SystemFormatStyle.Timer`, `.Stopwatch`, `.DateOffset`, `.DateReference`*

The four styles reproduce every reading measured (about 200, pinned in
`SystemFormatStyleClockTests` and `SystemFormatStyleDateTests`). Between the
measurements, these were chosen:

- **`DateReference`'s absolute form is drawn in the calendar's time zone.**
  SwiftUI's keeps a zone of its own beside the calendar, set from the current
  zone and not reachable through its API; `calendar(_:)` with a calendar in
  another zone therefore moves TUI's absolute form and not SwiftUI's. With
  the default calendar the two agree.
- **`now`.** Foundation's anchored relative style says "this minute" (or
  "this hour") where SwiftUI's reference says "now"; TUI says "now" when
  the finest allowed unit is a minute or an hour and the offset rounds to
  nothing in it. With seconds allowed Foundation says "now" itself; with days
  the finest, "today" is left alone (unmeasured).
- **`DateOffset` on a clock face** only when exactly minutes and seconds are
  allowed. SwiftUI's documentation says hours, minutes and seconds use it too;
  measured, with two fields, they did not, and three fields were not tried.
- **Boundaries.** `discreteInput(after:)` and `(before:)` return the instant the
  reading changes, at a boundary or one representable `Date` past it. SwiftUI's
  `before` sometimes returns the boundary itself, where the reading has not yet
  changed, which its protocol allows; TUI's never does. `DateReference`
  turns between its forms half a second before a period begins (the point of
  reference is rounded to the second), where SwiftUI's turn at a new year was
  measured at the year's first instant.

**Fuller version:** a macOS 26 measurement pass over the same probes, and the
three-field clock face. An hour each.

### B51. A live text read for its string is read once, when it is built

*`Text(_:style:)`, `Text(timerInterval:…)`, the live interpolations,
`Text(_:format:)` over a `TimeDataSource`*

A live `Text` draws its words at each frame. But some of TUI's API takes a
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

**2026-10-24 (lane TEXTFMT, owner ruling B51-LIVE: "live everywhere it makes
sense; measure; case by case").** Measured on macOS 15.8: SwiftUI keeps a live
value live in a button's title, a field's placeholder and a table column's
header, and reads it once in a window's navigation title and an alert's title
and message. TUI now matches all five: a button's and a colour picker's
title key, a text, secure or value field's title and prompt, and a column's
header (key or `Text`) are live; `navigationTitle` and the alert family keep
reading once. Help and a tab's title, unmeasured, still read once. Details and
costs:
[B51-LIVE in TEXTFMT](<Formatting and live text.md>).

### B-TEXTFMT-1. A number interpolated without a specifier is drawn in the locale, without SwiftUI's padding

*`appendInterpolation<T: _FormatSpecifiable>(_:)`*

**Done (owner ruling 2026-10-24, lane NUMFMT).** The ruling: "I would like
numbers to be localised by default, although I don't think we want to mimic
things like turning "3.5" into "3.500000" because that's ugly and IMO a bug in
SwiftUI."

SwiftUI forwards a bare number to `appendInterpolation(_:specifier:)` with the
number's own conversion, and formats it in the locale. Measured (macOS 15.8,
SwiftUI rendered through `ImageRenderer` and read back by Vision, `en_US`;
`Tools/SwiftUIProbes/Interpolated values drawn (TEXTFMT)/`):
`Text("a \(1234567) b")` draws `a 1,234,567 b`, `\(3.5)` draws `3.500000`,
`\(Float(3.25))` `3.250000`, and under `de_DE` `1.234.567` and `3,500000`.
Until this ruling TUI drew the number's description, `1234567` and `3.5`.

**What ships.** The key is unchanged: `%@` in TUI's spelling and the
number's conversion (`%lld`, `%lf`, …) in SwiftUI's, so a translation keyed
`"Count: %lld"` still matches. The number is kept with the key
(`InterpolatedNumber`, `LocalizedStringKey.numberArguments`) and written as
`.number` writes it in the locale in force:

| | `en_US` | `de_DE` | `fr_FR` |
|---|---|---|---|
| `\(1234567)` | `1,234,567` | `1.234.567` | `1 234 567` (U+202F between) |
| `\(3.5)` | `3.5` | `3,5` | `3,5` |
| `\(0.1 + 0.2)` | `0.3` | `0,3` | `0,3` |
| `\(Double.pi)` | `3.141593` | `3,141593` | `3,141593` |

**The floating-point rule: `.number`'s default, which is at most six fraction
digits with no trailing zeros.** Six is `%lf`'s precision, so what is drawn is
exactly SwiftUI's number with the padding the owner ruled a bug taken off:
`3.500000` is `3.5`, `3.141593` stays `3.141593`, and a tenth that binary
cannot hold reads `0.3`. The other candidate, the shortest form that
round-trips (Swift's own `description`), writes `0.1 + 0.2` as
`0.30000000000000004`, seventeen digits SwiftUI never shows, and a `Float`'s
`0.1`, widened, as `0.10000000149011612`. What `.number` writes differently
from `%lf` besides the padding: `∞` and `NaN`, where `%lf` writes `inf` and
`nan`.
Deliberate deviations T11 records the padding.

**Which locale.** `\.locale`: the key is built where no environment is known,
so it writes its numbers in the app's locale (`LocalizationService.currentLocale`,
which is what `\.locale` is at the root, every frame); a `Text` under a subtree
whose `\.locale` is another — another language, or the same language in
another region (`en_IN` groups `12,34,567`) — writes them again in that one
when it draws, as it reads its words again in that language
(`Text.relocalized(in:)`). A control's title read eagerly (`.localized`) is in
the app's locale, as its words are in the app's language.

**Cost.** A key is built every time a body runs, so a number was formatted
every frame whether it had changed or not. Foundation's `IntegerFormatStyle`
and `FloatingPointFormatStyle` take about 0.3 µs a number on this Mac
(measured 2026-10-24, 200,000 calls; `String(format:locale:)` with the printf
conversion, the price quoted above, takes 3.6 µs and 13 µs), and the shared
service keeps what it has written in the app's locale
(`LocalizationService.formatted(_:)`, a `GenerationalMemo` of 1,024 numbers a
generation, emptied when the locale moves): an unchanged number costs a lock
and a lookup. Counted, not timed: a hundred builds of one number write it
once (`InterpolatedNumberTests`). A `Text` under a subtree with another locale
writes its numbers again each time it draws, unkept; that subtree is rare, and
its words are already read again there.

**The gap, closed (lane SPECIFIER, 2026-10-24).** `\(value, specifier:)` first
formatted at once in the process's locale (`.current`), so under an app-chosen
language its numbers could differ from a bare one's and a subtree's `\.locale`
did not reach it. It now takes the bare number's path: the value is kept with
the key as `InterpolatedNumber.specified(specifier, argument)`, the argument at
the width C's variadic promotion gives it (`Int32` for `%d`, `Int64` for
`%lld`, `UInt32`/`UInt64`, and a `Double` for `%f`, which a `Float` and a
`CGFloat` are widened to; a `CVarArg` itself is not `Equatable`, which is why
this was left). It is written with `String(format:locale:)` in the app's
locale where the key is built, kept per number in
`LocalizationService.formatted(_:)` like a bare number, and written again where
a `Text`'s `\.locale` differs, through the same `numberArguments` and
`Text.relocalized(in:)`. The key is as SwiftUI's: `%@` in TUI's spelling and
the specifier as written (`"Price %.2f"`) in SwiftUI's, so a translation keyed
with it matches.

| | `en_US` | `de_DE` | `fr_FR` |
|---|---|---|---|
| `\(234.5, specifier: "%.2f")` | `234.50` | `234,50` | `234,50` |
| `\(7, specifier: "%03d")` | `007` | `007` | `007` |

Unlike a bare number, a specifier writes **exactly** the conversion: `%.2f`
pads, which is the author's ask and not SwiftUI's `%lf` default the owner ruled
against. `String(format:locale:)` on Apple's platforms also groups a
conversion's digits in the locale (`1,234.50` in `en`, `1.234,50` in `de`, with
`%.2f` and `%lld` alike); that is Foundation's (measured on macOS 15.8 through the tests; whether SwiftUI
draws the same, and whether swift-corelibs-foundation groups, are unmeasured),
so the tests compare the digits of a large value rather than assert it. A value whose `_arg` is none of the
standard library's (only an app's own `_FormatSpecifiable` conformance makes
one) is still written at once in `.current`.

**Cost.** Better than before: every body that built a key with a specifier paid
`String(format:locale:)` (3.6 µs for an integer, 13 µs for a `Double`, measured
2026-10-24) each time; it now pays a type switch, a hash of the specifier and a
lock, and the formatting only when the number or the locale is new. Counted in
`InterpolatedNumberTests` (100 builds of one specified number write it once).

### B-TEXTFMT-2. The `formatter:` interpolations ship, although O11 deferred the `Formatter` forms

*`appendInterpolation(_:formatter:)` for `ReferenceConvertible` and `NSObject`*

O11 (2026-10-12) deferred SwiftUI's `Formatter` forms because the parse
direction is internal in Linux Foundation. An interpolation only formats
(`Formatter.string(for:)`, public everywhere), and without these overloads a
`Date`, `URL` or `UUID` interpolated with no formatter would warn in TUI
where it compiles silently in SwiftUI, which DEPR-CATCHALL's "same lookup and
warning as SwiftUI" rules out. So the interpolations ship; `Text(_:formatter:)`
and the `TextField` forms stay deferred under O11. A value with no formatter
is drawn as its description (what SwiftUI draws for it is not measured).

Swift 6.2.4 to 6.4.0 crash in SILGen when the generic value is handed straight
to `Formatter.string(for:)`'s Objective-C `id` parameter; the overload goes
through a local `Any`. Reported on the owner's desktop as
`swift-6.4-SILGen-bridging-generic-ObjectiveCBridgeable-to-id-asserts.md`.

### C-TEXTFMT-1. Declined: the interpolations of a date range, a date interval, a `LocalizedStringResource` and a colour's name

*`appendInterpolation(_:)` for `ClosedRange<Date>`, `DateInterval` and
`LocalizedStringResource`; `appendInterpolation(accessibilityName:)`*

Each follows a `Text` initializer or a type TUI does not have, and is
interpolated through the deprecated catch-all, with its warning, until that
lands:

- **The date range and interval.** `Text(_:)` of a `ClosedRange<Date>` or a
  `DateInterval` does not exist in TUI yet. SwiftUI's format is its own,
  not Foundation's `Date.IntervalFormatStyle` default: measured (the same
  probe), an hour reads
  `11:13 PM-12:13 AM` and three days `May 8 - May 11`, with no year even 400
  days apart, where Foundation writes `5/8/2026, 11:13 PM – 5/9/2026, 12:13 AM`.
  Matching it is the initializers' work, and the interpolations follow them.
- **`LocalizedStringResource`.** TUI takes a `LocalizedStringResource`
  nowhere yet: no `Text` or control initializer does.
- **`accessibilityName:`.** Declined on 2026-10-05 (A33; the parity map).

### B-TEXTFMT-3. Help and a tab's title are read once, where SwiftUI's is not measured

*`help(_:)`, `Tab`'s title*

Both stay as they were. Help is a string the tooltip and the focused
control's hint draw in the chrome's style; a tab's title is laid out from its
string as a chip in the strip. SwiftUI's behaviour is unknown for both: its
tooltip shows only while the pointer rests, and the probe found no tab bar to
read.

**The fuller version:** carry the `Text` (or `LiveWords`) into the tooltip and
the strip, read it per frame and declare its change; about two hours each, and
worth it only once SwiftUI's own is measured live.
