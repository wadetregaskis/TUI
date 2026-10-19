# SwiftUI API completion — lane LISTS (list, table and section fixes): new judgement calls

*Lane LISTS worked through a set of open list, table and section items on
2026-10-18. Each call below came up on the way. The safe option shipped; the
alternative and its price are given. Numbered as the main decisions document
is: A = owner decision, B = basic shipped, C = declined.*

## B. Basic option shipped

### B-LISTS-1. A row's badge is read through environment writes only

*`View.badge(_:)`, `View.badgeProminence(_:)` on a `List` row (decisions B72)*

Measured on macOS 15.8 (`Tools/SwiftUIProbes/Badge prominence/badgeprom.swift`):
a `.badgeProminence(_:)` written on a row around its `.badge(_:)` is that
badge's, and wins over the list's; one written inside the badge is not; and a
badge with a padding after it, `.badge(5).padding(.leading, 0)`, is still
drawn, with a prominence written around the padding reaching it.

**Shipped:** a `List` reads a row's badge, and the prominence written around
it, through any number of environment writes after the `.badge(_:)`
(`.badge(5).badgeProminence(.decreased)`, `.badge(5).environment(…)`). It is
a conditional conformance of `EnvironmentModifier` to the badge carrier, so
the windowed list's type gate (`viewTypeCarriesBadge`) still answers from
the row's type alone, and a row without a badge pays nothing for it.

**Not shipped:** a badge with any other modifier after it — a padding, a
frame, a foreground style — is still not seen as the row's badge, and the row
draws without one, where SwiftUI draws it. Before this lane that was also true
of an environment write after the badge.

**The fuller version:** read the badge through every single-content wrapper,
as the container-value walk (`throughWrappers`) does for a tag or a z-index.
The badge gate is asked of every row on every frame, and it is a single cached
conformance check today; walking the row's type through its wrappers is a
cast per wrapper per row per frame, on the windowed path of every list. About
two hours, plus an A/B on `megalist`, `session` and `inbox`.
