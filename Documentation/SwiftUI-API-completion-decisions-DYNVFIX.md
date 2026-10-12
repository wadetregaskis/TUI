# Completing the SwiftUI API: decisions from lane DYNVFIX

*Lane DYNVFIX, 2026-10-12, fixed the ten dynamic-property bugs the DYNV
research confirmed (session notes `DYNV/notes.md`, `DYNV2/notes.md`), keeping
every reach TUIkit supported, as the owner asked: "Take the best of both as
much as you can; 'hybrid', but try not to lose anything that we currently
support, even if SwiftUI doesn't support it." The property walk is now
planned once per type from the runtime's field metadata (`PropertyPlans`),
not reflected from each value with `Mirror`. SwiftUI's behaviour was measured
with SwiftUI 6.5.4 on macOS 15.8.1 with offscreen `NSHostingView`s (probes in
the session notes, `DYNV/probe/`, `DYNP/optional/`). The format is that of
the main decisions file:*

- **A-DYNVFIX-n — needs your decision.**
- **B-DYNVFIX-n — shipped the safe option.** Says what the fuller version
  would be, and its price.
- **C-DYNVFIX-n — declined.** With the reason.

## B. Shipped the safe option

### B-DYNVFIX-1. A property subclass behind a field declared as a plain class is not updated

*`DynamicProperty`*

A field declared as a plain class, `let delegate: RowDelegate`, can hold a
subclass that is a property, `CachingRowDelegate: RowDelegate,
DynamicProperty`. TUIkit's walks found it from the value, but kept a view type
as holding nothing when its first value held a plain instance there, so
whether the property was ever updated depended on the first value drawn
(DYNV bug 10).

**Shipped:** the declared type decides, as SwiftUI decides it (measured,
`DYNV/probe/dv2-main.out`, `subclass`: never updated; declared as the
subclass, updated). To have the property updated, declare the field as the
subclass, or make the base class the property.

**The fuller version** would look at every object field's value each body.
Its price: a load of the reference and a compare of its class per object
field per body, in every view that holds any object, such as an
`@Observable` model passed as `let model: Model`, whatever it holds. No use
of the reach was found (DYNV §3).
