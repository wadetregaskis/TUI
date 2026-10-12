# Completing the SwiftUI API: decisions from lane RES

*Lane RES took the remedies that lane CTL's diagnosis named for the module
split's last two warm residuals against the pre-split build, 2026-10-10:
`controls` (+0.55%, six placements) and `table-tail` (+0.6%, one placement).
R1 makes `Gesture.onEnded(_:)` `@inlinable`; R2 inlines `ItemListHandler`'s
selection getters into `isSelected(at:)`; R3 inlines
`BorderRenderer.standardContentLines` into `_ContainerViewCore`'s
`renderStandardStyle`. None changes public API. This file holds the judgement
call the lane reached that its brief did not already settle, in the format of
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>):*

- **A-RES-n — needs your decision.** Nothing has shipped for these.
- **B-RES-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-RES-n — declined.** With the reason.

### B-RES-1. A container's footer lines are still built by an out-of-line call

*Sources/TUIkitFoundation/Rendering/BorderRenderer.swift — no API*

**Shipped:** `@inline(__always)` on `standardContentLines`, whose one caller,
`renderStandardStyle`, calls it twice: once for the body's lines, once for the
footer's. Before the split it inlined both; since, neither. Swift 6.2.4 honours
the attribute only while the caller has under 64 basic blocks or the callee at
most 64 (`isInlineAlwaysCallSite` in PerformanceInliner.cpp). This callee has
more, so the body's call, the first, is inlined, and the footer's falls back to
the inliner's cost model, which declines it as on main. Measured in a release
`Stress` (Xcode 6.2.4): `renderStandardStyle` builds the body's lines in its
own code, as the pre-split build did, and makes one call for the footer's
(main: two); `__text` +964 B, against an estimate of about +1.7 KB for both.

The body is what every bordered container draws; the footer is drawn only by a
container that has one, and costs the one call per footer per draw that it
cost on main.

**The other version:** both calls inlined, as before the split. Two ways:

- `@_transparent` instead: the mandatory inliner takes it at every call site,
  but in debug builds too, where stepping into the function stops working; no
  file in `Sources` uses the attribute yet.
- One call site: `renderStandardStyle` builds the body's and the footer's
  lines through one call. The divider between them and the body's known width
  (which the footer's lines do not have) make that a change to a drawing path.

**Price:** about +0.7 KB more `__text` (the estimate for both, less what
shipped; unmeasured), for a gain only where a container has a footer
(unmeasured; one call per footer per draw at most). If the coordinator's
`table-tail` A/B still shows a residual, this is not where it is: that
scenario's bordered container is its `Table`'s, which `Table` builds without
a footer.
