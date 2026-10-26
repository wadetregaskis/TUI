# Small parity items: decisions from lane PARITYMISC

*Lane PARITYMISC, 2026-10-18: a batch of small SwiftUI parity items and
Example demos from the 2026-10-18 inventory of open work. The calls below are
the ones the owner's rulings left open. The format is that of the main
decisions file:*

- **A-PARITYMISC-n — needs your decision.**
- **B-PARITYMISC-n — shipped the safe option.** Says what the fuller version
  would be, and its price.
- **C-PARITYMISC-n — declined.** With the reason.

## A. Needs your decision

### A-PARITYMISC-1. Core Data's FetchRequest family: build it now, or when an app asks?

*`FetchRequest`, `FetchedResults`, `SectionedFetchRequest`,
`SectionedFetchResults`, `EnvironmentValues.managedObjectContext`*

Your A18 ruling (2026-10-12, option 1) allows Apple-only API behind
`#if canImport` where it is honoured on Apple platforms, and says Core Data's
`FetchRequest` "becomes possible" — not that it be built. Nothing is built;
the parity map now says the family is permitted and waiting on this, where it
used to say a policy forbade it.

**Options.**

1. **Build it now.** The property wrappers over `NSFetchRequest` (entity,
   sort descriptors, predicate, animation, and the `fetchRequest:` forms),
   the results collections with their settable `nsPredicate`,
   `sortDescriptors` and section identifier, and `\.managedObjectContext`;
   redrawn when the context announces changes
   (`NSManagedObjectContextObjectsDidChange`), tested on an in-memory store.
   Honoured on macOS, absent on Linux and Windows. *Price:* three to four
   days, and an Apple-only surface to keep working on every macOS SDK the CI
   builds.
2. **When an app asks.** Leave it permitted and unbuilt; the map says why.
   *Price:* nothing now; Core Data code that ports does not compile until
   then.
3. **Decline it after all.** *Price:* nothing; it contradicts nothing in A18,
   which allowed rather than required it.

**Recommendation:** 2. A Core Data app is a GUI app's data layer; a
terminal port of one is rare, and the work is days.

## B. Shipped the safe option

### B-PARITYMISC-1. A wrong-typed write through an AnyHashable projection is reported and dropped

*`Binding.init(_:)` where `Value == AnyHashable`*

SwiftUI force-casts the written value to the base binding's type, so writing
a value of another type traps (measured 2026-10-18; `AnyHashable(Int8(7))`
into a projection of a `Binding<Int>`).

**Shipped:** the write goes through `SoftTrap`: a debug build stops there, as
SwiftUI's trap would, and a release build drops it and reports it once, the
base keeping its value (Deliberate deviations S7). It is the framework's
standing answer to a programming error with a safe fallback.

**The fuller version** would be SwiftUI's trap, exactly: one line (`as!`), and
the price is a crash in someone's terminal for a mistake a debug build already
stops at. Not recommended.

### B-PARITYMISC-2. Every NSTextContentType is spelled, free-text types filter nothing, and a TextEditor filters as a field does

*`TextContentType` (every `NSTextContentType` member), `View.textContentType(_:)`*

TUI had 8 of the SDK's 43 content types (macOS 15), and spelled
SwiftUI's `.URL` as `.url`, so most `.textContentType(_:)` calls failed to
compile. A content type is a filter here (T8, owner 2026-10-13: keep the
filter, ring the bell, and admit every character a valid value holds).

**Shipped:** all 43 under their Swift names (`.url` became `.URL`, no alias),
beside TUI's own `.integer` and `.decimal`. A type gets a character set
only where its values are drawn from a closed alphabet: digits for a card's
security code, its expiration month and year and a birth date's day and
year; digits, space and `-` for a card number; digits and `/-. ` for an
expiration date; letters, digits, space and `-` for a postal code, a
tracking number and a flight number; letters, digits and `.` for a birth
month (`3`, `March`, `Sept.`). Every other type — a password, a name and its
parts, a job title, an organisation, a location, the address parts, a
country, the name on a card, a card's type, a date and time, a full birth
date — is free text: any character can be in a valid value, so it filters
nothing.

`TextEditor` filters too, typing, pastes (the terminal's and Ctrl-V's) and
Ctrl-O alike, with the same bell, where it ignored the content type: a
modifier on a container that reached its fields but not its editor was a
silent no-op. A line break is filtered as any character is, as a vertical
`TextField` already filtered it, so an editor typed as an email address
takes none.

**The fuller version** would be per-type validation of structure rather than
of characters — a card number's Luhn check, a postal code's pattern per
country, an expiry month of 1–12. Each is a rule about a whole value, not a
character, so it belongs to submission rather than typing; about a day for
the numeric ones, and a locale table for postal codes. Not recommended
without an app asking.

### B-PARITYMISC-3. A column header and a tab title draw their key's Markdown words, not its styles

*`TableColumn`'s `LocalizedStringKey` initializers, `Tab`'s, and
`TextField`'s (B87's three leftovers)*

Measured on macOS 15 (2026-10-18, probes in
`Tools/SwiftUIProbes/Small parity items (PARITYMISC)/b87/`): SwiftUI parses Markdown in all three. A
`TextField`'s title becomes its placeholder as plain words
(`TextField("**Bold** and *it*", …)` has the placeholder string "Bold and
it", no attributes); a `TableColumn`'s header is styled (`"**Name** *x*"`
draws a semibold "Name" and an italic "x"); a `Tab`'s title draws exactly as
a `Text` of the key does.

**Shipped:** a field's title is its key's `Text`, so the placeholder draws its
words plain, exactly as SwiftUI's. A header and a tab title, which TUI
measures, truncates and draws as strings in a style of its own (the header
bold in the secondary ink, the strip's cells), take the key's words with the
delimiters gone (`LocalizedStringKey.titleWords`) and draw them in that
style.

**The fuller version** draws the styles too: the header row appending a cell
as styled runs rather than one ink (`ClaimingRow` takes one style a cell
today), and the strip and the sidebar drawing a tab's title as a `Text`. A
header is already bold, so only italic, strikethrough and a code span would
show. About half a day each, and an A/B, since both are drawn every frame
(B87's own change cost `app-shapes` +2.3%).

### B-PARITYMISC-4. A gradient on one interpolated fragment is written as its description

*`LocalizedStringKey.StringInterpolation.appendInterpolation(_:)`, the
catch-all; `Text + Text`, removed*

`Text + Text` is gone (SwiftUI deprecated it in macOS 26; the owner's ruling
[21] of 2026-10-12), replaced by SwiftUI's own replacement: an interpolated
`Text` keeps its styling. One thing `+` did differently: a gradient on one
fragment, `Text("a").foregroundStyle(gradient) + Text("b")`, failed to
compile, because `foregroundStyle` with a gradient returns a view, not a
`Text`. Interpolated, that view takes the catch-all `appendInterpolation(_:)`
and is written as its description, which SwiftUI's catch-all (deprecated
there, with a warning) does too.

**Shipped:** the interpolation as SwiftUI has it; the hole is recorded in the
compatibility guide's gradient note.

**The fuller version** closes it: an unavailable `appendInterpolation` for a
view that is not a `Text` or an `Image`, so the spelling fails to compile as it
did under `+`, or SwiftUI's typed overloads with the catch-all retired (the
DEPR audit's tenth item). The first is an hour but also refuses
`\(Color.red)`, which SwiftUI accepts with a warning; the second is half a
day and decides what each SwiftUI-accepted type writes.

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
