# A19 — sheets the reader can resize, with a live page behind

Design study, 2026-10-04, read against `main` at `f56c419d0`. Read-only: nothing
here was built, run or measured. Every cost below is an estimate; every
performance figure is a prediction for the A/B in §9 to confirm or refute.

## 0. Summary

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

## 1. The problem in TUIkit's terms

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

## 2. What SwiftUI specifies

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
`Equatable` in SwiftUI, and `PresentationContentInteraction` is. TUIkit's types
match (`PresentationInteraction.swift:32`, `:56`), so adding cases is purely
additive. `Visibility` exists (`ListRowSeparatorModifier.swift:34`).

**What follows from the doc comments.** On iOS, `.automatic` content
interaction behaves like `.resizes`. TUIkit documents `.automatic` as "its
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

## 3. The machinery today

### 3.1 Presentation hosting and the backdrop

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

### 3.2 Focus sections, Tab and Escape

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

### 3.3 Mouse and hit testing

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

### 3.4 Resize precedents

| Precedent | What it gives |
|---|---|
| `_SplitPaneDividerHandler` (`SplitView.swift:73`), `dividerBuffer` (`:243`) | A focus stop via `FocusRegistration.persistFocusID` / `register` (`FocusRegistration.swift:54`, `:120`). Up/Down move it, Shift for five. A press focuses it and a drag moves it relative to the press. |
| `_UserResizableCore` | `GripGlyphs.standingOut(from:)` (`_UserResizableCore.swift:146`): a handle drawn in whichever Box Drawing weight stands out from the border cell it lands on. `drawGrip`, `mark` and `drawEdgeGrips` (`:474`, `:538`, `:563`) handle the resting, hovered and focused tints. All of it is `private`. Uses negative `StateIndex` values (`:101`). |
| `Drawers-sheets-and-slideovers.md` §3–§5 | Already recommends: a sheet with more than one detent draws a grabber on its top border; a drag snaps to detents; the keys move between detents, not cells; the grabber matches `.userResizable`'s handle. |

### 3.5 Root geometry and the chrome rule

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

## 4. What terminals pass through — the key bindings

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
| F6 ("next pane") | not now | Nothing in TUIkit binds it. Tab already does the job. Revisit if readers ask. |

Mouse: drag the sheet's top border row (the whole row is the target and the
drawn handle is short, as with `.userResizable`). A press focuses the grabber.
The wheel follows `.resizes` / `.scrolls`, rate-limited to one detent per
250 ms (15 frames at 60 Hz, per the animation-timing rule) so that one
trackpad burst does not sweep every detent.

---

## 5. Three designs

Every design includes A's grabber. They differ in what happens behind the sheet.

### Design A — detents made real, the page stays inert (the entry's option 2)

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

### Design B — an overlay over a full-height live page (iOS read literally)

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

### Design C — a docked sheet; the page reflows into the rows above it (recommended)

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

### Comparison

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

## 6. Recommendation

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

## 7. Decided here (minor; per "decide minor questions myself")

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

## 8. Questions only the owner can answer

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

## 9. Staged plan (one commit per step)

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

## 10. Risks and loose ends

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
