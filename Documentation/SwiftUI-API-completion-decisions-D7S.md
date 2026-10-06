# SwiftUI API completion — lane D7S (live sheets): new judgement calls

*Lane D7S implemented the owner's decision A19 — resizable sheets and a live
page behind them, designs A then C of
`SwiftUI-API-completion-design-A19-sheets.md` (2026-10-06). Each call below
came up on the way. The safe option shipped; the alternative and its price are
given. Numbered as the main decisions document is: A = owner decision, B =
basic shipped, C = declined.*

## B. Shipped the safe option

### B-D7S-1. The grabber is a rule of its own, and a sheet with one detent has none, whatever the indicator says

*`presentationDragIndicator(_:)`, `PresentationDetent` (decisions A19)*

**Shipped:** a sheet with two detents or more (two distinct heights, after a
short terminal floors them) draws its grabber as a ONE-ROW RULE across its top
edge, inside the detent's height — a `VSplitView` divider between the sheet and
the page, with `.userResizable`'s handle in the middle. `.automatic` and
`.visible` both draw it there and only there; `.hidden` takes the rule, the
focus stop and the drag away together.

Two departures from the study, which proposed stamping the handle onto the
content's own top border and prepending a rule only for box-less content:

- **A rule of its own, always.** Whether the content's top row is a border is
  known only after the content has rendered, and the rule's row has to come out
  of the detent BEFORE it does (the detent is the height being rendered into).
  A stamped handle also lands on a titled border's title, and box-less content
  got a different grabber from boxed. The owner's split-view framing settles
  the look: the boundary between page and sheet is a divider, drawn and dragged
  by the split's own code (`DividerRule`, `DividerDrag`). Price of the
  alternative (stamp when the first row is a border, else prepend): about half
  a day, with the content rendered at the full detent and, for box-less
  fillable content, a second render to give the rule its row.
- **`.visible` on a sheet with one detent draws nothing.** iOS draws the
  indicator there, and a drag on it rubber-bands, or swipes the sheet away.
  A terminal sheet has no swipe to dismiss, so a handle on a sheet with one
  height would promise a drag that moves nothing — the rule `.userResizable`
  already keeps (a pinned axis gets no mark). **The alternative:** draw it,
  and make a drag past the smallest detent dismiss the sheet (unless
  `interactiveDismissDisabled`), with ↓ at the smallest as its keyboard route
  — iOS's gesture, about half a day; the keyboard half is the doubtful part,
  since a held ↓ would close the sheet.

### B-D7S-2. A key equivalent the sheet does not bind reaches the page's; Return and Escape do not

*`.keyboardShortcut` behind a live sheet (decisions A19, design C; study §7
"`.keyboardShortcut` becomes pane-scoped")*

**Shipped:** the page and a live sheet docked under it are PANES, and a
shortcut registered in one is that pane's. With the focus in the sheet, the
sheet's shortcuts fire; a key equivalent it does not bind (a ⌃N "new note" on
the page) still reaches the page's, as a key goes up a responder chain — but
Return and Escape, the `.defaultAction` and `.cancelAction` roles, are the
sheet's alone: a field in the sheet that lets Return through must not press
the page's default button, which was the study's motivating defect. With the
focus on the page, only the page's fire; the sheet's never do. Escape claims
follow the same panes (a `NavigationStack` in the sheet claims Escape, and
pops, only while the focus is in the sheet — owner Q6).

**The study's rule, and its price:** page registrations eligible only while
no pane is active — a page's app-wide chords dead whenever the reader is in
the sheet. One line in `KeyboardShortcutRegistry.appEntry(for:activePane:)`;
held back because a docked sheet is meant to be a pane BESIDE a live page,
and macOS fires a window's key equivalents from whichever pane has the focus.
