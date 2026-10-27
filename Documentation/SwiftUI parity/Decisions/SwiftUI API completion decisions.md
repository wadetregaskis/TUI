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
`Shapes, effects and animation/Visual effects rulings (VISUALS).md`).

**Decided, waiting on a measurement.** A16's colour provider waits on an A/B on
the quiet machine. A40's default dissolve was measured on 2026-10-15 and, as
agreed, not shipped: it cost far more than 1% (see A40).

**Decided, lane owed.** A0's ruled O items but O1, O2, O7, O17 and O16 (deferred), and with them
A22 and A26 (O9) and A24 (O0, O15); A42, B19 (after its A/B). B22's look at
the faint tiers was taken on 2026-10-19 (lane EFFECTS): the faintest vanish at
16 and 256 colours, and what to do is A-EFFECTS-1, in
[Blend modes and image details (EFFECTS)](<Shapes, effects and animation/Blend modes and image details (EFFECTS).md>).
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
  ([Shapes (W1)](<Shapes, effects and animation/Shapes (W1).md>)).
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
  ([Matched geometry and the zoom transition (O4)](<Shapes, effects and animation/Matched geometry and the zoom transition (O4).md>));
  the zoom source's clip shape and shadow follow in lane W1B (B-O4-6).
- **O5** Materials and Glass (A41, now removed, listed the material symbols waiting on it).
  **(b) for both**; a cell-resolution blur is an optional add-on. Materials
  and glass shipped 2026-10-18 ([Glass (GLASS)](<Shapes, effects and animation/Glass (GLASS).md>)); the
  frost, the add-on, shipped 2026-10-24 (O5-FROSTED, [VISUALS](<Shapes, effects and animation/Visual effects rulings (VISUALS).md#o5-frosted-a-material-frosts-what-is-behind-it>)).
- **O6** `ShadowStyle`. **(b)**, radius and offsets in cells. `View.shadow(color:radius:x:y:)`
  and `ShadowStyle` shipped 2026-10-18; `ShapeStyle.shadow` waits on W1 ([Shadows (O6)](<Shapes, effects and animation/Shadows (O6).md>)).
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
  ([The menu bar (O13)](<Menus, toolbars and chrome/The menu bar (O13).md>)).
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

### A21. Compact-size-class adaptation and `preferredCompactColumn`

*`PresentationAdaptation` (`.automatic`, `.none`, `.popover`, `.sheet`,
`.fullScreenCover`), `View.presentationCompactAdaptation(_:)`,
`View.presentationCompactAdaptation(horizontal:vertical:)`,
`NavigationSplitView.init(preferredCompactColumn:…)` (all four)*

All of these say what to do in a compact size class: present a popover as a
sheet, show which split view column on top once the split collapses into one.
macOS is never compact, so on a Mac they are inert; TUI's size classes are
`.regular` unless an app sets them, and nothing TUI draws reads them (B3) —
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
TUI follows a compact class an app sets and changes no default, so when an
app writes `.compact` a popover must adapt and a split view must collapse;
shipping these inert would ignore the app's own setting. The defaults stay
regular, so nothing changes for an app that sets nothing. The work (about two
days, as priced above) goes with B3's lane.

**Shipped 2026-10-13: the popover half.** `PresentationAdaptation` and both
`presentationCompactAdaptation` modifiers ship, read from the popover's
content through the other presentation traits. In a compact class a popover
is a sheet (`.automatic`, `.sheet`), a full-screen cover (`.fullScreenCover`)
or stays a popover (`.none`, `.popover`). Where both classes are compact the
vertical class's adaptation wins, since a presentation is shortest of room
there; SwiftUI documents no order. The popover, sheet and cover presenters
are always all present around the presenting view, and the size class picks
whose binding is live, so a class written while the popover is up leaves the
presenting view's state alone. Not yet adapting: `TabContent.popover`, which
SwiftUI offers on iOS 18. TUITabs draws a tab's popover with Foundation's
`PopoverPresentationModifier` and does not depend on TUIPresentation, where
the sheet and the cover are; adapting it means that dependency, or an
environment hook the app installs. Left for a ruling: a tab's popover in a
compact class is an edge case, and the dependency is not free.

**Ruled 2026-10-23** (owner, A21-TABPOPOVER, option 1): TUITabs depends on
TUIPresentation, measuring first what that adds to an app that imports
only TUITabs. **Shipped 2026-10-24** (lane TABS): a tab's popover is shown
with `View.popover`'s adapting presenter (`_AdaptivePopover`, `package` for
it), so in a compact class it is a sheet, a cover or a popover still, as a
view's is; TUITabs re-exports TUIPresentation, and TUIPresentation
does not depend on it. **Its price,** measured 2026-10-24 (Xcode's Swift
6.2.4, release, default traits, `strip`): an app on `TUIApp` and
`TUITabs`, a tab with a popover, 8,731,120 → 8,997,600 B (+266,480 B,
+3.1%); the same app with a sheet of its own, which links TUIPresentation
already, 8,997,664 B before and after; an executable on `TUITabs` alone,
with no `App` (Tools/ProductSmoke's `UsesTUITabs`), 7,373,168 → 8,106,192
B (+733,024 B, +9.9%), TUIChrome coming with TUIPresentation there,
where `TUIApp` brings it to an app. The umbrella's apps pay nothing.

**Shipped 2026-10-13: the sheet's adaptation.** SwiftUI documents it: "In
vertically compact environments, such as iPhone in landscape orientation, a
sheet presentation automatically adapts to appear as a full-screen cover."
So in a vertically compact class a sheet is a cover (`.automatic`,
`.fullScreenCover`) or stays a sheet (`.none`, `.sheet`, and `.popover`,
there being no anchor for a sheet to become one at); in a horizontally
compact class alone it stays a sheet unless the content asks for a cover. A
sheet and a cover are one presenter whose style follows the class, so the
presented content keeps its state too, and `onDismiss` watches the app's
binding, so becoming a cover runs nothing. `modal(isPresented:)`, which
`sheet` forwards to, adapts with it.

**Shipped 2026-10-13: the split-view collapse.** In a compact horizontal
class a `NavigationSplitView` collapses into a stack: the column on top at
the full width, under a navigation stack's bar (the trail of the columns'
titles, or ‹ Back) when it is not the sidebar, with Escape and `\.dismiss`
going back a column. The four `preferredCompactColumn:` initializers ship;
without one the split keeps the column itself, starting at the sidebar, as
SwiftUI's documentation describes a collapsed split starting with its first
list. Choosing a row of a `List` with a selection — Return, Space or a
click — selects it and shows the next column, as tapping one does on
iPhone; the row stays selected, so coming back and choosing it again goes
forward again rather than clearing it. Column visibility, the handles, the
widths and the sidebar chords are set aside while collapsed, as SwiftUI
ignores visibility there. The columns behind the one on top render
off-screen, as a stack's root does, and keep their state; a column ahead of
it is not drawn. A `Table` chooses its rows the same way since the compact
`Table` (B3). A `NavigationLink` in the column on top pushes its destination
onto the collapsed stack, over that column (lane TOOLBARS, 2026-10-19); in a
regular class a split's links still push only within a `NavigationStack`
(decisions TOOLBARS, B-TOOLBARS-3).

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

**Shipped (2026-10-18, lane O9).** `DismissBehavior` with `.interactive` and
`.destructive`, and `Transaction.dismissBehavior` (a bit of the transaction's
flags, so no `Binding` grew). Under `.interactive`, the default, `dismissWindow`
leaves open a window showing a modal presentation — a sheet, a cover, an alert
or a confirmation dialog, which hold its keyboard; a popover or an open menu does
not count — whether it is the window in front or one held behind it; under
`.destructive` it closes it with them
([B-O9-4](<Presentation and windows/Several scenes on one surface (O9).md#b-o9-4-an-interactive-dismissal-leaves-a-window-with-a-modal-presentation-open>)).

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

### A26. The scene-level dialog modifiers and optional scenes wait on O9

*`Scene.dialogIcon(_:)`, `Scene.dialogSeverity(_:)`,
`Scene.dialogSuppressionToggle(_:isSuppressed:)` and `(isSuppressed:)`,
`SceneBuilder.buildOptional(_:)`, `SceneBuilder.buildLimitedAvailability(_:)`;
and with them O9's settings scene: `Settings`, `SettingsLink`,
`DefaultSettingsLinkLabel`, `OpenSettingsAction`, `\.openSettings`*

SwiftUI's examples apply the dialog modifiers to an `AlertScene`, and the two
builder methods exist for `if #available` around a scene among others. Both
need more than one scene, which TUI's `SceneBuilder` does not build: that is
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

**Shipped (2026-10-18, lane O9).** The four dialog modifiers on `Scene`, as
scene environment writes: on an `AlertScene` they are its alert's, and on a
window scene they reach the alerts its views present, as the view modifiers
written on their root would. `buildOptional` and `buildLimitedAvailability`
came with the variadic `buildBlock`, and `Settings`, `SettingsLink`,
`DefaultSettingsLinkLabel`, `OpenSettingsAction` and `\.openSettings` with
O9's settings scene, a sheet over the window in front
([B-O9-6](<Presentation and windows/Several scenes on one surface (O9).md#b-o9-6-settings-is-a-sheet-over-the-window-in-front>),
[B-O9-7](<Presentation and windows/Several scenes on one surface (O9).md#b-o9-7-an-alert-scene-is-presented-over-the-window-in-front-its-dialog-modifiers-its-own>)).

### A27. Pixel effects: transforms, masks and `drawingGroup` (Wave 16)

*`View.scaleEffect(_:anchor:)`, `View.scaleEffect(x:y:anchor:)`,
`View.rotationEffect(_:anchor:)`, `View.rotation3DEffect(_:axis:anchor:anchorZ:perspective:)`,
`View.projectionEffect(_:)`, `View.transformEffect(_:)`, `View.mask(alignment:_:)`,
`View.drawingGroup(opaque:colorMode:)`; and, waiting on refusal-review items
already, `View.clipShape(_:style:)` and `View.contentShape(_:eoFill:)`/`(_:_:eoFill:)`
(O0), `View.shadow(color:radius:x:y:)` (O6)*

Wave 16 shipped what a cell grid keeps honestly: `clipped(antialiased:)` (the
cut `ScrollView` and `List` already made) and `compositingGroup()` (a guarantee
the compositor keeps). `View.shadow(color:radius:x:y:)` followed with O6 (2026-10-18). Blur, luminance to alpha and the background
extension effect joined the map's per-pixel shading family; blend modes did too, until W5
shipped them per cell (2026-10-19). The rest is yours.

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
`colorMode: .linear` asks for linear-light blending, which TUI's encoded-sRGB
blend does not do.

1. **Ship it as `compositingGroup()`**, honouring `.nonLinear`, the default,
   and documenting `.linear` and `.extendedLinear` as blended non-linearly.
2. **Decline it.**

**Recommendation:** transforms (1); mask, the cell-coverage rule; drawingGroup
(1), since nearly every use is the argument-free performance hint.

**Ruled 2026-10-26: option 2.** The six transforms are declined (the API
parity map's family, with A39's spellings); `mask(alignment:_:)` ships at
cell coverage, a shape mask by `clipShape`'s half-cell rule; `drawingGroup`
ships as `compositingGroup()`, with linear-light blending inside it for
`.linear` and `.extendedLinear`.

**`mask` shipped 2026-10-26** (`MaskModifier.swift`), with one rule beyond
coverage: a glyph's alpha is its letter's shape, so where the mask draws a
glyph with no field over a cell the view only fills, the cell is the mask's
glyph inked in the view's colour. Without it `gradient.mask { Text(…) }`,
SwiftUI's gradient-text idiom, drew solid blocks where the letters are. Where
the view draws a glyph of its own it keeps it.

**`drawingGroup` shipped 2026-10-26** (`DrawingGroupModifier.swift`, with
`ColorRenderingMode`): the blends spent at a composite inside a linear group
mix in linear light, and what leaves the group unspent mixes where it lands,
as SwiftUI composites the group's image into the window (`Opacity as
composition.md` §113).

**You asked (2026-10-04)** whether linear and extended-linear blending could be
supported. Yes (answer of 2026-10-05): blending happens in one place, in
encoded sRGB by design today, and linear blending is decode, blend and
re-encode through lookup tables, which is cheap. Extended-linear is the same on
an SDR terminal, clamped at the end. Not yet decided.

*Wave 8a's remaining entries (C10; A30, A31 and B44–B47 shipped 2026-10-06, A29 on 2026-10-07): SwiftUI's behaviour was measured on macOS 15.8, built against the macOS 26.2 SDK, with an offscreen `NSHostingView`; the probes are in `Tools/SwiftUIProbes/Table questions, compile and runtime (wave 8a)/`.*

*Wave 11a's entries (A32–A33, B48–B51): every string was measured on SwiftUI, macOS 15, by rendering with `ImageRenderer` and reading the picture back with Vision; the probes are in `Tools/SwiftUIProbes/Live text formats read back (wave 11a)/`. A pass on macOS 26 is owed.*

*Wave 12's entries (A34–A40, B52–B61; its `Transaction.dismissBehavior` joined A22): SwiftUI's behaviour is from its doc comments unless an entry says it was measured; measurements are from probes built against the macOS 26.2 SDK and run on macOS 15, kept in [`Tools/SwiftUIProbes/Animation curves, springs and keyframes`](<../../../Tools/SwiftUIProbes/Animation curves, springs and keyframes>).*

### A39. The geometric visual effects wait on Wave 16 (A27)

*`VisualEffect.rotationEffect(_:anchor:)`,
`VisualEffect.rotation3DEffect(_:axis:anchor:anchorZ:perspective:)`,
`VisualEffect.scaleEffect(_:anchor:)`, `VisualEffect.scaleEffect(x:y:anchor:)`,
`VisualEffect.transformEffect(_:)`*

The `View` modifiers of the same names are Wave 16's (sub-cell geometry, an
owner decision: A27, declined on 2026-10-26, and these with them). The
visual-effect spellings are the same requests made from a geometry proxy, and
are answered with them; `VisualEffect` itself and the
effects with a cell reading are this wave's.

### A40. Should a content change dissolve by default under an animation?

*`EnvironmentValues.contentTransition`'s default; the drawing of `Text` (and
`Image`) when what it shows changes inside `withAnimation`*

SwiftUI's environment holds an unnamed default content transition (measured:
equal to none of `.identity`, `.opacity`, `.interpolate`), under which a
`Text` whose string changes inside an animation cross-fades. TUI's default
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

**Measured on 2026-10-15: kept instant, as agreed.** A prototype (session notes
`A40/`) kept each `Text`'s last drawing in state storage, at an identity of its
own, and dissolved from it when its glyphs changed under an animation (a change
of colour alone left to the colour's animation). It passed the suite and cost,
warm, with nothing animating: `fanout` +500%, `anyview` +100%, `modifiers`
+97%, `textwall` +69%, `scrollfollow` +53%, `dashboard` +40%, `menus` +13.5%;
`table` +0.2%. The price is the record every drawn text writes — a boxed value
in the tracked-value table, a live mark, and the pass's sweep over them — and
any design that dissolves from the last drawing has to keep that drawing
somewhere for every text, since nothing else keeps it. So a port that relies
on the default cross-fade still snaps until it writes `.contentTransition(.opacity)`.

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

### B4. `DynamicProperty.update()` writes back (superseded by lane DYNP)

The owner ruled this a bug to fix, carefully for performance (2026-10-05).
Lane DYNP made `update()` write back what it changes, as SwiftUI's does, at
no measured per-frame cost. What the write-back covers, and where TUI
still differs from SwiftUI, is in
[`DynamicProperty update write-back (DYNP).md`](<State and dynamic properties/DynamicProperty update write-back (DYNP).md>),
B-DYNP-1 onwards.

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
[A-EFFECTS-1](<Shapes, effects and animation/Blend modes and image details (EFFECTS).md#a-effects-1-the-faint-content-levels-vanish-at-16-colours-and-the-faintest-at-256>).

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

**How TUI had it.** A transition was a value — `AnyTransition`'s closed set
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

**Where TUI cannot follow SwiftUI, and why.**

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
  out its siblings on every frame. TUI's transitions have never moved
  their neighbours (see `AnyTransition`); this is the same rule applied to a
  custom body. (Since 2026-10-18 the neighbours glide with the change of
  layout itself, as SwiftUI's do — decisions FB16; a transition still never
  changes the size of the view it plays on.)
- **A body that changes its structure between phases does not animate the
  difference.** A value is interpolated only where both renders produced it
  at the same place; a modifier present at one phase and not the other is
  drawn as the `.identity` render has it. SwiftUI asks for the same
  ("Transitions should not use any identity-affecting changes like `.id`,
  `if`, and `switch`").

**The built-in transition types** (`OpacityTransition`, `MoveTransition`,
`OffsetTransition`, `ScaleTransition`, `SlideTransition`, `PushTransition`,
`IdentityTransition`, `AsymmetricTransition`) have real bodies, built from one
animatable modifier that applies TUI's own effect at the body's presence —
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

**Measured and put to you again (2026-10-19, lane TRANSITIONS2):** since
FB16 the neighbours of a collapsing transition glide with the change, which
closes its gap as SwiftUI's does in every container that glides (measured,
`Tools/SwiftUIProbes/Transitions/tr1.out` T7); the container is already laid
out again on every frame a transition is on screen. What is left, and its
price, is decisions
[A-TRANSITIONS2-1](<Shapes, effects and animation/Transition follow-ups (TRANSITIONS2).md#a-transitions2-1-b52-a-custom-transition-that-changes-its-views-size--lay-the-body-out-at-each-frames-size>).

### B54. A scale transition uncovers from its anchor, and a scale above 1 draws the view whole

*`ScaleTransition` (`init(_:anchor:)`, `scale`, `anchor`),
`Transition.scale`, `Transition.scale(_:anchor:)`,
`AnyTransition.scale(scale:anchor:)`*

TUI's `.scale` already reveals the view from its anchor a whole cell at a
time, there being no sub-cell rendering to shrink. The scale factor is now
where that reveal starts: `.scale(0.5)` shows half the view at once and
uncovers the rest. `.scale` itself is `ScaleTransition(1e-5)`, SwiftUI's own
value (measured) — nothing, in whole cells.

A factor above 1 asks for the view to start larger than its slot. A cell grid
cannot draw that: the reveal is clamped at the whole view, so the transition
draws the view whole from the first frame. `opacity` above 1 is clamped the
same way in SwiftUI itself.

TUI's own spelling, `AnyTransition.scale(anchor:)`, was not SwiftUI's and is
gone; `scale(scale: 0, anchor:)` is the same transition.

**The fuller version** would draw an oversized start by cropping the view to
its middle and widening the crop as it settles — a zoom-out rather than a
grow. Nothing in TUI crops from the middle today; half a day, and I would
wait for someone to ask.

### B55. `tracksVelocity` is recorded and read by nothing; `isContinuous` is set by TUI's own continuous controls

**Since 2026-10-18** a retarget hands the velocity on (O3's merging, with A38): a merging
spring starts the next at the speed the value was moving. What follows is the entry as written
before that, when no velocity was carried; `tracksVelocity` is still recorded and read by nothing.

*`Transaction.tracksVelocity`, `Transaction.isContinuous`*

**`tracksVelocity`.** SwiftUI accumulates the velocity of values changed under
such a transaction, so a later animation can start moving at that speed.
TUI's animations are closed-form functions of elapsed time that start at
rest — a spring retargeted mid-flight already restarts from where its picture
is, without its speed — so there is nothing to track, and the flag is a value
the transaction carries for whoever reads it. This is the one place the
"retargets at rest" deviation of every TUI spring shows up as a property;
the Wave 17 review (W6) asked for it to be documented in one place rather than
used to refuse spellings, and B58 (the spring animations) points here
too.

**`isContinuous`.** SwiftUI sets it when "a continuous action created the
transaction" — dragging a slider, holding a stepper. TUI now sets it on the
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

Two transactions in one frame render under the last one (the rule TUI
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
rather than the limit the curve approaches (1.72 for both). TUI answers
the same, by the same arithmetic: a keyframe track carries a linear
keyframe's end velocity into the cubic keyframe after it, and the two
frameworks' tracks agree only if these do.

A circular curve is a new case of the animation curve, so
`Animation.timingCurve(.circularEaseIn, duration:)` moves along the circle;
a Bézier or `.linear` builds the animation `timingCurve(_:_:_:_:duration:)` and
`linear(duration:)` already build, and compares equal to it.

### B58. `Spring` is SwiftUI's numbers, two quirks kept and one not

**Since 2026-10-18** a spring keeps its velocity across a retarget: the fuller version below
shipped with O3's merging (and A38). The rest of the entry stands.

*`Spring` (its four initialisers, `duration`, `bounce`, `response`,
`dampingRatio`, `mass`, `stiffness`, `damping`, `settlingDuration`, `value`,
`velocity`, `force`, `update`, `settlingDuration(…)`, `.smooth`/`.snappy`/
`.bouncy` and their tunable forms), `Animation.spring(_:blendDuration:)`,
`spring(duration:bounce:blendDuration:)`, `spring(response:dampingFraction:blendDuration:)`,
`interactiveSpring` (all three), `interpolatingSpring` (all four)*

The Wave 17 review (W6) found the refusal of all of these to be a judgement,
not a limit: TUI already drew springs in closed form. `Spring` is that
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
more than the derivative of its own `value(…)` (1 at rest at t = 0). TUI
answers the derivative.

**Bounce at or below −1** is NaN in SwiftUI; here it stops at −0.999, a spring
too sluggish to visibly arrive, rather than a NaN on its way to a cell.

**Retargeting.** SwiftUI's `spring` hands its velocity to the next spring on
the same value, blending the durations over `blendDuration`; its
`interpolatingSpring` adds overlapping animations so velocity is preserved.
TUI's animations are functions of elapsed time from a start at rest: a
change that retargets a running spring starts the new one from where the
picture is, without the speed it had. So `blendDuration` has nothing to blend,
and `interpolatingSpring`'s `initialVelocity` is honoured for the change it
is given to — it moves the start of the curve and lengthens the settling the
loop waits for — but not inherited by the next. This is the deviation every
TUI spring already had (B55 records `tracksVelocity` against it); the
`interactiveSpring` presets are, accordingly, the quick springs their numbers
describe.

**The fuller version** is velocity-preserving retargeting: store the
velocity at retarget and start the next closed form with it
(`SpringMotion` already takes one). For springs alone that is a day — the
store records where the picture is; it would also record how fast — but a
curve retargeting into a spring, or a spring into a curve, has no velocity
model, which is O3's question.

### B60. Keyframe timelines follow SwiftUI's curves, measured

The animator views this entry left with O2 shipped with it on 2026-10-14.

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
  initialiser and samplers are, because TUI's `Animatable` is (its values
  are read and written through `animatableData`). SwiftUI's are
  nonisolated. Code that builds a timeline in a view, a body or a `.task`
  compiles unchanged; one built off the main actor does not.
- **A time before the start is the start.** SwiftUI clamps its linear and
  cubic segments there, but evaluates a spring backwards (−58.5 at −0.5 s for
  a bouncy spring to 1).
- **A zero-length linear or cubic keyframe arrives at once**, where SwiftUI
  divides by its zero length and answers NaN.

### B61. A content transition dissolves each text and image

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
once. A change in mid-dissolve dissolves from the last drawing, so a burst
of changes is followed one change behind. The dissolve counts as an
animation for completions.

**Per leaf, as SwiftUI's** (owner ruling of 2026-10-23, option 2; lane
VISUALS, 2026-10-24). Each `Text` and each raster `Image` reads the value as
it draws and dissolves its own change; a symbol image is a `Text` and
dissolves there. So an inner `.contentTransition(.identity)` exempts its
part, and `.environment(\.contentTransition, …)` works as the modifier does.
The modifier only sets the environment value. What is not a text or an
image (a shape, a colour, a control's chrome) changes as it would without
the modifier, an animatable one animating, as in SwiftUI. Until then the
modifier dissolved its whole subtree's drawing, and an inner `.identity`
exempted nothing (deviations A4 as it was).

The price is A40's, confined: a leaf keeps its last drawing only where a
transition that dissolves is in force, in a record at an identity of its
own (`ContentDissolve`, TUIFoundation); everywhere else each `Text` and
raster `Image` pays one environment read a draw (a `Bool`,
`contentDissolves`, written by `\.contentTransition`'s setter, since the
leaves cannot see `ContentTransition`'s module). The ruling lands it if the
A/B on text-heavy scenarios is within a few percent; see the lane file
`Shapes, effects and animation/Visual effects rulings (VISUALS).md`.

**Where it still differs.** The leaf dissolves where SwiftUI interpolates
glyph shapes or rolls digits, and takes its new size at once (a shrinking
drawing loses its edges immediately). `contentTransitionAddsDrawingGroup` is
a rendering hint with no visible contract (a drawing group changes how
SwiftUI composites, not what it shows) and is kept for whoever reads it. The
symbol-effect content transitions shipped with A35 on 2026-10-05 (on macOS:
a fade of the symbol).

**A40's default dissolve** (every text, with nothing written) stays off: it
is this record kept for every text everywhere, measured at up to +500%.

### B95. A mesh is one sample a cell on a glyph terminal, and a picture where the terminal takes one

*`MeshGradient` (its five initialisers, `width`, `height`, `locations`,
`colors`, `background`, `smoothsColors`, `colorSpace`, `resolve(in:)`, `Body`,
`Resolved`), `MeshGradient.BezierPoint` (its initialiser and five points),
`MeshGradient.Locations` (`.points`, `.bezierPoints`),
`MeshGradient.Colors` (`.colors`, `.resolvedColors`); `Paint.mesh` and
`MeshPaint`, TUI's own*

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

- **One sample a cell, or two.** A cell is the mesh at its centre, so a smooth
  mesh is a staircase on a glyph terminal; the picture path removes the
  staircase where the terminal draws pictures. Since 2026-10-24 (the fuller
  version below) a blank cell is two samples where the terminal's Block
  Elements fill the line. This is the same rule every gradient follows.
- **Exact evaluation, not SwiftUI's tessellation.** TUI evaluates the
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

**Two samples a cell where Block Elements fill the line** (owner ruling of
2026-10-23, option 2; lane VISUALS, 2026-10-24). A ramp or mesh that changes
down a column draws each blank cell it fills by the rasterized shapes' rule
(`ShapeHalfBlocks.cell(upper:lower:)`): `▄` in the colour a quarter of the
way up from the cell's bottom over the colour a quarter of the way down from
its top, or a space where the two agree. That is a gradient view, a
`.background(gradient)` behind the content's bare cells (a space with nothing
in force), and a rectangle-family shape's whole cells (its corners keep their
quadrant in one sample), so a gradient `Rectangle`, `RoundedRectangle` and
`Circle` agree. Apple Terminal (`blockElementsFillTheLine` false) keeps one
sample, as do a cell with a glyph, a translucent or blended ramp, a
horizontal ramp (whose halves agree) and a terminal with no colour; a
terminal that takes pictures still draws an opaque ramp behind blank cells
as one. Copying such a region gives `▄` rather than spaces. The `▀`/`▌`
choice, quadrants and diagonals were not built (the ruling's follow-up
answer). Where a layer is drawn under content — `.background { gradient }`,
a `ZStack` — a cell the content draws, a space included, covers the `▄` and
shows the top half's colour. See the lane file `Shapes, effects and
animation/Visual effects rulings (VISUALS).md`.

## C. Declined without asking

### C1. `CGPoint`, `CGSize` and `CGRect` as `Animatable`

*`CGPoint.AnimatableData`, `CGSize.AnimatableData`, `CGRect.AnimatableData`*

This is a compiler wall, not a judgement. On Apple platforms, SwiftUICore's
own extensions of the CoreGraphics types are visible to any module that
imports Foundation, through a cross-import overlay. That is the same overlay
`Collection+Offsets.swift` already works around. SwiftUICore's
`AnimatableData` typealias on each type is found before any witness TUI
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

### C5. `HelpLink(anchor:)` and `HelpLink(anchor:book:)`

*`HelpLink.init(anchor:)`, `HelpLink.init(anchor:book:)`*

Both open an anchor in an Apple Help book, through AppKit's `NSHelpManager`
and the Help Viewer. A terminal app has no help viewer to open, and Linux and
Windows have no help books. `HelpLink(action:)` and `HelpLink(destination:)`
ship, so a help button that runs code or opens a URL ports as written.

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
