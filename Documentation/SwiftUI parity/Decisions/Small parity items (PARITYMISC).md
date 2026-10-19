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
