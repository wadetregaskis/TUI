# Which language a key is read in

*How a localized key is looked up: the order of languages, a language TUI
does not ship, and a `\.locale` override. Ids: A14's lookup order, B-FU2-1,
B-PARITYMISC-5, LOCALE-B, A-APPSTATE-1 (in
[Per-app render state](<../State and dynamic properties/Per-app render state: no singletons.md>)).*

## In short

Keys are looked up language by language, through the languages the user
prefers, up to the first TUI ships (A14, decided 2026-10-05). The root
`\.locale` is the user's locale; a `\.locale` override re-reads a `Text`'s
key when drawn (LOCALE-B, 2026-10-18), though a `Button`'s title, read when
made, does not yet.

## The record

#### A14's lookup order — decided 2026-10-05

*`LocalizationService`, `Text(_:tableName:bundle:comment:)`, TUI's own
controls' strings*

The first order (60296e574) read an app's `Localizable` table ahead of
TUI's own strings for every key, so an app that happened to spell
`button.ok` in it changed TUI's OK by accident. The owner accepted the
recommendation, with one rule added: "if there are no built-in TUI
translations for the active language, … automatically try the app's strings.
Better to get some of them, even if imperfect, than none at all."

**Shipped:** both orders go language by language — the languages the user
asked for, including any ahead of the first TUI ships (`LANG=pt_BR`), then
English.

- **TUI's own words** (its controls and the typed `LocalizationKey`s, which
  name TUI through `frameworkString(for:)`): registered strings, a
  `TUI.strings` table the app ships, TUI's translation, and — only where
  TUI has no translation of the key in that language — the app's
  `Localizable`, before English.
- **The app's keys:** the table the call names, registered strings,
  `Localizable`, then TUI's strings (so an app can borrow them). This is a
  deviation from SwiftUI where the call names a table (or a bundle) that lacks
  the key: SwiftUI's `Text("greeting", tableName: "Onboarding")` shows
  `greeting`, and TUI goes on to the rest of the order. Kept as the owner's
  order; the compatibility doc marks it.
- Writing out the default table (`tableName: "Localizable"`, `bundle: .main`)
  reads exactly as leaving it off.

### B-FU2-1. A language TUI does not ship is read only as far as the first it does

*`LocalizationService` (A14)*

**Shipped:** the languages a key is looked up in are the environment's list up
to and including the first language TUI ships (`currentLanguage`), then
English: `LANG=pt_BR` reads `pt`, then `en`; `LANGUAGE=pt:es` reads `pt`, `es`,
`en`; `LANGUAGE=fi:pt` with no shipped language reads `fi`, `pt`, `en`. A
language chosen with `setLanguage(_:)`, or stored by it, is read alone before
English. `currentLanguage` stays one of TUI's seven, so its public type does
not change, and the app's `Localizable` is read in the user's own language
first — for TUI's words only where TUI has none of them.

**The fuller version** is Foundation's own matching: a bundle's
`preferredLocalizations` against the whole of the user's list, per table, so an
app shipping `pt` under a `de:pt` user still reads German for the keys it has in
German and Portuguese for the rest only where German has none. A public way to
choose a language TUI does not ship (`setLanguage` takes a `Language`) would
come with it. About half a day; nothing in the tree needs it yet.

### B-PARITYMISC-5. A locale override re-reads a Text's key, not a Button's title

*`EnvironmentValues.locale`, `Text(_:tableName:bundle:comment:)` (the owner's
option B, 2026-10-14, and "locale should also pick string language as
SwiftUI does", 2026-10-15)*

Measured on macOS 15 (2026-10-18, an app bundle with `en`, `de` and `fr`
tables): under `.environment(\.locale, Locale(identifier: "de_CH"))` a
`Text("greeting")` reads the German table; under `pt_BR`, with no Portuguese
table, the development language's; a key the German table lacks shows the
key.

**Shipped:** the root `\.locale` is the user's locale (`pt_BR` stays
`pt_BR`). A `Text` made from a key keeps where its words came from (one
interned object per key, table and language, a word in the `Text`), and when
it is measured or drawn under a `\.locale` naming another language it reads
the key again in that language, its own style kept — lazily, at draw, as the
owner asked, since a `Text` is made before its environment is known. The
check is one environment read for a keyed `Text`, a nil check for any other;
nothing is read again where nothing overrides the locale. Every control whose
label is a `Text` of its key (B87's list: `Toggle`, `Label`, `Link`,
`Section`, `LabeledContent`, `Picker`, `Menu` and the rest) follows, and so
does `LocalizedString` for an app's key. So does a `Table`'s `Text` cell: a
plain one is drawn as the string it holds, never measured or drawn as a
`Text`, so the table reads its key in its own `\.locale`'s language before
taking the string (`Text.reading(in:)`), and an outline's first column puts
its triangle in front of those words. A key the language lacks reads
English (E4).

**The fuller version** reaches what reads a key as a string when it is made:
`Button`'s and `ColorPicker`'s titles (kept as strings for their measure and
truncation, B87), the titles drawn as strings (a column header, a tab's title,
a field's placeholder), `LocalizedStringKey.localized`, and TUI's own
chrome words (`frameworkString(for:)`: an alert's OK, a search field's
prompt). Each would resolve at draw from the environment's language: about a
day, most of it the string-titled controls. An A/B of the shipped half is
owed (Text-heavy scenarios: the `Text` grew a word, and a keyed `Text` pays
an intern lookup when it is made).
