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

### B-BITEMS1-2. A stated spacing edge outweighs a default one, as in SwiftUI

*`ViewSpacing`, `ViewSpacing.distance(to:along:)`, `ViewSpacing.formUnion(_:edges:)`,
`Layout.spacing(subviews:cache:)`*

B20's entry described TUIkit's `ViewSpacing`: a union takes each edge's larger
value, a distance the larger of the two facing edges, and `ViewSpacing()` is
one column beside a view. Probing SwiftUI for B20's fuller version
(`Tools/SwiftUIProbes/Stack spacing per pair/distances.out`) found its
arithmetic is not that. `ViewSpacing()` is the DEFAULT, not a number: `.zero`
facing it is 0 apart either way round (TUIkit said one column), `.zero`
merged with it is still `.zero` (TUIkit said `ViewSpacing()`), and two views
are the default apart only when both facing edges are the default. So a
layout that asks for no space beside it gets none from a plain neighbour
either (`spacing.out`: a tight layout beside a box, 0 points).

**Shipped:** SwiftUI's arithmetic. An edge of `ViewSpacing()` is stored as
unstated (the smallest `Int`, so a merge is still `max` and a stated edge
always wins); `distance` answers the default — one column, no row — only
where both facing edges are unstated. `Layout`'s default
`spacing(subviews:cache:)`, and `GridLayout`'s, merge from the default rather
than from `.zero` (from `.zero` every layout would now answer `.zero`), and
answer `.zero` for a layout with no subviews, as SwiftUI's did. What moves
for an app: a custom layout that spaces its subviews by `LayoutSubview.spacing`
now puts no column between a plain view and a neighbour that states `.zero`;
`ViewSpacing().union(.zero, edges: .leading)` now asks for no space on its
leading edge, where it asked for the default before (no TUIkit spelling could
say that before).

**The alternative** is TUIkit's old arithmetic, which would have the stacks
of B20 keep a column between a plain view and a tight layout where SwiftUI
keeps none. It has no use but the old answer.

## A. Needs your decision

### A-BITEMS1-1. Should a `Spacer` prefer no spacing, as SwiftUI's does?

*`Spacer`, `ViewSpacing`*

Measured on SwiftUI (`distances.out`, `spacer|box`): a `Spacer`'s preference
is zero on every edge, so `HStack { Text("a"); Spacer(); Text("b") }` puts no
gap either side of the spacer — the spacer takes it all. TUIkit's `Spacer`
prefers the default like any view, so the row keeps one column either side.
Wherever the row has room the difference cannot be seen (the spacer absorbs
it); it shows where the row has none — at its ideal width, or squeezed — as
two columns more than SwiftUI's reading would give it (TUIkit's side not run
for this note).

- **(a) Keep TUIkit's.** A spacer's gaps stay as they are; documented as a
  deviation.
- **(b) SwiftUI's.** A spacer states `.zero`. Every `HStack` with a spacer
  then resolves its gaps per pair (B20's path): a static witness makes that
  cost nothing for rows without one, but rows with a spacer — common — would
  take the per-pair path every walk. Measured cost unknown (an A/B on
  `kitchensink`, `deep` and `table`), and every fixed-size row with a spacer
  narrows by two columns.

**Recommended: (a)** until the A/B prices (b); the visible difference needs a
spacer squeezed to its minimum.
