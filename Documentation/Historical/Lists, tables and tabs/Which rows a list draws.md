# Which rows a list draws

*The places a `List` or `Table` draws rows outside its window, a list that
does not clip, who owns `.scrollView` in a list, and which loop a hierarchical
table's slot belongs to, and what a list knows of the rows it has not drawn.
Ids: B-LISTS-2, B-LISTS2-5, B-LISTS2-6, B-LISTS2-7, HUNT-O-04; B-D2S-4 and
B-D5G-9 (in the scrolling and layout stories).*

## In short

A list draws only the rows its window walks, plus the sites lane LISTS
identified that draw others (gated by lane LISTS2). Under
`scrollClipDisabled` a list draws the row before and after its window, not
clickable; a table still clips. A list owns `.scrollView` for the readers in
its rows but does not predict their places before drawing them. What a row
refuses (`.deleteDisabled()`, `.moveDisabled()`, `.selectionDisabled()`) is
kept from frame to frame by row id, and the keys that act on rows no frame
has drawn draw them as a measure first (HUNT-O-04).

## For a future reader

- **`OutlineSubgroupChildren`** is declined: TUI's `OutlineGroup` drops the two generic parameters that are always the same (C10, below).
- **Owed:** a `Table` honouring `scrollClipDisabled` (about half a day,
  B-LISTS2-5), and the overflow rows' clicks (about two hours).

## The record

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
gated yet. **All three are gated since 2026-10-19 (lane LISTS2)**, and every
shape of the test is among its arguments — see below for each.

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
draw of every section row, every frame). **Done in that order (lane LISTS2,
2026-10-19):** the sidebar's rows are `_SidebarRow`s, keyed by place and
compared by their tab's look — which tab it is, by its value, beside what
the row draws — and `SectionInfo` has no content buffer; the A/B is owed. A
row whose look cannot say what it draws or calls (a label view of the
app's own, a popover's content while it shows, a drag's payload, a drop's
action) is drawn afresh every frame by its own memo alone.

**The second and third** are decisions B73's option 1 (draw hand-written rows
lazily, as looped rows are drawn), which lane LISTS2 built in the same two
functions (2026-10-19): the test's `spliced` shape joined its arguments, and
`mixedSection` waits for the first site, whose render draws every row of the
section still.

### B-LISTS2-5. A list that does not clip draws the rows past its frame, not clicked; a table still clips

*`View.scrollClipDisabled(_:)` on `List` and `Table` (decisions-D2S B-D2S-4)*

**Shipped:** a `List` under the modifier draws the row before its window and
the one after, outside its frame, as overflow layers at its place in the
stacking order (B-D2S-4). They are drawn, not clicked: the list's click
mapping covers its frame, and a row's own controls there take no press.

**The fuller version:** carry each overflow row's own regions out with it,
and map a click on one to its row as a click on a drawn row is mapped — about
two hours. And a `Table`: its two composers (single- and multi-line rows)
each need the same rows drawn and handed out — about half a day.

### B-LISTS2-6. A list owns `.scrollView`, but does not place its rows before drawing them

*`GeometryReader` and `scrollTransition` in a `List` row (decisions-D5G B-D5G-9)*

**Shipped:** the list draws its frame as the owner of `.scrollView` and
`.scrollView(axis: .vertical)`, answering a row's reader in its content
window and drawing the frame once more where one drew from a wrong answer.
A list with nothing asking pays the walk's checkpoint and a test of the
geometry's waiting count each frame.

**The fuller version:** place each drawn row at its line in the window before
it is drawn, so a scrolled list's readers are told where they are rather
than found there — no second drawing per frame. The line is what the window
walk renders rows to learn, so the prediction would take each row's height
from its measure: about a day, with the `table`, `tables-scroll` and
`session/inbox` A/Bs.

### B-LISTS2-7. A slot two loops of a hierarchical table reach goes to the deeper loop

*`DynamicTableRowContent.dropDestination(for:action:)`, `onInsert(of:perform:)`
in a hierarchical table (decisions B80)*

SwiftUI's outline view aims a drop at the end of a branch's rows or before the
next row out by the pointer's indentation (measured, `Tools/SwiftUIProbes/
Hierarchical table insertions/`); a terminal's drop line has none. **Shipped:**
the deeper loop that takes the payload has that slot, and the next row's loop
the ones it alone reaches. **Not copied:** where a branch's rows have no loop
that takes the drop, SwiftUI hands it to the roots' loop at the offset it had
among the branch's rows; TUI gives the slot to the loop whose rows it is
among, or to none: a slot none takes opens no gap, and a drop there is
refused and flies home, as it does in a flat table at a slot outside its
loops.

**The alternative:** aim by the pointer's column, as the outline view does —
left of the deeper level's indentation, the shallower loop. A drag's column
is known; about two hours, with the gap drawn at the matching indentation.

### HUNT-O-04. A row's refusals are kept by row id, and the keys that act on rows no frame has drawn draw them as a measure

*`.deleteDisabled()`, `.moveDisabled()` and `.selectionDisabled()` on rows
outside the window (bug hunt of 2026-11-20, findings LISTS-1 and LISTS-2,
work item H-11; owner ruling O-04, answer b+c, 2026-11-21)*

A row says what it refuses only as it renders: the flag is written inside the
row's subtree, so reading it off the row's structure would depend on modifier
order, which is why `RowEditRestrictions` is a collector. The list rebuilt
what it knew from each frame's rows alone, on the stated premise that "the
only rows a user can delete or move are the focused one and the grabbed one,
and both are on screen by construction". They need not be: the wheel scrolls
the cursor row away without moving the cursor. Delete then removed a locked
row, Ctrl+Down moved a pinned one, a grab carried a pinned selected row off
screen, and Select All, a Shift span and a follow-cursor page key selected the
`.selectionDisabled()` rows out of sight. The docs said a disabled row was
routed around "once it has rendered at least once"; the set was per frame,
so a row drawn and scrolled away was unknown again.

**The ruling (owner, 2026-11-21, b+c):**

- Keep each row's reports across frames by row id (`RowRefusalMemory`): an
  id is dropped when its row draws without reporting, or leaves the data, so
  only rows no frame has drawn are unknown. A row with no id (one the
  selection cannot name) is kept by its place, and forgotten when the row
  count changes.
- **(b)** Ctrl+A, a Shift range and a follow-cursor key that selects build
  each row they take that no frame has drawn and the memory does not hold,
  when the key is pressed: one view build per such row, drawn as a measure
  (`LazyListRowContent.refusalProbe`), as type select's search builds rows.
  A measure registers nothing, so a row far out of sight runs no `.onAppear`,
  takes no focus stop and puts up no presentation; it reports its refusals
  because the collector takes them from a measure while it probes
  (`RowEditRestrictions.probingRefusals(ofRow:_:)`).
- **(c)** Delete, the move chords, the pick-up chord and a grab's held
  selection ask their rows the same way before they act, kept rows included,
  so an edit never acts on a stale answer. Nothing visible changes.
- The reports are taken only from a render that is not a measure.
- Not asked of rows no frame has drawn: plain navigation. Up/Down and the
  page keys route around a `.selectionDisabled()` row once it has drawn;
  asking every row they pass would cost a build on every arrow key.

**Measured (2026-11-21, debug build):** Ctrl+A over 10,000 rows of
`HStack { Text; Text }`, ten of them disabled, at the top of a fresh list so
that every row but the ten drawn is unknown: 0.78 s, against 7.5 ms with the
probe switched off. The same list's type-select search for a prefix no row
has, which builds and measures every row the same way, took 0.80 s. A row
whose type-select text is a plain `Text` is read without a draw there, so a
list of bare `Text` rows searches faster than this probe asks them; the
probe has no such shortcut, since the flag can sit anywhere in the row. Once
asked, a refusing row is kept and not asked again by a bulk key; a row that
refuses nothing is asked again by the next one.

### C10. `OutlineSubgroupChildren`

*`OutlineSubgroupChildren`*

The content type of the `DisclosureGroup` that is SwiftUI's
`OutlineGroup<…, Subgroup>` for views — a type only ever written inside
`OutlineGroup`'s full generic signature. TUI's `OutlineGroup` declares
the three generic parameters that carry information and drops the two that
are always the same (`Parent` is `Leaf`; `Subgroup` is that one
`DisclosureGroup`), as its documentation records, so there is no subgroup
type for this to be the content of. Every `OutlineGroup` initializer, for
views and for table rows, is SwiftUI's; only spelling the type out by hand
differs.
