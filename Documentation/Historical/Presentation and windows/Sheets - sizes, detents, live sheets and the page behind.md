# Sheets: sizes, detents, live sheets and the page behind

*How a sheet came to be sized, resized by detents, docked live beside a page
that keeps working, and how the page behind a modal sheet is drawn and kept
inert. Ids: A19 (the design study, appended), A24, B-D7S-1 to 5, B-D2C-3 to
5, A-MODALS-1, B-MODALS-1 to 4, B-BUGS13-1; DRAWERS (the retired draft,
appended); the modal veil.*

## In short

A sheet sizes to its content up to `.form`'s 25 rows, with no minimum; a
sheet with two or more detents can be resized, and one that enables background
interaction is a live sheet, docked as a pane beside a page that stays live. A
modal sheet's page is drawn behind it, veiled (faded half way toward the
overlay background) since 2026-10-25, and inert to the mouse, focus and the
page's own key handlers, and since 2026-10-27 to the shortcuts and status bar
items declared outside it as well (A-MODALS-1).

## How it unfolded

1. **2026-08-11, a draft** of drawers, sheets and slideover panes (appended).
   On 2026-10-23 the owner retired it (DRAWERS, option 1): inspectors, split
   views and docked live sheets cover its cases.
2. **2026-10-04, the A19 design study** (appended) priced resizable sheets and
   a live page behind them; the owner chose designs A then C, and lane D7S
   built them on 2026-10-06.
3. **2026-10-05, lane D2C** settled sheet sizes (`.form` at 25 rows, no
   minimum, sized sheets' boxes sharing their size).
4. **2026-10-12, A24:** `presentationCornerRadius` decided with O0 and O15.
5. **2026-10-19, lane MODALS** fixed five framework problems lane O10 met in
   sheets, and asked A-MODALS-1. (Lane BUGS13, 2026-10-13, had fixed a
   `@FocusedValue` behind a sheet.)
6. **2026-10-25, the owner:** the page behind a sheet or alert is veiled, not
   flattened (+6.4% on a frame with a sheet open in the notes session).

## Where it stands

Shipped, A-MODALS-1 included (2026-10-27).

## For a future reader

- **The veil is an SGR colour rewrite with a memo**, not the opacity resolver
  (the memory "Modal VEIL"); pictures behind it draw linear-light copies.
- **TUI's own popovers and the dialog builders are still built eagerly**
  (B-MODALS-4).

## The record

### A24. `presentationCornerRadius(_:)` waits on O0/O15

*`View.presentationCornerRadius(_:)`*

A sheet's corner radius. A terminal's corners are box-drawing glyphs, so the
honest reading is a choice of corner — `0` square (`┌`), anything larger
rounded (`╭`), `nil` the appearance's — applied to the sheet's box. But the box
is drawn by the content (a `Dialog`, a `Panel`), not by the presenter, and what
a radius means in cells is the question O0 (shapes) and O15
(`ButtonBorderShape`) are already asking. It should be answered once, there.

**Decided with O0 and O15 (2026-10-12):** square units, and button border
shapes supported, so a radius has a cell reading. Lane owed after those two.

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

Only a presenter its dock WINDOWED out (follow-up FU3): one whose ROW a
container that windows its rows — a lazy stack, a `List`, a `Table` — did not
draw in the walk drawn, the row still among the container's rows
(`StateStorage.wasLeftOutOfAWindow`, from what each such container notes it
drew on a walk a sheet docks, `StateStorage.noteWindowedRows`). The first
version held a sheet whose presenter merely posted nothing, and a presenter
drawn into the backdrop of a `.modal`, a `.contextMenu` or a `.dimmed()`
posts nothing, as does one away for a frame with its tab or navigation
destination: a one-frame "Saving…" modal turned the live sheet into a modal
for the rest of its presentation. The second asked only the presenter's
ancestry — drew nothing that pass, below a container that windows — so one
below a drawn `List` or lazy stack that was away for a frame for another
reason (an `if` switched, a `DisclosureGroup` collapsed and opened again) was
still held; and it asked whether the presenter drew anything all pass, so one
the discarded walk of a `.global` reader's correction drew and the drawn walk
left out read as drawn. The verdict is the frame's last walk's, kept for every
walk of the next frame (`PaneLedger.undrawnUnderTheirDock`). Within a walk it
is the kept drawing's: a scroll view that draws its content again at the
offset the frame settles on (a bottom-glued log re-glued to the tail the dock
moved) puts back the docks and the row notes its first drawing made
(`RenderWalkCheckpoint`), as it puts back the drawing's handler ids — left
in, a presenter the first drawing alone drew read as drawn, and the docked
rows stayed blank, the focus in a sheet nothing showed, until some other
frame.

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

### B-D2C-3. `.form` is 25 rows tall

*`FormPresentationSizing`, `PresentationSizing.form` (decisions A20)*

The owner approved `.form` at `min(64, width)` columns and `.page` at
`min(96, width)` by the content area's height. The form's height was not
named, but `.form` has to propose one — `.automatic` on macOS is
`.form.fitted(horizontal: false, vertical: true)`, which means nothing
unless `.form` has a height to fit away.

**Measured on macOS 15.8** (an offscreen window presenting a sheet of
filling content): `.form` proposes **470 by 400 points**, `.page` **520 by
735**, and a sheet is never smaller than **100 by 80**.

**Shipped:** `.form` proposes `min(25, height)` rows — the measured 400
points over a typical terminal cell of 8 by 16 points, a cell twice as
tall as it is wide. (A points-per-column scale alone does not give it:
470 points into the approved 64 columns is about 7.3 points a column, and
400 points at that scale would be some 54 rows. With the cell's 2:1
aspect, the same 7.3 points a column makes 400 points about 27 rows;
the 8-by-16 cell makes 470 points about 59 columns, which the owner's 64
rounds up.)

**The alternative:** `.form` proposes its width only and fits the height.
A one-line change.

### B-D2C-4. No minimum sheet size

*`PresentationSizing` (decisions A20)*

macOS never makes a sheet smaller than 100 by 80 points (measured, above),
about 14 columns by 5 rows. A TUI sheet has always been exactly its
content, and a sized one keeps that: a fitted axis is as small as the
content is.

**The alternative:** impose 14 by 5 on every sheet. Ten minutes, and a
drawing change for every small sheet that exists today; not recommended.

### B-D2C-5. A sized sheet's boxes share its size in a stack, and size to content in a scroll view — nowhere else

*`PresentationSizing`, `PresentationDetent` (decisions A20)*

A sheet's size — a detent's height, a sizing's width and height — goes to
its box (`EnvironmentValues.sheetDetentHeight`, `sheetProposedWidth`), and a
box clears it for what is inside it. Boxes stacked in a `VStack` or side by
side in an `HStack` take it flexibly and share it. A `ScrollView` clears it
as a box does, so the boxes in one are their content's size, as SwiftUI's are
(measured on macOS 15.6: two `GroupBox`es in a `ScrollView` in a `.form`
sheet 400 points tall are 43 points each — as they are in a `VStack`, where
TUI's share the sheet because a terminal sheet has no material and its
box is what shows the size). Every other container passes the size on to
each box below, and each takes all of it: a `ZStack`'s boxes overlap at the
sheet's size, which is what a sheet of layers wants; a `Grid`'s first box
takes the sheet and the cells after it are not drawn; a lazy stack's first box
takes it and the rest are not drawn; a lazy grid's rows each take it, so the
sheet scrolls through boxes the sheet's height each.

**The fuller version.** The grid, the lazy stacks and the lazy grids clear
the size for their children as a scroll view does, so their boxes are their
content's size, as SwiftUI's are. A lazy stack's every walk takes its rows'
context from one of two helpers (its pinned-section scope), and a grid has
two entry points; a lazy grid's paths are still to be traced. An hour or two
with the tests, and a drawing change only for sheets that hold such a
container.

**Shipped 2026-10-18 (lane LAYOUT): the fuller version.** A `Grid` clears the
size on both axes at both its entry points, and a lazy stack along its own
axis in the two helpers every lazy walk takes its rows' context from, so the
boxes in either are their content's size, and a box in a lazy column still
spans the sheet's width, as one in a vertical scroll view does
(`SheetSizeContainerTests`). A lazy grid needed nothing: run on the base, its
boxes were their content's size already, which the test now guards. A
`ZStack` passes the size on, as before.

### A-MODALS-1. Keys declared outside a modal sheet still work behind it

*`sheet`, `fullScreenCover`, `modal`, `alert` and `confirmationDialog`, and
what a page declares around the view presenting one*

A modal presentation makes the page behind it inert on four channels
(memory: modal input channels). The mouse is inert across the whole screen,
because the dimmed backdrop drops every hit region. Focus is held by the
modal's section, which Tab cannot leave. `onKeyEvent` handlers are silenced
across the whole tree by `grabInput`. The page drawn beneath the sheet is
isolated (`isolatedForBackground()`), so its own status bar items and
`.keyboardShortcut`s neither show nor fire.

Two channels are inert only inside the view that presents the sheet. Status
bar items and keyboard shortcuts declared *outside* that view stay live:

- **Status bar items.** The modal's section merges with the items declared
  outside it (`StatusBarState.resolvedSectionItems`, `.merge`). A page's
  `.statusBarItems { n new }` wrapped around the view that presents a sheet
  still shows "n new" over the sheet, and `n` still runs it. This was decided
  on 2026-08-22: "what is left to merge with is whatever the app declares
  outside the presented subtree, which is live and should show"
  (`ModalPresentationModifier.takeKeyboard`). M1 closed it for Escape alone:
  the sheet's Escape item now always shadows the page's "⎋ back".
- **`.keyboardShortcut`.** With no live sheet docked, every shortcut
  registered outside the presenting view is in the page's table, and it
  fires behind a modal sheet (`KeyboardShortcutRegistry.paneScoped`: with no
  active pane it reads `page[trigger]`). `reachesPage` gates only a pane's
  fall-through.

A scratch probe through the input-chain harness confirmed both (session
notes, `MODALS/ZZScratchOutsideKeysTests.swift`). Over a presented sheet the
bar read "⎋ dismiss", "n new" and "q quit". `n` ran the page's item, and ⌃K
fired the shortcut of a button beside the view presenting the sheet. It was
not run in a live app.

**Options.**
1. **Leave it** (shipped): Escape is the presentation's, and every other key
   declared outside the presenting view stays live and shown.
2. **Silence status bar items behind a modal.** While a modal section holds
   the focus (`activeSectionIsModal`), the bar shows and runs only that
   section's items and the system items (quit). An app item the app wants
   over its sheets is declared in the sheet. About two hours with tests. It
   reverses the 2026-08-22 note above.
3. **Option 2, plus shortcuts.** While a modal section holds the focus, only
   shortcuts registered inside it fire. The registry records each
   registration's section, as it already records its pane. The menu bar's
   commands stay app-wide. About half a day.

**Recommendation:** 3. The dimmed backdrop already says that the whole
screen behind a modal sheet is inert. Three channels of five already behave
that way, and a key that works behind the dimming contradicts the picture.

**Answered 2026-10-27: 3**, after a check against macOS 15.8.1 (a probe app,
`Tools/SwiftUIProbes/Modal sheet keys/`): behind a window-modal sheet the
window's own key equivalents and its menu commands do nothing; behind an
app-modal alert nothing does, every menu item disabled. Built: a keyboard
shortcut records the focus section it was declared in
(`KeyboardShortcutRegistry.Scope`), and while a modal section holds the
keyboard (`FocusManager.activeModalSectionID`) only the modal's own fire, its
framework defaults included; the status bar shows and fires only the modal's
own items, and the system items (`StatusBarState.resolvedUserItems`). The menu
bar's commands were already inert under a modal (drawn as a backdrop, they
register nothing), so TUI treats every modal as macOS treats an app-modal
alert: an app-level command that macOS would still run behind a sheet does not
run here (`ModalInertKeysTests`).

### B-MODALS-1. A dismissed sheet posts a dock resolver on every frame

*`sheet(isPresented:)`, `fullScreenCover(isPresented:)`, `modal(isPresented:)`*

A live sheet (`presentationBackgroundInteraction(.enabled)`) docks at the
bottom of the content area. The root lays the page out above it before the
walk, using the resolvers the sheets posted the frame before. A sheet the app
presents between two frames must therefore have posted one while it was
dismissed, or its first frame draws it over the page's bottom rows. A test
pins this (`LiveSheetLayoutTests.appDrivenOpenIsNotLate`). A dismissed sheet
used to learn whether it could be live by reading its content's trait, which
meant building its content on every frame.

**Shipped:** every dismissed sheet posts a resolver every frame: one closure
and one dictionary entry keyed by its section's name. The root asks it twice
a frame, before the walk and after it, and each time it reads the sheet's
binding once. Only if the sheet has been presented by then does it build the
content, and the presenter's records of a presentation with it. It replaces
building the content and reading two traits every frame. The sheet's posts
are forgotten when the run loop ends (B-MODALS-3). Two presenters post
nothing while dismissed, because they could never dock from it: an `item:`
sheet, whose content is made from no item (B-MODALS-2), and a closed
popover's sheet form, whose binding holds the form read while the popover
was closed (`ModalPresentationModifier.postsDockWhileDismissed`).
**A/B** (`Stress --scenario sheetrows`, da6ac224e against 05e0d085f, and the
head of the lane against both; ran 2026-10-16): the lazy content −4.5% (CI −5.6
to −4.0), the lane's head against the commit before the lazy content −4.8%.

**Fuller version, if the A/B says the post costs more than the build saved:**
key the posts by the presenter's identity, not by its section's name, which
is rendered from the identity's path on every frame, dismissed or not. Or
post only from presenters that have been presented live before, and let a
first live presentation dock a frame late. That is the `item:` forms'
behaviour today (B-MODALS-2), and it regresses the pinned test. About two
hours either way.

### B-MODALS-2. An `item:` live sheet presented between frames still docks a frame late

*`sheet(item:)`, `fullScreenCover(item:)`*

An `item:` sheet's content is built from the item read when its presenter
was built, together with the identity key. That item is none while the sheet
is dismissed. So the dismissed resolver has nothing to build, and the first
frame of an `item:` live sheet still draws it over the page's bottom rows
and settles on the next frame, as before.

**Fuller version:** have the resolver read the item binding when the root
asks, and derive the key from that same read, so that the first frame docks.
About two hours, with the key's "same read as the content" contract moved
into the resolver.

### B-MODALS-3. The last frame's dock resolvers are forgotten when the run loop ends

*`RenderLoop.deinit`, `FocusManager.forgetPresentationDocks()`*

A resolver holds its presentation's binding and the closure that builds its
content. Either may reach the environment, and the environment holds the
focus manager the resolver is posted to. The Settings scene's binding holds
the app's scene presenter, for one. Each frame's posts replace the last's,
but the last frame's stayed after the loop ended. They held the app's focus
manager, state storage, render cache and status bar
(`ScenesLifetimeTests.scenesFreed` caught it once every dismissed sheet
posted). The loop now forgets them when it goes.

A focus manager that no run loop owns had no such end, and nothing replaced
its posts either, because no root read them. The windowed stack's
focus-reach probe draws each row it asks under a scratch manager of its own,
and every probed row that held a sheet left its manager alive, every frame.
A snapshot (`renderOnce`) of a view holding a sheet kept its whole render, and
so did a test host per test. A manager now takes docks only once a root has
asked it for them, before its first walk, and never while it is a backdrop's
(`FocusManager.takesPresentationDocks`). In an app only the run loop's
manager takes them, and the loop's end forgets what it holds.

A presented live sheet's resolver has always kept its presenter's whole
environment. It needs that environment for custom detents, which may read
any value in it. While the sheet is presented, that resolver and the focus
manager hold each other until the next frame replaces it.

**Fuller version:** keep the docks somewhere the environment cannot reach.
The ledger lives in the focus manager, which every environment holds; it
would move to an object only the run loop holds, with the root reading it
through a weak reference. About a day, in the A19 machinery.

### B-MODALS-4. TUI's own popovers and the dialog builders are still built eagerly

*`alert`, `confirmationDialog`, and the popovers TUI draws for its own
controls*

The sheet's and the popover's content closures now run only while presented.
Some builders still run on every frame while dismissed:

- `alert`'s and `confirmationDialog`'s `actions` and `message` builders.
- The values TUI's own popovers are made from: the compact date picker's
  calendar, a link's destination, a tab's popovers, the toolbar's
  customization panel.

These are a handful of buttons or one small view, with no app closure whose
side effects could run early.

**Fuller version:** the same closure in each presenter, called once the
dialog or popover is presented. About three hours with tests, for little
measured benefit. It would need an A/B on a page of many date pickers to
justify it.

### B-BUGS13-1. A `@FocusedValue` drawn as a backdrop reads the values for the live focus

*`@FocusedValue`, `@FocusedBinding`; the page beneath a sheet, an alert or a
context menu, a `.dimmed()` view, a covered navigation page*

A view drawn as a backdrop renders under a throwaway focus manager that
focuses nothing (`RenderContext.isolatedForBackground()`), which shares the
live manager's focused values. Its own `@FocusedValue` read them at the
throwaway's focus, so it was handed the scene values alone, while the end of
the pass repeated every reading at the live focus. With a focused value on the
live focus's path (the sheet's focused control publishing one), every pass
found the backdrop's reading stale and asked for another frame: the app never
idled while the sheet was up (measured headless before the fix: a frame asked
for on every frame).

The page beneath a sheet has to read one of two things, and the choice is
what it shows:

1. **The values for the live focus (shipped).** A reader on the page shows
   what a reader on the live page shows: while a sheet is up, whatever the
   sheet's focus path publishes, and the scene values. The registry knows the
   manager that made it, and a reading follows that manager's focus, which is
   the focus the end of the pass repeats it at, so the two cannot disagree
   (`FocusedValueRegistry.owner`, `tableAtTheFocus()`). It is also what a class
   property's `@FocusedValue` already read behind a sheet: it never takes a
   backdrop's manager (75c2c226c), so the two spellings of one reader now agree.
2. **The scene values alone, as if nothing were focused.** The page would show
   what it shows with the focus nowhere; the end-of-pass check would have to
   repeat each reading at the focus it was made for. A reader that showed the
   selected note beside a list would show "nothing selected" behind every
   sheet, since the list is not on the sheet's focus path either way, and the
   two spellings of one reader would disagree.

SwiftUI is unmeasured here: on macOS a sheet is a window of its own, and
which window's focus a view in the window beneath it reads was not probed.

**Fuller version and price.** A backdrop that shows the page as it was when
the sheet came up, its readers frozen at that frame's values: a snapshot of
the registry's reading per presentation, kept while it is up and dropped with
it. About half a day with tests; it would make the page beneath a sheet
honest about being a picture, but it is a different contract from SwiftUI's
live window beneath, whichever focus that window reads.

## Appendix: the live sheets design study, A19 (2026-10-04)

> **Historical (moved 2026-10-12).** The design study behind decisions A19,
> written before anything was built; it no longer describes the code.
> **Decided since.** The owner answered its questions on 2026-10-04 and
> 2026-10-05: the page **reflows** above a docked live sheet, so nothing
> focusable sits hidden beneath it ("a mapping of these live sheets to
> vertical split views"), and the sheet is a full-width band. Lane D7S built
> designs A then C (2026-10-06, from 55e40a24f), with the calls it made on the
> way, among them a grabber that is a rule of its own rather than a stamp on
> the content's border, in `SwiftUI-API-completion-decisions-D7S.md`. Design B
> was not built. The A19 entry left the decisions doc when it shipped.

Design study, 2026-10-04, read against `main` at `f56c419d0`. Read-only: nothing
here was built, run or measured. Every cost below is an estimate; every
performance figure is a prediction for the A/B in §9 to confirm or refute.

### 0. Summary

The owner wants the iOS bottom sheet: a grabber on top that the reader pulls
between detents, drawn over the page, with the page still usable. That is three
separable changes, and the third is the one the decisions entry did not price:

1. **Detents become reachable.** A grabber (keyboard and pointer), the wheel
   under `.resizes`, `presentationDragIndicator(_:)`. Small and self-contained.
2. **A presentation that does not own the keyboard.** Today a presented sheet
   performs four isolation acts plus an input grab. A live sheet must stop all
   of them and then share three channels the framework assumes are global:
   `.keyboardShortcut` (last registration wins), the Escape claim (one per
   frame), and section activation (re-asserted every frame).
3. **Geometry.** Where the sheet sits and what becomes of the page rows under
   it. If the page stays full height under the sheet (iOS), Tab and the arrow
   keys can put the focus on a control the sheet hides, and no existing
   mechanism prevents it. If the page reflows into the rows above the sheet
   (the owner's "almost like a split view"), nothing is ever hidden, but the
   page's height now depends on a presentation declared inside the tree. That
   is the circularity the chrome rule forbids, unless the height is known
   before the walk.

**Recommendation.** Build **Design A** first: grabber, drag indicator,
`.resizes`, page still inert. It is useful on its own and every other design
needs it. Then build **Design C**: a live sheet docks to the bottom of the
content area and the page is laid out in the rows above it. The dock height is
resolved before the walk from a per-frame ledger of presenter-posted resolvers,
so there is no discarded pass. I do not recommend Design B (an overlay over a
full-height live page). Its occluded-focus problem has no general fix. About
2 days for A and 2.5–3 more for C, tests and docs included. The coordinator's
2–3 days for option 3 did not include the geometry work or the shortcut-scoping
work.

---

### 1. The problem in TUI's terms

**What a sheet is today.** `.sheet(isPresented:)` forwards to `.modal`
(`View+Presentation.swift:395`, `:329`), which builds a
`ModalPresentationModifier`. That modifier always builds its content eagerly,
via `content()` at `:336`. While presented, the modifier does five things:

| # | What it does | Where |
|---|---|---|
| 1 | Registers a per-instance section `modal-<path>`, activates it as a *presented* section **every frame**, marks it modal | `ModalPresentationModifier.swift:97`, `:152`, `:157`, `:160` |
| 2 | Grabs the keyboard for that section | `:164` → `KeyEventDispatcher.grabInput` (`KeyEvent.swift:109`) |
| 3 | Renders the page it wraps through `isolatedForBackground()`: throwaway focus manager, key dispatcher, shortcut registry and status bar | `:237-238`; `RenderContext+TUIContext.swift:117`, `:146` |
| 4 | Drops the page's hit regions (and, for a cover, its runs) | `:252`, `:264-266` |
| 5 | Emits the sheet as a `.modal`, `centered: true`, `dimsBackground: true` overlay; the root compositor dims the whole base first | `:317-320`; `FrameBuffer+Overlays.swift:70-86` → `dimmedAsBackdrop` (`DimmedModifier.swift:167`) |

**What a detent is today.** A height and nothing else. `presentationDetents`
wraps the content in `_PresentationDetentsView` (`PresentationDetent.swift:238`).
The presenter reads it by a static trait walk before rendering
(`presentationTrait`, `PresentationTraits.swift:40`). The height then reaches
the content's outermost box through `EnvironmentValues.sheetDetentHeight`
(`PresentationDetent.swift:230`), which `ContainerViewCore` consumes in both
measure and render (`ContainerViewCore.swift:124`, `:279`). Without a
`selection:` binding the smallest detent applies (`resolvedHeight`, `:189`), so
every extra detent is unreachable. `Drawers-sheets-and-slideovers.md` §1 calls
this "a parity shim, not a feature".

**What is left out.** `presentationDragIndicator(_:)`,
`PresentationContentInteraction.resizes`, `PresentationBackgroundInteraction.enabled`
and `.enabled(upThrough:)` all fail to compile. The shipped `.automatic`,
`.disabled` and `.scrolls` modifiers return `self` (`PresentationInteraction.swift:83`, `:98`).

**What the owner asked for.** A bottom sheet with a top grabber that resizes it.
It draws over the page without necessarily blocking the page — "almost like a
split view".

---

### 2. What SwiftUI specifies

From the macOS SDK's symbol graph (the scratchpad copy; `sdoc.py`'s cache
`plan/sdoc.pickle` is an empty pickle and returns nothing, see §10). The doc
comments are paraphrased here, not quoted.

| Symbol | Availability | What the doc comment says |
|---|---|---|
| `View.presentationDragIndicator(_ visibility: Visibility) -> some View` | macOS 13, iOS 16 | Sets the visibility of the drag indicator on top of a sheet. Show it when it is not obvious that the sheet can resize, or when the sheet cannot be dismissed interactively. The example uses `[.medium, .large]` with `.visible`. |
| `PresentationContentInteraction.resizes` | macOS 13.3, iOS 16.4 | A swipe resizes the presentation before it scrolls the content. |
| `View.presentationContentInteraction(_:)` | same | By **default**, swiping up on a scroll view in a resizable presentation grows it to the next detent. The scroll view only scrolls once the presentation is at its largest. `.scrolls` reverses that: scroll first, and resize only when the scroll view hits its end. The drag indicator always resizes. |
| `PresentationBackgroundInteraction.enabled` | macOS 13.3, iOS 16.4 | People can interact with the view behind the presentation. |
| `PresentationBackgroundInteraction.enabled(upThrough detent: PresentationDetent)` | same | Interaction up through that detent. At larger detents it is disabled. The example uses `[.height(120), .medium, .large]` with `upThrough: .height(120)`. |
| `View.presentationBackgroundInteraction(_:)` | same | Many platforms disable the view behind a sheet; this modifier enables it. |

**Type shapes already match.** `PresentationBackgroundInteraction` is not
`Equatable` in SwiftUI, and `PresentationContentInteraction` is. TUI's types
match (`PresentationInteraction.swift:32`, `:56`), so adding cases is purely
additive. `Visibility` exists (`ListRowSeparatorModifier.swift:34`).

**What follows from the doc comments.** On iOS, `.automatic` content
interaction behaves like `.resizes`. TUI documents `.automatic` as "its
content scrolls" (`PresentationInteraction.swift:63`). That is owner question
Q5.

**Unmeasured iOS behaviour.** The following is from general knowledge, not
measured, and the design should treat it as hypothesis:

- `.automatic` drag-indicator visibility shows the indicator when there is
  more than one detent.
- At an enabled detent the dimming goes. A tap on the page reaches the page
  and does not dismiss the sheet.
- Tapping the grabber (the accessibility activation) cycles the detents.
- User drags write the `selection:` binding.
- A drag snaps to the nearest detent on release.

**macOS.** Sheets are window-modal there, so these APIs are probably inert. The
decisions entry says this was not measurable with an offscreen hosting view.

---

### 3. The machinery today

#### 3.1 Presentation hosting and the backdrop

- **Root-hosted overlays.** A presenter emits an `OverlayLayer` and `RenderLoop`
  composites it (`RenderLoop.swift:585` → `compositingOverlays`,
  `FrameBuffer+Overlays.swift:28`). There is one queue, sorted by
  `OverlayLevel` (`OverlayLayer.swift:21`: popover < modal < alert <
  notification) and then by `zIndex`. A centred layer's offset is a
  post-centre drag delta, clamped on screen (`OverlayLayer.swift:326-331`).
  `isScreenLevel` reads `centered` (`:157`), and `.hidden()`, `.opacity()`,
  `.allowsHitTesting(false)`, ScrollView culling and the app header's lift all
  turn on it.
- **The backdrop's cost per frame.** For each presented sheet,
  `isolatedForBackground()` allocates a throwaway `FocusManager`,
  `KeyEventDispatcher`, `KeyboardShortcutRegistry` and `StatusBarState`. The
  page subtree is memoised under a separate backdrop slot when it has
  registrations (`RenderCache.swift:802`, `EffectScope` in
  `RenderCacheKeys.swift:26`), so live and backdrop pictures never serve each
  other. The compositor then re-spells every line of the expanded base through
  `dimmedAsBackdrop` every frame. I found nothing that caches that. A live
  page skips all of it: no throwaways, the live memo slot, no dim pass.
  **A live page should cost about what the same page costs with no sheet up,
  which is less than today's dimmed backdrop.** The coordinator's
  "live (not frozen) backdrop render each frame" is not a new cost: the
  backdrop is already rendered every frame.
- **Popovers already render the page live.** `PopoverPresentationModifier`
  renders its content without isolation (`:150`), grabs the keyboard, and
  takes the mouse with a screen-covering dismiss region
  (`DropdownMenu.attachDismissBackdrop`, `DropdownMenuRenderer.swift:309`;
  `holdsInput: true`, `:246`). This is the existing precedent for a live page
  under a surface, and for a region that blocks what is beneath it.
- **Inspector is a precedent for "a panel beside a live page".** `_InspectorModifier`
  (`Inspector.swift:80`) is pure composition: `HSplitView { content; inspector }`
  (`:93`). The vertical twin `VSplitView` exists (`SplitView.swift:48`).

#### 3.2 Focus sections, Tab and Escape

- **Section membership.** A control with no enclosing section registers in the
  stable default section, never in the active one (`Focus.swift:445-455`). A
  live page's controls therefore land in the page's own sections even while
  the sheet's section is active. The comment in `isolatedForBackground()`
  (`RenderContext+TUIContext.swift:69-76`) describes the older fallback and is
  stale on this point.
- **Sections are rebuilt every walk, in registration order.**
  `beginSceneRender` clears them (`Focus.swift` near `:1358`). A presenter's
  section therefore sits wherever the presenter is in the tree.
- **Tab.** `focusNext()` (`Focus.swift:872`) crosses sections at a boundary
  unless the active section is modal, in which case it wraps inside it.
  `cycleSection` (`:1527`) enters a section at its edge
  (`focus-section-cycling-boundary`). A live sheet section that is not marked
  modal joins the ring with no new code.
- **Re-activation every frame.** `activatePresentedSection` (`FocusManagerPresentedSection.swift:67`)
  is called on every presented frame and takes the active section back from
  anything that is not a surface presented on top. For a live sheet this
  would pull the focus back from the page on the next frame. The doc comment
  there explains why a "first presented frame" flag is unreliable. Its case:
  a presenter that rendered into an alert's throwaway backdrop manager the
  frame before.
- **Dismissal.** `deactivateSection` (`Focus.swift:1252`) reverts to the
  section the sheet was activated over and restores its remembered focus. It
  runs only if the sheet's section is active, which is the behaviour a live
  sheet needs.
- **Clicking a page control** activates that control's section
  (`focus(id:)`, `Focus.swift:692-701`).
- **Escape today** reaches a sheet two ways. One is a section status item at
  layer 1 (`:194-203`). The other is a layer-2 handler registered with
  `sectionID` (`:212-218`), added because a pushed `NavigationStack`'s Escape
  claim hid the status item. Without a grab, `KeyEventDispatcher.dispatch`
  (`KeyEvent.swift:197`) asks **every** handler in reverse registration order,
  regardless of focus. A live sheet's Escape handler would therefore fire with
  the focus on the page unless it checks the active section itself.
- **The Escape claim is frame-global.** `StatusBarState.escapeLabelOverride`
  (`StatusBarState.swift:226`) is set by `NavigationStack` (`NavigationStack.swift:435-443`),
  drop-downs and lists. `InputHandler` pre-routes a claimed Escape through the
  focus system (`InputHandler.swift:149`), and the status bar skips every
  Escape item while a claim stands. A `NavigationStack` inside a live sheet
  would therefore claim Escape for the page as well.
- **Keyboard shortcuts are last-wins and focus-blind.**
  `KeyboardShortcutRegistry.register` (`KeyboardShortcutRegistry.swift:55`)
  stores one action per trigger, and the last registration wins, "which
  render order makes the topmost surface". With two live panes, the sheet's
  `.defaultAction` would fire on a Return that a page control let fall
  through, and the page's `.cancelAction` would be shadowed by the sheet's.
  This is the one channel the modal case solved by throwing the page's
  registry away (`modal-input-channels`) and the live case cannot.
- **Status-bar items** registered inside the sheet are section items
  (`StatusBarItemsModifier.swift:121`), so they show only while the sheet's
  section is active. The page's global items stay live, which is correct for
  a live page.
- **Chrome keys.** `t` and `a` are grounded only while a modal section is active
  (`InputHandler.swift:257`). The header is clickable only while no modal
  section is active (`RenderLoop.swift:603`). Both behave correctly for a live
  sheet once its section is not marked modal.

#### 3.3 Mouse and hit testing

- Dispatch is innermost-first, meaning last-registered first
  (`MouseEventDispatcher.swift:895`). A declined event falls through to the
  next region (`:770`). A region that wants to block what is beneath it
  consumes the event.
- Compositing an overlay **appends** its regions after the base's and does not
  punch the base's regions (`FrameBuffer.swift:846-848`). Runs and opacity
  regions are punched. Over a live page, a click on a blank cell of the sheet
  would therefore reach the page control under it unless the sheet carries a
  blocking region.
- `DialogDrag` (`DialogDrag.swift:25`) makes a centred sheet movable by its
  title row and border. The grab regions are prepended so content controls win
  (`:93`). On a resizable sheet the top row has to mean resize instead.
- ScrollView's wheel handler returns `false` when it cannot move
  (`ScrollView.swift:886-930`, "no-op-not-consumed"). That makes both wheel
  orders cheap to build:
  - `.resizes`: a resize region appended above the content takes the wheel
    first and declines at the extreme detent.
  - `.scrolls`: a resize region prepended under the content gets the wheel
    only once the scroll view is at its end.

#### 3.4 Resize precedents

| Precedent | What it gives |
|---|---|
| `_SplitPaneDividerHandler` (`SplitView.swift:73`), `dividerBuffer` (`:243`) | A focus stop via `FocusRegistration.persistFocusID` / `register` (`FocusRegistration.swift:54`, `:120`). Up/Down move it, Shift for five. A press focuses it and a drag moves it relative to the press. |
| `_UserResizableCore` | `GripGlyphs.standingOut(from:)` (`_UserResizableCore.swift:146`): a handle drawn in whichever Box Drawing weight stands out from the border cell it lands on. `drawGrip`, `mark` and `drawEdgeGrips` (`:474`, `:538`, `:563`) handle the resting, hovered and focused tints. All of it is `private`. Uses negative `StateIndex` values (`:101`). |
| `Drawers-sheets-and-slideovers.md` §3–§5 | Already recommends: a sheet with more than one detent draws a grabber on its top border; a drag snaps to detents; the keys move between detents, not cells; the grabber matches `.userResizable`'s handle. |

#### 3.5 Root geometry and the chrome rule

`RenderLoop.renderContent` (`RenderLoop.swift:694`) lays the scene out at the
content-area height and publishes `overlayContentHeight` (`:757`). If the app
header's height turns out wrong after the walk, it re-renders. That correction
is the **only** source of discarded passes
(`Discarded render passes and redundant frames.md` §1), and its effect leak is
pinned as a known issue. The owner's rule
(`chrome-height-must-not-need-content`) is that nothing whose height displaces
the content may be discoverable only by walking the tree. A docked sheet is
exactly that kind of thing, unless its height is known before the walk.

**A precedent for presenter-posted closures read on the next frame.**
`FocusManager.notePresentation` and `closeUndrawnPresentation`
(`FocusManagerPresentedSection.swift:95`, `:102`) keep
`presentationDismissals` and `previousPresentationDismissals`, rotated in
`beginRenderPass`. Design C's dock ledger has the same shape.

---

### 4. What terminals pass through — the key bindings

From `Terminal-compatibility.md` and the memory notes:

| Candidate | Verdict | Why |
|---|---|---|
| Ctrl-↑/↓ (the entry's suggestion) | **reject** | Apple Terminal strips **every** modifier from Up and Down (compat doc, Apple Terminal "Input behaviour", and "Shift on a printable key…", last paragraph). macOS Mission Control also takes ⌃↑/⌃↓ system-wide (memory `row-shortcut-table`; **not yet in the compat doc** — add it). |
| Shift-↑/↓, ⌥-↑/↓ | reject | Same stripping in Apple Terminal. |
| Ctrl+letter | avoid | A C0 byte, and the letters are spoken for: Emacs chords, ⌘ shortcuts under `.commandKey(.control)`, and Ctrl-H/I/J/M/[ cannot arrive (compat doc "Control collides with the C0 range"). |
| Bare ↑/↓ on a **focused grabber** | **adopt** | Passes everywhere. It is the split divider's binding (`SplitView.swift:91`), so a reader who has used a split view already knows it. |
| Home / End on the grabber | adopt as secondary | `.userResizable` already binds them. Whether **bare** Home/End/PgUp/PgDn reach the app in Apple Terminal is not recorded in the compat doc. Its default profile may keep them for scrollback. This needs a measurement before the docs promise it (§9, step 3). |
| Return / Space on the grabber | adopt | Cycles to the next detent, like the iOS grabber's activation (hypothesis, §2). |
| Escape | the focused pane's | §7 and Q6. |
| Tab / Shift-Tab | unchanged | Section cycling crosses page ↔ sheet. |
| F6 ("next pane") | not now | Nothing in TUI binds it. Tab already does the job. Revisit if readers ask. |

Mouse: drag the sheet's top border row (the whole row is the target and the
drawn handle is short, as with `.userResizable`). A press focuses the grabber.
The wheel follows `.resizes` / `.scrolls`, rate-limited to one detent per
250 ms (15 frames at 60 Hz, per the animation-timing rule) so that one
trackpad burst does not sweep every detent.

---

### 5. Three designs

Every design includes A's grabber. They differ in what happens behind the sheet.

#### Design A — detents made real, the page stays inert (the entry's option 2)

**Mechanics.**

- **Detent state.** `ModalPresentationModifier` keeps the chosen detent in its
  own `StateStorage` box (`StateIndex.detentState = 2`; positive indices are
  fine, because content renders at child identities, `:108`, `:287-289`). The
  grabber writes through `selection:` when there is one. `resolvedHeight`
  (`PresentationDetent.swift:189`) gains a "state" argument and a sorted,
  de-duplicated list of distinct resolved heights to step through. Two detents
  that floor to the same height on a short terminal are one stop.
- **Placement.** A detented sheet anchors to the bottom of the content area
  (Q2). This needs no `OverlayLayer` change. A centred layer's offset is a
  post-centre delta clamped to `maxHeight - height` (`OverlayLayer.swift:330`),
  so emitting `offsetY: overlayHeight` lands the sheet flush on the bottom edge.
  `isScreenLevel` stays true, so ScrollView culling, `.hidden()` and the header
  lift all keep working. Name it (`OverlayLayer.dockedAtBottom(…)`) and say in
  the comment what it is not: a new placement mode. `DialogDrag` is skipped for
  docked sheets, as it is for covers (`:307-311`).
- **The grabber.** It is stamped onto the top border row when the content's
  top row is a border cell. It reads the cell, as `.userResizable` does, using
  `GripGlyphs.standingOut` extracted to a shared `BorderGrip` (step 1). If the
  content has no box (a bare `Text`), the presenter prepends a one-row rule
  carrying the handle, and the detent height includes that row. The chrome's
  height is fixed at 0 or 1 and known before the content renders.
- **Focus stop.** A `_SheetGrabberHandler: PersistedFocusable` registered
  through `FocusRegistration` with focus ID `sheet-grabber-<identity path>`.
  It registers **after** the content, so the content gets the opening focus,
  and it is a stop only when there is more than one distinct detent.
  Keys: ↑ next larger, ↓ next smaller, Home/End to the extremes, Return/Space
  cycle, Escape left to the sheet.
- **Drag.** A press on the top row focuses the grabber. Drag events move the
  height (free or snapping, per Q4), and the release snaps to the nearest
  detent.
- **`presentationDragIndicator(_:)`.** A trait wrapper like
  `_PresentationDetentsView`, read by `presentationTrait`. `.automatic` means
  visible when there is more than one detent. `.hidden` removes the handle,
  the drag and the focus stop together (the no-mouse-only rule: a keyboard
  route or neither).
- **`.resizes`.** Another trait. It installs the wheel-resize region above the
  content. `.scrolls` installs it beneath (scroll first, then resize at the
  end), which matches SwiftUI's own text. Neither acts without a visible
  grabber, again for the keyboard-route rule.

**Costs.**

- **Work:** about 2 days with tests and docs.
- **Hot path:** none on frames without a detented sheet. With one up: one
  focusable, one or two regions and a few stamped cells per frame. No
  `RenderContext` field, and no new environment key.
- **Measure/render parity:** a non-detent height during a free drag goes
  through `sheetDetentHeight`, the same path both passes already read. The
  prepended rule is the presenter's own and nothing measures it from outside.
- **Memo:** the presenter already declares a render side effect (`:150`). A
  height change misses the content's memo through `contextHeight`.
- **Focus and input:** the sheet still owns the keyboard. The only new thing
  is one stop in its ring.

**What it makes possible.** Detents mean something. `presentationDragIndicator`
and `.resizes` compile and behave. The Example's "stand-in for dragging a
sheet's grabber" Picker (`OverlaysPage.swift:307-313`) can go. `.enabled` and
`.enabled(upThrough:)` still fail to compile.

#### Design B — an overlay over a full-height live page (iOS read literally)

**Mechanics** (A, plus the following):

- While live, the presenter performs none of acts 2–5 in §1. It renders the
  page with `contentContext`, keeps the page's regions and runs, does not grab
  input or mark the section modal, and does not dim.
- The section is activated **only on entry**, using a state bit that is set
  only when it rendered against a real manager (`!focusManager.isBackdrop`).
  This answers the hazard `activatePresentedSection` documents.
- The sheet is emitted at `level: .popover, zIndex: -0.5`. That puts it above
  displaced drawing (`displacedDrawingZIndex = -1`, `OverlayLayer.swift:95`)
  and below the page's own drop-downs, menus and tooltips, which must draw over
  it. It switches back to `.modal` and dims above the `upThrough` detent.
- A blocking region covers the sheet's whole rectangle and is prepended inside
  the sheet. The sheet's own controls win, and nothing reaches the page through
  its blank cells.
- **Occlusion.** The page keeps its full height, so its bottom rows sit under
  the sheet. Tab can land on a control there. The page's `ScrollView`s reveal
  the focus inside their own viewport, which runs under the sheet. A `List`'s
  cursor walks into the hidden rows on ↓. The only fix I can see for Tab is a
  geometry-aware skip:
  - after compositing, `RenderLoop` intersects the final regions that carry a
    `focusID` with the sheet's rectangle;
  - it tells `FocusManager` which IDs are fully covered;
  - traversal skips them on the next key.
  Nothing equivalent exists for the cursor inside a list or table, and every
  windowing container would have to learn an "obscured band".

**Costs.**

- **Work:** A plus about 2 days. That is A + live branch (1 d) +
  shortcut/Escape scoping (0.5 d) + occlusion skip (0.5–0.75 d). The occlusion
  skip is new machinery with a known hole.
- **Hot path:** while live, about the same as a page with no sheet (no dim, no
  throwaways), plus one region scan per frame for the occlusion set. Zero when
  no live sheet is up.
- **Parity:** the page's geometry is unchanged; that is the point of B.
- **Memo:** crossing the threshold flips the page between live and backdrop
  `EffectScope`, which already uses separate slots.
- **Focus:** the hole described above. Arrow navigation inside a page
  container can disappear under the sheet.

**What it makes possible.** iOS fidelity: `GeometryReader` in the page sees the
whole height, as on iOS. Modeless **centred** dialogs (`.enabled` on an
undetented sheet, a Find panel) would come almost free.

#### Design C — a docked sheet; the page reflows into the rows above it (recommended)

**Mechanics** (A, plus B's live branch, minus the occlusion skip):

- **The dock ledger.** It sits beside `presentationDismissals` in
  `FocusManagerPresentedSection.swift`, with the same current/previous rotation
  in `beginRenderPass` and no new environment key:
  - every sheet presenter whose content carries a background-interaction trait
    posts `notePresentationDock(id:resolver:)` every frame, **dismissed or
    presented**;
  - `resolver: (contentHeight) -> Int?` reads the binding, the detent state or
    selection and the `upThrough` detent, and answers the dock height, or `nil`
    when the sheet is not docked live;
  - the `isPresented:` forms build their content eagerly (`View+Presentation.swift:336`),
    so the trait is readable on the dismissed path;
  - `sheet(item:)`'s content is `nil` while dismissed, so its traits are
    unknown until it opens.
- **The root.** `RenderLoop.renderContent` asks last frame's resolvers once,
  before laying out (`:745-767`, where the root `RenderContext` is built). The scene is laid out at
  `contentHeight - dock`, while `overlayContentHeight` stays `contentHeight`.
  The sheet is the bottom-docked layer from A, filling exactly the rows the
  page gave up. There is one walk and the height is known in advance. This is
  how C honours the chrome rule.
- **When the dock is learnt late.** That happens on a presenter's first drawn
  frame, a `sheet(item:)` opening, or two live sheets at once. That frame is
  drawn as B would draw it, a docked overlay over the full-height page, and it
  asks for another frame. It settles one frame later, not as a discarded pass.
- **Writing the ledger immediately.** The grabber's keys, drag and dismiss
  routes, all owned by the presenter, write the new height straight into the
  ledger. Reader-driven changes are therefore never late.
- **Docking conditions.** The sheet docks only when it is live *and* leaves the
  page at least **3** rows (one bordered row). Otherwise it is today's modal
  overlay over a full-height, dimmed, inert page. On a short terminal the
  feature therefore degrades to today's sheet, which is A18's "documented
  run-time capability check" for icing.
- **Crossing `upThrough`.** The sheet stops docking and goes modal. That costs
  one relayout, on a deliberate user action.
- **Hit testing.** No page row lies under a docked sheet, so the page's regions
  and the sheet's never overlap. Keep B's blocking region anyway, for the
  late-learnt frame.
- **Z-order** as in B: `.popover` at −0.5 while live, so a page drop-down that
  opens downward draws over the sheet.
- **Undetented sheets** with `.enabled` stay centred modal dialogs. Their
  height would need the content walked, and both platforms agree: on an iPhone
  an undetented sheet is `.large` and covers the page, and on a Mac it is
  window-modal. The behaviour is documented.

**Costs.**

- **Work:** A plus about 2.5–3 days: ledger and root (0.5 d), live branch
  (1 d), shortcut and Escape-claim scoping (0.5 d), full-width box if Q3 says
  so (0.5 d, shared with A20), Stress session (0.5 d).
- **Hot path:** on frames with no live-capable presenter, one empty-dictionary
  check per frame. While docked, the page costs what it costs at that height
  with no sheet, minus the dim pass.
- **Hot path, new per-frame work:** a trait walk on each **dismissed** sheet
  presenter (a few `as?` casts). This matters for row-hosted sheets (one
  presenter per drawn row). A/B it on `notes` and `inbox-sheet`. If it shows
  up, register only while presented and accept the one-frame settle on
  app-driven opens.
- **Transitions:** opening, closing and each detent change relayout the page
  once, the same order of work as a terminal resize. A mouse drag that snaps
  while dragging (Q4) bounds this to one relayout per detent crossed. Free
  dragging would relayout per drag event.
- **Measure/render parity:** the dock shrinks the root's single
  `RenderContext`, which measure and render share, so there is no fork.
  `GeometryReader`, `containerRelativeFrame` and lazy windows see the shorter
  height. This **deviates from iOS** and has to be written into
  `SwiftUI-compatibility.md`.
- **Memo:** the page's entries at the new height miss once (`contextHeight` is
  in the key). The live/backdrop `EffectScope` slots cover crossing the
  threshold. The ledger is outside the walk and touches no memo.
- **Focus and input:** nothing can be hidden, so a `ScrollView`'s or `List`'s
  own reveal is correct by construction. The same three shared channels as B
  still need scoping (step 7).
- **Lifecycle:** a lazy page's rows `onDisappear` and `onAppear` as the dock
  changes the page height. iOS does not do that. Document it as "the page is
  resized, as by a terminal resize".

**What it makes possible.** The owner's split-view reading: a list above and a
sheet below, both driven by the keyboard, with the cursor never under the
sheet. The ledger and the docked layer are also the machinery a later
`.drawer`/slideover (`Drawers-sheets-and-slideovers.md` §4) would need.

#### Comparison

| | A | B | C |
|---|---|---|---|
| Work (with tests, docs) | ~2 d | A + ~2 d | A + ~2.5–3 d |
| `.enabled` / `upThrough` compile | no | yes | yes |
| Focus ever on a hidden control | n/a | **yes** (Tab is patched; list and table cursors are not) | no |
| Page geometry | full, dimmed | full (iOS) | shortened (deviation) |
| Relayout on detent change | no | no | yes, once per change |
| Discarded pass | no | no | no (one-frame settle when learnt late) |
| New shared-channel scoping | no | yes | yes |
| Per-frame cost while up | today's | ≤ today's | ≤ today's |

---

### 6. Recommendation

**A now, then C.**

A is worth shipping on its own: `presentationDetents` stops being a parity shim
and two of the four symbols compile honestly.

Choose C over B because the defect B cannot close, the focus walking under the
sheet inside a list, is exactly the kind of bug this project's ledgers are full
of, while C's deviation (the page is shorter) is visible, explainable and
consistent with how a terminal resize already behaves.

C keeps the chrome rule by resolving the dock before the walk. It does not
start a second source of discarded passes.

---

### 7. Decided here (minor; per "decide minor questions myself")

- **Pane ownership of Escape.** When the focus is in the sheet, Escape
  dismisses it. When the focus is on the page, Escape is the page's (for
  example `NavigationStack` back).
  - The layer-2 handler at `:212` gets a guard,
    `focusManager?.activeSectionIdentifier == sectionID`.
  - The status item is a section item already.
  - Q6 asks only whether an Escape that the page does not use should fall
    through to closing the sheet.
- **Escape claims become section-scoped.** A claim made while rendering inside
  a section that is not active does not count: `escapeLabelOverride` records
  the claiming section, and `InputHandler.swift:149` and the status bar honour
  it only when that section is active. Without this, a `NavigationStack` in a
  live sheet takes the page's Escape.
- **`.keyboardShortcut` becomes pane-scoped.**
  - Each app registration records the section it rendered in
    (`activeFocusSectionID`).
  - A section the presenter marks as a pane (`markSectionPane(id:)`, cleared
    per pass like `modalSectionIDs`) has its registrations eligible only while
    that pane is active.
  - Registrations outside any pane are eligible only while no pane is active.
  - Within the eligible set, last-wins is unchanged.
  - The memo's effect replay already compares the section
    (`EffectScope.section`), so served registrations land in the right pane.
- **Ring order.** The sheet's section goes last in the Tab ring. The presenter
  registers it after rendering the page it wraps. A sibling section rendered
  later still follows it, which is acceptable because the ring is a cycle;
  `markSectionPane` can move panes to the end at `endRenderPass` if a test
  shows it reads badly.
- **Entering the sheet.** Presenting moves the focus into the sheet, as every
  sheet does today. Growing past `upThrough` moves it in as well, because the
  sheet now owns the keyboard. Shrinking back leaves it where it is.
- **Short terminals.**
  - A docked sheet is at least 3 rows; the page must keep at least 3 rows, or
    the sheet goes modal.
  - Distinct detent heights only.
  - `upThrough` is compared by **resolved height**, as SwiftUI words it ("at
    detents larger than…").
  - A custom detent that resolves to `nil` as the `upThrough` disables
    background interaction.
- **Popover and cover.** `.enabled` and `presentationDragIndicator` are
  documented no-ops there. A cover has nothing behind it, and a popover is
  already a live page with an outside-click dismiss. They have to compile,
  because the type is shared with sheets. This is A18's documented-capability
  route.
- **Wheel resize rate.** One detent per 250 ms.

---

### 8. Questions only the owner can answer

1. **Page behind a live sheet:** reflow into the rows above it (C, split-like,
   recommended) or stay full height under it (B, iOS-literal)?
2. **Detented sheets anchor to the bottom edge** (all of them, as on iOS,
   recommended), or stay centred unless live?
3. **A docked sheet's width:** full width (recommended; needs A20's width twin
   of `sheetDetentHeight`), or a centred card in a full-width band?
4. **Mouse drag on the grabber:** snap between detents while dragging
   (recommended for C, at most one relayout per detent) or move freely and
   snap on release (iOS)?
5. **`.automatic` content interaction:** keep "the wheel scrolls"
   (recommended), or follow iOS, where the wheel grows the sheet first?
6. **Escape with the focus on the page behind a live sheet:** page only
   (recommended), or close the sheet when the page does not use it?

---

### 9. Staged plan (one commit per step)

For every step: `swift build` clean with zero warnings, the 6.2.4 suite
(`swift test --skip-build -q`), and `Stress --selfcheck` for every drawing
change (gate policy). A/B runs on a quiet box only. Agents do not benchmark,
so the steps name the scenarios for the owner or coordinator to run with
`ab_bench.py`. Documentation changes go in the same commit as the behaviour.

**1. Extract the grip (pure refactor).**
- Move `GripGlyphs`, `drawGrip`, `mark` and `drawEdgeGrips`' handle arithmetic
  from `_UserResizableCore.swift` (`:118-146`, `:474-598`) into a shared
  `BorderGrip.swift`.
- Tests: `UserResizableTests`, `ResizeGripAlphaTests` and the golden snapshots
  must be unchanged.
- A/B: none (no behaviour change; `--selfcheck` only).

**2. Detent state and bottom docking** (A; needs Q2).
- `ModalPresentationModifier`: `StateIndex.detentState`, distinct-height
  stepping, selection write-through. Detented sheets are emitted docked at the
  bottom (the named clamp idiom) and `DialogDrag` is skipped for them.
  `PresentationDetent.swift` docs drop "a terminal has no grabber".
- Tests:
  - placement at the bottom edge across the ten attachment points (extend
    `ModalAttachmentMatrixTests`);
  - colliding detents on a 10-row terminal;
  - the selection binding written;
  - dismiss and re-present restores the bound or smallest detent;
  - `PresentationVariantsTests` stays green.
- A/B: `session/notes`, `session/inbox-sheet`.

**3. Grabber and `presentationDragIndicator(_:)`** (A).
- Trait wrapper, stamp or prepend, `_SheetGrabberHandler`, keys, press/drag/release.
- Tests:
  - the focus ring order (content, then grabber);
  - ↑/↓/Home/End/Return through `InputChainHarness`;
  - a drag snapping to the nearest detent (render twice through one context,
    as the `DialogDrag` test does);
  - `.hidden` removes stop, drag and glyph together;
  - a single detent gives no stop;
  - `interactiveDismissDisabled` leaves Escape on the grabber inert;
  - focus colours via the existing `.userResizable` tint vocabulary.
- **Terminal:** measure bare Home/End/PgUp/PgDn in Apple Terminal, iTerm2,
  Ghostty and Warp (a `stty raw -echo; od -c` reading, or a new
  `Tools/TerminalProbes/key_probe.py`). Record the result and the Mission
  Control ⌃↑/⌃↓ fact in `Terminal-compatibility.md`, and note that the sheet
  grabber uses `.userResizable`'s handle weights in the chrome glyph table.
- Update `Drawers-sheets-and-slideovers.md` §4c to *shipped*.
- A/B: `session/notes`, `session/inbox-sheet`.

**4. `.resizes` and `.scrolls`' resize-at-the-end** (A).
- Trait wrapper. A wheel-resize region appended (`.resizes`) or prepended
  (`.scrolls`) in the sheet buffer, rate-limited. Replace the two "nothing
  resizes" doc comments in `PresentationInteraction.swift`.
- Tests:
  - the wheel over a tall sheet's scroll view grows it first under `.resizes`
    and scrolls first under `.scrolls`;
  - `.automatic` scrolls only (or per Q5);
  - a burst of eight wheel events moves one detent.
- A/B: none needed (only active over a detented sheet).

*A ships here. Decisions doc A19: mark option 2 shipped, and update the
SwiftUI-compatibility rows (`:128`, `:1073`).*

**5. The dock ledger and the root** (C; infrastructure only).
- `notePresentationDock(id:resolver:)` and rotation in `FocusManager`.
  `RenderLoop.renderContent` subtracts the dock from the scene's height, not
  from `overlayContentHeight`.
- Tests: through `HeadlessApp`, with a test-only resolver.
  - the scene is laid out at `contentHeight - dock`;
  - an overlay still clamps to the full content area;
  - a resolver not posted this frame is dropped next frame;
  - the late-learnt path asks for exactly one more frame.
- A/B: `anyview`, `modifiers`, `deep`, `menus`, `kitchensink` (the empty-ledger
  check must be noise). Not `megalist`, whose A/B verdicts are unresolvable.

**6. Pane-scoped shortcuts and Escape claims** (C; no new public API).
- `KeyboardShortcutRegistry` entries carry their section. `markSectionPane`.
  Section-tagged `escapeLabelOverride`.
- Tests:
  - two panes with a `.defaultAction` each: Return fires the focused pane's
    only;
  - a `NavigationStack` claim in an inactive section leaves the page's Escape
    alone;
  - every existing `ModalEscapeRouteTests`, `NavigationStackPresentedEscapeTests`
    and `TextInputShortcutPrecedenceTests` case is unchanged when there are no
    panes.
- A/B: `modifiers`, `kitchensink`, `menus`, `session/notes` (every
  `.keyboardShortcut` registration pays the tag).

**7. The live page: `.enabled` and `.enabled(upThrough:)`** (C).
- The presenter's live branch:
  - no isolation, grab, modal mark or dim;
  - activation on entry only;
  - the guarded Escape handler;
  - `.popover` at −0.5;
  - the blocking region;
  - posting its resolver;
  - modal above `upThrough` or when the page would keep fewer than 3 rows.
- Rewrite `PresentationInteractionTests.backgroundIsInert` to keep `.disabled`
  and add its `.enabled` twin.
- Tests:
  - Tab crosses page ↔ sheet and the focus stays put for several frames (the
    `activatePresentedSection` trap);
  - a click on a page control works and one on a blank sheet cell does not
    reach the page;
  - `a` and `t` are live;
  - the header is clickable;
  - growing past `upThrough` dims, takes the focus and grabs; shrinking frees
    it;
  - dismissing with the focus on the page leaves it there;
  - an alert from inside a live sheet still grabs and then reverts to the
    sheet;
  - a page `Picker` drop-down draws over the sheet and owns the keyboard;
  - `ModalFocusRestorationTests`, `ModalInputGrabTests` and
    `NestedPresentationFocusTests` stay green for non-live sheets.
- `TUIKIT_VERIFY_RENDER_MEMO=1` and `TUIKIT_VERIFY_MEASURE_MEMO=1` on the new
  session (step 9).
- A/B: `session/inbox-sheet` before vs after (unchanged), then the new
  session's cost against `session/inbox` (expected: about equal).

**8. Full-width docked box** (if Q3 says full width; shared with A20).
- A `sheetDetentWidth` twin consumed where `sheetDetentHeight` is
  (`ContainerViewCore.swift:124`, `:279`, `ContainerView.swift:465`).
- Tests: `DialogPreferredWidthTests`-style width for `Dialog`, `Panel`, `Card`
  and `.border()`, and a bare `Text` sheet.
- A/B: `framedcolumns`, `kitchensink`.

**9. Example, docs and a Stress session.**
- **Example.** On `OverlaysPage`, replace the stand-in Picker with
  `.presentationDragIndicator(.visible)` and add a live sheet over the page's
  list with `.enabled(upThrough: .medium)`. New strings go into all seven
  languages (the localization parity guard).
- **Docs.** `Presentation.md` (the "Sheet heights: detents" section gains
  grabber, keys, live page and the reflow deviation). `SwiftUI-compatibility.md`
  rows. Decisions A19 marked decided.
- **Stress.** Add a new `InboxVariant.docked` (`inbox-docked`). The inbox goes
  under a live sheet at `.medium` with `[.height(8), .medium, .large]` and
  `upThrough: .medium`. The script plays the inbox steps on the page and, every
  N steps, Tab into the sheet, grabber ↑/↓ (crossing the threshold), Escape and
  reopen. Checks:
  - the page's cursor row is never in the dock rows;
  - exactly one pane shows focus;
  - above the threshold the page is dimmed and a page key does nothing.
  Run it with `--verify` and both memo verifiers.

Totals: A ≈ 2 d (steps 1–4). C ≈ 2.5–3 d more (steps 5–9, step 8 conditional).

---

### 10. Risks and loose ends

- **The `activatePresentedSection` trap is the likeliest regression.** A live
  sheet that keeps re-activating its section yanks the focus back from the page
  every frame. Step 7's multi-frame test is the guard.
- **Late-learnt dock frames.** `sheet(item:)` opens and first-drawn presenters
  show one frame of overlay before the reflow. If the owner finds that visible,
  the alternative is the header's correction re-render, which would be a second
  discarded-pass source. I would not take it.
- **The dismissed-presenter trait walk** (step 5 A/B). It is the only new
  per-frame cost that scales with presenters rather than with live sheets.
- **Focus-blind layer-2 handlers** (`onKeyEvent`) in either pane still hear the
  other pane's keys. That is today's rule for a page with two
  `.focusSection()`s. Document it, don't fix it here.
- **Lazy rows' lifecycle** fires as the dock changes the page height (C). It
  is documented, not prevented.
- **`sdoc.py` returns nothing.** `plan/sdoc.pickle` is 5 bytes (an empty dict),
  and `plan/../parity/work/swiftui/` does not exist; the symbol graphs are in a
  session scratchpad. Delete the pickle and point `SP` at a durable copy, or
  the next study will quote SwiftUI from memory.
- **Stale comment.** The doc comment on `isolatedForBackground()`
  (`RenderContext+TUIContext.swift:69-76`) still says a background control
  "would resolve to `activeSectionID`". `FocusManager.register` has filed
  section-less controls in the default section since the split-view fix
  (`Focus.swift:446-455`). Worth correcting in step 7, which edits the
  presenter beside it.
- **Section-item replacement** (seen in passing, not verified):
  `registerSectionItems` replaces a section's items wholesale
  (`StatusBarState.swift:501-508`). A sheet whose content declares
  `.statusBarItems` may therefore replace the presenter's "⎋ dismiss" item.
  This happens today, independent of A19. Check it when writing step 7's
  status-bar test.


## Appendix: drawers, sheets and slideover panes, the retired draft (2026-08-11)

> **Historical (moved 2026-10-23).** A design draft, written on 2026-08-11 and
> never built beyond its §4c. **Retired by the owner on 2026-10-23**
> (DRAWERS, option 1): no drawer and no slideover will be built, because the
> shipped APIs cover the cases it was written for. It no longer describes the
> code.
>
> | The draft's case | Covered by |
> |---|---|
> | A trailing pane the reader can resize and hide (§4a, `.drawer(edge: .trailing)`) | `.inspector(isPresented:content:)`, a resizable trailing column with a focusable divider and a hide button (`Inspector.swift`) |
> | A leading pane | `NavigationSplitView`'s sidebar (its divider resizes it from the keys and the pointer) |
> | A top or bottom pane | `VSplitView`; a bottom pane that is a sheet is a detented live sheet, docked like a `VSplitView` (A19, [Live sheets design study](<Sheets - sizes, detents, live sheets and the page behind.md>)) |
> | Resizing a sheet between detents (§4c, §3, §5, Q3, Q5, Q6) | **Shipped** (A19, 2026-10-06): the grabber on the sheet's top edge, a focus stop moved by the keys and the pointer, snapping as it moves |
> | The slideover's header row (§4b) | Not needed: window chrome is opt-in (A28), so the one visible difference between a page-anchored and a screen-anchored pane is mostly gone |
> | The size as an app-visible binding (Q4) | Not built; `presentationDetents(_:selection:)` binds a sheet's detent |
>
> Questions 1, 2 and 4 of §8 are closed by the retirement. The text below is
> as it stood.

The draft exists because `.presentationDetents` shipped with a hole in it, and
closing that hole properly means deciding what a "sheet that can be resized"
*is* in a terminal — which is a design question, not an implementation detail.

---

### 1. The hole

`.presentationDetents([.medium, .large])` compiles, measures and renders. It
also does nothing a user can reach. From `PresentationDetent.swift`:

> A terminal has no drag-grabber to move between them, so the binding is how a
> multi-detent sheet changes size.

SwiftUI's detents are a *gesture* feature. The API names the rest stops; the
user drags between them, and the sheet snaps. Take the gesture away and what
remains is `.presentationDetents([.medium])` — a verbose way of writing "this
sheet is half height". Every additional detent in the set is unreachable unless
the app also binds `selection:` and builds its own control, at which point the
detent set is doing no work the app is not already doing.

So the honest reading of the current state: **detents are a parity shim, not a
feature.** They keep SwiftUI code compiling. They do not give a TUI user
anything.

Two ways out, and they are not exclusive:

- **(A)** Give the terminal the gesture — a grabber the mouse can drag and the
  keyboard can drive. Detents become real.
- **(B)** Recognise that a resizable panel anchored to an edge is a *different
  control* from a modal sheet, name it, and build it deliberately.

The owner's framing — "this sounds like a drawer (in old Mac OS X parlance)" —
is (B), and it is the more interesting half. (A) is worth having anyway, and
falls out of (B)'s machinery.

---

### 2. Three things, currently conflated

| | Modal? | Anchored to | Resizable | Dismissed by |
|---|---|---|---|---|
| **Sheet** | yes — dims, traps focus | centred | no (fixed detent) | Escape, or its own button |
| **Drawer** | **no** | one edge of a parent view | yes, by its grabber | closing it; content keeps working |
| **Slideover** | no | one edge of the SCREEN | yes | closing it |

They differ on the axis that actually matters in a terminal: **does the rest of
the app keep working while it is open?** A sheet says no — it dims what is
behind it and takes the focus ring. A drawer says yes: it is a second pane, and
Tab moves between them.

That distinction is already load-bearing elsewhere. `NavigationSplitView` is
"two panes, both live"; a modal is "one pane, everything else inert". A drawer
is the first with a resize affordance and an open/closed state.

Which suggests the cheapest honest answer to "what is a drawer": **a
NavigationSplitView column that can be collapsed and dragged**, not a sheet that
can be resized. The framework already has resizable split panes with keyboard
and mouse handles (task #317). The question is whether a drawer should reuse
that or be its own thing.

**Recommendation: reuse it.** A drawer is a split-view column with

1. an open/closed binding,
2. an edge (leading / trailing / top / bottom),
3. a size the user can change and the app can persist.

Everything else — the divider, the drag handle, keyboard resize, size-to-fit —
already exists and is already tested. Building a parallel implementation would
be the "reinventing the wheel" smell the project's rules call out.

---

### 3. The grabber

The owner's suggestion: *"we can have a grabber at the top border of the
sheet"*. Yes — and the machinery is already written.

`DialogDrag` makes a presented dialog draggable by its title row and border. It
registers a mouse handler, appends grab regions to the buffer's hit-test
regions, and keeps a persisted `(x, y)` the compositor applies as a post-centre
delta. A grabber is the same shape with the delta applied to **height** instead
of position, and the grab region limited to one edge.

So the work is: generalise `DialogDrag` into a "grab this edge and give me a
delta" helper, and let both the drag-to-move and drag-to-resize cases use it.

**That question was answered elsewhere, and answered differently.**
`.userResizable(_:)` shipped on 2026-08-21 (`7aba17dd`; the design record is
`Documentation/Layout and scrolling/Resizable views.md`) with its own core rather than a generalised
`DialogDrag`. `_UserResizableCore` marks a stretch of the bottom and right
borders as draggable, keeps the size the user chose in `StateStorage` under the
view's render identity, and resizes from the keyboard by one cell (Shift for
five), Home/End to the bounds, Escape back to the size the layout wanted. That
is §5's table for every row but the last, arrived at independently — §5 spends
Escape on closing the drawer, and a resizable view has nothing to close.
`DialogDrag` is untouched and still dialog-only, so "generalise it" is now a
choice between a *third* implementation and sitting a drawer's grabber on
`_UserResizableCore`'s. Sit on it.

#### What it looks like

The border already draws. A grabber marks a stretch of it as grabbable:

```
╭──────────────── ▁▁▁▁▁▁ ────────────────╮     ← grabbable stretch, centred
│                                        │
```

Candidate glyphs, in the project's usual order of preference (see
`Terminal compatibility survey.md` on chrome repertoires — anything chosen here needs
measuring on Apple Terminal, iTerm2, Ghostty and Warp before it ships):

| Glyph | Reads as | Risk |
|---|---|---|
| `▁▁▁▁` U+2581 | a lip to pull | fine everywhere; low contrast on some fonts |
| `═══` U+2550 | a doubled rule | reads as decoration, not a control |
| `⣿⣿` U+28FF | a knurled grip | Braille — the `.dots` spinner's coverage problem |
| `───` (plain) | nothing | invisible affordance |

`▁▁▁▁` is the recommendation. It differs from the border it sits in, it is
BMP-old, and it does not depend on Braille or emoji coverage.

What `.userResizable(_:)` shipped with is not `▁▁▁▁`, and is not a fixed glyph:
the handle is drawn in whichever Box Drawing weight stands out from the border
cell it lands on — doubled (`═` `║` `╝`) over a single-line or heavy border,
heavy (`━` `┃` `┛`) over a double one — because that modifier wraps a border it
did not draw and has only the drawn result to read. The stretch is 7 cells along
a bottom edge and 3 rows along a side, shrunk to fit a small view. A drawer's
grabber should match it rather than reopen this table.

**A grabber must not be the only affordance.** The framework's own rule (from
the iTerm2 right-click work) is that mouse-only features need a keyboard route.
See §5.

#### Where it lives

On the drawer's edge nearest the content it resizes: bottom drawer → top
border; trailing drawer → leading border. That is the edge that moves.

---

### 4. Proposed API

#### 4a. Drawer (TUI-specific, no SwiftUI equivalent)

```swift
ContentView()
    .drawer(isPresented: $showingInspector, edge: .trailing) {
        InspectorPane()
    }
```

with modifiers on the content, following the modifier-first principle:

```swift
    .drawerWidth(30)                    // initial; user-resizable from there
    .drawerWidthRange(20...60)          // resize limits
    .drawerResizable(false)             // fixed; no grabber drawn
```

Open questions on this shape:

- **Should the size be a binding?** `.drawer(isPresented:edge:size:content:)`
  with `size: Binding<Int>?` would let an app persist the user's drag across
  launches (`@AppStorage`). Without it the drawer forgets on every relaunch,
  which for an inspector pane is annoying. **Recommend: yes, optional binding**,
  same shape as `presentationDetents(_:selection:)`.
- **Does a drawer take focus when it opens?** macOS drawers did not. Tab-into
  seems right; auto-focus does not. Matches how `NavigationSplitView` behaves.
- **What happens at a terminal size where the drawer will not fit?** Proposal:
  it clamps to the range's minimum, and below THAT it refuses to open and the
  binding snaps back to `false`, so an app can notice. Silently opening a
  1-cell drawer is worse than not opening.

#### 4b. Slideover (TUI-specific)

Same as a drawer but anchored to the screen rather than to a view — so it needs
the root-hosted overlay path modals already use (`OverlayLayer`, per
`modal-presentation-is-page-hosted`), not the parent's layout.

```swift
    .slideover(isPresented: $showingHelp, edge: .trailing) { HelpPane() }
```

**Question for the owner: is this worth having separately at all?** The visible
difference between "anchored to the page" and "anchored to the screen" is one
row of app header. If the answer is "not worth it", drop it and keep drawers.

#### 4c. Sheet detents (SwiftUI parity, made real)

Keep the SwiftUI API exactly as it is and give it the gesture:

```swift
.sheet(isPresented: $showing) {
    Detail().presentationDetents([.medium, .large], selection: $detent)
}
```

- A sheet with **more than one** detent draws a grabber on its top border.
- Dragging it resizes; on release it **snaps to the nearest detent**, as
  SwiftUI does.
- `selection:` stays authoritative — dragging writes through it when bound, so
  an app observing the binding sees the user's choice.
- A sheet with **one** detent draws no grabber. Nothing to move to.

This is pure parity work: no new API, and the existing detent set finally means
something.

**Shipped 2026-10-06 (A19, design study §9 step 3), differently in one
respect.** The grabber is not stamped onto the sheet's top border: it is a rule
of its own across the sheet's top edge — a `VSplitView` divider (`DividerRule`,
`DividerDrag`), the owner having framed a docked sheet as a split view, page
above, sheet below — with `.userResizable`'s handle (`BorderGrip`) in its
middle. One row, always, and known before the content renders, so the detent
includes it; a titled border has nothing written over its title; and box-less
content gets the same grabber as a `Dialog`. Detented sheets rest on the bottom
edge. The grabber is a focus stop after the sheet's controls (↑ ↓ to the next
detent, Home End to the ends, Return Space round them); a drag snaps between
detents AS IT MOVES (owner Q4) rather than on release; `selection:` is written
through. `presentationDragIndicator(.hidden)` removes the rule, the stop and
the drag together.

---

### 5. Keyboard

Every mouse route here needs a keyboard equivalent, and the keys are nearly
spoken for.

When the drawer (or its grabber) holds focus:

| Key | Does |
|---|---|
| ← / → (or ↑ / ↓, by edge) | resize by one cell |
| Shift + those | resize by five (`shiftStepMultiplier`, as sliders and steppers already do) |
| Home / End | minimum / maximum of the range |
| Escape | close the drawer |

For a **detented sheet**, arrows should move between *detents*, not by cells —
the detents are the rest stops, and one-cell nudges would fight the snap.

This wants the grabber to be a focusable element, which raises: **is the
grabber a Tab stop of its own, or does the drawer's own focus handle resize?**
The split-view divider work (#317) already made this choice — dividers are
focusable and resize with arrows. **Recommend matching it**, so a user who has
learned split views already knows drawers.

---

### 6. Mechanics

Grounded in what exists; nothing here needs new infrastructure.

| Need | Existing part |
|---|---|
| Grab region on a border | `_UserResizableCore`'s grabber (shipped 2026-08-21, `7aba17dd`); `DialogDrag.appendGrabRegions` is still dialog-only |
| Persisted drag delta | `DialogDrag`'s `StateBox` + `propertyIndex` pattern |
| Drag reporting | `MouseEventDispatcher.requestFeature(.drag)` |
| Screen-anchored placement | `OverlayLayer.placed(maxWidth:maxHeight:)` |
| Two live panes + divider | `NavigationSplitView` / split-view resize |
| Focus per pane | focus sections (`activeFocusSectionID`) |
| Persisting user size | `@AppStorage` |

Two traps worth naming in advance, both from the bug ledger:

- **Chrome height must not need the content.** A drawer's border and grabber
  have to be sizeable before its content renders, or the render pass is
  discarded (see `chrome-height-must-not-need-content`).
- **Measure must not mutate.** A drag delta is state; reading it during a
  measure pass and writing it back is the measure-side-effect class.
  `DialogDrag` already guards on `!context.isMeasuring` — keep that.

---

### 7. What I recommend building, in order

1. **Detent grabber** (§4c). Smallest, pure parity, makes a shipped API real.
   Proves the grabber glyph and the drag-resize helper.
2. **Drawer** (§4a) on top of the split-view machinery, with a size binding.
3. **Slideover** (§4b) only if §4b's question comes back "yes".

Step 1 is worth doing regardless of what happens to 2 and 3, because right now
`.presentationDetents` is a promise the framework does not keep.

---

### 8. Open questions for the owner

1. **Drawer as split-view column, or its own control?** (§2 — I recommend
   reusing the split view.)
2. **Is a slideover worth having separately from a drawer?** (§4b)
3. **Grabber glyph** — `▁▁▁▁`, or something else? (§3 — largely settled by
   `.userResizable(_:)`, which draws whichever Box Drawing weight stands out
   from the border cell it lands on rather than any fixed glyph.)
4. **Should a drawer's size be an app-visible binding** so it can persist?
   (§4a — I recommend yes.)
5. **Is the grabber its own Tab stop**, matching split-view dividers? (§5)
6. **Should a sheet drag snap to the nearest detent, or move freely** and only
   snap when released near one? SwiftUI snaps; free movement would make the
   detent set advisory. (§4c — I recommend snapping, for parity.)

