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
on 2026-10-12, and 90 on 2026-10-19 (94 on 2026-10-23, when C11's four `Tab` forms left the map for the baseline) (93 on 2026-10-24, when B96 closed `tabBarMinimizeBehavior(_:)`; 84 before C11's four shipped and 80 after) (`Tools/APIParity/baseline.json`), plus
three overloads only CI's SDK lists. Besides the gaps, the refusal review's
implementable P items have shipped, and so has Wave 11b, underline and
strikethrough patterns and colours, which you read on real terminals on
2026-10-18.

**How your answers are recorded.** Your review of 2026-10-04 (A1–A54,
B1–B37), my answers to its questions of 2026-10-05 (which you answered
"Proceed", so their proposals count as approved) and your rulings of
2026-10-12 are folded into the entries, each dated. An entry whose work has
landed is removed, and no entry is renumbered. **Lane owed** marks an entry
that is decided and waits only on its implementation.

**Still yours to answer.** None of the A entries: A27 (pixel effects) and A48
(swipe actions) were answered on 2026-10-26, A27 with option 2 and A48 with
its recommendation, and are lanes owed. A34 (the blur transition) was answered on
2026-10-23 with its option 2 and has shipped (lane VISUALS, decisions
`Historical/Shapes, effects and animation/`, by id).

**Decided, waiting on a measurement.** A16's colour provider waits on an A/B on
the quiet machine. A40's default dissolve was measured on 2026-10-15 and, as
agreed, not shipped: it cost far more than 1% (see A40).

**Decided, lane owed.** A0's ruled O items but O1, O2, O7, O17 and O16 (deferred), and with them
A22 and A26 (O9) and A24 (O0, O15); A42, B19 (after its A/B). B22's look at
the faint tiers was taken on 2026-10-19 (lane EFFECTS): the faintest vanish at
16 and 256 colours, and what to do is A-EFFECTS-1, in
[Blend modes and image details (EFFECTS)](<../../Historical/Shapes, effects and animation/Pixel effects: transforms, masks, drawingGroup, blend modes and meshes.md>).
B3's lane shipped on 2026-10-13 with most of A21; A21 lists what is left.
Shipped on 2026-10-14 (their entries removed): A25; O7 with A12; O1; O17; O2 with A37.
Shipped on 2026-10-18: O0's shapes (lane W1); O3's merging and additive
retargets with A38; O5's materials with A41, and its glass; O6's shadows;
O13's menu bar; O4 with A23 and A36.
Shipped on 2026-10-19: O8's refusals, with A11 and A51.

**Deferred.** A3, and B8's mirroring, with right-to-left (B1); A50 and A53
until macOS 26 or 27 can be measured.

**Waiting on another answer.** None: A39 was answered with A27 (declined,
2026-10-26).

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
O8 refuses the APIs that are inert on macOS too, which settled A11 and A51; O11 is deferred, not refused for good); each
ruling is in the review under its item. In brief, with the ruling:

- **O0** The unit of a shape's path. This gates the whole Shapes cluster:
  `Shape`, `Rectangle` and its members (`path(in:)`, `inset(by:)`,
  `corners(in:)`, `InsetShape`), `clipShape`, `contentShape`, `background(_:in:)`.
  **Keep (B)**, square units: the display scale cancels out of the cell's
  ratio, which (C)'s absolute size cannot say. Shipped 2026-10-18
  ([Shapes (W1)](<../../Historical/Shapes, effects and animation/Shapes.md>)).
- **O1** Reduce-motion and the other accessibility preferences. **(b), but
  only `TUIKIT_REDUCE_MOTION`** (B53, shipped) unless TUI can be confident
  the terminal is on the same machine; then the host's setting too, by the
  clipboard's locality test. Shipped 2026-10-14.
- **O2** `PhaseAnimator` and `KeyframeAnimator`. **(b)**; (c) is not easy,
  so it is presented after (b). (b) shipped 2026-10-14.
- **O3** `CustomAnimation`. **Detect, else live**: integrated lazily and
  memoised, a finished animation is its own pre-sampled table. Shipped
  2026-10-14 (`CustomAnimationCurve`); merging a retarget by `shouldMerge`,
  and running two side by side, shipped 2026-10-18: an interrupted animation
  carries its motion on, and an interpolating spring adds to the change it
  interrupts.
- **O4** Matched geometry and zoom transitions. **(b), with (a) where
  possible.** Shipped 2026-10-18 with A23 and A36
  ([Matched geometry and the zoom transition (O4)](<../../Historical/Shapes, effects and animation/Matched geometry and the zoom transition.md>));
  the zoom source's clip shape and shadow follow in lane W1B (B-O4-6).
- **O5** Materials and Glass (A41, now removed, listed the material symbols waiting on it).
  **(b) for both**; a cell-resolution blur is an optional add-on. Materials
  and glass shipped 2026-10-18 ([Glass (GLASS)](<../../Historical/Shapes, effects and animation/Materials and glass.md>)); the
  frost, the add-on, shipped 2026-10-24 (O5-FROSTED, [VISUALS](<../../Historical/Shapes, effects and animation/Materials and glass.md#o5-frosted-a-material-frosts-what-is-behind-it>)).
- **O6** `ShadowStyle`. **(b)**, radius and offsets in cells. `View.shadow(color:radius:x:y:)`
  and `ShadowStyle` shipped 2026-10-18; `ShapeStyle.shadow` waits on W1 ([Shadows (O6)](<../../Historical/Shapes, effects and animation/Shadows.md>)).
- **O7** `ScrollEdgeEffectStyle`. **Only `.hard`**; no `.soft`. Shipped 2026-10-14.
- **O8** APIs that are inert on macOS too: `submitLabel`, `SensoryFeedback`
  and others. **Refused**: they fail to compile, as `submitLabel` already
  did, and `scrollDismissesKeyboard` (A11) and `sectionIndexLabel` (A51) with
  them. Recorded in the parity map 2026-10-19.
- **O9** Multi-scene apps. **(b)**, leaving room for real windowing.
- **O10** File panels. **(b)**, TUI-drawn open and save dialogs.
- **O11** The `formatter:` APIs. **Deferred** (ruled 2026-10-12): not refused
  for good, and not built now.
- **O12** `PointerStyle`. **(b)**, inert where unsupported (the review's
  facts about which terminals take OSC 22 were corrected).
- **O13** `Commands`, as a menu bar. **A full menu bar**; the app header
  optional, either, both or neither. Shipped 2026-10-18
  ([The menu bar (O13)](<../../Historical/Menus, toolbars and chrome/The menu bar.md>)).
- **O14** `ControlSize`. **(b)**, with extra render styles per size. The
  type, the environment value, both modifiers and the button's table shipped
  2026-10-15 (`ButtonFaceEdges.swift`); the other controls' rows 2026-10-19,
  on one row each: a segmented picker, a stepper, a slider and a text field
  follow the button's padding and caps, a checkbox and a switch draw alike at
  every size ([Forms and control density (FORMS)](<Forms and control density (FORMS).md>),
  B-FORMS-4 to B-FORMS-6).
- **O15** `ButtonBorderShape`. **Support it.** Shipped 2026-10-15 in O14's
  table, without the `Shape` conformance, which waits on O0.
- **O16** `TextRenderer`, with `View.textRenderer(_:)` and `Text.customAttribute(_:)`.
  **Defer.**
- **O17** The toolbar's `.title` and `.search` items. **Do them.** Shipped
  2026-10-14, with `DefaultToolbarItem`.

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
  style at every resolve. TUI's `Color` is five bytes with no padding:
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

**Shipped 2026-10-13** (the storage half; Core Data and O10 remain). On Apple platforms `@AppStorage`'s `store:` takes
a `UserDefaults` in every form SwiftUI has (the tab view and table column customization forms, and `@SceneStorage`'s
tab view one, included), and `View.defaultAppStorage(_:)` and `Scene.defaultAppStorage(_:)` take one; on every
platform both also take a TUI `StorageBackend`. An `@AppStorage` that names no store reads and writes the one set
nearest above its view, found before its body runs and kept in a lock-guarded box the property's copies share — so a
closure the body made writes where the body read — and `StorageDefaults.backend` where none is set. **Which stores
share change announcements** (decided in the lane, a technical call): a `UserDefaults` cannot name its domain, and two
made for one suite — `UserDefaults(suiteName:)` written in a view makes one each time the view is made — are two
objects, so every `UserDefaultsStorage` shares one `StoredKey` per key name. A write through any store over a domain
redraws the readers that read the key through any other; a key of that name in another domain costs its readers a
redraw that finds nothing new. The table lives with `UserDefaultsStorage`, not on the app, because the process's
default store exists before any app does. The alternative, documenting "pass a long-lived `UserDefaults`", would have
left the inline spelling SwiftUI code commonly uses showing stale values.

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
   storage spellings TUI's own (`StorageBackend`), with
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
Whether that admitted option 1's framework spellings was left open on
2026-10-04, and answered on 2026-10-12 (above): it does. What remains is
Core Data's `FetchRequest`, unbuilt; O10's file panels shipped with
`FileDocument` on Apple platforms only.

*Wave 9's entries (A20–A25, B34–B41, C9; A19 shipped 2026-10-06): SwiftUI's behaviour is from its own doc comments unless an entry says it was measured.*

## B. Shipped the safe option

### B2. `\.legibilityWeight` is settable, and every text-drawing site steps its weight

SwiftUI's is settable. Under `.bold`, every piece of system text is drawn
one weight heavier. That was measured on a SwiftUI build: light→regular,
regular→bold, and bold stays bold. In SwiftUI that includes control labels.

TUI draws many labels without going through `Text`, so honouring it in
`Text` alone would be a partial honour, which is the shape Rule 2 forbids.

**The fuller version** is one "heavier by one step" rule applied at every
text-drawing site:

- faint→normal, normal→bold;
- `Text`, button and control labels, field contents, list chrome.

Alternatively, apply it once at the subtree's buffer, the way
`SGRColorRewrite` applies a colour effect. The rewrite is cheaper to get
complete, but it would also embolden non-text glyphs (borders, bars). That
is a reason to prefer the per-site rule.

**Owner, 2026-10-12 (second message):** yes, make it writable. Lane owed (the helper, the A/B); both done, below.

**Shipped 2026-10-13, the per-site rule.** `\.legibilityWeight` is settable,
`nil` by default. One helper, `LegibilityWeight?.applied(bold:faint:)`, steps a
weight a tier up under `.bold` — faint → plain, plain → bold, bold stays — and
every site that draws text uses it: `Text` (after a secondary scale's step down,
before redaction's dim), and each control that draws its own text rather than a
`Text` — a field's contents, prompt and caret cell (`TextField`, `SecureField`,
the vertical field, `TextEditor`), a button style's string label, a picker's
closed label, the stepper's and slider's read-outs, both date pickers, a tab's
title and badge, a navigation crumb, a list row's badge, a table's cells and its
reorder preview, the status bar's labels and help, a tooltip, a notification, a
spinner's label, the 256-colour grid's numbers. A site whose lines are all text
wraps them in `ANSIRenderer.applyPersistentBold` (with `AnimatedCellRun.drawnBold`
for frames the run loop paints itself); one that mixes text with chrome passes
the weight to the text's own run. Borders, caps, arrows, indicators, swatches,
images and rules are not text and are never stepped, which is why the per-site
rule was chosen over a rewrite of a subtree's buffer. A faint that means
something other than a weight (disabled, `.dimmed()`, `.invalidated`) is not
stepped. Tests: `LegibilityWeightTests`, `LegibilityWeightControlTests`,
`LegibilityWeightChromeTests`. Cost where no weight is set: one environment
read per `Text` and per control that draws its own text. The A/B ran at the landing (2026-10-13, the base before it against the commit, with the machine not
quiet, so indicative): neutral, the largest change controls +0.7% cold and several
scenarios 0.3 to 0.9% faster; the stripped binary grew 16,544 B.

**Asked 2026-10-12 (answered above, and shipped): confirm that it should become writable.** You asked
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

**Looked at 2026-10-19** (lane EFFECTS; `FaintLevelsAuditTests`, the ink read
back out of the emitted SGR over each shipped palette's page): at 16 colours,
on every palette, `.secondary` is `.primary`'s colour and `.tertiary` to
`.quinary` are the page's own — invisible. At 256 most levels stay apart, but
`.quinary` is the page on five palettes and `.quaternary` too on three, and
some neighbours share a colour. The rendered contrast floor does not reach
content text. Nothing changed: a vanishing level is your call,
[A-EFFECTS-1](<../../Historical/Shapes, effects and animation/Pixel effects: transforms, masks, drawingGroup, blend modes and meshes.md#a-effects-1-the-faint-content-levels-vanish-at-16-colours-and-the-faintest-at-256>).

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
- **`currentValueLabel:`:** SwiftUI says not every style shows it. TUI's
  slider draws a numeric read-out, so a label given here replaces it.
- **`sliderThumbVisibility(.hidden)`:** the knob's cell shows the fill's end.
  On the `.marker` track, which has no fill, nothing then shows the value.

**Fuller versions:** sub-cell edges at the neutral value for the fill styles
(the ramps only grow rightward, so a leftward edge needs mirrored glyphs most
fonts lack); and a measured look once a macOS 26 machine is available.

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
TUI-only activation rather than a reading of SwiftUI's.

## C. Declined without asking

### C10. `OutlineSubgroupChildren`

*`OutlineSubgroupChildren`*

The content type of the `DisclosureGroup` that is SwiftUI's
`OutlineGroup<…, Subgroup>` for views — a type only ever written inside
`OutlineGroup`'s full generic signature. TUI's `OutlineGroup` declares
the three generic parameters that carry information and drops the two that
are always the same (`Parent` is `Leaf`; `Subgroup` is that one
`DisclosureGroup`), as its documentation records, so there is no subgroup
type for this to be the content of. Every `OutlineGroup` initializer, for
views and for table rows, is SwiftUI's; only spelling the type out by hand
differs.
