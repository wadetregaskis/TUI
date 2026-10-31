# Layout and geometry: how it came to be

One story per subject, each with the record of its decisions below it (see the
[Historical README](../README.md) for the arrangement). The current design is in
[Layout and scrolling](<../../Layout and scrolling/>); deliberate departures from SwiftUI
(L1 to L17) are in [Deliberate deviations from SwiftUI.md](<../../SwiftUI parity/Deliberate deviations from SwiftUI.md>).

| Story | What it covers |
|---|---|
| [Alignment guides that travel out of their view](<Alignment guides that travel out of their view.md>) | Guides through containers, modifiers, app view types, lazy stacks, `AnyView` and `Grid`; the push bound (B19, GUIDE, GUIDE3, LAYOUT, LAYOUTPERF). |
| [Drawing past a region](<Drawing past a region.md>) | Overflow layers: guided views, overhangs, larger content, `.offset` and `.position`, who cuts them (GUIDE, GUIDE3, LAYOUT). |
| [Stack spacing, and what a container counts as its children](<Stack spacing, and what a container counts as its children.md>) | `spacing: nil` per pair, `Spacer`'s preference, members of groups, `AnyView`, `EmptyView`, app views and loops (B20, BITEMS1, D1S, LAYOUT). |
| [Sections and pinned headers in lazy stacks](<Sections and pinned headers in lazy stacks.md>) | Sections as parts, lazy stacks keeping theirs whole, pinned headers (D1S, B66–B71). **Owed:** the fuller lane. |
| [Where a view is: coordinate spaces, geometry readers and scroll visibility](<Where a view is - coordinate spaces, geometry readers and scroll visibility.md>) | Design G4: markers, predictions and corrections (A2, A7, D5G), with the design study as an appendix. |
| [Sharing space: overfull columns and ideal sizes](<Sharing space - overfull columns and ideal sizes.md>) | Rows and columns sharing space by flexibility; a frame's ideal size. **Open:** A-LAYOUT-1. |
| [Safe areas, size classes and layout direction](<Safe areas, size classes and layout direction.md>) | No safe area, settable size classes, left to right only (B1, A3, B3, B6, B25). **Deferred:** right-to-left. |
