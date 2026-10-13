# Completing the SwiftUI API: decisions for review

*The companion to [`SwiftUI API completion plan.md`](<../SwiftUI API completion plan.md>).
That file is the plan. This one collects every point the work reached where the
call was the owner's, or where I made a call that the owner may want to revisit.
It is written to be read once, at the end of the straightforward work.*

Three parts:

- **A. Needs your decision.** Nothing has shipped for these. Each entry gives
  the options, what each costs, and my recommendation.
- **B. Shipped the safe option.** A basic, honest form is in. Each entry says
  what the fuller version or the alternative reading would be, and what it
  would cost.
- **C. Declined without asking.** Gaps I recorded in `parity-map.json` as not
  implementable, because the reason seemed unarguable. Listed so they can be
  vetoed.

Each entry names the SwiftUI symbols it covers, so `api_parity.py` output can be
traced back to it.

Ideas that were measured or designed and then deliberately not taken, here or in
the lane files, are in [`Future options.md`](<../../Future options.md>), each with what
would make it worth revisiting.

## Start here: the questions in one list

Every gap `api_parity.py` still reports names one of these entries, and
nothing else is waiting. The batch closed the rest: 2,022 gaps when it started
and 404 when it ended (the count rose from 392 at the end, when 14
drag-session modifiers a wrong refusal had hidden became gaps under A53); 232
on 2026-10-12, plus three overloads only CI's SDK lists. Besides the gaps, the refusal review's implementable P items have
shipped, and the one lane not run is Wave 11b, underline and strikethrough
patterns and colours, which needs real terminals measured (screen capture
needs your approval).

**How your answers are recorded.** Your review of 2026-10-04 (A1–A54,
B1–B37), my answers to its questions of 2026-10-05 (which you answered
"Proceed", so their proposals count as approved) and your rulings of
2026-10-12 are folded into the entries, each dated. An entry whose work has
landed is removed, and no entry is renumbered. **Lane owed** marks an entry
that is decided and waits only on its implementation.

**Still yours to answer.** A27 (pixel effects), A34 (the blur transition)
and A48 (swipe actions): each entry ends in a recommendation.

**Decided, waiting on a measurement.** A16's colour provider and A40's
default dissolve each wait on an A/B on the quiet machine, whose numbers
decide them as agreed: A40 dissolves by default if that costs under about 1%
when nothing animates.

**Decided, lane owed.** A0's ruled O items but O16 (deferred), and with them A12 (O7),
A22 and A26 (O9), A23 and A36 (O4), A24 (O0, O15), A37 (O2), A38 (O3) and
A41 (O5); A21 (with B3), A25, A42, B3, B19 (after its A/B), B22 (a look
at the faint tiers).

**Deferred.** A3, and B8's mirroring, with right-to-left (B1); A50 and A53
until macOS 26 or 27 can be measured.

**Waiting on another answer.** A11 and A51 (O8), A39 (A27).

---

## A. Needs your decision

### A0. The eighteen refusal questions (O0–O17)

The early Wave 17 review re-examined every existing refusal in
`parity-map.json`. Its verdicts:

- 54 are wrong;
- 21 are partly wrong;
- 60 hold;
- 23 turn on a genuine design call.

Those 23 are written up, each with options and a recommendation, as O0–O17 in
[`Refusals re-examined, wave 17 (2026-10-03).md`](<../Refusals re-examined, wave 17 (2026-10-03).md#owner-decision>).
They are not repeated here. **Ruled on 2026-10-12, all eighteen** (O8 and O11 in the owner's second message:
O8 refuses the APIs that are inert on macOS too, so A11 and A51 stay refused; O11 is deferred, not refused for good); each
ruling is in the review under its item. In brief, with the ruling:

- **O0** The unit of a shape's path. This gates the whole Shapes cluster:
  `Shape`, `Rectangle` and its members (`path(in:)`, `inset(by:)`,
  `corners(in:)`, `InsetShape`), `clipShape`, `contentShape`, `background(_:in:)`.
  **Keep (B)**, square units: the display scale cancels out of the cell's
  ratio, which (C)'s absolute size cannot say.
- **O1** Reduce-motion and the other accessibility preferences. **(b), but
  only `TUIKIT_REDUCE_MOTION`** (B53, shipped) unless TUIkit can be confident
  the terminal is on the same machine; then the host's setting too, by the
  clipboard's locality test. Lane owed.
- **O2** `PhaseAnimator` and `KeyframeAnimator`. **(b)**; (c) is not easy,
  so it is presented after (b).
- **O3** `CustomAnimation`. **Detect, else live**: integrated lazily and
  memoised, a finished animation is its own pre-sampled table.
- **O4** Matched geometry and zoom transitions. **(b), with (a) where
  possible.**
- **O5** Materials and Glass (A41 lists the material symbols waiting on it).
  **(b) for both**; a cell-resolution blur is an optional add-on.
- **O6** `ShadowStyle`. **(b)**, radius and offsets in cells.
- **O7** `ScrollEdgeEffectStyle`. **Only `.hard`**; no `.soft`.
- **O8** APIs that are inert on macOS too: `submitLabel`, `SensoryFeedback`
  and others. This reopens `submitLabel`. **Restated; awaiting the owner.**
- **O9** Multi-scene apps. **(b)**, leaving room for real windowing.
- **O10** File panels. **(b)**, TUIkit-drawn open and save dialogs.
- **O11** The `formatter:` APIs. **Restated; awaiting the owner.**
- **O12** `PointerStyle`. **(b)**, inert where unsupported (the review's
  facts about which terminals take OSC 22 were corrected).
- **O13** `Commands`, as a menu bar. **A full menu bar**; the app header
  optional, either, both or neither.
- **O14** `ControlSize`. **(b)**, with extra render styles per size.
- **O15** `ButtonBorderShape`. **Support it.**
- **O16** `TextRenderer`, with `View.textRenderer(_:)` and `Text.customAttribute(_:)`.
  **Defer.**
- **O17** The toolbar's `.title` and `.search` items. **Do them.**

### A3. `layoutDirectionBehavior(_:)`: mirror now, or with right-to-left?

*`LayoutDirectionBehavior` (`.fixed`, `.mirrors`, `.mirrors(in:)`),
`View.layoutDirectionBehavior(_:)`, `Shape.layoutDirectionBehavior`*

Measured in SwiftUI: in a left-to-right environment `.fixed` and `.mirrors`
change nothing, but `.mirrors(in: .leftToRight)` really mirrors. So this
cannot ship as a no-op, and one enum case cannot be made a compile error.

**Options.**

1. **Mirror at cell level now.** Reverse each row's cells (wide characters
   kept whole), swap glyphs that have mirror forms (Unicode's mirroring
   pairs, plus `┌↔┐`, `╭↔╮`, `├↔┤`, `▌↔▐`, arrows), and mirror the x of every
   payload (hit regions, floating layers, opacity regions, animated runs).
   Letters come out reversed, not mirror-written. 1–1.5 days.
2. **Defer to right-to-left support** (B1's fuller version), which needs the
   same buffer mirror and would give it real use and tests.

**Recommendation:** 2. Nothing ships until then.

**Decided 2026-10-04: defer with right-to-left** (option 2; you left it to
me). You also raised that a terminal's own bidi may mirror a Hebrew line a
second time. That is the per-terminal survey right-to-left needs first: TUIkit
already puts invisible left-to-right marks round its image glyphs to stop
terminals reordering them, and one terminal (VTE) lets an app turn its
reordering off; most do not (answer of 2026-10-05).
`flipsForRightToLeftLayoutDirection(_:)` has shipped regardless: its
condition is a right-to-left environment, which cannot occur yet (B1).

**Wave 11 adds four symbols to the same question:**
`View.multilineTextAlignment(strategy:)`, `View.writingDirection(strategy:)`,
`Text.AlignmentStrategy` and `Text.WritingDirectionStrategy`. Each strategy
chooses between the layout direction and a paragraph's own writing
direction. TUIkit lays every paragraph out left to right, so the two agree
except on a right-to-left paragraph. There, `.writingDirectionBased` and
`.contentBased` would right-align a Hebrew line in SwiftUI and left-align it
here. Shipping them before right-to-left would be a quiet lie for exactly
the text they exist for, so they wait with this entry.

*Wave 10's entries (A6–A12, B23–B31, C6–C7): SwiftUI behaviour quoted as *measured* was measured on macOS 15 with an offscreen `NSHostingView`; the probes are in the session notes, `w10/probe`.*

### A11. `scrollDismissesKeyboard(_:)` joins O8

*`View.scrollDismissesKeyboard(_:)`, `ScrollDismissesKeyboardMode` (+ `.automatic`,
`.immediately`, `.interactively`, `.never`),
`EnvironmentValues.scrollDismissesKeyboardMode`*

It is about the software keyboard, which macOS does not have either, so on
macOS every mode is inert — exactly the refusal review's O8 question. Under O8's
recommended (b) it ships as a recorded, documented-inert value, as macOS's is;
under (a) it is declined with `submitLabel`. Nothing to decide here apart from
O8.

### A12. The scroll edge effects join O7

*`View.scrollEdgeEffectHidden(_:for:)`, `View.scrollEdgeEffectStyle(_:for:)`*

They style content passing under a bar, and nothing passes under a bar here
(B6). Refusal-review O7 already asks whether to ship them with the safe-area
design; these two modifiers are that question's modifiers.

**Decided with O7 (2026-10-12): lane owed.** `ScrollEdgeEffectStyle` ships
with `.automatic` and `.hard` and no `.soft`, and both modifiers are honoured
by the medium: nothing passes under a bar, since B6's safe area is not built.

### A16. Colours that resolve themselves, and HDR

**2026-10-05: the HDR half shipped** (`Color.headroom(_:)`; `ResolvedHDR`,
`resolveHDR(in:)` and `exposureAdjust(_:)` declined in the parity map). What is
left is the custom colour provider, which waits on its benchmark.

*`Color.init(_:)` for a `ShapeStyle & Hashable` whose `Resolved` is
`Color.Resolved` or `Color.ResolvedHDR`; `Color.ResolvedHDR` and its
members; `Color.resolveHDR(in:)`, `Color.headroom(_:)`,
`Color.exposureAdjust(_:)`*

`Color.Resolved`, `resolve(in:)` and the component initialisers have
shipped. Two things remain.

- **A custom colour provider.** SwiftUI's `Color(MyStyle())` defers to the
  style at every resolve. TUIkit's `Color` is five bytes with no padding:
  every `Text` carries two, every cell's run carries them, and the value
  hash reads them as plain words. A provider case would hold an existential
  (40 bytes), growing every one of those, or an index into a registry, which
  is a singleton. Resolving the provider once at `init` against a default
  environment would be the quiet lie the parity rules forbid.
- **HDR.** A terminal is SDR, so a headroom cap is always met
  (`headroom(_:)` would return the colour unchanged, honestly), and
  `ResolvedHDR` is a value type that could ship as data.
  `exposureAdjust(_:)` brightens by stops, though, and a palette role or a
  terminal slot has no numbers until it is painted, so it cannot be applied
  at `init`.

**Options.** (a) Decline the provider, ship `ResolvedHDR`, `resolveHDR(in:)`
and `headroom(_:)`, and decline `exposureAdjust(_:)`. (b) Decline all of it.
(c) Grow `Color` for the provider.

**Recommendation:** (a). All of these are macOS 26 APIs (the HDR half could
not even be probed on this machine's macOS 15), and they are rare in ported
code.

### A18. Apple-only public API behind `#if canImport`: allowed or not?

**Owner, 2026-10-12 (second message):** option 1. "Yes, we can use platform-specific API. I prefer not to if we
have a reasonable alternative, but certainly if it's intrinsically tied to a specific platform (or the presence of a
specific supporting package/module/whatever), then that's fine." So the `store: UserDefaults` spellings and
`defaultAppStorage(_:)` ship behind `canImport`, Core Data's `FetchRequest` becomes possible for Apple-only apps, and
O10's Linux file exporter may be absent where its type is Apple-only. Lane owed.

*Policy, with these symbols waiting on it: `AppStorage`/`SceneStorage`'s
`store: UserDefaults` spellings, `View.defaultAppStorage(_:)`,
`Scene.defaultAppStorage(_:)`; and, if allowed, Core Data's `FetchRequest`
family (declined in the map today)*

The Wave 17 review treats "no Apple-only public API surface" as settled (its
`SectionedFetchRequest` note). The batch has not kept to it:

- **Wave 7** shipped `onDrag`, `onDrop(of:…)`, `DropDelegate`, `itemProvider`
  and the `onCopyCommand`/`onCutCommand` forms that take `NSItemProvider`,
  behind `#if canImport(UniformTypeIdentifiers)`.
- **Wave 13** shipped `Color(cgColor:)`, `Color(nsColor:)`, `NSColor(_:)` and
  `Color.Resolved.cgColor`, behind `canImport(AppKit)`/`(CoreGraphics)`.

Each is honoured where it exists, and absent elsewhere. A Linux build simply
does not offer it, so it cannot compile there and do nothing.

**Options.**

1. **Allow it, behind `canImport`, where the feature is honoured on Apple
   platforms.** Then `store: UserDefaults` and `defaultAppStorage(_:)` ship
   (`UserDefaultsStorage` gains an `init(_ defaults: UserDefaults)`), and Core
   Data's `FetchRequest` becomes possible for macOS-only apps (a few days).
2. **Forbid it.** Remove the Wave 7 and Wave 13 surfaces above, and keep the
   storage spellings TUIkit's own (`StorageBackend`), with
   `defaultAppStorage(_:)` taking one. A ported `@AppStorage(…, store:
   UserDefaults(…))` then fails to compile.
3. **Allow bridges and value conversions only** (colours, item providers),
   not frameworks (Core Data).

**Recommendation:** 1, with "honoured where it exists" as the test, which is
the rule the batch has been following in practice.
`defaultAppStorage(_:)` also needs `@AppStorage` to resolve its store from
the environment at render, through a nested `@Environment`; that part is
half a day whichever option is chosen.

**Your answer of 2026-10-04:** `canImport` is fine if it fails gracefully.
Absence at compile time is ideal; a failure at run time is acceptable only for
icing, or with a capability query beside it (as the kitty keyboard protocol
has). The shipped bridges meet that: each is honoured where it compiles.
**Still open:** whether that admits option 1's framework spellings, the
`store: UserDefaults` forms and Core Data's `FetchRequest` on Apple platforms.
The refusal review's O10 depends on it: on Linux, `fileExporter(item:)` and
`FileDocument` would be absent (or a small protocol of TUIkit's own).

*Wave 9's entries (A20–A25, B34–B41, C9; A19 shipped 2026-10-06): SwiftUI's behaviour is from its own doc comments unless an entry says it was measured.*

### A21. Compact-size-class adaptation and `preferredCompactColumn`

*`PresentationAdaptation` (`.automatic`, `.none`, `.popover`, `.sheet`,
`.fullScreenCover`), `View.presentationCompactAdaptation(_:)`,
`View.presentationCompactAdaptation(horizontal:vertical:)`,
`NavigationSplitView.init(preferredCompactColumn:…)` (all four)*

All of these say what to do in a compact size class: present a popover as a
sheet, show which split view column on top once the split collapses into one.
macOS is never compact, so on a Mac they are inert; TUIkit's size classes are
`.regular` unless an app sets them, and nothing TUIkit draws reads them (B3) —
the split never collapses and a popover never adapts.

**Options.**

1. **Leave them out** until B3 is decided.
2. **Ship them inert**, as macOS has them — under O8's option (b), citing
   the size classes never being compact here.
3. **Make them real:** a popover or sheet adapts by `PresentationAdaptation`
   when the environment's size class is compact (`.automatic` adapting a
   popover to a sheet, as iOS does), and a split view collapses into a stack
   showing `preferredCompactColumn` in a compact horizontal class. The
   adaptation is small (the popover presenter delegates to the sheet or cover
   presenter); the collapse is not (a split that becomes a stack keeps its
   columns' state and focus sections) — two days together. It only matters if
   B3 makes a narrow terminal compact.

**Recommendation:** decide with B3 and O8: 2 if O8 is (b) and B3 stays
"regular", 3 if B3 makes narrow terminals compact.

**Decided 2026-10-12, with B3: option 3, lane owed.** B3's ruling is that
TUIkit follows a compact class an app sets and changes no default, so when an
app writes `.compact` a popover must adapt and a split view must collapse;
shipping these inert would ignore the app's own setting. The defaults stay
regular, so nothing changes for an app that sets nothing. The work (about two
days, as priced above) goes with B3's lane.

### A22. `DismissBehavior` waits on O9

*`DismissBehavior`, `.interactive`, `.destructive`, and (from Wave 12) `Transaction.dismissBehavior`*

It qualifies `dismissWindow` (`withTransaction(\.dismissBehavior, .destructive)`
closes a window even with a sheet up on it). `dismissWindow` is in the window
family the map declines, which O9 of the refusal review reopens. If O9 goes
(b) — secondary scenes as covers stacked over the main one — `.destructive`
means closing such a cover with its own presentations still up, and
`.interactive` refusing to; under (a) or (c) the type has nothing to qualify
and joins the decline.

**Decided with O9 (2026-10-12): (b), so this ships with O9's lane.**

### A23. `matchedTransitionSource` waits on O4

*`View.matchedTransitionSource(id:in:)`,
`View.matchedTransitionSource(id:in:configuration:)`*

The source half of the `.zoom` navigation transition, which O4 (matched
geometry and zoom transitions) covers. `NavigationTransition` and `.automatic`
shipped (the stack's own transition); `.zoom` and these two follow O4.

**Decided with O4 (2026-10-12): lane owed,** after matched geometry; the
source configuration needs O0's shapes (W1).

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

### A25. `searchSelection(_:)` waits on A13

*`View.searchSelection(_:)`*

It binds the search field's `TextSelection`. That type, and whether TUIkit
draws its own selection at all, is A13 (text selection) in the main decisions
doc. Once `TextField` takes a selection binding, this is a few lines on the
searchable's field.

**No longer waits.** A13 shipped on 2026-10-05, and `TextField` takes a
`TextSelection?` binding, so this is ordinary work: owed.

### A26. The scene-level dialog modifiers and optional scenes wait on O9

*`Scene.dialogIcon(_:)`, `Scene.dialogSeverity(_:)`,
`Scene.dialogSuppressionToggle(_:isSuppressed:)` and `(isSuppressed:)`,
`SceneBuilder.buildOptional(_:)`, `SceneBuilder.buildLimitedAvailability(_:)`;
and with them O9's settings scene: `Settings`, `SettingsLink`,
`DefaultSettingsLinkLabel`, `OpenSettingsAction`, `\.openSettings`*

SwiftUI's examples apply the dialog modifiers to an `AlertScene`, and the two
builder methods exist for `if #available` around a scene among others. Both
need more than one scene, which TUIkit's `SceneBuilder` does not build: that is
O9 of the refusal review.

**Options.**

1. **Under O9 (b) or (c):** ship the dialog modifiers as scene environment
   writes, reaching an `AlertScene` and the alerts the scene's views present.
   That is half an hour, on top of `Scene.environment(_:_:)`. Under (b), the
   builder methods come with the variadic `buildBlock`.
2. **Under O9 (a):** decline all six with the window family.

**Recommendation:** follow O9. The dialog modifiers could ship today as
environment writes, but whether SwiftUI's reach a view's alert, and not only
an `AlertScene`, cannot be measured offscreen. Alerts are modal panels.

**Decided with O9 (2026-10-12): option 1 under (b), lane owed** with O9's
`SceneBuilder`.

### A27. Pixel effects: transforms, masks and `drawingGroup` (Wave 16)

*`View.scaleEffect(_:anchor:)`, `View.scaleEffect(x:y:anchor:)`,
`View.rotationEffect(_:anchor:)`, `View.rotation3DEffect(_:axis:anchor:anchorZ:perspective:)`,
`View.projectionEffect(_:)`, `View.transformEffect(_:)`, `View.mask(alignment:_:)`,
`View.drawingGroup(opaque:colorMode:)`; and, waiting on refusal-review items
already, `View.clipShape(_:style:)` and `View.contentShape(_:eoFill:)`/`(_:_:eoFill:)`
(O0), `View.shadow(color:radius:x:y:)` (O6)*

Wave 16 shipped what a cell grid keeps honestly: `clipped(antialiased:)` (the
cut `ScrollView` and `List` already made) and `compositingGroup()` (a guarantee
the compositor keeps). Blur, blend modes, luminance to alpha and the background
extension effect joined the map's per-pixel shading family. The rest is yours.

**Transforms.** A glyph cannot be scaled or turned, and an affine transform
of a cell grid is not a cell grid.

1. **Decline all six.** `scaleEffect(isPressed ? 0.95 : 1)` in ported code then
   fails to compile, and the developer removes it. Free.
2. **`scaleEffect` as the `.scale` transition draws it**, a reveal from the
   anchor, with `rotationEffect` and the rest declined. A scale of 0.95 then
   draws as 1 (nothing to reveal), which is the silent no-op rule 2 forbids, so
   this only makes sense with a threshold. Half a day.
3. **Raster content only:** a scaled or quarter-turned `Image` is resampled.
   The receiver is any view, so the type system cannot keep this to images.
   Text would draw unchanged. That is a no-op again. A day.

**`mask(alignment:_:)`.** Masking by another view's alpha can be honoured at
cell granularity: a cell where the mask draws (a glyph or a background) keeps
the content, at the mask colour's alpha through an opacity region, and the
rest is cleared to what is behind. Choosing that coverage rule is the decision
("a space with no background masks out" is the one that would surprise). Half
a day.

**`drawingGroup(opaque:colorMode:)`.** In SwiftUI it flattens the view into an
offscreen image before display. Here every view already composites as one
picture, as for `compositingGroup()`. `opaque` is a promise by the caller.
`colorMode: .linear` asks for linear-light blending, which TUIkit's encoded-sRGB
blend does not do.

1. **Ship it as `compositingGroup()`**, honouring `.nonLinear`, the default,
   and documenting `.linear` and `.extendedLinear` as blended non-linearly.
2. **Decline it.**

**Recommendation:** transforms (1); mask, the cell-coverage rule; drawingGroup
(1), since nearly every use is the argument-free performance hint.

**You asked (2026-10-04)** whether linear and extended-linear blending could be
supported. Yes (answer of 2026-10-05): blending happens in one place, in
encoded sRGB by design today, and linear blending is decode, blend and
re-encode through lookup tables, which is cheap. Extended-linear is the same on
an SDR terminal, clamped at the end. Not yet decided.

*Wave 8a's remaining entries (C10; A30, A31 and B44–B47 shipped 2026-10-06, A29 on 2026-10-07): SwiftUI's behaviour was measured on macOS 15.8, built against the macOS 26.2 SDK, with an offscreen `NSHostingView`; the probes are in the session notes, `w08a/probe`.*

*Wave 11a's entries (A32–A33, B48–B51): every string was measured on SwiftUI, macOS 15, by rendering with `ImageRenderer` and reading the picture back with Vision; the probes are in the session notes, `w11a/probe`. A pass on macOS 26 is owed.*

*Wave 12's entries (A34–A40, B52–B61; its `Transaction.dismissBehavior` joined A22): SwiftUI's behaviour is from its doc comments unless an entry says it was measured; measurements are from probes built against the macOS 26.2 SDK and run on macOS 15, kept in [`Tools/SwiftUIProbes/Animation curves, springs and keyframes`](<../../../Tools/SwiftUIProbes/Animation curves, springs and keyframes>).*

### A34. `BlurReplaceTransition`: a fade in place of the blur, or wait for W16?

*`BlurReplaceTransition` (and `Configuration`, `.downUp`, `.upUp`,
`init(configuration:)`, `configuration`, `body(content:phase:)`),
`Transition.blurReplace`, `Transition.blurReplace(_:)`*

SwiftUI documents it as "combining blurring and scaling effects": `.downUp`
scales the view down while removing it and up while inserting it, `.upUp`
scales up both ways. The scale half is TUIkit's `.scale` reveal. The blur half
is the per-pixel filter the map declines (`VisualEffect.blur*`, confirmed by
the Wave 17 review, P14), and Wave 16 owns blur as a whole.

**Options.**

1. **Leave it out until Wave 16 decides blur.** Free. Code using it fails to
   compile, which is the rule for anything not honoured.
2. **Ship it as a scale and a fade.** A blurred-out view reads, at a cell's
   resolution, as one that has faded: there is no sub-cell detail to soften,
   and the opacity compositor already dissolves a cell's colours toward what
   is behind it. `.downUp` becomes the reveal from the centre plus the fade;
   `.upUp` the same on insertion and a fade alone on removal (a reveal cannot
   grow past the slot). An hour with tests, and the doc comment says
   the blur is drawn as a fade.
3. **Option 2, plus a cell "blur"**: soften the glyphs on the way out (shade
   blocks `▓▒░`, or the dim attribute) as well as the colours. A day, and a
   drawing that has no precedent in TUIkit.

**Recommendation:** 2, if Wave 16 does not give blur a cell reading of its
own; 1 until then. Nothing ships.

### A36. `matchedGeometryEffect` waits on O4

*`View.matchedGeometryEffect(id:in:properties:anchor:isSource:)`*

`@Namespace` shipped in Wave 9, so the identifier half exists. The effect
itself — carrying a view from the source's frame to its own — and its
`MatchedGeometryProperties` are O4 of the refusal review, with options from
position-only (whole cells, size snaps) to a full re-layout per frame.
Nothing ships until O4 is answered.

**Decided with O4 (2026-10-12): a full re-layout per frame, translating only
when the sizes are equal.** Lane owed: about three to four days.

### A37. `phaseAnimator(_:trigger:content:animation:)` waits on O2

*`View.phaseAnimator(_:trigger:content:animation:)`*

The animator views are O2 of the refusal review. If O2 goes (b), this is the
trigger form of that live phase animator, and its completion advance would use the
animation completions this wave adds.

**Decided with O2 (2026-10-12): (b), lane owed.**

### A38. `Animation.shouldMerge` and `Animation.velocity` wait on O3

*`Animation.shouldMerge(previous:value:time:context:)`,
`Animation.velocity(value:time:context:)`*

Both take an `AnimationContext`, which belongs to the `CustomAnimation`
family that O3 of the refusal review reopens. They are the merge and velocity
half of a custom animation's contract; with O3 (b) they would answer `false`
and the closed-form velocity respectively.

**Decided with O3 (2026-10-12): live, memoised integration**, so both become
real rather than constant answers: `shouldMerge` is asked on a retarget to the
same custom type, and the velocity is the integration's. Lane owed with O3.

### A39. The geometric visual effects wait on Wave 16 (A27)

*`VisualEffect.rotationEffect(_:anchor:)`,
`VisualEffect.rotation3DEffect(_:axis:anchor:anchorZ:perspective:)`,
`VisualEffect.scaleEffect(_:anchor:)`, `VisualEffect.scaleEffect(x:y:anchor:)`,
`VisualEffect.transformEffect(_:)`*

The `View` modifiers of the same names are Wave 16's (sub-cell geometry, an
owner decision: A27). The visual-effect spellings are the same requests made from a
geometry proxy, and should be answered with them; `VisualEffect` itself and the
effects with a cell reading are this wave's.

### A40. Should a content change dissolve by default under an animation?

*`EnvironmentValues.contentTransition`'s default; the drawing of `Text` (and
`Image`) when what it shows changes inside `withAnimation`*

SwiftUI's environment holds an unnamed default content transition (measured:
equal to none of `.identity`, `.opacity`, `.interpolate`), under which a
`Text` whose string changes inside an animation cross-fades. TUIkit's default
draws the change at once, as it always has; `contentTransition(_:)` shipped
(B61) dissolves only where it is written.

**Options.**

1. **Keep the default instant.** Free. A port that relied on the default
   cross-fade snaps until it adds `.contentTransition(.opacity)`.
2. **Dissolve by default, in `Text` and `Image`.** Each keeps its last
   drawing and dissolves to a changed one under an animated transaction, as
   the modifier does for a subtree. The price is in the hottest view there
   is: every `Text` drawn under an animation compares its lines with the last
   frame's and, while a change dissolves, draws twice; and every `Text` keeps
   one drawing in state storage. A day, plus the A/B on `Stress` that a change
   to `Text` needs.

**Recommendation:** 1, until a port shows the default being relied on.

**Your answer of 2026-10-04:** inclined to option 2, unless it costs when
nothing is animating. **Agreed on 2026-10-05:** to dissolve from old to new,
each `Text` needs its previous drawing kept from before the change, which is a
cost on every frame of every app, not only while animating; so the option is
A/B'd first, and option 2 is adopted if that costs under about 1%. The A/B is
owed on the quiet machine. The recommendation above predates both.

### A41. Materials wait on O5

*`ShapeStyle.ultraThinMaterial`, `.thinMaterial`, `.regularMaterial`,
`.thickMaterial`, `.ultraThickMaterial`, `ShapeStyle.materialActiveAppearance(_:)`,
`View.materialActiveAppearance(_:)`, `\.materialActiveAppearance`,
`\.backgroundMaterial`, and `ShapeStyle.bar`, the material a bar draws with*

A material is a blurred, translucent surface. O5 of the refusal review asks
whether TUIkit's should be a translucent palette surface composited over what
is behind, its thickness an alpha and with no blur (recommended), or stay the
`dimmed()`/`overlayBackground` substitution. These symbols ship or are
declined with that answer.

**Decided with O5 (2026-10-12): the translucent surface.** Lane owed: about a
day.

### A42. Rich-text editing, now that P8 has shipped

*`AttributedTextSelection` and its members, `AttributedTextValueConstraint`,
`AttributedString.replaceSelection(_:with:)` and `(_:withCharacters:)`,
`AttributedString.subscript(_:)` (by selection),
`AttributedString.transform(updating:body:)`,
`AttributedString.transformAttributes(in:body:)`,
`AttributedString.init(transferable:in:)`,
`View.attributedTextFormattingDefinition(_:)`, `Optional.Scope` (an optional formatting definition's scope)*

SwiftUI's rich-text editing: a `TextEditor` over an `AttributedString`, its
selection carrying typing attributes, and constraints on which attributes an
edit may set. It presupposed `Text(AttributedString)` (P8 of the refusal
review), which has shipped with lane 17t (B84–B88): bold, italic, underline,
strikethrough, colours and links draw in cells. An attributed editor is now
the plain editor with styled runs, about two days; the selection type itself
is a day on top of `TextSelection`, which has shipped. **Recommendation:**
build it after the batch, with the formatting-definition constraints, if
rich text in a terminal editor is wanted; otherwise decline the family.

**Decided 2026-10-04: yes, build it.** Lane owed: about three days (the
attributed editor two, the selection type one), with the
formatting-definition constraints; the design is §7 of
[`Text selection and editing design study, A13, A42 and A43 (2026-10-04).md`](<../Design studies/Text selection and editing design study, A13, A42 and A43 (2026-10-04).md>).

*Wave 6b's entries (A43, B62–B65): SwiftUI's behaviour was measured on macOS 15.8 (SDK 26.2) by driving a SwiftUI `TextField` in an `NSWindow` with key events; the probes are in the session notes, `w06b/probe`.*

*Wave 10b's entries (B66–B71; A44 shipped, and A45 on 2026-10-07: a `List` pins its section headers under every style but `.sidebar`), pinned section headers and footers.* What SwiftUI does was measured on macOS 15.8, with offscreen `NSHostingView`s
in scroll views scrolled through their `NSScrollView`, reading the pixels down
a column (probes in [`Tools/SwiftUIProbes/Pinned section headers and footers`](<../../../Tools/SwiftUIProbes/Pinned section headers and footers>)):

- A header pins to the viewport's top while its section's **content** is under
  it. The content's last row pushes it up and away — the footer's top when the
  footer scrolls, the next header's top when there is none — so a header never
  sits over its own footer, and a header taller than what is left of its
  section rides up with it.
- A footer pins to the bottom, never above its section's first content row:
  with only a sliver of the content showing, it sits on that sliver, clipped by
  the viewport's edge.
- Pinned views draw over the content with no background of their own: rows
  show through wherever the header draws nothing.
- Only the stack's own sections pin — a `ForEach` of them, or ones written in
  its content, with any modifiers (a `.padding` on a section is applied to each
  of its parts, and its header still pins). A section in a row's `VStack` does
  not. Outside a scroll view nothing pins.
- A pinned stack below other content in the scroll view (a title above it)
  pins exactly as one at the top.
- Grids: a header and a footer span every column and pin the same way.
  Horizontal stacks and grids pin to the leading and trailing edges.
- `scrollTo(_:anchor: .top)` puts the row at the viewport's top edge, under a
  pinned header: nothing allows for it.
- `List`: `.plain` and `.inset` (and the macOS default) keep the first
  section's header at the top as the list scrolls; `.sidebar` does not. Read
  from the header's reported frame, which a floating table row may not update,
  so weaker evidence than the pixels above.

*Wave 8b's entries (A46–A51, B72–B80, C11): SwiftUI's behaviour was measured on macOS 15.8 (SDK 26.2) with an offscreen `NSHostingView`; the probes are in the session notes, `w08b/probe`. macOS 26 APIs could not be probed.*

### A48. Swipe actions: which keys and which pointer gesture?

*`View.swipeActions(edge:allowsFullSwipe:content:)`,
`TabContent.swipeActions(edge:allowsFullSwipe:content:)`*

A macOS list row reveals its swipe actions on a two-finger trackpad swipe
toward the edge they belong to; a full swipe performs the first. A terminal
has no swipe, and an action only the pointer reaches breaks the
no-mouse-only rule, so the route has to be chosen.

**Options.**

1. **A menu, from a chord and a horizontal scroll.** On the focused row, a
   row shortcut (bindable through `.rowShortcuts`, say Ctrl-L for the
   leading edge and Ctrl-T for the trailing) opens the edge's actions as the
   context-menu engine's menu, anchored at that edge of the row; a
   horizontal wheel event over a row (what a trackpad swipe sends in a
   terminal that reports the wheel) opens the same menu, and a full swipe is
   not modelled. Half a day: the menu, the shortcuts and the wheel are all
   there.
2. **Revealed buttons in the row.** The chord or the horizontal wheel slides
   the actions in at the row's edge, over its trailing cells, as macOS draws
   them; Tab moves through them and Escape slides them away; a second
   horizontal wheel in the same direction is the full swipe. Closer to
   macOS, and a day and a half: the row needs a revealed state the list draws
   and memoises, and its focus ring has to admit the buttons.
3. **Decline** by reason: a gesture the terminal does not have.

**Recommendation:** 1. A swipe action is a context menu for one edge, and the
menu brings its keyboard handling, dismissal and colours with it.

**You asked (2026-10-04)** whether any terminal reports swipes. None reports
a swipe as a gesture. Terminal.app and iTerm2 report a trackpad's horizontal
scroll as the horizontal wheel buttons (Terminal compatibility survey.md), which is
what option 1 uses, and a full swipe could be inferred from a long burst
(answer of 2026-10-05). Not yet decided.

### A50. Search in a tab view (macOS 26): the search tab and its activation

*`TabSearchActivation` (`.automatic`, `.searchTabSelection`),
`View.tabViewSearchActivation(_:)`; and `.searchable` written on a
`TabView`*

On macOS 26 `.searchable` on a `TabView` puts the search field into the tab
whose role is `.search`, and `.searchTabSelection` focuses the field when
that tab is chosen and goes back to the previous tab when the search is
dismissed. TUIkit draws `.searchable` on a tab view as it does on any view —
a field above the whole tab view — and has the `.search` role only as a
label. Nothing here could be measured: these are macOS 26 APIs, and this
machine runs 15.8.

**Options.**

1. **Implement as documented.** The tab view hands a `.searchable` written on
   it to its search tab's content (the field drawn at the top of that tab),
   and `.searchTabSelection` focuses it on selection (`SearchDismissal`
   already focuses a field) and reselects the previous tab on Escape. Half a
   day, and it should be measured on macOS 26 first.
2. **Defer** until a macOS 26 machine can measure it. Nothing compiles
   meanwhile, which is the honest state.

**Recommendation:** 2, then 1.

**Decided 2026-10-04: defer** until a macOS 26 or 27 pass can measure it.

### A51. `sectionIndexLabel(_:)` joins O8

*`View.sectionIndexLabel(_:)` (both)*

A macOS 26 modifier naming a section in a list's section index — the
A-to-Z strip down an iOS list's edge. macOS has no section index:
`listSectionIndexVisibility(_:)` is not in the macOS SDK, so on macOS the
label is inert. Exactly O8's question (APIs inert on macOS too); it ships or
is declined with O8's answer. Shipping it inert is ten minutes.

*Lane 17d's entries (A53, B82–B83, C12), spring-loading and the drag-session family (refusal review P11, P18): measured on macOS 15.8 (SDK 26.2) by driving SwiftUI's spring-loading entry points; the session family is macOS 26's and is from its doc comments. Probes in the session notes, `w17d/probe`.*

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
anything outside the process, and TUIkit's drag session and list selection
are where it would be built. The values (B83) ship; these fourteen
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

**Decided 2026-10-04: pinned** until macOS 26 or 27 can be measured; the
macOS 15.8 notes here stay.

*Lane 17g's entries (A54, B89–B94, C15), SwiftUI's gestures (refusal review P6): measured on macOS 15.8 (SDK 26.2) by sending synthesised `NSEvent`s into a window; the probes are in the session notes, `w17g/probe`.*

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

## B. Shipped the safe option

### B1. `\.layoutDirection` is read-only (always left-to-right)

SwiftUI's is settable, and under `.rightToLeft` its views mirror everything
that runs along the horizontal axis:

- stacks;
- `leading`/`trailing` alignment and insets;
- text alignment;
- images that are marked to flip.

TUIkit's views do none of that yet, so a write would be accepted and
ignored. The setter is left out instead, so the write fails to compile.

**The fuller version** is real right-to-left support. Every layout site that
resolves leading/trailing to left/right would consult the direction:

- `HStack` placement order;
- `Alignment` and `EdgeInsets` resolution;
- `Text` wrapping and alignment;
- `List` chrome (disclosure indicators, separator insets);
- scroll bars, which go on the leading side in RTL.

It also needs `layoutDirectionBehavior(_:)` (A3), and
`flipsForRightToLeftLayoutDirection(_:)`, which ships as the identity —
correct while the direction is always left-to-right — must start mirroring.

That is several days, and every one of those sites gets a test. Bidi text
itself (reordering mixed-direction runs) is a separate and larger question,
because the terminal does some of it on its own and inconsistently. That
belongs in `Terminal compatibility survey.md`, measured, before any design.

**Your answers (2026-10-04, 2026-10-12):** right-to-left is still wanted, and
out of scope for now: pinned until there is a solid plan, after everything
else. A3 and B8's mirroring wait on it.

### B2. `\.legibilityWeight` is read-only (always `nil`)

SwiftUI's is settable. Under `.bold`, every piece of system text is drawn
one weight heavier. That was measured on a SwiftUI build: light→regular,
regular→bold, and bold stays bold. In SwiftUI that includes control labels.

TUIkit draws many labels without going through `Text`, so honouring it in
`Text` alone would be a partial honour, which is the shape Rule 2 forbids.

**The fuller version** is one "heavier by one step" rule applied at every
text-drawing site:

- faint→normal, normal→bold;
- `Text`, button and control labels, field contents, list chrome.

Alternatively, apply it once at the subtree's buffer, the way
`SGRColorRewrite` applies a colour effect. The rewrite is cheaper to get
complete, but it would also embolden non-text glyphs (borders, bars). That
is a reason to prefer the per-site rule.

**Owner, 2026-10-12 (second message):** yes, make it writable. Lane owed (the helper, the A/B).

**Asked 2026-10-12: confirm that it should become writable.** You asked
whether this was already decided. Not in so many words: on 2026-10-04 you
said it did not seem hard to support, asked whether the built-in views should
switch to drawing through `Text`, and wanted an experiment and a benchmark
before deciding; on 2026-10-05 I answered that they need not switch (a shared
"one weight heavier" helper at each drawing site costs one environment read
per control) and that I would A/B it. Neither the helper nor the A/B was
built. If you confirm, the lane is 4–6 commits, about 1–1.5 days (estimate):
the setter, keeping `nil` the default; the helper (faint→normal,
normal→bold, bold stays bold); `Text`; the controls and chrome by family (58
`ANSIRenderer.colorize(` calls in 28 files, plus the sites that build a style
without it); tests under `.bold`; and the A/B on the quiet machine. Some
terminals draw bold as a brighter colour (Terminal compatibility survey.md), which the
heavier weight inherits.

### B3. Size classes are settable, and nothing TUIkit draws reads them

`\.horizontalSizeClass` and `\.verticalSizeClass` default to `.regular`, as
macOS reports for any window. They are settable, as SwiftUI's are, for an
app's own views to read.

I believe macOS's own views ignore a written `.compact`, but I have not been
able to confirm that for `NavigationSplitView`. On iOS, compact collapses a
split view into a stack.

If you would rather a terminal narrower than some width report `.compact`,
that is a cheap change: the run loop already publishes the terminal size each
frame. It would make split views worth teaching to collapse.

The same reasoning covers `\.displayScale` and `\.isLuminanceReduced`:

- They are settable channels, and nothing TUIkit draws reads them.
- macOS's text ignores both; that was measured.
- `\.dynamicTypeSize` is the same, which also answers the old refusal of
  `DynamicTypeSize`. The refusal was true about terminals and wrong about
  the API, because macOS reads `.large` and ignores writes for text too.

**Decided 2026-10-12: follow what an app sets, and change no default.** An
app decides when a class is `.compact`, and TUIkit adapts where it can. (You
asked the cost on 2026-10-04; the 2026-10-05 answer priced reporting
`.compact` at nothing and the views that adapt to it, chiefly a split view
collapsing, at one to two days.) Since A6, `.viewAligned` reads both classes
for its paging limit; nothing else does. Following a written `.compact` means,
by SwiftUI's own behaviour on iOS and iPadOS:

- a popover adapts to a sheet (`presentationCompactAdaptation`, A21);
- `NavigationSplitView` collapses into a stack showing
  `preferredCompactColumn` (A21);
- `Table` hides its headers and every column after the first (Apple's
  `Table` documentation);
- a `.sidebarAdaptable` `TabView` shows tabs instead of a sidebar.

`\.dynamicTypeSize` and `\.displayScale` stay channels nothing reads: the
terminal owns the font and the cell size. **Lane owed:** 5–7 commits, about 3
days (estimate): the popover adaptation, the split-view collapse, the compact
`Table` and the compact sidebar tab view, each with tests.

### B4. `DynamicProperty.update()` writes back (superseded by lane DYNP)

The owner ruled this a bug to fix, carefully for performance (2026-10-05).
Lane DYNP made `update()` write back what it changes, as SwiftUI's does, at
no measured per-frame cost. What the write-back covers, and where TUIkit
still differs from SwiftUI, is in
[`DynamicProperty update write-back (DYNP).md`](<DynamicProperty update write-back (DYNP).md>),
B-DYNP-1 onwards.

### B6. `safeAreaInset` puts the bar beside the view; there is no safe area

*`View.safeAreaInset(edge:alignment:spacing:content:)` (both edge types),
`View.safeAreaBar(edge:alignment:spacing:content:)` (both); still refused:
`View.ignoresSafeArea(_:edges:)`, `SafeAreaRegions`,
`GeometryProxy.safeAreaInsets`, and the `ignoresSafeAreaEdges:` overloads of
`background`/`overlay`*

SwiftUI's `safeAreaInset` does two things: it lays the bar beside the view,
and it grows the view's safe area by the bar. Measured (W05 brief, probes E
and q13–q15), the second is what lets a `ScrollView` run *under* the bar, a
style `.background(.red)` extend beneath it, and `ignoresSafeArea()` reach
into it.

**Shipped:** the first half only. The bar sits beside the view, which is
proposed what the bar leaves; spacing `nil` is none (measured), a bar wider
than the view sets the width, `alignment:` places the bar across the view, and
two bars stack outward. `safeAreaBar` lays out identically — its extra is the
scroll-edge effects, which need content under the bar. The bar renders at the
layer identity `.overlay` uses, so adding one moves no `@State`.

**What this gives up, silently:** in ported code, a scroll view stops at the
bar instead of running under it, and an existing style background on the
view does not extend beneath it. In a cell grid that is visible only as
colour under the bar's blank cells — the bar's glyphs cover anything under
them — and nothing that would *observe* a safe area compiles, so no code can
depend on one being there.

**The fuller version (SA-B)** is a real safe area: a `safeAreaInsets` value
set by the producers and propagated by adjacency through every container
(stacks, `ZStack`, `Layout`, `Grid`, frame, padding — which consumes it —
overlay/background, and `ScrollView`/`List`, which turn it into content
margins and extend their viewport under the bar); `ignoresSafeArea`; style
backgrounds and overlays extending; `GeometryProxy.safeAreaInsets`;
`SafeAreaRegions`. Four to six days, a context field on the layout hot path
(a single `Int` there has measured +2.4%), and a measure/render-parity risk at
every container that decides adjacency — for colour under a bar's blanks. It
is the route if the scroll-edge effects (refusal review O7) are to mean
something.

`safeAreaPadding` shipped with Wave 10's `contentMargins`: for non-scrolling
content it is padding, and for a scroll view it is a content margin along the
axes it scrolls (B25).

**Decided 2026-10-12: SA-B is not built.** You asked on 2026-10-04 what
safe-area support is worth. The 2026-10-05 answer: very little here. With no
notch and no system bars, the only producers would be TUIkit's own bars, and
the payoff is colour under a bar's blank cells; it would matter only if
toolbars wanted content scrolling beneath them. You were not convinced, so the
half that shipped is the behaviour, kept as a deliberate deviation
([Deliberate deviations from SwiftUI.md L10](<../Deliberate deviations from SwiftUI.md#l10-safeareainset-puts-the-bar-beside-the-view-there-is-no-safe-area>)). The
refused symbols above stay refused, and B25's fuller version, which is SA-B,
goes with it. The entry stays as the record of what the declined version was.

### B8. `KeyboardShortcut.Localization` is recorded, and every strategy behaves as `.custom`

*`KeyboardShortcut.Localization` (`.automatic`, `.withoutMirroring`,
`.custom`), `KeyboardShortcut.localization`,
`KeyboardShortcut.init(_:modifiers:localization:)`,
`View.keyboardShortcut(_:modifiers:localization:)`*

On macOS, `.automatic` (the default) does two things.

- It remaps a shortcut whose character is awkward on the user's layout. `⌘[`
  needs ⌥5 on a German keyboard, so it becomes `⌘Ö`.
- It mirrors a directional shortcut under a right-to-left layout.

`.withoutMirroring` remaps but does not mirror, and `.custom` does neither.

**Shipped:** the type, the three values, the stored property (compared, so
`KeyboardShortcut("a", localization: .custom) != KeyboardShortcut("a")` as on
macOS), the initializer and the modifier. All three behave as `.custom`.

That is honest on its own, because neither half has anything to act on:

- A terminal reports the character a key typed, never the key's place on
  the keyboard. A shortcut already matches its character however the
  layout types it, and there is no US-layout position to remap from.
- TUIkit lays out left to right only (B1 in the main decisions doc), so
  there is nothing to mirror.

**The fuller version:**

- *Mirroring* comes free with right-to-left layout, if B1 is ever taken up.
  Mirror the directional pairs under `.automatic` and leave them under the
  other two.
- *Remapping* would need the key's position. The kitty keyboard protocol's
  "report alternate keys" enhancement sends the base-layout key alongside
  the character, so it is the same negotiation as the kitty protocol's
  (A4, shipped 2026-10-05), plus a
  remapping table. That table is AppKit's, and it is not public, so it would
  have to be inferred per layout. I would not do it: an app that wants
  layout-aware shortcuts in a terminal is better served by bare keys.

**Decided 2026-10-12: mirror once right-to-left lands** (B1); one commit then,
the pairs under `.automatic` in a right-to-left environment. You asked how big
AppKit's tables are, and whether TUIkit could copy them:

- **The mirroring table is 10 characters, 5 pairs** (measured on macOS 15.8
  through AppKit's own mirroring call over U+0020–U+2FFF): `(`↔`)`, `<`↔`>`,
  `[`↔`]`, `{`↔`}`, `←`↔`→`. `NSMenuItem.h` in the macOS SDK documents the
  same list, so TUIkit can write it from the documentation and copy nothing.
- **The remapping is not a data file.** It is compiled AppKit code
  (`NSKeyboardShortcut`'s localization methods, found through the Objective-C
  runtime), possibly an algorithm over the layout's key map plus a cache of
  well-known shortcuts; its size is unknown, since sizing it would mean
  switching the system's input source through many layouts. It is Apple's
  proprietary code, so it cannot be copied.
- **Matching AppKit is not table-free either.** AppKit remaps only a shortcut
  the current layout cannot type (`NSMenuItem.h`). The kitty protocol's
  base-layout key gives a positional fallback, which TUIkit already uses for a
  Ctrl or Alt chord on a non-Latin key, but matching every shortcut by
  position would also move the reachable ones (⌘Z on the key labelled W on
  AZERTY), and a terminal does not say which characters the user's layout can
  type. Over ssh the local machine's layout is not the user's either. So the
  remap stays out until there is a source for that.

### B10. Item-provider drag and drop stays in the app, and only cancel and forbidden change a drop

*`View.onDrag(_:)`, `View.onDrag(_:preview:)`, `View.itemProvider(_:)`, `View.onDrop(of:isTargeted:perform:)`,
`View.onDrop(of:delegate:)`, `DropDelegate`, `DropInfo.hasItemsConforming(to:)`,
`DropInfo.itemProviders(for:)`, `DropOperation` (+ `.Set`), `DropProposal`*

**Shipped:**

- On Apple platforms, the four modifiers and the delegate, riding TUIkit's
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
  source application is told. A TUIkit drag has no badge and never leaves the
  app, so the delegate's `performDrop` is where any difference has to be
  made.
- *`operationOutsideApplication`.* It is recorded and never applies.

`DropOperation.Set`'s raw values are TUIkit's own: SwiftUI does not document
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
`DropInfo` reports): `+` in the accent colour for `.copy`, `↗` in the accent
for `.alias`, `⊘` in the error colour for `.forbidden`, nothing for `.move`.
`onDrop(of:isTargeted:perform:)` proposes `.copy`; `onDrop(of:delegate:)`
proposes what `dropUpdated` last returned, once `validateDrop` said yes.
`↗` and `⊘` are corpus rows now, measured one cell by `advance_probe.py` on
Apple Terminal, iTerm2, Ghostty, Warp and tmux (Terminal compatibility
survey.md, "The drop-operation badge"; ink unmeasured). Three choices of the
lane's own are in [B-BITEMS1-1](<Default focus, drop badges and stack spacing (BITEMS1).md#b-bitems1-1-a-delete-wears-no-badge-and-only-the-item-provider-drops-propose-one>):
`.delete` and `.cancel` wear none, TUIkit's own `dropDestination` and a
list's drops propose nothing, and no destination highlight shifts colour
(TUIkit draws none for these views; the app's `isTargeted` does).

### B19. A guide does not travel out of a view type of the app's own

*`View.alignmentGuide(_:computeValue:)`, `Layout.explicitAlignment(of:in:proposal:subviews:cache:)`*

SwiftUI resolves a guide recursively through everything between it and the
container aligning on it. TUIkit now does the same through `VStack`,
`HStack`, `ZStack`, `.padding` (each moving the guide by where it put its
content) and a custom `Layout` (`explicitAlignment`), which closes the gap the
compatibility notes recorded: `.alignmentGuide(.decimalPoint)` on a `Text`
inside each row of a column aligns the rows on the point.

It stops at a view type of the app's own: a guide inside
`struct Row: View`'s `body` does not travel out of `Row`. A container decides
whether to ask a child about guides from a static witness
(`View._providesAlignmentGuide`), which the framework's containers now
forward from their content; an app's view states none, so it is not asked. It
also stops at any modifier that does not translate guides (`.border()`,
`.frame`, `.offset`): there a wrong position is the alternative.

**The fuller version** makes every composite view forward its `body`'s
witness by default (`Body._providesAlignmentGuide`, `false` for a `Never`
body), so the question reaches into every body type. The cost is where the
witness is read: `ChildView` construction, per child per walk, would recurse
through the child's whole static body type, not only the framework containers
in it. That is O(static subtree) per construction, which the per-pass measure
memo keeps to roughly O(nodes × depth) witness calls a frame — small on paper,
and exactly the kind of thing that has measured as a percent on `fanout` and
`deep` before. Half a day, plus an A/B on `deep`, `kitchensink`, `megalist`
and `table` on a quiet machine before it ships.

**A/B owed for what did ship.** The witness now forwards through `TupleView`,
`Group`, `ForEach`, `ConditionalView`, `Optional`, the three eager stacks and
padding, so constructing a `ChildView` for a container child ORs its
framework subtree's witnesses instead of reading one constant. A tree with no
guide still pays one stored `Bool` per child at layout time, as before; the
added cost is in the construction, and it was not measured (no benchmarks on
a shared machine). `deep` and `kitchensink`, the structure-heavy scenarios,
are the ones to A/B. One more: an app's own `Layout` cannot be known not to
override `explicitAlignment`, so inside a stack it is laid out once more per
walk to answer the stack's guide question (the framework's layouts state
`_definesExplicitAlignment = false` and are asked only when a subview may
hold a guide). Stress's `customlayout` scenario is the one to A/B for that.

**Decided 2026-10-12: explore the cost**, of the current version against the
fuller one at least. (You asked for my recommendation on 2026-10-04; on
2026-10-05 I recommended the fuller version, gated on an A/B, because a guide
inside an app's own row view, decimal alignment say, is how SwiftUI code is
commonly written; if `deep` or `kitchensink` cost more than about 1%, it comes
back to you before landing.) **Lane owed**, about a day (estimate, more than
the half day above): the witness defaults to `Body._providesAlignmentGuide`
with `false` for `Never`, and stops where a body holds its own type, since
`Optional` and the conditional view forward and a recursive body would
recurse (an if/else in both arms would be 2ⁿ); `_handsOverChildren` already
defaults to its body's this way. Tests for recursive and if/else bodies. The
A/B can price all three versions on today's tree: a forwarding-off arm, where
the containers' witnesses return `false` and the modifier's stays `true`,
stands in for the original, which is 1,357 commits back. Scenarios: `deep`,
`kitchensink`, `table`, `customlayout`, `fanout`, `anyview`, and `megalist`
only where its verdict reproduces at more than one path layout. A-GUIDE-2
needs the fuller version whichever way it is answered.

### B20. A stack's `spacing: nil` is the default preference, not each pair's

*`HStack.init(alignment:spacing:content:)`, `VStack`, `LazyHStack`, `LazyVStack`,
`HStackLayout`, `VStackLayout`, `ViewSpacing`, `Layout.spacing(subviews:cache:)`*

The stacks now take SwiftUI's `spacing: Int? = nil` (it was `Int = 1` and
`Int = 0`), so `HStack(spacing: nil)` compiles. In SwiftUI, `nil` means "for
each pair of neighbours, the distance their `ViewSpacing`s ask for". Here
`nil` resolves, at `init`, to the distance two views of default preference ask
for — one column in a row, none in a column — and is used between every pair.

The two readings differ less than they sound. `ViewSpacing` has SwiftUI's
surface only: `init()` (one column beside, no row above or below), `.zero`,
and unions, which take per-edge maxima. So every preference a TUIkit view can
state is the default or less, edge by edge, and every vertical edge is 0.
Each pair's distance in a column is therefore always 0 — exact — and in a row
it is 1 unless BOTH neighbours are custom layouts whose
`spacing(subviews:cache:)` asks for no space on the facing edges. That pair
gets a column here and none in SwiftUI. A custom layout that spaces its
subviews by `LayoutSubview.spacing` does get the per-pair answer.

**The fuller version** resolves `nil` per pair inside the stacks: a stored
flag on `ChildView` saying the child can state a preference (it fits the
struct's tail padding), and per-gap spacings through
`distributeLinearSpace`, `totalLinearSpacing`, the assembly in both cores, the
lazy windows and the guide placement. That is a structural change to the
hottest layout path for a case that needs two zero-spacing custom layouts side
by side. A day, and the plan's rule applies: an A/B on `deep`, `kitchensink`,
`megalist` and `table` on a quiet machine before it lands. What shipped
changes nothing on the stack path — `nil` becomes the old constant at `init` —
so no A/B is owed for it.

**Decided 2026-10-12: attempt the fuller version, mindful of performance.**
(You asked for an example on 2026-10-04; on 2026-10-05 I gave
`HStack { MyLayoutA(); MyLayoutB() }`, both asking for no space on the facing
edges, and advised against it. Your ruling overrides that.) **Lane owed:** 2–3
commits and an A/B on `deep`, `kitchensink` and `table` (`megalist` with
B19's caveat). The shape that keeps the common path as it is (estimate): a
static witness, "states a spacing preference", true only for `Layout`-backed
views and their forwarding wrappers; a per-stack flag set while children are
built; and per-gap distances only where two neighbours both state one.

**Shipped 2026-10-13 (BITEMS1):** `HStack`, `LazyHStack` and `HStackLayout`
resolve `spacing: nil` per pair of neighbours, so `HStack { MyLayoutA();
MyLayoutB() }`, both asking for no space on the facing edges, draws them
touching. Probing it found SwiftUI's `ViewSpacing` arithmetic is not the one
this entry describes: a stated edge outweighs a default one, so ONE
neighbour asking for none is enough (`Tools/SwiftUIProbes/Stack spacing per
pair/spacing.out`). That shipped first, as
[B-BITEMS1-2](<Default focus, drop badges and stack spacing (BITEMS1).md#b-bitems1-2-a-stated-spacing-edge-outweighs-a-default-one-as-in-swiftui>),
and a gap is the pair's wherever either neighbour states a preference. The
shape is the estimate's: a static witness, `View._statesSpacingPreference`
— true for a `Layout`'s view and a `Subview`, forwarded by `ForEach`,
`Group`, `if`, `Optional` and the single-content wrappers (the environment
modifiers, `.background`, `.border` and `.offset` among them, as SwiftUI's
measured), and by padding and a frame on the edges they leave alone — read
once per row, so a row whose content holds no layout asks no child anything;
and `StackGaps`, which carries no preferences on that common path. A column
needed nothing: every vertical distance is 0 either way. Where it differs from
SwiftUI (an `AnyView`, a frame that exactly fits its content, an app's own
view, a nested row) and the cost are in
[B-BITEMS1-3](<Default focus, drop badges and stack spacing (BITEMS1).md#b-bitems1-3-a-rows-spacing-nil-per-pair-reaches-layouts-and-the-wrappers-that-move-no-edge>).

### B22. The content levels, and the two- and three-style `foregroundStyle`

*`HierarchicalShapeStyle`, `HierarchicalShapeStyleModifier`,
`View.foregroundStyle(_:_:)`, `View.foregroundStyle(_:_:_:)`*

The compatibility doc declined all four on two grounds. Neither held up:

- **Ambiguity.** A `.secondary` on `ShapeStyle` beside `Color.secondary` does
  not make `.foregroundStyle(.secondary)` ambiguous, because the `Color`
  overload is the disfavoured one. That is how SwiftUI is built too.
- **"A glyph has one layer."** True for a symbol, but the second and third
  styles are also what `.secondary` and `.tertiary` resolve to below the
  modifier, and a terminal honours that fully.

**What shipped.** With no foreground style above, the levels are the palette's
tiers, so `.foregroundStyle(.secondary)` paints what `Color.secondary` did.
`.quinary` is the quaternary tier at half strength. Under a `foregroundStyle`,
the levels are that style at macOS's label alphas (1, 0.5, 0.26, 0.1, 0.05),
composited at the cell. The two- and three-style forms name the second and
third levels outright; the levels past a named one are it faded by the same
ratios. A single-style `foregroundStyle` below clears the named levels, so
`.secondary` derives from the nearer primary.

**What moves for an app.** One case changes:
`.foregroundStyle(.secondary)` on a non-`Text` view, below an explicit
`foregroundStyle`. That is now the outer style at half strength, where it was
the palette's secondary tier, which is SwiftUI's behaviour.
`Text("a").foregroundStyle(.secondary)` is unchanged, because it still takes
`Text`'s `Color` overload (§3's remaining refusal).

**Enhancements to consider:**

- The 0.5 / 0.26 / 0.1 / 0.05 strengths are macOS's light-appearance label
  alphas. At 0.1 and 0.05 a faded glyph's colour is nearly the surface's, which
  the rendered contrast floor may lift. That is fine for a tint, but it is
  worth a live look in the 16- and 256-colour modes.
- A fuller version would carry the levels per palette (a palette naming its
  own faded tiers for an arbitrary foreground). That is a palette-protocol
  change, so I left it for you.

**Decided 2026-10-05** (you asked for my recommendation on 2026-10-04): the
cheap one, a live look at the faint tiers in 16 and 256 colours, owed; the
per-palette tiers are skipped for now.

### B25. `safeAreaPadding` is padding, or a scroll view's content margin

*`View.safeAreaPadding(_:)` (both), `View.safeAreaPadding(_:_:)`*

As B6 planned. Measured in SwiftUI: on a vertical `ScrollView`,
`safeAreaPadding(15)` puts 15 of content inset at the top and bottom (it
scrolls with the content, and adds to `contentMargins`) and narrows the view
itself by 30 — across its axis it is padding. Nested calls add.

**Shipped:** exactly that geometry, for a `ScrollView` that is the modifier's
content itself or behind modifiers that only set the environment
(`.scrollIndicators`, `.contentMargins`, `.scrollPosition` and the like).
Anything else — including a scroll view behind `.padding` or `.frame`, which
in SwiftUI does not reach the edges the safe area is on — is padded.
`nil` is one cell, what SwiftUI's 16-point default is to `.padding()`.

**What this gives up**, and B6 already accepted: SwiftUI also extends a
`List` or a `TextEditor` into the safe area and insets its rows (measured: a
`List`'s first row moves down 40 under `safeAreaPadding(.top, 40)`, with the
list itself still at the top). Here those are padded whole, so their chrome
moves in with their rows. The fuller version is B6's real safe area, which
you declined on 2026-10-12, so this stays as shipped.

### B27. Scroll phases: `.interacting` until a quarter of a second of quiet, and no velocity

*`ScrollPhase` (all five cases, `isScrolling`, `debugDescription`),
`ScrollPhaseChangeContext` (`geometry`, `velocity`), `View.onScrollPhaseChange(_:)`
(both); `CellVector`, new, as the counterpart of `CGVector`*

Measured in SwiftUI: the action runs once on appear, `.idle` to `.idle`; a
`scrollTo` without animation changes no phase; one with animation goes
`.idle` → `.animating` → `.idle`. I could not measure a mouse wheel: events
synthesized into an offscreen hosting view do not reach its scroll view.

**Shipped:** a user scroll — wheel, keys, scrollbar, a drag's auto-scroll,
either axis — makes the view `.interacting`; it returns to `.idle` once the
steps have stopped for 250 ms (fifteen 60 Hz frames, a wake requested for the
moment) and nothing is held (a scrollbar drag or auto-repeat). A terminal
reports no gesture phases, so the end of a scroll is inferred from quiet:
wheel ticks and key repeats arrive well inside 250 ms, a pause to read does
not. `.tracking`, `.decelerating` and `.animating` are never produced — there
is no touch, no momentum, and TUIkit does not animate scrolling, so an
animated `scrollTo` is a jump here and changes no phase. `velocity` is always
`nil`; SwiftUI's is optional for the same reason.

**What you might want different:**

- *The quiet interval.* Shorter makes "scrolling ended" arrive sooner and
  splits a slow wheel into several scrolls; longer the reverse. It is one
  constant (`ScrollPhase.quietNanos`).
- *A measured velocity* (lines per second over the last few steps) is cheap
  if a use turns up; I did not invent one nobody reads.
- *`.animating`* comes with animated scrolling, which is its own feature.

**Decided 2026-10-12: measure a velocity, if it is cheap.** It is, at run
time (estimate): on each user scroll step a subtraction, a division, an
averaging step and about three stores, and 24 bytes per scroll handler, which
is a class, not the render context; nothing per frame, since it is read only
when a phase change is reported to an observer. B91's drag estimator can be
shared.

**Asked 2026-10-12: what the number should mean.** TUIkit reports two
changes. From idle to interacting, one step in, there is no rate yet: `nil`.
From interacting to idle, 250 ms after the last step, the view is still.
SwiftUI documents the velocity as the speed "at the time of the scroll phase
change", and measured (0, 0) at its appear call and at both changes of an
animated `scrollTo` (macOS 15.8, session notes `DECB/probe/phase`); its value
when a user's scroll starts decelerating could not be driven offscreen. Read
literally, TUIkit's change to idle reports (0, 0), and the number never says
anything. **Recommended:** report the speed the scrolling had when its steps
stopped. TUIkit's one change to idle stands for SwiftUI's two (interacting to
decelerating, then to idle), and the speed belongs to the first; B91's
precedent, measured on macOS, is that a still pointer keeps its last motion's
velocity. That is a deliberate deviation, recorded when it ships.

**Owner, 2026-10-12 (later):** (0, 0) at both changes, as SwiftUI reports
it, not the last speed. So no estimator is built: the change to
`.interacting` and the change to `.idle` both report (0, 0), and the
velocity is never `nil`. The owner also asked whether any terminal extension
reports more about a wheel or a trackpad. None reports a delta, a phase or a
velocity: [Terminal compatibility survey.md](<../../Terminals/Terminal compatibility survey.md#wheel-reports-per-notch--a-hosts-choice-not-normalised>)
records what a notch sends, and [Future options.md](<../../Future options.md>)
parks SGR-Pixels (mode 1016).

**Shipped 2026-10-13 (SCROLLB):** the velocity is `(0, 0)` at every report —
the first frame's and both changes — and never `nil`.

### B28. `scrollIndicatorsFlash` returns the view: the indicators are already showing

*`View.scrollIndicatorsFlash(onAppear:)`, `View.scrollIndicatorsFlash(trigger:)`*

A flash exists because an overlay scroller is hidden until something scrolls.
A terminal's bar, or its "N more" lines, is drawn on every frame the content
overflows, from the first — as macOS's legacy ("always show") scrollers are,
under which a flash changes nothing either. SwiftUI flashes only the
indicators configured to be visible, and those are the ones already drawn.
So both join the medium-guaranteed modifiers (`MediumGuaranteedModifiers.swift`),
with a test of the guarantee: an overflowing view's first frame shows its
indicator in either style.

**The fuller version** would be a brief highlight of the bar — its focus pulse
for half a second — to draw the eye, as a flash does. About two hours:
the bar memo is keyed on the pulse already, and the trigger needs a
per-view "last value" and a wake. I would only do it if a port asks.

**Decided 2026-10-12: implement it.** (On 2026-10-04 you pointed out that
TUIkit supports automatic visibility; the 2026-10-05 answer was that TUIkit's
`.automatic` shows the bar whenever the content overflows, with no fading, so
the bar is already visible whenever a flash could matter, and the alternative
is a half-second pulse.) **Lane owed:** 2–3 commits, half a day to a day
(estimate), more than the two hours above: bars are drawn in at least five
views (`ScrollView`, `List`, `Table`, `TextEditor` and the field chrome);
`trigger:` needs a last-value store per view (a small `_*Core` with negative
state indices); and a focused bar already breathes, so the flash needs a
distinct peak within the focus and selection colour rules. A view that is not
flashing pays nothing.

**Shipped 2026-10-13 (SCROLLB):** both forms, in `ScrollView` (both bars and
its "N more" lines), `List` and `Table` (bar or lines) and `TextEditor` (its
bar). The field chrome draws no scroll indicator (`FieldChrome` is the caps
only), so there is nothing there to flash. A flash is half a second — ten
steps of three 1/60 s ticks — rising in two, held for four, fading over four;
the thumb and arrows, or the lines, go from where they rest to one
`hoveredForeground` step past the focused breath's far end (the focus
identity's own colour, so a focused bar's flash is told from its breathing),
drawn still, without the breath's runs. `trigger:` keeps its last value in a
`_ScrollIndicatorsFlashCore` (state index −150, a new reserved range); the
scrollable keeps when it first drew, for `onAppear:`. A scrollable that is not
flashing asks for no frame; where it draws an indicator, the flash costs one
environment read a frame. The peak and the shape are the lane's call:
[B-SCROLLB-1](<Scroll indicator flash and bounce (SCROLLB).md#b-scrollb-1-a-flash-peaks-one-hover-step-past-a-focused-bars-breath>).

### B30. The `Transaction` scroll members: what "no adjustment" suspends

*`Transaction.scrollTargetAnchor`, `Transaction.scrollContentOffsetAdjustmentBehavior`
(and `ScrollContentOffsetAdjustmentBehavior`, whose `differentShape` map entry
goes), `Transaction.scrollPositionUpdatePreservesVelocity`*

The run loop already publishes the transaction a change was made under for the
frame that renders it, so a scroll view can read all three where it decides.

- **`scrollTargetAnchor`**: preferred to a `.scrollPosition(id:anchor:)`
  modifier's anchor (SwiftUI's documentation says so); for a `ScrollPosition`
  request or a `ScrollViewProxy.scrollTo` that names an anchor of its own, the
  call's wins, and one that names none takes the transaction's. SwiftUI does
  not say which wins there; the call is the more specific statement.
- **`scrollContentOffsetAdjustmentBehavior = .disabled`** suspends a declared
  anchor's adjustments for the change: a `ScrollView`, `List` or `Table`
  following its tail does not follow, which leaves it short of the new tail
  and so releases the follow, exactly as a user scroll does (engagement is
  positional); a `List`, a `Table` or a windowed lazy stack holding a row
  (`.anchorPosition(.row)`) lets it go and holds it again from the line the
  change left it on. The opening placement is not an adjustment and is kept;
  an app's own write to a bound `.anchorPosition` still jumps.
- **`scrollPositionUpdatePreservesVelocity`** is recorded and met by the
  medium: no scroll here has momentum, so nothing is moving for a
  programmatic change to stop or spare.

`Transaction` lives below `UnitPoint`, and every `Binding` carries one
inline, so the anchor is stored in two bytes — hundredths of the viewport,
finer than any terminal's row — and the switches share one byte with
`disablesAnimations`. A binding grows by two bytes and gains no padding (a
titled `Toggle`: 195 → 197, `ControlLayoutPaddingTests`); stored as two
`Double`s and three `Bool`s it grew by twenty-four and left five undefined.

**You asked (2026-10-12) what the gap is, and what I recommend.** Measured on
macOS 15.8 (a 300×200 window, rows 20 high; session notes `DECB/probe/anchor`
and `DECB/probe/disabled`):

- **`ScrollViewProxy.scrollTo`:** the call's anchor wins over the
  transaction's, and with none the transaction's applies. That is TUIkit's
  rule exactly.
- **`ScrollPosition.scrollTo(id:anchor:)`:** SwiftUI ignored the call's anchor
  (`.top` and `.center` both landed at the minimal position) and applied the
  transaction's even over a `.bottom` call. TUIkit honours the call's anchor
  first. That looks like a SwiftUI defect, so TUIkit's rule stays, recorded as
  a deliberate deviation
  ([Deliberate deviations from SwiftUI.md R11](<../Deliberate deviations from SwiftUI.md#r11-scrollpositionscrolltoidanchor-honours-its-own-anchor>)).
- **`.disabled`** stops SwiftUI's lazy-stack bottom follow and its hold of the
  top row on an insertion above, as it stops TUIkit's follows. SwiftUI ignores
  it for an eager `VStack`, which follows anyway; TUIkit treats eager and lazy
  alike. Kept, and recorded
  ([Deliberate deviations from SwiftUI.md R12](<../Deliberate deviations from SwiftUI.md#r12-no-adjustment-suspends-an-eager-stacks-follow-too>)).
- **The larger gap is the default.** With no `scrollPosition` at all, SwiftUI
  keeps the top row in place when rows are inserted above it (a lazy stack,
  one insertion: the offset moves 200 → 300). TUIkit's Window default, from
  your 2026-07-17 anchoring spec, leaves the offset in line coordinates, so the
  rows shift and a "load earlier messages" list jumps.

**Shipped 2026-10-12 (SCROLLANCHOR):** the reader that was missing inside
TUIkit — a windowed `LazyVStack`'s `.anchorPosition(.row)` hold ignored "no
adjustment". All three of the stack's paths now let the row go, and adopt it
on the change's own frame where the change left it. `List` and `Table` adopt
it there too: they adopted it a frame later, where the NEXT change left it,
so a second change, made without the transaction, went unheld as well.

**Asked 2026-10-12:** keep TUIkit's Window default and record it as a
deviation, or hold the top row by default as SwiftUI does? The second reverses
part of `Scroll anchoring.md`'s first slice for views that declare no anchor,
at a cost not measured.

**Owner, 2026-10-12 (later):** follow SwiftUI. With no anchor declared, rows
inserted above the top row keep the reader's place. Make it configurable
either way, and redesign TUIkit's existing anchoring API where that makes it
cleaner (pre-1.0, no compatibility spellings). **Lane owed** (SCROLLANCHOR),
together with the missing reader above; the cost is measured in that lane.

**Shipped 2026-10-12 (SCROLLANCHOR):** with nothing else holding it, a scroll
view keeps the row at the top of its viewport where it is as rows are
inserted, removed or resized above it — a lazy stack on all three of its paths,
`List` and `Table` — and holds nothing at the top, while following the tail,
for a seek, or for a change made under "no adjustment".
`.scrollWindowHold(.offset)` (TUI-specific: no SwiftUI spelling expresses it,
measured) keeps the offset in lines, the old default. Design in `Scroll
anchoring.md` §5; the lane's own entries in [Scroll anchoring default
(SCROLLANCHOR).md](<Scroll anchoring default (SCROLLANCHOR).md>), among them
A-SCROLLANCHOR-1: `List` and `Table` hold as the stacks do, though macOS's
`List` keeps its offset (measured); you kept that on 2026-10-13, for one rule
across scrollables. Cost: neutral in the A/B (no scenario past +0.8%,
2026-10-13).

### B31. Bounce behaviour gates the overscroll allowance

*`ScrollBounceBehavior` (`.automatic`, `.always`, `.basedOnSize`; its
`differentShape` map entry goes), `View.scrollBounceBehavior(_:axes:)`,
`EnvironmentValues.verticalScrollBounceBehavior`,
`EnvironmentValues.horizontalScrollBounceBehavior`*

The refusal review called this a cheap alias over `ScrollOverscroll`, and the
two are close but not the same: SwiftUI's bounce springs back, TUIkit's
overscroll stays (that is what makes a deliberate push readable, §1.5 of
`Scroll anchoring.md`), and the allowance's size is TUIkit's own setting.

**Shipped:** the behaviour decides *when* the allowance applies, and
`.scrollOverscroll` keeps deciding *how far*:

- `.basedOnSize` — only while the content overflows, so content that fits
  sits still. This is the reason the modifier is written in practice, and it
  is the opt-out from your 2026-07-31 decision that a fitting view may still
  be pushed.
- `.always` and `.automatic` — whatever the content's size: TUIkit's default,
  as `.always` is SwiftUI's.

With no allowance (TUIkit's default) nothing is pushed at all, which is also
what macOS does under a mouse wheel. The allowance is vertical only, so the
horizontal value is recorded and decides nothing yet.

**The fuller version** is a real bounce: a default allowance of a line or two
under `.always`/`.automatic`, sprung back once the scroll phase returns to
idle (B27 gives the moment). Half a day, and it changes the default feel
of every scrollable, so it is yours to want.

**Decided 2026-10-12: a bounce, if it is cheap.** (You asked on 2026-10-04
whether a full bounce is easy; the 2026-10-05 answer proposed the scope
below.) It is cheap at run time (estimate): nothing new per frame for a view
that is not overscrolled, since the allowance and excursion tests run already;
one wake request per step while it is; a spring-back of one to two frames,
re-sliding a buffer already drawn; one flag per handler. **Scope:** `.always`
gets a sprung allowance of one or two lines; `.automatic` keeps today's feel;
an explicit `.scrollOverscroll` allowance keeps staying where it was pushed,
since that is TUIkit's deliberate-push signal. **Lane owed:** 2–3 commits,
half a day to a day, which includes detecting the end of a scroll without a
phase observer (shared with B27) and the spring-back in `List` and `Table`.
Nothing is paid by an app that does not write `.always`.

**Shipped 2026-10-13 (SCROLLB):** under `.always` an end the app gave no
allowance gets a sprung one — two lines, one in a view under eight lines tall
([B-SCROLLB-2](<Scroll indicator flash and bounce (SCROLLB).md#b-scrollb-2-the-bounce-is-two-lines-one-in-a-view-under-eight-lines-tall-per-end>)).
A push into it is held while the user's steps keep coming, and once they have
been quiet for 250 ms (B27's `ScrollPhase.quietNanos`, no phase observer
needed) it springs back a line a 50 ms frame, in `ScrollView`, `List` and
`Table` alike (`ScrollableOffsetState.settleOverscroll`). `.automatic` and
`.basedOnSize` are as they were, and an allowance the app asked for stays
where it was pushed under every behaviour. Cost: a bounce-free view's frame is
unchanged but for one more comparison as its allowance is resolved; a pushed
view asks for the frames of its spring.

### B33. Slider ticks, neutral value, enabled bounds and thumb visibility, read from the documentation

*`SliderTick`, `SliderTickBuilder`, `SliderTickContent`,
`SliderTickContentForEach`, `TupleSliderTickContent`, the three `Slider`
initialisers with `neutralValue:`/`enabledBounds:`/`ticks:`/`tick:`,
`View.sliderThumbVisibility(_:)`*

All macOS 26, so none of it was measured; what shipped follows SwiftUI's
documentation, and each reading below is a guess at the look:

- **Ticks:** a `╵` on the row under the track at each tick's value, at the
  column the knob takes for that value. Labels go on the row under that,
  centred on their marks; a label that would touch the one before it is left
  out rather than overlap. The rows exist only when there are ticks (or
  labels), and the row's other contents stay on the track's row.
- **`neutralValue:`:** the fill runs from the neutral value to the knob, on
  whichever side. For the knob and dot styles this is exact. For the fill
  styles (`.block`, `.bar`, the custom ones), the track is put together from
  whole cells of renders at the neutral value and at the value, so the edge at
  the neutral value is a whole cell. A neutral value draws the track as cells,
  never as a picture.
- **`enabledBounds:`:** every input stops at the bounds, and a value the app
  writes outside them is brought inside, as `bounds` already does. The track
  beyond them is drawn in a disabled slider's colours.
- **`currentValueLabel:`:** SwiftUI says not every style shows it. TUIkit's
  slider draws a numeric read-out, so a label given here replaces it.
- **`sliderThumbVisibility(.hidden)`:** the knob's cell shows the fill's end.
  On the `.marker` track, which has no fill, nothing then shows the value.

**Fuller versions:** sub-cell edges at the neutral value for the fill styles
(the ramps only grow rightward, so a leftward edge needs mirrored glyphs most
fonts lack); and a measured look once a macOS 26 machine is available.

### B34. A focused-value reader drawn ahead of its publisher catches up a frame later

*`FocusedValue`, `FocusedBinding`, `View.focusedValue(_:_:)`,
`View.focusedSceneValue(_:_:)`*

SwiftUI's readers are mostly `Commands` and toolbar items, which are updated
outside the view graph. A terminal has neither, so TUIkit's readers are views,
and they usually sit beside the publisher — a detail pane next to a list, a
status line above it — and are drawn before it in the same walk.

**Shipped:** a read answers from this frame's publications where the publisher
has already posted, and from last frame's where it has not. Every table handed
to a reader during a render is kept, and the reading is repeated at the end of
the pass against the frame's final publications and focus; if it differs, the
run loop is asked for one more frame. So a reader shows a value that changed
this frame one frame late (about 17 ms at the default rate), and a value that
did not change at once. A value that cannot be compared — a closure, a
`Binding` — counts as unchanged while the same view publishes it, so a closure
rebuilt every render cannot keep the loop spinning; a `Binding` reads through
to its source wherever it is read, so it is never stale either.

Two smaller readings, both SwiftUI-silent:

- Of several scene values for one key with none on the focus's path, the
  first published in the tree wins.
- A reader on the page beneath a sheet (the dimmed backdrop) reads the live
  tree's publications; the backdrop's own publishers publish nothing, since
  they are a picture of the page.

**The fuller version** removes the late frame: a publisher-only walk before the
real one, or deferring the readers' subtrees to the end of the walk. The first
is a second walk of every page that uses the API (a measure-shaped walk that
renders nothing, which the memos would mostly serve); the second breaks the
one-pass layout. Neither seems worth it for a one-frame delay that only a
reader ahead of a changing publisher sees. **A/B owed:** a reader records an
unkeyed read, so every memo above it declines to store; on a page whose root
holds a reader that is the whole page. Publishers are replayed by the memo, so
they cost nothing on a served frame.

### B35. What "when no other view has focus" means for a preferred default

*`View.prefersDefaultFocus(_:in:)`, `View.focusScope(_:)`, `ResetFocusAction`,
`EnvironmentValues.resetFocus`*

SwiftUI's documentation says the preference "sets the initial focus preference
when no other view has focus", is "limited to the focusable ancestor that
matches the provided namespace", and that a reset reevaluates default focus
"when the currently-focused item is within the provided namespace". Its
examples are tvOS ones. Three readings were needed:

- **Who has focus.** TUIkit focuses the first control of a screen or a newly
  presented sheet by itself, mid-render. That choice is not counted as a view
  having the focus, so the preferred control takes it from there; a focus the
  user, an app's `@FocusState` write or a `.defaultFocus` put somewhere is
  left alone. While an unapplied scope or preference is on screen the
  automatic choice waits for the end of the pass, so the first control inside
  a scope does not flicker through the focus; one before the scope can (it has
  registered before the scope was seen).
- **Once.** The initial preference is applied on the frame it first appears,
  then spent until its scope leaves the screen — the rule `.defaultFocus`'s
  `.automatic` priority already follows here.
- **No scope.** A preference whose namespace has no `.focusScope` applies to
  the whole screen, and a reset in that namespace moves the focus from
  anywhere.

**The alternative readings** are each a line to change: count the automatic
choice as holding the focus (then a preference only ever acts on a reset), or
make a scope-less preference inert. Neither has an obvious use. Not probed on
a SwiftUI build: focus needs a key window, which an offscreen hosting view does
not have.

**Decided 2026-10-12: an explicit focus overrides the default focus, and the
automatic choice must not count as held.** The first holds today: a focus the
user, an `@FocusState` write, a pending request or `.defaultFocus` put
somewhere is left alone (`FocusScopeTests`, `initialFocus` and
`initialFocusInsideScope`). The second holds only on the render pass that
makes the choice: each pass clears the mark (`FocusScopeRegistry.beginPass`), so a
scope that appears on a later frame, while the focus is still the automatic
pick, does not take it (`doesNotSteal`). So "who has focus" above is true for
one pass only. **Lane owed, one commit:** keep the mark across frames until a
real focus event (a user's move, a click, an app's write or `.defaultFocus`),
and end it on any input delivered to the automatically focused control, so
focus never moves from under someone typing; a new test for a scope that
appears while the focus is still the automatic pick.

**Shipped 2026-10-13 (BITEMS1):** the mark lasts across frames. It ends when
the focus moves off the chosen control by any path, when anything focuses
that control explicitly (a click on it), and when a key is offered to it —
taken or not, or taken by an `onKeyPress` on its way there — or a press or a
wheel over it is taken (`wheelEndsTheAutomaticChoice`). The first-control
fallback at the end of a pass is the manager's choice too, as is the
neighbour an untouched choice falls back to when it leaves, at a pass's end
or unregistered by the app (`unregisterKeepsTheChoiceAutomatic`); a
`.focusHandoff` target (the app named it) and a page's focus restored when a
sheet closes are not. Tests: `takesTheUntouchedAutomaticFocus` (a scope
three frames on takes it), `doesNotSteal` (Return pressed it first) and
`declinedKeyEndsTheAutomaticChoice` (a key the button ignores).

### B38. Search scopes show while the search is under way, by a terminal's reading of "presented" and "cancelled"

*`View.searchScopes(_:scopes:)`, `View.searchScopes(_:activation:_:)`,
`SearchScopeActivation`*

SwiftUI shows the scope bar "when SwiftUI presents search" (macOS) or "when
someone enters text" (iOS), and hides it "when someone cancels the search".
On macOS the search field lives in a toolbar and is presented by clicking it.
Here it is always on screen at the top of the searchable subtree.

**Shipped:** presented is the field holding the focus, as `isSearching` already
was; cancelled is `dismissSearch` (or `isPresented = false`), or leaving the
field with nothing typed. So under `.onSearchPresentation` and `.automatic`
(macOS's default) the scopes show while the field has the focus or the query
is not empty; under `.onTextEntry`, while the query is not empty. Under both
they stay while the focus is in them, or Tab from the field would hide the
picker it was heading for.

**The alternative** is to show the scopes whenever the field is on screen,
since a terminal's field is never hidden. That reads well for a dedicated
search page but makes `.onTextEntry` meaningless, so it would have to be a
TUIkit-only activation rather than a reading of SwiftUI's.

### B49. `SystemFormatStyle`: where the rules go beyond the measurements

*`SystemFormatStyle.Timer`, `.Stopwatch`, `.DateOffset`, `.DateReference`*

The four styles reproduce every reading measured (about 200, pinned in
`SystemFormatStyleClockTests` and `SystemFormatStyleDateTests`). Between the
measurements, these were chosen:

- **`DateReference`'s absolute form is drawn in the calendar's time zone.**
  SwiftUI's keeps a zone of its own beside the calendar, set from the current
  zone and not reachable through its API; `calendar(_:)` with a calendar in
  another zone therefore moves TUIkit's absolute form and not SwiftUI's. With
  the default calendar the two agree.
- **`now`.** Foundation's anchored relative style says "this minute" (or
  "this hour") where SwiftUI's reference says "now"; TUIkit says "now" when
  the finest allowed unit is a minute or an hour and the offset rounds to
  nothing in it. With seconds allowed Foundation says "now" itself; with days
  the finest, "today" is left alone (unmeasured).
- **`DateOffset` on a clock face** only when exactly minutes and seconds are
  allowed. SwiftUI's documentation says hours, minutes and seconds use it too;
  measured, with two fields, they did not, and three fields were not tried.
- **Boundaries.** `discreteInput(after:)` and `(before:)` return the instant the
  reading changes, at a boundary or one representable `Date` past it. SwiftUI's
  `before` sometimes returns the boundary itself, where the reading has not yet
  changed, which its protocol allows; TUIkit's never does. `DateReference`
  turns between its forms half a second before a period begins (the point of
  reference is rounded to the second), where SwiftUI's turn at a new year was
  measured at the year's first instant.

**Fuller version:** a macOS 26 measurement pass over the same probes, and the
three-field clock face. An hour each.

### B51. A live text read for its string is read once, when it is built

*`Text(_:style:)`, `Text(timerInterval:…)`, the live interpolations,
`Text(_:format:)` over a `TimeDataSource`*

A live `Text` draws its words at each frame. But some of TUIkit's API takes a
`Text` only for its string — `navigationTitle(Text)`, `help(Text)`,
`dismissalConfirmationDialog`'s title — and a `LocalizedStringKey` handed to a
control other than `Text` (a button's title) is resolved to a string where the
control is built. Those read a live text or a live interpolation once, as it
read when built; it moves only when the view around it is rebuilt. SwiftUI
keeps them live, since its titles are `Text` all the way down.

To give those consumers a reading at all, a live text formats once when it is
built, as well as at each frame it is drawn. Only live texts pay it (about
6 µs for a unit spelling, 30 µs for `.time`/`.date`, which use a
`DateFormatter`).

**Fuller version:** the string-taking consumers keep the `Text` and draw it,
which each of them could (a title is drawn by a `Text` in the end); a title
that changes would then also have to re-measure the bar it sits in. About two
hours a consumer, and none has asked. **A/B owed:** the build-time reading
could be deferred to the first consumer that asks, saving it for every live
text drawn only as a view — worth measuring on a list of a few hundred
`Text(date, style: .relative)` rows before deciding.

### B52. A custom transition's body is drawn at each frame's point between its phases

*`Transition` (`body(content:phase:)`, `Content`, `properties`,
`animation(_:)`, `combined(with:)`, `apply(content:phase:)`),
`TransitionPhase`, `TransitionProperties`, `PlaceholderContentView`,
`AnyTransition.init(_:)`, `AnyTransition.modifier(active:identity:)`,
`View.transition(_:)` for a `Transition`*

**How SwiftUI does it.** A transition's body is evaluated at three discrete
phases. On insertion it is shown at `.willAppear` and then "immediately moved
to the `identity` phase" under the change's animation; on removal it goes from
`.identity` to `.didDisappear`. Nothing about the body is continuous: what
moves are the animatable modifiers inside it, each interpolated between the
value it had at one phase and the value it has at the other. "If no animatable
change is applied, then the transition will be a no-op."

**How TUIkit had it.** A transition was a value — `AnyTransition`'s closed set
of effects — applied to the view's rendered buffer as a function of one number,
how present the view is (0 absent, 1 there, above 1 while a spring overshoots).
An insertion reads that number from the animation store as the view arrives; a
removal leaves a closure behind every frame, "here is what I look like part-way
gone", which whatever holds its slot plays out over the picture the view last
drew (`DepartureStore`). All of that stays exactly as it was.

**What shipped: a custom body is drawn by scrubbing it.** For a presence `p`
on any frame of an arrival or a departure, the body is rendered twice:

1. **Record**, at the end phase (`.willAppear` arriving, `.didDisappear`
   leaving), with the content standing in as an empty box of its own size.
   Every animatable value the body produces — an `Animatable` view or
   modifier's data, and the colours `.foregroundStyle`, `.background` and
   `.border` resolve — is noted, keyed as the animation store keys it (place
   in the tree, owning type, slot), and nothing is drawn.
2. **Draw**, at `.identity`, with the real content, and each of those values
   replaced by `end.interpolated(towards: identity, amount: p)`.

That is the same arithmetic the animation store performs when a value animates
(`from.interpolated(towards: to, amount: curve(t))`), with `p` already being
`curve(t)`, so the picture is the one SwiftUI's per-modifier interpolation
gives. Both passes go through one hook at the top of the store's lookup, so a
scrubbed value never reaches, or disturbs, the store's own records. A value
built FROM one drawn part-way — inside the body of an animatable modifier,
evaluated at its interpolated data — is drawn as built, not interpolated a
second time; what a placeholder draws (the view a modifier is applied to) is
not built from the modifier, and is scrubbed on its own account.

Everything else is reused rather than rebuilt: the arrival phase and its
explicit animation, the departure slot and its timing, a removal starting
mid-insertion from where the arrival had got to, a spring's overshoot (`p`
above 1 extrapolates, so an `.offset` in a body bounces past its slot and an
`.opacity` stops at opaque, both as the built-ins do), and the rule that only
an animated change transitions.

**The content is live while the view is present.** The placeholder draws the
real view, at the transition's own identity (so its `@State` is where it would
be without the transition), under the environment the body gives it — a body's
`.foregroundStyle` or `.disabled` reaches it, as in SwiftUI. While the body is
being recorded the placeholder draws nothing, so the content's side effects
(focus, hit regions, `onAppear`) happen once a frame, as they always have.
At rest the body is drawn at `.identity` every frame: SwiftUI applies it for as
long as the view is visible, and a body is allowed to leave something there.

**Where TUIkit cannot follow SwiftUI, and why.**

- **A departing view's content is a picture.** A removed view does not exist
  any more — that is what `DepartureStore` is for — so while it leaves, the
  body is drawn around the cells the content drew on its last frame. The
  body's own modifiers still move: its opacity, offset, colours. What the body
  would have changed *inside* the content (an environment value that differs
  between `.identity` and `.didDisappear`) does not change any more once the
  view has gone.
- **The slot is the size of the `.identity` body.** A body that changes the
  view's size between phases (`.frame(height: phase.isIdentity ? nil : 0)`,
  a collapse) is drawn inside the size it has at rest, rather than re-laying
  out its siblings on every frame. TUIkit's transitions have never moved
  their neighbours (see `AnyTransition`); this is the same rule applied to a
  custom body.
- **A body that changes its structure between phases does not animate the
  difference.** A value is interpolated only where both renders produced it
  at the same place; a modifier present at one phase and not the other is
  drawn as the `.identity` render has it. SwiftUI asks for the same
  ("Transitions should not use any identity-affecting changes like `.id`,
  `if`, and `switch`").

**The built-in transition types** (`OpacityTransition`, `MoveTransition`,
`OffsetTransition`, `ScaleTransition`, `SlideTransition`, `PushTransition`,
`IdentityTransition`, `AsymmetricTransition`) have real bodies, built from one
animatable modifier that applies TUIkit's own effect at the body's presence —
so `OpacityTransition().apply(content: v, phase: phase)` inside an app's own
transition fades exactly as `.opacity` does. Erased to `AnyTransition` (which
is what `View.transition(_:)` does with any `Transition`), they keep the
buffer fast path; only a transition with a body of the app's own takes the
two-pass route.

**What it costs.** Two body renders a frame while a custom transition plays
(the first draws no content); one at rest, which is what any `ViewModifier`
body costs. The built-ins cost what they did.

**The fuller version.** Animate the layout too: measure the body at the
interpolated values each frame, so a collapsing transition closes its gap as
it goes. That is a re-layout of the transition's container per frame — the
cost the buffer-based design exists to avoid — and needs the measure walk to
scrub as well, which the memoised measure path makes delicate. About two days.
I would wait for a port that needs it.

### B54. A scale transition uncovers from its anchor, and a scale above 1 draws the view whole

*`ScaleTransition` (`init(_:anchor:)`, `scale`, `anchor`),
`Transition.scale`, `Transition.scale(_:anchor:)`,
`AnyTransition.scale(scale:anchor:)`*

TUIkit's `.scale` already reveals the view from its anchor a whole cell at a
time, there being no sub-cell rendering to shrink. The scale factor is now
where that reveal starts: `.scale(0.5)` shows half the view at once and
uncovers the rest. `.scale` itself is `ScaleTransition(1e-5)`, SwiftUI's own
value (measured) — nothing, in whole cells.

A factor above 1 asks for the view to start larger than its slot. A cell grid
cannot draw that: the reveal is clamped at the whole view, so the transition
draws the view whole from the first frame. `opacity` above 1 is clamped the
same way in SwiftUI itself.

TUIkit's own spelling, `AnyTransition.scale(anchor:)`, was not SwiftUI's and is
gone; `scale(scale: 0, anchor:)` is the same transition.

**The fuller version** would draw an oversized start by cropping the view to
its middle and widening the crop as it settles — a zoom-out rather than a
grow. Nothing in TUIkit crops from the middle today; half a day, and I would
wait for someone to ask.

### B55. `tracksVelocity` is recorded, and no velocity is carried; `isContinuous` is set by TUIkit's own continuous controls

*`Transaction.tracksVelocity`, `Transaction.isContinuous`*

**`tracksVelocity`.** SwiftUI accumulates the velocity of values changed under
such a transaction, so a later animation can start moving at that speed.
TUIkit's animations are closed-form functions of elapsed time that start at
rest — a spring retargeted mid-flight already restarts from where its picture
is, without its speed — so there is nothing to track, and the flag is a value
the transaction carries for whoever reads it. This is the one place the
"retargets at rest" deviation of every TUIkit spring shows up as a property;
the Wave 17 review (W6) asked for it to be documented in one place rather than
used to refuse spellings, and B58 (the spring animations) points here
too.

**`isContinuous`.** SwiftUI sets it when "a continuous action created the
transaction" — dragging a slider, holding a stepper. TUIkit now sets it on the
writes its own controls make that way: a press and drag on a `Slider`'s track,
and the repeats of a held arrow (`Slider`, `Stepper`) or a repeating
`Button` (the first action of the press is a click, and is not continuous).
A key the terminal repeats arrives as separate presses with nothing to say
they are one hold, so a held arrow KEY is not continuous. Setting the flag
makes the write an explicit transaction, which — like any `withTransaction` —
takes over from an animated change made earlier in the same frame.

**The fuller version** of `tracksVelocity` is O3's: velocity-preserving
retargeting needs integrated animations, the `CustomAnimation` question.

### B56. When a completion fires: the pass that shows the change decides, and a spring logically completes at its pace

*`AnimationCompletionCriteria` (`.logicallyComplete`, `.removed`),
`Transaction.addAnimationCompletion(criteria:_:)`,
`withAnimation(_:completionCriteria:_:completion:)`,
`Animation.logicallyComplete(after:)`*

SwiftUI fires a completion "when the animations created with this
transaction are all complete", exactly once, and "immediately after `body`"
if the changes created none.

**Shipped.** A completion rides the transaction onto the state change made
under it; the frame that renders the change starts its animations, and the
stores report each one they start (an animated value, an arriving transition,
a departing one) for that pass only. Then:

- **Nothing changed** in `body` (no state change claimed the completion): it
  runs as `withTransaction` returns.
- **Something changed but nothing animated:** it runs when that frame's pass
  ends.
- **`.logicallyComplete`:** when the latest logical completion among the
  started animations has passed. A curve completes at its end. A spring
  completes at the end of its pace — the `duration:` it was made with — and
  settles after that; SwiftUI calls that "the long tail". `.logicallyComplete
  (after:)` brings the point forward (it scales with `speed`, as the delay
  does), never past the end. A later change does not move it.
- **`.removed`:** when the latest end has passed and none of the values the
  pass started is still animating, so a retarget makes it wait for the new
  animation too.
- **A value whose view has left** is removed, so its completion fires
  whatever the deadlines say; a `repeatForever` animation still on screen
  never completes, as in SwiftUI.

Two transactions in one frame render under the last one (the rule TUIkit
already had), but each keeps its completion: the pending completions are
collected separately from the pending transaction.

**Readings, not measurements.** That a spring logically completes at its
perceptual duration is from SwiftUI's description of a spring's `duration`
("the perceptual duration, which defines the pace of the spring"); a
completion's timing could not be measured with an offscreen hosting view.
"The animations created with this transaction" is read as every animation the
change's frame starts — an unrelated `.animation(_:value:)` whose value moved
in the same frame is included.

**Not honoured:** a completion added by a view's `transaction(_:)` modifier
while rendering. No change was made under that transaction, so nothing claims
the completion and nothing runs it. SwiftUI documents no such use either.

### B57. `UnitCurve` is SwiftUI's arithmetic, except where its answers contradict its documentation

*`UnitCurve` (`value(at:)`, `velocity(at:)`, `inverse`, `bezier(startControlPoint:endControlPoint:)`,
the eight named curves), `Animation.timingCurve(_:duration:)`*

The Bézier curves share the solver an `Animation`'s timing curve uses (the
Wave 17 review asked for one formula, not two), and match SwiftUI's values and
velocities to the sixth place (measured, [`p3.swift`](<../../../Tools/SwiftUIProbes/Animation curves, springs and keyframes/p3.swift>)). Two readings
differ from what SwiftUI answers, in the documentation's favour:

- **Out-of-range input is clamped**, as `value(at:)` and `velocity(at:)`
  document. SwiftUI clamps its Bézier curves, but not `.linear` (1.5 gives
  1.5) or the circular ones (1.5 gives NaN, -0.5 a mirrored value).
- **`circularEaseInOut.inverse` is the curve with x and y swapped**, as
  `inverse` documents: level in the middle, steep at the ends. SwiftUI
  answers `circularEaseInOut` itself, whose values are not an inverse at all.

Where a curve is vertical — `circularEaseIn` at its end, the circular in-out
at its middle — the velocity is infinite, as in SwiftUI. Where a Bézier's
control point sits on its end point the tangent vanishes, and SwiftUI answers
1 (`easeOut` at 0) or 0 (`easeIn` at 1, the quotient of two rounding errors)
rather than the limit the curve approaches (1.72 for both). TUIkit answers
the same, by the same arithmetic: a keyframe track carries a linear
keyframe's end velocity into the cubic keyframe after it, and the two
frameworks' tracks agree only if these do.

A circular curve is a new case of the animation curve, so
`Animation.timingCurve(.circularEaseIn, duration:)` moves along the circle;
a Bézier or `.linear` builds the animation `timingCurve(_:_:_:_:duration:)` and
`linear(duration:)` already build, and compares equal to it.

### B58. `Spring` is SwiftUI's numbers, two quirks kept and one not; a spring animation keeps no velocity across a retarget

*`Spring` (its four initialisers, `duration`, `bounce`, `response`,
`dampingRatio`, `mass`, `stiffness`, `damping`, `settlingDuration`, `value`,
`velocity`, `force`, `update`, `settlingDuration(…)`, `.smooth`/`.snappy`/
`.bouncy` and their tunable forms), `Animation.spring(_:blendDuration:)`,
`spring(duration:bounce:blendDuration:)`, `spring(response:dampingFraction:blendDuration:)`,
`interactiveSpring` (all three), `interpolatingSpring` (all four)*

The Wave 17 review (W6) found the refusal of all of these to be a judgement,
not a limit: TUIkit already drew springs in closed form. `Spring` is that
closed form made public — one implementation (`SpringMotion`) behind both the
type's arithmetic and the curve a spring animation is drawn with — and every
number was checked against SwiftUI's `Spring` on a probe
([`p4.swift`](<../../../Tools/SwiftUIProbes/Animation curves, springs and keyframes/p4.swift>), [`p5.swift`](<../../../Tools/SwiftUIProbes/Animation curves, springs and keyframes/p5.swift>)): values, velocities with and without a
starting velocity in all three damping regimes, force, `update`, the
settling durations, the conversions, the presets.

**Quirks kept, because ported arithmetic reads them:**

- An overdamped spring's `stiffness` reads `(2ζ² − 1)` times the stiffness it
  moves with, and `force` uses it.
- A critically or overdamped spring's settling duration is found in steps of
  a tenth of a second (0.8 s for the default spring); an underdamped one's is
  the bound `ln((|y₀| + |v₀ + ζω·y₀|)/ε)/(ζω)`.
- `init(settlingDuration:dampingRatio:epsilon:)` solves a different relation
  from the one `settlingDuration` answers by, so the spring it makes reports
  a longer settling duration than it was asked for (1 s asks, 1.25 s
  reported, at ζ = 0.8), and a ratio above 1 is treated as 1.

**A quirk not kept:** SwiftUI's overdamped `velocity(…)` reads exactly one
more than the derivative of its own `value(…)` (1 at rest at t = 0). TUIkit
answers the derivative.

**Bounce at or below −1** is NaN in SwiftUI; here it stops at −0.999, a spring
too sluggish to visibly arrive, rather than a NaN on its way to a cell.

**Retargeting.** SwiftUI's `spring` hands its velocity to the next spring on
the same value, blending the durations over `blendDuration`; its
`interpolatingSpring` adds overlapping animations so velocity is preserved.
TUIkit's animations are functions of elapsed time from a start at rest: a
change that retargets a running spring starts the new one from where the
picture is, without the speed it had. So `blendDuration` has nothing to blend,
and `interpolatingSpring`'s `initialVelocity` is honoured for the change it
is given to — it moves the start of the curve and lengthens the settling the
loop waits for — but not inherited by the next. This is the deviation every
TUIkit spring already had (B55 records `tracksVelocity` against it); the
`interactiveSpring` presets are, accordingly, the quick springs their numbers
describe.

**The fuller version** is velocity-preserving retargeting: store the
velocity at retarget and start the next closed form with it
(`SpringMotion` already takes one). For springs alone that is a day — the
store records where the picture is; it would also record how fast — but a
curve retargeting into a spring, or a spring into a curve, has no velocity
model, which is O3's question.

### B60. Keyframe timelines follow SwiftUI's curves, measured; the animator views stay with O2

*`KeyframeTimeline` (`init(initialValue:content:)`, `duration`, `value(time:)`,
`value(progress:)`), `Keyframes`, `KeyframeTrack`, `KeyframeTrackContent`,
`KeyframesBuilder`, `KeyframeTrackContentBuilder` (and `Conditional`),
`LinearKeyframe`, `CubicKeyframe`, `SpringKeyframe`, `MoveKeyframe`,
`Never: Keyframes`*

The Wave 17 review (P13) found the timeline side of the keyframe family
wrongly refused: these are pure functions of time with no rendering at all,
and `KeyframeTimeline` cannot be written without them. `KeyframeAnimator` and
`keyframeAnimator` — the views that play a timeline — stay with O2.

**Shipped,** with every curve rule taken from SwiftUI's own timelines
([`p6.swift`](<../../../Tools/SwiftUIProbes/Animation curves, springs and keyframes/p6.swift>), [`p7.swift`](<../../../Tools/SwiftUIProbes/Animation curves, springs and keyframes/p7.swift>)) and pinned by tests to six places:
adjacent cubic keyframes form a Catmull–Rom spline at rest at both ends; a
cubic keyframe starts at the velocity the keyframe of another kind before it
ended at, and ends at the next one's starting velocity; a named velocity
wins on its own side of a junction only; a spring keyframe without a
duration runs until it is within 0.0001 of its target (an absolute
threshold, so a larger change takes longer), and one cut short hands on the
value and velocity it reached; a move leaves the value at rest; tracks run
together from the initial value and the last to write a property wins.

**Where it differs.**

- **Main-actor isolated.** The protocols, builders and the timeline's
  initialiser and samplers are, because TUIkit's `Animatable` is (its values
  are read and written through `animatableData`). SwiftUI's are
  nonisolated. Code that builds a timeline in a view, a body or a `.task`
  compiles unchanged; one built off the main actor does not.
- **A time before the start is the start.** SwiftUI clamps its linear and
  cubic segments there, but evaluates a spring backwards (−58.5 at −0.5 s for
  a bouncy spring to 1).
- **A zero-length linear or cubic keyframe arrives at once**, where SwiftUI
  divides by its zero length and answers NaN.

### B61. A content transition dissolves everything the modifier wraps

*`ContentTransition` (`.identity`, `.opacity`, `.interpolate`,
`.numericText(countsDown:)`, `.numericText(value:)`), `View.contentTransition(_:)`,
`EnvironmentValues.contentTransition`,
`EnvironmentValues.contentTransitionAddsDrawingGroup`*

The Wave 17 review (W4) found the refusal ("a cell holds one glyph with no
alpha") overtaken by opacity compositing. **Shipped:** where the modifier is
written, a change to what its content draws, made under an animation, draws
the new content over the old at the animation's progress through the opacity
compositor: colours blend and each cell's glyph changes half way, so a cell
whose character is the same keeps it and moves only its colours. That is
`.interpolate` here (SwiftUI's "matching glyph pairs" interpolate, and the
rest use its documented opacity fallback); `.opacity` and both
`.numericText` forms draw the same dissolve (SwiftUI's rolling digits are
promised only "in certain environments"); `.identity` draws the change at
once. A change in mid-dissolve dissolves from what is on screen. The dissolve
counts as an animation for completions.

**Where it differs.** SwiftUI's leaf views read the environment value and
each animates its own content. Here the modifier dissolves its whole
subtree's drawing — identical cells dissolve into themselves, so only what
changed is seen to move, but an inner `.contentTransition(.identity)` does
not exempt its part, and the view takes its new size at once (a shrinking
drawing loses its edges immediately). `contentTransitionAddsDrawingGroup` is
a rendering hint with no visible contract (a drawing group changes how
SwiftUI composites, not what it shows) and is kept for whoever reads it. The
symbol-effect content transitions shipped with A35 on 2026-10-05 (on macOS:
a fade of the whole view).

**The fuller version** is A40's second option: the dissolve inside `Text`
and `Image`, reading the environment, which also gives the leaf-level
semantics above.

### B62. A vertical `TextField` is a text field that wraps, not an editor with a field's chrome

*`TextField.init(_:text:axis:)`, `TextField.init(_:text:prompt:axis:)`,
`TextField.init(text:prompt:axis:label:)`*

**What shipped.** On `.vertical` the field soft-wraps its text over rows and
grows a row at a time as it is typed. Measured on macOS 15.8: with no line limit
it grows without end; `lineLimit(2)` stops it at two rows;
`lineLimit(3, reservesSpace: true)` keeps three and `2...4` two; an empty field
grows to show its whole prompt; a field on one line ignores the limit. At its
cap the field scrolls to keep the caret's row in view; unfocused it shows its
first rows. The wrap is the macOS text system's: after a run of spaces, which
hangs at the end of the row it breaks (`"aaa bbb ccc "` then `"ddd"`), between
the characters of a word too long for a row, and at every newline. The last
cell of a row is kept for the caret, so text wraps one cell short of the
field's edge.

**Why on the field's machinery.** A vertical `TextField` in SwiftUI is the same
AppKit field editor as one on a single line (measured: the first responder is
`_SystemTextFieldFieldEditor` on either axis). Return and Shift-Return submit
and insert nothing; the Emacs chords are the field's. So it is built on
`TextFieldHandler`, whose caret is a character offset — the natural coordinate
of a wrapped layout — and keeps every key a text field has: Ctrl-V pastes,
Ctrl-U erases, Shift-arrows select, a submit-less field lets Return through to
a dialog's default button, suggestions and content types work. The editor's
handler would have brought the editor's map instead: Return inserting a newline,
Ctrl-V paging, no keyboard selection. What a field on one line had no use for
is added, each measured on macOS 15.8:

| Key | In a vertical field |
|-----|---------------------|
| Up / Down, Ctrl-P / Ctrl-N | a row, keeping the column through short rows; off the first row Up goes to the start, off the last Down to the end |
| Shift-Up / Shift-Down | extend the selection a row |
| Ctrl-A / Ctrl-E | the start / end of the caret's line (Cocoa's paragraph commands); they keep the key from an app's shortcut, since Home and End go to the ends of the text |
| Ctrl-K | to the end of the line; at its end, the newline |

**Where TUIkit chose, unmeasured.** A combo box's `▾` sits on the first row,
and Down opens the suggestions only from the last row (above it Down moves a
row). Page Up and Page Down only scroll a SwiftUI vertical field, leaving the
caret where it was (measured); TUIkit's field scrolls only to follow its caret,
so it has nothing for them to page, and leaves them to the view around it.

**The fuller version:**

- **The caret's lean at a wrap, per caret.** Where a row wrapped, one offset is
  both the end of a row and the start of the next. TUIkit draws the caret by
  `\.textSelectionAffinity`, and `.automatic` at the start of the later row.
  macOS keeps a lean per caret (measured): an arrow key leaves it downstream,
  as TUIkit draws it, but typing, a click and Ctrl-E leave it upstream, at the
  end of the earlier row. The two draw the same offset in different places, and
  the next character typed goes to the same place either way. About half a day
  to track the lean through each kind of motion, after measuring the motions
  not yet measured (deletion, Up and Down, Home and End).
- **A scroll indicator** while the text is taller than the field, as the
  editor draws one. A field on one line shows no indicator for its sideways
  scroll either. Half a day, mostly finding a column for it: the margin cell is
  the caret's.
- **The wheel.** A pointer over a scrolled field could scroll it, which the
  editor does not do either. Half a day for both.
- **An Example page section** with a vertical field, which wants its strings
  in the Example's seven languages.

### B63. A newline from the keyboard: Option-Return where the terminal sends it, Ctrl-O everywhere

*Part of `TextField.init(_:text:axis:)` and the other `axis:` forms*

Measured on macOS 15.8, in a vertical field:

| Key | SwiftUI |
|-----|---------|
| Return, Shift-Return, keypad Enter | submit (`onSubmit`), insert nothing, select all |
| Option-Return | inserts a newline, caret after it (`insertNewlineIgnoringFieldEditor:`) |
| Ctrl-Return | inserts U+2028 LINE SEPARATOR (`insertLineBreak:`) |
| Ctrl-O | inserts a newline, caret before it (Cocoa's open line) |
| Ctrl-J, Ctrl-M | nothing |

What a terminal delivers decides what TUIkit can honour:

- **Option-Return** arrives as ESC CR where the terminal sends Option as Meta
  (Terminal.app with "Use Option as Meta Key", iTerm2 with Option as Esc+, and
  the terminals whose own setting does the same). TUIkit inserts a newline
  for it. Without Meta it is a plain CR, indistinguishable from Return, and
  submits.
- **Ctrl-O** is byte 0x0F from every terminal. TUIkit opens a line, as macOS
  does. This is the route that is always there: Ctrl-O, then Ctrl-F (or Right)
  past the newline.
- **A paste** keeps its line breaks, each as one newline whatever the
  clipboard used.
- **Ctrl-Return and Shift-Return** arrive as a plain CR from every terminal
  that does not speak an extended keyboard protocol, so they submit. Ctrl-Return
  would be U+2028 in SwiftUI.

**The fuller version:**

1. **Ctrl-J as newline-and-advance on every terminal.** LF (0x0A) is Ctrl-J,
   and only Ctrl-J sends it in raw mode, where the Return key sends CR. Today
   the input parser reads LF and CR alike as `.enter`. Reading LF as its own
   key would make Ctrl-J deliverable everywhere — it is the newline key of many
   terminal chat and prompt tools. About half a day with the tests. The risk
   is any path that delivers LF for Return (none known with `ICRNL` off, but a
   multiplexer or a serial line would need checking), where every Return would
   insert a newline instead of submitting. It also bears on the kitty keyboard
   protocol (A4, shipped 2026-10-05), which frees Ctrl-J among other chords.
2. **Shift-Return and Ctrl-Return** wherever the kitty keyboard protocol is
   negotiated, where they arrive as themselves. Possible now that the
   protocol has shipped (A4, 2026-10-05).

### B64. `lineLimit`'s range forms ship, reversing their omission

*`View.lineLimit(_:)` with `ClosedRange<Int>`, `PartialRangeFrom<Int>`,
`PartialRangeThrough<Int>`*

The compatibility doc omitted the three range forms because no terminal text
control grew to be sized by them. The vertical field does, and SwiftUI documents
them for a `Text` as well: the lower bound is a floor and the upper a cap, as
`reservesSpace:` and the limit are. `Text("one").lineLimit(2...4)` keeps two
rows and long prose stops at four; `lineLimit(...2)` is `lineLimit(2)`. Listed
because it reverses a recorded omission. (The parity tool counts a function's
overloads under one name, so these were never in its gap list.)

They are stored without widening every `Text`: a range that reserves nothing,
or exactly its cap, is the existing `.lines` case, and the rest a new
`LineLimit.range` whose bounds are 32-bit, so `LineLimit` stays nine bytes.

### B65. A text field's selection is one range

*`TextField.init(_:text:selection:prompt:axis:)`,
`TextField.init(text:selection:prompt:axis:label:)`*

Wired as `TextEditor(text:selection:)` is: the field writes its caret and
selection to the binding after every key and pointer event, and a selection the
app writes moves them at the next frame. A field selects one range, so an app's
multiple selection selects its first range, as the editor's does.

**The fuller version:** draw and edit several ranges. A terminal has no gesture
that makes a second range (macOS's is Command-drag), so only an app could ask
for one. Painting every range is cheap; what typing over several ranges does
needs measuring on an `NSTextView` first.

### B66. A pinned header covers the rows under it; SwiftUI's lets them show through

*`LazyVStack.init(alignment:spacing:pinnedViews:content:)`, `PinnedScrollableViews`*

SwiftUI's pinned header has no background, so a row scrolling under it shows
through every point the header leaves empty (measured: a 50-point header over
300-point rows leaves the rows visible beside it). A cell holds one glyph,
and a row's text showing beside a short header reads as one garbled line:
"Header 0ow 3 text".

So a pinned header's cells replace the rows' glyphs across the section's
width (the copy is padded to it), along with what rides on those cells — runs,
fades and hit regions, so a click there never reaches a row no one can see.
What it does not replace is a cell's background: a blank cell of the header
keeps the field under it, so a highlighted row stays highlighted beside the
header's text, which is SwiftUI's transparency for everything a terminal can
show twice.

**The alternative** is SwiftUI's literal reading: the header's trailing blanks
trimmed (`FrameBuffer.trimmingTrailingBlankCells()`, one call), so a row's
text continues past the header's. Free to build, and I recommend against it.

### B67. Under the "N more above" line, a pinned header sits below it

*`LazyVStack.init(alignment:spacing:pinnedViews:content:)`*

With `.scrollIndicatorStyle(.text)` the scroll view writes "▲ N more above"
over the viewport's first line whenever it is scrolled. Pinned to that line, a
one-line header — the usual terminal header — would never be seen. So it
goes below it, as a revealed control does (the same `edgeInset` reasoning),
and a pinned footer goes above "▼ N more below". Under the default scrollbar,
and under `.visible`, which reserves the pair outside the viewport, nothing
is charged.

SwiftUI has no such line, so there is nothing to measure. The alternative is
the header under the line, and only its second line onward showing.

### B68. Which sections are the stack's own: the next stack down, and one sibling step

*`LazyVStack.init(alignment:spacing:pinnedViews:content:)`*

SwiftUI pins the sections in the stack's own list of subviews, however
wrapped, and not one inside a row. TUIkit's stack sees each section as one
child — a section in a stack draws as one unit (B16; shipped 2026-10-05, so
the compatibility doc now says where a section is taken apart) — so the question is
asked from the section's side, by two tests:

- the stack hands its rows the scope in the environment entry every stack
  core replaces for its own children (`ContainerRelationship`, beside the
  axis `Divider` reads), so a section inside a row's `VStack`, `HStack`,
  `Grid` or custom `Layout` never sees it;
- and the section must be one sibling step below the stack
  (`ViewIdentity.siblingSteps(belowDepth:)`): a `ForEach` row or a child of
  the content, through any number of bodies, modifiers and `if`s.

What the two miss: a section that is the only child of a container that
publishes nothing to its children — a row that is `ZStack { Section { … } }`
— is taken for the stack's own and pins (seen in a test). A `ZStack` of one
child is not a shape anything needs.

**The fuller version** is structural: the stack marks each of its children's
contexts as it renders them, and nothing else can. That is a change to every
place the three windowed paths render a row (about a dozen), and to
`ChildView`, whose size is load-bearing (`ChildView.swift`'s note). Half a day,
and an A/B on `megalist` and `fanout`.

### B69. Focus keeps a row clear of a pinned header; a seek does not

*`LazyVStack.init(alignment:spacing:pinnedViews:content:)`, `ScrollViewProxy.scrollTo(_:anchor:)`*

SwiftUI's `scrollTo(_:anchor: .top)` puts the row at the viewport's top edge,
under the header pinned there (measured: the row is drawn, and the header
covers it). A seek here does the same, unchanged: it is SwiftUI's API, and a
program that wants the row clear can say `.center`.

The reveal that follows focus is TUIkit's own, and it does allow for pinned
chrome: a focused row is kept clear of the lines a pinned header or footer
covers, as it is kept clear of the "N more" lines. Without that, stepping up
through rows with Shift-Tab put each one under the header as it arrived —
focused, and not seen — which for a keyboard user is a hole in the screen. A
control inside a pinned header is found where the header is drawn, so a key
it takes leaves the view where it is.

What macOS's own focus ring does under a pinned header was not measurable
offscreen. If it lets a focused row sit under the header, this is a deviation
toward the terminal's need; I would keep it either way.

### B70. A sectioned `LazyVGrid` is a stack of sections, each around a grid of its views

*`LazyVGrid.init(columns:alignment:spacing:pinnedViews:content:)`, `Section`*

A section in a `LazyVGrid` took a single cell: its header, its views stacked
under it and its footer, all in the first column. SwiftUI lays it out across
the grid (measured): the header starts a row and spans the columns, placed
across them where the grid's `alignment` places a view in a cell; the views
flow from the start of the row below; the footer spans after them; views
outside any section flow between the sections. That is what ships, and it is
how `pinnedViews:` could be offered at all.

It is built from parts that exist: the section APIs take the grid's content
apart (`SectionCollection`, which also makes the implicit sections), and
each section is drawn as a `Section` around a grid of its own views, in a
stack that pins as `LazyVStack(pinnedViews:)` does. A grid with no section
among its views is drawn as it always was. Three consequences:

- A sectioned grid fills the width it is offered — the header has to be
  placed across it — where a grid of only `.fixed` columns used to hug them.
- `spacing` falls between rows and between sections, but not between a
  header and its section's first row, nor before the footer, where SwiftUI
  puts it as well (measured). It is the deviation a `LazyVStack`'s sections
  have already, since a section draws as one unit (B16, shipped 2026-10-05;
  the compatibility doc says where it is now taken apart).
- The header keeps the dimmed, bold styling a section's header has in every
  container that is not a `List`, where SwiftUI's is plain.

`spacing:` is `Int? = nil` now, SwiftUI's spelling, where it was `Int = 0`;
`nil` is still no blank rows.

**The fuller version** places a header and a footer as spanning cells of the
grid's own layout, with the spacing exactly SwiftUI's, and pins them from
there. That needs the layout to emit the pinned copy, knowing the section's
extent only as it places its views — a hook into `_LayoutCore` that no other
layout needs. Half a day; worth it only if the header spacing matters to
someone.

### B71. The cost of pinning, and the measurement owed

*`LazyVStack.init(alignment:spacing:pinnedViews:content:)`*

Two things are paid by stacks that do not pin:

- The stack cores' environment entry for their children is now a struct (the
  axis, and an optional scope) rather than an optional axis: still one
  dictionary write per stack render, and still inside an existential's inline
  buffer, which a test pins. No allocation was added.
- A lazy stack notes its scope (`nil` when it does not pin) once a pass in the
  render cache's environment record, so that turning `pinnedViews:` on or off
  drops the section rows a memo kept — without it a memoized section came back
  without its pinned copy (a test fails so). One dictionary probe per lazy
  stack per pass.

And by a scroll view: one scan of its content's floating layers for a pinned
one per frame, and one more on a frame whose focus moved — usually a scan of
nothing. Every `Section` reads the scope once per render. A pinned section
pays a copy of its header per render. A `LazyVGrid` resolves its views once
more per measure and render, to ask whether a section is among them — the
grid's layout resolves them again — which is the one cost a grid with no
sections pays.

None of this was measured: the machine is shared. The A/B owed is `deep`,
`kitchensink` and `megalist` on a quiet machine, against the parent commit
(no Stress scenario has a lazy grid).

### B72. Badge prominence: two inks, read from the list's environment

*`BadgeProminence` (all members), `EnvironmentValues.badgeProminence`,
`View.badgeProminence(_:)`*

Measured on macOS 15.8, in a `List` of the default style and of the sidebar
style alike: a `.standard` badge is bold grey text in a light grey capsule; a
`.decreased` one is lighter grey text with no capsule; an `.increased` one is
drawn exactly as a `.standard` one (the same pixels).

TUIkit's list badge has always been plain text in the palette's tertiary
foreground, which is closer to macOS's `.decreased` than to its `.standard`.

**Shipped:** `.standard` keeps that look, `.decreased` draws in the quaternary
foreground (the dimmest text a palette has), and `.increased` draws as
`.standard`, as measured. The list reads the prominence from its own
environment, so `.badgeProminence(_:)` works on the list or anything around it.
Written inside a row — around or within the row's `.badge(_:)` — it does not
reach that badge: the list draws a row's badge itself, from the row's view
value, in the list's environment.

**The fuller version** has two parts.

- **A capsule for `.standard`.** Draw the badge on a tinted field one cell
  wider on each side (` 12 `), the terminal's capsule, and keep today's plain
  text for `.decreased`. This changes every badged list's look, and every
  golden or render test that reads a badged row needs re-baselining. Half a
  day, most of it the tests and choosing the field colour per palette (it has
  to read on the cursor row's breath too).
- **A row's own prominence.** Read a `.badgeProminence(_:)` written inside the
  row by peeling the environment modifier off the row value the way the badge
  is peeled off, or by rendering the row's badge inside the row's own
  environment. A couple of hours; nothing else changes.

### B73. Background prominence: raised on the rows a list builds itself

*`BackgroundProminence` (all members), `EnvironmentValues.backgroundProminence`*

SwiftUI raises the prominence for the content of a focused list's selected
rows, whose fill is the vivid accent, and resolves the system content styles
there to a monochrome that keeps their contrast.

**Shipped:** a `List` and a `Table` raise it for the row under the cursor while
the control has the focus, when that row is also selected (in a table, for its
view cells) — the row whose fill is the accent's
breath (TUIkit has one cursor, so one row; SwiftUI raises every selected row of
a focused list, all of which it fills alike). The content levels `.primary`
through `.quinary` resolve to the palette's own text tiers under a raised
background, whatever foreground style the row inherited: those are the inks the
row fills were chosen to carry. The list clears the raised row's cached renders
on the frame the raise moves, since the value reaches the row through its
environment and no memo below the row would notice it.

Raised: every row the list builds lazily — the rows of a `ForEach` and an
`OutlineGroup`, which is every data-driven list. **Not raised:** a hand-written
row beside them (`List { Text("All"); ForEach(items) { … } }`), which the
list's child walk hands over already drawn, before anyone knows where the
cursor will be.

**The fuller version:**

- **Hand-written rows.** Draw them lazily too — keep the child's render
  closure in the row's content box, as a looped row's is — and the raise
  reaches them unchanged. Half a day, most of it the child walk's badge and
  tag reads, which today come off the drawn row.
- **`.background(.selection)`.** SwiftUI says its selection style raises the
  content above it too. A `background(_:)` whose style is `.selection` would
  set the value for its content. An hour.

### B74. `\.sidebarRowSize` is read-only (always `.medium`)

*`SidebarRowSize` (all members), `EnvironmentValues.sidebarRowSize`*

On macOS the value follows the "Sidebar icon size" setting, and a write
forces a sidebar's rows — their height and their `Label` icons — to that
size. Off macOS SwiftUI always reports `.medium` and ignores a write.

A terminal row is one line in the terminal's one font, so TUIkit's is always
`.medium`. **Shipped:** the type with its three cases, and the value
read-only, so a write fails to compile rather than being ignored (the B1/B2
precedent).

**The fuller version** would make the value settable with a meaning a
terminal can give it — `.large` adding a blank line under each sidebar row,
say, and `.small` dropping a `Label`'s icon. Neither is what the setting means
on macOS, so it is not recommended without a use for it.

### B75. A tab's label is drawn as text

*`Tab.init(content:label:)`, `Tab.init(value:content:label:)`,
`Tab.init(role:content:label:)`, `Tab.init(value:role:content:label:)`,
`DefaultTabLabel`*

The strip draws each tab as a chip (`▐ title ▌`, or a folder tab), in the
strip's own ink — the active one breathing while the strip has the focus —
on the strip's own field. A label view of the app's own would bring its own
colours and layout into that.

**Shipped:** the default label is the title, after the SF Symbol's glyph
where the terminal can draw it (`Label(_:systemImage:)`'s rule). A label of
the app's own is rendered as a measure — it registers nothing — under an
identity of its tab's, and its first line is taken without its colours: the
strip draws the label's text, in the strip's ink.

**The fuller version** draws the label view itself into the chip: rendered at
the chip's height with the strip's ink as its foreground style and the chip's
fill as its background, spliced in finished, its own runs and claims carried.
The breath would have to repaint it per frame, which the strip's run does by
redrawing the chip's text today. Half a day, most of it the breath and the
folder style's walls.

### B76. The sidebar style: a list beside the content, chosen with Return

*`SidebarAdaptableTabViewStyle`, `TabViewStyle.sidebarAdaptable`,
`TabBarPlacement` (all members), `EnvironmentValues.tabBarPlacement`,
`EnvironmentValues.isTabBarShowingSections`, `View.tabViewSidebarHeader(content:)`,
`View.tabViewSidebarFooter(content:)`, `View.tabViewSidebarBottomBar(content:)`*

Measured on macOS 15.8: `.sidebarAdaptable` is a split view whose leading
pane is an outline list of the tabs — a `TabSection`'s header above its tabs,
a badge at a row's trailing edge — and the selected tab's content beside it.
Tab content reads `\.tabBarPlacement` as `.sidebar` there and
`\.isTabBarShowingSections` as true; under every other style `.topBar` and
false.

**Shipped:** the sidebar is a `.sidebar`-style `List` hugging its widest row,
a rule, then the content, sized and kept as a strip's content is. Its
sections, badges and disabled rows are the list's own, and a `Label` tab
label's icon takes the list item tint, as a sidebar list's does. The header, footer and bottom bar sit above
and below the list. The two environment values report as measured.

Where it differs:

- **Choosing a tab.** The arrow keys move the list's cursor, and Return,
  Space or a click choose the tab — TUIkit's list convention. A macOS sidebar
  selects as the cursor moves. Following the cursor needs a list mode that
  selects as it moves (a `List` option of TUIkit's own, or the sidebar style
  watching the cursor), about two hours; whether every keystroke should swap
  the content beside it is the question.
- **The header and footer stay put.** SwiftUI's header and footer scroll with
  the tabs; here they are fixed above and below the list, and only the tabs
  scroll. Moving them into the list as a first and last row is an hour, but a
  header that is a row is a row the cursor must step over.
- **Sections are not collapsible.** macOS lets the user fold a sidebar
  section. The list's `Section(isExpanded:)` does it (tried on this branch),
  but a list draws its section headers before it registers its own focus
  stop, so each fold joins the focus ring ahead of the tabs and the first
  fold, not the tab list, takes the initial focus. The same order holds for
  any control in a list's section header — a `Section(isExpanded:)` fold, a
  `.sectionActions` button — in any list. Registering the list's own stop
  before its eager rows are drawn fixes both; about two hours, with the
  focus-order tests that pin the rest. The sidebar folds once that is in.

### B77. Type select moves the cursor, and a prefix's first character gives way to bare-key bindings

*`View.typeSelectEquivalent(_:)` (all four)*

macOS type select, in a focused table or outline: typing a few characters
selects the first row after the selection whose text starts with them, and a
key no row answers to beeps.

**Shipped:** with a list or table focused, a typed character without Control
or Option (and not Space, which selects) joins a prefix, which a second's
pause starts afresh; the next render moves the cursor to the first row whose
text starts with the prefix, ignoring case — after the cursor for a first
character, at it for a longer prefix — and scrolls it into view. A row's text
is its stated `typeSelectEquivalent(_:)`, else a list row's first line of text
(drawn as a measure for a row out of sight, which registers nothing) or a
table row's first column. An empty equivalent takes the row out.

Where it differs:

- **The cursor moves, not the selection.** TUIkit's lists and tables move the
  cursor with the arrow keys and select with Return or Space; type select
  follows them. Selecting as well is a line, if the owner prefers macOS's
  behaviour for this one gesture.
- **A prefix's first character gives way to bare-key bindings.** macOS's
  shortcuts take Command, so its type select never meets one; TUIkit binds
  bare keys — its own `q` (quit), `t` (theme), `a` (appearance) and help key,
  and any bare `.keyboardShortcut` an app registers. The first character of a
  prefix goes to such a binding (the Stress `themes` session presses `t` with
  a list focused, and caught it); once a prefix is under way every character
  continues it, or typing "Atlas" would cycle the theme at the `t`. So a row
  whose name starts with a bound letter is not found by typing that letter
  first. Any other character is taken whether or not a row answers to it, as
  macOS takes it. The alternative — resolve the prefix when the key arrives
  and pass on a key no row answers to — needs every row's text at key time,
  measured outside a render; a day.
- **A looped row spliced among hand-written rows** (a `ForEach` beside a
  static row) is matched by its drawn text; an equivalent it states is not
  seen, behind the memo the list wraps such rows in. Half an hour with the
  badge's own unwrapping (`extractRowBadgeValue`).

### B78. Section actions: always shown, after the header's title

*`View.sectionActions(content:)`, `TabContent.sectionActions(content:)`*

macOS shows a list section's actions at the trailing end of its header while
the pointer is over the section.

**Shipped:** in a `List`, the actions are drawn one cell after the header's
title, all the time, and are ordinary controls there — Tab moves onto each, a
click presses one. A section with no header shows them alone on the header's
line. A custom container reads them as `SectionConfiguration.actions`.
Outside a list (a `Section` in a stack) the view draws as it would without
them, as SwiftUI's does. On a `TabSection`, a `.sidebarAdaptable` tab view's
sidebar draws them the same way; a tab strip, which lists a section's tabs
among the others, shows none, and on a lone `Tab` they do nothing, as
SwiftUI documents.

Where it differs:

- **Always shown.** An action shown only under the pointer is one the
  keyboard cannot reach; showing them while the focus is inside the section
  as well as on hover is a line, if the owner prefers the quieter header.
- **After the title, not flush right.** The list builds a header row before
  it knows the width a hugging list (a sidebar) settles on, so a flush-right
  action there would lose its trailing cells. Flushing right in a list that
  fills its width, and after the title in one that hugs, is half a day: the
  header row would carry the actions apart from its buffer and the list
  would place them as it places a badge.
- **An environment modifier between the section and `.sectionActions`**
  (`Section { … }.headerProminence(.increased).sectionActions { … }`) hides
  the section from the list, which draws it without its actions — checked in
  a test run. That is the list's own limit: it does not see a `Section`
  through an environment modifier, with or without actions.

### B79. Tab view customization is the app's to change; no gesture changes it

*`TabViewCustomization` (all members, `SectionCustomization`,
`TabCustomization`), `View.tabViewCustomization(_:)`,
`TabContent.customizationID(_:)`, `.defaultVisibility(_:for:)`,
`.customizationBehavior(_:for:)`, `AdaptableTabBarPlacement`,
`TabCustomizationBehavior`, `AppStorage`/`SceneStorage`
`init(wrappedValue:_:)` for a customization*

Measured on macOS 15.8 (offscreen `NSHostingView`, a customization bound): a
tab whose `[tab:].sidebarVisibility` is `.hidden` leaves the
`.sidebarAdaptable` sidebar and stays in a `.tabBarOnly` tab bar;
`.defaultVisibility(.hidden, for: .tabBar)` and `for: .automatic` leave the
tab in both. macOS lets the user drag sections to reorder them and offers no
visibility control of its own ("a custom experience should be provided",
says the documentation). Its encoding is private (a UUID, `perTabState`,
`perSectionState`).

**Shipped:** all of it, as measured, with the shape of table column customization (B45, shipped 2026-10-06): a hidden tab leaves
the sidebar and not a strip; a stated tab order (per section) and section
order are applied to the sidebar, the identified items taking the slots
identified items had; `Codable` in TUIkit's own encoding; persisted through
`@AppStorage`/`@SceneStorage` with no default written. The binding is read,
never written: the environment carries the value, not the binding, so the
render memos below the tab view stay on.

Where it differs:

- **No gesture reorders sections.** macOS drags them; a keyboard pair to move
  the focused section up and down needs a notion of a focused section the
  sidebar list does not have — about a day, with a decision on whether the
  list's cursor row or its section header is the thing moved. So a stated
  order comes only from the app or a decoded value.
- **`.defaultVisibility(_:for:)` and `.customizationBehavior(_:for:)` do
  nothing**, as on macOS: the placement the first acts on (`.sidebar`) and the
  behaviors the second restricts (`.reorderable`, `.disabled`) are not
  macOS's, so no macOS source can ask either for anything.

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
- **A draggable row is not picked up by `Table.onMove(_:)`** (TUIkit's own
  table-level reorder): the press carries the payload. SwiftUI's tables have
  no `onMove`; their reorder is a loop's `dropDestination` with draggable
  rows, which works here too.
- **A hierarchical table's loops take no insertions**: there the drawn rows
  are the open tree's, not one loop's, and an offset into a loop under a
  closed branch has no drawn slot. An hour or two, if wanted, to map the slot
  to the loop whose rows it falls among by walking the outline.

### B81. The find bar: Ctrl-G opens it, the current match is the selection, and other matches are not highlighted

*`View.findNavigator(isPresented:)`, `View.findDisabled(_:)`, `View.replaceDisabled(_:)`,
`FindContext`, `\.findContext`*

**Shipped** for `TextEditor` (refusal review P17): a bar above the text with a
search field, the match count, previous and next, Done, and a replacement row
unless replace is disabled. Matching ignores case. Return finds the next match,
Escape closes the bar, and the bar writes `false` back to the binding when it
closes.

**What differs, and what a fuller version would cost:**

- **The key.** macOS opens find with Cmd-F, which a terminal keeps for itself.
  Ctrl-F is the editor's "forward a character" (macOS's standard key binding),
  so the bar opens with Ctrl-G. A different key is a one-line change.
- **Only the current match is marked**, by selecting it in the editor, which
  scrolls to it. macOS also highlights every other match. Drawing them all is
  about half a day: the editor's rows would take a list of ranges to tint, as
  they take the selection.
- **No options menu.** macOS's find bar offers "Contains", "Starts with",
  "Full word" and case matching. The bar searches for the literal text,
  ignoring case; the options would be a menu and a day.
- **No Find Next from the editor.** With the bar closed, Cmd-G and Shift-Cmd-G
  move between matches on macOS. A terminal binding for them is the same
  question as the key above.

### B82. Spring loading: a paused drag activates a control, undrawn

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
- **The descriptions are TUIkit's spelling** (`.ended(.move)`,
  `DragSession.ID(3)`, `DragConfiguration(operationsWithinApp: [.copy,
  .move], …)`): SwiftUI does not document its own, and it is macOS 26 only.

The fuller version is A53. A macOS 26 measurement pass is owed either
way.

*Lane 17t's entries (B84–B88, C13–C14), `Text(AttributedString)` and Markdown in `Text` keys (refusal review P8): SwiftUI's rules measured on macOS 15.8 (SDK 26.2) by comparing offscreen bitmaps; the probes and the differential fuzz harness are in the session notes, `w17t`.*

### B84. On macOS, SwiftUI's attribute scope is visible beside TUIkit's

*`AttributeScopes.SwiftUIAttributes` and its members, `AttributeScopes.swiftUI`,
`AttributeDynamicLookup.subscript(dynamicMember:)`*

TUIkit imports AppKit (for the `NSColor` and `NSImage` bridges), and AppKit
loads SwiftUICore. Swift makes every extension member of every loaded module
visible, so a TUIkit app on macOS sees SwiftUICore's
`AttributeScopes.SwiftUIAttributes` as well as TUIkit's. This is the same leak
B50 met with `SystemFormatStyle`'s statics.

**Since 2026-10-05 this applies only to an app that imports `TUIkitAppKit`
(or AppKit itself).** B50 shipped: the AppKit bridges are the `TUIkitAppKit`
module, no module TUIkit is built from imports AppKit (a test guards it), and
an app that imports TUIkit alone sees no SwiftUICore member. The rest of this
entry describes the app that imports the bridges too.

**Shipped:**

- **Setting and reading an attribute binds to TUIkit's.**
  `string.foregroundColor = .red` and the rest resolve here, because TUIkit
  declares one dynamic-member subscript per key where SwiftUI declares one
  generic subscript. A concrete overload outranks a generic one, so TUIkit's
  wins; two generic ones would tie and be ambiguous. (AppKit's own subscript is
  `@_disfavoredOverload`, which is how SwiftUI's beats AppKit's.) This was
  measured against a standalone module that imports AppKit, and it is pinned
  by the compile corpus.
- **Inside TUIkit, the leak is closed.** The TUIkit target turns on
  `MemberImportVisibility`, so SwiftUICore, which no TUIkit file imports, is
  invisible there. Without it, TUIkit could not spell its own scope in a type
  position.

**What remains, on macOS only:**

- **Naming the scope's types in a type position is ambiguous** in an app,
  for example `let key: AttributeScopes.SwiftUIAttributes.FontAttribute.Type`.
  The test suite reaches keys through the lookup for this reason.
- **An attribute only SwiftUI has, such as `kern`, compiles and then fails to
  link.** It binds to SwiftUICore's subscript, and SwiftUICore admits no
  direct clients. On Linux it fails to compile, as rule 2 wants.

**The fuller version** was B50's, and shipped with it on 2026-10-05: the AppKit
bridges (`Color(nsColor:)`, `NSColor(_:)`, the `CGColor` pair, `Image`'s
`NSImage`/`CGImage` initializers) are the `TUIkitAppKit` module. An
`internal import` of AppKit was not enough — it still loads SwiftUICore into
clients of a SwiftPM module — so TUIkit imports none.

### B85. A link in a `Text` is drawn and hyperlinked, but is not a control

*`AttributeScopes.FoundationAttributes.link` as `Text` draws it; Markdown
`[label](url)` and autolinks*

SwiftUI makes a `Text`'s link clickable, and it opens through the
`OpenURLAction` in the environment.

**Shipped:** a link run is drawn as follows:

- **Colour:** the accent, which follows `.tint`, as SwiftUI's link colour does.
  The run's own colour wins over it, and the text's `.foregroundStyle` does not
  reach it, as measured.
- **Underline:** underlined, as `Link` is. This is TUIkit's deviation, for
  `Link`'s reason. `.linkUnderline(false)` removes it.
- **Hyperlink:** an OSC 8 hyperlink under `Link`'s three conditions:
  - the host honours OSC 8;
  - `.terminalHyperlinks` allows it;
  - the text is enabled.

  It is emitted as one balanced pair per line, with an id when the link wraps.

The destination is the terminal's to show and open. The link takes no focus
and no click, so on a host without OSC 8 (Apple Terminal) the destination
cannot be reached from the text.

**The fuller version:**

1. **Make a text's links reachable from the keyboard.**
   - Each link registers a focus stop (`text-link-<identity path>#<run>`), and
     Tab moves through them.
   - A focused link's words breathe, as `Link`'s `.text` indicator does.
   - Return opens the link through `OpenURLAction` and raises `Link`'s
     destination popover.
   - A click on a link fragment does the same. That needs a hit region per
     fragment, which the render already knows.

   About two days. The work is a leaf `Text` that registers focus and animates
   one run. The keyboard part is not optional: a click-only link would break
   the no-mouse-only rule.
2. **Honour `.linkDisplay(.urlInParentheses)` and `.urlOnly` for text links.**
   The URL would be written after or instead of the label, so Terminal.app
   users can read it. Half a day. The measure has to see the added text.

**Recommendation:** 2 now if Terminal.app matters; 1 when an app needs inline
links it can activate.

### B86. TUIkit's Markdown parse is its own, with two known differences

*Markdown in `Text(_ key: LocalizedStringKey)`*

Foundation's Markdown parser is Darwin-only. swift-foundation has neither
`AttributedString(markdown:)` nor `InlinePresentationIntent`; this was checked
on the 6.3.3 static Linux SDK. TUIkit therefore parses with `InlineMarkdown`:

- CommonMark's inline algorithm;
- cmark-gfm's strikethrough and autolink extensions;
- Foundation's own quirks, each one measured:
  - a tilde is a skip character;
  - emphasis nested in emphasis ends the outer one;
  - openers are keyed in the pre-0.30 way;
  - an unbalanced `(` is allowed in a bare destination;
  - the email scan's carried dot count;
  - link text drops its emphasis;
  - an image with no alt text becomes U+FFFC.

It agrees with Foundation on a 138-case table and on 550,000 random strings,
with two exceptions:

1. **Named character references beyond about 140 common ones.** `&Aacute;`
   draws as written; Foundation knows all 2,125 HTML names. The full table is
   20 KB of generated source and an hour's work.
2. **Link reference definitions.** In inline-only mode Foundation still
   consumes a `[label]: destination` line and makes `[label]` elsewhere a link.
   TUIkit draws both as text. Definitions and reference links would take half
   a day. A UI string that starts with `[x]: …` is rare.

**Two places where TUIkit draws differently, neither a parse difference:**

- **`^[text](inflect: true)`** (automatic grammar agreement) draws its text
  without inflecting it. TUIkit has no inflection engine. SwiftUI also draws
  "2 apple" when it has no localized bundle, as measured.
- **A code span** draws as plain text, because every cell is monospaced
  already.

**Cost:** a key whose resolved text holds none of the bytes a construct starts
with, no `://`, no `www.` and no `@` after an address character pays one
allocation-free byte scan and takes the old path. A Markdown text's runs are a fresh array each frame, so the
per-pass value memo misses on such a text. That is already true of every
concatenated text.

The memo counters agree with that. `Stress --bench`, 200 iterations, was run
before this wave and after it on `textwall`, `fanout`, `menus`, `kitchensink`
and `dashboard`:

- Every checksum is identical.
- Every memo count is identical. On `kitchensink` and `dashboard` that took a
  second run of the base build, whose first run differed by the run-to-run
  variation the Stress README describes.
- `Text`'s stored size is unchanged (56 bytes, the `TextLayoutPaddingTests`
  pin).

**The A/B, run in the performance pass (quiet machine, `ab_bench.py`), found
the scan letting every interpolated key through.** An interpolation's
placeholder is `%@`, and the scan took any `@` as a possible email address, so
`Text("#\(index)")` ran the whole parse on every construction:
`scrollfollow` +53%, `churn` +18% and `gradients` +12% against the build before
this lane. The scan now takes an `@` only after a byte an address's local part
can end with, as the email scan itself requires; that recovered `scrollfollow`
−33%, `churn` −14%, `gradients` −9%. A key that really holds Markdown parses
its template once: the parse never reads a value, so it is kept per resolved
template (`MarkdownTemplate`, with whether the key has values), and each
construction only puts its values in.

**Recommendation:** leave both differences until a translation needs them.

### B87. Markdown in the title keys of controls other than `Text` is not parsed yet

*`Button(_:action:)` and the other `LocalizedStringKey` initializers*

SwiftUI parses Markdown in a control's title key. Measured: `Button("**Save**")
{}`, `Toggle`, `Label`, `Link` and `LabeledContent` all draw the bold. TUIkit's
controls resolve the key eagerly to a `String` (`key.localized`) and draw it as
written, so the asterisks show. This gap existed before this wave. It is more
visible now that `Text("**Save**")` is bold.

**The fuller version:** each control whose SwiftUI label is a `Text` builds its
label with `Text(titleKey)`.

- **Scope:** about 30 initializers across about 20 controls, including
  `Button`, `Toggle`, `Label`, `Link`, `LabeledContent`, `Section`, `Picker`,
  `Menu` and `DisclosureGroup`.
- **Prerequisite:** some of these store the title as a `String` and measure or
  truncate it, `Button`'s `label` among them. They would store a `Text` and
  measure that instead.
- **Price:** about a day with the tests. The `LocalizedTitleTests` round trips
  would each gain a Markdown case.
- **What stays as is:** TUIkit's own chrome (status-bar labels, `Alert`,
  `Card`, `Dialog` titles) has no SwiftUI meaning to match.

**Recommendation:** do it for the SwiftUI controls listed above.

### B88. A live text with an attributed format draws the characters only

*`Text(_:format:)` over a `TimeDataSource` with an `AttributedString` output;
`LocalizedStringKey.StringInterpolation.appendInterpolation(_:format:)` with
one*

The one-off `Text(_:format:)` now draws an attributed output's attributes.
The live form reads only words at each frame (a `LiveTextSource` returns a
`String`), and an interpolation's arguments are strings. Neither draws the
attributes.

Foundation's own attributed styles set only field attributes, which say what a
run is (a year, a day) rather than how it looks, and SwiftUI ignores them too.
So the only difference is for a custom style that colours its output.

**The fuller version:** a live source that returns runs. About half a day.

### B89. A control takes the press once the gestures ahead of it give up; it cannot wait

*`View.gesture(_:including:)`, `View.highPriorityGesture(_:including:)`,
`View.simultaneousGesture(_:including:)` (all forms), `GestureMask`*

The arena (`Sources/TUIkitFoundation/App/GestureArena.swift`) ranks every region under
a press: gestures, and the ordinary controls' regions — a `Button`'s press is
one of the view's own gestures and ranks as one, as measured. A gesture is a
recognizer: it sees every event, is held back while anything ahead of it is
undecided, and reports what it held back once released. A control is not: its
press handler acts at once. So a control is given the press when everything
ranked ahead of it has given up, and from then on owns the press as it always
did.

Where that differs from macOS:

- **A control never fails.** macOS's plain-style button fails when its press
  is released off it, and a `.gesture(DragGesture())` attached to it then
  reports its end. Here the button owns the press, and the drag never hears
  it.
- **A control behind an undecided gesture gets the press late.** Under a
  high-priority tap, a button draws no pressed state until the tap fails; a
  `.gesture(TapGesture(count: 2))` on a `List` row holds the row's selection
  back by the double-tap interval, since the list waits for the double tap to
  fail. (macOS's bordered `Button` is an AppKit control that ignores attached
  gestures altogether — measured: none of tap, high-priority, simultaneous,
  long press or drag ran on it. TUIkit's buttons are drawn, and follow the
  plain-style SwiftUI button, which was measured.)

**The fuller version** makes controls recognizers: each control's press
handler reports possible, recognized and failed, and accepts a cancel. A day
and a half — fifteen-odd controls, and every mouse test that reads a
control's press.

### B90. Distances are cells along either axis

*`DragGesture.minimumDistance`, `LongPressGesture.maximumDistance`, the tap's
slop*

SwiftUI counts Euclidean points: a drag starts at 10, a long press fails past
10, a tap fails past 40. **Shipped:** whole cells counted along either axis,
as `onLongPressGesture` already counted — one cell by default for the first
two (the smallest move a terminal reports), and five columns or two rows for
a tap (40 points over a typical 8×17-point cell). `DragGesture(minimumDistance:
10)` written for SwiftUI therefore asks for ten cells here, the §2.1 porting
note.

**The fuller version** measures in points: the terminal reports its cell size
in pixels (`TIOCGWINSZ`, CSI 16 t — `Terminal compatibility survey.md` records both
per host), so a distance could be converted and compared as SwiftUI compares
it. Half a day, and it reopens §2.1 for these three: a distance in points
would be the only `CGFloat`-like measurement in the API.

### B91. A drag's velocity is an average of the report-to-report speeds

*`DragGesture.Value.velocity`, `.predictedEndLocation`,
`.predictedEndTranslation`*

**Shipped:** each motion report's speed since the last one, in cells per
second from the times the reports arrived, averaged with the estimate so far.
A pointer held still sends no reports, so its velocity is the last motion's —
macOS keeps it too (measured: 658 points per second after 0.3 s still). The
predicted end is a quarter of a second on at that velocity, the horizon
SwiftUI defines its own velocity against (four times the predicted end's
distance from the location). macOS's estimator itself is unknown; on a
synthetic drag of 20 ms steps it runs below the instantaneous speed, a
smoothed estimate.

**The fuller version** fits the last 100 ms of reports by least squares, as
UIKit's pan recognizer does. Two hours; it matters only to fling physics.

### B92. Timed recognizers run on the frame clock

*`LongPressGesture`, `TapGesture` (its hold limit and its multi-tap wait),
`View.onLongPressGesture(minimumDuration:maximumDistance:perform:onPressingChanged:)`*

**Shipped:** the run loop ticks the arena at the start of each frame and wakes
for the next deadline, so a long press ends — and a double tap gives up — on
the first frame at or past its deadline, as `onLongPressGesture` already did.
A deadline starts at the first frame after the event that armed it rather
than at the event's own report time, a few milliseconds later; event-to-event
intervals (a tap's hold, a multi-tap's gap) use the report times.

**The fuller version** starts the deadline at the report time. In an app the
two clocks are one; in a test harness they are not, which is why they are
kept apart. An hour, with the harness's clocks joined.

### B93. Two double-click windows: a row's and a tap's

*`TapGesture(count:)`, `SpatialTapGesture(count:coordinateSpace:)`,
`View.onTapGesture(count:perform:)`; and, for comparison,
`List`/`Table` `onRowActivate(_:)`, `MouseEvent.clickCount`*

A tap counts its own clicks, as measured: the next click released within
0.35 s of the last release (a press in time but held past that gives the tap
up then, with the button still down). The dispatcher's `clickCount`, which rows open on, counts presses
within 400 ms of each other (macOS's `NSEvent.doubleClickInterval` is 0.5 s,
and `NSTableView` uses it). **Shipped:** both, each matching its macOS
counterpart's kind.

**The alternative** is one interval for both — 0.35 s, or the dispatcher's
0.4 s for taps too. Half an hour either way; the first slows nothing, the
second departs from SwiftUI's measured taps.

### B94. `onTapGesture` and `onLongPressGesture` are gestures now

*`View.onTapGesture(count:perform:)`, `View.onTapGesture(count:coordinateSpace:perform:)`,
`View.onLongPressGesture(minimumDuration:maximumDistance:perform:onPressingChanged:)`*

They were mouse handlers that took the press outside-first, tapped wherever
the release landed, and ran a long press's action before its pressing
callback's `false`. **Shipped:** each is the `TapGesture`, `SpatialTapGesture`
or `LongPressGesture` it is on macOS, attached with `gesture`, so:

- a gesture inside the view, or the view's own press, comes first — a tap on
  a `Button` no longer takes its click;
- a release off the view, past the slop, or after 0.75 s is no tap;
- `.onTapGesture(count: 2)` inside `.onTapGesture` delays the single tap until
  the double one has given up, and a double-click runs only the double; a
  click on another view meanwhile does not give the double tap up, and the
  single tap still runs for the first click when it does;
- `onPressingChanged(false)` comes just before the action.

**The alternative** kept the old behaviour, which no SwiftUI app expects.
Every in-repo use was checked (the Mouse page, an outline triangle, the Stress
log rows) and the full suite passes.

*Lane 17m's entry (B95), `MeshGradient` (refusal review P11): measured on macOS 15.8 (SDK 26.2) against offscreen renders, with the fitting scripts in the session notes, `w17m/probe`.*

### B95. A mesh is one sample a cell on a glyph terminal, and a picture where the terminal takes one

*`MeshGradient` (its five initialisers, `width`, `height`, `locations`,
`colors`, `background`, `smoothsColors`, `colorSpace`, `resolve(in:)`, `Body`,
`Resolved`), `MeshGradient.BezierPoint` (its initialiser and five points),
`MeshGradient.Locations` (`.points`, `.bezierPoints`),
`MeshGradient.Colors` (`.colors`, `.resolvedColors`); `Paint.mesh` and
`MeshPaint`, TUIkit's own*

**Shipped:** all of SwiftUI's surface, a style and a view. Each cell takes
the mesh's colour at the cell's centre; an opaque mesh used as a view, or
behind blank cells, is a picture on a graphics terminal; inside
`withAnimation` its vertices slide and its colours fade. Measured on macOS
15.8, and pinned at SwiftUI's own pixels in `MeshGradientTests`:

- **A patch is a Coons patch.** The interior control points fitted from
  SwiftUI's picture match PDF's type 6 formula to the probe's noise.
- **An implied control point** (the `points:` form) lies a third of the way to
  its neighbour, along the line bisecting the vertex's two edges in that
  direction; an edge vertex aims straight at its one neighbour. Residual on
  four warped meshes: 0.7–0.9 px on a 201 px picture, against 2–4 px for
  straight thirds or Catmull–Rom tangents.
- **`smoothsColors`** is a bicubic Hermite patch per channel, with no twist,
  whose slope at a vertex is half the difference of its neighbours — zero at
  the mesh's edges (not one-sided), zero at a peak or a trough, and capped at
  three times the smaller difference. 1 level in 255 against SwiftUI, which is
  its own tessellation; bilinear blending matches to the byte.
- **`.perceptual`** makes those slope decisions per channel of OKLab's
  cube-root cone space, the stage before OKLab's last matrix: 1.4 levels
  against SwiftUI, where deciding them in OKLab itself missed by 12. (For a
  bilinear blend the two spaces give the same answer.)
- **Translucent colours blend premultiplied**; `background` fills what no
  patch covers (`.clear` by default); a mesh with fewer than two vertices in a
  direction, or a point count other than `width × height`, draws its
  background alone; a missing colour is `.clear`.
- **Inside `withAnimation`** SwiftUI moved a mesh's column at even steps and
  stepped its colours exactly as a `LinearGradient`'s stops beside it.

Where it differs, or rests on less than a measurement:

- **One sample a cell.** A cell is the mesh at its centre, so a smooth mesh is
  a staircase on a glyph terminal; the picture path removes the staircase
  where the terminal draws pictures. This is the same rule every gradient
  follows.
- **Exact evaluation, not SwiftUI's tessellation.** TUIkit evaluates the
  Hermite patch at each sample; SwiftUI interpolates linearly between the
  vertices of its tessellation. The two differ by a level or two where a colour
  curves.
- **The slope cap is spelled as a box, not a circle.** "At most three times the
  smaller difference" and Fritsch–Carlson's α² + β² ≤ 9 both fit every probe:
  with Catmull–Rom slopes they part only once one difference is about five
  times the other, and then by under 2 % of the slope. Telling them apart
  needs one more probe aimed at that band, an hour; the colour it could move is
  under a level.
- **A folded mesh draws its patches in reading order**, a later one over an
  earlier. SwiftUI's order where patches overlap was not measured.
- **Whether a mesh is opaque throughout is decided conservatively.** A mesh
  whose outline lies on its box's edges covers the box, and is opaque if its
  colours are; one that covers the box some other way (points past its edges)
  is treated as letting a `.clear` background through. It draws the same,
  through the translucency path, which costs more and leaves an `.opacity`
  inside it carried up rather than spent against the mesh.
- **A colour with no RGB** — `.default`, an unreported terminal slot — cannot
  be blended: a patch with one takes whichever corner weighs most at the point,
  whole. This is `Color.lerp`'s rule for a gradient stop; SwiftUI has no such
  colour.
- **At 256 colours each cell is quantised on its own.** A ramp's quantiser
  repairs monotonicity along the ramp; a mesh has no order to repair along.

**The cost**, debug build, one mesh over 80 × 24 cells: 0.9 ms for a grid
mesh (each cell finds its patch by two divisions) and 3.4 ms for a warped one
(each patch split by de Casteljau until a piece is within a twentieth of a
cell of its corners' bilinear map). A picture of the same box at 640 × 408
pixels fills in 104 ms and 170 ms, once per picture: the store asks for the
bytes only when the terminal does not already hold them, which is new for
every gradient picture (before, each render of a ramp behind blank cells
filled its whole picture first). A `Table`'s ramp runs over every row of its
data, so a mesh there is worked out a band of eight rows at a time, only for
the rows asked about.

**The fuller version: two samples a cell on a glyph terminal.** A gradient
used as a view — any of the five, behind blank cells — could draw each cell as
an upper half block (`▀`) whose foreground is the sample a quarter of the way
down the cell and whose background the sample three quarters down, doubling
the vertical resolution where there is no picture. `Image` already draws this
way. About half a day with the self-check, and a look in Apple Terminal and
Warp, which take no pictures and are where it would show. It changes how every
gradient view looks on those terminals, and copying such a region yields `▀`
rather than spaces, which is why it is not done here.

## C. Declined without asking

### C1. `CGPoint`, `CGSize` and `CGRect` as `Animatable`

*`CGPoint.AnimatableData`, `CGSize.AnimatableData`, `CGRect.AnimatableData`*

This is a compiler wall, not a judgement. On Apple platforms, SwiftUICore's
own extensions of the CoreGraphics types are visible to any module that
imports Foundation, through a cross-import overlay. That is the same overlay
`Collection+Offsets.swift` already works around. SwiftUICore's
`AnimatableData` typealias on each type is found before any witness TUIkit
could give, so `extension CGPoint: Animatable` does not compile on macOS. I
tried with and without an explicit typealias.

`CGFloat` *is* conformed, because there the wall has a door. An app's ported
`Animatable` type with `CGFloat` data compiles and animates, and so does
`AnimatablePair<CGFloat, CGFloat>`. What stays ambiguous on macOS is calling
the extension methods directly on a concrete value (`x.interpolated(…)`).
That call never linked before either.

### C2. `CGPoint.applying(_:)`, `EdgeInsets.inset(by:edges:)`, `EdgeInsets.init(_:)`

- The first two take types that were already declined: `ProjectionTransform`
  and `RectangleCornerInsets`.
- The third converts AppKit's `NSDirectionalEdgeInsets`, whose values are
  points. The conversion would need an invented point-to-cell scale.

### C3. `AttributeDynamicLookup`

This is folded into the existing `AttributeScopes*` family rule, whose reason
it shares.

**That family is itself on the Wave 17 re-examination list.** SwiftUI's
attribute scope carries a foreground colour, a background colour, an
underline and a strikethrough, all of which a cell grid has. So
`Text(AttributedString)` may well be implementable.

### C4. `KeyEquivalent.clear`

*`KeyEquivalent.clear`*

SwiftUI's `.clear` is AppKit's Clear key, U+F739: the keypad key in Num
Lock's position on a full-size Mac keyboard. A shortcut or `onKeyPress` on it
fires only if a terminal sends that key as a key of its own. The legacy
encodings TUIkit parses have no sequence for it, and the parser has nothing
to map to it. So `.clear` would name a key no event can carry, and a
shortcut on it would compile and never fire. Rule 2 says leave it out.

Not byte-captured: this machine has no extended keyboard. If a terminal turns
out to send the key, distinctly from Num Lock, the parser gains a case and
this entry goes. The kitty keyboard protocol (A4, shipped 2026-10-05) is the likeliest
route: it reports keypad keys by their own codes.

### C5. `HelpLink(anchor:)` and `HelpLink(anchor:book:)`

*`HelpLink.init(anchor:)`, `HelpLink.init(anchor:book:)`*

Both open an anchor in an Apple Help book, through AppKit's `NSHelpManager`
and the Help Viewer. A terminal app has no help viewer to open, and Linux and
Windows have no help books. `HelpLink(action:)` and `HelpLink(destination:)`
ship, so a help button that runs code or opens a URL ports as written.

### C6. `scrollInputBehavior(_:for:)` and `ScrollInputKind`

*`ScrollInputKind`, `View.scrollInputBehavior(_:for:)`*

`ScrollInputKind`'s values are watchOS's — the Digital Crown and the
double-tap hand-gesture shortcut — and the macOS SDK defines none. No macOS
source can name a kind, so none can call the modifier: declining it changes
what compiles for nobody. A terminal has neither input. What macOS code can
ask — may this view scroll at all — is `.scrollDisabled`, already the
`ScrollInputBehavior` map entry.

### C7. `ScrollView.showsIndicators`

*`ScrollView.showsIndicators`*

The stored property behind the soft-deprecated
`ScrollView(_:showsIndicators:content:)`, which TUIkit omits as it omits every
soft-deprecated spelling. `ScrollView.init`'s comment records why the
property was not kept with it: it was a second, hidden answer to the question
`.scrollIndicators(_:axes:)` answers. The property itself is not deprecated,
so this is the one arguable entry in this part: a settable `Bool`, `false`
meaning `.scrollIndicators(.hidden)` for that view, is twenty minutes if you
would rather SwiftUI code that reads or writes it compiled.

The `ScrollView.Body` map entry claimed the property was public; it never
was, and the entry now says so.

### C8. `TypesettingLanguage`

*`TypesettingLanguage` (`.automatic`, `.explicit(_:)`),
`View.typesettingLanguage(_:isEnabled:)` and `Text.typesettingLanguage(_:isEnabled:)`
in both forms*

The language a run is typeset in sets its line height (taller for Thai, say),
its line breaking and its spacing. Line height is the terminal's row, and
spacing is whole cells. TUIkit's word wrapper breaks at spaces and at
characters a line cannot hold, whatever the language, so a language would
change none of the three, and accepting one would be the quiet no-op the
parity rules forbid. If the wrapper ever learns dictionary-based breaking
(Thai, Khmer and Lao have no spaces between words), this becomes its
modifier.

### C9. `@FocusedObject`, `focusedObject(_:)`, `focusedSceneObject(_:)`

*`FocusedObject` (and its `Wrapper`, `init()`, `wrappedValue`,
`projectedValue`), `View.focusedObject(_:)`, `View.focusedSceneObject(_:)`*

All three take an `ObservableObject`, the Combine-based family §2.3 of the
compatibility doc declines for the whole framework. The `@Observable` forms
SwiftUI offers beside them ship — `@FocusedValue(Model.self)`,
`.focusedValue(model)`, `.focusedSceneValue(model)` — so the map entries are
`differentShape`, naming those.

### C10. `OutlineSubgroupChildren`

*`OutlineSubgroupChildren`*

The content type of the `DisclosureGroup` that is SwiftUI's
`OutlineGroup<…, Subgroup>` for views — a type only ever written inside
`OutlineGroup`'s full generic signature. TUIkit's `OutlineGroup` declares
the three generic parameters that carry information and drops the two that
are always the same (`Parent` is `Leaf`; `Subgroup` is that one
`DisclosureGroup`), as its documentation records, so there is no subgroup
type for this to be the content of. Every `OutlineGroup` initializer, for
views and for table rows, is SwiftUI's; only spelling the type out by hand
differs.

### C11. `Tab`'s `image:` initialisers join the asset-catalogue family

*`Tab.init(_:image:content:)`, `Tab.init(_:image:role:content:)`,
`Tab.init(_:image:value:content:)`, `Tab.init(_:image:value:role:content:)`*

The `image:` spelling names an `ImageResource` from an asset catalogue, which
a terminal app's build does not have — the reason `Button`, `Label`, `Picker`,
`Menu` and the rest already give in `parity-map.json`. The `systemImage:`
forms are implemented. `Tab.init(_:image:*` is added to that family's
patterns.

### C12. The drag sessions' AppKit comparisons

*`DragSession.ID.matches(_:)`, `DropSession.ID.matches(_:)`*

Each compares a session with AppKit's own dragging object
(`NSDraggingSession`, `NSDraggingInfo`), which a TUIkit drag never is: a
terminal app drags inside itself, without AppKit, and Linux has no AppKit at
all. The review listed both as its CONFIRM for P18. They are now the only
declined members of the family, each with its own `notImplemented` entry; the
family rule that declined the rest is gone.

### C13. Sub-cell typography and paragraph metrics in the scope

*`AttributeScopes.SwiftUIAttributes.kern`, `.tracking`, `.baselineOffset`,
`.lineHeight`, `.alignment`, and `KerningAttribute`, `TrackingAttribute`,
`BaselineOffsetAttribute` with their members*

These are the attributed-string form of the `View` modifiers C8 declined. A
cell grid has one advance per cell, one baseline and one line height.

A run's paragraph `alignment` has nothing to carry it either. A `Text` aligns
its lines as one block (`multilineTextAlignment`), never paragraph by
paragraph, and `alignment` is macOS 26's, typed as a CoreText scope Linux does
not have.

Omitting them means setting one fails to compile on Linux. On macOS it fails to
link; see B84. `parity-map.json` has a family entry for them.

### C14. The adaptive image glyph

*`AttributeScopes.SwiftUIAttributes.adaptiveImageGlyph`,
`AdaptiveImageGlyphAttribute` and its members*

A Genmoji is a multi-resolution bitmap drawn inline at the font's size. A cell
holds a character. The image protocols that can place a picture do so at block
level, not as glyphs in a run of text. `parity-map.json` has a family entry.

`AttributeScopes.SwiftUIAttributes.accessibility` needed no entry of its own.
The existing Accessibility family covers it.

### C15. The multi-contact gestures, the window drag, and the recognizer bridge

*`MagnifyGesture`, `RotateGesture`, `SpatialEventGesture` (and their members);
`WindowDragGesture`; `View.gesture(_:)` (an `NSGestureRecognizerRepresentable`)*

The gesture family in `parity-map.json` now holds only the first three, with
a reason that holds: they recognize the scale and angle between two contacts,
or report every simultaneous contact with its kind, 3D location and pose, and
a terminal's mouse protocols report one pointer — its cell, its buttons, the
wheel and three modifier bits. `WindowDragGesture` is declined with the Window
family (a TUIkit app has no window to drag), and `View.gesture(_:)` with the
AppKit-bridge family. The family's old reason — "no velocity, no simultaneous
touches, nothing to arbitrate" — is gone with what it refused.
