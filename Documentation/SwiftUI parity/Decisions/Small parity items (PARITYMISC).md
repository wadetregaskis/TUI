# Small parity items: decisions from lane PARITYMISC

*Lane PARITYMISC, 2026-10-18: a batch of small SwiftUI parity items and
Example demos from the 2026-10-18 inventory of open work. The calls below are
the ones the owner's rulings left open. The format is that of the main
decisions file:*

- **A-PARITYMISC-n — needs your decision.**
- **B-PARITYMISC-n — shipped the safe option.** Says what the fuller version
  would be, and its price.
- **C-PARITYMISC-n — declined.** With the reason.

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

TUIkit had 8 of the SDK's 43 content types (macOS 15), and spelled
SwiftUI's `.URL` as `.url`, so most `.textContentType(_:)` calls failed to
compile. A content type is a filter here (T8, owner 2026-10-13: keep the
filter, ring the bell, and admit every character a valid value holds).

**Shipped:** all 43 under their Swift names (`.url` became `.URL`, no alias),
beside TUIkit's own `.integer` and `.decimal`. A type gets a character set
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

