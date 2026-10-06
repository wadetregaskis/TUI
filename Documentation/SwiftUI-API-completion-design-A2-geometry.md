# A2 (+A7): anchors, named coordinate spaces, scroll visibility — design study

*Read-only study at `f56c419d`, 2026-10-04. Inputs: decisions doc A2 (line 178) and
A7 (line 386); the W05 brief §3.3 (G1's full mechanics, probes L/M);
`plan/a2_g3_idea.md` (G3); `Documentation/Locating things without drawing them.md`
§2, §5a–b, §12. Nothing here was built or measured; every cost below is an
estimate, and every percentage I quote is one somebody else measured, with its
source.*

---

## 0. The answer in one paragraph

G1 and G3 are not rivals. **G1's markers are the only way to get a TRUE position
that does not depend on every container being taught something; G3's carried
origin is the only way to get a position BEFORE the content is built.** Three of
the five users never need the second (anchors read by `overlayPreferenceValue`,
scroll visibility, `onGeometryChange`): under markers they are exact with no
re-render at all. The re-render only ever concerns content that is built FROM a
non-local frame — a `GeometryReader` body, a `scrollTransition`. And there pure
G1 is worse than its entry says: "none in steady state" is false for the most
common SwiftUI geometry idiom (a reader tracking scroll offset), which moves
every scroll frame and so corrects every scroll frame — twice the scroll cost.
**Recommendation: G4, a hybrid — markers as the truth, the carried origin as a
prediction, a per-reader residual between them, and a correction only when the
prediction missed.** With no container converted G4 *is* G1 (the prediction is
"last frame's answer"), so G1 is the first stage, not a fallback; each
container that learns to translate the origin removes a class of corrections,
and the Stress correction counter says which ones are worth converting.
Converting the scroll view and the stacks (which already compute placement for
gradients) takes the scroll idiom to zero corrections. The hot-path field fits
in RenderContext padding that already exists (stride stays 104).

---

## 1. The problem in TUIkit's terms

TUIkit fuses SwiftUI's two top-down phases — *place* and *draw* — into one
bottom-up walk: a container renders a child into a `FrameBuffer`, and only then
composites it at an offset. So a view learns where it is only after it has
already been built. `GeometryProxy` must answer while its content closure runs,
which is before.

Two different quantities are being asked for, and they have different
solutions:

- **(a) Where the asker is**, in some space S — `frame(in:)`, `bounds(of:)`'s
  offset, the proxy's own origin when it resolves an anchor.
- **(b) Where something else is**, relative to the asker — an anchor site, S's
  rectangle (`bounds(of:)`), the scroll viewport (A7).

(b) is naturally *observed*: by the time the asker's owner has composited, every
rectangle is known. (a) is needed *before the asker's content exists*, which is
the only part that forces either a prediction or a re-render.

**One simplification the whole design leans on:** TUIkit geometry is
translation-only. Every space is the root shifted by a constant; there is no
scale or rotation (A27 recommends declining the transforms — if option 2 ships,
a scale must stay non-geometric, as the `.scale` transition already draws). So
one `(x, y)` origin carried or observed per view answers every space at once:
`frame(in: S) = origin(view) − origin(S)`.

### What the five users actually need

| User | Needs (a) before content builds? | Content depends on the answer? | Exact with markers alone, no re-render? |
|---|---|---|---|
| `GeometryProxy.frame(in:)` / `bounds(of:)` inside a `GeometryReader` body | yes | **yes** (the body is built from it, or a preference value is) | no |
| `anchorPreference` + `proxy[anchor]` in `overlay/backgroundPreferenceValue` | only the proxy's origin *within the layer* | yes | **yes** when the reader is the layer's root (the common case, and probe L1): the base renders before the layer is built, so the anchor markers are already in the base's buffer in the layer's coordinates. Probe L2 (reader padded inside the layer) needs (a) inside the layer only. |
| `coordinateSpace(_:)` / `.named` declarations | no — they are owners | — | yes |
| `.scrollView` space; A7 `onScrollVisibilityChange`, `onScrollTargetVisibilityChange` | no — callbacks | no | **yes**: the scroll view measures the markers against its final viewport after it settles its offset |
| A7 `scrollTransition`, and `visualEffect` asking a non-local frame | yes | yes (the drawing) | no (but see §5.4: the effect can be applied late instead) |
| `onGeometryChange` with a non-local space | no | no — the action fires | **yes**, if the action fires after the owner composites (it fires at the view's own render today) |
| Popover attachment (`Anchor<CellRect>.Source`) | **no** — `.bounds` and `.rect(_:)` are both LOCAL to the presenting view | — | not a positional user at all; a type swap |

That table is the main reframing of the decision: the "re-render" the owner
dislikes is confined to rows 1, 2 (L2 only) and 5.

---

## 2. Existing machinery (file:line at `f56c419d`)

**Proxies and readers**
- `GeometryProxy` — `Sources/TUIkit/Views/GeometryReader.swift:25`; `globalOrigin`
  `:30` is never set by any caller; `frame(in:)` `:49–58` falls back to local;
  `hasGlobalPosition` `:70`.
- `_GeometryReaderCore` `:203`: greedy (`sizeThatFits` `:213` never builds the
  content), so **a reader's size and position never depend on its own content**
  — the property that lets one correction converge. `contentContext(noting:in:)`
  `:266` notes the size and `clearAffected` `:274` below on change: the pattern
  a resolved origin must follow.
- `OnGeometryChangeModifier` — `Sources/TUIkit/Modifiers/OnGeometryChangeModifier.swift:88`;
  compares at render and records a render side effect `:103` (declines every
  ancestor memo); proxy built from the rendered size `:125`.
- `_VisualEffectView.renderToBuffer` — `Sources/TUIkit/Modifiers/VisualEffect.swift:108`:
  renders content, THEN builds the proxy from the buffer and applies
  `_applied(to:context:)` (`:44`) — an effect is already a post-render buffer
  transform.

**Things that already travel up (G1's carrier)**
- `FrameBuffer.hitTestRegions` — `Sources/TUIkitCore/Rendering/FrameBuffer.swift:152`;
  shifted by every combinator (`shiftedHitTestRegions` `:1243`, `replacingLines`
  `:1142`); grep finds 102 references in 51 files across the three modules.
- `HitTestRegion` — `Sources/TUIkitCore/Input/HitTestRegion.swift:29`: `topClip` /
  `leftClip` and `localOriginY/X` (`:118`, `:122`) keep the UNCLIPPED origin through
  a scroll view; `clipped(toColumns:rows:)` `:182` drops a region with no
  surviving area; `HandlerID` is a `UInt64` `:208` (room for a reserved range).
- `MouseEventDispatcher.regionOffset(for:)` — `Sources/TUIkit/App/MouseEventDispatcher.swift:973`:
  the absolute, unclipped origin of any region after the frame.
  **`RegionOrigin` (`Sources/TUIkit/Modifiers/OnHoverModifier.swift:124`) already
  answers `.global` for pointer events this way** — observed up, looked up
  lazily. Hover observers are skipped for claiming (`hoverObserverIDs`,
  `MouseEventDispatcher.swift:151, 913–916`): precedent for a region that
  takes no clicks.
- Overlay layers are DROPPED off-screen by the scroll view
  (`viewportOverlay`, `ScrollView+Content.swift:554–570`) and filtered at about a
  dozen other sites (`ClippedModifier.swift:56`, `HitTestingModifier.swift:149`,
  `ScrollPinnedChrome.swift:101`, `FrameBuffer+Overlays.swift:51`, …) — which is
  why I would carry markers as hit regions (A7's option 2 carrier), not as
  overlay layers (the W05 brief's choice).

**Things that already travel down (G3's carrier)**
- `RenderContext.gradientFrame` — `Sources/TUIkitView/Rendering/RenderContext.swift:343`;
  `gradientContentFrame` `:358`; `placingGradientChild(_:x:y:)` `:371`.
  `GradientFrame` (`Sources/TUIkitCore/Rendering/GradientFrame.swift:22`) already
  carries `originX/originY`.
- Grep finds 13 `placingGradientChild` calls in 8 files: `_VStackCore.renderClip`
  (`VStack.swift:466–487`), the windowed paths (`VStack.swift:620–624, 963–988`,
  `StackAnchoredWindow.swift:815–913`, `StackUniformWindow.swift`), `HStack.swift:487–531`,
  `_LayoutCore.renderToBuffer` (`Layout.swift:414–423`), `_GridCore` (`Grid.swift:434–464`),
  `_ListCore` (`_ListCore.swift:3389–3409`, in CONTENT coordinates, before the
  list's window and chrome), plus `OutlineGroup.swift:464`, `ListRowExtractor.swift:385`.
  Placement helpers: `StackGradientPlacement.swift` (`gradientOffsets`,
  `windowGradientPlacement` for both stacks).
- `LayoutPlacing` — `Sources/TUIkitView/Rendering/LayoutPlacing.swift:89`: placement
  by measurement; implemented only by `_VStackCore` (`StackLayoutPlacing.swift:219`),
  and it reports `x = 0` (`LayoutPlacing.swift:33–37`).
- `BufferModifier.adjustContext` — `Sources/TUIkitView/Core/BufferModifier.swift:127`,
  called before the content renders (`ModifiedView.renderToBuffer` `:235`):
  where a padding/border can translate an origin.

**RenderContext layout** (`RenderContext.swift`): six word fields to offset 48;
three `Bool`s and `measureGeneration: UInt8` 48–51; `scrollContentOriginDepth:
UInt16` 52–53; padding 54–55; `environmentApplicationDepth: Int` 56–63;
`gradientFrame: GradientFrame?` 64–96 (four `Int`s and a `Bool` whose spare bits
hold the optional's tag). Size 97, stride 104 — the 97 is the doc's own figure
(`:218`). An `Int` more measured **+2.4% `anyview`, +1.4% `modifiers`** (`:218–228`,
the stride moving to 112). No test pins the stride today.

**Owners that already re-render to correct**
- Root: `RenderLoop.swift:768–788`, the App Header correction — the one
  discarded pass (`Discarded render passes and redundant frames.md` §1); its
  side effects fire twice, pinned as a known issue in `RenderPassScopeTests`.
- Scroll view: `coverSnappedViewport` (`ScrollViewReveal.swift:341`) re-renders
  the content band in the same call when the reveal moved past it.

**Owners/storage**
- `PreferenceLayerModifier.renderToBuffer` — `Sources/TUIkit/Modifiers/PreferenceLayerModifier.swift:33`:
  push, render base, pop, build layer, composite (`compositeLayer`,
  `LayerComposite.swift:152/196`). The anchor table belongs between `pop()` and
  `transform`.
- StateKey negative ranges — `Sources/TUIkitView/State/StateStorage.swift:54–70`;
  `-90…` is free at this commit (the W05 brief claimed it; two lanes are open —
  re-check at landing).
- `VolatileReadTracker.recordUnkeyedRead()` — `Sources/TUIkitCore/Environment/VolatileReadTracker.swift:246`:
  "a read of a value no memo keys on"; the buffer memo's store gate refuses it.

**ScrollView render order** (`ScrollView.swift:416–627`): offset decided
(`applyPositionOffset`, opening glue) → `renderedContent` `:502` → re-glue against
the real height `:523–531` → `clampScrollOffset` `:541` → focus snap `:548` →
`coverSnappedViewport` `:559` → `reglueToRefinedTail` → `windowedBuffer` `:595` →
`finishFrame` (`ScrollGeometry.swift:212`, where `onScrollGeometryChange` already
fires). **The final offset is known only after the content rendered** on glue,
clamp and reveal frames; on a plain wheel/arrow frame it is the pre-render one.

**Root**: `WindowGroup.renderScene` CENTRES the content by its RENDERED size
(`App.swift:960–1000`), below a header whose height is estimated, then corrected.

---

## 3. Container audit: who knows a child's origin before rendering it?

"Exact" = from numbers the container has already computed before the child's
render. "Measured" = would need the child's measured size, which equals the
rendered one only under measure/render parity. "After" = only known after the
child renders.

| Container | Child origin before render? | Where it diverges |
|---|---|---|
| `VStack` `.clip` (`VStack.swift:399`) | **y exact** (PASS 1 `distributeLinearSpace`); **x measured** — alignment uses RENDERED widths (`maxChildWidth` `:489`, `alignmentWidth` `:497`); guides from rendered sizes `:505` | a wrapping `Text` measures at its natural width (`.unspecified` proposal `:408`) but renders narrower at `availableWidth`, so the predicted centre moves. A greedy reader child is width-flexible, so `fillsWidth` makes ITS x exactly 0; it is a reader in a `.background` of a rigid row that inherits the error. |
| Lazy stacks (`renderWindow`, `renderViewportWindow`, anchored, uniform) | y exact in the stack's coordinates; x from measured width (`StackAnchoredWindow.swift:852`) | the anchored path's ABSOLUTE content y is an estimate (its own comment `:808–814`); viewport-relative y is exact, because the offset is anchored the same way |
| `HStack` `.clip` (`HStack.swift:447`) | x from allocated widths (exact if the child renders its allocation); y measured, re-measures a height-filling child `:519` | children are appended by RENDERED width (`appendHorizontally`, `FrameBuffer.swift:549`), so a child narrower than its allocation shifts later ones left |
| `ZStack` (`ZStack.swift:74`) | **no** — renders every child unmeasured `:97`, aligns by rendered size `:153–158` | needs a measure per layer when active (likely a memo hit from its own `sizeThatFits`) |
| `Grid` (`Grid.swift:409`) | box origin exact; seat in box measured (already done for gradients `:452–464`) | parity only |
| custom `Layout`, lazy grids, `AnyLayout` (`Layout.swift:389`) | **exact**: `placeSubviews` entries `(x, y)` before render `:418–423` | none |
| `.padding` (`PaddingModifier.swift:132` adjust, `:199` modify) | exact from `drawnInsets` and the context (except the empty-content rule `:203`, irrelevant: nothing to locate) | none in practice |
| `.border` / Box / Panel / Card / GroupBox (`ContainerViewCore.swift`) | (1, 1) plus a title row; exact in principle | not converted for gradients either |
| `.frame` (`FrameModifier.swift:223`) | **after** — final size and alignment from the rendered buffer `:251–278` | needs a measure at the content proposal (memo hit from `sizeThatFits` usually) |
| `.overlay` / `.background` / preference layers (`LayerComposite.swift:47`) | **after** for the layer — aligned by its rendered size `:93–103`; base at (0,0) | a greedy layer (a reader) fills the base and lands at (0,0) for every alignment — exact for the idiom |
| `.offset` / `.position` (`OffsetModifier.swift:37`, `PositionModifier.swift:84`) | exact (`x`, `y` are the modifier's data) | content FLOATS as an `OverlayLayer` — an owner scanning only `hitTestRegions` misses markers inside it; owners must also scan layer contents |
| alignment guides | resolved against rendered sizes in VStack/ZStack, measured in HStack (`HStack.swift:539–541`) | parity only |
| `ScrollView` (`ScrollView.swift:416`) | content origin `−scrollOffset` exact on plain scroll frames | **after** on glue/clamp/reveal frames (§2) — the frames where things move anyway |
| `List` / `Table` rows | viewport y from the handler's index window + chrome; the gradient path is in content coordinates (`_ListCore.swift:3389`) | needs its own conversion (viewport, not content) |
| Root | header height estimated; centring by RENDERED size (`App.swift:960`) | usually content fills the terminal (offset 0); header correction exists |
| Presenters (sheet, popover, menu) | popover origin known after the panel renders (`PopoverPresentationModifier.swift:233–240`), flipped at the root | a separate hierarchy: named spaces should not cross it (SwiftUI's don't) |

Beyond the 8 gradient files, grep finds roughly 30 more files that composite a
child at an offset (`App.swift`, `AppHeader.swift`, `ContainerBackground.swift`,
`FrameModifier.swift`, `LayerComposite.swift`, `ListRowStyleModifiers.swift`,
`PaddingModifier.swift`, `SafeAreaInsetModifier.swift`, `ContainerViewCore.swift`,
`ContentUnavailableView.swift`, `ScrollContentMargins.swift`,
`ScrollPinnedChrome.swift`, `SplitView.swift`, `TabView.swift`, `ZStack.swift`,
`_UserResizableCore.swift`, `NavigationSplitView*.swift`, `NavigationStack.swift`,
`RadioButton.swift`, `SelectableListRow.swift`, `TableOutline.swift`,
`_ToggleCore.swift`, `SectionActions.swift`, `NotificationHostModifier.swift`,
`DialogSuppression.swift`, the offset/position modifiers, `ScrollView*`). **G3
alone is exact only once every one of them translates, and silently wrong at
each one that does not** — the same failure class as the "payload dropped by a
bare `FrameBuffer(lines:)`" audit, but invisible (a wrong number, not a dead
click).

---

## 4. Design G1 — markers read back up, correction re-render

The W05 brief §3.3 has the full mechanics; in short:

- A reader that asks a non-local question, and every anchor site, stamps a
  zero-content marker. Owners — `.coordinateSpace(_:)`, the `ScrollView` (for
  `.scrollView`), `PreferenceLayerModifier` (anchors), the root (`.global`) —
  read the markers out of their rendered subtree. A proxy answers from what its
  owners found LAST frame (a tracked value at `-90…`); an owner whose readers
  were told something different re-renders its subtree once (a greedy reader
  cannot move itself, so one pass converges).

**Carrier.** I would change one thing from the brief: carry the marker as a
`HitTestRegion` whose `HandlerID.raw` has a reserved high bit (interned per
reader identity, so a memo replay keeps it), not as an `OverlayLayer`. Regions
already ride every combinator and keep their unclipped origin through a scroll
view (`localOriginY`); overlay layers are dropped at ~12 sites (§2). Two edits
make regions sufficient: `clipped(toColumns:rows:)` keeps a marker that loses
all area (zero-size, clip amounts recorded) instead of returning `nil`, and the
dispatcher's collection/hit test skips the range (one compare per region, the
`hoverObserverIDs` precedent). Owners also scan `overlays[i].content` for
markers that `.offset` floated.

**Costs.**
- Work: 3–4 days per the decisions doc; A7 visibility about a day more.
- Hot path when unused: none (no markers, owners scan nothing).
- With readers: a correction re-render of the owner's subtree **on every frame a
  queried position moved**. That includes:
  - every scroll frame for the scroll-offset idiom
    (`GeometryReader { p in Color.clear.preference(key:, value: p.frame(in: .named("scroll")).minY) }`,
    or the same with `.scrollView`) — the owner is the scroll view or just above
    it, so scrolling costs two content renders a frame;
  - every animation frame of an animated `.offset` / transition above a reader;
  - the first frame each reader appears (a lazy row entering the band);
  - at the root (`.global`), each of these is a whole-frame re-render.
- Parity risk: none — it observes the truth.
- Memo: a reader that asks a non-local question calls `recordUnkeyedRead()`, so
  its ancestor chain stores no buffer memo (the preference writer's precedent);
  the reader notes the resolved origin like its size (`GeometryReader.swift:266`).
  Callback users (A7, `onGeometryChange`) need not decline: their markers replay
  with the buffer, and the owner fires.
- Focus/input: a correction re-runs registrations and `onAppear`/`onChange` in
  the re-rendered subtree (the header correction's known issue, scoped to a
  subtree); markers must never take a click.

**Makes possible:** all five users exactly; `.global` stops lying; A7 option 1;
`onGeometryChange` with named spaces.

---

## 5. Design G3 — carry the origin down

**Mechanics.** Each container that places a child computes the child's origin
before rendering it and hands it down in the context, as the gradient path does.
`.global`, named spaces, `.scrollView` and anchor sites read their origin at
render; no markers, no correction.

- **Carrier without growing the stride.** Two `Int32`s fit in padding that
  already exists if the declarations are reordered: `geometryOriginX: Int32` at
  52 (after `measureGeneration`), `scrollContentOriginDepth: UInt16` moved to 98
  (after `gradientFrame`), `geometryOriginY: Int32` at 100. Size 104, stride 104.
  `Int32.min` is "unknown/inactive". (Folding it into `GradientFrame` is wrong:
  a nested `.gradientExtent(.subtree)` resets that origin, and the render cache
  keys on `gradientFrame` (`RenderCache.swift:757`), which would turn every move
  into a memo miss under an owner.) A `MemoryLayout<RenderContext>.stride == 104`
  test should pin it. Stride-neutral is not the same as free — the UInt8
  precedent was accepted on that argument; it still needs an A/B.
- **One call per placement.** Generalise `placingGradientChild(_:x:y:)` into
  `placingChild(gradient:x:y:)` translating both carriers, so the 13 existing
  sites convert for free; each new converter also fixes `.gradientExtent(.subtree)`
  drift at that container (padding, border, frame, ZStack and overlay do not move
  the ramp today).
- **Activation** cannot be a static witness: B19 records that a witness stops at
  an app's own view type unless every body forwards (`Body._providesAlignmentGuide`
  — measured-risk on `fanout`/`deep`), and readers live inside app views. It has
  to be dynamic: an owner activates when it had readers last frame, a
  `.coordinateSpace` declaration always (it exists to be read). *As built:
  "readers" means views told a prediction — a `GeometryReader`, a visual
  effect, a scroll transition — not an `onGeometryChange` reporter or a
  pointer converting at event time, which are asked after the frame; and a
  declaration carries one while there are readers or before anything has
  asked, so one read only by gestures stops carrying it on its second frame.*

**Costs.**
- Work: carrier + the 13 sites (1 day); ScrollView/List/Table (1–1.5); the ~10
  generic composers (padding, border chrome, frame, overlay/background/preference
  layers, ZStack, offset/position, safeAreaInset, content margins, TabView /
  NavigationSplitView / SplitView, root + header) (1.5–2); API, spaces, anchors
  (2); A7 visibility without markers needs its own "vanished" bookkeeping (1).
  **6.5–7.5 days, plus a permanent tax**: every future container must translate.
- Hot path: stride unchanged; per placement, one sentinel check inactive, two
  adds active; extra measures in ZStack/frame/overlay when active.
- **Parity risk is a correctness risk here**: every row of §3's last column is a
  silently wrong answer, and the scroll view is wrong exactly on the frames
  where things move (glue, clamp, reveal). The root centres by rendered size.
- Memo: as G1 (a memo above a reader does not key on its origin).
- Focus/input: none.

**Makes possible:** zero re-renders where every container on the path is
converted; parallax and `scrollTransition` with no correction; gradient extents
that follow padding and borders; a "placed context" substrate the safe-area
option SA-B would need anyway (W05 brief: "propagated by adjacency through every
container" — the same list).

### 5.4 Two side variants, recorded

- **G5, pull instead of push.** The owner locates each known reader by its
  identity chain with `LayoutPlacing` (the Locating doc's Stage 2 "locate"
  visitor, outstanding) before rendering. No context field; but every container
  must implement `placement(at:)` with a real `x` (today only `_VStackCore`, with
  `x = 0`), and each reader costs an O(depth) walk of memo-hit measures that the
  render walk does anyway. Not now; if Stage 2 lands for its own reasons, G4's
  predictor can switch to it and drop the field.
- **Late-bound effects** (for `scrollTransition` and a non-local `visualEffect`
  only). The view floats its rendered content as an `OverlayLayer` with the
  effect pending (closure in a per-frame table by marker id); the scroll view,
  once its offset is final, computes the phase and calls the effect's
  `_applied(to:context:)` on the layer — offset, opacity (an `OpacityRegion`)
  and the colour effects all apply to a buffer. Exact everywhere, no prediction,
  no re-render. Price: a transitioning row is a floated layer, so it draws above
  its siblings and its in-flow footprint is blank — harmless for rows that do not
  overlap, visible for overlapping layouts.

---

## 6. Design G4 (recommended) — markers for truth, origin as prediction, residual between

**Mechanics.**

1. **Truth:** G1's markers, carried as reserved-range hit regions (§4).
2. **Prediction:** G3's carried origin, but *only where a container already knows
   it*. Unconverted containers do nothing special — their offset simply is not in
   the prediction.
3. **Residual:** per (reader identity, space), store `observed − predicted` from
   the last frame (tracked value, `-90…`). The answer a reader gets is
   `predicted_now + residual_last`. With no container converted, `predicted ≡ 0`
   and this is exactly G1's "last frame's answer".
4. **Verify:** the owner compares each marker with what its reader was told
   (told values in a per-frame table on the owner); a mismatch updates the
   residual and re-renders the owner's subtree once (debug-assert the second
   verify is clean).
5. **Callbacks never predict:** A7 visibility, `onScrollTargetVisibilityChange`
   and a non-local `onGeometryChange` are fired by the owner after it composites,
   from markers. The proxy handed to `onGeometryChange`'s `transform` is a
   recording one: a transform that asked only for `size`/`.local` keeps firing at
   render as today; one that asked a non-local space is deferred to the owner.

**Why the residual is enough.** An unconverted container's contribution is
usually constant from frame to frame (a padding, a centring, a border). The
residual absorbs it after one correction; from then on, motion from CONVERTED
containers (the scroll offset, a stack reflow, a `Layout`) is predicted exactly
and costs nothing. A correction happens only when an unconverted container's
offset changes, or a reader appears for the first time under one.

**Where the corrections go, per stage** (owner = the subtree re-rendered):

| Situation | G1 | G4 after scroll + stacks rung | G4 after generic-composer rung | G3 (if fully converted) |
|---|---|---|---|---|
| static page with readers | 0 | 0 | 0 | 0 |
| scroll-offset tracker while scrolling (wheel/arrows) | **1 per frame** | 0 | 0 | 0 |
| rows with `.background(GeometryReader…)` entering a lazy band | 1 per frame a row enters | 0 if the row path is stack-only; 1 if a row padding/border sits between | 0 | 0 |
| animated `.offset` above a reader | 1 per animation frame | 1 per animation frame | 0 | 0 |
| insertion above a reader (stack reflow) | 1 | 0 | 0 | 0 |
| reflow inside an unconverted container (wrapped text in a centred `VStack` row) | 1 | 1 | 1 (parity) | wrong answer, no correction |
| glue/clamp/reveal frame of a scroll view | 1 | 1 (merged with `coverSnappedViewport`'s re-render) | 1 | wrong answer |
| terminal resize, `.global` | whole frame | whole frame, merged with the header correction | same | wrong if centring changed |
| first frame of a `.global` reader | whole frame | 0 if the root's active | 0 | 0 |

**Costs.**
- **Work:** floor = G1 + A7 visibility ≈ 4.5–5.5 days; prediction rungs ≈ 3.5–4.5
  days (carrier + 13 sites 1; scroll view, List, Table + `scrollTransition`
  1–1.5; generic composers 1.5–2). Each rung is optional and lands on a
  measured correction rate.
- **Hot path:** unused → nothing beyond G1's (zero) plus one sentinel compare per
  converted placement site; carrier stride-neutral (§5). Used → corrections as
  in the table, plus G3's arithmetic and the occasional extra measure.
- **Parity:** affects the correction RATE only, never the answer.
- **Memo:** as G1 (`recordUnkeyedRead` on a non-local read; resolved origins noted
  at the reader). A later refinement could key an ancestor memo on the carried
  origin instead of declining; not proposed now.
- **Focus/input:** as G1, at the reduced correction rate; markers skipped by the
  dispatcher.

**Makes possible:** everything G1 and G3 do, plus a measurable dial: the Stress
counter says which unconverted container causes corrections, so conversion is
spent where an app actually pays.

### The five users under G4

1. **`frame(in:)` / `bounds(of:)`.** `GeometryProxy` gains a reference to the
   frame's resolver (owner origins and sizes, the residuals). `frame(in: S)` =
   carried origin + residual − S's origin; an unknown name gives the local frame
   and `bounds(of:)` gives `nil` (probe M2). `bounds(of: S)` needs S's SIZE before
   S has finished rendering: S measures its content at its proposal first
   (predicted), verifies after; `.scrollView`'s viewport size is known before the
   content renders (`viewport(context)`, `ScrollView.swift:419`).
2. **`anchorPreference` / `proxy[anchor]`.** `Anchor<Value>` = (marker id,
   source); id interned from the site's identity + source, stable across frames.
   `PreferenceLayerModifier`, between `pop()` and `transform`, builds an
   id→rect table from the base buffer's markers (base-relative = layer-relative)
   and sets the carrier to (0, 0) for the layer. L1: exact, no correction. L2:
   exact once padding converts; one layer-only correction before that (the base
   is never re-rendered — its anchors came from it). An anchor kept in `@State`
   and read elsewhere resolves from the root's table, last frame — SwiftUI-like.
3. **`coordinateSpace(_:)`.** A `Renderable` modifier: writes name → owner token
   into the environment (one write, only where declared), records its own carried
   origin, renders, verifies its readers. `NamedCoordinateSpace`,
   `CoordinateSpaceProtocol.named(_:)`, `CoordinateSpace.named(_:)` (the enum
   gains a case — a source change on exhaustive switches; pre-1.0, no shim).
   Presenters clear the name table and start a fresh root for their content.
4. **`.scrollView` / A7.** The scroll view owns `.scrollView` and
   `.scrollView(axis:)` (nearest scroll view on that axis — two environment
   tokens). Visibility: after the offset is final (`finishFrame`,
   `ScrollGeometry.swift:212`), each observer marker in the content buffer is
   intersected with `[offset, offset + viewport)`; first report, then each
   threshold crossing; an observer seen last frame and absent now (windowed out,
   removed) reports `false`; an observer under no scroll view is reported by the
   root against the screen. `onScrollTargetVisibilityChange` takes its ids from
   the target layout's children (the stack files, other lane's). `scrollTransition`
   reads its phase from the predicted viewport position at its own render — exact
   for rows of a stack under a scroll view once rung 2 lands — or, if you prefer
   no prediction, the late-bound variant (§5.4).
5. **Popover attachment.** `PopoverAttachmentAnchor.rect(Anchor<CellRect>.Source)`
   replacing `PopoverAttachmentRect` (`PopoverPresentationModifier.swift:20–31`):
   `.bounds` and `.rect(_:)` are local, resolved against the base buffer at
   `:233–240`. Needs only the `Anchor.Source` type. Point sources need `CellPoint`
   (exists, `Views/CellPoint.swift:15`) and floor once (`x + w/2`).

---

## 7. Comparison

| | G1 | G3 | **G4** |
|---|---|---|---|
| Exact answers | always (after a correction) | only where every container on the path translates | always |
| Re-renders in steady scrolling with a tracker | 1 per frame | 0 | 0 (after rung 2) |
| Re-renders on first appearance | 1 per owner | 0 | 0 on converted paths |
| New hot-path field | none | 2×Int32 in existing padding | same as G3 |
| Containers to change | none (carrier exists) + clipping sites keep markers | all ~40 placing files, forever | as many as the counter justifies |
| Failure mode of a forgotten container | none | silent wrong number | one correction (then absorbed) |
| Parity dependence | none | correctness | correction rate |
| Days | 3–4 (+1 A7) | 6.5–7.5 | 4.5–5.5 floor, +3.5–4.5 rungs |

---

## 8. Recommendation

**G4, staged so that G1 ships first.** It answers the owner's objection where it
bites — the scroll-offset idiom, which pure G1 would re-render every scroll
frame — without making correctness depend on converting forty files. Land the
floor (markers, owners, correction, A7 visibility, anchors), add the Stress
`geometry` scenario and its correction counter, then convert the scroll view
and the stacks (rung 2). Convert the generic composers only where the counter
on a real shape says a correction is being paid; each of them also fixes a
gradient-extent drift, so the work is not wasted either way.

---

## 9. Questions only the owner can answer

1. **Hybrid G4 (G1 floor first, then prediction rungs measured by a correction counter) rather than pure G1?** — yes / no.
2. **On a misprediction: correct in the same frame (exact, one more pass of that owner's subtree) or draw it and fix it next frame (one wrong frame, no extra pass)?** Suggested: same frame for named/scroll/anchor owners; for `.global` at the root, same frame but merged into the header-correction pass.
3. **May RenderContext's fields be reordered to fit two `Int32`s in existing padding (stride stays 104), landing only if `anyview` and `modifiers` A/B within noise?** — yes / no.
4. **Does a non-local geometry read decline ancestor buffer memos, as a preference writer does (its ancestor chain then renders every frame)?** — yes / find a keyed memo first.
5. **`scrollTransition`: predicted position (exact through stacks under a scroll view, corrected elsewhere) or late-bound effect on a floated layer (exact everywhere, the row draws above its siblings)?** — predicted / late-bound.
6. **Generic-composer rung (padding, border, frame, overlay, ZStack, offset, root): with A2, or only when the counter shows corrections on a real shape?** — with A2 / on evidence.
7. **`onGeometryChange` with a non-local space fires after the owner composites, not during the view's render — acceptable?** — yes / no.
8. **A row deep in an anchored (>256-row) lazy stack: may its content-space frame (`.named` above the stack) be an ESTIMATE, as the scrollbar is? `.scrollView` stays exact.** — yes / no.
9. **Swap `PopoverAttachmentRect` for `Anchor<CellRect>.Source` now, as its own commit (it needs no geometry)?** — yes / no.

One measurement, not a question: probe M3 was taken at scroll offset 0, so it
cannot tell content space from viewport space. The decisions doc says
`.scrollView` "answers in the scroll content's space"; Apple documents it as the
space "added by the system for the innermost containing scroll view", and every
use of it I know (offset tracking, transitions) needs it to move with the
scroll. Re-run M3 at offset 40 before step 3; I expect `(0, 0, 100, 20)`
(viewport space), and the design above assumes it.

**Re-measured (2026-10-05, lane D5G, macOS 15, probes in the session notes
`D5G/probe`):** confirmed. A reader 40 points down a 100-point `ScrollView`
scrolled 40 points reports `frame(in: .scrollView) == (0, 0, 100, 20)` and
`bounds(of: .scrollView) == (0, 0, 100, 100)` — the viewport; `.named` on the
`ScrollView` itself answers the same, and `.named` on its content answers
`(0, 40, …)`. Two findings beside it, re-measured with the reader OFF the
window's origin (M2 had it at the origin, where local and global coincide):
**an unknown name answers in the global space**, not the local one
(`bounds(of:)` is still `nil`); and `.scrollView` outside any scroll view, or
`.scrollView(axis:)` with no scroll view along that axis, answers in the global
space too. The innermost scroll view answers `.scrollView` whatever its axis.
The implementation follows these: the scene root answers every name nothing
nearer declared, in the global space.

---

## 10. Staged implementation plan

One commit per step; each runs the 6.2.4 build + suite, and `Stress --selfcheck`
where drawing changes (steps 2, 4, 6, 7). A/B only on a quiet box (agents never
benchmark); "A/B" below names the scenarios to run then.

1. **Marker carrier.** `HitTestRegion.HandlerID.isGeometryMarker` (reserved high
   bit) and interning per identity; `HitTestRegion.clipped` keeps a marker with no
   area; `MouseEventDispatcher` skips markers when collecting and hit testing;
   `FrameBuffer.geometryMarkers(…)` scans regions and floated layer contents.
   *Tests:* a marker survives padding, `.border()`, VStack/HStack/ZStack/Grid/
   `Layout`, overlay/background, `.offset`, `.position`, `.clipped()`, a scroll
   view scrolled past it (unclipped origin via `localOriginY`), List/Table rows;
   a click on a marker's cell reaches the control under it.
   *A/B:* `fanout`, `table`, `kitchensink` (region-list length).
2. **A7 visibility on markers.** `onScrollVisibilityChange(threshold:_:)`: observer
   marker + closure table (replayable effect, so a memo replay keeps firing);
   `ScrollView.finishFrame` fires crossings; the root fires for observers outside
   any scroll view. *Tests:* first report true/false; crossing at 0.5; custom
   threshold; windowed-out row → false; removed view → false; nested scroll views;
   no double fire across a `coverSnappedViewport` re-render. *A/B:* `scrolleager`,
   `scrollfollow`, `megalist` (no observers: must be unchanged).
3. **G1 floor: spaces, owners, correction.** `NamedCoordinateSpace`,
   `.named(_:)`, `CoordinateSpace.named`, `.scrollView`, `.scrollView(axis:)`,
   `View.coordinateSpace(_:)`; `GeometryProxy` resolver reference, `frame(in:)`
   for all spaces, `bounds(of:)`; residual store at `-90…` (claim it in the
   `StateKey` table); owner verification + one re-render in
   `_CoordinateSpaceModifier`, `ScrollView` (merged with `coverSnappedViewport`),
   and `RenderLoop.renderContent` (merged with the header correction);
   `recordUnkeyedRead` + origin noting in `_GeometryReaderCore`; recording proxy +
   owner-deferred `onGeometryChange`. Remove `hasGlobalPosition`'s fallback
   wording. Add the Stress `geometry` scenario (scroll-offset tracker, a named
   space over a 500-row `LazyVStack` of `.background(GeometryReader…)` rows, an
   anchor highlight following the focused row, visibility observers; script:
   scroll, insert above, animate an offset, resize) with counters: corrections per
   frame by owner kind. *Tests:* probes M1, M2, M3 (and M3 at offset 40); a
   correction happens once then steady state is clean; side effects inside a
   corrected subtree (known-issue pin like `RenderPassScopeTests`); memo verifier
   clean on `geometry`. *A/B:* `anyview`, `modifiers`, `deep` (reader-free trees
   untouched); `geometry` baseline numbers.
4. **Anchors.** `Anchor`, `Anchor.Source` (rect and point sources, arrays,
   optionals), `anchorPreference`, `transformAnchorPreference`,
   `GeometryProxy.subscript(_:)`; the id→rect table in `PreferenceLayerModifier`;
   layer-only correction. Popover `.rect(Anchor<CellRect>.Source)` swap as a
   separate commit here if Q9 is yes. *Tests:* probes L1 (no correction), L2 (one
   layer correction until step 7), anchor in `@State`, an anchor inside a scrolled
   view, an anchor inside `.offset`. *A/B:* `preferences`.
5. **Rung 1: the carrier.** Reorder `RenderContext` (`geometryOriginX/Y: Int32`,
   `scrollContentOriginDepth` moved), pin the stride at 104 in a test,
   `placingChild(gradient:x:y:)` replacing `placingGradientChild` at the 13 sites,
   prediction + residual in the resolver, activation from last frame's readers and
   always under a `.coordinateSpace`. *Tests:* prediction equals the marker
   through stacks, `Grid`, `Layout`, lazy windows; residual absorbs an unconverted
   ZStack; correction counter 0 for an insertion above a reader. *A/B:* `anyview`,
   `modifiers` (stride claim), `gradients` (the generalised call), `deep`,
   `fanout`, `customlayout`, `geometry`.
6. **Rung 2: scroll view, List, Table; `scrollTransition`.** Content origin
   `−offset` on the pre-render offset; List/Table rows in viewport coordinates
   including chrome; `scrollTransition(_:axis:transition:)`,
   `scrollTransition(topLeading:bottomTrailing:axis:transition:)`,
   `ScrollTransitionConfiguration`, `ScrollTransitionPhase` (or the late-bound
   variant, per Q5). *Tests:* the tracker scrolls 100 frames with 0 corrections;
   phases at the edges; rows entering a lazy band predicted exactly. *A/B:*
   `scrolleager`, `scrollfollow`, `megalist`, `table`, `tables-scroll`,
   `session/editor`, `session/log`, `geometry`.
7. **Rung 3 (per Q6): generic composers.** Padding/border via `adjustContext`,
   `ContainerViewCore` chrome, `FlexibleFrameView` and `LayerComposite` (measure
   the layer when active), `ZStack` (measure when active), `.offset`/`.position`,
   `SafeAreaInset`, content margins, TabView / NavigationSplitView / SplitView,
   root centring + header. Each also moves `.gradientExtent(.subtree)` correctly —
   extend `GradientExtentTests`/`GradientGeometryTests` beside the geometry test.
   *A/B:* `modifiers`, `framedcolumns`, `kitchensink`, `gradients`,
   `customlayout`, `geometry`.
8. **Docs.** Decisions doc A2/A7 to "shipped" entries; `SwiftUI-compatibility.md`
   (Layout row, §4b anchors and safe area); the `CoordinateSpaceProtocol.swift`
   header comment; a cross-reference from the Locating doc §12 (G5 as the
   pull-side future). Behaviour and doc go in the same commit as each step per the
   docs-as-you-go rule; this step only sweeps what is left.

**Built (lane D5G, 2026-10-05).** Steps 1–8 as above, one commit each (two
pure moves and a field reorder made room first), with these departures, each
written up in `SwiftUI-API-completion-decisions-D5G.md` (the decisions doc's
A2 and A7 entries are left for the coordinator to retire):

- the geometry correction of a scroll view is its own drawing, not merged into
  `coverSnappedViewport` — with rung 2 the content's second and third drawings
  are predicted at the offsets they are made at, so it only runs when the
  prediction missed;
- a reader is held to a space's SIZE only if it asked it (`bounds(of:)`), so a
  growing list does not correct readers that asked only `frame(in:)`;
- `.global` and undeclared names are predicted only in the root's frame of
  reference (`GeometryOwnerScope.startsReference`);
- not converted: a `List`'s rows and its `.scrollView` (B-D5G-9), the root's
  centring, `safeAreaInset`, content margins, `TabView`, `NavigationSplitView`,
  `SplitView` (B-D5G-10); `Table` cells carry no origin, so a reader there is
  corrected on its first frame (B-D5G-2);
- `scrollTransition`'s default threshold is unmeasured and taken as `.visible`
  (B-D5G-8).

**Merged onto A28's window chrome (2026-10-06).** The header correction the
root's correction was merged into (question 2) is gone: the window's bars are
rows of the scene, adopted the frame after. The root's correction is now a
second walk of the scene of its own, made only when a `.global` reader's
prediction missed, with the bars laid out against the rows the first walk was
(`RenderLoop.renderContent`) — the only walk a frame after the first ever
repeats. The frame the root reads is the screen, bars and composited layers
included, so `.global` is the screen's cells, the window's chrome host places
the content's carried origin below the top bar, and a reader in a presented
surface or in a bar's `.toolbar` item is found and corrected in the frame that
draws it (B-D5G-3, B-D5G-2).

The Stress counter's shape (`GeometryCorrectionRateTests`), corrections per
frame by owner after each rung:

| | G1 (step 3) | rung 1 (step 5) | rung 2 (step 6) | rung 3 (step 7) |
|---|---|---|---|---|
| first frame | named 1, scroll view 1, root 1 | scroll view 1, root 1 | scroll view 1, root 1 | scroll view 1, root 1 |
| at rest | 0 | 0 | 0 | 0 |
| each scroll step | scroll view 1, named 1 | scroll view 1 | 0 | 0 |
| an insertion above | named 1 | 0 | 0 | 0 |
| each step of an `.offset` above a `.global` reader | root 1 | root 1 | root 1 | 0 |
| anchor highlight following a row | — | layer 0 | layer 0 | layer 0 |
| residual | 0 | 0 | 0 | 0 |

The first frame's two are the frame before the root has a reader to carry an
origin for.

The residual row holds for that shape, whose scroll steps set the offset before
the content draws. **Review follow-ups (same day):** a scroll view whose offset
moved after its content drew — the glue to a tail that grew, a seek the content
resolved, the clamp, the focus snap over eager content — kept the first
drawing's prediction beside what it found, so its correction drew every reader
one move off and counted a residual of 1 each such frame. Each drawing now
says where it placed the content, and the predictions are moved to the offset
the frame settled on before any owner looks (`settlePlacement`): those frames
cost their owner one correction (the first drawing is still made at the old
offset) and leave residual 0. The placement includes the overscroll slide, so a
push past an edge costs nothing. Also from the review: rows a scroll view draws
twice in a frame keep their marker and handler ids (`RenderWalkCheckpoint.rewind`);
a value first seen in a walk the frame then draws again appears rather than
animating from it; only readers start a carried origin (not reporters or
pointers); `GeometryProxy` is neither `Equatable` nor `Sendable`, as SwiftUI's
is not.

---

## 11. Risks and things to check while building

- **Markers inside floated layers** (`.offset`, `.position`, transitions) are
  invisible to an owner that scans only `hitTestRegions`; the scan must descend
  into `overlays[i].content` with the layer offset, and presented surfaces
  (sheets, popovers, menus) must NOT be descended into for the presenter's named
  spaces.
- **One-pass convergence** rests on readers being greedy. An anchor site is not
  greedy, but anchors are observed, never predicted, so a correction never moves
  one; assert it in debug.
- **Merging corrections.** A scroll view can re-render up to three times today
  (content, `coverSnappedViewport`, `reglueToRefinedTail`); the geometry
  correction must ride one of those, not add a fourth.
- **Measure passes** must not stamp markers, register readers, or record the
  unkeyed read (a reader's size never depends on the answer).
- **Lazy windows**: a row never rendered has no marker; its reader keeps last
  frame's residual and is not drawn, so nothing shows the staleness — but its
  `onGeometryChange` must not fire from a stale value.
- **Stress `geometry` correction counter** is the acceptance metric for rungs 2
  and 3; the profile share of a correction is a hypothesis until a trace says so.
