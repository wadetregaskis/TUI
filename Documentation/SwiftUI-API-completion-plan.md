# Completing the SwiftUI API: the plan

*Started 2026-10-03. This is the working plan for closing every SwiftUI API gap
that `Tools/APIParity` reports. It is updated as waves land. Owner decisions that
come up along the way do NOT live here: they are collected in
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md)
for review once the straightforward work is done.*

## Where we start

`Tools/APIParity/api_parity.py` on 2026-10-03 (local SDK 26.2, Swift 6.2.4):

| | |
|---|---|
| SwiftUI live public symbols (macOS) | 6,759 (6,767 once synthesized `Codable` members count) |
| TUIkit live public symbols | 4,317 |
| explained absences (`parity-map.json`) | 3,551 |
| **unexplained gaps** | **2,022** |
| argument-label deviations | 20 (60 more in `baseline.json` no longer reproduce) |

A gap is a symbol, not a feature: `DropOperation` is sixteen of them, and one
`Table` builder is fourteen. The 2,022 symbols come to roughly 250 families.

## How a gap gets closed

Every gap ends in exactly one of four places. These are the two rules at the top
of `SwiftUI-compatibility.md`: source compatibility, and *anything TUIkit cannot
honour must fail to compile*.

1. **Implemented.** The SwiftUI spelling compiles and means the same thing.
   Extra optional parameters, `Int` cells for `CGFloat` points, and added
   overloads are all fine.
2. **Implemented, basic form, with a note.** A safe reading ships, and the
   enhancement or the alternative reading is written up in the decisions doc
   under *Shipped the safe option*. Use this only where the basic form is
   honest on its own. It must not be a stub that drops part of the request.
3. **Declined, with a reason.** The symbol stays absent and gets a
   `parity-map.json` `notImplemented` entry or `families` rule saying what a
   character grid (or Linux, or a pty) cannot do. I do this myself when the
   reason is unarguable: a visionOS-only API, Core Data on a package that must
   build on Linux, Combine likewise, or Apple hardware a terminal never sees.
   Anything arguable goes to (4).
4. **Owner decision.** Written up in the decisions doc with priced options and a
   recommendation. Nothing ships until it is answered.

**The stated refusals get re-examined too.** The 2026-08 audits found every
refusal they examined to be wrong in the same way: a true fact about terminals,
offered as a reason the API should not exist when the API never depended on it.
Wave 17 goes back over the existing `notImplemented` entries and `families`
rules with that test. Any that look wrong go to the decisions doc. The rest are
confirmed.

## Order, and why

**Foundations before the things built on them.** Style protocols come before
controls that take styles. `Transition` comes before the built-in transition
structs. `Subview`/`ContainerValues` come before `ForEach(sections:)`.
`ScrollGeometry` comes before `onScrollGeometryChange`.

**Cheap and wide before narrow and deep.** The early waves close hundreds of
symbols with low risk. Every later wave then starts from the vocabulary it
needs.

**Value inside a tier.** Where nothing forces the order, the APIs ported
SwiftUI code reaches for most go first. Examples: `onKeyPress`, list and table
variants, styles, focused values, `Text(_:style:)`.

**Drawing changes are their own commits.** Anything that changes what reaches
the screen gets the Stress `--selfcheck` gate, so it must not be mixed into a
vocabulary commit.

| Wave | Area | Gaps | Expected outcome |
|---|---|---:|---|
| 01 | Spelling fixes: the capability exists under another label | 20 dev. | implement |
| 02 | Value types, conformances, small enums, builder arities | 103 | implement |
| 03 | Environment values the medium fixes (scale, contrast, size class…) | 30 | implement read-only; writes owner/basic |
| 04 | Core protocols (`DynamicProperty`, `ViewModifier` surface) + style infrastructure (every `*Style` protocol, configuration, built-in names) | 241 | implement |
| 05 | Composition & layout: `Subview`s, container values, `Layout` completeness, `GridLayout`, preferences/anchors, coordinate spaces, safe-area insets | 136 | mostly implement |
| 06 | Controls: `GroupBox`, `ControlGroup`, `Menu`/`Picker`/`Toggle`/`Slider`/`Stepper`/`Gauge`/`ProgressView`/`TextField` variants, `PasteButton`, `RenameButton`, `HelpLink`, split views | 160 | mostly implement |
| 07 | Input: `KeyPress` + `onKeyPress`, `KeyboardShortcut` members, move/exit/delete/copy/cut/paste commands, hover, long press, drop delegates | 91 | mostly implement |
| 08 | Collections: `Table` builders/rows/customisation, hierarchical tables, `List` edit actions & row styling, `Section(isExpanded:)`, the `Tab` API | 302 | mostly implement |
| 09 | Focus, presentation & search: `FocusedValue` family, focus scopes, presentation modifiers, inspector, dialog modifiers, `searchable` variants | 131 | mostly implement |
| 10 | Scrolling: `ScrollGeometry`, phases, visibility, target behaviours, `ScrollPosition` rest, content margins, pinned views, scroll transitions | 123 | mostly implement |
| 11 | Text, formatting & time: line styles, date/timer `Text`, `SystemFormatStyle`, interpolations, alignment strategies, selectability | 160 | mixed |
| 12 | Animation & transitions: `Transition` protocol + built-ins, `Animation` members, completions, `Transaction` members, `KeyframeTimeline`, `VisualEffect` | 116 | mostly implement |
| 13 | Colour, shape styles & images: `Color` inits/`Resolved`, `ShapeStyle` statics & hierarchical styles, `Image` options | 165 | mixed |
| 14 | Scenes, app & data: `Scene` modifiers, `Settings`, `ScaledMetric`, `AppStorage(store:)`; the Apple-platform-only remainder | 197 | mostly decline |
| 15 | Toolbars | 44 | owner decision (§2.6 of the compatibility doc made them a divergence) |
| 16 | Pixel effects: blur, shadow, rotation/scale/projection, blend modes, masks, clip shapes | 19 | owner decision; basic where honest |
| 17 | Re-examining the existing refusals (124 `notImplemented` entries, 28 `families`) | — | confirm or escalate |
| 18 | Finish: re-baseline, full gate sweep, decisions doc complete | — | — |

The symbol-to-wave mapping is mechanical (fnmatch patterns over the report),
and every one of the 2,022 symbols lands in exactly one wave.

## Per-item routine

1. **Read SwiftUI's own doc comment** for the symbol from the SDK symbol graph
   (offline, pinned to the SDK; the 2026-08 semantic audit's method). The name
   alone is not the spec.
2. **Search TUIkit for the capability first.** Many gaps are an existing feature
   under another spelling, or one parameter away from one.
3. **Implement, test, document in one commit.** A behavioural test must fail
   with the change reverted (mutation-checked). The SwiftUI-compatibility doc
   row is updated in the same commit.
4. **Pure refactors that make room go in a separate commit first.**

## Gates and cadence

- **Every commit:**
  - The debug build with Swift 6.2.4 has zero warnings.
  - The touched tests pass.
  - `swiftlint --strict` passes on the changed files.
- **Every ~10 commits, and at each wave's end:**
  - The full parallel suite.
  - The Linux static-SDK cross-compile, which catches type-check timeouts that
    macOS does not.
- **Drawing changes:** Stress `--selfcheck`.
- **At each wave's end, re-baseline by hand.**
  - Closed gaps are removed from `Tools/APIParity/baseline.json`, and any
    surfaced members are added.
  - `--accept` is never run locally, because the local SDK (26.2) is not CI's.
  - `--stale` checks the map entries.
- **Performance is measured only where it decides something:** a structural
  change to a hot path (`Text`, stack layout, `List`/`Table` rows, the
  environment). A full optimisation pass follows the whole batch.

## Progress

| Wave | Status | Gaps closed | Notes |
|---|---|---:|---|
| 01 | done | 1 dev. | Only `onHover(perform:)` was a pure relabel. `border(_:width:)` always compiled (a tool bug, fixed). The other 18 "deviations" are missing overloads and moved to their families' waves. |
| 02 | done | 93 | The parity tool now reads synthesized `Codable`/`RawRepresentable` members. Moved on: `ModifiedContent` → 04; `Never.Value`/`Optional.Value` (keyframes) → 12; `listRowSeparatorLeading/Trailing` → 08; `KeyEquivalent.clear` and `EventModifiers.capsLock` → 07 (they need the input parser). |
| 03 | done | — | Read-only where macOS's own views honour a write TUIkit's cannot yet (`layoutDirection`, `legibilityWeight`); settable channels where macOS ignores writes too, all probed on a SwiftUI build. `undoManager` → decisions A1. |
| 04 | done | — | SwiftUI `ViewModifier` (TUIkit's buffer protocol is now `BufferModifier`), `ModifiedContent`, `EmptyModifier`, `EnvironmentalModifier`, `DynamicProperty`; button styles under SwiftUI's names + `PrimitiveButtonStyle`; toggle styles (`$isOn`, `Toggle(configuration)`, `.button`); `LabeledContentStyle`, `Label(configuration)`, `Form(configuration)`; built-in toggle/form/gauge style bodies draw their style; text field `.roundedBorder`/`.squareBorder`. `StyleChain` carries "the style outside" for every configuration initialiser. **Moved to their controls' waves**: list style variants → 08 (List's hug width ignores row padding — fix first); picker `.segmented`/`.palette`, menu `.button`, `.progressViewStyle`, disclosure-group, date-picker and text-editor styles → 06; table style → 08; navigation-split-view style bodies → 09. |
| 05 | done | — | Research brief (probes on a SwiftUI build), then: preference reduction from the first value; chained overlays keep their own identities; `geometryGroup`, `containerCornerOffset`, `flipsForRightToLeftLayoutDirection`, `scenePadding`; `LayoutProperties`, `LayoutSubviews.layoutDirection`; `CoordinateSpaceProtocol` (`.local`/`.global`); `transformPreference`, `overlay`/`backgroundPreferenceValue`, `background(alignment:content:)` (worklog Q4 reversed); `safeAreaInset`/`safeAreaBar` beside the view (B6); `containerBackground(for: .window)`; `containerRelativeFrame` (window, scroll view, list, tab, navigation stack, split-view column). By a worktree agent: `ContainerValues`, `Subview`/`Group(subviews:)`/`ForEach(subviews:)`, sections, guides decided on values and travelling through stacks and padding, `Layout.explicitAlignment`, `ViewSpacing` and `spacing: Int? = nil`, `GridRow` flattening, `GridLayout`, `gridCellUnsizedAxes` (B15–B21). **Owner:** anchors and named spaces (A2), `layoutDirectionBehavior` (A3); `containerShape` waits on the Shapes decision (O0); `safeAreaPadding` comes with 10. |
| 06 | in progress | — | `ColorPicker(selection:supportsOpacity:label:)`, `Stepper(…format:)`, `Slider` value labels, built-in button styles' `makeBody`, `RenameButton`, `HelpLink` (anchor forms declined, C5), `Gauge` marked-value labels, `Picker` `currentValueLabel:`, `Toggle(sources:)`, `Menu(configuration)` and `primaryAction:` (B11), `horizontalRadioGroupLayout`, timer `ProgressView`, `buttonRepeatBehavior` (B12), `HSplitView`/`VSplitView`, `.segmented`/`.palette` + `paletteSelectionEffect` (B13), `.menuStyle(.button)`, `DisclosureGroupStyle`, `TextEditorStyle`, `DatePickerStyle` (B14) with a `.graphical` calendar. Then `Picker(sources:)`, `ProgressViewStyle` (a bar's track is now `trackStyle(_:)`), `Button(role:action:)` with `.close`/`.confirm`. **Left:** `buttonSizing`, slider ticks/neutral value/thumb visibility, the `Transferable` clipboard family (`PasteButton`, `copyable`, `cuttable`, `pasteDestination`), `TextField(axis:)` and text selection; `badgeProminence` and `typeSelectEquivalent` → 08; `controlSize` is O14. |
| 07 | done (agent) | — | 87 of 91 input symbols: SwiftUI's `onKeyPress` (TUIkit's focus-blind handler is now `onKeyEvent`), keyboard-shortcut members, move/exit/delete and copy/cut/paste commands, located taps, `onContinuousHover`, `onLongPressGesture`, drop destinations, `onDrag`/`onDrop`/`DropDelegate`, `itemProvider`; `CellPoint`. Open on A4 (kitty keyboard protocol: key-up phases, modifier-key changes) and A5 (live resize); `KeyEquivalent.clear` declined (C4). |
| 09 | done (agent) | — | 88 of 131: `@Namespace` (reversing its refusal), `@FocusState.Binding`, `@FocusedValue` (B34), focus scopes with `prefersDefaultFocus`/`resetFocus` (B35), the dialog modifiers (severity, icon, suppression toggle), termination prevention (B36), `dismissalConfirmationDialog` (B37), `searchFocused`, `searchScopes` (B38), search tokens (B39), the search toolbar behaviours, `presentationBackground` and the two interaction modifiers, `PresentationDetent` as a struct with `.custom`, `inspector` (B40), `navigationSubtitle`, `navigationTransition(.automatic)`, `navigationLinkIndicatorVisibility`, `NavigationSplitViewStyle.makeBody`. Declined: `@FocusedObject` (C9). **Owner:** resizable sheets (A19), `presentationSizing` (A20), compact adaptation (A21), and four that wait on earlier questions (A22–A25). |
| 10 | done (agent) | — | 54 of 123 closed, and 7 `ScrollPosition` label deviations fixed: `ScrollPosition`'s whole vocabulary (its readings keep the request until the user scrolls, B23), `contentMargins` (B24), `safeAreaPadding` (B25), `onScrollGeometryChange` (B26), `onScrollPhaseChange` (B27), `scrollIndicatorsFlash` and `scrollTargetLayout` return the view (B28, B29), the `Transaction` scroll members (B30), `scrollBounceBehavior` (B31). **Owner:** target behaviours, visibility, `ScrollAnchorRole.alignment`, `scrollContentBackground`, `scrollClipDisabled` (A6–A10); `scrollDismissesKeyboard` and the edge effects join O8 and O7 (A11, A12). Declined: `scrollInputBehavior`, `ScrollView.showsIndicators` (C6, C7). **Deferred:** the `scrollTransition` family needs 12's `VisualEffect` and A7's visibility; `pinnedViews:` and `PinnedScrollableViews` go with the lazy-stack initialisers. |
| 11 | in progress | — | `textScale` (one intensity tier down), `Font.Design` with `.default`/`.monospaced` and `fontDesign`, `Font.system(_:design:weight:)`; sub-cell typography (`kerning`, `tracking`, `baselineOffset`, `lineHeight`, `fontWidth`), the OS text affordances and `TypesettingLanguage` (C8) declined. **Owner:** text selection (A13), string tables (A14), the writing-direction and alignment strategies (with A3), `customAttribute`/`textRenderer` (O16). **Next (agents):** live time text (`SystemFormatStyle`, `TimeDataSource`, `Text(_:style:)`, `Text(timerInterval:…)`, the `LocalizedStringKey` interpolations, `TextVariantPreference`); underline and strikethrough patterns and colours (`Text.LineStyle`), which need terminal measurements; attributed-text editing waits on P8's `Text(AttributedString)`. |
| 13 | in progress | — | The named colours as `ShapeStyle` statics; `HierarchicalShapeStyle` (on the type and on `ShapeStyle`) and `HierarchicalShapeStyleModifier`, `foregroundStyle(_:_:)` and `(_:_:_:)` (B22, reversing the compatibility doc's refusal); the role styles `.foreground`, `.tint`, `.selection`, `.separator`, `.fill`, `.placeholder`, `.link`, `.windowBackground`; `Color(red:green:blue:opacity:)`, `(white:opacity:)` and `(hue:saturation:brightness:opacity:)` in all three colour spaces, `Color.Resolved` and `resolve(in:)` matched to SwiftUI's numbers, the Apple colour bridges; the symbol-mode and image-scale modifiers declined with their types. **Owner:** custom colour providers and HDR (A16), asset catalogues (A15), `preferredColorScheme` (A17); materials, `.bar`, `blendMode`, `shadow` and image paint stay with O5/W16; `Rectangle` and `background(_:in:)` with O0. **Next (agent):** `AsyncImage` and its phases, `Image`'s own `interpolation`/`antialiased`/`renderingMode`/`resizable(capInsets:resizingMode:)`, `Image.Orientation`. `BackgroundProminence` goes with 08's list rows. |
| 14 | in progress | — | Scene `.environment(_:_:)`/`.environment(_:)`/`.transformEnvironment` reaching the content, app header and status bar; `OpenURLAction`'s `completion:` and `prefersInApp:` forms; the optional `@AppStorage`/`@SceneStorage` forms; `@ScaledMetric` (macOS does not scale it, measured); `SceneBuilder.buildExpression`; the platform-only remainder declined by reason (visionOS, WidgetKit, AppKit bridges, Handoff/URL delivery, iOS lifecycle, Core Data, StoreKit, window and menu-bar chrome, Combine). **Owner:** `Settings`/`SettingsLink`/`openSettings` and optional scenes (O9), `sensoryFeedback` (O8), window toolbar styles (15). **Left:** `defaultAppStorage` (needs `@AppStorage` to resolve its store from the environment), `Scene.onChange(of:initial:_:)`, `task(id:name:executorPreference:…)`. |
| 17 | review done | — | `SwiftUI-API-completion-refusal-review.md`: 54 refusals wrong, 21 partly wrong, 23 to the owner (O0–O17). Acting on the wrong ones happens in each owning wave; stale and truncated map reasons still to fix. |
