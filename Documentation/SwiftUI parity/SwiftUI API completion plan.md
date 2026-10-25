# Completing the SwiftUI API: the plan

*Started 2026-10-03. This is the working plan for closing every SwiftUI API gap
that `Tools/APIParity` reports. It is updated as waves land. Owner decisions that
come up along the way do NOT live here: they are collected in
[`SwiftUI API completion decisions.md`](<Decisions/SwiftUI API completion decisions.md>)
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
of `SwiftUI compatibility guide.md`: source compatibility, and *anything TUIkit cannot
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
| 18 | done | — | Every lane integrated; 2,022 gaps → 404, each tracing to a decision or review item (checked by a sweep); the baseline re-recorded by hand (three task overloads only CI's SDK lists kept); full suite 9,640 tests, Stress self-check, Linux 6.3.3 static cross-compile and DocC `--strict` from a clean clone all clean on the final tree; the decisions document opens with a start-here index. **Not run** at the time: Wave 11b (line styles), which needed real-terminal measurement; it shipped since, read on four terminals 2026-10-18. **Owed:** the performance pass the owner planned, with the A/Bs each lane noted. |
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
   with the change reverted (mutation-checked). The SwiftUI compatibility guide's
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
| 03 | done | — | Read-only where macOS's own views honour a write TUIkit's cannot yet (`layoutDirection`; `legibilityWeight` too, until B2 made it settable); settable channels where macOS ignores writes too, all probed on a SwiftUI build. `undoManager` → decisions A1. |
| 04 | done | — | SwiftUI `ViewModifier` (TUIkit's buffer protocol is now `BufferModifier`), `ModifiedContent`, `EmptyModifier`, `EnvironmentalModifier`, `DynamicProperty`; button styles under SwiftUI's names + `PrimitiveButtonStyle`; toggle styles (`$isOn`, `Toggle(configuration)`, `.button`); `LabeledContentStyle`, `Label(configuration)`, `Form(configuration)`; built-in toggle/form/gauge style bodies draw their style; text field `.roundedBorder`/`.squareBorder`. `StyleChain` carries "the style outside" for every configuration initialiser. **Moved to their controls' waves**: list style variants → 08 (List's hug width ignores row padding — fix first); picker `.segmented`/`.palette`, menu `.button`, `.progressViewStyle`, disclosure-group, date-picker and text-editor styles → 06; table style → 08; navigation-split-view style bodies → 09. |
| 05 | done | — | Research brief (probes on a SwiftUI build), then: preference reduction from the first value; chained overlays keep their own identities; `geometryGroup`, `containerCornerOffset`, `flipsForRightToLeftLayoutDirection`, `scenePadding`; `LayoutProperties`, `LayoutSubviews.layoutDirection`; `CoordinateSpaceProtocol` (`.local`/`.global`); `transformPreference`, `overlay`/`backgroundPreferenceValue`, `background(alignment:content:)` (worklog Q4 reversed); `safeAreaInset`/`safeAreaBar` beside the view (B6); `containerBackground(for: .window)`; `containerRelativeFrame` (window, scroll view, list, tab, navigation stack, split-view column). By a worktree agent: `ContainerValues`, `Subview`/`Group(subviews:)`/`ForEach(subviews:)`, sections, guides decided on values and travelling through stacks and padding, `Layout.explicitAlignment`, `ViewSpacing` and `spacing: Int? = nil`, `GridRow` flattening, `GridLayout`, `gridCellUnsizedAxes` (B15–B21). **Owner:** anchors and named spaces (A2), `layoutDirectionBehavior` (A3); `containerShape` waits on the Shapes decision (O0); `safeAreaPadding` comes with 10. |
| 06 | done | — | `ColorPicker(selection:supportsOpacity:label:)`, `Stepper(…format:)`, `Slider` value labels, built-in button styles' `makeBody`, `RenameButton`, `HelpLink` (anchor forms declined, C5), `Gauge` marked-value labels, `Picker` `currentValueLabel:`, `Toggle(sources:)`, `Menu(configuration)` and `primaryAction:` (B11), `horizontalRadioGroupLayout`, timer `ProgressView`, `buttonRepeatBehavior` (B12), `HSplitView`/`VSplitView`, `.segmented`/`.palette` + `paletteSelectionEffect` (B13), `.menuStyle(.button)`, `DisclosureGroupStyle`, `TextEditorStyle`, `DatePickerStyle` (B14) with a `.graphical` calendar. Then `Picker(sources:)`, `ProgressViewStyle` (a bar's track is now `trackStyle(_:)`), `Button(role:action:)` with `.close`/`.confirm`. **Left:** `buttonSizing`, slider ticks/neutral value/thumb visibility, the `Transferable` clipboard family (`PasteButton`, `copyable`, `cuttable`, `pasteDestination`), `TextField(axis:)` and text selection; `badgeProminence` and `typeSelectEquivalent` → 08; `controlSize` is O14. **Then (agent, 6b):** `TextField`'s `axis:` initialisers (all five) and its `selection:` initialisers: a vertical field is a text field that wraps (`SoftWrapLayout`) and grows to its `lineLimit`, Option-Return or Ctrl-O for a newline (B62–B63); `lineLimit`'s three range forms, reversing their omission (B64); a field's selection is one range (B65). **Owner:** should `TextEditor` wrap too (A43). **Deferred:** Option-Return in a one-line field (macOS inserts a newline; TUIkit submits), `searchSelection` with A25 (shipped 2026-10-14), a macOS 26 measurement pass. **Since:** every **Left** item has shipped — `buttonSizing`, the slider's ticks, neutral value and thumb visibility, `PasteButton`/`copyable`/`cuttable`/`pasteDestination`, `TextField(axis:)` and its selection, `controlSize` (O14) — and A43's wrapping `TextEditor`; the macOS 26 newline-key pass is MACOS26-PASS (checked 2026-10-23). |
| 07 | done (agent) | — | 87 of 91 input symbols: SwiftUI's `onKeyPress` (TUIkit's focus-blind handler is now `onKeyEvent`), keyboard-shortcut members, move/exit/delete and copy/cut/paste commands, located taps, `onContinuousHover`, `onLongPressGesture`, drop destinations, `onDrag`/`onDrop`/`DropDelegate`, `itemProvider`; `CellPoint`. Open on A4 (kitty keyboard protocol: key-up phases, modifier-key changes) and A5 (live resize); `KeyEquivalent.clear` declined (C4). |
| 09 | done (agent) | — | 88 of 131: `@Namespace` (reversing its refusal), `@FocusState.Binding`, `@FocusedValue` (B34), focus scopes with `prefersDefaultFocus`/`resetFocus` (B35), the dialog modifiers (severity, icon, suppression toggle), termination prevention (B36), `dismissalConfirmationDialog` (B37), `searchFocused`, `searchScopes` (B38), search tokens (B39), the search toolbar behaviours, `presentationBackground` and the two interaction modifiers, `PresentationDetent` as a struct with `.custom`, `inspector` (B40), `navigationSubtitle`, `navigationTransition(.automatic)`, `navigationLinkIndicatorVisibility`, `NavigationSplitViewStyle.makeBody`. Declined: `@FocusedObject` (C9). **Owner:** resizable sheets (A19), `presentationSizing` (A20), compact adaptation (A21), and four that wait on earlier questions (A22–A25). |
| 08a | done (agent) | — | 170 of 191 `Table` symbols closed (169 implemented, 1 declined), and the 15 `TableStyle` symbols moved here from 04. `Table<Value>` keeps one generic parameter; SwiftUI's column surface (`TableColumn<RowValue, Sort, Content, Label>`, `TableColumnContent`/`Builder`/`ForEach`, any `SortComparator`, view cells), widths in cells, `TableColumnAlignment`, column customization (no gestures yet, B45), `.tableColumnHeaders`, `.alternatingRowBackgrounds`, the row surface (`TableRowContent`/`Builder`, `TableRow`, `ForEach` of rows, `ModifiedContent` of rows, `.selectionDisabled`, `.onHover`), hierarchical tables (`Table(_:children:)`, `OutlineGroup` rows, `DisclosureTableRow`), `TableStyle` (`.bordered`, `.inset`, custom). `Group`, `ForEach` and `OutlineGroup` now take unconstrained content and are views when it is one. **Owner:** the defaults (A29), context menus and `primaryAction` vs `onRowActivate` (A30), section rows (A31). Declined `OutlineSubgroupChildren` (C10). **Deferred:** row drag and drop (rows carrying a payload out, drops onto a row, `onInsert` on a `ForEach` of rows; a day and a half) and `IndexedIdentifierCollection`, both → 08b. |
| 08b | done (agent) | — | 135 of 146 symbols closed: 131 implemented, and `Tab`'s four `image:` initialisers declined with the asset-catalogue family (C11; that reason was wrong, and C11 now says so). SwiftUI's tab API: `TabContent` and its builder, `Tab` (symbols, roles, label views, promoted optional values), `TabSection`, `AnyTabContent`, `TabView(content:)`, the tab modifiers (badge, hidden, disabled, placement, section actions), `TabViewStyle` as a protocol with `.tabBarOnly`, `.grouped` and `.sidebarAdaptable` (a sidebar `List` beside the content, B76), `\.tabBarPlacement` and `\.isTabBarShowingSections` as measured, `TabViewCustomization` (B79). Lists: the `editActions:` initialisers and `IndexedIdentifierCollection`, `Section(isExpanded:)`, `.automatic`/`.bordered`/`.inset`/`.sidebar` styles with `ListItemTint`, `listRowInsets(_:_:)`, `contextMenu(menuItems:preview:)`, `sectionActions` (B78), badge and background prominence (B72, -2), `\.sidebarRowSize` (B74), the minimum row heights, type select (B77). Table row drag and drop from 8a (B80). Two list fixes on the way: a hugging list keeps a flexible height and draws a badged row whole. **Owner:** the default list style (A46, with A29), separators (A47), swipe actions (A48), per-tab interactions — the 6 `TabContent` members that surfaced (A49), tab search activation (A50, macOS 26), `sectionIndexLabel` (A51, with O8). |
| 10 | done (agent) | — | 54 of 123 closed, and 7 `ScrollPosition` label deviations fixed: `ScrollPosition`'s whole vocabulary (its readings keep the request until the user scrolls, B23), `contentMargins` (B24), `safeAreaPadding` (B25), `onScrollGeometryChange` (B26), `onScrollPhaseChange` (B27), `scrollIndicatorsFlash` and `scrollTargetLayout` return the view (B28, B29), the `Transaction` scroll members (B30), `scrollBounceBehavior` (B31). **Owner:** target behaviours, visibility, `ScrollAnchorRole.alignment`, `scrollContentBackground`, `scrollClipDisabled` (A6–A10); `scrollDismissesKeyboard` and the edge effects join O8 and O7 (A11, A12). Declined: `scrollInputBehavior` (C6); `ScrollView.showsIndicators` (C7) was declined too, and shipped on 2026-10-18 (lane PARITYMISC). **Deferred:** the `scrollTransition` family needs 12's `VisualEffect` and A7's visibility; `pinnedViews:` and `PinnedScrollableViews` go with the lazy-stack initialisers. **Then (agent, 10b):** `PinnedScrollableViews`, `LazyVStack(alignment:spacing:pinnedViews:content:)` and `LazyVGrid(columns:alignment:spacing:pinnedViews:content:)`: a pinned section's header and footer float as layers the nearest vertical scroll view draws at its edges, and a sectioned grid lays its sections out as SwiftUI's (B66–B71). **Owner:** pinning in `LazyHStack`/`LazyHGrid` (A44, after B16), and whether a plain `List` pins its headers (A45). |
| 11 | done | — | `textScale` (one intensity tier down), `Font.Design` with `.default`/`.monospaced` and `fontDesign`, `Font.system(_:design:weight:)`; sub-cell typography (`kerning`, `tracking`, `baselineOffset`, `lineHeight`, `fontWidth`), the OS text affordances and `TypesettingLanguage` (C8) declined. **Owner:** text selection (A13), string tables (A14), the writing-direction and alignment strategies (with A3), `customAttribute`/`textRenderer` (O16). **Then (agent, 11a):** live time text, 66 of 70: `Text(_:style:)` with `Text.DateStyle`, `Text(timerInterval:pauseTime:countsDown:showsHours:)`, their `LocalizedStringKey` interpolations, `SystemFormatStyle` (`Timer`, `Stopwatch`, `DateOffset`, `DateReference`) and its statics, `TimeDataSource` and `Text(_:format:)` over one, `TextVariantPreference` with `.fixed`; a live text draws at the frame's date and asks for one wake at its next change, and a plain `Text` pays one nil check (B48–B51). **Owner:** `.sizeDependent` (A32), `accessibilityName` (A33). **Deferred:** an attributed output's attributes (with P8), an Example page (needs a frozen clock in the PTY walk), a macOS 26 measurement pass. **Next (agent):** underline and strikethrough patterns and colours (`Text.LineStyle`), which need terminal measurements; attributed-text editing waits on P8's `Text(AttributedString)`. **Since:** `.sizeDependent` shipped (A32, a1e6484e3); `accessibilityName` was declined (A33, the parity map); an attributed output's attributes draw, the live form too (P8, B88); underline and strikethrough patterns and colours shipped with Wave 11b, read on real terminals 2026-10-18. Left: the macOS 26 pass (MACOS26-PASS) (checked 2026-10-23). |
| 12 | done (agent) | 95 | 91 of 116, plus `PlaceholderContentView`, `Never.Value` and `ViewModifier`'s `animation`/`transaction`: the `Transition` protocol and its built-ins (a custom transition's body is drawn at each frame's point between its phases, B52), custom `Transaction` values, `isContinuous`/`tracksVelocity`, animation completions, `transaction(_:body:)`/`animation(_:body:)`, `UnitCurve` and `timingCurve`, `Spring` and every spring spelling, `VisualEffect` with offset, opacity and the colour effects, `KeyframeTimeline`, `ContentTransition`, `AnyTransition.modifier(active:identity:)` (B52–B61). **Owner:** the blur transition (A34), symbol effects (A35), the default text dissolve (A40); `matchedGeometryEffect` with O4 (A36), `phaseAnimator` with O2 (A37), `shouldMerge`/`velocity` with O3 (A38), the geometric visual effects with Wave 16 (A39), `Transaction.dismissBehavior`, shipped with O9 (A22). **Deferred:** the scroll transitions have their `VisualEffect` now and wait on A7. |
| 13 | done | — | The named colours as `ShapeStyle` statics; `HierarchicalShapeStyle` (on the type and on `ShapeStyle`) and `HierarchicalShapeStyleModifier`, `foregroundStyle(_:_:)` and `(_:_:_:)` (B22, reversing the compatibility doc's refusal); the role styles `.foreground`, `.tint`, `.selection`, `.separator`, `.fill`, `.placeholder`, `.link`, `.windowBackground`; `Color(red:green:blue:opacity:)`, `(white:opacity:)` and `(hue:saturation:brightness:opacity:)` in all three colour spaces, `Color.Resolved` and `resolve(in:)` matched to SwiftUI's numbers, the Apple colour bridges; the symbol-mode and image-scale modifiers declined with their types. **Owner:** custom colour providers and HDR (A16), asset catalogues (A15), `preferredColorScheme` (A17); materials, `.bar`, `blendMode`, `shadow` and image paint stay with O5/W16 (materials shipped with O5, `ShadowStyle` with O6, `ShapeStyle.shadow` and `ImagePaint` with W1B, the `blendMode`s with W5); `Rectangle` and `background(_:in:)` with O0. **Then, on main:** `AsyncImage` and `AsyncImagePhase`; `Image`'s `interpolation`/`antialiased`, `renderingMode(.template)`, `resizable(capInsets:resizingMode:)` (B42); the `CGImage`/`NSImage` initialisers and `Image.Orientation` (B43); the bundle initialisers (A15's option 2); `Image`'s drawing closure, dynamic range and `Transferable` conformance declined in the map. `BackgroundProminence` goes with 08's list rows. |
| 14 | done | — | Scene `.environment(_:_:)`/`.environment(_:)`/`.transformEnvironment` reaching the content, app header and status bar; `OpenURLAction`'s `completion:` and `prefersInApp:` forms; the optional `@AppStorage`/`@SceneStorage` forms; `@AppStorage`'s `store: UserDefaults` forms and `View`/`Scene.defaultAppStorage(_:)` (decisions A18); `@ScaledMetric` (macOS does not scale it, measured); `SceneBuilder.buildExpression`; the platform-only remainder declined by reason (visionOS, WidgetKit, AppKit bridges, Handoff/URL delivery, iOS lifecycle, Core Data, StoreKit, window and menu-bar chrome, Combine). **Owner:** `sensoryFeedback` (O8), window toolbar styles (15). **Done with lane O9 (2026-10-18):** `Settings`/`SettingsLink`/`openSettings` (a sheet), several scenes in one body and optional scenes (`buildOptional`, `buildLimitedAvailability`), `Window`, `WindowGroup(id:/for:)`, `openWindow`/`dismissWindow`, `AlertScene`, per-window `@SceneStorage`, `windowDismissBehavior`, `WindowVisibilityToggle`, the scenes' `keyboardShortcut` (decisions file *Several scenes on one surface (O9)*; `UtilityWindow` declined there, C-O9-2). Since: `Scene.onChange(of:initial:_:)`, `task(id:name:executorPreference:…)`. The scene-level dialog modifiers (A26) shipped with O9. **Left:** nothing. **Since:** `defaultAppStorage` shipped (A18, 2026-10-13); the three `task` forms only a newer SDK declares — `task(name:priority:file:line:_:)`, `task(name:executorPreference:priority:file:line:action:)` and `task(id:name:priority:file:line:_:)` — shipped 2026-10-24, their signatures taken from Apple's documentation because this machine's newest SDK (macOS 26.2) lacks them; CI's macOS 26.4 SDK checks them. |
| 15 | done (agent) | — | Toolbars, decisions A28 (owner, 2026-10-04): the window's opt-in bars with `.toolbar`, `toolbarVisibility` and the window toolbar styles (lane D5C); the other bar modifiers (`toolbarBackground` ×2, `toolbarRole`, `toolbarItemHidden`, `toolbarTitleMenu`, `ToolbarLabelStyle` and `windowToolbarLabelStyle`, `contentToolbar`, `sharedBackgroundVisibility`), the `.keyboard` and `.accessoryBar(id:)` placements, the labelled `ToolbarItemGroup`, a `NavigationStack`'s bar hosting a pushed screen's items, sheets and covers hosting theirs at their edges, and the customisation family `toolbar(id:)` (lane TOOLBARS, decisions B-TOOLBARS-1 to 4). Declined: `toolbarTitleDisplayMode` (O8), `toolbarColorScheme` (A17), C-TOOLBARS-1/2. |
| 16 | basic shipped | — | `clipped(antialiased:)` (the cut `ScrollView`/`List` make, on any view) and `compositingGroup()` (a guarantee the compositor keeps); blur, `blendMode`, `luminanceToAlpha` and `backgroundExtensionEffect` join the map's per-pixel family. **Owner:** transforms, `mask`, `drawingGroup` (A27); `clipShape`/`contentShape` with O0. `shadow(color:radius:x:y:)` shipped with O6 (2026-10-18). |
| 17 | acting on it | — | `Refusals re-examined, wave 17 (2026-10-03).md`: 54 refusals wrong, 21 partly wrong, 23 to the owner (O0–O17). The truncated map reasons are whole again (X3). The implementable P items the waves left in the map: **done on main** P2 (`Font.resolve(in:)`, `Font.Resolved`, `Font.Context`), P9 (`AnimatableValues`; the `@Animatable` macros are A52), P10 (`Font.default`), P12 (`Label`/`ContentUnavailableView` `image:` names), P17 (the find bar, B81); **done by lane 17d** P11's `SpringLoadingBehavior` (B82) and P18's drag-session values (B83; the behaviour is A53); **done by lane 17t** P8 (`Text(AttributedString)`, the SwiftUI attribute scope and dynamic lookup, Markdown in `Text` keys and attributed formats; B84–B88, C13–C14); **done by lane 17g** P6 (the `Gesture` protocol, taps, spatial taps, long presses, drags, `@GestureState`, the three combinators, `AnyGesture`, the attaching modifiers with `GestureMask`, ranked as macOS ranks them; `onTapGesture` and `onLongPressGesture` are gestures now; B89–B94, C15, and `onDragGesture`'s future A54); **done by lane 17m** P11's `MeshGradient`, as a style and a view, with SwiftUI's Coons patches, smoothed colours and animation (B95); **done by lane O10** P16's file panels, by the owner's O10 ruling: `fileImporter`, `fileMover`, `fileExporter` and the `fileDialog` customizations as panels TUIkit draws, in the module TUIkitFilePanels, with `FileDocument` and the `Transferable` exporters on Apple platforms ([File panels (O10)](<Decisions/Presentation and windows/File panels (O10).md>)). The rest are owner items (O-numbers) or with their waves. |
