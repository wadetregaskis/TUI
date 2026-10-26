# Completing the SwiftUI API: decisions from lane TEXTFMT

*Lane TEXTFMT carried out four of the owner's rulings of 2026-10-23 about
text: DEPR-CATCHALL, B51-LIVE, B-D4X-7-17 and D4X-LOCALITY (`Documentation/Open
owner decisions.md`). This file holds the judgement calls the work reached that
the rulings did not already settle, in the format of
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>):*

- **A-TEXTFMT-n — needs your decision.** Nothing has shipped for these.
- **B-TEXTFMT-n — shipped the safe option.** Says what the fuller version would
  be, and its price.
- **C-TEXTFMT-n — declined.** With the reason.

## DEPR-CATCHALL: SwiftUI's typed interpolations, and the catch-all deprecated

**Shipped.** `LocalizedStringKey.StringInterpolation` has SwiftUI's typed
overloads, read from the macOS 26.2 SDK's `SwiftUICore.swiftinterface`
(Xcode 26.3), and the catch-all `appendInterpolation<T>(_:)` is deprecated with
SwiftUI's message and `@_disfavoredOverload`, as SwiftUI's is. What each value
takes now (`LocalizedStringKey+Interpolation.swift`, `LocalizedStringKey+Live.swift`):

| Interpolated | Overload | New here |
|---|---|---|
| `String`, `Substring` | `appendInterpolation(_:)` | yes |
| an integer, a `Float`, a `Double`, a `CGFloat` | `appendInterpolation<T: _FormatSpecifiable>(_:)`, with SwiftUI's `_FormatSpecifiable` and its 13 conformances | yes |
| a number with `specifier:` | `appendInterpolation<T: _FormatSpecifiable>(_:specifier:)` | was `T: CVarArg` |
| `Text`, `Image` | as before | no |
| a value with `format:` (String, `AttributedString` output, discrete) | as before | no |
| `AttributedString`, `AttributedSubstring` | `appendInterpolation(_:)`; its runs reach the `Text` as an interpolated `Text`'s do | yes |
| a `ReferenceConvertible` value (`Date`, `URL`, `UUID`) or an `NSObject`, with or without `formatter:` | `appendInterpolation(_:formatter:)` | yes |
| `\(date, style:)`, `\(timerInterval:…)` | as before | no |
| a `TimeDataSource` with `format:` | `appendInterpolation(_:format:)`, live as `Text(_:format:)` over the source is | yes |
| anything else: `Bool`, an `Optional`, an enum, an array, a value typed `Any` | the catch-all, which now warns | — |

The key each one builds is unchanged, in both spellings: `%@` in TUI's,
and in SwiftUI's the number's conversion (`%lld`, `%lf`…) or `%@`
(`Tools/SwiftUIProbes/Localization keys/keys.out`). A number typed `Any` now
spells `%@` in SwiftUI's key, where TUI used to spell its dynamic type's
conversion; SwiftUI's catch-all writes `%@`, and so does TUI's.

TUI's own uses that reached the catch-all were seven, all in tests (a
`Bool` in three keys, a sorted `Set` in two, and the catch-all's own test,
which now reaches it through a protocol requirement, so no warning). The
library and the Example had none.

**Compile time.** Measured with the compiler's own counters
(`-stats-output-dir`, `Sema.NumConstraintScopes`, deterministic) over a clean
debug build of every target and test, before and after: +0.13% in all
(41,724,430 to 41,776,786 scopes); the Example, which interpolates most,
+3.07%; TUIFoundation −0.48%. Wall-clock type-check times were taken
on a busy machine and are not quoted.

One body crossed the type-check guard (`-solver-scope-threshold=2000`), which
main passes: the find bar's (`TextEditor+Find.swift`), whose
`Text(matches.isEmpty ? "0/0" : "\(min(current, matches.count - 1) + 1)/\(matches.count)")`
now has more overloads to try at each interpolation. Typing the ternary as a
`String` inside the body did not bring it back under; a function of its own
did, and the counter is drawn verbatim, being a position rather than words.
So an app's body that interpolates arithmetic into a key inside a ternary pays
more than it did, as SwiftUI's does with the same overload set.

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

## B51-LIVE: live titles where SwiftUI's are live

**The ruling:** "Live everywhere it makes sense; measure; case by case."

**Measured first** (macOS 15.8, a `WindowGroup` app with a timer interpolated
into each title, read at three times through AppKit and Vision;
`Tools/SwiftUIProbes/Live titles (TEXTFMT)/`):

| Consumer | SwiftUI | TUI before | TUI now |
|---|---|---|---|
| `Button`'s title key | live | read once | live |
| `ColorPicker`'s title key | not measured (its label is a `Text`, as a button's is) | read once | live |
| `TextField`'s title key, drawn as its placeholder | live | drawn at the wall clock's time, no wake | live |
| `SecureField`'s title key | live | read once (a string) | live |
| a value field's (`TextField(_:value:format:)`) title key | not measured (as `TextField`'s) | read once (a string) | live |
| a field's `prompt:` `Text` | not measured (as the title) | drawn at the wall clock's time, no wake | live |
| `TableColumn`'s header, key or `Text` | live | read once | live |
| `Toggle`, `Label`, `Section`, `Picker`… (B87's `Text(titleKey)`) | live (a `Text`) | live, unverified | live, now tested |
| `navigationTitle(Text)` and a key | read once (the window's title stayed `0:00`) | read once | read once |
| an alert's title and message | read once (the panel's fields stayed `0:00`) | read once | read once |
| `confirmationDialog`, `dismissalConfirmationDialog`'s title | not measured (presented as the alert is) | read once | read once |
| `help(_:)` | not measured (a tooltip shows only while the pointer rests) | read once | read once |
| a `Tab`'s title | not measured (the probe could not read the tab bar) | read once | read once |

**How.** A title key with a live value resolves to its `Text`
(`LocalizedStringKey.resolvedTitle`), which `Button` and `ColorPicker` already
draw for a styled key. The text and secure field cores read a live placeholder
at the frame's date before drawing or measuring it, and declare its next change
as a live `Text` does; `SecureField` and the value field take the key's `Text`
as their title, as `TextField` does (so their Markdown is parsed now too, as
SwiftUI's is). A column keeps its header's words as `LiveWords` (one reference),
and the table reads them into the title when it prepares a pass, each under a
wake of its own, and keeps no `.fit` width for such a column, because the
rows' signature cannot see a header change.

**What it costs where nothing is live:** a check of a key's live arguments when
a button or colour picker is built; a check of the placeholder's runs per field
render; a look at each column's optional per table pass; a word more in every
`TableColumn` and column spec. No title that is not live is drawn any
differently. **A/B owed:** `table`, `table-api`, `tables-scroll`,
`framedcolumns`, `controls`, `kitchensink`.

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

## B-D4X-7-17: a cell's modifier keeps to its cell

**The ruling:** "Tentatively concur; configurability by a modifier may be
wise." Option 1: fix the leak, and keep a table-wide scope crossing columns.

**Shipped.** A cell's `.textSelection(.enabled)` makes that cell's text
selectable, kept to the cell; the row's other text is the row's, so a click on
it selects the row and a drag on it selects nothing, as on macOS. An enabled
scope around the table still selects a row's text across its columns. The
option priced column geometry filed with the rows; it was not needed. The
scoped cell's own region, which the table carries up, already kept a
selection begun on it to the cell; the leak was a flag on the rows' press role
(`cellsSelectText`) that treated the row's unscoped text as enabled. Removing
it fixes the leak in `PressRole.rows`, and a `List` passed `false` for it
anyway. Tests: `TextSelectionModifierTests` (`cellTextKeepsToTheCell`, now a
click on the other column selecting the row; `wholeTableCrossesColumns`).
Nothing per frame changes.

### C-TEXTFMT-2. Declined: a modifier to choose cell or row for a table-wide scope

*A `TextSelectionScope.cell`, or a table modifier, making `.textSelection(.enabled)`
around a `Table` keep each selection to one cell, as macOS does*

Not built, because where the modifier goes already chooses: on the cells'
`Text` (`TableColumn("Name") { Text($0.name).textSelection(.enabled) }`) a
selection keeps to the cell, as macOS's does, and around the table it crosses
the row's columns, which is TUI's screen selection everywhere else (T6). A
third spelling for the first would add API without adding a behaviour, and no
app has asked for a table-wide scope that keeps to cells.

**Price, if wanted:** about two hours. A `.cell` case on `TextSelectionScope`
(TUI's existing modifier for what a selection keeps to), read by the table,
which files its columns' x-ranges with its rows so that a press under a
table-wide scope keeps to the column under it.

## D4X-LOCALITY: copies through screen's and tmux's passthroughs

**The ruling:** the screen and tmux passthroughs "seem fine"; asked about
asking keepers for their clients, which the follow-up answered: client
queries only for a keeper someone uses and asks for. So the passthroughs are
built and the client queries are not.

**Measured first** (`Tools/TerminalProbes/keeper_passthrough_probe.py`, new:
each keeper run on a pty the script plays as the terminal, so what the keeper
passes on is read without a GUI terminal; the survey's "OSC 52 through screen
and tmux"). GNU screen 4.00.03 drops a bare OSC 52 and passes one on inside a
DCS string, at most 256 bytes a string (260 is dropped whole), and a 64 KiB
write cut into such strings arrives whole. tmux 3.7c passes a wrapped write on
under `allow-passthrough on`, 64 KiB whole, and drops it under `off`, its
default; with `set-clipboard on` and `allow-passthrough on` a bare write
arrives once.

**Shipped.** The ladder (`TerminalClient.clipboardDelivery`) now says how to
wrap a write as well as how far to trust it (`ClipboardPassthrough`):

- **Inside screen** (`STY`, not in a tmux pane): "Sent", the write
  BEL-terminated and cut into 256-byte DCS strings. It was "Not copied". The
  terminal's name screen inherited says nothing of where it is drawn now, so
  never "Copied".
- **In a tmux pane:** `set-clipboard on` first, the bare write as before, so a
  copy is never sent twice; otherwise, where the pane's `allow-passthrough` is
  `on` or `all` (`show-options -pvA`, asked per copy, only then), "Sent", the
  write in tmux's passthrough. Where every client that sees the write runs in
  a screen window it is still "Not copied", as under `on`: tmux hands screen
  the bare write, which screen drops.
- **`TUIKIT_OSC52=1` inside screen** wraps the write too; it used to send it
  bare, which screen drops.
- **Through either passthrough a copy is its text alone.** Its other types
  (OSC 5522) are a write of their own that the probe did not measure crossing
  a keeper.

Nothing per frame: one more bounded tmux subprocess per copy, where
`set-clipboard` is not `on`.

### C-TEXTFMT-3. Declined for now: asking keepers for their clients

*screen's and zellij's session sockets, an outer tmux's `list-clients`*

The follow-up's answer, and the ruling's: only for a keeper someone uses and
asks for. It is the one way to know the user is at the desk under a keeper,
which would let `pbcopy` and the desk's clipboard serve such a session, but
each keeper has its own interface (dtach and abduco have none), the answer is
a snapshot a reattach makes stale, and it does nothing over ssh. About half a
day per keeper.
