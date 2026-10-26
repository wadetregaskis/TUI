# Ctrl-U, selection kept to a container, undoable reorders: decisions from lane TEXT2

*Lane TEXT2, 2026-10-24: the owner's items #15 (Ctrl-U), #10 (a drag selection
begun inside a bordered container stays inside it) and #16 (reorders and drag
moves are undoable in the Example) from his message of 2026-10-23. The format
is that of the main decisions file:*

- **A-TEXT2-n — needs your decision.**
- **B-TEXT2-n — shipped the safe option.** Says what the fuller version would
  be, and its price.
- **C-TEXT2-n — declined.** With the reason, and a parity-map entry.

## A. Needs your decision

### A-TEXT2-1. A gesture that widens a container's selection to the pane

*#10's opt-out, from the mouse*

You asked for suggestions for getting past a container's interior from the
mouse; Option (a rectangle), Shift (a rectangle's moving corner, and many
terminals' own bypass) and Control (the secondary click) are taken.

What already works, at no cost: **start the drag on the container's border,
or outside it.** The border is not the interior, so a press there is the
pane's, and the drag crosses the container as it always did. The same goes for
a press in the page's blank cells beside the box.

Options for a gesture from inside:

1. **None beyond the border (shipped).** *Price:* nothing. A drag from the
   middle of a card's text cannot reach the page.
2. **A drag that leaves the container by more than N cells widens to the
   pane.** *Price:* small to build (`HeldPress` keeps the outer pane and
   re-clips the selection once), but ambiguous: a drag down to "the end of the
   card" overshoots the bottom border by a row or three as a matter of course,
   since a stream dragged past the clip's bottom already runs to the end of
   the last row. Whatever N is, a fast drag crosses it by accident, and the
   selection then jumps out to the page mid-gesture; and an N large enough to
   be safe is often more rows than there are below a card near the screen's
   foot.
3. **A double-press-and-drag on the border itself selects the whole box and
   extends from there.** *Price:* small; a new rule to learn.

**Recommendation:** 1. The border is a visible, unambiguous handle, and
`.textSelectionScope(.pane)` covers an app that wants the old reach
everywhere. I did not build 2 because of the overshoot.

**Ruling (owner, 2026-10-24): 2, as an experiment.** "I think (2) has
potential — let's try that first, and see how it feels." Built on lane
SELWIDEN for the owner to try; the border handle and
`.textSelectionScope(.pane)` work as before.

- **What widens.** A drag kept to a bordered container's interior that goes
  more than **3 rows** above or below it, or more than **6 columns** beside
  it, widens to the scope the container sits in, and the selection re-clips
  to it at once. The distance is counted in cells outside the interior, the
  border's own row or column being 1, separately per axis; either one past
  its limit widens. One constant pair, `HeldPress.wideningRows` and
  `wideningColumns`, in `TUIFoundation/App/HeldPress+Widening.swift`,
  which holds the whole rule.
- **Why 3 and 6.** The border and two rows beyond it stay inside, because a
  drag to "the end of a card" overshoots the bottom border by a row or two as
  a matter of course, and a stream dragged past the clip already runs to the
  end of the last row, so that overshoot loses nothing. The third row beyond
  the border is a drag that meant to leave, and still few enough rows to be
  there below a card near the screen's foot. Sideways it is twice that,
  because a cell is about half as wide as it is tall, so 6 columns are about
  the same distance on the screen as 3 rows, and a drag to a line's end
  overshoots sideways as freely as one to a card's end does downward.
- **One way.** Once widened, the selection stays widened until the release:
  a pointer that comes back inside the card does not narrow it again, so it
  cannot flicker between the two mid-gesture. Leaving is all that counts. The
  drag need not also be moving away, since the overshoot that should not
  widen is itself outward, and only its distance tells the two apart.
- **One scope at a time.** The next scope out is the next bordered
  container's interior around this one, an enabled `textSelection` around it
  (the widening stops there, since that scope is the app's own), or else the
  pane (a scroll view, a split view's column, the content area), which is
  always the limit. A card inside a card widens to the outer card's interior
  first. Leaving that by the same distance widens to the pane. The steps are
  measured from the rectangle in force, so one long jump can take two steps
  in one event, as it would in two shorter ones. A scope no wider than the
  last (an interior that fills its scroll view) is skipped.
- **Unchanged.** A drag begun on the border or outside the container, a
  drag kept to a list's or table's row, a cell's own `.textSelection(.enabled)`,
  and a Control-press, which selects nothing. TUI has no keyboard
  extension of the screen selection (no Shift-arrows), so there is nothing
  for the rule to apply to there.
- **Cost.** The check runs on each drag event of a gesture begun inside an
  interior. The rungs are built once at the press, from the hit regions it
  already walks. Nothing is added per frame or per region.

What to feel for: whether 3 rows is enough slack for a quick drag to a
card's end, and whether the jump to the page, when it comes, reads as
deliberate or as a surprise.

## B. Shipped the safe option

### B-TEXT2-1. Ctrl-U is readline's `unix-line-discard` in every text control

*#15. `TextField`, `SecureField`, a vertical `TextField`, `.searchable`'s field,
`TextEditor`*

The report was "Ctrl-U doesn't work". Measured in the live Example under a
PTY (legacy bytes, 0x15): every field erased its whole text wherever the
caret was, and kept nothing for Ctrl-Y; `TextEditor` passed the key on and
did nothing (it declined it on purpose: "one chord erasing a whole document is
a different thing"). Nothing earlier in the input chain took the key.

Now Ctrl-U kills from the caret to the start of the caret's line: in a field
on one line the whole text before the caret, in a vertical field and in the
editor the caret's logical line (its wrapped rows and all). One undoable edit,
kept in the kill ring for Ctrl-Y as Ctrl-K's kill is; a `SecureField` deletes
and keeps nothing, as for Ctrl-K. A selection goes first, as for Ctrl-K. At a
line's start it kills nothing and never takes the line break before it.
Ctrl-U still keeps the key from an app's ⌘U (which arrives as Ctrl-U): it is
the terminal's own line kill, not an Emacs bonus. Cocoa binds no Ctrl-U; ⌘⌫
is its delete to the start of the line (deviations T7).

**The fuller version:** readline's append rule, where consecutive kills
(Ctrl-K, Ctrl-U, the word deletions) join into one kill ring entry, and a
real ring with Option-Y to cycle. *Price:* half a day for the append rule in
both handlers; the ring is a larger design (the macOS text system keeps one
slot, which is what TUI follows today).

### B-TEXT2-2. A bordered container keeps a drag selection begun inside it to its interior

*#10. `.border()`, `Box`, `Card`, `Panel`, `GroupBox`, `Dialog`, `Alert` —
every bordered `ContainerView` around content; not a `List`'s, a `Table`'s
or a menu's own box*

Each bordered box files its interior (inside the border lines, title row and
bottom line excluded) as a selection scope, as `textSelection(_:)` files its
content. The innermost scope under the press is what a selection keeps to,
the existing rule; an interior says nothing about *whether* text selects, so a
box inside `.textSelection(.disabled)` still selects nothing, and a box does
not turn on a list's row text as `.enabled` does. A drag begun on the border
or outside the box crosses it. The Example's Contact card is fixed by this
default: dragging from "Contact" down past the card selects the card's four
interior rows and nothing else (measured in the live Example under a PTY,
before and after). Since A-TEXT2-1's experiment, a drag that goes more than
3 rows or 6 columns outside the interior widens to the scope around the box.

The opt-out is a TUI-only modifier, `.textSelectionScope(_:)` with
`TextSelectionScope.container` (the default) and `.pane`: on the root view it
restores the old reach everywhere, on one box it frees that box, and
`.container` inside puts the rule back. Named for the scope it sets, as the
brief suggested; `.pane` rather than `.page`, since a selection already keeps
to its pane (a scroll view, a split view's column), never to the page.

**Cost, measured 2026-10-24.** As first shipped, each bordered box registered
a hover observer and journalled its scope, which a memoized row replayed every
frame: release A/B against the commit before the lane, warm, `modifiers`
+28.7%, `dashboard` +7.4%, `anyview` +3.8%. Since b8acc3898 the interior is a
region under the reserved `HitTestRegion.HandlerID.selectionInterior`, which
registers and journals nothing (`modifiers` −16.8% against that first form).
What remains is the region itself: a box that carried no regions now makes
every ancestor carry one, measured by switching the interior off — `modifiers`
+6.4% and `dashboard` +3.7% warm for having it, `modifiers` +1.3% cold. Under
the owner's ~10% line and accepted as the cost of the behaviour; making the
interior opt-in would remove it, and is the owner's call.

A list's, a table's and a menu's own box files none
(`ContainerConfig.keepsSelectionInside`): their presses are the control's,
and a list's or table's rows keep a selection to themselves already, so an
interior there would cost a region a frame for nothing — and it came in front
of a table's own region at its header gaps, which a test pins.

**The fuller version:** a scope on any surface that reads as a container
without a border (a `.background` panel, a `GroupBox` styled borderless).
*Price:* a rule for what counts, per view; not attempted.

### B-TEXT2-3. The Example's reorders, deletions and drops are undoable, through a TUI-only helper

*#16. The Lists page's editable list (`onMove`, `onDelete`), the Table page's
reorderable table, the rows that travel between two lists (`onMove`, a drop),
the Mouse page's shelf and basket (three drops) and its filing tag, and the
Focus page's command board (`onDeleteCommand`, `onExitCommand`)*

SwiftUI registers no undo for `onMove`, `onDelete` or a drop: the app owns
the data. Neither does TUI, and neither did the Example, so none of these
could be taken back. Each now registers its inverse with
`@Environment(\.undoManager)`, named "Move", "Delete", "Copy", "Discard" or
"Reset" (seven languages), which Edit ▸ Undo and Redo show. Checked live
under a PTY: two Ctrl-Down moves in the editable list, then two Ctrl-Z, put
the rows back one move at a time, the status bar offering "undo" and then
"redo".

The helper, `UndoManager.registerRestoring(_:to:actionName:)` in
`TUIFoundation/Undo/`, is TUI's own name, documented as such:
Foundation's `registerUndo(withTarget:handler:)` wants a class to call back,
which a `@State` array is not, so the step holds the binding and the old value
in a main-actor class, and its undo registers the redo, keeping the name. Two
values that change together (a row moved between lists) restore through one
binding to both. A drop that changed nothing registers nothing.

**The fuller version:** a diff-based step that undoes only what the change
did (a moved row moved back), so an undo does not also revert other edits
made to the same value since. *Price:* a day — a step per collection
operation (move, remove, insert) with its inverse, for `RangeReplaceableCollection`
and `MutableCollection`; the snapshot is exact for state a person edits a step
at a time, which is every case in the Example.
