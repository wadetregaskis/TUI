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
| SwiftUI live public symbols (macOS) | 6,759 |
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
| 01 | not started | | |
