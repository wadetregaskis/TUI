# Completing the SwiftUI API: decisions from lane SPH

*Lane SPH, 2026-10-08, recovered the run-time costs that module split steps B4, B5 and B6 added at the module
boundaries they drew, by the rules SPB5's diagnosis set for every carve: a plain import of what each file uses,
accessors rather than widened class storage, no stored-property defaults under an `@inlinable` initializer, and tier
2's `@inlinable` on the per-row and per-cell crossings. It changed no public API and no behaviour. This file holds the
judgement calls it reached that the plan did not settle, in the format of
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>):*

- **A-SPH-n — needs your decision.** Nothing has shipped for these.
- **B-SPH-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPH-n — declined.** With the reason.

## B. Shipped

### B-SPH-1. Tier 2 covers the per-row crossings that inline as annotated, not the ones that would need more

*Sources/TUIkitFoundation (RowBackground, ListRowSeparatorLine, ListSeparatorPreference, the line-limit and
truncation-mode environment), Sources/TUIkitStyling (HighlightFill) — no API*

The brief allowed `@inlinable` on the crossings that the plan's tier 2 or set T lists, or that step B6's inventory
names per row or per cell, and asked that each one's call be gone from the release Stress binary, or go to a
specialised or inlined body. Annotating is not enough for that, as two measurements showed:

- **An `@inlinable package` member of a type that is only `package` is not serialized.** A `-emit-sil` probe
  against the release modules sees `ListRowSeparatorLine.init(tint:leading:trailing:)`,
  `ListSeparatorPreference.overridden(by:)` and `RowBackground`'s getters as `package_external` declarations with
  no body, so the release Stress still called all of them. With the types (and the fields and members the bodies
  read) `@usableFromInline`, which is the style step A3 used for `ClaimingRow`, the bodies are there to inline. The
  type checker accepts the first form without a word.
- **`-O` does not inline a generic into an unspecialised generic caller.** `Button.init(action:label:)` and
  `HStack.init(alignment:spacing:content:)` made `@inlinable` were still called, unspecialised, from
  `_NavigationLinkCore.button` and `_OutlineRow.branchRow`, which are generic over the app's views and are not
  specialised in TUIkitNavigation or TUIkitLists. The same holds for `extractBadgeValue(from:)` and
  `staticListRowID(of:ordinal:as:)`, which `_ListCore.extractRows(ofUnwrapped:context:)` calls, generic over the
  row. `HorizontalAlignment.childOffset(childWidth:in:)`, made `@inlinable` with `ViewDimensions`' initializer and
  subscripts, was serialized but not inlined: with the guides' dictionary lookup inlined into it, it is past the
  inliner's size limit.

**Shipped:** `@inlinable` on `RowBackground.tint(_:)`, `claimableFill`, `stepNow` and `pulseTiming`,
`ListRowSeparatorLine.init(tint:leading:trailing:)`, `ListSeparatorPreference.overridden(by:)`, and the
`lineLimit` and `truncationMode` environment accessors (tier 2), with what their bodies read
`@usableFromInline`: the three types and the two structs' fields, `RowBackground.Paint`, `HighlightFill`,
`SelectionEmphasisCycle.timing` and `isAnimating(dim:bright:)`, `IndicatorCycleTiming`, and the two environment
keys. No class's stored property, and no type that conservative cross-module optimisation reads differently: all
of them were `package` already. The annotations that did not inline (`Button.init(action:label:)`,
`HStack.init`, `childOffset`) were taken out again rather than left as decoration.

**The other version,** crossing by crossing, and its price:

- **`ANSIRenderer.colorize` and `TextStyle.init()` / `foregroundColor` (tier 2).** `colorize` builds a
  `TextStyle`, so all three need `TextStyle` usable from inline code: its fourteen stored properties and the
  three `Stated…` enums `@usableFromInline`, and its four enum-case defaults deleted and assigned in its
  initializer (CONTRIBUTING.md, "Crossing a module boundary"). The price is also a layout change: with `TextStyle`'s
  fields usable from inline code, conservative CMO can serialise more of `Text`'s public modifiers into every app,
  as B5's widening of the type did for `bold()` (SPB5's diagnosis, §3.1 and §6.4), which moves every address after
  them. Worth an A/B of its own, once the coordinator's A/B shows whether the table rows (`table*`) still need it.
- **`Button.init(action:label:)` and `HStack.init` (B5's `NavigationLink` row).** Only `@inline(__always)`, or
  `@_specialize` on the callers, would remove the call; neither is in the plan's annotation style (step 0b), and
  both cost code size in every specialisation.
- **`childOffset` (per table cell, per tab-strip line).** `@inline(__always)`, or splitting it so the common
  case (no explicit guide) is a few arithmetic instructions. The work in its body, a dictionary lookup and a call
  through the alignment's `AlignmentID` metatype, would stay.
- **Not annotated, their own work being the cost (the tier cut's "left out as their own work"):**
  `ANSIRenderer.styleSequence(for:)`, `applyPersistentDim(_:)`, `PaintRenderer.band`, `RampSampler.alphaClaims`,
  `RowBackground`'s `painting(_:padding:)`, `framePaints`, `stillLines(_:)` and `Paint`'s, and
  `ListRowSeparatorLine.drawn(width:palette:)`. `LazyListRowContent.init(buffer:badge:)` initializes a class's
  stored properties, which would have to become `@usableFromInline`: the first rule of the diagnosis forbids it.
