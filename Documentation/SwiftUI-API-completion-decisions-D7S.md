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
pops, only while the focus is in the sheet — owner Q6), and so do the
framework's own defaults (a split view's sidebar chord): a modal opened inside
the sheet — an alert — holds the page's defaults as it holds the page's
chords (review of 0b2d764f1).

**The study's rule, and its price:** page registrations eligible only while
no pane is active — a page's app-wide chords dead whenever the reader is in
the sheet. One line in `KeyboardShortcutRegistry.appEntry(for:activePane:)`;
held back because a docked sheet is meant to be a pane BESIDE a live page,
and macOS fires a window's key equivalents from whichever pane has the focus.

### B-D7S-3. A live sheet is a band at every detent, and `.automatic` sizing does not make it a card

*`presentationBackgroundInteraction(.enabled)` with `presentationSizing(_:)`
(decisions A19 owner Q3, A20)*

**Shipped:** a detented sheet whose content enables background interaction
spans the content area — its box takes the whole width, through A20's
`sheetProposedWidth` — at EVERY detent, including the ones past
`upThrough` where it is a modal again, so it does not narrow at the
threshold. A sizing the content names sizes it as it sizes any sheet
(`.fitted`: a card centred where the band would be, as the owner's Q3 answer
says); `.automatic`, named explicitly, is treated as naming none — it is the
sizing every sheet has, and "the band" is what a live sheet's automatic size
is. A detented sheet that does not let the page through keeps its content's
width, as before.

**The alternative:** a band only while docked, the content's width while a
modal — a sheet that jumps narrower as the reader grows it past
`upThrough`. Free to switch (`isBand(sizing:hasDetent:)` reads the dock
decision instead of the trait).

### B-D7S-4. A live sheet presented from inside a modal presentation is a modal

*`presentationBackgroundInteraction(.enabled)` on a sheet presented from a
modal sheet, a full-screen cover or a popover (decisions A19, design C; review
of 0b2d764f1)*

**Shipped:** such a sheet is a modal over the presentation it was presented
from, whatever its background interaction says: it takes the focus and the
input, Tab stays inside it, and Escape closes it and gives the focus back to
the presentation under it. Docked, it reflowed the dimmed page under both
(which nobody could use), and the presentation around it — which re-activates
its own section every frame and holds the input grab — took the focus back
from it every frame, so nothing in it could be reached from the keyboard. The
presenters of modal sheets, covers and popovers mark their content
(`EnvironmentValues.isInModalPresentation`), and `LiveSheet.dock` declines
there.

**The fuller version, and its price:** iOS lets a sheet presented from a sheet
leave the outer sheet live. Here that means the outer presentation becoming
the inner sheet's page: the outer sheet laid out short in the rows above the
inner one (a dock ledger per presentation rather than per content area), the
two sharing the keyboard as panes inside the outer's section — the outer's
per-frame re-activation and its grab made pane-aware — and the modal page under
both staying inert. About two days, with the presented-section and grab
machinery the riskiest part.

### B-D7S-5. A live sheet whose dock pushes its presenting row out of a lazy window comes back as a modal

*`presentationBackgroundInteraction(.enabled)` on a sheet presented from a row
of a `List` or a lazy stack (decisions A19, design C; review of 0b2d764f1)*

**Shipped:** the page under a docked sheet is laid out shorter, and a lazy
container draws only the rows in its window — so a sheet presented from a row
inside the window at the full height and outside it at the docked one took its
own presenter away: undrawn, the sheet went and its dock with it, the page grew
back, the row and the sheet returned, and so on every frame, the app never
idling and the focus lost. Now the frame laid out short that leaves a docked
sheet's presenter out of a lazy container's window is noted
(`FocusManager.presenterWentUndrawnUnderItsDock`), and a presenter drawn again
on the next frame keeps its sheet off the dock for as long as it stays
presented (`PresentationEntry.isKeptOffTheDock`): a modal over the whole page,
which leaves the row where it was. One frame shows the page short with no
sheet; from the next the sheet is a modal and nothing alternates. A presenter
that stays undrawn (another tab, a page navigated away from) is not affected,
and docks again when drawn.

Only a presenter its dock WINDOWED out (follow-up FU3): one that drew nothing
that frame (`StateStorage.isMarkedActive`) under a container that windows its
rows (`StateStorage.retainWindowedSubtree`, declared by the lazy stacks,
`List` and `Table`). The first version held a sheet whose presenter merely
posted nothing, and a presenter drawn into the backdrop of a `.modal`, a
`.contextMenu` or a `.dimmed()` posts nothing, as does one away for a frame
with its tab or navigation destination: a one-frame "Saving…" modal turned
the live sheet into a modal for the rest of its presentation.

And for the whole presentation, an `item:` sheet's switches to other items
included (follow-up FU3): the switch starts the sheet over
(`startOver(forItem:context:)`) but keeps the hold, which is about where the
presenter's row sits. Cleared with the rest, every switch docked the next
item's sheet, the dock took the row away again, and the sheet came back as a
modal two frames later, appearing twice.

**The fuller version, and its price:** keep the row in the window instead —
the page's lazy container told, through the ledger, to scroll so that the
presenting row stays above the dock (as it reveals the focused row), and the
sheet docked. About a day: the container has to know which of its rows
presents, before the walk that lays it out at the docked height, and a row the
reader then scrolls away would still take the sheet with it.
