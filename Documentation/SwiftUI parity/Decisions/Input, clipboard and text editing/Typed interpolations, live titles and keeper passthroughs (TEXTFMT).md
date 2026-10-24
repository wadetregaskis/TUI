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

The key each one builds is unchanged, in both spellings: `%@` in TUIkit's,
and in SwiftUI's the number's conversion (`%lld`, `%lf`…) or `%@`
(`Tools/SwiftUIProbes/Localization keys/keys.out`). A number typed `Any` now
spells `%@` in SwiftUI's key, where TUIkit used to spell its dynamic type's
conversion; SwiftUI's catch-all writes `%@`, and so does TUIkit's.

TUIkit's own uses that reached the catch-all were seven, all in tests (a
`Bool` in three keys, a sorted `Set` in two, and the catch-all's own test,
which now reaches it through a protocol requirement, so no warning). The
library and the Example had none.

**Compile time.** Measured with the compiler's own counters
(`-stats-output-dir`, `Sema.NumConstraintScopes`, deterministic) over a clean
debug build of every target and test, before and after: +0.13% in all
(41,724,430 to 41,776,786 scopes); the Example, which interpolates most,
+3.07%; TUIkitFoundation −0.48%. Wall-clock type-check times were taken
on a busy machine and are not quoted.

One body crossed the type-check guard (`-solver-scope-threshold=2000`), which
main passes: the find bar's (`TextEditor+Find.swift`), whose
`Text(matches.isEmpty ? "0/0" : "\(min(current, matches.count - 1) + 1)/\(matches.count)")`
now has more overloads to try at each interpolation. Typing the ternary as a
`String` inside the body did not bring it back under; a function of its own
did, and the counter is drawn verbatim, being a position rather than words.
So an app's body that interpolates arithmetic into a key inside a ternary pays
more than it did, as SwiftUI's does with the same overload set.

### B-TEXTFMT-1. A number interpolated without a specifier is drawn as its description, not as SwiftUI formats it

*`appendInterpolation<T: _FormatSpecifiable>(_:)`*

SwiftUI forwards a bare number to `appendInterpolation(_:specifier:)` with the
number's own conversion, and formats it in the locale. Measured (macOS 15.8,
SwiftUI rendered through `ImageRenderer` and read back by Vision, `en_US`;
`Tools/SwiftUIProbes/Interpolated values drawn (TEXTFMT)/`):
`Text("a \(1234567) b")` draws `a 1,234,567 b`, `\(3.5)` draws `3.500000`,
`\(Float(3.25))` `3.250000`, and under `de_DE` `1.234.567` and `3,500000`.
TUIkit draws the number's description, `1234567` and `3.5`, as it did when
the catch-all took numbers. Nothing changes for an app.

Why not SwiftUI's: it is a visible change to every interpolated number, in
the Example and in apps, and a cost. `String(format:locale:)` takes about
4 µs for an integer and 16 µs for a `Double` on this Mac (measured, 200,000
calls), against nanoseconds for the description, and a key is built every
time a body runs.

**The fuller version:** format as SwiftUI does, possibly memoised per value and
locale. A visible change, priced as above per number per build. Put to the
owner as DEPR-CATCHALL's follow-up.

### B-TEXTFMT-2. The `formatter:` interpolations ship, although O11 deferred the `Formatter` forms

*`appendInterpolation(_:formatter:)` for `ReferenceConvertible` and `NSObject`*

O11 (2026-10-12) deferred SwiftUI's `Formatter` forms because the parse
direction is internal in Linux Foundation. An interpolation only formats
(`Formatter.string(for:)`, public everywhere), and without these overloads a
`Date`, `URL` or `UUID` interpolated with no formatter would warn in TUIkit
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

Each follows a `Text` initializer or a type TUIkit does not have, and is
interpolated through the deprecated catch-all, with its warning, until that
lands:

- **The date range and interval.** `Text(_:)` of a `ClosedRange<Date>` or a
  `DateInterval` does not exist in TUIkit yet. SwiftUI's format is its own,
  not Foundation's `Date.IntervalFormatStyle` default: measured (the same
  probe), an hour reads
  `11:13 PM-12:13 AM` and three days `May 8 - May 11`, with no year even 400
  days apart, where Foundation writes `5/8/2026, 11:13 PM – 5/9/2026, 12:13 AM`.
  Matching it is the initializers' work, and the interpolations follow them.
- **`LocalizedStringResource`.** TUIkit takes a `LocalizedStringResource`
  nowhere yet: no `Text` or control initializer does.
- **`accessibilityName:`.** Declined on 2026-10-05 (A33; the parity map).
