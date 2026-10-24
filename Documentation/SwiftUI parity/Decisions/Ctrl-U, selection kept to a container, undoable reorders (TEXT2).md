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
slot, which is what TUIkit follows today).

### B-TEXT2-2. A bordered container keeps a drag selection begun inside it to its interior

*#10. `.border()`, `Box`, `Card`, `Panel`, `GroupBox`, `Dialog`, `Alert`, a
bordered `List` or `Table`, a menu's box — every bordered
`ContainerView`*

Each bordered box files its interior (inside the border lines, title row and
bottom line excluded) as a selection scope, as `textSelection(_:)` files its
content. The innermost scope under the press is what a selection keeps to,
the existing rule; an interior says nothing about *whether* text selects, so a
box inside `.textSelection(.disabled)` still selects nothing, and a box does
not turn on a list's row text as `.enabled` does. A drag begun on the border
or outside the box crosses it. The Example's Contact card is fixed by this
default: dragging from "Contact" down past the card selects the card's four
interior rows and nothing else (measured in the live Example under a PTY,
before and after).

The opt-out is a TUIkit-only modifier, `.textSelectionScope(_:)` with
`TextSelectionScope.container` (the default) and `.pane`: on the root view it
restores the old reach everywhere, on one box it frees that box, and
`.container` inside puts the rule back. Named for the scope it sets, as the
brief suggested; `.pane` rather than `.page`, since a selection already keeps
to its pane (a scroll view, a split view's column), never to the page.

**Cost:** one hover-observer region and one dictionary entry per bordered box
per frame (none under `.pane`, none while measuring), journalled for memo
replay as a `textSelection` scope is. The Stress selfcheck passes (122 cases,
23 sessions). An A/B is owed on the scenarios with the most boxes:
`anyview` (a bordered row per element), `deep` (nested borders),
`modifiers`, `customlayout`, and the `chat`, `glides` and `session/menus`
sessions (menus are bordered containers).

**The fuller version:** a scope on any surface that reads as a container
without a border (a `.background` panel, a `GroupBox` styled borderless).
*Price:* a rule for what counts, per view; not attempted.
