# Default focus, drop badges and stack spacing: decisions from lane BITEMS1

*Lane BITEMS1, 2026-10-13, shipping decisions B35 (the automatic first-control
focus is nobody's until something happens to it) and B10 (the drop-operation
badge). The calls below are the ones the owner's rulings left open. The format
is that of the main decisions file:*

- **A-BITEMS1-n — needs your decision.**
- **B-BITEMS1-n — shipped the safe option.** Says what the fuller version
  would be, and its price.
- **C-BITEMS1-n — declined.** With the reason.

## B. Shipped the safe option

### B-BITEMS1-1. A delete wears no badge, and only the item-provider drops propose one

*`DropOperation`, `DropProposal`, `View.onDrop(of:delegate:)`,
`View.dropDestination(for:action:isTargeted:)`*

The ruling of 2026-10-12 confirmed three glyphs: `+` for a copy, `↗` for a
link and `⊘` for a forbidden drop, with nothing for a move. Three things it did
not settle:

- **`.delete`.** The entry offered `×` (U+00D7, East Asian Ambiguous) or `✕`
  (U+2715, Neutral); neither was confirmed. **Shipped:** no badge, as for a
  move — the delete is still accepted, and the delegate's `performDrop` is
  where it means anything. **`.cancel`** wears none either: it proposes no drop
  at all, which macOS shows with a plain pointer (unmeasured here; drag and
  drop needs a window server an offscreen probe does not have).
- **TUIkit's other destinations.** `dropDestination(for:action:isTargeted:)`,
  a `List`'s or `Table`'s insertion and reordering, and a tab's drop zone
  propose no operation, so they wear no badge. SwiftUI documents no operation
  for `dropDestination`; on macOS it is believed to draw `+` (unmeasured).
  **The fuller version:** `dropDestination` proposes `.copy` and a reorder
  `.move` (which wears nothing anyway): one line in `DropDestinationModifier`,
  plus a decision on whether a TUIkit-only API should look like macOS's
  `Transferable` drop.
- **The destination's highlight.** The proposal said the drop target's
  highlight "can" shift colour to match. TUIkit draws no highlight for these
  views — the app draws its own from `isTargeted` — so there is nothing to
  shift. **The fuller version** would hand the app the proposed operation,
  which SwiftUI does not do either.

The badge sits on the preview's top-right cell, not beside it: the preview's
frame is what a `DropInfo` reports and what a cancelled drag walks home from,
and a cell beyond it would make the carried picture wider than that frame. It
hides the preview's corner cell while it shows.
