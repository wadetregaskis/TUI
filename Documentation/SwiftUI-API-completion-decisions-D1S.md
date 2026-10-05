# Completing the SwiftUI API: lane D1S's new judgement calls

*The lane that implemented the owner's decisions on B15, B16, B17 and A44 of
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md).
Where the work met a judgement call those decisions did not settle, the safe
option shipped and is written up here, in that document's three parts: A needs
a decision, B shipped the safe option (with the fuller version and its price),
C declined with a parity-map reason. SwiftUI's behaviour was measured on macOS
15.8 with offscreen `NSHostingView`s (probes in the session notes,
`D1S/probe/`).*

## B. Shipped the safe option

### B-D1S-1. A pinned lazy stack keeps its own sections whole

*`LazyVStack(alignment:spacing:pinnedViews:content:)`,
`LazyVGrid(columns:alignment:spacing:pinnedViews:content:)`, `Section`*

Everywhere outside a `List`, a `Form` and a `Table` a `Section` is now its
parts (B16): the container lays its header's, content's and footer's views out
as its own children. A lazy stack that pins its sections' headers or footers is
the exception. Pinning is done by the section, which knows where its header,
content and footer are and emits a copy of the header marked to pin; a stack
handed the parts as anonymous rows could not say which row is whose header, and
its windowed paths would not draw a header that has scrolled out of the band
while its rows are still on screen. So a pinned stack keeps its own sections
whole, and each lays its parts out as the stack would — along its axis, its
`spacing` between every two (between the header and the first row too, as
SwiftUI spaces them), each aligned across by its alignment.

What differs from taking the section apart:

- **Centre alignment can be a cell off.** The section centres its views within
  its widest view, and the stack centres the section. Where those two widths
  differ in parity a view lands a cell from where the stack would centre it
  unpinned. Leading and trailing alignment are exact.
- **A modifier on such a section wraps it whole**, where SwiftUI applies it to
  each part (`Section { … }.padding(.top, 10)` pads the section once, above
  its header, not above each row).
- **The stack windows by section.** A section in the band draws all of its
  rows, as before this lane; unpinned, the stack windows over the rows.

**The fuller version.** The stack takes its own sections apart like any other
container and does the pinning itself: it keeps a map from each section to its
header row, content rows and footer row; every windowed path (the uniform
seek, the anchored window, the exact walk, and the append-while-fits walk)
draws the header and footer of any section that meets the band even when they
are outside it; and the stack emits the pin layers from the rows' positions.
About two days with the tests, most of it in the anchored window, whose rows
away from the band have estimated positions.

### B-D1S-2. A section header in a menu is a plain item

*`Menu`, `Section`*

A `Section` in a `Menu` is its parts, as in any container that is not a
`List`, a `Form` or a `Table` (B16), so its header is drawn as a line of plain
text among the items. Before this lane it was drawn bold and dimmed, a section
drawn as one unit. SwiftUI's macOS menus show a section's header as a smaller
grey title, which is styling, so the owner's B16 rule ("a header outside a
`List`, `Form` or `Table` gets no styling") and SwiftUI's menus disagree here.

**The fuller version.** The menu's walk keeps sections whole (as a `List`'s
does, `RenderContext.keepsSectionsWhole`) and the menu style draws a section's
header as a disabled title in the menu's secondary colour, with a separator
before every section but the first, as macOS does. Half a day.
