# Wave 17 — the refusals, re-examined

*2026-10-03. Wave 17 of [`SwiftUI API completion plan.md`](<SwiftUI API completion plan.md>),
done early so the other waves can act on it: its WRONG and PARTLY WRONG
verdicts are scheduled into the waves that own them, and its OWNER DECISION
items (O0–O17) are put to the owner from
[`SwiftUI API completion decisions.md`](<Decisions/SwiftUI API completion decisions.md>).
Produced by a read-only review agent; its macOS and Linux probes are quoted
where they decided a verdict.*

*Every `notImplemented` entry (130 — the plan says 124; six were
added since) and every `families` rule (28) in `Tools/APIParity/parity-map.json`,
plus a skim of the 54 `differentShape` entries. Read-only review: nothing in the
repository was changed.*

The test applied throughout: a refusal earns its place by naming what the API
would have to DO and why a cell grid, a pty, Linux or Windows cannot do it. A
true fact about terminals that the API never depended on does not count, and
nor does a cost or taste argument dressed as a medium limit. The opposite error
was checked too: per-pixel shading, GPUs, an accessibility tree, Apple-only
frameworks and hardware a terminal never sees stay refused.

## Counts

| | notImplemented (130) | families (28) | total (158) |
|---|---:|---:|---:|
| **WRONG — implementable** | 54 | 0 | 54 |
| **PARTLY WRONG** | 8 | 13 | 21 |
| **OWNER DECISION** | 19 | 4 | 23 |
| **CONFIRM** | 49 | 11 | 60 |

26 of the 54 WRONG keys are one cluster, Shapes, gated by one owner
sub-decision (§W1). The rest are mostly small (S): vocabulary types the planned
waves already need.

---

## Cross-cutting findings

### X1. Refused types, queued modifiers: the map contradicts the plan

The waves schedule modifiers whose argument types the map refuses. Whichever way
each call goes, the type and its modifiers must move together. As things stand,
a wave cannot implement its modifier without first overturning a map entry.

| Refused type (map) | Modifier(s) queued in the plan |
|---|---|
| `Namespace` | W09 `focusScope(_:)`, `prefersDefaultFocus(_:in:)`, `ResetFocusAction.callAsFunction(in:)`; W09 `matchedTransitionSource`; W12 `matchedGeometryEffect` |
| `ControlSize` | W06 `View.controlSize(_:)`, `\.controlSize` |
| `SafeAreaRegions`, `ScenePadding` | W05 `ignoresSafeArea(_:edges:)`, `scenePadding(_:)`, `scenePadding(_:edges:)` |
| `InsettableShape`, `Shape` | W05 `containerShape(_:)`; W16 `clipShape`, `contentShape`, `background(_:in:fillStyle:)`, `overlay(_:in:fillStyle:)` |
| `Rectangle` | W13 (it is a *gap* there, but every other shape is *refused*) |
| `ButtonBorderShape` | W04 `buttonBorderShape(_:)` |
| `ContentTransition` | W12 `contentTransition(_:)`, `\.contentTransition` |
| `AnimationCompletionCriteria` | W12 `withAnimation(_:completionCriteria:_:completion:)` (the entry itself says "worth adding together") |
| `Keyframes`, `KeyframeTrack`, `*Keyframe` (family) | W12 `KeyframeTimeline` — which cannot be written without them |
| `Spring` | W12 `Animation.interpolatingSpring(_:initialVelocity:)` takes a `Spring` |
| `AnyTransition.push(from:)` | W12 `PushTransition` |
| `AnyTransition.modifier(active:identity:)` | W12 the `Transition` protocol (the same mechanism) |
| `NavigationTransition`, `MatchedTransitionSourceConfiguration` | W09 `navigationTransition(_:)`, `matchedTransitionSource(id:in:configuration:)` |
| `ViewSpacing` | W05 `Layout.spacing(subviews:cache:)` and its `AnyLayout`/`GridLayout` witnesses |
| `Text.Scale`, `Font.Design`, `TextAttribute`, `TextRenderer` | W11 `textScale`, `fontDesign`, `customAttribute`, `textRenderer` |
| `Font.Context` | W03 `\.fontResolutionContext` |
| `SymbolRenderingMode`, `Image.Scale`, `SymbolVariableValueMode`, `SymbolColorRenderingMode` | W13 `symbolRenderingMode`, `imageScale`, `symbolVariableValueMode`, `symbolColorRenderingMode` |
| `ScrollEdgeEffectStyle` | W10 `scrollEdgeEffectStyle(_:for:)` |
| `TabBarMinimizeBehavior`, `ToolbarTitleDisplayMode` | W15 |
| `BlendMode`, `ShadowStyle` | W16 `blendMode`, `shadow`; W13 `ShapeStyle.blendMode`, `ShapeStyle.shadow` |
| `MaterialActiveAppearance` | W13 `materialActiveAppearance`, `ShapeStyle.*Material` |

### X2. Reasons written before the capability existed

Several reasons cite an absence that has since been filled. They are false
today, whatever the verdict.

- **"No transition system in TUIkit (no `.transition`/`AnyTransition`)"** —
  `NavigationTransition`, `MatchedTransitionSourceConfiguration`,
  `SymbolEffectTransition`, `Namespace`. `AnyTransition`, `TransitionModifier`,
  `DepartureStore` and `withAnimation` all ship
  (`Sources/TUIkitEffects/Animation/AnyTransition.swift`).
- **"TUIkit has no Font type"** — `ToolbarTitleDisplayMode`. `Font` ships
  (`Sources/TUIkitFoundation/Styling/Font.swift`).
- **"There are no shapes, no ShapeStyle"** — `ImagePaint`. `ShapeStyle`,
  `AnyShapeStyle` and four gradient styles ship (`Sources/TUIkitFoundation/Styling/`).
- **"Never composites colour"** — `ColorRenderingMode`. Opacity is real
  compositing in encoded sRGB (`Documentation/Colour and styling/Opacity as composition.md`), and
  until 2026-09-04 it was done in linear light.
- **"Custom keys on a Transaction that does not exist"** — `TransactionKey`.
  `Transaction` ships (`Sources/TUIkitCore/Animation/Transaction.swift:15`).
- **"No window-activation state"** — `MaterialActiveAppearance`. TUIkit enables
  focus reporting (DEC 1004, `App.swift:692`) and publishes `\.appearsActive`
  (`ScenePhaseEnvironment.swift:127`).
- **"Spring curves ... need a continuous timeline"** — the `Spring*`/`*.spring*`
  family. `Animation.spring(duration:bounce:)`, `.smooth`, `.snappy` and
  `.bouncy` ship as closed-form springs (`AnimationCurve.swift:24`).
- **"No way to place a bitmap in a cell"** — the `image:` family. `Image` draws
  bitmaps as half-blocks or Braille everywhere, and as real pixels through Kitty
  placeholders where the terminal supports them (compat doc §2.4).
- **`VisualEffect.brightness/contrast/grayscale/hueRotation/saturation` under
  "per-pixel shading"** — the same five effects ship as `View` modifiers that
  rewrite cell colours (`Sources/TUIkitEffects/Modifiers/ColorEffectModifiers.swift`).

### X3. The map's reasons are truncated

28 `notImplemented` reasons end mid-word: `AccessibilityAdjustmentDirection`,
`AssistiveAccess`, `BlendMode`, `Circle`, `ColorMatrix`, `ColorRenderingMode`,
`ContainerRelativeShape`, `Edge.Corner`, `GeometryEffect`,
`GeometryProxy.containerCornerInsets`, `GeometryProxy.safeAreaInsets`,
`ImagePaint`, `InsettableShape`, `MatchedTransitionSourceConfiguration`,
`Namespace`, `NavigationTransition`, `PreviewProvider`, `ProjectionTransform`,
`SafeAreaRegions`, `ScenePadding`, `ScrollEdgeEffectStyle`,
`SectionedFetchRequest`, `Shape`, `StrokeStyle`, `SymbolRenderingMode`,
`SymbolVariableValueMode`, `Text.Layout`, `TextInputFormattingControlPlacement`.

So are 31 `differentShape` reasons and 5 `renamed` ones. They appear to have
been cut at about 250–300 characters when they were written. For `Edge.Corner`
the cut removes the whole reason: it stops at "Edge is fully at parity except
`C". Whatever survives the review needs its reason rewritten anyway.

### X4. Two precedents that disagree: "inert on macOS too"

- **`DynamicTypeSize` shipped.** macOS SwiftUI reads `.large` and ignores
  written sizes, so a settable, inert channel matches macOS exactly.
- **`submitLabel` was removed.** It was "a value nothing read".

Measured on macOS 15.8 (`w17/probe/p.swift`, offscreen `NSHostingView`), and
from Apple's own doc comments:

| API | macOS SwiftUI behaviour |
|---|---|
| `.submitLabel(.send)` | pixel-identical to no modifier |
| `.sensoryFeedback(.success, …)` | pixel-identical; doc: "Only plays feedback on iOS and watchOS" (most feedback kinds; the press, release and selection kinds say "visionOS") |
| `ToolbarTitleDisplayMode.inline` / `.automatic` | doc: "This has no effect in macOS" |
| `TabBarMinimizeBehavior.automatic` | doc: on macOS, minimizes when the window has reduced space. **Not** inert. |

These need one owner ruling (§O8) rather than case-by-case drift.

### X5. "A guarantee the medium keeps for free is honoured"

The compat doc already has this rule (lines 36–40; `MediumGuaranteedModifiers.swift`).
It applies to several refusals that call a TRUE constant "answering a question
the caller should not be asking":

- `ViewSpacing`: TUIkit's real defaults are `HStack` 1 column and `VStack` 0 rows
  (`HStack.swift:48`, `VStack.swift:50`), with a zero-extent child charged none.
- `GeometryProxy.containerCornerInsets`: zero. A corner glyph is never inside
  the content area.
- `GeometryProxy.safeAreaInsets`: zero today, because chrome is subtracted
  first.
- `EnvironmentValues.supportsMultipleWindows`: `false`.
- `SafeAreaRegions.keyboard`: macOS has no software keyboard either.

### X6. Platform facts verified for this review

- **Swift 6.3.3 static Linux SDK** (`swiftc -typecheck -target
  aarch64-swift-linux-musl`, `w17/probe/lx*.swift`):

  | Present | Absent |
  |---|---|
  | `CGRect`, `AffineTransform`, `AttributedString`, `AttributeScopes`, a custom `AttributeScope` with an `AttributeDynamicLookup` subscript, `FoundationAttributes.link` | `CGAffineTransform`, `FileWrapper`, `AttributedString(markdown:)`, `inlinePresentationIntent` |

  `Formatter.getObjectValue(_:for:errorDescription:)` exists but is `internal`.
- **macOS SwiftUI**, measured as `fittingSize`, in points:

  | API | Without → with | macOS honours it |
  |---|---|---|
  | `Font.leading(.loose)` / `(.tight)` | 48 → 52 / 44 (3 lines) | yes |
  | `controlSize(.large)` / `(.mini)` on a `Button` | 35×20 → 35×28 / 24×13 | yes |
  | `textScale(.secondary)` | 68 → 61 wide | yes |
  | `imageScale(.large)` | 17×16 → 23×20 | yes |
  | `fontDesign(.serif)` | 31 → 34 wide | yes |
  | `scenePadding()` | 20 pt on every edge (7×16 → 47×56) | — |
  | `symbolRenderingMode(.hierarchical)` | pixels differ even for single-layer `star` | yes |
  | `submitLabel`, `sensoryFeedback`, `contentShape(Rectangle())` | pixel-identical | no |

---

## WRONG — implementable

### W1. Shapes — 26 keys

`Shape`, `Path`, `AnyShape`, `ShapeView`, `ShapeRole`, `InsettableShape`,
`FillShapeView`, `StrokeShapeView`, `StrokeBorderShapeView`, `FillStyle`,
`StrokeStyle`, `RoundedRectangle`, `UnevenRoundedRectangle`, `Capsule`,
`Circle`, `Ellipse`, `ContainerRelativeShape`, `ConcentricRectangle`,
`RoundedCornerStyle`, `RectangleCornerRadii`, `RoundedRectangularShape`,
`RoundedRectangularShapeCorners`, `OffsetShape`, `RotatedShape`, `ScaledShape`,
`TransformedShape`. The `Rectangle` gap in W13 belongs here too.

**What the refusals say, and why they fail.** "A cell grid has no partial
coverage", "TUIkit has no path rasterizer", "a radius needs sub-cell coverage",
"line width is exactly one cell". TUIkit already rasterizes arbitrary RGBA
images to cells:

- `TUIkitImage/ASCIIConverter` covers half-blocks, quadrants, Braille and shape
  matching.
- Kitty pictures are sent where supported (`Image+TerminalGraphics`,
  `TerminalImageStore`).
- `EllipticalGradient` and `RadialGradient` already compute "a circle as a
  staircase" corrected for the 2:1 cell, and send it as a per-pixel picture on
  graphics terminals (`GradientRaster.swift`).
- Partial coverage becomes alpha, and the opacity compositor resolves alpha
  against what is behind (`OpacityBlend.swift`). That is antialiasing.
- A path is coordinates. Rotating, scaling, offsetting or trimming it is
  arithmetic before rasterization, not rotating glyphs, so the
  Rotated/Scaled/Offset/TransformedShape refusals conflate the two.

**What a shape means in TUIkit.** Two render paths behind one `Shape` protocol.

1. **Rectangle family, box-drawing fast path.** This covers rectangular paths
   whose edges land on cell boundaries: `Rectangle`, `RoundedRectangle`,
   `UnevenRoundedRectangle`, `Capsule`, `ContainerRelativeShape` and
   `ConcentricRectangle`.
   - `fill(_:)` paints the cells with the style's `Paint`, so gradients come
     free (`PaintRenderer.swift`).
   - `stroke`/`strokeBorder` draw a `BorderStyle` box through
     `BorderRenderer.swift`.
   - **Corner radius zero → `┌`, non-zero → `╭`, decided per corner.**
     `BorderStyle` already stores four independent corner characters
     (`BorderStyle.swift:13-22`), so `UnevenRoundedRectangle` and
     `RectangleCornerRadii` are *exactly* representable. The
     `UnevenRoundedRectangle` refusal cites that very fact.
   - `RoundedCornerStyle`: `.circular` and `.continuous` differ by less than one
     sub-cell unit. Both draw `╭`, which is quantisation and not a dropped
     request (SwiftUI's two styles are near-identical at small radii too).
   - A one-row `Capsule().fill` is `▐████▌`. Those are
     `TerminalSymbols.openCap`/`closeCap` (`TerminalSymbols.swift:18-21`),
     already TUIkit's capsule vocabulary for `TextField`.
   - `ContainerRelativeShape` and `ConcentricRectangle` resolve to the
     enclosing container's corner glyphs. The container publishes its
     `BorderStyle` through the environment, which is what W05's
     `containerShape(_:)` would set.
2. **Everything else, rasterizer path.** `Circle`, `Ellipse`, custom `Shape`
   conformers, transformed shapes, `trim(from:to:)`, dashed or wide strokes:
   - Flatten the path's curves and compute coverage at sub-cell resolution:
     non-zero or even-odd fill (`FillStyle.eoFill`), and a distance-to-polyline
     stroker for width, caps, joins, dashes and miter limit (`StrokeStyle`).
   - Write coverage × style colour into an `RGBAImage`. Hand it to
     `ASCIIConverter` (`.blocks(.fine)`), or to the Kitty picture path on
     graphics terminals.
   - Composite it with the opacity rules.
   - `FillStyle.isAntialiased: false` thresholds coverage instead of blending
     it.
   - Small members:

     | Member | Implementation |
     |---|---|
     | `AnyShape` | a box |
     | `ShapeRole` | `.separator` → `Palette.border` |
     | `InsettableShape.inset(by:)` | path arithmetic |
     | `Shape.layoutDirectionBehavior` | constant |
     | `Shape.sizeThatFits` | a flexible default |

   - Animatable conformances: `RoundedRectangle.animatableData` is its corner
     size, and so on.
3. **Not in this cut.** Leave out `Path`'s boolean set operations
   (`union`/`intersection`/`subtracting`, macOS 14) and `Path.strokedPath`
   (outline of a stroke as a path). Both need exact geometric clipping or
   offsetting. Absent, they fail to compile. Mask-level versions are possible
   later for fills.

**Platform caveat.** `CGAffineTransform` is absent on Linux (verified), and
`TransformedShape`, `Shape.transform(_:)` and `Path.applying(_:)` take one.
Declaring `CGAffineTransform` under `#if !canImport(CoreGraphics)` is what
swift-corelibs-foundation itself did for `CGRect`. The lower modules must stay
Windows-clean, so put shapes in the `TUIkit` umbrella module or confine the
rasterizer to `TUIkitImage`, which is pure math. *(2026-10-08: since module
split step B1 the umbrella holds only re-exports; that module is
`TUIkitFoundation`.)*

**Owner sub-decision: the unit of `path(in:)`.** See §O0. Recommendation:
square units, x in columns and y in half-rows.

**Effort.** Rect tier: protocol, `Path` value type with all builders, the six
rect shapes, the view types, corner types and `AnyShape` — **L, about 1
day**. Rasterizer tier: **L, 2–3 days**. They cannot ship apart: a public
`Shape` protocol invites custom conformers, which need the rasterizer.

This also unblocks: `background(_:in:)`, `overlay(_:in:)`, `clipShape`
(rects clip to the frame; other shapes mask cells at coverage ≥ ½),
`contentShape`, `containerShape`, `buttonBorderShape`, and later `Canvas` and
`GraphicsContext` (§D3).

### W2. `Namespace` — S

- **What the API must do:** mint a stable, unique `Namespace.ID` per view
  identity.
- **How:** a `DynamicProperty` property wrapper storing an ID in
  `StateStorage`, the same slot mechanism as `@State`.
- **Why the reason fails:** "exists to scope `matchedGeometryEffect`" is
  incomplete. W09's `focusScope(_:)`, `prefersDefaultFocus(_:in:)` and
  `ResetFocusAction(in:)` all take a `Namespace.ID` (X1). Its own reason is
  also stale (X2).

### W3. `AutomaticNavigationTransition` — S

`NavigationTransition.automatic` is what `NavigationStack` already does
(`NavigationStack.swift`). The entry concedes that. Naming it is honouring it.
Ship it with the `NavigationTransition` type (§P7).

### W4. `ContentTransition` — M

Keys: `ContentTransition`, plus W12's `View.contentTransition(_:)` and
`\.contentTransition`.

- **What it must do:** animate a change *within* one view under an animated
  transaction.
- **Why the reason fails:** "A cell holds one glyph with no alpha, so there is
  no representable intermediate" was overtaken by opacity compositing. Colours
  cross-fade exactly, glyphs swap at ½, and matching characters never snap
  (`Opacity as composition.md`).
- **How:** keep the outgoing buffer in a departing slot
  (`TUIkitView/Animation/DepartingSlot.swift`, `DepartureStore.swift`) and
  composite outgoing → incoming per frame.

| Case | Meaning in TUIkit |
|---|---|
| `.identity` | no animation |
| `.opacity` | cross-fade |
| `.interpolate` | Cells whose characters match keep the glyph and interpolate colour (`ColorAnimation.swift`). The rest use opacity, which is SwiftUI's own documented fallback ("Any changes that can't show an interpolated animation use an opacity animation instead"). |
| `.numericText` | Apple's doc promises the special roll only "in certain environments", so cross-fading the changed characters honours it. A whole-row digit roll inside a clipped row is an optional later upgrade. |
| `.symbolEffect` | cross-fade |

`contentTransitionAddsDrawingGroup` is a rendering-strategy hint with no visible
contract, so accepting it changes nothing either framework promises.

### W5. `BlendMode` — M

Keys: `BlendMode`, plus W16's `View.blendMode` and W13's `ShapeStyle.blendMode`.

- **Why the reason fails:** "There is no blend function to name" describes
  `FrameBuffer.composited(with:at:)`. But `.opacity` already renders its subtree
  as a layer and blends every cell against the cell beneath
  (`OpacityBlend.swift` `blend(…)`, `OpacityResolution.swift`). A blend mode is
  the same pipeline with a different colour function.
- **Separable modes** — `multiply`, `screen`, `overlay`, `darken`, `lighten`,
  `colorDodge`, `colorBurn`, `softLight`, `hardLight`, `difference`,
  `exclusion`, `plusDarker`, `plusLighter` — work per channel in encoded sRGB,
  the space TUIkit already composites in to match SwiftUI.
- **Non-separable modes** — `hue`, `saturation`, `color`, `luminosity` — go
  through `Color+ColorSpaces.swift`.
- **Porter–Duff modes** — `sourceAtop`, `destinationOver`, `destinationOut` —
  decide which layer's glyph and field survive, using the opacity glyph rules.
- **Same as opacity:** the destination's foreground is never tinted, and glyph
  contests follow the existing ½ rule.

### W6. Animation vocabulary — 14 keys, S–M each

All refused on maintenance or "not useful here" grounds, none on a medium
limit.

- **`Spring` (S–M).** Pure math, and TUIkit already owns the closed form
  (`AnimationCurve.spring(omega:zeta:)`, `AnimationCurve.swift:24`).
  - Expose every SwiftUI initializer: `duration:bounce:`,
    `response:dampingRatio:`, `mass:stiffness:damping:allowOverDamping:` and
    `settlingDuration:dampingRatio:epsilon:`.
  - Also the parameters, `value`/`velocity`/`force`/`settlingDuration`
    (closed form with initial velocity), `update(value:velocity:target:deltaTime:)`,
    and the `.smooth`/`.snappy`/`.bouncy` presets.
  - Put it in `TUIkitCore`, which is Windows-safe.
  - The reason "nothing in a terminal integrates motion" is a judgement.
    `SpringKeyframe` and `Animation.spring(_:blendDuration:)` both need the
    type.
- **`Animation.interpolatingSpring`, `(mass:stiffness:damping:initialVelocity:)`,
  `(duration:bounce:initialVelocity:)` (S).**
  - The refusal: "velocity-preserving on retarget; TUIkit carries position
    only".
  - But TUIkit's shipped `.spring` already retargets at rest where SwiftUI's
    preserves velocity. The deviation is common to every spring and belongs in
    one documented place, not a reason to refuse one spelling.
  - `initialVelocity` *is* honourable in the closed form (x′(0) = v₀).
  - Semantic audit #94 (`SwiftUI semantic audit (2026-08).md`) already prescribes
    the mapping.
- **`Animation.interactiveSpring`, `(response:dampingFraction:blendDuration:)`,
  `(duration:extraBounce:blendDuration:)` (S).**
  - These are presets of `spring(response:dampingFraction:blendDuration:)`.
    Audit #94 says the same.
  - "No continuous pointer stream" is false: SGR any-motion reports a drag cell
    by cell, and `onDragGesture` delivers `.moved` continuously.
- **`UnitCurve` (S–M).**
  - The refusal: "a second formula to keep in step".
  - Make the internal `AnimationCurve.bezier` *be* `UnitCurve`'s storage, so
    there is one formula. Add the closed-form `circularEaseIn/Out/InOut`, plus
    `value(at:)`, `velocity(at:)` and `inverse`.
  - `Animation.timingCurve(_: UnitCurve, duration:)` then follows.
- **`AnimationCompletionCriteria` (S–M)**, with W12's
  `withAnimation(_:completionCriteria:_:completion:)` and
  `Transaction.addAnimationCompletion`.
  - The store already retires an animation on the first frame past its
    duration. That is the completion point.
  - For a TUIkit spring the duration *is* the settling envelope, so
    `.logicallyComplete` and `.removed` fire on the same frame. Document it
    rather than refuse.
- **`TransactionKey` (S).** `Transaction` exists. Add a keyed store, the
  `subscript<K: TransactionKey>`, and `withTransaction(_ keyPath:_:_:)`.
  `Transaction` is `Equatable`, so stored values must take part in `==` — which
  is what SwiftUI's `TransactionKey` requirement is for.
- **`View.animation(_:)` (S).**
  - The live symbol is **not** the deprecated one. SwiftUICore declares a
    *second* overload, `extension View where Self: Equatable`, available since
    macOS 12 and not deprecated. It animates when the view's own value changes,
    i.e. `animation(a, value: self)`.
  - The reason ("the unscoped form, deprecated") describes the other overload.
  - Ship the `Equatable` one and leave the deprecated one out.
- **`View.animation(_:body:)` (M).**
  - Render `body(PlaceholderContentView(self))` with the transaction overridden
    for the modifiers inside `body`.
  - The placeholder restores the outer transaction for `self`.
  - `TransactionModifier` and `AnimationValueModifier` already read the
    transaction from the render context.
  - The refusal is about composition-rule complexity, not the medium.
- **`AnyTransition.push(from:)` (S).**
  - SwiftUI's own doc defines it as moving in from `edge` while fading in, and
    out toward the opposite edge while fading out.
  - That is `.asymmetric(insertion: .move(edge: e).combined(with: .opacity),
    removal: .move(edge: opposite).combined(with: .opacity))`. Every piece
    ships, and the departing half is exactly what `DepartureStore` already
    animates.
  - W12 plans `PushTransition` anyway.
- **`AnyTransition.modifier(active:identity:)` (S once W12's `Transition`
  protocol lands, M with it).**
  - The SwiftUI-shaped `ViewModifier` landed in 2017efa46. W12's
    `Transition.body(content:phase:)` is the same mechanism: content rendered
    through modifiers per phase.
  - The real cost is a re-render per frame for the transition's duration
    instead of a buffer transform. It is opt-in and the same cost
    `withAnimation` already pays for animatable modifiers.

### W7. Layout and geometry vocabulary — 8 keys, S each

- **`ViewSpacing`.**
  - `distance(to:along:)` answers TUIkit's actual rule: 1 column horizontally,
    0 rows vertically, 0 against a zero-extent child (compat doc §3, "A child
    with no extent takes no stack spacing"). Add `formUnion`, `union` and
    `.zero` beside it.
  - Wire it to W05's `Layout.spacing(subviews:cache:)` and `LayoutSubview.spacing`.
  - Why it matters: Apple's own sample layouts (`FlowLayout`, equal-width
    stacks) call `subviews[i].spacing.distance(to:along:)`, so they port
    unchanged.
  - The constant is TRUE (X5).
- **`SafeAreaRegions`.**
  - W05 plans `ignoresSafeArea(_:edges:)`, which takes one.
  - `.container` means the region W05's `safeAreaInset` bars, and any future
    chrome overlay, occupy.
  - `.keyboard` is empty, as it is on macOS (X5).
- **`ScenePadding`.**
  - `scenePadding()` is "the recommended spacing around the root view of a
    window" (20 pt on macOS, measured).
  - TUIkit already picks platform defaults: `.padding()` is 1 cell
    (`View+Layout.swift:393`). Choose the scene margin the same way: 1 cell, or
    the app header's title indent. `.minimum` is that value.
  - "A terminal exposes no such metric" — nor does a terminal expose the
    `.padding()` default. TUIkit chose that one too.
- **`GeometryProxy.safeAreaInsets`.**
  - `.zero` is TRUE today, because chrome is subtracted before layout.
  - It must become real if W05's `safeAreaInset` lets content run under a bar.
  - The in-tree note at `GeometryReader.swift:17-24` and compat doc §4b argue
    "answering a question the caller should not be asking". That contradicts the
    guarantee rule (X5) and needs rewriting along with this.
- **`GeometryProxy.containerCornerInsets`, `RectangleCornerInsets`,
  `EdgeInsets.inset(by:edges:)`.**
  - The value is `.zero`, and TRUE: a corner glyph sits in the border cell,
    never in the content area.
  - The types are four cell sizes; the `EdgeInsets` arithmetic is trivial.
  - Low value, zero risk.
- **`Edge.Corner`** (with `.Set` and `.Style`).
  - The four corners of a rectangle, and cells have corners.
  - Consumers: `RoundedRectangularShapeCorners`, `Shape.rect(corners:)`, W05's
    `containerCornerOffset`.
  - Its reason is truncated (X3).

### W8. `Text.Scale` — S

- `.secondary` is "a logical text scale relative to the base font". macOS
  shrinks the text about 10% (68 → 61 pt, measured).
- The `Font` precedent already maps "smaller" to "subordinate":
  `.caption`/`.footnote` → faint (`Font.swift`, `defaultAttributes`).
- So `.textScale(.secondary)` steps one intensity tier down: bold → plain →
  faint. That is the same reading that made all eleven `Font` styles ship.
- The refusal ("cannot be a size") states the premise `Font` overturned.

### W9. `ImagePaint` — M

Keys: `ImagePaint`, with W13's `ShapeStyle.image(_:sourceRect:scale:)`.

- **What it is:** a `Paint` that samples an image's RGBA per cell, honouring
  `sourceRect` and tiling `scale`.
- **The pattern exists:** `RampSampler` (`PaintRenderer.swift:473`) samples
  gradients per cell, and gradient foregrounds on text already work.
- **Graphics terminals:** over blank cells it can be sent as a picture, as
  gradients are.
- **Why the reason fails:** "no ShapeStyle" is stale (X2).

---

## PARTLY WRONG

### P1. `Font.Design` — S

Ship `.default` and `.monospaced` and omit `.serif` and `.rounded`, so
`.fontDesign(.serif)` fails to compile.

- `.monospaced` is a guarantee, like `.monospaced()` in
  `MediumGuaranteedModifiers.swift`.
- `.default` is what the terminal draws.
- This is the `TextFieldStyle` pattern (`.roundedBorder` omitted).
- It also unlocks W11's `fontDesign(_:)` and `Font.system(_:design:weight:)`
  (§P10).
- **Why it's only partly wrong:** "TUIkit cannot honour any case" is too
  strong. Serif and rounded *are* unhonourable: measured on macOS, `.serif`
  changes the width (31 → 34 pt).

### P2. `Font.Resolved`, `Font.resolve(in:)`, `Font.Context`, `\.fontResolutionContext` — S–M, low value

Resolve through the style cascade, which is meaningful because a theme can
redefine `.headline`.

- **Ship** `isBold`, `isItalic`, `weight`, `isMonospaced` (always true) and the
  three small-caps flags (always false, truly).
- **Omit** `ctFont` (CoreText, absent on Linux and Windows), `pointSize`,
  `width` and `leading`, so those spellings fail to compile.

### P3. `ContentShapeKinds` — S–M, with W16's `contentShape`

| Kind | Verdict |
|---|---|
| `.interaction` with `Rectangle` | Already TUIkit's behaviour: hit regions are the view's frame (`HitTestRegion.swift`), so a guarantee. |
| `.interaction` with other shapes | A cell mask from the W1 rasterizer, so the dispatcher needs masked regions. |
| `.dragPreview` | Clip the drag preview TUIkit already draws (`DragAndDrop.swift`). |
| `.focusEffect` | Omit; TUIkit draws no focus ring to shape. |
| `.contextMenuPreview`, `.hoverEffect` | Inert on macOS too, which makes them an §O8 question. |
| `.accessibility` | Omit. |

`.contentShape(Rectangle())` is among the most-ported idioms. Measured, it is
pixel-identical on macOS, since its effect is only on hit-testing.

### P4. `SymbolEffectTransition` — M, with W12's `symbolEffect`

The reason ("no transition system") is stale (X2).

- **Implementable on a single glyph through the opacity compositor and
  `AnimatedCellRun`:** appear and disappear (fade), replace (cross-fade),
  pulse, breathe.
- **Need glyph geometry or layers, so their types are omitted:** bounce, scale,
  wiggle, rotate, variableColor.
- **Caveat:** the `SymbolEffect` protocols live in Apple's Symbols framework,
  absent on Linux, so TUIkit would declare its own effect types under the same
  names.

### P5. Family `["Accessibility*", "AX*", "*.accessibility*", "View.accessibility*", "*.speech*"]`

- **CONFIRM** for everything that feeds an AX tree: labels, hints, values,
  traits, rotors, actions, custom content, heading levels, children, drag/drop
  points, hidden, `accessibilityRepresentation` and the speech attributes.
  Nothing outside the process can read app-side metadata.
- **Wrong for the user-preference reads** the glob swallows:
  - `\.accessibilityReduceMotion`, `…DifferentiateWithoutColor`,
    `…ReduceTransparency`, `…DimFlashingLights`, `…PlayAnimatedImages`,
    `…InvertColors`, `…ShowButtonShapes` / `…ShowBorders`,
    `…VoiceOverEnabled`, `…SwitchControlEnabled`, `accessibilityEnabled`.
  - These are not AX-tree metadata. They describe the *user*, and TUIkit has
    the motion and colour-only cues they exist to modulate: breathing focus,
    spinners, transitions, focus-by-colour.
  - Where the value comes from is §O1.

### P6. Family `["*Gesture", "*GestureMask*", "GestureState*", "View.gesture*", "View.highPriorityGesture*", "View.simultaneousGesture*"]` — L

**Implementable**, built on `MouseEventDispatcher.swift`, `DragGestureModifier.swift`
and `onTapGesture` (`View+Events.swift`):

- The `Gesture` protocol with `onChanged`, `onEnded`, `updating`, `map`,
  `modifiers(_:)` (Shift, Alt and Ctrl come in the SGR mouse modifier bits) and
  `AnyGesture`.
- `DragGesture` (`Value` with location, startLocation, translation, time,
  velocity and predictedEnd*).
  - TUIkit's `DragGestureEvent` already carries location, start and
    translation in cells (`View+Events.swift:245-274`).
  - Velocity comes from report timestamps, which is also how a Mac mouse
    produces it.
- `TapGesture(count:)`, `SpatialTapGesture`, and `LongPressGesture` (press and
  release are timed).
- `GestureState` and `GestureStateGesture`.
- `simultaneously`/`sequenced`/`exclusively`, with
  `SimultaneousGesture`/`SequenceGesture`/`ExclusiveGesture`.
- `gesture`/`highPriorityGesture`/`simultaneousGesture` with `GestureMask`
  arbitration.
- Geometry in cells (§2.2).

**Why the reason fails:** it claims "no velocity, no simultaneous touches". A
Mac mouse has no simultaneous touches either, and SwiftUI's mouse gestures work
on it.

**CONFIRM:** `MagnifyGesture`/`MagnificationGesture` and
`RotateGesture`/`RotationGesture` (no terminal reports a trackpad pinch or
rotate), `WindowDragGesture` (Window family) and `SpatialEventGesture`
(visionOS).

The `differentShape` entries for `TapGesture` and `GestureState` go away with
this.

### P7. `NavigationTransition` — S, plus owner for `.zoom`

The type and `.automatic` (with W3) are trivially honoured. `.zoom(sourceID:in:)`
is §O4. The reason "no transition system" is stale.

### P8. Family `["AttributeScopes*", "AttributedTextFormatting*", "AttributeDynamicLookup*"]` — L

**Implement `Text(AttributedString)`.** The overload is invisible to the parity
tool because the key collapses onto `Text.init(_:)`.

- **Scope:** `AttributeScopes.SwiftUIAttributes` with
  - `foregroundColor` and `backgroundColor`: cells have both.
  - `font`: the semantic tiers.
  - `underlineStyle`: SGR 4, with `4:x` styles and SGR 58 colour where
    measured; iTerm2 lists `usstyle` (`Terminal compatibility survey.md:1633`).
  - `strikethroughStyle`: SGR 9.
  - Foundation's `link`, carried as OSC 8 (it ships for `Link`).
- **Dynamic lookup:** the `AttributeDynamicLookup` subscript.
- **Omit:** `kern`, `tracking`, `baselineOffset`, `lineHeight` and
  `adaptiveImageGlyph`, so they fail to compile. Take `alignment` only if
  `multilineTextAlignment` can carry it.

Verified on the Linux 6.3.3 SDK: a custom `AttributeScope` with an
`AttributeDynamicLookup` subscript compiles there.

**Not available on Linux:** `AttributedString(markdown:)` and
`inlinePresentationIntent`. SwiftUI's `Text("**bold**")` literal markdown
therefore needs a small TUIkit inline parser (`**`, `*`/`_`, `` ` ``, `~~`,
`[..](..)`), which is cross-platform. Compat §4a already lists
AttributedString/Markdown as "should add". This family contradicts it.

`AttributedTextFormatting*` (macOS 26 rich-text `TextEditor`) waits on rich
editing: defer it, not refuse it.

**CONFIRM:** the scope members named above.

### P9. Family `["*.animatableData", "Animatable*"]`

- **The reason is wrong for:**
  - `AnimatableValues` (S–M). A variadic parameter-pack `VectorArithmetic` for
    any custom `Animatable`, a general replacement for nested `AnimatablePair`.
    It has nothing to do with geometry, and Swift 6.2 has parameter packs.
  - `AnyLayout.animatableData` and `ModifiedContent.animatableData` (S). These
    are types TUIkit *has*. The rule claims it only hides conformances "on types
    TUIkit does not have".
  - `Color.Resolved.animatableData` (S, with W13's `Color.Resolved`). Colours
    already animate.
- **The shape conformances** go with W1.
- **CONFIRM:** the `CGPoint`/`CGSize`/`CGRect` conformances (compiler wall,
  verified).

### P10. Family `["Font.custom*", "Font.system*", "Font.init(_:)", "Font.pointSize*", "Font.scaled*", "Font.Width*", "Font.default", "Font.width(_:)"]`

- **Wrong:**
  - `Font.system(_:design:weight:)` (S). It takes a `TextStyle`, not a point
    size: `Font(style).weight(w)`, with design per P1.
  - `Font.default` (S). "The effective font in the environment", i.e. a value
    that resolves to the inherited font.
- **CONFIRM:** `custom(...)`, `system(size:…)`, `pointSize`, `scaled(by:)`,
  `Font.Width`/`width(_:)` and `Font.init(CTFont)`.

### P11. Family `["MeshGradient*", "Spring*", "*.spring*", "SensoryFeedback*"]`

- **`Spring` and spring animations are wrong** (W6): `Animation.spring(_:blendDuration:)`,
  `spring(duration:bounce:blendDuration:)` and
  `spring(response:dampingFraction:blendDuration:)`. `Animation.spring`
  without arguments already ships, which shows the glob is stale.
- **`SpringLoadingBehavior` is wrong (M):** `View.springLoadingBehavior`,
  `TabContent.springLoadingBehavior` and `\.springLoadingBehavior`.
  - It means activating a control by pausing over it during a drag.
  - TUIkit's in-process drag (`DragAndDropSession.swift`, plus keyboard drag)
    can time a hover-pause over a `Button` or a tab. The `*.spring*` glob caught
    it by name only.
- **`MeshGradient` is wrong (M–L).**
  - "Needs per-pixel interpolation" is exactly what `GradientRaster.swift`
    does for the other four gradients.
  - Evaluate the patch mesh per sample: a staircase in cells, a picture on
    graphics terminals.
  - `SIMD2<Float>` points are standard library.
- **`SensoryFeedback` is §O8.** On macOS most kinds are documented as not
  playing.

### P12. Family `["Label.init(_:image:)", "Button.init(_:image:*", "Toggle.init(_:image:*", "Picker.init(_:image:*", "ContentUnavailableView.init(_:image:*"]`

- **Wrong for the `image name: String` overloads**, on `Label` and
  `ContentUnavailableView` (S, after W13's `Image(_:bundle:)`).
  - The name resolves a bundle resource.
  - "No way to place a bitmap in a cell" is false (X2).
- **CONFIRM for the `ImageResource` overloads** (all of `Button`, `Toggle` and
  `Picker` here).
  - `ImageResource` is DeveloperToolsSupport's type, emitted by Xcode's
    asset-symbol generator, and absent on Linux.
  - Ported asset-symbol code would not produce a TUIkit stand-in.

### P13. Family `PhaseAnimator`, `KeyframeAnimator`, `Keyframes*`, `KeyframeTrack*`, `*Keyframe`

- **Wrong for the timeline side (M):**
  - `Keyframes`, `KeyframeTrack`, `KeyframesBuilder`,
    `KeyframeTrackContentBuilder`, `LinearKeyframe`, `CubicKeyframe`,
    `SpringKeyframe` (needs `Spring`, W6) and `MoveKeyframe`.
  - These are pure functions of time with no rendering at all.
  - W12's planned `KeyframeTimeline` cannot be written without them (X1).
- **The animator views are §O2:** `PhaseAnimator`, `KeyframeAnimator`,
  `phaseAnimator`, `keyframeAnimator`.

### P14. Family `["Shader*", "View.colorEffect*", …, "VisualEffect.*", "Glass*", …]`

- **Wrong (S, part of W12's `VisualEffect`):**
  `VisualEffect.brightness/contrast/grayscale/hueRotation/saturation`. The same
  operations ship per cell as `View` modifiers (X2).
- **`VisualEffect.blendMode`** goes with W5.
- **`Glass*`/`glassEffect*` are §O5**, with Material.
- **CONFIRM:** `Shader`/`ShaderLibrary`/`ShaderFunction` (Metal),
  `colorEffect`/`layerEffect`/`distortionEffect`, `VisualEffect.blur` and its
  shader members, and `allowedDynamicRange`/`Image.DynamicRange` (HDR).

### P15. Family `Window*` (163 symbols)

- **Wrong (S each):**
  - `ShapeStyle.windowBackground` / `WindowBackgroundShapeStyle`: the
    palette's background, the same surface `BackgroundStyle` names.
  - `\.supportsMultipleWindows`: `false`, which is true (X5).
  - `ContainerBackgroundPlacement.window`: the root surface, with W05's
    `containerBackground`.
  - The **title-taking `WindowGroup` initializers** (`init(_:makeContent:)`,
    `init(_:id:makeContent:)`, …).
    - The title becomes the terminal's window title via OSC 2.
    - Save and restore it with XTWINOPS 22/23 on exit.
    - Every measured host lists `title` (`Terminal compatibility survey.md:1633-1638`);
      record the behaviour there.
    - Titling is not opening, placing or dismissing a window, which is all the
      family's reason covers.
- **Multi-scene is §O9:** `Window` scenes, `openWindow`/`dismissWindow`/`openSettings`
  and their actions, `WindowGroup(id:/for:)`, `AlertScene`.
- **CONFIRM:** size, position, resizability, level, style, toolbar style,
  `MenuBarExtra*`, `FrameResize*`, `DisplayProxy`, `WindowDragGesture`, the
  window minimize/fullscreen/dismiss behaviours, `restorationBehavior`,
  `handlesExternalEvents`, `WindowIdealSize`, `WindowPlacement*` and
  `defaultSize`/`defaultPosition`. The user's emulator owns geometry, and
  resizing their terminal by XTWINOPS 8 would be hostile even where it works.

### P16. Family `DocumentGroup*`, `*FileDocument*`, the file panels

- **File panels are §O10:** `fileImporter`, `fileExporter`, `fileMover` and the
  `fileDialog*` customisations.
- **CONFIRM:**
  - `DocumentGroup`, `FileDocument`, `ReferenceFileDocument` and their
    configurations. They read and write through `FileWrapper`, which is
    **absent on Linux** (verified).
  - Services, `exportsItemProviders` and `importsItemProviders`
    (`NSItemProvider`, Apple-only).
  - `navigationDocument`. Minor note: Apple Terminal's proxy icon via OSC 6/7
    exists but is unmeasured, and too niche to matter.

### P17. Family `["*WritingTools*", …, "View.findNavigator*", "View.findDisabled*", "View.replaceDisabled*", "*.findContext", "FindContext*"]`

- **Wrong for the find bar (M):** `findNavigator(isPresented:)`,
  `findDisabled`, `replaceDisabled` and `FindContext`.
  - A TUIkit-drawn find/replace bar for `TextEditor`, whose text is a `String`.
  - `.searchable` already draws a field above a subtree.
  - `Find pasteboard and the remote viewer.md` declined only the *system*
    find-pasteboard sync, not an in-app bar.
- **CONFIRM:** Writing Tools (Apple's on-device models).

### P18. Family `DragSession*`, `DropSession*`, `Drag/DropConfiguration`, `DragDropPreviewsFormation`, container `draggable` — L, low priority

- **The reason fails:** "Cross-process session machinery" does not describe
  these APIs.
- **What they actually are:** macOS 26's in-app multi-item drag.
  - `dragContainer(for:in:_:)` with `dragContainerSelection`,
    `draggable(containerItemID:)`.
  - Session phase and items.
  - Allowed operations.
  - Preview formations `.list`/`.pile`/`.stack`, which TUIkit would draw.
- **All implementable** on `DragAndDropSession.swift` and List selection.
- **CONFIRM:** `DragSession.ID.matches(NSDraggingSession)` (AppKit).
- **Effort and priority:** new API, little ported code yet.

---

## OWNER DECISION

**Status, 2026-10-12.** The owner ruled on every item below; O8 and O11, whose questions were restated that day,
were ruled in his second message of the day (under each item). Each ruling is under
its item, with what was found when it was researched (session notes
`REFO/notes.md`, which has the design sketches for O10 and O13). The rulings
come to about 47 lane-days in all (estimate), sequenced after the lanes
running on 2026-10-12. The shapes lane (O0's W1) gates Glass, the
`ShapeStyle` shadow, `ButtonBorderShape`'s `Shape` conformance and the zoom
transition's source configuration.

### O0. Shapes: the unit of `Shape.path(in:)` — gates W1

- **(A) Cells** (x = column, y = row).
  - Matches `GeometryReader`.
  - A custom shape's `addEllipse(in: square)` comes out twice as tall.
  - Built-in `Circle` and friends must compensate by `\.imageCellAspect`.
- **(B) Square units**: x in columns, y in rows × cell aspect (≈2, already
  republished from the terminal's pixel size, `Image.swift:236-240`).
  - At aspect 2 one unit is exactly one half-block pixel.
  - Custom shapes come out round.
  - The rect a shape receives differs from the reader's cell size on y.
- **(C) Terminal pixels.**
  - Closest to points.
  - Unknown on some terminals, and the numbers are large.
- **Recommendation: B.** Ported shapes mostly compute from `rect.midX`,
  `rect.width * k` and the like, so they are unit-agnostic. Roundness is the
  thing a unit choice can break.
- **Price:** the same for all three. The decision only changes the transform at
  the rasterizer's input.

**Ruled 2026-10-12: keep (B).** The owner asked whether (B) has (C)'s problem
where the cell size cannot be read, and whether SwiftUI's unit is a display
unit that needs the scale factor. Half right:

- (B) and (C) read the same terminal report, but (B) needs only the cell's
  height-to-width **ratio**, in which the display scale cancels. Where the
  ratio is unknown (tmux, a host that reports zeros) TUIkit falls back to 2.0:
  within 2% on Apple Terminal and Warp, circles 6–8% too tall on Ghostty and
  21–29% on iTerm2. Even known, iTerm2's two reports disagree by about 6%.
- (C) needs an **absolute** size, whose unit is device pixels on some hosts
  and points on others, so its fallback can be wrong in scale by up to about
  2.3×; a ported `lineWidth: 2` would be 2/7 of a cell on Apple Terminal and
  2/16 on Ghostty.
- SwiftUI's unit is the point, not the pixel: `pixelLength` is documented as
  1 / `displayScale`.

Literal constants (`lineWidth`, `cornerRadius`, `dash`) are then in columns,
the same deliberate choice `.padding(20)` is. Lane owed: W1, about 12 commits
(the rect tier about a day, the rasterizer two to three).

### O1. Accessibility preference reads (from P5) — M

- **(a) Constant `false`.**
  - "The terminal offers no channel."
  - Simple, and a lie on a Mac with Reduce Motion on.
- **(b) Read the host setting when local, with an env override.**
  - macOS `com.apple.universalaccess`; GNOME `enable-animations`.
  - `TUIKIT_REDUCE_MOTION=1` etc., the `TUIKIT_OPEN_URLS` precedent.
  - TUIkit honours them itself: no breathing focus, instant transitions,
    static spinners, and non-colour focus cues for differentiate-without-colour.
- **(c) Settable only.**
- **Recommendation: (b).**
- **Conflict to resolve:** the owner rule that focus "ALWAYS breathes" would
  need a reduce-motion exception.
- **`accessibilityVoiceOverEnabled`:** leave it refused unless (b) can detect
  VoiceOver reading the terminal. A wrong `false` would mislead.

**Ruled 2026-10-12: (b), but only `TUIKIT_REDUCE_MOTION`, unless TUIkit can
be confident the terminal is on the same machine.** B53 (2026-10-04) had
already decided the stricter half and shipped it: the environment variable
plus the app-wide `Scene.reduceMotion(_:)`, OR-combined, and explicitly not
the host's setting, because the machine an app runs on need not be the one its
user sits at. The conflict above was settled on 2026-10-05 (A-D3M-1): reduce
motion means movement in x and y, so the focus breath, spinners and the caret
keep moving.

TUIkit can be confident by positive evidence, with the test the clipboard
already uses (`ClipboardLocality`): no `SSH_*` variable, no remote-session
daemon or session keeper among the process's ancestors, and inside tmux
every attached client passing the same test. Where it says local, the host's
Reduce Motion can be OR'd in, in the app runner only, and re-read when the
terminal regains focus; a wrong "local" can only add reduced motion. Lane
owed: about a day (a refactor that gives the three locality rules one home
first), with B53's docs. Until it lands, B53's rule is the behaviour. Still
the owner's: whether to extend the host read to reduce transparency,
differentiate without colour and contrast. `accessibilityVoiceOverEnabled`
stays refused: every non-local session would answer a wrong `false`.

**Shipped 2026-10-14.** The locality rules have one home, `SessionLocality`
(the clipboard's test, and the cell-points calibration's environment-only
one beside it). `HostReduceMotionRefresher` reads macOS's
`com.apple.universalaccess` `reduceMotion`, or GNOME's `enable-animations`
through `gsettings`, off the main actor at launch and on every focus-in, and
counts it only where `SessionLocality.isLocal()` holds. The render loop ORs it
into the root with `TUIKIT_REDUCE_MOTION`.

### O2. `PhaseAnimator` / `KeyframeAnimator` views (from P13) — M + M

- **The reason fails:** "pre-rendering a subtree once per phase runs its side
  effects once per phase" rules out one *implementation*, the pre-rendered
  run.
- **SwiftUI's own model is live:** the current phase is state, each step is a
  `withAnimation` with the phase's animation, and completion advances it (needs
  W12's completion criteria). The animatable modifiers inside interpolate per
  frame.
- **The cost:** continuous per-frame renders while it runs. TUIkit already
  accepts exactly that for `TimelineView(.animation)` (`AnimationTimelineSchedule`)
  and for any running `withAnimation`.
- **Options:**
  - (a) keep refused;
  - (b) ship live, documenting that a repeating one renders every frame;
  - (c) ship live and detect phases that differ only in colour, replaying them
    as `AnimatedBufferCycle`.
- **Recommendation: (b) now, (c) as an optimisation.**

**Ruled 2026-10-12: (b), and (c) if it is easy.** It is not: replaying
colour-only phases means rendering the subtree once per phase, which
multiplies its side effects, and a measuring render does not isolate them
soundly (each persistent write is gated by hand, and the memo verifier cannot
see the class). So (c) is presented after (b), not built with it. Lane owed:
(b), about two days: `PhaseAnimator` and `KeyframeAnimator` as views with real
bodies, and their four modifiers. A37 follows it.

**(b) shipped 2026-10-14**, with A37, after measuring SwiftUI
(`Tools/SwiftUIProbes/Animation curves, springs and keyframes/p9.swift`), whose
documentation disagrees with it twice. A phase animator's trigger runs through
every phase and back to the first, not one step; a keyframe animator replays
from its initial value, not from the end value. A step into a phase is a
`withAnimation` with that phase's animation, the next starting when it is
logically complete; keyframes play on the frame clock through a
`TimelineView(.animation)`, paused at rest. Keyframes restarted part-way carry
no velocity, TUIkit's keyframes taking no initial velocity.

### O3. `CustomAnimation` family — M

- **The reason fails:** "State between frames forbids pre-sampling" is false
  for the non-retargeted case. `animate(value:time:context:)` is deterministic
  given its call sequence, so TUIkit can integrate it once at the frame cadence
  until it returns `nil` and replay the samples like any curve.
- **What it really breaks:** retargeting (`shouldMerge`, velocity) does break
  the closed-form model.
- **Options:**
  - (a) refuse;
  - (b) pre-sample, with retargets restarting from rest — TUIkit's spring
    deviation;
  - (c) live only.
- **Recommendation: (b).**

**2026-10-12: detect, else live.** The owner asked whether TUIkit can detect
when pre-sampling is viable, use it then, and fall back to running live. It
can, with no detection step: integrate each custom animation lazily on the
frame grid, one frame at a time, memoising every step. If it finishes
(`animate` returns `nil`), the memo is the pre-sampled table, and repeat,
autoreverse, speed and delay work as for the built-in curves; if not, it keeps
extending live. Reads are quantised to the frame clock, so the measure walk,
the render walk and a discarded pass agree. A retarget to the same custom type
follows SwiftUI's contract (merge if `shouldMerge` says so, else run both and
add); a retarget onto a built-in curve restarts from rest, as today (B55,
B58). Capping the records per slot (about 8) bounds the cost at about 8 calls
a frame. Lane owed: about two and a half days. A38 follows it.

### O4. Matched geometry: `MatchedGeometryProperties` (+ W12 `matchedGeometryEffect`); zoom: `MatchedTransitionSourceConfiguration`, `EmptyMatchedTransitionSourceConfiguration` (+ W09 `matchedTransitionSource`, `NavigationTransition.zoom`)

**What it must do:** carry a view from the source's `CellRect` to its own.
`CellRect` is already `Animatable` (`AnimatableGeometry.swift`).

| Option | Behaviour | Cost |
|---|---|---|
| (a) | Position only: move the rendered buffer in whole cells, like `.move`/`.offset`; size snaps | M |
| (b) | Full frame: lay out at the interpolated size each frame | L; a re-layout per frame while animating |
| (c) | Refuse | — |

Zoom is a reveal from the source rect to the full destination, the
`.scale`-from-anchor machinery generalised (M after (a) or (b)). Its source
configuration (background, `clipShape`) needs W1.

**Recommendation:** (b), using (a) as the fast path when the sizes are equal.
Matched geometry first, zoom after.

**Ruled 2026-10-12: (b) as the baseline, (a) where possible.** `Namespace`
and A2's geometry have shipped. Lane owed: `matchedGeometryEffect` about
three to four days, then the zoom transition with `matchedTransitionSource`,
whose source configuration needs W1. A23 and A36 follow it.

**Matched geometry shipped 2026-10-18**
(`Sources/TUIkitEffects/Geometry/MatchedGeometryEffect.swift`, the groups in
`Sources/TUIkitFoundation/Geometry/MatchedGeometryRegistry.swift`; Deliberate
deviations A8, decisions O4).
**The zoom transition shipped 2026-10-18** (`ZoomNavigationTransition`,
`matchedTransitionSource` and the source configuration's `background(_:)`,
`Sources/TUIkitNavigation/Views/NavigationZoom.swift`; Deliberate deviations
A9). The configuration's `clipShape(_:)` and `shadow(color:radius:x:y:)` wait on
W1 and O6 (decisions O4, B-O4-6).

### O5. Materials and Glass: `MaterialActiveAppearance`, plus differentShape `Material`, W13's `*Material`, `\.backgroundMaterial`, P14's `Glass*`

- **(a) Keep the substitution:** `dimmed()`/`overlayBackground`.
- **(b) A material is a translucent palette surface composited over what is
  behind.**
  - Thickness maps to alpha: `.ultraThin` lowest through `.ultraThick` highest.
  - No blur.
  - Active appearance follows `\.appearsActive` (terminal focus, DEC 1004).
- **(c) Glass as (b) plus a highlighted border.**
- **Recommendation:** (b) for Material (M), and defer Glass.

**Ruled 2026-10-12: (b) for Material and for Glass.** No blur unless an
insight makes it much simpler, and one does: at cell resolution a blur's job
is to remove detail, and the detail is the glyphs. A frosted material can drop
the glyphs beneath it, give each cell the average of its neighbours'
effective colours (which the opacity compositor already resolves) and tint
that; only a glyph's coverage is new, and a constant table answers it. That is
an optional add-on of about two days, offered once (b) shows in the Example.
Lane owed: the materials about a day; Glass one to two days after W1, since
`glassEffect` takes a `Shape`. A41 follows it.

**Materials shipped 2026-10-18** (`Sources/TUIkitFoundation/Styling/Material.swift`,
Deliberate deviations C5); Glass and the frosted add-on are still owed.

### O6. `ShadowStyle` (+ W16 `shadow`, W13 `ShapeStyle.shadow`) — M

**What it would be:** the classic TUI drop shadow. The cells under the view's
footprint, offset by (x, y) cells, are darkened by compositing a translucent
shadow colour. `radius` is an alpha falloff across that many cells; `.inner`
darkens inside the edges.

**The real hazard is units.** A ported `radius: 8` becomes 8 cells.

- **(a) Refuse.**
- **(b) Cells as-is**, consistent with `.padding(8)`.
- **(c) A points-to-cells scale for shadows only**, which is inconsistent.

**Recommendation: (b), documented.** Choose (a) only if cell-radius shadows
look too heavy in the Example.

**Ruled 2026-10-12: (b), cells as-is**, documented. Lane owed: about two days;
`ShapeStyle.shadow` after W1.

**`View.shadow(color:radius:x:y:)` and `ShadowStyle` shipped 2026-10-18**
(`Sources/TUIkitFoundation/Modifiers/ShadowModifier.swift`, Deliberate
deviations C10, decisions [Shadows (O6)](<Decisions/Shadows (O6).md>)).
`ShapeStyle.shadow(_:)`, the one consumer of a `ShadowStyle` and so the only
route to `.inner`, is still owed after W1.

### O7. `ScrollEdgeEffectStyle` (+ W10 `scrollEdgeEffectStyle`/`Hidden`) — S–M

- **`.hard`:** a divider rule where content passes under a bar.
- **`.soft`:** an opacity fade over the edge rows.
- **Today it would correctly draw nothing.** No content passes under chrome,
  just as SwiftUI shows no pocket without a bar.
- **It becomes visible** once W05's `safeAreaBar`/`safeAreaInset` lets content
  scroll beneath.
- **Recommendation:** decide together with the W05 safe-area design. Ship if
  bars overlay content.

**Ruled 2026-10-12: only `.hard`; no `.soft` in the API**, so that mimicking
content sliding under a bar fails to compile. What that reaches: only code
that names `.soft` (a macOS 26 API) fails to compile. The idiom itself, a
`safeAreaBar` or a toolbar over a `ScrollView`, still compiles and draws
beside the view (B6), because making it an error would mean removing the
`safeAreaBar` that shipped. Since B6's safe area is not being built
(2026-10-12), nothing ever passes under a bar, so `.automatic`, `.hard` and
`scrollEdgeEffectHidden` describe what TUIkit always draws and are honoured by
the medium, tested as a guarantee. Lane owed: about half a day. A12 follows
it.

**Shipped 2026-10-14**, with A12: `ScrollEdgeEffectStyle` (`.automatic`,
`.hard`), `scrollEdgeEffectStyle(_:for:)` and `scrollEdgeEffectHidden(_:for:)`,
in `ScrollEdgeEffect.swift`; `ScrollEdgeEffectStyle.soft` is declined in the
parity map.

### O8. "Inert on macOS too" (X4): `SubmitLabel`, `View.submitLabel(_:)`, `ToolbarTitleDisplayMode`, `TabBarMinimizeBehavior`, `SensoryFeedback` (P11), `ContentShapeKinds.contextMenuPreview`/`.hoverEffect` (P3)

**Owner, 2026-10-12 (second message):** omit them. "We already have the general rule that we don't implement SwiftUI API we
can't actually do anything sensible with." So the APIs that are inert on macOS too stay refused, failing to compile, as
`submitLabel` already does; A11 and A51 stay refused.

- **(a) Refuse anything TUIkit cannot do, even when macOS SwiftUI cannot
  either.** This is the submitLabel precedent.
- **(b) Accept where Apple documents, or a probe measures, macOS SwiftUI as
  inert.** This matches macOS exactly, the DynamicTypeSize precedent. Each
  entry cites its measurement.
- **Recommendation: (b), limited strictly to measured or documented
  inertness.** Under (b):
  - `submitLabel` returns.
  - Most `SensoryFeedback` kinds ship. `.alignment` and `.levelChange`, which
    *do* play on a Force Touch trackpad, are hardware-dependent there too.
  - `ToolbarTitleDisplayMode` ships. Its reason ("TUIkit has no Font type") is
    stale regardless.
- **`TabBarMinimizeBehavior` is not inert on macOS.** `.automatic` minimizes
  under reduced space, so honour it by collapsing to the compact strip
  (`TabViewStyle.compact`); `.onScrollDown` likewise. Decide with W15.

**Restated 2026-10-12, at the owner's request; awaiting the owner.** Some
SwiftUI APIs do nothing on macOS either, by Apple's documentation or by
measurement: `submitLabel`, most `sensoryFeedback` kinds,
`ToolbarTitleDisplayMode`, `scrollDismissesKeyboard` (A11) and
`sectionIndexLabel` (A51). Multiplatform code calls them without `#if`,
because they compile on macOS. Should TUIkit accept them and do nothing, as
macOS does, or refuse them so they fail to compile? **Recommended: (b),
strictly where Apple documents or a probe measures macOS as inert**, each with
its evidence. A compile error tells a macOS developer nothing they do not
already see on macOS, code shared with iOS keeps compiling, and no TUIkit
capability is given up. An API that does something on macOS and nothing here
stays refused (`TabBarMinimizeBehavior` is honoured, not stubbed). (b)
settles A11 and A51; A21 is settled by B3 instead. About a day; the Example's
text that says `.submitLabel` fails to compile changes with it, in its seven
languages.

### O9. Multi-scene apps on one surface (from P15)

**The scenes in question:** `Window`, `openWindow`/`dismissWindow`,
`openSettings` (and `SettingsLink`/`Settings` in W14), `WindowGroup(id:/for:)`,
`AlertScene`.

- **(a) Refuse.**
- **(b) A sole `Window` scene behaves as `WindowGroup`.** Secondary scenes
  present as full-surface covers stacked over the main one; `dismissWindow`
  pops; `openSettings` presents the `Settings` scene as a sheet.
- **(c) Only `Settings`/`openSettings`.**
- **Recommendation: (c) now, (b) later.** Settings scenes are ubiquitous in Mac
  apps, and `SettingsLink` and `openSettings` have an obvious TUI reading.
- **Effort:** M for (c), L for (b).

**Ruled 2026-10-12: (b) for now, unless there is a significant reason to do
only (c); leave room for a real windowing model later.** There is no such
reason: (c) is the first commits of (b). Every scene presentation goes through
one internal presenter whose first policy is "secondary scenes are
full-surface covers stacked over the main one", so a tiling or overlapping
manager can later replace the policy, not the API. Lane owed: about five days,
about ten commits, among them `SceneBuilder`'s variadic `buildBlock` and
per-scene `@SceneStorage`. A22 and A26 follow it. Proposed, the owner's to
confirm: ship `\.supportsMultipleWindows` as `true`, since `openWindow` then
works.

### O10. File panels (from P16) — M–L

`fileImporter`, `fileExporter` and `fileMover`.

- **(a) Refuse.** "An app draws its own from `List`".
- **(b) A TUIkit-drawn file browser sheet.** The precedent:
  `ColorPickerPanel` stands in for the system colour panel. `allowedContentTypes:
  [UTType]` needs `UniformTypeIdentifiers`, absent on Linux. Either use it
  under `#if canImport(UniformTypeIdentifiers)` with an extension-based shim
  elsewhere, or a TUIkit `UTType` subset.
- **Recommendation: (b).** The meaning, "let the user pick a file", fully
  survives.

**Ruled 2026-10-12: (b), open and save dialogs drawn by TUIkit, adapted
natively and elegantly to the terminal.** Lane owed: about six days, in a
module of its own. On Linux, `fileExporter(item:)` and `FileDocument` wait on
A18.

### O11. `TextField(…value:formatter:…)` / `Text(_:formatter:)` / `\(x, formatter:)` family

**Owner, 2026-10-12 (second message):** deferred. The `Formatter`-based forms are not deprecated in SwiftUI (only the
`TextField` initialisers with `onEditingChanged:`/`onCommit:` are), but Linux's internal `getObjectValue` makes the
parse direction costly, so they wait: "we can always add them later if we change our mind." They stay refused until
then.

The stated reason, "type safety taken out", is taste, not the medium.

**New fact:** `Formatter.getObjectValue(_:for:errorDescription:)` is
**internal** in Linux Foundation (verified). Generic parsing through an
arbitrary `Formatter` is impossible there. Users cannot subclass usefully on
Linux either, so a dispatch over Foundation's concrete formatters is complete:
`NumberFormatter.number(from:)`, `DateFormatter.date(from:)`, `ISO8601…` and so
on.

- **(a) Keep refusing,** rewriting the reason to the Linux fact.
- **(b) Ship `Text(_:formatter:)` and the interpolation (S)**, which need only
  `string(for:)` (public everywhere). **And ship `TextField(value:formatter:)`
  (M)** on the existing draft machinery (`TextFieldValue.swift`), with the
  Linux dispatch.
- **Recommendation: (b).** This is common pre-iOS-15 code.

**Restated 2026-10-12, at the owner's request; awaiting the owner.** Should
TUIkit accept the older `Formatter`-based spellings, `Text(_:formatter:)`,
`\(value, formatter:)` and `TextField(value:formatter:)`, beside the
`format:` ones it ships? The refusal's reason ("the type safety taken out") is
taste; the real constraint is Linux, where parsing through an arbitrary
`Formatter` is internal, so `TextField` dispatches to the concrete parsers
there and a custom `Formatter` subclass displays but does not parse (a
documented platform deviation). **Recommended: (b), excluding the deprecated
`onEditingChanged:` and `onCommit:` forms** (the owner's 2026-10-12 ruling: no
deprecated SwiftUI API). About a day and a half.

### O12. `PointerStyle` family — M

- **Why the reason fails:** "No terminal protocol lets an app ask for a resize
  cursor" is false. OSC 22 sets the pointer shape by name.
  - kitty and foot document it, with CSS names.
  - Ghostty documents it from 1.0.0, with CSS names (corrected 2026-10-12:
    this said "believed to").
  - iTerm2 supports it from 3.5.0, with its own subset of X11 names, and xterm
    takes X11 names, so the CSS-only table below is wrong for both (corrected
    2026-10-12: this said iTerm2 likely does not).
  - Apple Terminal is unmeasured.
  The per-host names are in `Ghostty VT reference adoption study.md` §C4.
- **Mapping:**

  | PointerStyle | CSS cursor name |
  |---|---|
  | `default` | `default` |
  | `grabIdle` | `grab` |
  | `grabActive` | `grabbing` |
  | `horizontalText` | `text` |
  | `verticalText` | `vertical-text` |
  | `link` | `pointer` |
  | `columnResize` | `col-resize` |
  | `rowResize` | `row-resize` |
  | `frameResize` | `*-resize` |
  | `zoomIn` / `zoomOut` | `zoom-in` / `zoom-out` |
  | `rectSelection` | `crosshair` |
  | `image(_:hotSpot:)` | omit |

- **Options:**
  - (a) refuse, but fix the reason;
  - (b) ship and emit only where measured, inert elsewhere — the OSC 8
    hyperlink precedent and `.terminalHyperlinks`;
  - (c) refuse until a majority of hosts measure positive.
- **Recommendation: (b),** after probing with `Tools/TerminalProbes` and a
  `Terminal compatibility survey.md` entry, as CLAUDE.md requires.

**Ruled 2026-10-12: (b), inert where unsupported.** The design is
`Ghostty VT reference adoption study.md` §C4: names per host, the shape resolved from the hover
tracking, motion reporting only while a style is on screen, a reset on exit
and suspend, and built-in shapes (text over fields, a pointer over links and
buttons, resize over dividers and table columns) only where the reset is
measured clean, with a run-time check of whether the host honours shapes.
Lane owed: about two and a half days, plus a probe that takes screenshots,
since the shape is not in the byte stream, and a `Terminal compatibility survey.md`
entry. `pointerVisibility` and `.image(_:hotSpot:)` stay refused.

### O13. `Commands*` family — L

- **Why the reason fails:** "A terminal has no menu bar" is true, but the
  API's meaning survives. Commands are app-level, grouped, have shortcuts, and
  act on focused content through `FocusedValue`, which W09 implements.
- **(a) Refuse.** The status bar stands in (§2.6).
- **(b) A menu bar in the app-header row,** built from `Menu`/`DropdownMenu`
  and opened by F10, Alt-letter or a click: the Turbo Vision and mc idiom.
  - Command shortcuts register globally through the existing `keyboardShortcut`
    machinery.
  - `CommandGroupPlacement` standard groups map onto TUIkit's built-ins: quit →
    `QuitShortcut`, `.appSettings` → `openSettings`.
- **(c) A command palette (Ctrl-P).**
- **(d) Shortcuts only, no menus:** a partial seam, so reject it.
- **CONFIRM:** `onCommand(_:perform:)` (an ObjC `Selector` and the responder
  chain).
- **Recommendation: (b),** with (c) as a later addition.

**Ruled 2026-10-12: a full menu bar; the app header optional, following a
SwiftUI API close to its purpose; any combination of the two, neither, one or
both.** The header half is built: A28 deleted `.appHeader`, the window's top
bar comes from `.toolbar` items and `.navigationTitle`, every bar is opt-in,
and a bare `WindowGroup` draws on every row. The menu bar is designed (A28
§3.5, steps 8–9, with the owner's 2026-10-04 answers: declaring `.commands`
shows it; F10, Alt-letter and a click open it; it is not in the Tab ring) and
not built. Lane owed: about six days, a new leaf module over the app, chrome
and menu modules; its Window menu comes with O9.

**Built by lane O13 (2026-10-18)**, as TUIkitCommands: the vocabulary, the
scene modifiers, the bar with its keys, the scene's own commands and four of
the standard sets. What it decided, and what waits (Settings… and the Window
menu on O9, `TextFormattingCommands` on A42), is in
[`Decisions/The menu bar (O13).md`](<Decisions/The menu bar (O13).md>).

### O14. `ControlSize` (+ W06 `controlSize` modifiers) — M–L

Measured on macOS: `.large` makes a `Button` 20 → 28 pt tall, `.mini` 24×13.

- **(a) Refuse.**
- **(b) Ship the environment value and the modifiers (including the range
  form), and give built-ins an explicit density table:**
  - `.mini`/`.small`: compact chrome (no caps or brackets, tighter padding).
    TUIkit already has compact variants such as `TabViewStyle.compact`.
  - `.regular`: today's look.
  - `.large`/`.extraLarge`: roomier, with extra padding cells, or a three-row
    boxed `Button` at `.extraLarge`.
- **(c) Environment only, built-ins ignore it.** This is the B3 size-class
  precedent, but it is rule 2's stub shape.
- **Recommendation: (b).**
- **Why the reason fails:** "Every control is one row" is true, but the axis
  that survives is density.

**Ruled 2026-10-12: (b), with extra render styles per size** where they help:
a bordered button of three or more rows at `.large` or `.extraLarge`, say. One
"button chrome" table with O15, the same density axis applied to the other
controls. Lane owed: about three and a half days.

**Shipped 2026-10-15, the button half:** `ControlSize`, `\.controlSize`,
`controlSize(_:)` and its range form, and the bordered button's table in
`ButtonFaceEdges.swift` — no padding at `.small`, no caps at `.mini` (the label
breathes the focus instead), three rows at `.large` and `.extraLarge` with a
ring that breathes with the caps, one more cell of padding at `.extraLarge`.
A face-less (plain, borderless, link) button is unchanged, as SwiftUI changes
only its font. `ButtonToggleStyle` draws through the same body, so it follows.
The other controls' density is owed.

### O15. `ButtonBorderShape` (+ W04 `buttonBorderShape`) — M

**Possible mapping:**

| Shape | Rendering |
|---|---|
| `.capsule` | `▐label▌` (the half-block caps) |
| `.roundedRectangle` | `╭─╮` box or brackets |
| `.circle` | icon-only buttons |
| `.automatic` | today's look |

**Recommendation:** decide with O14 as one "button chrome" table.

**Why the reason fails:** "No radius exists" is true, but choosing between
caps, brackets and a box IS choosing a border shape.

**Ruled 2026-10-12: support it as best TUIkit can**, in O14's table. Lane
owed: about a day and a half, after O14; its `Shape` conformance after W1.

**Shipped 2026-10-15 with O14's button table**, a little differently from the
mapping above: a capsule keeps the half-block caps; a rounded rectangle ends in
the one-eighth blocks `▕ … ▏`, and its three-row ring meets quadrant corners
where a capsule's stops a cell short; a circle is the capsule with no padding.
`.roundedRectangle(radius:)` is `.roundedRectangle`. The `Shape` conformance
waits on O0 (parity-map entries say so).
A24 rides on O0 and O15.

### O16. `TextRenderer` group: `TextRenderer`, `TextProxy`, `Text.Layout`, `Text.LayoutKey`, `TextAttribute` (+ W11 `textRenderer`, `customAttribute`) — L

- **What maps:** `Text.Layout`'s lines, runs and slices map onto wrapped lines,
  style runs and grapheme clusters at known `CellRect`s.
- **What it would take:**
  - A minimal `GraphicsContext` that draws a run with style, opacity and
    whole-cell translation.
  - `TypographicBounds` ascent, descent and leading have no honest value, so
    omit them.
- **What it buys:** apps get the per-character effects TUIkit keeps internal
  today (`AnimatedCellRun`).
- **Recommendation:** defer, but rewrite the reason. "No glyphs" is not the
  blocker; the size of the `GraphicsContext` subset is.

**Ruled 2026-10-12: defer.** The parity map's reasons for `TextRenderer`,
`TextProxy`, `TextAttribute` and `Text.LayoutKey` now say so (2026-10-12).

### O17. `ToolbarDefaultItemKind.title`, `.search` (W15)

- **`.title`:** hide `NavigationStack`'s title crumb, which TUIkit's framework
  does draw (S). Recommend implementing it.
- **`.search`:** pairs with `DefaultToolbarItem(kind:placement:)` for
  re-placing `.searchable`'s field. Decide with W15.

**Ruled 2026-10-12: do these.** `.title` removes the window top bar's title
slot and the stack's title crumb. `.search`: `DefaultToolbarItem(kind:
.search, placement:)` draws `.searchable`'s field in that toolbar placement
instead of at the top of the subtree, and `toolbar(removing: .search)` hides
it. Lane owed: about a day, with the stale reasons it leaves (the map's and
`ToolbarRemovalModifier`'s, which still say TUIkit draws no default title).

**`.title` shipped 2026-10-14**, with those reasons: the window's chrome
records the removal per walk, as it records titles, and the stack's bar (and a
collapsed split view's) reads it from the screen's preferences or the
environment above.

**`.search` shipped 2026-10-14**, with `DefaultToolbarItem(kind:placement:)`
(TUIkitChrome; `ToolbarDefaultItemKind` moved to TUIkitFoundation so the three
sibling modules can name it). Declaring a search item claims the window's
field from its chrome, kept by frame, so a toolbar inside the searchable's
content moves the field a frame later; the searchable hands its field, scopes
and all, to the chrome for the item to draw, and its content stays its second
child. `.toolbar(removing: .search)` draws the field nowhere. A `.title` item
moves the title out of the top bar's slot. `.sidebarToggle` in a
`DefaultToolbarItem` draws nothing (a slated deviation).

---

## CONFIRM

### Accessibility, 18 entries

Each feeds an AX tree no outside process can read, describes a VoiceOver or
Switch Control surface, or is an iOS scene.

- `AXChartDescriptorRepresentable`: also Apple-only `AXChartDescriptor`.
- `AccessibilityActionCategory`, `AccessibilityAdjustmentDirection`,
  `AccessibilityAttachmentModifier`, `AccessibilityChildBehavior`.
- `AccessibilityCustomContentKey`: Apple-only `AXCustomContent`.
- `AccessibilityDirectTouchOptions`, `AccessibilityHeadingLevel`,
  `AccessibilityLabeledPairRole`.
- `AccessibilityRotorContent`, `AccessibilityRotorContentBuilder`,
  `AccessibilityRotorEntry`, `AccessibilitySystemRotor`.
- `AccessibilityTechnologies`, `AccessibilityTextContentType`,
  `AccessibilityTraits`, `AccessibilityZoomGestureAction`.
- `AssistiveAccess`: an iOS Assistive Access scene. Its reason is truncated
  (X3).

### Geometry and transforms

- **`CGPoint.AnimatableData`, `CGSize.AnimatableData`, `CGRect.AnimatableData`:**
  a compiler wall (SwiftUICore's cross-import overlay typealias), verified
  2026-10-03.
- **`ProjectionTransform`, `CGPoint.applying(_:)`, `GeometryEffect`:**
  arbitrary projective transforms of *rendered* content. A cell grid can only
  translate by whole cells, and the type cannot restrict itself to translations
  at compile time. A translation-only `GeometryEffect` such as the classic
  "shake" would be expressible, but a rotation would be silently dropped.
- **`EdgeInsets.init(_:)` (NSDirectionalEdgeInsets):** an AppKit-type bridge,
  so the `NSHostingView` family's reasoning applies.
  - Rewrite the reason: "would invent a point-to-cell scale" is wrong, because
    TUIkit already maps 1 pt to 1 cell everywhere (§2.1).

### Text metrics

- **`View.allowsTightening(_:)`, `\.allowsTightening`:** reduces sub-cell
  inter-character spacing, and cells advance in whole units.
- **`View.minimumScaleFactor(_:)`, `\.minimumScaleFactor`:** shrinks the
  glyph size, which the emulator owns.
- **`Font.Leading`, `Font.leading(_:)`:** fractional inter-baseline spacing,
  honoured on macOS (±4 pt over 3 lines, measured), and a grid can only move
  whole rows.
  - Note: SwiftUI's doc lets a font without leading support "return the
    original font". That is an escape hatch the owner *could* invoke under O8's
    logic, but macOS does honour it, so CONFIRM.
- **`Image.Scale`:** relative symbol size, honoured on macOS (17×16 → 23×20).
  A symbol is one codepoint at the terminal's size.
- **`TextInputFormattingControlPlacement`:** OS-drawn rich-text formatting
  chrome. Nothing in TUIkit is OS-drawn, and rich editing does not exist.

### Symbols

- **`SymbolRenderingMode`:** layer colouring. One glyph has one foreground. On
  macOS, rendering differs even for single-layer `star`, so "monochrome only"
  would drop the request.
- **`SymbolColorRenderingMode`:** a gradient inside one glyph.
- **`SymbolVariableValueMode`:** variable-value symbol layers.
  `Image(systemName:variableValue:)` is consistently absent too.

### Core Data

**`SectionedFetchRequest`, `SectionedFetchResults`.** Core Data is absent on
Linux.

Note: `#if canImport(CoreData)` could offer it to macOS-only apps. That is a
*policy* call — no Apple-only public API surface — not a medium limit, and the
plan already treats it as settled.

*2026-10-18:* the policy was ruled the other way — decisions A18 (owner,
2026-10-12, option 1) allows Apple-only API behind `canImport` where it is
honoured — so the family is permitted and unbuilt, its priority the owner's
call ([A-PARITYMISC-1](<Decisions/Small parity items (PARITYMISC).md#a-paritymisc-1-core-datas-fetchrequest-family-build-it-now-or-when-an-app-asks>)).

### Windows

**`WindowManagerRole`, `WindowToolbarFullScreenVisibility`.** These are the
window manager and window toolbar, which the host terminal owns.

### Previews

`PreviewProvider`, `PreviewContext`, `PreviewContextKey`, `PreviewDevice`,
`PreviewModifier`, `PreviewModifierContent`, `PreviewPlatform`, and the
`View.preview*` family. Rewrite the reason:

- **The current reason is wrong:** "No canvas can host a FrameBuffer" is false.
  `#Preview { … }` accepts an `NSView`, and a TUIkit-provided `NSView` that
  draws a `FrameBuffer` would show in the canvas. That is a TUI-only feature,
  not parity.
- **The actual reason:** a TUIkit `PreviewProvider` is not the protocol Xcode
  discovers, so it would compile and never appear. That is rule 2. (Hypothesis
  — check against Xcode's discovery before quoting it.)

### No consumer — rewrite the reason

- **`ColorMatrix`:** its only consumer is `GraphicsContext.Filter`.
  - Correction: the operation itself, a per-cell colour transform, is exactly
    what `ColorEffectModifiers` does.
- **`ColorRenderingMode`:** its consumers are `Canvas(colorMode:)`,
  `drawingGroup(colorMode:)` and `ImageRenderer`, none of which exist.
  - The reason "never composites colour" is false (X2). TUIkit has composited
    in both spaces.
- Both become implementable with Canvas (see D3).

### Families

- **`View.preview*` / `Preview*`:** as above.
- **`*.hashValue`, `*.Element`, …:** standard-library conformance members.
  - Caveat: this also masks a *missing* `Hashable`/`Collection` conformance on
    a TUIkit counterpart. Check conformances with `sconf.py` when a type ships.
- **`*.Body` / `*.body`:** the type is reported instead.
- **`Font.smallCaps*`:** glyph variants. Unicode's small-capital letters are
  different codepoints (and miss Q and X), which is the `textCase` objection
  again.
- **`SearchSuggestionsPlacement*`:** declined twice on recorded reasoning.
  - If O8 is (b) and macOS ignores `.content`, revisit (unmeasured).
- **`NSHostingView*` and the other AppKit bridges:** no AppKit on the grid or
  on Linux. `Renderable` is the escape hatch.
- **`SpatialEvent*`, `*ImmersiveSpace*`, …:** visionOS.
- **`*Pencil*`:** Apple Pencil.
- **`*.touchBar*`:** the Touch Bar.
- **`Widget*`:** WidgetKit extensions.
- **`ShareLink*`:** the system share sheet. Linux and terminals have no
  share-extension registry.

---

## differentShape — entries whose "how" is about to go stale

Most entries still hold. These need attention.

- **About to be superseded by planned waves.** Each should become an
  implementation, not a differentShape entry:
  - `Anchor`, by W05's `anchorPreference`/`transformAnchorPreference`.
  - `FillShapeStyle`, `ForegroundStyle`, `HierarchicalShapeStyle(Modifier)`,
    `LinkShapeStyle`, `PlaceholderTextShapeStyle`, `SeparatorShapeStyle` and
    `TintShapeStyle`, by W13's `ShapeStyle.fill/.foreground/.secondary…/.link/.placeholder/.separator/.tint`.
  - `ProgressViewStyle`, by W04's style protocols.
  - `GestureState` and `TapGesture`, if P6 lands.
  - `Material`, by O5.
- **Cheap source-compatibility aliases** — rule 1 says SwiftUI source should
  compile:
  - `BorderedButtonStyle`/`BorderedProminentButtonStyle`/`BorderlessButtonStyle`
    as `.bordered`/`.borderedProminent`/`.borderless` (S).
  - `DefaultPickerStyle`, `DefaultProgressViewStyle`.
  - `LinearProgressViewStyle` as `.linear`.
  - `CircularProgressViewStyle` as `.circular`: Spinner when indeterminate,
    `accessoryCircular` gauge when determinate.
  - `Image.Interpolation`: `.none` for nearest, `.high` for supersampling 4.
  - `ScrollBounceBehavior` as `scrollBounceBehavior(_:axes:)` over
    `ScrollOverscroll`.
  - `Spacer.minLength`, a rename of `spacerMinLength`.
- **`AsyncImage`.** `Image(.url)` plus placeholder already *is*
  `AsyncImage(url:content:placeholder:)` with `AsyncImagePhase`. Ship the
  spelling (S–M).
- **`Canvas`, `GraphicsContext` (D3).** "Renderable + FrameBuffer" is true
  today. With W1's rasterizer, a `GraphicsContext` that fills and strokes paths
  into an RGBA buffer, draws text runs at cells, and applies opacity, blend
  modes and per-cell colour filters is implementable (L). Decide after W1.
- **`Toolbar*`, `DefaultToolbarItem`.** These belong to the W15 owner decision.
- **Truncation.** 31 `differentShape` reasons are truncated (X3).
