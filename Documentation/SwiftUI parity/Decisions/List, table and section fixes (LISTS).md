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

### B-LISTS-2. Rows a List does not draw: the sites that draw them anyway, identified, not yet gated

*`List`'s windowing; `.onAppear`, `.sheet` and the focus ring on a row (the
modal-input-channels note: "suppressing side effects of off-window rows that
some configurations DO materialise — needs the materialisation sites
identified first")*

A `List` draws only the rows its window walks, so a row of a flat loop that
is out of sight does nothing a drawn row does until it is scrolled to: it does
not appear, put up a presentation or take a place in the focus ring
(`ListOffWindowSideEffectsTests` pins that). The sites that draw rows the
window does not walk, found with a row's `.onAppear` far below a list eight
lines tall — in each case every one of 40 rows appeared:

1. **A `Section`'s whole content**, rendered every frame into a buffer nothing
   reads (`SectionInfo.contentBuffer`), kept for exactly those effects: every
   row of every section, on screen or not, and the drawn ones twice.
2. **The section's child walk** (`Section.listRows`, a section of several
   views — a hand-written row beside a loop): every row is rendered as it is
   read, to make its buffer.
3. **The list's child walk** (`_ListCore.extractFromChildren`, the same
   arrangement without a section): likewise.

**Shipped:** the identification and the test of the flat case; no site is
gated yet.

**Why not the first, which is one line:** removing it was tried, and it
gates that site (the sectioned case then passes), but it exposes a hole in
the tab view's sidebar. Its rows are a loop over their places
(`_SidebarSectionList`), drawn from tab data the place does not carry, so the
row memo — which assumes a row is a pure function of its element — serves a
tab's old picture, and replays its old effects, after the tab changes. The
section's second render of its content each frame had kept that memo from
serving those rows; without it, a tab whose context menu went away kept its
Shift+F10 opener (`TabContentInteractionsTests`, "Shift+F10 on a tab whose
menu went away is not taken while another tab keeps its own", fails). Taking
the memo off those rows instead fails `TabInteractionsMemoTests`, which pins
that they are served. The order is: key the sidebar's rows by what they draw
(a comparable signature of the tab — title, badge, disabled, which
interactions it has — beside its place, so a change misses the memo for that
row alone), then drop the render. About two hours, an A/B on the tabs
scenarios and on sectioned lists (`session`, `inbox`: the render is a second
draw of every section row, every frame).

**The second and third** are decisions B73's option 1 (draw hand-written rows
lazily, as looped rows are drawn), which lane LISTS2 built in the same two
functions (2026-10-19): the test's `spliced` shape joined its arguments, and
`mixedSection` waits for the first site, whose render draws every row of the
section still.
