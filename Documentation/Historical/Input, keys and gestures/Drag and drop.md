# Drag and drop

*How drag and drop came to TUI: item-provider drags kept in the app, drop
badges, table rows dragged, spring loading, the session values, keyboard
drags, and what is still open. Ids: B10, B80, B82, B83, A53, C12,
B-BITEMS1-1, A53-KEYBOARD-DRAG, DEPR-DROPDEST, DRAG-SELECTION.*

## In short

Drags stay inside the app (a terminal has no system pasteboard drag), and
only cancel and forbidden change a drop. Drops wear macOS's badges: + for a
copy, ↗ for a link, ⊘ where forbidden, nothing for a move. A table row with a
payload drags on its own line, drawn selected. A paused drag spring-loads a
control, drawn waiting and firing, after the host's delay where local. The
session values ship; nothing hands them out yet.

## How it unfolded

1. **2026-10-04, A53** (the drag-session behaviour of macOS 26) was pinned.
2. **2026-10-05 to 13, B10:** the badges were decided, the glyphs confirmed by
   the owner on 2026-10-12, and shipped by lane BITEMS1 (B-BITEMS1-1).
3. **B80, B82, B83** shipped table row drags, spring loading and the session
   values; on 2026-10-23 the owner asked spring loading to draw its pending
   state and use the system delay (built 2026-10-24).
4. **2026-10-23 and 26, keyboard drags.** The owner asked to explore a
   keyboard drag mode that limits focus to drop destinations
   (A53-KEYBOARD-DRAG), and on 2026-10-26 ruled: the carry mode, after its
   prerequisite (`.draggable` as a focus stop with Copy and Paste). The same
   day: B-BITEMS1-1's three-party model. Both were built that night, and the
   carry's first part on 2026-10-27 (A53-KEYBOARD-DRAG below).
5. **2026-10-26, found while filming:** a `.draggable` row in a multi-selection
   drags only itself; asked whether it should carry the selection, as AppKit's
   tables do (DRAG-SELECTION, open).

## Where it stands

Shipped as above, and A53's prerequisite (2026-10-26): Copy on a focused
`.draggable` copies its payload, Paste on a focused drop destination drops it
— a stop of the content's own where it has one (a draggable `Button` keeps
its single stop), else one of the modifier's, which publishes `\.isFocused`;
none in a list row (the list is the row's stop) or while disabled
(`TransferKeys`); and B-BITEMS1-1's three-party model the same night:
`dragConfiguration(_:)` states what a source allows (a copy by default, a
row reorder a move), a destination proposes (a delegate its own; else a move
into the container the drag came from — one the source is inside — and a
copy anywhere else), the pointer's one modifier or Option held on the
keyboard flips a copy and a move, and the source's set narrows it: the other
where only that is allowed, `.forbidden` and a refused drop where neither is.
The badge names the result, so a plain `dropDestination` now wears `+`. A
delegate that refuses the drag proposes `.cancel`, unbadged. A53's carry
mode, its first part (2026-10-27): Ctrl-R picks a focused draggable up, Tab
and the arrows carry it among the stops that can take it, Return drops it,
Escape puts it back. Its second part followed the same night: a `‹` cue on
every stop it can reach, Return and Escape named in the status bar, and a
list as one stop whose rows Up and Down move between. **Owed:** "Pick Up" in
a draggable's context menu, which needs a way for a modifier to add a menu
item; the image well's badge probed in a real window.
**Open:** DRAG-SELECTION. DEPR-DROPDEST's line is in the compatibility guide
(the Drag and drop row: SwiftUI's older `dropDestination(for:action:isTargeted:)`,
soft-deprecated, kept while the `isEnabled:` form's `DropSession` waits on
A53).

## The record

### B10. Item-provider drag and drop stays in the app, and only cancel and forbidden change a drop

*`View.onDrag(_:)`, `View.onDrag(_:preview:)`, `View.itemProvider(_:)`, `View.onDrop(of:isTargeted:perform:)`,
`View.onDrop(of:delegate:)`, `DropDelegate`, `DropInfo.hasItemsConforming(to:)`,
`DropInfo.itemProviders(for:)`, `DropOperation` (+ `.Set`), `DropProposal`*

**Shipped:**

- On Apple platforms, the four modifiers and the delegate, riding TUI's
  in-app drag session. An `onDrag` provider, or a `draggable` string or URL
  wrapped as SwiftUI wraps a `Transferable`, lands in an `onDrop` whose types
  it conforms to.
- The delegate is called in SwiftUI's order: validate once, enter, update on
  each move, then exit or perform.
- `DropOperation`, its `Set` and `DropProposal` are values everywhere.

Two things SwiftUI's drop does are not here:

- *The operation's meaning.* A proposal of `.cancel` or `.forbidden` refuses
  the drop, and the drag goes home. `.copy`, `.move`, `.delete` and `.alias`
  all accept it. On macOS they differ in the pointer's badge and in what the
  source application is told. A TUI drag has no badge and never leaves the
  app, so the delegate's `performDrop` is where any difference has to be
  made.
- *`operationOutsideApplication`.* It is recorded and never applies.

`DropOperation.Set`'s raw values are TUI's own: SwiftUI does not document
its own, and it is macOS 26 only, so it could not be probed on this machine.

**The fuller version:** a badge beside the drag preview naming the proposed
operation (`+` for copy, as Finder draws), and a source-side callback when a
drop completes with `.move` or `.delete`. SwiftUI's is `onDragSessionUpdated`,
which the `DragSession*` family rule declines. About half a day for the
badge; the callback belongs with that family's re-examination in Wave 17.

**Decided 2026-10-05; lane owed once the glyphs are confirmed.** You asked on
2026-10-04 for a fleshed-out badge proposal (with ➕ for copy, say). The
2026-10-05 answer, which "Proceed" approved: a one-cell badge at the drag
preview's top-right corner, following the pointer, `+` in the accent colour
for copy, `↗` for link, `⊘` in the error tint for forbidden, and nothing for
move; the drop target's highlight can shift colour to match. It uses
single-width symbols rather than ➕, because emoji widths vary between
terminals and would knock the preview out of line. (A record of 2026-10-11
listed the proposal as still owed; it was not.)

**Owner, 2026-10-12 (second message):** the single-width glyphs are confirmed. Lane owed, with a measured
Terminal compatibility survey.md row for `↗`, which is East Asian Ambiguous.

**To confirm (asked 2026-10-12): the single-width glyphs.** `+` is Narrow and
`⊘` (U+2298) Neutral, one cell everywhere. `↗` (U+2197) is East Asian
Ambiguous, as is `×` (U+00D7), the candidate for `.delete`, so each would need
a measured row in Terminal compatibility survey.md, as the other chrome glyphs have;
Neutral alternatives are `⇗` (U+21D7) or `⤴` (U+2934) for link and `✕`
(U+2715) for delete, whose ink still wants the same measurement. A plain
`onDrop` proposes `.copy`, so `+` shows over most item-provider targets, which
is macOS's look. Work: 1–2 commits, about half a day, plus the glyph
measurements. The source-side callback stays with A53, which is pinned.

**Shipped 2026-10-13 (BITEMS1):** the badge, in the preview's top-right
cell (on the preview rather than beside it, so the picture stays the frame a
`DropInfo` reports; beside a top row of one cell, which it would hide): `+` in the accent colour for `.copy`, `↗` in the accent
for `.alias`, `⊘` in the error colour for `.forbidden`, nothing for `.move`.
`onDrop(of:isTargeted:perform:)` proposes `.copy`; `onDrop(of:delegate:)`
proposes what `dropUpdated` last returned, once `validateDrop` said yes.
`↗` and `⊘` are corpus rows now, measured one cell by `advance_probe.py` on
Apple Terminal, iTerm2, Ghostty, Warp and tmux (Terminal compatibility
survey.md, "The drop-operation badge"; ink unmeasured). Three choices of the
lane's own are in [B-BITEMS1-1](#b-bitems1-1-a-delete-wears-no-badge-and-only-the-item-provider-drops-propose-one):
`.delete` and `.cancel` wear none, TUI's own `dropDestination` and a
list's drops propose nothing, and no destination highlight shifts colour
(TUI draws none for these views; the app's `isTargeted` does).

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
- **TUI's other destinations.** `dropDestination(for:action:isTargeted:)`,
  a `List`'s or `Table`'s insertion and reordering, and a tab's drop zone
  propose no operation, so they wear no badge. SwiftUI documents no operation
  for `dropDestination`; on macOS it is believed to draw `+` (unmeasured).
  **The fuller version:** `dropDestination` proposes `.copy` and a reorder
  `.move` (which wears nothing anyway): one line in `DropDestinationModifier`,
  plus a decision on whether a TUI-only API should look like macOS's
  `Transferable` drop.
- **The destination's highlight.** The proposal said the drop target's
  highlight "can" shift colour to match. TUI draws no highlight for these
  views — the app draws its own from `isTargeted` — so there is nothing to
  shift. **The fuller version** would hand the app the proposed operation,
  which SwiftUI does not do either.

The badge sits on the preview's top-right cell, not beside it: the preview's
frame is what a `DropInfo` reports and what a cancelled drag walks home from,
and a cell beyond it would make the carried picture wider than that frame. It
hides the preview's corner cell while it shows. Precisely, it covers the last
cell of the top row, which is that corner for a rectangular preview, and
every row keeps its own width, so a ragged preview shows the page after its
short rows as it does unbadged. A top row of one cell wears the badge beside it, the one
place the picture grows by a cell: covering it hid a one-glyph drag whole.

### B80. Table row drag and drop: the row's own line, a selected look, flat loops

*`TableRowContent.draggable(_:)`, `TableRowContent.dropDestination(for:action:)`,
`TableRowContent.itemProvider(_:)`, `ItemProviderTableRowModifier`,
`DynamicTableRowContent.dropDestination(for:action:)`,
`DynamicTableRowContent.onInsert(of:perform:)`, `OnInsertTableRowModifier`*

Wave 8a's deferral (priced at a day and a half), built on the drag session
`List` rows and `.draggable` views already use.

**Shipped:** a press on a row that carries a payload, then any movement,
starts a drag with the row's own line under the pointer (morphing from the
grid's layout to a carried row's, as a `.cursor` reorder's does); a release
over anything that takes the payload — a view's `.dropDestination`, another
row's, a table or list that inserts it — delivers it, and a press released
without moving is a click on the row. A row's own `.dropDestination(for:action:)`
takes drops onto itself. A loop's `.dropDestination(for:action:)` and
`.onInsert(of:perform:)` take payloads between its rows, the table opening the
gap `Table.dropDestination` already opens, and report the offset into the
loop's own collection, counting from its first row whatever rows come before
it, as SwiftUI's `onInsert` offsets are. Item providers are Apple-only, as
the view forms are.

Where it differs:

- **The targeted row is drawn as a selected row.** macOS rings the row a drop
  would land on in the accent; a ring needs a cell around the row, which the
  grid does not have. The selection fill is the nearest drawn answer, and
  goes when the drag leaves.
- **A draggable row is not picked up by `Table.onMove(_:)`** (TUI's own
  table-level reorder): the press carries the payload. SwiftUI's tables have
  no `onMove`; their reorder is a loop's `dropDestination` with draggable
  rows, which works here too.
- **A hierarchical table's loops take no insertions**: there the drawn rows
  are the open tree's, not one loop's, and an offset into a loop under a
  closed branch has no drawn slot. An hour or two, if wanted, to map the slot
  to the loop whose rows it falls among by walking the outline. **Built
  (2026-10-19, lane LISTS2):** measured on macOS 15.8
  (`Tools/SwiftUIProbes/Hierarchical table insertions/outlineinsert.swift`),
  a drop SwiftUI's outline proposes among a branch's rows goes to those rows'
  loop at its offset among them, and one among the roots to the roots' loop;
  TUI's table now walks the outline it shows and does the same. A slot
  two loops reach — the end of a branch's rows is also the place before the
  next row out — goes to the deeper loop that takes the payload, as a
  terminal's drop line has no indentation to aim by. Not copied: where a
  branch's rows have no loop that takes the drop, SwiftUI hands it to the
  roots' loop at the offset it had among the branch's rows. A slot no loop
  that takes the payload reaches opens no gap and refuses the drop, which
  flies home — in a flat table too, where a hand-written row sits outside
  the loops.

### B82. Spring loading: a paused drag activates a control, drawn waiting and firing

*`SpringLoadingBehavior` (`.automatic`, `.enabled`, `.disabled`),
`View.springLoadingBehavior(_:)`, `TabContent.springLoadingBehavior(_:)`,
`EnvironmentValues.springLoadingBehavior`*

Measured on macOS 15.8:

- `\.springLoadingBehavior` is `.automatic` by default, and the modifier
  overrides an ancestor's value rather than unioning with it.
- A `Button` in every style (`.automatic`, `.bordered`, `.borderedProminent`,
  `.borderless`, `.plain`, `.link`), a `NavigationLink` (both forms), a `Link`,
  a `.button` `Toggle` and a segmented `Picker` are spring-loaded under
  `.enabled` and not under `.automatic` or `.disabled`. A `Menu`, a menu or
  radio-group `Picker` and a checkbox `Toggle` are never spring-loaded.
- A `DisclosureGroup` under `.enabled` toggles its expansion on each
  activation; a plain button runs its action on each. The activation is
  discrete: AppKit's `NSSpringLoadingEnabled`, without continuous activation.
- The system's delay, `com.apple.springing.delay`, reads 0.5 s.

A macOS `TabView` draws no tab bar in a bare `NSHostingView`, so its default
was taken from SwiftUI's documentation: a tab view spring-loads under
`.automatic`.

**Shipped:** while a drag carrying a payload is in flight, the pointer
resting on a spring-loaded control for half a second activates it as a click
would — a button runs its action, a disclosure group opens or closes, a tab
(its chip in a strip, its row in a `.sidebarAdaptable` sidebar) is selected —
and the drag carries on. The controls are the ones measured, through
`Button`'s core (which `NavigationLink`, `Link`, segmented segments and a
disclosure group's header are built on), the toggle core for a `.button`
toggle, and the tab view. A tab's own behavior beats the tab view's.

Where it differs:

- **Drawn as hovered while it waits, pressed as it fires** (owner ruling
  B82, 2026-10-23: "Draw the pending state"; built 2026-10-24, lane MISC).
  macOS highlights a spring-loadable control under a drag and emphasises it
  as it activates (`NSSpringLoadingHighlight`). The session names the
  control the pause rests on and its phase
  (`DragAndDropSession.springLoadPhase(of:)`: `.pending` from the moment the
  pointer arrives, `.firing` from the frame it activates for a tenth of a
  second, six frames, so the emphasis is seen — one frame is gone before it
  is), and drops the control's cached pictures as the phase changes, through
  the `HandlerDrawing` its registration carries. A button draws hovered
  through both and pressed as it fires: the built-in styles draw a press as
  they draw the hover, as they do under the mouse; a style of the app's own
  sees `isHovered` and `isPressed`. A `.button` toggle draws hovered (it has
  no pressed look; its flip is the emphasis); a segmented picker's segment
  and a tab strip's chip draw as the pointer over them does, each naming its
  own spring-load identity below the control's. A `.sidebarAdaptable`
  sidebar's row has no hover look, so it draws as it was. Asked only while a
  drag is in the hand. Tests: `SpringLoadingTests`
  (`pendingAndFiringAreDrawn`), `SpringLoadingRunLoopTests`.
- **A move to another cell restarts the pause**, and a control activates once
  per arrival: the pointer has to leave and come back for a second
  activation, so a disclosure group opened by a pause is not shut by the
  next. AppKit's own repeat rule could not be measured.
- **The delay is the user's where TUI can read it** (owner ruling B82:
  "system delay when local, with an override"; built 2026-10-24, lane MISC).
  macOS reads the user's spring-loading speed, `com.apple.springing.delay` in
  the global domain (a float in seconds: `defaults read-type -g` says so, and
  it reads 0.5 at the default, on macOS 15.8.1). The app runner reads it with
  the host's accessibility settings (`HostSettingsRefresher`, at launch and
  on focus-in, off the main actor) and counts it only where
  `SessionLocality.isLocal()` says the user is at this machine; elsewhere —
  over ssh, on Linux — it is macOS's default, half a second. The user's
  `TUIKIT_SPRING_LOADING_DELAY` (seconds) overrides the host's. The render
  loop writes the result at the root as `\.springLoadingDelay`, and the
  TUI-specific `.springLoadingDelay(_:)` overrides it for a subtree, as an
  environment value does — the app's choice over the user's there, which is
  the override the ruling asks for. Each target takes the delay it was drawn
  under. Not read: macOS's spring-loading on/off switch
  (`com.apple.springing.enabled`), which the ruling did not ask for. Tests:
  `SpringLoadingDelayTests`, `SpringLoadingTests.delayModifier`.
- **No Force Click**, macOS's other trigger: a terminal has no pressure.
- **A row reorder does not spring-load**: its rows land only in their own
  list, so revealing somewhere else is no use to it.
- **A control built from a button spring-loads through it** under
  `.enabled`: an `OutlineGroup`'s triangle opens its branch. Not a
  `ColorPicker`'s well, since 2026-10-24 (owner ruling B82: "SwiftUI's
  per-control defaults"): SwiftUI's colour well does not spring-load under
  any behavior, its `NSColorWell` no `NSSpringLoadingDestination` (measured,
  macOS 15.8.1, `Tools/SwiftUIProbes/Spring loading (lane 17d)/spring7.swift`),
  so the well's button is `.springLoadingBehavior(.disabled)`. Test:
  `ColorWellSpringLoadingTests`.
- **The keyboard needs no pause.** Mid-drag, Tab moves the focus and Return
  or Space activates the focused control, with the drag still in hand — the
  route the no-mouse-only rule asks for, and pinned by a test.

This also takes `TabContent.springLoadingBehavior(_:)` out of A49:
a strip's chips already register a click region each, so a pause over one
needed nothing new. The other five per-tab interactions shipped with A49 on
2026-10-05.

### B83. The drag and drop session values ship; nothing hands them out yet

*`DragSession` (`id`, `phase`, `location`, `draggedItemIndex`,
`draggedItemIDs(for:)`), `DragSession.ID`, `DragSession.Phase` (`.initial`,
`.active`, `.ended(_:)`, `.dataTransferCompleted`), `DropSession` (`id`,
`phase`, `location`, `size`, `itemsCount`, `localSession`,
`suggestedOperations`), `DropSession.ID`, `DropSession.Phase` (`.entering`,
`.active`, `.exiting`, `.ended(_:)`, `.dataTransferCompleted`),
`DropSession.LocalSession`, `DragConfiguration` (its three initialisers,
`operationsWithinApp`, `operationsOutsideApp`),
`DragConfiguration.OperationsWithinApp`,
`DragConfiguration.OperationsOutsideApp`, `DropConfiguration`
(`init(operation:)`, `operation`, `acceptedItemCount`),
`DragDropPreviewsFormation` (`.default`, `.list`, `.none`, `.pile`,
`.stack`), and their descriptions*

**Shipped:** the values, as SwiftUI documents them: a phase that ended
carries its operation; a session's item identifiers are filtered by the type
asked for; a drag configuration allows copying unless told otherwise, and
`init(allowMove:)` allows moving both within the app and outside it, as on
macOS. A `location` is a `CellPoint` and a `size` a `CellSize` (§2.2 of the
compatibility doc), as `DropInfo`'s location is. A drop's `localSession` is
never `nil`, since a terminal app's drags all start inside it, and
`OperationsOutsideApp` is recorded and offered to nothing.

Where it differs:

- **Nothing hands a session out.** The modifiers that would are A53,
  and do not compile; a value can be named, built where SwiftUI lets one be
  built (the configurations, the formations), and passed around.
- **The descriptions are TUI's spelling** (`.ended(.move)`,
  `DragSession.ID(3)`, `DragConfiguration(operationsWithinApp: [.copy,
  .move], …)`): SwiftUI does not document its own, and it is macOS 26 only.

The fuller version is A53. A macOS 26 measurement pass is owed either
way.

*Lane 17t's entries (B84–B88, C13–C14), `Text(AttributedString)` and Markdown in `Text` keys (refusal review P8): SwiftUI's rules measured on macOS 15.8 (SDK 26.2) by comparing offscreen bitmaps; the probes and the differential fuzz harness are in the session notes, `w17t`.*

### A53. The drag-session behaviour: callbacks, configurations, containers, formations

*`View.onDragSessionUpdated(_:)`, `View.onDropSessionUpdated(_:)`,
`View.dragConfiguration(_:)`, `View.dropConfiguration(_:)`,
`View.dragPreviewsFormation(_:)`, `View.dropPreviewsFormation(_:)`,
`View.dragContainer(for:in:_:)`, `View.dragContainer(for:itemID:in:_:)`,
`View.dragContainerSelection(_:containerNamespace:)`,
`View.draggable(containerItemID:containerNamespace:)`,
`View.draggable(_:containerNamespace:_:)`,
`View.draggable(_:id:containerNamespace:_:)`,
`View.draggable(_:id:item:containerNamespace:)`,
`View.draggable(_:item:containerNamespace:)`; and whether
`dropDestination(for:isEnabled:action:)` hands its action a `DropSession`*

macOS 26's in-app drag and drop. A source hears its drag's phases
(`.initial`, `.active`, `.ended(operation)`, `.dataTransferCompleted`) and
says which operations it allows; a destination hears the drag enter, move
over it and leave, and chooses the operation; a container turns a drag of one
item into a drag of the selection, its payload built from identifiers when
the drag starts; and the previews of several items are composed as a list, a
stack or a pile. The review (P18) found the refusal wrong: none of it needs
anything outside the process, and TUI's drag session and list selection
are where it would be built. The values (B83) ship; these fourteen
modifiers stay out until this is answered, recorded in `baseline.json` as
known gaps.

Nothing here could be measured: these are macOS 26 APIs, and this machine
runs 15.8. Whatever ships would be built from the doc comments and want a
measurement pass on macOS 26.

Three things are genuinely the owner's:

- **What an operation means.** TUI's drops do not distinguish copy, move
  and delete today (B10): a source that hears `.ended(.move)` is the point of
  `onDragSessionUpdated`, so the session would carry the destination's chosen
  operation back to the source, and a destination's `dropConfiguration`
  choosing an operation the source does not allow — or `.cancel` or
  `.forbidden` — would refuse the drop and send the drag home.
- **`dropDestination(for:isEnabled:action:)`.** SwiftUI hands its action a
  `DropSession`; TUI hands a `DropInfo` (the cell, the modifiers held at
  release, the preview's frame). Either the action switches to `DropSession`,
  which then also carries the modifiers and the preview frame as TUI's own
  members, or `DropInfo` keeps the action and grows the session's members
  (`phase`, `itemsCount`, `size`, `suggestedOperations`, `localSession`) so
  SwiftUI source reading them compiles. Pre-1.0, the switch needs no shim.
- **Keyboard drags.** A `.draggable` view is picked up only by the pointer
  today — an existing mouse-only interaction this family inherits. A keyboard
  pick-up and put-down for `.draggable`, as Ctrl-R is for a list's rows
  (focus a draggable, a chord picks it up, Tab and the arrows carry it, Return
  drops it on the focused destination, Escape sends it home), would make
  every session reachable from the keyboard. About a day, and a question of
  its own if the owner wants it apart from this one.

**Options.**

1. **Sessions and configurations on the single-item drags that exist.**
   `onDragSessionUpdated` on a `.draggable`, an item provider's drag and a
   table row's; `onDropSessionUpdated` on every drop destination;
   `dragConfiguration` setting the source's allowed operations (a drop
   session's `suggestedOperations`); `dropConfiguration` asked on each move,
   its operation the drop's, one the source does not allow refusing it,
   `acceptedItemCount` capping how many items are taken. The configuration
   closure is held by a box compared by identity, as the `.searchable`
   dismissal is, so the memos below a destination stay on. A day.
2. **Option 1, plus containers and formations.** A drag container's payload
   is several items, so every destination — `dropDestination`, a list's and
   a table's insertions, item providers, drop delegates — takes all of them
   (SwiftUI's actions already take arrays); the selection comes from
   `dragContainerSelection`. The previews are drawn from the items' own
   pictures where they are on screen: `.list` stacked down the column,
   `.stack` and `.pile` offset behind the grabbed one (a cell grid has no
   rotation), `.none` where each sits, `.default` as `.stack`, and a count
   for items not drawn. A drawing change, with the Stress self-check. A day
   and a half more: two and a half in all.
3. **Option 1, and decline containers and formations** as macOS 26 surface
   with no ported code to serve yet. A day.
4. **Decline the family** by reason. Not recommended: the review found the
   reason wrong, and no better one exists.

**Recommendation:** 1 now, with `dropDestination(for:isEnabled:action:)`
switched to `DropSession` (carrying the modifiers and preview frame), so the
SwiftUI spelling means the SwiftUI thing; containers and formations (2's
remainder) once there is macOS 26 code to port and a macOS 26 machine to
measure them on. Option 1 is what B10's fuller version asked for — a source
told its item moved — and is the part of this family ported code reaches
first.

**Decided 2026-10-04: pinned** until macOS 26 or 27 can be measured; the
macOS 15.8 notes here stay.

*Lane 17g's entries (A54, B89–B94, C15), SwiftUI's gestures (refusal review P6): measured on macOS 15.8 (SDK 26.2) by sending synthesised `NSEvent`s into a window; the probes are in `Tools/SwiftUIProbes/Gestures (lane 17g)/`.*

What the probes established, and what now holds here too:

| Question | macOS 15.8 |
|---|---|
| A parent's `gesture` vs a child's tap | the child's; the parent's gets a click elsewhere |
| A parent's `highPriorityGesture` | the parent's, on the child too |
| A parent's `simultaneousGesture` | both — the parent's callback first |
| `including:` `.gesture` / `.subviews` / `.none` | child off / parent off / both off |
| `.gesture` / `.onTapGesture` / `.onLongPressGesture` on a plain-style `Button` | the button's action; the gesture never runs |
| `.highPriorityGesture(TapGesture())` on that button | the tap; no action |
| `.simultaneousGesture(TapGesture())` on it | both, the tap first |
| `.highPriorityGesture(DragGesture())` on it | a click is the button's; a drag is the drag's |
| A tap's slop, hold and double-tap interval | 40 points (45 fails); 0.75 s; the next click released within 0.35 s of the last release (a press in time but held past that gives the tap up then, button still down) |
| `onTapGesture(count: 2)` inside `onTapGesture` | a double-click runs only the double; a single click runs the single 0.35 s after its release |
| `LongPressGesture`'s defaults | 0.5 s, 10 points (Euclidean; 11 fails); `true` from the press; ends at the deadline with the button down |
| `onLongPressGesture`'s pressing callback | `true` on the press; `false` just before the action |
| `DragGesture`'s start | at `minimumDistance` (≥), the press kept as `startLocation`; a drag that never starts does not end |
| A sequence's `onEnded` | when its second gesture ends; the event that ends the first gesture is the second's first (a tap before a tap ends at one click); only a first gesture that ends on its clock leaves the second to the next event. A release is a press already over: a tap before a drag or a long press fails at the tap's release, and a tap before a zero-duration long press ends there, `false`, with no `onChanged` |
| `@GestureState`'s reset | on end, failure or cancellation, before `onEnded` |
| `modifiers(_:)` | read at the press; more keys than asked for satisfy it |

### A53-KEYBOARD-DRAG. A drag carried from the keyboard

*`View.draggable(_:)`, `View.dropDestination(for:action:isTargeted:)` and the
other drop destinations, from the keyboard*

The owner asked (2026-10-23) for a keyboard drag mode that limits the focus to
drop destinations, and ruled (2026-10-26) for the carry mode after its
prerequisite, Copy and Paste on the two ends (shipped that night,
`TransferKeys`).

**First part shipped (lane CARRY, 2026-10-27).** A carry is the pointer's
drag driven by a pointer of its own, placed on the top row's last cell of the
focus stop it is at (`DragAndDropSession+Carry.swift`). So everything a drag
over a destination does, a carry does too: `isTargeted`, the badge, the
three-party operation, a delegate's moves, and the drop itself.

- **Picking up:** Ctrl-R, a list row's pick-up chord, on a focused
  `.draggable` (on its content's stops, or its own). The view is drawn as gone
  while it is carried, as under the pointer.
- **Carrying:** Tab and the arrows move the focus only among the stops that
  can take it. Those are the stops of the destinations that accept the
  payload: the ones a destination names (`Target.focusIDs`: a
  `dropDestination`'s, from `TransferKeys`), or else the stops drawn inside
  it. Also included are the spring-loaded controls a pause would press, and
  the stop the carry started from. They are ordered by reading position,
  round the ends. The picture is drawn just after the stop.
- **Ending:** Return drops on the destination at the focus. On a
  spring-loaded control with no destination there, it presses the control
  and the carry goes on; at the origin, it puts the drag back. Escape, or
  Ctrl-R again, puts it back and returns the focus to the origin. A refused
  drop also puts it back.
- **Other keys:** Space flips the operation, as Option does for the pointer
  (B-BITEMS1-1's sixth point). The paging keys go on to the drag navigators,
  which scroll what the carry is over. A chord goes on its way, so the quit
  key still quits. Other plain keys are swallowed, so a field the focus
  passes does not type them.

**Second part shipped (lane CARRY2, 2026-10-27).**

- **The cue.** Each stop the carry can reach, except the one it is at, is
  marked by an accent `‹` in the cell after its top row. That is where the
  picture would be drawn were the carry there. `‹` is U+2039, East Asian
  Width Neutral, so it is one cell everywhere.
- **The status line.** At a destination, Return says "drop". At the origin, it
  says "cancel move", the label a list's keyboard move already uses. At a
  spring-loaded control, the control's own verb stands. Escape says "cancel
  move" throughout (`DragAndDropSession.carryLabels`).
- **A list is one stop.** At a destination taller than a row, Up and Down
  first move the carry's pointer between its rows, and the list's landing
  slot follows it. Past the top or bottom row, they move to the next stop.
  Tab, Left and Right always move between stops. A lazy list's unseen rows
  are reached with the paging keys, which scroll what the carry is over.

**Not built, and why.** An idle expiry: a carry left alone keeps its keys, and
the status line says how to put it back. Ending it on a timer would make a
slow hand lose what it carried, which is the opposite of what the mode is for.
"Pick Up" in a draggable's context menu: nothing yet lets a modifier add an
item to a context menu the app builds, so that is a mechanism of its own.

The pick-up chord is Ctrl-R as written: a list's `RowAction` rebinding does
not reach it, because the table of row actions lives in `TUILists`. The
tests are `CarryModeTests` and `ListCarryTests`.

### C12. The drag sessions' AppKit comparisons

*`DragSession.ID.matches(_:)`, `DropSession.ID.matches(_:)`*

Each compares a session with AppKit's own dragging object
(`NSDraggingSession`, `NSDraggingInfo`), which a TUI drag never is: a
terminal app drags inside itself, without AppKit, and Linux has no AppKit at
all. The review listed both as its CONFIRM for P18. They are now the only
declined members of the family, each with its own `notImplemented` entry; the
family rule that declined the rest is gone.
