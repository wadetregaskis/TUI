# Completing the SwiftUI API: Wave 17d decisions (spring loading and drag sessions)

*Wave 17d's entries for
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md),
in its format, to be folded in and renumbered there. Wave 17d acts on two
refusals the Wave 17 review found wrong, P11 (`SpringLoadingBehavior`) and P18
(the drag-session family). SwiftUI's behaviour was measured on macOS 15.8
(built against the macOS 26.2 SDK) by probes that host SwiftUI views in an
`NSHostingView` and drive SwiftUI's own spring-loading entry points with a
stand-in `NSDraggingInfo`; the probe sources are in the session notes
(`w17d/probe/`), not in the repository. The drag-session family is macOS 26
API and could not be probed.*

---

## A. Needs your decision

### A-W17d-1. The drag-session behaviour: callbacks, configurations, containers, formations

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
anything outside the process, and TUIkit's drag session and list selection
are where it would be built. The values (B-W17d-2) ship; these fourteen
modifiers stay out until this is answered, recorded in `baseline.json` as
known gaps.

Nothing here could be measured: these are macOS 26 APIs, and this machine
runs 15.8. Whatever ships would be built from the doc comments and want a
measurement pass on macOS 26.

Three things are genuinely the owner's:

- **What an operation means.** TUIkit's drops do not distinguish copy, move
  and delete today (B10): a source that hears `.ended(.move)` is the point of
  `onDragSessionUpdated`, so the session would carry the destination's chosen
  operation back to the source, and a destination's `dropConfiguration`
  choosing an operation the source does not allow — or `.cancel` or
  `.forbidden` — would refuse the drop and send the drag home.
- **`dropDestination(for:isEnabled:action:)`.** SwiftUI hands its action a
  `DropSession`; TUIkit hands a `DropInfo` (the cell, the modifiers held at
  release, the preview's frame). Either the action switches to `DropSession`,
  which then also carries the modifiers and the preview frame as TUIkit's own
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

---

## B. Shipped the safe option

### B-W17d-1. Spring loading: a paused drag activates a control, undrawn

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

- **Nothing is drawn.** macOS highlights a spring-loadable control under a
  drag and emphasises it as it activates (`NSSpringLoadingHighlight`).
  TUIkit's control does not know a drag is over it; a pause activates it with
  no warning. The fuller version: the session publishes the target under the
  pointer and how far through the pause it is, and the control draws itself
  hovered while it waits and pressed for the frame it activates, its memo
  told through the session's render invalidation as a drag source is. Half a
  day, a drawing change with the Stress self-check.
- **A move to another cell restarts the pause**, and a control activates once
  per arrival: the pointer has to leave and come back for a second
  activation, so a disclosure group opened by a pause is not shut by the
  next. AppKit's own repeat rule could not be measured.
- **The delay is fixed at half a second**, the system's default. macOS reads
  the user's setting; a terminal app cannot, and an environment value to
  change it would be TUIkit's own API, with nothing asking for it yet.
- **No Force Click**, macOS's other trigger: a terminal has no pressure.
- **A row reorder does not spring-load**: its rows land only in their own
  list, so revealing somewhere else is no use to it.
- **A control built from a button spring-loads through it** under
  `.enabled`: a `ColorPicker`'s well opens its editor, an `OutlineGroup`'s
  triangle opens its branch. macOS's colour well is no `NSButton`, and was
  not measured; if it should not, the well's button can opt out in an hour.
- **The keyboard needs no pause.** Mid-drag, Tab moves the focus and Return
  or Space activates the focused control, with the drag still in hand — the
  route the no-mouse-only rule asks for, and pinned by a test.

This also takes `TabContent.springLoadingBehavior(_:)` out of A49 (A-W08b-4):
a strip's chips already register a click region each, so a pause over one
needed nothing new. The other five per-tab interactions there are unchanged.

### B-W17d-2. The drag and drop session values ship; nothing hands them out yet

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

- **Nothing hands a session out.** The modifiers that would are A-W17d-1,
  and do not compile; a value can be named, built where SwiftUI lets one be
  built (the configurations, the formations), and passed around.
- **The descriptions are TUIkit's spelling** (`.ended(.move)`,
  `DragSession.ID(3)`, `DragConfiguration(operationsWithinApp: [.copy,
  .move], …)`): SwiftUI does not document its own, and it is macOS 26 only.

The fuller version is A-W17d-1. A macOS 26 measurement pass is owed either
way.

---

## C. Declined without asking

### C-W17d-1. The drag sessions' AppKit comparisons

*`DragSession.ID.matches(_:)`, `DropSession.ID.matches(_:)`*

Each compares a session with AppKit's own dragging object
(`NSDraggingSession`, `NSDraggingInfo`), which a TUIkit drag never is: a
terminal app drags inside itself, without AppKit, and Linux has no AppKit at
all. The review listed both as its CONFIRM for P18. They are now the only
declined members of the family, each with its own `notImplemented` entry; the
family rule that declined the rest is gone.

---

## D. Deferred to other waves or lanes

- **A macOS 26 measurement pass** for B-W17d-2's values, and for A-W17d-1's
  behaviour if it is built.
- **A tab view's spring loading under `.automatic`** follows SwiftUI's
  documentation; measuring it needs a probe with a live window and a real
  drag, which a hosting view offscreen does not give.
- **Keyboard drags for `.draggable`** — raised in A-W17d-1, and a question of
  its own if the owner wants it separately.
