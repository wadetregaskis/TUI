# The module split

*How TUI's single 230,000-line module became an umbrella over modules that
compile in parallel and that apps can take à la carte: the analysis that
called for it, the plan, each step as it landed, and what it delivered. The
plan (revision 4) and every step's own record follow, in order, with the two
investigations of what the split cost and delivered.*

## In short

On 2026-10-07 an analysis of clean release builds found most of the gap was
the toolchain (swiftly's assertions build; Xcode's 6.2.4 is 26–42% faster),
and the one large package-side lever was splitting the module. The plan's
revision 4 cut it into a base module (TUIFoundation), tiers and leaves, as
landable steps A1 to A3 (preparation), B1 to B7 (carving) and C1 to C8
(peeling), each A/B'd with its neighbour. It landed by 2026-10-11, with the
run-time costs it introduced won back in follow-up lanes (in
[Winning back the module split's cost](<Winning back the module split's cost.md>)),
and per-module products (in [Per-module products](<Per-module products.md>)).
On 2026-10-25 the package and every module were renamed from TUIkit to TUI.

## How it unfolded

1. **2026-10-07, the owner** took the plan with decisions D1 (the base module
   named TUIFoundation), D4 (every app carries the split's export table during
   the battle-test), D2 and D3 deferred, products option (b) (only the
   umbrella advertised until battle-tested), and CLAUDE.md's POSIX rule
   relaxed for Windows.
2. **2026-10-08 to 09, the owner:** optimise compile time and bytes for Swift
   6.4 first, with no major regression on 6.2 and 6.3; stack the split's lanes
   and A/B each pair.
3. **The steps** landed in the order below, each recording its own calls.
4. **2026-10-10 and 11, investigations** measured the split's run-time cost step
   by step and what it delivered in build time, size and tests (appended).

## For a future reader

- **D2 and D3** were deferred "until after Phase C and the battle-test"; look
  for them when the battle-test is done.
- **The module map's rules** are `Tools/ModuleMap/rules.json`; the gate checks
  them.

## The plan, revision 4 (2026-10-07)

> **What this is.** The design for splitting TUI's single 230k-line module into an umbrella over twenty modules
> that compile in parallel and that apps can later depend on à la carte: the module map, every cut out of the base
> module with its seam and price, the migration as landable steps, and the decisions. Revision 4 (2026-10-07), after
> three designers, two judges, a synthesis and a skeptic who re-ran every check against the code. Earlier revisions
> and the trial split's measurements stay in the working notes.
>
> **Decided since this was written (owner, 2026-10-07):**
> - **D1:** the names stand, except that the base module is **TUIFoundation**, not TUIBase (this text keeps
>   the name it was written with). Committed to `Tools/ModuleMap/rules.json`.
> - **D4:** accepted: under products option (b) every app carries the split's export table during the battle-test.
> - **D2, D3:** deferred until after Phase C and the battle-test, as recommended.
> - **Products:** option (b), only the umbrella product is advertised until the structure has been battle-tested.
> - **Windows:** CLAUDE.md's POSIX rule was relaxed: POSIX-only code may live in any module, isolated, never in one
>   that builds on Windows today.
>
> **Paths.** Evidence is cited by paths relative to the maintainers' working notes (`split2/…`, `refine/…`,
> `challenge/…`, `reindex/…`); those files are not in this repository. The map itself is `Tools/ModuleMap/`.

Revision 3 (the refine round's synthesis of the slimbase, layers and leaves designs and the judge-owner and judge-risk
judgements) with the skeptic's corrections (`split2/refine/challenge/`) applied, 2026-10-07. Revision 3 is kept as
`plan-refined.r3.md`; plan revision 2 (`split2/plan.md`) is kept as is. Sources at main be7aba9df, whose
`Sources/TUI` equals 59e04b011's (diffed).

**Evidence tags**
- **measured**: counts, line totals, findings, crossing sites and widening, all from the index and `Tools/ModuleMap`.
- **est.**: times and sizes, from plan §2's model (job = −0.334 + 1.324 × (SIL + type-check s), fitted on M3's
  quiet-box re-time), run through judge-owner's `jlib.py`, which reproduces step 0c to the decimal.
- **model / conservative**: the **model** charges each moved file its full per-file SIL time; **conservative** leaves
  in Base the SIL that WMO spent on stdlib specialisations it happened to emit in a moved file. The truth lies
  between. The gap is almost all two files: `FrameBuffer+Overlays` (1,033 of its 1,074 ms of SIL is stdlib
  specialisation) and `LocalizationService` (1,131 of 1,208 ms).
- **Nothing was built split and nothing was benchmarked.** Today's 77.8 s (quiet box) and M3's 64.8 s (a real
  6-module split) are the only measured build times here.

**What revision 4 corrects** (the skeptic re-ran every check and recomputed the headline numbers; all reproduced)
1. **S1 was not a pure split.** The `imageCellAspect` setter calls `ASCIIConverter.sanitizedCellAspect`
   (`Views/Image.swift:509`), which is in TUIImage. S1 now also moves that rule (`sanitizedCellAspect`,
   `cellAspectRange`) down into TUIStyling as `package` API, with `ASCIIConverter`'s public members forwarding to
   it, so there is still one copy of the rule. Base drops TUIImage only once that lands.
2. **A Linux-only call the index never saw would break B2 on every Linux lane.** `UserDefaultsStorage.swift:246`
   (Base, `#elseif os(Linux)`) calls the internal `sanitizedProcessName`, which moves to Strings. B2 widens it to
   `package`. Every carve now runs the inactive-arm scan and a Linux cross-compile before landing.
3. **Four public members moved off-topic, hidden inside lifted extension blocks.** `.focusSection(_:)` went to
   Chrome; `.aspectRatio(_:contentMode:)`, `.scaledToFit()` and `.scaledToFill()` went to Bitmaps. They stay in Base
   now: S1 grows to cover the layout trio, and a new S2 splits `.focusSection` out. The r4 rules pin what they use
   (measured: Base +232 lines, +0.04 s of job). `public-above` will list each public member, not just a block's first.
4. **Some new crossings are per row.** These are FrameDiffWriter's terminal-quirk reads, the colour effects,
   `.scrollTransition` and open menus. The "≤ ~0.3%" judgement is withdrawn. Stress's A/B never runs FrameDiffWriter,
   so B2 and B3 add an emission bench. Stress has no colour-effect scenario, so one is added before B5b. Step 0a stays
   binding for B5b.
5. **Bookkeeping.** S1 is 5 edges / 12 references and R2 4 / 11 (measured, r4 rules). R1's public-above entry lands
   in R1's own commit, because a pre-accepted entry would trip the `rules` check.
6. **DequeModule** is App's dependency, not Base's; B3 adds it.
7. **Text.** `ToolbarPlacement` goes to Chrome (only `ToolbarItemPlacement` stays). `LocalizationService.string(for:)`
   leaves set L, because `@inlinable` cannot reach its private lock and tables.
8. **A5** adds `Tools/verify-versioned-consumer.sh` to its path list.

Price of the corrections: about +0.75 agent-day, no extra quiet-box A/B (two emission benches ride along with B2 and
B3), and no change to any build-time figure at one decimal.

**What revision 3 changed over plan revision 2** (still true)
- **The owner's answers.** TUIBase stays; TUIControls is dissolved. Small modules are kept only where they never
  lengthen an import list. Base is as slim as is worth doing. Under products (b), only the umbrella is advertised;
  per-module products wait for the battle-test.
- **Base: 127,418 → 108,068 lines (54.8% → 46.5%, −19.4k)**, measured on the r4 rules. A4's two block splits put about
  0.15k more back (by hand: ≈108.2k). Its job is 39.6 → 30.2 s on the model, 33.6 s conservative (est.). That is seven
  moves out of Base and one back in (§2); four need code changes (R1, R2, S1, S2).
- **Full clean build (est.):** 61.9 → **52.5 s**, 55.9 s conservative; today 77.8 s (measured). Under (b) every app
  pays exactly this build. The coarse stage drops from 66.8 to 57.4 s (60.8 conservative).
- **20 modules plus the umbrella** (plan: 15 plus the umbrella). New: TUITerminalHost (side lane), TUIChrome,
  TUIEffects, TUIBitmaps, TUIMenus, TUINumericControls. Gone: TUIControls.
- **Refactors.** New: R1, R2, S1, S2. K3 is dropped (ViewRenderer moves to App with `renderOnce`). K1 gains one slot.
- **The tool** gains a `lower` check (a side module cannot silently start using TUIView) and per-member public-API
  reporting.
- **Set L** folds into A3, because several of its callees now first cross at B2 and B4.
- **New carves:** B5b (Chrome, Effects, Menus, after the Navigation group, because Presentation uses Chrome) and B5c
  (Bitmaps, after R2 and S1).
- **Cost:** 17 quiet-box A/Bs (+2) and about 18–22 agent-days of remaining work, about +4.25 d over the plan's
  remainder (0b, 0c and A1 have landed).

### 0. The answer in one screen

```
 TUICore ──┬────────────────────────► TUIView ──┐   lower four, unchanged (Windows-binding)
 TUIStyling┴─► TUIImage ─────────────────────────┼──────────────► only Bitmaps and ColorPicker use it now
 side lane (compiles beside View; never imported; Base re-exports it):
   TUIStrings       SF table, Markdown, format styles + localization and the resources   needs Core
   TUITerminalHost  terminal facts as values (host, identity, quirks, capabilities)       needs Core
                                                       ▼
                                                  TUIBase  46.5% (was 54.8%)
                                                       │
   leaves over Base (extra edges in brackets)
   TUIApp [Chrome]  (POSIX run loop, Scene)   TUIChrome   TUIEffects   TUIBitmaps   TUIMenus
   TUINumericControls   TUITextInput   TUIPickers   TUIForms   TUIGrid   TUINavigation
   TUIPresentation [Chrome]   TUILists   TUITables [Lists]   TUITabs [Lists]
   TUISearch [TextInput, Pickers]   TUIColorPicker [NumericControls, TextInput, Pickers, Tabs, Presentation]
 TUI = umbrella: @_exported import of everything, no code. `import TUI` and its API are unchanged.
```

| | Today | Plan rev 2 | **Refined (r4)** | Option D-m: + menu engine |
|---|---|---|---|---|
| Base lines (% of TUI) | 230,756 in one module | 127,418 (54.8%) | **108,068 (46.5%)**, ≈108.2k after A4 | 105,705 (45.4%) |
| Base job, Xcode (est.) | — | 39.6 s | **30.2 s (cons. 33.6)** | 29.2 (32.7) |
| Full clean build, Xcode: every app under (b) | **77.8 s measured** | 61.9 s | **52.5 s (cons. 55.9)** | 51.5 (55.0) |
| Same, swiftly 6.2.4 | ≈ 110 s (model) | 89.8 s | **77.6 s (cons. 82.0)** | 76.3 (80.8) |
| End of Phase B (coarse stage), Xcode | — | 66.8 s | **57.4 s (cons. 60.8)** | — |
| Stripped binary, every app under (b) | **11.15 MB measured** | 11.59 MB | **11.66 MB** | 11.66 MB |
| À la carte later: hello world | — | 7.90 MB, 65.3% of lines | **7.56 MB, 62.0%** (≈ 7.3 MB without TUIImage, once S1's sanitiser move lands) | 7.45 MB, 61.0% |
| `Tools/ModuleMap check` (measured) | — | 0 new (28) | **0 new (40; 45 with `lower`)** | 0 new (50; 55) |
| Files split across modules (measured) | — | 80 | **93**, plus two extension blocks split (S1, S2) | 93 |
| Widened to `package`, member level (measured) | — | 2,055 | **2,367** | 2,392 |
| Quiet-box A/Bs | — | 15 | **17**, plus emission benches at B2 and B3 | 18 |

- **Products.** Under (b), every app builds and links everything until per-module products ship, so today the split's
  value is the clean-build time: −25 s (−32%) on the model, −22 s conservative (est.). The cost is +0.51 MB of export
  trie in every binary (§7, D4).
- **Runtime.** Most new crossings are per frame, per string, per image, per transition step or cold. Four are **per
  row** (§5), and one of those calls a closure per colour code, which in a gradient is every cell:
  - FrameDiffWriter's quirk reads and compensation (per emitted row);
  - the colour effects' SGR rewrite (per line, with that per-colour-code closure call);
  - `.scrollTransition` (per row per frame);
  - the rows of an open menu (per frame while it is open).

  Each costs a call, not lost work, but there is **no estimate** until step 0a attributes M3's unexplained app-shapes
  cold +2.3%. The gates are each carve's A/B (+1.5% stop, +3% budget), emission benches at B2 and B3, and a
  colour-effects scenario at B5b.

### 1. The module map

Lines are at 59e04b011, 232,653 in all, measured on the r4 rules. Jobs and end times are est. on the model, for Xcode /
swiftly; Base's conservative figures are in brackets. The `lower` column gives the lower modules each module may use, as
the new check enforces; "all" means all four.

| Module | Contents | Lines (%) | Decls / files | Job | Ends | Depends on | `lower` |
|---|---|---|---|---|---|---|---|
| **TUIStrings** (side) | The SF Symbols name table, the inline-Markdown parser, the format styles; **plus localization**: `LocalizationService` and its extensions, `BundleStringTables`, `LocalizationKey`, `ModuleResource` (so it holds the resources), `StorageDiagnostics`/`StorageFailure`, `appConfigDirectory()`, `sanitizedProcessName` (`package` from B2) | 14,687 (6.3%) | 45 / 26 | 3.7 s | 13.2 / 23.3 s | — | Core (`Lock`) |
| **TUITerminalHost** (side, new) | Terminal facts as values: `TerminalHost` (cases, quirks), `TerminalIdentity` with `startupIdentity`, `TerminalClient` and its capability queries, `ClientCapabilities`, `ProcessAncestry`, `ClipboardLocality`, hyperlink and clipboard support, URL opening. The probes that fill them in stay in App (K4). | 2,616 (1.1%) | 14 / 10 | 0.5 s | 10.0 / 19.2 s | — | Core |
| **TUIBase** | The default: the substrate, plus what two or more leaves use (below) | **108,068 (46.5%)** | 2,238 / 468 | **30.2 (33.6) s** | **44.8 (48.2) / 67.6 s** | Strings, TerminalHost | Core, Styling, View (**no Image**, after S1) |
| **TUIChrome** (new) | What the run loop draws around the content: the `StatusBar` view, toolbars (`.toolbar`, `ToolbarItem`, the builder, bars, `ToolbarPlacement`, `.toolbarVisibility`), notifications (`NotificationService`, the host), the tooltip popover and `.tooltipStyle`/`.tooltips`/`.tooltipDelay`, `.help`, `.statusBarItems`, the window chrome host, the overlay compositor (`FrameBuffer+Overlays`), the screen-selection highlight and Copy menu. Not `.focusSection` (S2). | 5,187 (2.2%) | 93 / 28 | 2.8 s | 47.6 / 71.2 s | Base | all |
| **TUIEffects** (new) | `.transition`, `AnyTransition`, `Transition` and the built-in and custom transitions; content transitions; `.symbolEffect`; `.visualEffect`; `.scrollTransition`; the colour effects (brightness, contrast, saturation, hue rotation, grayscale, invert, multiply) | 3,736 (1.6%) | 99 / 13 | 0.8 s | 45.6 / 68.7 s | Base | all |
| **TUIBitmaps** (new) | Image's bitmap path: `Image(_:)` from a file or URL, `Image(_:bundle:)`, `_ImageCore` with its render cache and templates, orientation, `AsyncImage`, `.terminalGraphics`, the `.image*` options, asset catalogs and `Color(_:bundle:)`, the `image:` initialisers of `Label` and `ContentUnavailableView`. Not `.aspectRatio`, `.scaledToFit`, `.scaledToFill` or `.imageCellAspect` (S1). | 3,632 (1.6%) | 51 / 14 | 1.1 s | 46.0 / 69.1 s | Base | all (uses Image) |
| **TUIMenus** (new, a pure leaf) | `Menu`, `ControlGroup` and its styles, `.contextMenu`, `.menuStyle`, `.menuOrder`, the concrete menu styles, the popup and inline menu cores, the menu-column layout. The engine and the state rows and tabs use stay in Base, so **no leaf depends on Menus**. | 1,780 (0.8%) | 64 / 7 | 0.6 s | 45.4 / 68.4 s | Base | all |
| **TUINumericControls** (new) | Slider (ticks, value labels), Stepper, Gauge, ProgressView (timer); their handlers and styles; the track and indeterminate renderers and rasters with `.trackStyle`; `.sliderShowsValue` | 8,756 (3.8%) | 160 / 25 | 2.8 s | 47.6 / 71.2 s | Base | all |
| TUITextInput | As planned | 9,681 (4.2%) | 132 / 34 | 2.8 s | 47.6 / 71.3 s | Base | all |
| TUIPickers | As planned | 5,064 (2.2%) | 104 / 18 | 1.3 s | 46.1 / 69.3 s | Base | all |
| TUIForms | Form, LabeledContent, GroupBox, Card, Panel; their styles; `FormButtonRow`. `Box` stays in Base, as on the plan's map. | 2,219 (1.0%) | 89 / 8 | 0.5 s | 45.3 / 68.3 s | Base | all |
| TUIGrid | As planned | 1,685 (0.7%) | 28 / 7 | 0.5 s | 45.3 / 68.3 s | Base | all |
| TUINavigation | As planned (with Inspector) | 5,443 (2.3%) | 117 / 18 | 1.2 s | 46.0 / 69.2 s | Base | all |
| TUIPresentation | As planned | 6,307 (2.7%) | 159 / 25 | 1.3 s | 48.9 / 73.0 s | Base, **Chrome** (`notificationHost(width:)`) | all |
| TUILists | As planned | 16,748 (7.2%) | 211 / 60 | 3.4 s | 48.2 / 72.0 s | Base | all |
| TUITables | As planned | 12,192 (5.2%) | 168 / 28 | 3.6 s | 51.8 / 76.6 s | Lists | all |
| TUITabs | As planned | 4,852 (2.1%) | 130 / 18 | 1.5 s | 49.7 / 74.0 s | Lists | all |
| TUISearch | As planned | 1,576 (0.7%) | 38 / 9 | 0.5 s | 48.1 / 71.9 s | TextInput, Pickers | all |
| TUIColorPicker | As planned | 4,639 (2.0%) | 44 / 12 | 2.3 s | 52.0 / 77.0 s | NumericControls, TextInput, Pickers, Tabs, Presentation | all (uses Image) |
| **TUIApp** | The POSIX console layer as planned, **plus** `Scene`, `SceneBuilder`, `WindowGroup`, `SceneConfiguration` and every Scene modifier (toolbar style, palette and appearance overrides, environment, onChange, mouse support, text selection, theme, undo shortcuts, key notation, reduce motion), `ViewRenderer`, `FrameDiffWriter`, `renderOnce` | 13,785 (5.9%) | 143 / 58 | 3.3 s | 50.9 / 75.5 s | Base, Chrome, **DequeModule** (the `Terminal` files) | all |
| TUI | `Exports.swift` only | 0 | — | 0.5 s | **52.5 (55.9) / 77.6 s** | all | — |

#### Names, as the owner asked

- **TUIBase stays.** TUICore is taken by the lower module, and renaming that one would churn every lower-module
  import and the Windows lanes. TUIFoundation reads as Apple's Foundation, which every TUI file imports.
- **TUIControls is dissolved.** Its contents now sit where a SwiftUI developer would look:
  - Slider, Stepper, Gauge and ProgressView → **TUINumericControls**. Every view in it edits or shows a number in a
    range, and they share the track renderer. No other module holds such a control: Toggle is Boolean, and a TextField
    with a number format is a text field.
  - Menu and ControlGroup → **TUIMenus** (SwiftUI's "Menus and commands"). ControlGroup goes too because its
    `.menu` styles draw a Menu.
  - Link, HelpLink, PasteButton and RenameButton → **TUIBase**, beside Button, Text's links, `OpenURLAction` and the
    clipboard (SwiftUI's "Buttons" and "Links").
- **The new names:** **TUIChrome** (the code already says "window chrome": `WindowChromeHost`, `ChromeStyle`);
  **TUIEffects** (transitions and visual effects); **TUIBitmaps** (not "TUIImages", one letter from the lower
  TUIImage decoder module); **TUITerminalHost** (not "TUITerminal", because the POSIX `Terminal` class stays in
  App).
- **TUIStrings keeps its name.** With localization in it, the name fits better than before.
- **No catch-all names are left.** Every name is free to change until per-module products ship (§7, D1).

#### Granularity

Five modules hold about 1% of the code or less: Menus 0.8%, Grid 0.7%, Search 0.7%, Forms 1.0% and TerminalHost 1.1%.
The owner's test is whether they lengthen an import list.
- **Under (b), nobody imports them.** `import TUI` stays the only import.
- **TerminalHost and Strings are never imported, even later.** Base re-exports them.
- **The leaves each earn their place (est.).** Folding Grid or Forms into Base puts +0.7 s or +0.5 s on every clean
  build, because Base is on every path; folding Menus into Base costs +0.9 s; folding Search into TextInput makes
  TextInput depend on Pickers. The cheapest merge, if fewer modules are wanted, is Grid into Forms: no build cost, and
  +0.07 MB for form apps à la carte.

#### What Base holds now, and what left it

**What left** (measured; §2 has the seams): localization, to Strings; the terminal facts, to TerminalHost; the window
chrome, to Chrome; transitions and visual effects, to Effects; the bitmap path, to Bitmaps; the menu views and
modifiers, to Menus; the Scene family and the run-loop rendering, to App. The link buttons came in.

**What stays, by share of Base's compile time** (slimbase's breakdown of its 110.4k-line Base; this map's Base is 2.3k
lines smaller):

| Area | Share |
|---|---|
| Compositing, opacity, paint, the FrameBuffer algorithms | 24% |
| Stacks and layout | 13% |
| The interaction primitives (Button, Toggle, Label, DisclosureGroup, Spinner, `Image(systemName:)`, the menu engine, popover) | 12% |
| Focus, keyboard, shortcuts and the status-bar *state* | 11% |
| Mouse, gestures and the drag session | 9% |
| Scrolling and windowing | 8% |
| Text | 6% |
| Rows, ForEach, Section and Group | 4% |
| Environment, state, storage, undo, animation, geometry and app services | 13% |

These are what every leaf uses. §2 explains why the rest is not cheap to move.

**Public API that changes module** (measured). By extension block (`pubmoves.refined.out`), 257 public declarations
move against the plan's map. Per member (`challenge/pubmembers.out`, 104 blocks), every member was reviewed. After A4's
S1 and S2 splits, each moved member is under its own SwiftUI topic:
- Scene API in App;
- `.toolbar`, `ToolbarPlacement`, `.toolbarVisibility`, `.help`, `.statusBarItems`, `.tooltipStyle`/`.tooltips`/
  `.tooltipDelay` and `NotificationService` in Chrome;
- `.transition` and its kin in Effects;
- `.contextMenu` and `.menuStyle` in Menus;
- the bitmap initialisers and the `.image*` options in Bitmaps.

`.focusSection(_:)`, `.aspectRatio(_:contentMode:)`, `.scaledToFit()`, `.scaledToFill()` and `.imageCellAspect(_:)`
stay in Base, so `Image(systemName:).resizable().scaledToFit()` needs no Bitmaps.

Under (b) all of this is invisible, behind the umbrella. Three public overload sets are split by label between Base and
Bitmaps: the `Image`, `Label` and `ContentUnavailableView` initialisers with an `image:` or bundle source. A missing
half is a compile error for an à-la-carte user, never a silent rebinding; 15 sets are split across modules in all,
against the plan's 12. One placement is odd: the public `FrameBuffer.compositingOverlays(maxWidth:maxHeight:palette:)`
goes to Chrome with the overlay compositor; it is rarely used outside TUI.

### 2. Base before and after: every cut, its seam, price and A/B

Base goes from 127,418 to 108,068 lines on the r4 rules (measured), about 108.2k after A4's block splits (by hand). Its
job falls by 9.4 s on the model and 6.0 s conservative (est.). The per-cut figures below are revision 3's (`flows.out`).
The r4 pins hand back 0.04 s in all (measured on the model), which changes no total at one decimal.

| # | Cut | Decls / lines (measured) | Base job saved: model / conservative (est.) | Seam | Runtime (new crossing sites, measured; hottest callee by profiled inclusive share) | A/B | Effort |
|---|---|---|---|---|---|---|---|
| 1 | **Localization → Strings** (side lane) | 14 / 1,740 | 2.18 / 0.68 s. Most of the file's SIL is stdlib `Dictionary` specialisation, which Base may still need. | **R1** (2 sites; the `lower` check finds 5 findings, 8 references). `setLanguage(_:)` and `register(translations:)` call `AppState.shared.setNeedsRender…()`, which is in TUIView. They become a Base extension that calls a core in Strings and then AppState: no new mechanism, no registry, no hook on the singleton. Strings gains TUICore (`Lock`). The resources move with `moduleResourceURL`, so the bundle becomes `TUI_TUIStrings.bundle`. **The Linux arm of `UserDefaultsStorage` calls `sanitizedProcessName`, which moves here; B2 widens it to `package`** (the index never saw the call). | 287 sites Base→Strings, plus 7 from Chrome. Hottest: `LocalizationService.string(for:)`, 2.35%: a lock plus lookups, its own work. **Not in set L**: `@inlinable` cannot reach its private state. | B2 | R1 0.25 d |
| 2 | **Terminal facts → TerminalHost** (side lane, new) | 14 / 2,616 | 0.65 / 0.56 s | **None.** A free carve: the assigner moves the files and pulls nothing down. K4 and K6 apply here unchanged. | 28 sites Base→TerminalHost and 36 App→TerminalHost; none ≥ 0.3% in any profile. **Per emitted row:** FrameDiffWriter reads `TerminalClient.simulatedQuirks` (`FrameDiffWriter.swift:539`, and `:589–590` with `simulated` in `model`) and calls `TerminalClient.compensating` (`:570`). The `is*` flags are read once, at init. Stress's A/B never runs FrameDiffWriter, so B2 adds an emission bench. If it shows, snapshot `model` once per frame (App-local, no annotation). | B2 | 0.25 d in B2 |
| 3 | **Window chrome → Chrome** | 93 / 5,187 (rev 3: 100 / 5,402) | 3.14 / 1.72 s (rev 3). The overlay compositor is 1.0 s of stdlib specialisation. | **None**, beyond S2 (below). A free carve. The assigner keeps in Base what Base uses: `StatusBarState`, `SystemStatusBarItem`, the item builder, `TooltipState`, `TooltipStyle` and its keys, `WindowChromeState` and `ToolbarItemPlacement` (`ToolbarPlacement` goes to Chrome), some of them by pin. **K1 gains one opaque slot** (`notificationService`), in its existing pattern. K5's edge now starts in Chrome, with the same fix. | 905 Chrome→Base sites, per frame. Hottest: the VStack/HStack inits (default CMO inlines them, t13); `ANSIRenderer.styleSequence` (its own work); `MouseEventDispatcher.register`, 1.86%, in set L. M3's TUIChrome held 22 of the 42 files that Chrome and Effects take, so M3's A/B partly covered this boundary, and its app-shapes cold +2.3% is still unattributed: **step 0a is binding before B5b.** | B5b | 0.5 d |
| 4 | **Effects → Effects** | 99 / 3,736 | 1.12 / 1.00 s | **None.** A free carve. Transition removal plays back through TUIView's DepartureStore closures, so Base never names a transition type. `TimelineView` stays, because ProgressView uses it. `_SymbolEffectGlyph` stays too: `_SymbolIcon` draws it, and M3 lost Label icons over it. Only the `.symbolEffect` modifiers move. | 218 sites. Hottest: `View.modifier`, 0.34%. **Per row or line:** `.scrollTransition` (per row per frame; the Geometry scenario covers it), and the colour effects, which call `SGRColorRewrite.rewriting(…){closure}` (`ColorEffectModifiers.swift:252`) per line across the boundary. That costs the closure's specialisation and adds an indirect call per SGR colour code. **No Stress scenario uses colour effects**, so one is added before B5b. If it shows, the remedy is `@inlinable package` on `rewriting` (tier 2's style), or keeping the 386-line `ColorEffectModifiers.swift` in Base (≈0.1 s). | B5b | 0.25 d, + 0.25 d scenario |
| 5 | **Bitmaps → Bitmaps** | 51 / 3,632 (rev 3: 54 / 3,650) | 1.47 / 1.43 s (rev 3). **Base drops TUIImage and CSTBImage once S1's sanitiser move lands.** The `lower` check gives 159 Base→TUIImage findings on the plan's map and 0 on this one; that 0 holds only because the S1 block is still assigned to Bitmaps until A4 splits it. | **R2** (4 edges, 11 references; below). **S1** (5 edges, 12 references; below). | One existential call per image measure or render, and 260 sites on the image's own path. Hottest: `Text.init<S>`, which tier 1's shim covers. | B5c | R2 1–1.5 d; S1 0.5 d in A4 |
| 6 | **Menu views → Menus** (a pure leaf) | 31 / 1,104 from Base, plus 33 / 676 from Controls | 0.79 / 0.57 s | **None.** The menu engine, `ContextMenuState`, the menu-row sink and `MenuStyle` stay in Base. A4 splits `MenuPopover.swift` into its column and popup halves. | 227 Menus→Base sites, **per frame for each row of an open menu** (the MenuBar scenario covers it). Hottest: `FocusRegistration.register`, 3.15%, in set L. | B5b | 0.25 d |
| 7 | **The Scene family and the run-loop rendering → App** | 53 / 2,219 | 0.31 / 0.30 s | **None, and K3 is dropped.** `ViewRenderer` and `FrameDiffWriter` move with `renderOnce`, so ViewRenderer needs no `any TerminalProtocol` parameter. App gains the DequeModule dependency (B3). | 172 App→Base sites, per frame. Hottest: the environment accessors (`mouseEventDispatcher` 1.24%, `preferenceStorage` 0.94%), tier 1 and E1. FrameDiffWriter's `TerminalProtocol` calls are existential already; its ANSI clip and compensation helpers are in TUICore today. B3 adds an emission bench. | B3 | −0.25 d (no K3) |
| in | **Link, LinkDisplay, HelpLink, PasteButton, RenameButton, `.refreshIndicator`, `.shiftStepMultiplier`**, from the plan's Controls into Base | 26 / 884 | −0.20 s | **None.** Removes crossings. | — | — | — |

> **Added 2026-10-08:** the profiled shares in the Runtime column, each cut's
> hottest callee and "none ≥ 0.3% in any profile", were read with
> `Tools/Profiling/analyze_timeprofile.py`. Until 2026-10-08 that analyzer
> counted each distinct stack once, under-weighting the hottest. Treat the
> shares as indicative, since a full count may name a different hottest
> callee. The A/Bs the A/B column schedules time binaries, so they are
> unaffected.
> `Tools/Profiling/README.md` has the details.

**R2 in detail** (from slimbase, with judge-risk's conditions):
- **What stays in Base.** `Image` stays one public type in Base, with `Image(systemName:)`.
- **The raster content becomes a value the leaf constructs.** `Image(_:)` and `Image(_:bundle:)` become extensions in
  Bitmaps, and `AsyncImage`'s decoded pixels travel inside the value. So does `imageSupersampling`, which `Image.body`
  sets on the raster core today (`Image.swift:190`; R2's fourth edge).
- **The raster arm draws a Base host view** (`Renderable & Layoutable`) that forwards measure and render to the value.
  It keeps `_ImageCore`'s `StateIndex` slots. Equality goes through the value, with the decoded pixels excluded, as
  today.
- **The raster protocol gets no default** `isEqual`, measure or render. A default would be a silent stale image or a
  silent memo miss.
- **The memo is no worse off.** `Image.Content` has not opted into `_ValueHashing`, so Image already skips the per-pass
  memo. Opting it in is an optional follow-up.
- **Gates:** golden snapshots, ImageHarness, Stress `--selfcheck`.

**S1 in detail** (A4; no longer a pure split):
- **The split.** Out of `Image.swift`'s image-option blocks, into Base extensions of their own:
  - the cell-aspect option: `ImageCellAspectKey`, the `imageCellAspect` accessor and `.imageCellAspect(_:)`. Text,
    Table, the background and the run loop read it.
  - the content-mode and aspect-ratio pair: `ImageContentModeKey`, `ImageAspectRatioKey`, `imageContentMode`,
    `imageExplicitContentMode`, `imageAspectRatio`, and the layout modifiers `.aspectRatio(_:contentMode:)`,
    `.scaledToFit()` and `.scaledToFill()`, beside `Image.resizable()`. `_ImageCore` (Bitmaps) reads them downward.
- **The sanitiser move.** The setter's rule moves down into TUIStyling as `package` API: `sanitizedCellAspect` and
  `cellAspectRange`. TUIImage already depends on Styling, so `ASCIIConverter`'s two public members stay and forward
  to it.
  - The rule keeps exactly one implementation; its comment records that a second copy once let `.infinity` through.
  - No new public API.
  - It is pure arithmetic in a module that must keep building on Windows, which the advisory Windows lane checks.
- **Without the move,** Base keeps a TUIImage dependency for one function. That costs no build time, and about
  0.25 MB for an à-la-carte app without bitmaps later (slimbase's estimate). The move is recommended.

**S2 in detail** (A4, new): `.focusSection(_:)` is split out of the `.statusBarItems` extension block
(`Extensions/View+Events.swift:612`) into its own block, and stays in Base with `FocusSectionModifier` and
`RenderContext.publishSectionIndicator`. The r4 rules pin those two now (measured: 7 declarations back from Chrome);
the method follows when A4 splits the block.

**Totals for the cuts.**
- About 4.5 agent-days: R1, R2, S1 with the sanitiser move, S2, the `lower` check and per-member reporting, the
  colour-effects scenario, 14 more file splits, and the B5b and B5c carves.
- 2 more A/Bs, plus the two emission benches.

**The floor.** Base is still 30.2 s (33.6 conservative) of the 37.9 s between View's end and the umbrella's (est.).
What is left in it is used by everything, so further cuts are no longer free:
- **The menu engine (D-m), measured here.** Base −2.4k lines; the full build −1.0 s on the model, −0.9 s conservative
  (est.). It needs R3 (3 edges, 4 references) and R4 (7 edges, 20 references), about 2–2.75 d and an A/B; R4 touches
  the row context-menu path.
- **The side layer (D-a′).** Compositing, paint and opacity (24% of Base's compile time), plus the View-free values.
  Est. −4 to −6 s on top: judge-owner's estimate from layers' full2 at 45.5 s, 49.2 conservative; not measured on this
  map. It brings per-cell crossings, set S (215 declarations) and two tie rules the tool lacks.
- **The leaf lift and mid layers:** rejected (§6).
- **Splitting TUICore (D-d):** 9.5 s on every path, unexplored.

### 3. Critical path, and what apps compile and link

#### The full clean build: every app's build under (b)

| | Xcode 6.2.4 | swiftly 6.2.4 |
|---|---|---|
| Today | **77.8 s (measured, quiet box)** | ≈ 110 s (model; 116.7 s measured in a busy session) |
| M3's trial split, 6 modules, no annotations | **64.8 s (measured, quiet box)** | — |
| Plan rev 2, coarse / full (est.) | 66.8 / 61.9 s | 96.2 / 89.8 s |
| **Refined (r4), coarse / full (est.)** | **57.4 / 52.5 s** (cons. 60.8 / 55.9) | **84.0 / 77.6 s** (cons. 88.3 / 82.0) |

**The chain after the full split (est., Xcode):**
- The path: View 14.6 (measured) → **Base 44.8** (cons. 48.2) → Lists 48.2 → Tabs 49.7 → ColorPicker 52.0 → umbrella
  **52.5**.
- Off the path: Tables ends at 51.8, the next floor; Base → Chrome 47.6 → App 50.9; the side lane is hidden under View
  (TerminalHost ends at 10.0 s and Strings at 13.2 s, 1.4 s before View ends).
- **The tail after Base** is 7.7 s on the chain. Shortening it is not worth it (§6): Tables is the next floor, at most
  0.3 s away.
- **On a 3-core CI runner the tail is bound by work, not by the chain.** The leaves hold about 30.8 s of jobs, so the
  build ends at about 55.4 s (est.). Contention is not modelled, as in the plan.
- **The model's range.** It is calibrated on M3's real modules (residuals ≤ 0.9 s; M3's base job was 38 s), so Base's
  30 s job is inside its range. It overstates one 230k-line job: it predicts 85.0 s for today's measured 77.8 s.

#### When the win arrives (est., change in the family's end time after each step)

Model / conservative, from revision 3's `steps.out` (r4's 0.04 s does not show at one decimal). Before B6, Base is
still over 150k lines, where the model reads high, so read the changes, not the absolute times.

| Step | Change, model / cons. |
|---|---|
| B2: Strings with localization, and TerminalHost | −4.7 / −3.1 s |
| B3: App | −0.3 / −0.3 s |
| B4: ColorPicker | −2.6 / −2.6 s |
| B5: Navigation group | −1.4 / −1.4 s |
| B5b: Chrome, Effects, Menus | −2.4 / −0.6 s |
| B5c: Bitmaps | −1.5 / −1.4 s |
| B6: Lists group | −6.0 / −6.0 s |
| B7: TextInput group | −8.7 / −8.7 s |
| **End of Phase B** | **57.4 / 60.8 s** |
| C2: Tables | −1.4 s |
| C5: Search | −0.4 s |
| C6: Forms | −0.5 s |
| C7: NumericControls | −2.6 s |
| **Full split** | **52.5 / 55.9 s** |

The other peels change nothing.

#### What each kind of app compiles and links

**Now, under (b):** every app compiles all 20 modules (232.7k lines) and links 11.66 MB stripped (est.), against
11.59 MB for the plan's map and **11.15 MB today (measured)**, at a clean-build end of 52.5 s (55.9 conservative),
against 77.8 s today.

**Later, à la carte** (est.). Every app compiles Strings, TerminalHost, Base, Chrome and App. Plan rev 2's figures are in
brackets.

| App | Extra modules | TUI lines compiled | Stripped | Family ends, Xcode / swiftly |
|---|---|---|---|---|
| Hello world | — | 144.3k, 62.0% (151.9k, 65.3%) | 7.56 MB (7.90) | 50.9 / 75.5 s (57.2) |
| Typical: List, TextField, Picker, alert, toolbar | Lists, TextInput, Pickers, Presentation | 182.1k, 78.3% (81.6%) | 9.12 MB (9.47) | 50.9 s (57.6) |
| Forms and controls | NumericControls, TextInput, Pickers, Forms | 170.1k, 73.1% (77.0%) | 8.72 MB (9.13) | 50.9 s (57.3) |
| Table or list | Lists, Tables | 173.3k, 74.5% (77.7%) | 8.76 MB (9.11) | 51.8 s (61.2) |
| Navigation and tabs | Navigation, Lists, Tabs | 171.4k, 73.7% (76.9%) | 8.68 MB (9.03) | 50.9 s (59.2) |
| Dashboard: Grid, Gauge, GroupBox | Grid, NumericControls, Forms | 157.0k, 67.5% (71.4%) | 8.17 MB (8.59) | 50.9 s (57.3) |
| Everything | all | 232.7k, 100% | 11.66 MB (11.59) | 52.5 / 77.6 s (61.9) |

- **TUIImage.** Once S1's sanitiser move lands, apps without Bitmaps or ColorPicker also stop linking TUIImage
  and CSTBImage: about −0.25 MB more, on slimbase's estimate; the table leaves it out.
- **The sizes** use plan §2's formula, with 156 B per new exported symbol, as 0c did.

### 4. Imports

**Now:** one import, `import TUI`. The owner chose umbrella-only products, so nothing changes for users. The new
modules exist and compile in parallel, out of sight.

**Later, once per-module products are advertised.** This assumes plan Q4: each module `@_exported`-imports its direct
dependencies.

| App | Imports |
|---|---|
| Hello world | `TUIApp` (1) |
| Typical (List, TextField, Picker, alert, toolbar) | TUIApp, TUILists, TUITextInput, TUIPickers, TUIPresentation (5). With `.searchable`: TUISearch replaces TextInput and Pickers (4). |
| …with row context menus | + TUIMenus |
| Table | TUIApp, TUITables (2); Tables re-exports Lists |
| Navigation and tabs | TUIApp, TUINavigation, TUITabs (3) |
| Forms and controls | TUIApp, TUINumericControls, TUITextInput, TUIPickers, TUIForms (5) |
| Dashboard | TUIApp, TUIGrid, TUINumericControls, TUIForms (4) |
| Any app using transitions or visual effects, or bitmaps | + TUIEffects, + TUIBitmaps |
| Everything | `TUI` (1) |

**Never imported:**
- Strings and TerminalHost: Base re-exports them.
- Chrome: App and Presentation re-export it, so `.toolbar`, `.help` and `.statusBarItems` come with `import TUIApp`.
- Base itself: every leaf re-exports it, so `.focusSection`, `.aspectRatio` and `Image(systemName:)` come with any of
  them.

Under MemberImportVisibility, a file imports only what it uses, usually one or two modules.

**Against the plan's map.** Link, PasteButton and RenameButton need nothing extra: they are in Base, where the plan
needed Controls. `.contextMenu`, transitions and bitmaps each add one opt-in import; the plan had all three in Base.

**Conveniences.**
- **The umbrella stays the default.** Under (b) it is the only product, and since everything compiles in parallel it
  costs no wall time.
- **At C9b, if the battle-test shows import lists that are too long:** TUIApp could re-export Effects and Menus (a
  hello world à la carte then compiles 5.5k more lines and links +0.33 MB, est., for no wall time; not recommended now),
  or thin bundle products could re-export a set of leaves (about 0.5 s of parallel job each).

### 5. What changes in the plan's steps

#### The refactors (every seam)

| # | Status in revision 4 | Effort |
|---|---|---|
| K1 | **6 edges, 12 references** (plan: 5, 10). It gains the `notificationService` slot (Base→Chrome), in the same opaque-slot pattern. | as planned, with a PTY smoke |
| K2 | Unchanged (2 edges, 17 references) | as planned |
| K3 | **Dropped.** ViewRenderer goes to App with `renderOnce`, so nothing in Base needs a terminal. | −0.25 d |
| K4 | Unchanged. The edge now starts in TerminalHost (`TerminalIdentityQuery.swift:294`, `setenv` at :318). Follow the Terminal-compatibility rule. | as planned |
| K5 | Unchanged fix (a field-text-layout protocol in Base; WordBoundary moves down). The highlight edge now starts in Chrome. | as planned |
| K6 | Unchanged. The two Windows arms (`ProcessAncestry`, `TerminalHost`'s `pid_t`) are now what lets **TerminalHost** build on Windows. | as planned |
| X1, X2 | Unchanged. `GaugeStyleConfiguration` stays in Base with `GaugeStyle`; the concrete gauge styles go to NumericControls. | in A4 |
| **R1** | New (§2, cut 1): a Base extension over a Strings core, in place of `AppState.shared` in `LocalizationService`. **Its commit adds the `accepted` public-above entry** for the public `setLanguage(_:)` and `register(translations:)` it declares on a Strings type; accepting it earlier would trip the `rules` check, which reports an entry that matches nothing. Gate: a language-switch PTY smoke. | 0.25 d |
| **R2** | New (§2): **4 edges, 11 references**. It lands **last** in A2. If it slips, B5c moves after B7 and nothing else changes: Bitmaps is a pure leaf. | 1–1.5 d |
| **S1** | New (§2): **5 edges, 12 references**; the block split plus the sanitiser move into TUIStyling, in A4. | 0.5 d |
| **S2** | New (§2): `.focusSection` out of the `.statusBarItems` block, in A4. | 0.1 d |
| R3, R4 | Option D-m only (§7, D2) | 2–2.75 d |

#### Runtime and the annotation tiers

- **Crossings** (measured on revision 3's rules, `xings.refined.out`; the r4 pins move 10 declarations and change at
  most a few dozen sites, not re-counted). There are 11,848 sites in all, against 9,902 for the plan's map on the same
  script: 2,173 new. On the r4 rules, 2,367 members are widened to `package`. The biggest boundaries:

  | Boundary | Sites |
  |---|---|
  | Lists→Base | 1,686 |
  | App→Base | 921 |
  | Chrome→Base | 905 |
  | Tables→Base | 873 |
  | Tables→Lists | 723 |

- **The per-row crossings, and what measures them.** None is in a scenario's hot list today. Each is one call, or one
  indirect call, per row or colour code.

  | Crossing | Rate | Instrument | Remedy if it shows |
  |---|---|---|---|
  | FrameDiffWriter → `TerminalClient.simulatedQuirks`, `simulated`, `compensating` | per emitted row | **`Tools/Profiling/emit_bench.py`** at B2 and B3, Apple Terminal host (the heaviest walk). `Stress --bench` never runs FrameDiffWriter. | snapshot `model` once per frame (App-local) |
  | Colour effects → `SGRColorRewrite.rewriting` | per line, closure per colour code | **a new colour-effects variant** in Stress (a `ScenarioVariant` of ModifierChains or Gradients), in B5b's A/B | `@inlinable package` on `rewriting`, or keep `ColorEffectModifiers.swift` in Base |
  | `.scrollTransition` → Base | per row per frame | the Geometry scenario, B5b | tier 2 |
  | Open-menu rows → Base | per frame while open | the MenuBar scenario, B5b | set L covers `FocusRegistration.register` |

- **Set L lands with tier 1 in A3**: 34 declarations, since `LocalizationService.string(for:)` is out (it is its own
  work, behind private state). `ClaimingRow` joins it (10 members, 190 leaf→Base sites; 0c's advice). Its named callees
  now cross before B6: `FocusRegistration.register` and `MouseEventDispatcher.register` at B4, and again through Chrome
  and Menus at B5b. The A2+A3 A/B measures them inside the monolith, where they should be neutral. Their
  `@usableFromInline` state becomes exported symbols in Phase A (0b, point 3); under (b) every app would carry those
  anyway.
- **Set T is unchanged:** before C2. Tier 2 is generated and held, as planned.
- **Re-cut the tiers on this map at A1′** (`reindex/w/tiers.py`). The annotation style is unchanged: `@inlinable
  package` with `@usableFromInline` state (0b). `@_specialize(exported:)` and `@_alwaysEmitIntoClient` stay in reserve.
- **Watch items.** The four per-row crossings above, and the environment accessors App now reads across (tier 1 and
  E1).

#### The steps, revised

| Step | What | Change from the plan | Effort |
|---|---|---|---|
| 0a | The coordinator profiles M3's cold truncate and app-shapes runs. | **Binding before B5b**, whose Chrome overlaps M3's. | 1 session |
| 0b, 0c, A1 | Done: `RESULTS-0b.md`, `reindex-0c.md`, and `Tools/ModuleMap` on main (be7aba9df), warning-only in CI | — | — |
| **A1′** | Commit this map: `r4/rules.r4.json` becomes `rules.json`, then `assign --write`. Port the `lower` check (layers' 76-line prototype, `layers/tool-lower-check.patch`) with unit tests and the README, and add `lower` lists. **public-above lists every public member of a flagged block, not just its first** (`challenge/w/pubmembers.py` is the reference). Schedule R1 under `lower`. Re-cut the tiers. | new | 1 d |
| A2 | K1, K2, K4, K5, K6, R1 (with its accepted entry), then **R2 last**; one commit each | +R1, +R2, −K3 | 2.5–3.5 d |
| A3 | Tier 1 (15 declarations, after 0c's corrections) **+ set L (34) + ClaimingRow**. Generate and park set T and tier 2. One A/B covers A2 + A3 and sets the +3% baseline. | set L folded in | 0.75–1.25 d + A/B |
| A4 | File splits: **93** files (plan: 80), including `MenuPopover.swift`; the **S1** and **S2** block splits; S1's sanitiser move into TUIStyling; X1, X2; ControlGroup to Menus; FormControlRow; Label's and DisclosureGroup's styles. Add the **colour-effects Stress variant**. | +13 files, S1, S2, scenario | 1.25–1.75 d |
| A5 | `git mv` into `Sources/TUI/<Module>/`, with the plan's path fixes. The resources (`Localization/translations`, `VERSION`) follow `ModuleResource` into the Strings directory and target. `Documentation/Terminal-compatibility.md`'s source paths for FrameDiffWriter and TerminalHost. **`Tools/verify-versioned-consumer.sh`**: its references to `Sources/TUI/VERSION` and the bundle. | small additions | 0.5–1 d |
| B1 | Umbrella swap, as planned | — | 1–1.5 d |
| **B2** | Carve Strings, now with localization and the resources (the bundle becomes `TUI_TUIStrings.bundle`), and TerminalHost, under one A/B **plus an emission bench**. **Widen `sanitizedProcessName` to `package`** for `UserDefaultsStorage`'s Linux arm. Both modules join the Windows ratchet as advisory steps. | +TerminalHost, +localization | 0.75 d |
| B3 | Carve App, now with the Scene family, ViewRenderer and FrameDiffWriter, plus `renderOnce`, `identify(using:)` and `seedDiscoveredHost`; **App gains the DequeModule dependency**. A/B **plus an emission bench**. CLAUDE.md's POSIX rule names TUIApp, per the relaxed rule. | +Scene, +run-loop rendering | 0.5–1 d |
| B4 | Carve ColorPicker | — | 0.5 d |
| B5 | Carve the Navigation group (with Presentation) | — | 0.5 d |
| **B5b** | Carve Chrome, Effects and Menus under one A/B, **after 0a**, with the colour-effects variant in the A/B. App and the Navigation group gain their Chrome edge. It must follow B5: Presentation uses Chrome, so Chrome cannot leave Base while Presentation is still inside it. | new | 0.75 d |
| **B5c** | Carve Bitmaps, after R2 and S1. Remove TUIImage and CSTBImage from Base's dependencies. | new | 0.5 d |
| B6 | Carve the Lists group (Tables, Tabs, Grid inside). Set L is already in. | — | 1–1.5 d |
| B7 | Carve the **TextInput group** (Pickers, Forms, Search and NumericControls inside), named after its residual, since Controls no longer exists. **Coarse stage done: 57.4 / 60.8 s (est.).** | renamed | 1 d |
| C1–C8 | Peel, top of the DAG first: Presentation; set T, then Tables; Tabs; Grid; Search; Forms; NumericControls; Pickers (TextInput is the residual). ColorPicker's dependencies follow each peel. Measure peak RSS at C2. **Full split: 52.5 / 55.9 s (est.).** | same count | 4.5 d |
| **C9a** | Docs and release notes, now: the bundle name; `String(reflecting:)`, `dump` and debugger names (`TUIBase.Text`, `TUIChrome.StatusBar` …); **`NavigationPath.CodableRepresentation` stores `_mangledTypeName`**, so a saved path holding a TUI-defined type no longer decodes; `renderOnce` is in TUIApp; `TUI.X` keeps resolving (t14). Plus CONTRIBUTING's Windows table. | split from C9 | 0.5–1 d |
| **C9b** | Per-module products, the "which module provides X" article and the import guide, **after the battle-test** (the owner's (b)). | deferred | 0.5 d when decided |

**Total.** About **18–22 agent-days** of remaining work, plus **17 quiet-box A/Bs** (one for A2 + A3, eight carves,
eight peels) and two emission benches beside B2's and B3's. That is about 4–5 weeks on one landing stream; the A/Bs
remain the long pole. Against the plan's remaining work (its 16–20 d, less step 0 and A1, which are done): about +4.25 d.

**Gates.** As planned, plus:
- the `lower` check, warning-only until A2 and A4 land, then gating like the rest;
- **at every carve, before landing:**
  - `challenge/w/inactive_widen.py`, re-pointed at the tree being carved, to widen what only a non-macOS arm uses;
  - the Linux cross-compile (static-linux SDK) of the package, because the index never sees those arms;
- Strings, TerminalHost and each new non-POSIX module as advisory Windows steps (the existing Windows lane already
  covers S1's change to TUIStyling);
- R2's image gates;
- the PTY smokes for K1's new slot and for R1.

Every step lands on its own with the gates green. B5b and B5c can move later without affecting anything else.

### 6. What is not worth doing

| Candidate | What it would buy (est.) | Why not |
|---|---|---|
| **Layers' lift**: public API no other module uses, in a parallel module | −2.0 s on this map (51.1 / 54.7 cons.) | Membership is defined by non-use, so public API changes module whenever a leaf starts using it. It would carry 54 public modifier blocks (`.hidden()`, `.offset`, `.zIndex`, `.tint`, `.lineLimit` …), and the map would hang on 1,151 pinned labels. A structure that drifts by construction cannot be battle-tested and then advertised. |
| Layers' mid layers | −2.3 s | 32 public-above findings and a boundary that follows no topic |
| **Renaming the kernel TUIFoundation** and giving the lift the name TUIBase | — | It hands the owner's chosen name to a grab-bag. |
| A separate TUILocalization side module (layers' K7) | ≈ 0.5 s, not 1.75 | `LocalizationService.swift`'s SIL is 1.13 s of stdlib specialisation and 78 ms of its own. |
| **Menus as a mid layer** (leaves' original) | — | It sits on the Lists chain (+0.6 s against a pure leaf) and moves the per-cell `selectionContextMenu` read across a boundary. |
| Toggle out of Base (half of plan D-c) | −0.3 s | 11 findings: the default ToggleStyle draws a Toggle, and the run loop reads `ToggleCharacterSet`. |
| A drag-and-drop module | +0.1 s | TUIContext, ScrollView, spring loading and mouse dispatch use the session, so it could only be a mid layer under Lists. |
| A gesture-API module | −0.3 s | 1 owns-neither and 2 public-above findings, for noise |
| The scroll family out of Base | 3.7 s at stake | Base uses it 468 times from 39 declarations; the lazy-stack windowing *is* the scroll machinery. |
| Storage, undo, ContentUnavailableView, DisclosureGroup | ≤ 0.2 s each | A carve and an A/B each, for noise |
| Tabs folded into Navigation | +1.6 s | ColorPicker's panel is a TabView, so the chain becomes Lists → Navigation → ColorPicker. |
| Grid, Forms or Search folded into Base or TextInput | +0.5–0.7 s on every build, or a TextInput→Pickers edge | §1, Granularity |
| Shortening the tail after Base (a ColorPicker without TabView, Tabs without Lists) | ≤ 0.3 s | Tables, at 51.8 s, is the next floor; and it would change UI. |
| Merging Strings and TerminalHost into one side module | nothing users see | It halves the side lane's margin (1.4 s) under View. |
| TUIApp re-exporting Effects and Menus now | shorter import lists, later | +0.33 MB for an à-la-carte hello world. Decide at C9b with the battle-test's evidence. |
| Copying the cell-aspect rule into Base instead of moving it down | avoids touching Styling | Two copies of that rule are how `.infinity` once got through (the modifier's own comment). |
| K8 and K9 (layers) now | — | They matter only to the Phase D side layer, and are trivial at any time, so land them with D-a′. |
| Layers' full2 side layer now | −4 to −6 s on top | Phase D. About 6.2k kernel→side sites (per-cell helpers among them), set S, +0.25 MB, and two tie rules the tool lacks: `StateIndex` collisions, and environment keys separated from their accessors. |

### 7. Decisions for the owner

Four are real trade-offs. Everything else is decided below, and can be vetoed.

**D1. The new names.**
- Recommended: TUINumericControls; TUIMenus, TUIChrome, TUIEffects, TUIBitmaps and TUITerminalHost.
- Alternatives for NumericControls: TUIRangeControls; TUIValueControls (weaker: Picker and Toggle are value
  controls too); TUIIndicators (fits only if Slider and Stepper leave, which costs the shared track renderer, +1.6k
  lines in Base, or an extra edge).
- **Price:** none before products ship. Decide before A1′ if possible: each later rename churns the re-qualification
  script.

**D2. The menu engine into TUIMenus (D-m).**
- Buys: −1.0 s on every clean build (−0.9 s conservative); Base −2.4k lines; −0.11 MB for an à-la-carte hello world.
- Costs: R3 and R4, about 2–2.75 d and an A/B; R4 touches the row context-menu path; TextInput and Pickers gain a Menus
  edge, off the chain.
- **Recommended:** not now. Revisit after the battle-test, with Phase C's A/B data. `r4/rules.r4+engine.json` is
  verified and ready.

**D3. The Phase D side layer (D-a′).**
- Buys: est. −4 to −6 s more, the only lever left of that size.
- Costs: per-cell crossings and set S, +0.25 MB, and the tie rules.
- **Recommended:** decide after Phase C and the battle-test.

**D4. Bytes under (b).**
- Until per-module products ship, every app links the split's export trie and gains nothing à la carte: 11.66 MB
  against 11.15 MB today, +0.51 MB (+4.6%, est.).
- Options:
  - (a) Accept for the battle-test **(recommended)**. The coordinator measures plan D-e's `-Xlinker
    -no_exported_symbols` on Example and Stress at B1: one build and a size check. If it works, it also removes the
    0.61 MB trie today's monolith carries. Document it for app authors (a package cannot impose it), together with
    `-internalize-at-link`.
  - (b) Ship per-module products sooner.
- **Price:** one build.

**Decided here (veto if you disagree):**
- **R2 and Bitmaps are in:** about 1.4 s on every build for about 2 d, with the image gates.
- **S1 moves the cell-aspect rule down into TUIStyling** (`package`, one copy, `ASCIIConverter` forwards), so Base
  needs no TUIImage. It touches a Windows-binding module, with pure arithmetic.
- **`.focusSection`, `.aspectRatio`, `.scaledToFit`, `.scaledToFill` and `.imageCellAspect` stay in Base** (S1, S2).
- Menus is a pure leaf.
- Link and its kin sit in Base, at +0.2 s.
- Scene and the run-loop rendering go to App, and K3 is dropped.
- Set L lands in A3, without `string(for:)`.
- TerminalHost stays separate from Strings.
- No lift.
- K8 and K9 wait for Phase D.
- The existing lower-four products are left untouched until C9b.
- TUIApp does not re-export Effects or Menus.

### 8. Verification (measured)

**Setup.**
- **Tool:** `Tools/ModuleMap` as committed at be7aba9df, copied to `refine/plan/tool`.
- **Snapshot:** the layers lane's pristine snapshot of 59e04b011, whose `Sources/TUI` diffs equal to be7aba9df's,
  with its own debug index store (Xcode 6.2.4). The repo's `.build` has no index store.
- **Wrapper:** `refine/plan/w/mm.py`, which never writes into the repo.

**The plan's rules reproduce 0c:**

```
upward           0 new   (scheduled K1 5 (10 refs), K2 2 (17 refs), K3 1 (2 refs), K4 2, K5 2 (19 refs))
public-above     0 new   (accepted 12)
modulemap: 0 new findings (28 scheduled or accepted) in 4.0 s
```

**Revision 4's map, stock tool** (`check --rules r4/rules.r4.json --map r4/map.r4.json`):

```
modulemap: 793 files, 4127 declarations, 12697 edges from …/refine/layers/store (2.0 s)
upward           0 new   (scheduled K1 6 (12 refs), K2 2 (17 refs), K4 2, K5 2 (19 refs), R2 4 (11 refs), S1 5 (12 refs))
owns-neither     0 new
witness          0 new
public-above     0 new   (accepted 15)
posix            0 new   (scheduled K4 1, K6 3)
umbrella         0 new
rules            0 new
modulemap: 0 new findings (40 scheduled or accepted) in 2.4 s
```

- `check --fresh` (the assigner run from the rules) gives the same: 0 new (40).
- `assign` from revision 3's map: "10 declarations change module" (7 Chrome→Base, 3 Bitmaps→Base), the S1 and S2 pins.
- **With the `lower` check** (layers' prototype; `r4/rules.r4.lower.json` adds R1 as scheduled):
  `lower 0 new (scheduled R1 5 (8 refs))`, and 0 new (45) in all. It is not vacuous: the plan's map, with Base's
  `lower` set to Core, Styling and View, gives `lower 159 new` (`TUIImage.RGBAImage`, `width`, `height` …). Its 0
  for Base→TUIImage on this map depends on S1's block still sitting in Bitmaps; once A4 splits it, the sanitiser
  move is what keeps it 0.
- **Option D-m** (`r4/rules.r4+engine.json`): 0 new (50; 55 with `lower`), adding `R3 3 (4 refs), R4 7 (20 refs)`;
  Base 105,705 lines.

**The skeptic's re-run of revision 3** (`challenge/`) reproduced every check and `price.out` byte for byte, and
recomputed Base's lines, Base's job, the full build, the hello-world share and the export trie by hand.

**Also measured:**
- owns-neither 0 and witness 0: the silent-failure classes, as far as the macOS index sees.
- **What the macOS index cannot see.** The non-macOS `#if` arms in Base, Strings, TerminalHost and App reference no
  type in a module they cannot see, with one exception: `UserDefaultsStorage.swift:246` →
  `sanitizedProcessName` (`challenge/inactive_widen.out`, apart from local-variable noise). There are no DEBUG or
  benchmark-flag arms in `Sources/TUI`.
- Lower-module use: only Bitmaps (304 references) and ColorPicker (234) use TUIImage; Strings' only TUIView use is
  R1's.
- Landing order: no final-map edge points from a module still inside Base into one carved earlier, at any of B2–B7.
- The `where Self ==` extensions in moved files are only static-member conveniences, not default implementations.
- Memo and identity: Image already skips the memo; identity paths use `String(describing:)`, so module names do not
  change focus IDs; K1's opaque slots keep each value's dynamic type.
- TUIAppKit reaches the `package` members `Color.catalogColor` and `catalogColorScheme` (now in Bitmaps) through the
  umbrella's re-export.
- 15 public overload sets split across modules (plan's map: 12); the 3 new ones are the Bitmaps initialisers.
- 93 split files; 2,367 members widened; 2,173 new crossing sites (revision 3), with each callee's profiled share.

### 9. Files

Everything is in `split2/refine/plan/` unless named otherwise:
- **The map (revision 4, the recommendation):** `r4/rules.r4.json`, `r4/map.r4.json`; `r4/rules.r4.lower.json` (with
  R1 for the `lower` check); `r4/rules.r4+engine*.json`, `r4/map.r4+engine.json` (option D-m). Built by `w/mkr4.py`
  from revision 3's `rules.refined*.json`, which `w/mkrefined.py` builds from judge-owner's
  `rules.graft-menusleaf.json`.
- **Tool outputs:** `r4/check.r4*.out`, `r4/assign.r4*.out`; revision 3's `check.refined*.out`,
  `check.plan-baseline.out`, `assign.refined*.out`.
- **Pricing:** `r4/price.r4.out` (`w/price_r4.py`: revision 3, revision 4, its coarse stage, and D-m); revision 3's
  `price.out` (`w/price.py`), `steps.out` (`w/steps.py`), `flows.out` (`w/flows.py`).
- **Crossings and API:** `xings.refined.out` (slimbase's `xings.py`) and `pubmoves.refined.out` (`w/pubmoves.py`, per
  block); `challenge/pubmembers.out` (per member).
- **The skeptic's checks:** `split2/refine/challenge/`: check and price re-runs, `inactive_widen.out` and `inactive.out`
  (the non-macOS arms), `pubmembers.out`, `lowerdeps.out`, `focused_base_refs.out`, `xside.out`, `xchrome.out`,
  `shellxings.extra.out`, and their scripts in `w/`.
- **Scripts:** `w/mm.py` is the tool wrapper (`MM_LOWER=1` uses the `lower` prototype); `w/shellxings.py` lists the
  crossings of the moved rendering files.
- **The inputs:** `refine/{slimbase,layers,leaves}/design.md`, `refine/judge-owner/`, `refine/judge-risk/`; revision 3
  is `plan-refined.r3.md`.
- **Re-running.** `w/mm.py`, `w/price.py` and `w/price_r4.py` read the layers snapshot (`refine/layers/src` plus
  `store`), which is in the session notes and durable. `xings.py` reads slimbase's snapshot in the session scratchpad,
  which is not durable; slimbase's design §10 says how to recreate it.

## Completing the SwiftUI API: decisions from lane SP0

*Lane SP0 carried out steps 0b, 0c and A1 of the module-split plan: the owner's decision of 2026-10-07 to split
TUI into à-la-carte modules. The plan is the session notes' `buildtime/split2/plan.md`. A1 added
`Tools/ModuleMap`, which checks the planned map against today's single module; it changed no public API. This file
holds the judgement calls the work reached that the plan did not already settle, in the format of
[the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>):*

- **A-SP0-n — needs your decision.** Nothing has shipped for these.
- **B-SP0-n — shipped the safe option.** Says what the fuller version would be, and its price.
- **C-SP0-n — declined.** With the reason.

### B. Shipped the safe option

#### B-SP0-1. ViewRenderer stays in TUIBase, and K3 stays a refactor to do

*`Tools/ModuleMap/rules.json`, the `declarations` rule for `Rendering/ViewRenderer.swift`*

Plan §1 lists ViewRenderer under Base's rendering infrastructure. K3 then makes it take its terminal, with no
`Terminal()` default, and moves `renderOnce` to TUIApp.

Once `renderOnce` is pinned to App, nothing in Base uses ViewRenderer. The assigner then pushes it up into
TUIApp, and K3's upward reference disappears. ViewRenderer is now pinned to Base, as the plan says, and K3
stays a scheduled refactor.

**The alternative, and its price.** Let ViewRenderer go to TUIApp, and drop K3:
- It saves K3's refactor: two sites, plus `renderOnce` passing `Terminal()` explicitly.
- A headless renderer would then live only in the POSIX module. Today that matters for nothing: every app links
  TUIApp, and the test target can import it. It would matter for a future Windows console backend or a
  WASI host that wants ViewRenderer without App.

#### B-SP0-2. Twelve pieces of public API stay above their type's module, recorded rather than moved

*`Tools/ModuleMap/rules.json`, `accepted`*

The `public-above` check lists public API placed above the module of the type it belongs to. Plan §4 reviewed
three such placements. One of them, `.safeAreaInset`, it pinned back to Base with a declaration rule, so the check
does not report it. At HEAD there are twelve findings. Each now has its reason in `rules.json`, and the map is
unchanged.
- The plan's other two: `.modal` in Presentation, and `.listStyle` with the row-selection modifiers in Lists.
- `TerminalClient`'s graphics-support API (`graphicsSupported` and its kin) goes to TUIApp. It reads what App's
  startup handshake records. Every app imports App, so no app loses it.
- `.automatic` for the List, Picker and NavigationSplitView styles stays in the leaf. It is usable only through
  the leaf's own modifier.
- `ForEach(_:editActions:content:)` and `ForEach(sections:content:)` stay in Lists.
- The four `SceneStorage` / `AppStorage` inits for tab and table customization stay in Tabs and Tables.

`asAnyView()` sits in its own `extension View` block in the same file as `.modal`, and stays in Base.

**The fuller version, and its price.** Move the sugar down beside the types it names at step A4. That means
`.automatic` beside the default styles in Base, and the graphics-support API split from what reads App's state.
It costs:
- about four more declaration-level placements;
- for the graphics API, an injected value in place of the static it reads.

It gains nothing for an app that uses the leaf: the sugar only works through the leaf's modifier anyway.

#### B-SP0-3. The check reads the committed map, so a new reference is a finding, not a silent move

*`Tools/ModuleMap/modulemap.py check` against `map.json`*

The assigner moves declarations to make the map consistent. Say new code in Base starts using a Lists helper: if
the check re-ran the assigner, the helper would simply come down into Base and nothing would be reported.

Instead, the check reads the committed `map.json`, so that reference is reported as `upward`. Moving the helper
is then a reviewed edit: `assign`, read the diff, `assign --write`. New files and new declarations are placed by
the rules until the next `assign --write`.

**The alternative, and its price.** Run the assigner in CI (`check --fresh`) and report only what it cannot
resolve. There would be fewer findings, but Base would grow silently with every convenience reference, and the
à-la-carte savings in plan §2 would erode without anyone choosing it. The fresh run costs 0.2 s, so this is a
policy choice, not a cost one.

#### B-SP0-4. TerminalHost's `pid_t` signatures are scheduled with K6, not left as a new finding

*`Tools/ModuleMap/rules.json`, `scheduled` K6 and `posix.c_symbols`*

The `posix` check's list lacked `pid_t`, although plan §4's K6 says Windows signatures must not use it. With
`pid_t` in the list, two declarations report it:
- ProcessAncestry, one of K6's two files. Its K6 entry now names `pid_t` beside `getpid`.
- TerminalHost (Rendering/TerminalHost.swift, all of it in TUIBase), which plan §4 does not list. Thirteen
  unguarded uses: the tmux client's `pid` field and the tmux hook and unhook argument builders.

An audit of every C symbol that a declaration outside TUIApp references outside a POSIX-only branch found no
other POSIX-only one; the rest are Foundation, Dispatch and libm. The only POSIX-only ones are `getpid` (K6),
`setenv` (K4) and `pid_t`.

The TerminalHost uses are now a second `scheduled` K6 entry. A2's K6 gives them the same Windows treatment as the
other two files. Until then the check reports them as scheduled, not new.

**The alternative, and its price.** Leave them as a new finding. Every CI run would then raise the same warning
until A2, and `check` would exit 1 on HEAD for everyone. The entry costs nothing to drop if you would rather track
it elsewhere. Either way, K6 in A2 grows from two files to three: TerminalHost needs Windows arms for its tmux
helpers, or a platform-neutral process-id type in their signatures.

## Completing the SwiftUI API: decisions from lane SPA2

*Lane SPA2 implemented step A2 of the module-split plan
(`buildtime/split2/plan.md`, §4 rows K1–K6): six refactors inside today's one
TUI module that remove the references which would point upward — from the
substrate (Base) into a feature leaf or into the POSIX app layer — once the
code is split. Where that work reached a judgement call the plan's rows did not
settle, the safe option shipped and is written up here, in the format of
[the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>):
A for the owner to decide, B for a basic form shipped with its fuller version
priced, C for a refusal recorded in `parity-map.json`. None of these changes
public API; all are internal shape. One public behaviour changed in K2 and
was put back in review round 1: an `OpenURLAction` an app makes itself defers
to the running app's opener again (B-SPA2-6).*

### B. Shipped the safe option

#### B-SPA2-1. Which per-subtree objects get a slot is the map's, not the row's prose

*`FeatureObjectSlot` (K1)*

Row K1's prose lists "navigation coordinator, dialog suppression, search
dismissal and scope keys, list-row edit restrictions". Read per declaration,
the plan's map places five of the objects `detachedFromRuntime()` clears in
leaves — the navigation coordinator (Navigation), the dialog suppression
(Presentation), and the search dismissal, focus offer and scope bar (Search) —
and places `listRowEditRestrictions` and `dismissalGate` in Base.

**Shipped:** five slots, one per leaf-owned object; the two Base-placed
objects stay plain keys, cleared by name.

**The fuller version** is a slot for any object the step-0c re-map moves up
(say `listRowEditRestrictions` to Lists): one enum case, one key, and the
accessor's two lines — ten minutes each, and DetachedFromRuntimeTests already
fails if such an object stops being cleared.

#### B-SPA2-2. Outside any context's services there is no clipboard

*`ClipboardAccess.unavailable` (K2)*

The environment's default clipboard, and a text handler's default argument,
used to run this machine's helpers itself (`ClipboardAccess.system`): a test
rendering a field with no context's services wrote the developer's pasteboard
wherever the test process looked local. With the helpers behind the app layer's
backend, the substrate's default cannot reach them.

**Shipped:** no clipboard — a copy reports `.unavailable`, a paste reads
nothing. Every render a context drives publishes that context's writer
(in memory for every context but the app's), so only a bare test environment or
a hand-made handler meets it, and tests that copy already hand their subtree a
clipboard of their own.

**The fuller version** is an in-memory clipboard as the default too. Its price
is the reason it did not ship: the default is a static value, so it is either
one store the whole process shares (a singleton, which parallel tests would
race over, as they raced over the pasteboard) or a new store per read (each
field its own, and a `PasteButton`, which reads the environment every render,
always empty).

#### B-SPA2-3. A context's in-memory URL opener reports the URL opened

*`InMemoryURLOpener` (K2)*

A deferral to the system opener reaches the opener only where opening URLs is
on (`TerminalURLOpening.isEnabled`); in a headless run or a test with it on,
that is now the context's in-memory opener rather than a real browser.

**Shipped:** it keeps the URL and answers `true`, as an in-memory clipboard
answers a copy `.copied`: the URL went where that context's URLs go.

**The other answer** is `false`, and all it would change is what the
completion form, `openURL(url) { accepted in … }`, reports. A `Link` raises its
destination popover on every activation whatever `open` answers
(`Link.swift`: `open(destination)`, then `showing.wrappedValue = true`, "raised
whether or not `open` 'worked'"), so a link looks the same either way. Nothing
reaches this but a headless run or a test that turned opening on, and the
change is one line; `true` stays because the URL did go where that context's
URLs go.

#### B-SPA2-4. FieldTextLayout carries the selection look and no requirements, and WordBoundary moves down by placement

*`FieldTextLayout`, `FieldSelectionStyle` (K5)*

Row K5: "A small field-text-layout protocol in Base that the TextInput renderer
adopts. WordBoundary (53 lines) and the selection colours move down." What the
screen's selection needs from field text today is one thing: the selection
colours.

**Shipped:** a protocol with no requirements whose extension implements the
colours once; the text inputs' renderer and `ScreenSelection` both adopt it, so
neither names the other. `WordBoundary.swift`, a whole self-contained file,
was not edited: the brief allows no file moves in this step, and the step-0c
re-map places the file in Base.

**The fuller version** gives the protocol requirements — the field's cell
widths, its scroll window, its word rule — so the substrate could lay out a
field's text through it. Nothing in the substrate calls them today, so they
would be dead requirements, and a witness-table call where a focused field's
row now calls a static function.

#### B-SPA2-5. Windows arms in the two files the row names; TerminalHost.swift still names `pid_t`

*`ProcessAncestry`, `ClipboardLocality` (K6)*

Row K6 gives ClipboardLocality.swift and ProcessAncestry.swift Windows arms
like their WASI ones. TerminalHost.swift, also placed in Base, names `pid_t`
too: `TmuxClient.pid`, `owningApplicationPath(ofTmuxClient:)`,
`executablePath(ofProcess:)` and the six builders of tmux hook and unhook arguments.

**Shipped:** the two files the row names. On Windows the walk by process id is
not compiled, `ownCommandNames()` and `tmuxClients()` answer `nil`, and
`ClipboardLocality.isLocal()` answers `false`, so no `pid_t` appears in either
file's Windows signatures. Unverified on Windows: this machine has no Windows
toolchain; the macOS build and the Linux static and WebAssembly cross-compiles
check every other arm.

**The fuller version** gives TerminalHost.swift the same treatment — its tmux
client probe and hook arguments compiled only where `pid_t` exists, with
`nil`/empty Windows arms — so that `pid_t` no longer stands between Base and a
Windows build. About an hour; worth doing when Base becomes an advisory Windows
step (B3).

#### B-SPA2-6. An action no environment handed an opener defers to the running app's

*`TerminalURLOpening.runLoopOpener` (K2, review round 1)*

K2 injects the URL opener per context, and an action gets it by being read
from an environment: the `openURL` getter attaches that environment's opener.
But SwiftUI's `OpenURLAction(handler:)` is public, and an app may make an
action itself and call it directly, from a button's action, a `Task` or a
`DispatchQueue.main` block, where no environment handed it anything. Before
K2 such an action, deferring with `.systemAction` while opening was on,
launched `open`/`xdg-open`. With only the per-context opener it launched
nothing and answered `false`. That is a silent no-op in a running app, and
SwiftUI's documentation puts no condition on it: `systemAction` "asks the
system to open the original URL" (sdoc; what SwiftUI does with a hand-made
action is unmeasured).

**Shipped:** the app's run loop publishes its context's opener for the length
of the run (`AppRunner.publishURLOpener()`, at startup beside the opening
gate, withdrawn when the run ends), and an action that carries no opener
defers to it. Nothing else publishes one, so a headless run, a snapshot and a
test still launch nothing, and an action read from an environment still uses
that context's opener first. It is process-wide, like the `isEnabled` gate it
sits beside, because the callers it serves are exactly the ones no context
reaches. The framework creates nothing for it: the value is the running
context's own opener. It is read only when a deferral reaches the opener,
never per frame.

**The alternatives:**
- A task-local bound around the run loop. It needs no process-wide value, but
  an action called from a `DispatchQueue.main` block (which `App.main()`'s
  documentation invites) or a detached task sees nothing, so the silent no-op
  comes back for them.
- Make this the only route and drop the per-context key
  (`EnvironmentValues.urlOpener`). That removes the root-environment entry
  whose cost K2's A/B is measuring, at the price of row K2's "headless runs and
  tests get an in-memory one" for URLs: a deferral there would answer `false`
  instead of reaching the context's in-memory opener (B-SPA2-3). It is worth
  the owner's look only if that A/B prices the entry above noise.

## Completing the SwiftUI API: decisions from lane SPA3

*Lane SPA3 carried out step A3 of the module-split plan
([revision 4](<The module split.md>), §5 "Runtime and the
annotation tiers"). It annotated the 61 declarations of tier 1 and set L (the session notes'
`buildtime/split2/refine/tiers-A1p/`) with `@inlinable`, in the style that step 0b's probes settled. These are
the hot callables that will cross a module boundary once the code is split. Where that work reached a judgement
call the plan did not settle, the safe option shipped and is written up here, in the format of
[the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>): A for the owner to decide, B for a
basic form shipped with its fuller version priced, C for a refusal recorded in `parity-map.json`. None of this
changes public API or behaviour.*

*The complete record of what A3 annotated is `A3-annotated.json`, beside the tiers: 62 `@inlinable` and 130
`@usableFromInline`, with each declaration and its file:line (the session notes' `SPA3/annotated.py BASE HEAD`
regenerates it). In the source, a comment saying why, with the tag "module split step A3" on one line, sits on
every type, environment key and helper function that A3 made usable from inline code. That includes the four
environment helpers that derive a value rather than read a key (`verticalScrollIndicators(overflowing:)`,
`alwaysShowsVerticalTextIndicators`, `overscrollAllowances(overflowing:)`, `declaredAnchorModes`), and the stored
properties of public types (`SelectionEmphasisClock.environment`). The tag is not repeated where such a comment
already covers a declaration: the members and witnesses of a tagged type (a key's `defaultValue`, an `==`,
`ClaimingRow`'s members), an environment accessor that reads a key carrying it (15 of them), or a sibling the
comment names (`register(in:reportingChangesTo:_:)`, `ANSIRenderer.colorize`, `ForEach.directID`). Public
declarations carry no tag in their doc comments, which ship in DocC; `Text.init<S>` explains itself in a `//`
comment in its body. So a grep for the tag finds every comment that explains an annotation (91 of the 192
declarations carry one directly), and the JSON lists every annotation. The session notes' `SPA3/r2/tagcover.py`
checks each of these rules against the source, and fails on an annotation that none of them covers.*

### B. Shipped the safe option

#### B-SPA3-1. Focus and mouse registration are annotated in full, though -O inlines neither even inside one module

*`FocusRegistration.register(context:handler:focusID:)`, `MouseEventDispatcher.register(in:_:)`*

**Shipped.** The plan's form:
- Both declarations are `@inlinable`.
- Everything their bodies reach is `@usableFromInline`: 20 declarations for the focus registration (the enum
  itself included, two of them `package` in TUIView), and 2 for the mouse one (`registerInterned`, until now
  `private`, and `MouseHandlerLane`).
- One thing the focus registration reaches stays internal: `PersistedFocusable`. `register` re-points a persisted
  handler at its declared id through an out-of-line `@usableFromInline` `repointPersistedHandler(_:to:)`, not
  inline. Usable from inline code, the protocol's settable `focusID` cost every app a dynamic exclusivity check
  per persisted control per frame (the last finding below).

**Measured** in a release (-O, whole-module) build of the tree before A3, by disassembling TUI's objects:
- `FocusRegistration.register` is an out-of-line function of 389 instructions, called from 35 functions.
- `register(in:_:)` is 115 instructions, called from 30 functions. That count includes `registerInterned`, which
  was inlined into it.
- The optimiser inlines neither into its callers within the module. A caller in another module that has the body
  would most likely decide the same way, but that is unmeasured: carving and measuring a module is not allowed
  on this disk.

**What the annotation changed inside the module** (the same comparison, after A3):
- `registerInterned` now has public linkage.
- `register(in:_:)` became a 5-instruction wrapper.
- The inliner's choices around it moved:
  - `_TabViewCore.attachTabInteractions`, `_ScrollViewCore.attachIndicatorMouseHandlers` and
    `GestureAttachment.renderToBuffer` grew by 111, 111 and 92 instructions: `registerInterned`'s body is
    inlined there now.
  - `DropdownMenu.popup` shrank by 561 instructions.
  - `HelpModifier` calls `registerInterned` directly.

**The leaner version, and its price.** Leave these two declarations un-annotated, so each stays one ordinary
call per control per render, which is what -O makes of it today. Or make each an `@inlinable` measure-pass guard
over an out-of-line `@usableFromInline` body.
- Gained: 22 declarations stay internal (`repointPersistedHandler` would not need to exist), and the inlining
  around mouse registration stays as it was.
- Lost: whatever a client module's inliner would do with the full body. By the measurement above, probably
  nothing.
- The coordinator's A/B of A2 + A2′ + A3 shows whether the inlining shifts matter. If they do not, this is a
  clean-up for a later step, not a revert.

#### B-SPA3-2. TextField's key initializer ends in a concrete core, rather than exporting the field's storage

*`TextField.init(_: LocalizedStringKey, text:)`*

**Shipped.** A pure refactor came first, in its own commit. All four `Label == Text` initializers (two key, two
`StringProtocol`) end in one internal `init(verbatimTitle:text:prompt:)`. The key initializer is `@inlinable`,
and the core is `@usableFromInline` and out of line. This is the shape 0b's probe t13f/g proved for
`Text.init<S>`, which now delegates to `init(verbatim:)` the same way. Annotated as it was, the key initializer
would have called the generic `init<S>(_:text:)` unspecialised from another module.

**The fuller version, and its price.** Make `init<S>(_:text:)` `@inlinable` too, writing the fields itself, so a
client can specialise `TextField(name, text: $value)` with a `String` variable.
- It would export all ten stored properties, and `_FieldValueFormatting` and `_TextSelectionChannel` as well,
  which then lose their implicitly inferred `Sendable`.
- `init<S>(_:text:)` is not in tier 1 or set L, so it belongs to tier 2's A/B-gated pass.

#### B-SPA3-3. Four declarations outside the list are `@inlinable` too, where `@usableFromInline` alone would cost

*`ForEach.init(storing:id:directID:content:)`, `HandlerDrawing.reportingChanges(to:around:)`,
`SelectionEmphasisClock.init(environment:)`, `ResolvedScrollIndicators.init(bar:text:)`, and `ClaimingRow.init()`
(which is in the list)*

The rule in RESULTS-0b is that whatever an inlinable body touches must be `@usableFromInline`. Two of the
declarations touched are generic: the internal initializer both `ForEach` initializers end in, and the method the
inlined `register(in:reportingChangesTo:_:)` calls with its own `Drawn`. Left as `@usableFromInline` only, a
client would specialise the outer call and then make an unspecialised generic call inside it, which is the cost
tier 1 exists to remove. Both are small, so they are `@inlinable`.

The three initializers had been implicit, and an implicit initializer can be neither `@usableFromInline` nor
`@inlinable`. They are now spelled out, unchanged, and `@inlinable`.

**The alternative.** Leave the two generic callees as `@usableFromInline` and accept the unspecialised inner
calls until tier 2. That saves nothing measurable: their bodies are 4 and 3 statements.

### Findings for the later tiers (not decisions)

- **`@inlinable` on a member of an internal type that is not itself `@usableFromInline` raises nothing on Swift
  6.2.4, and the body goes unchecked.** `FocusRegistration.register` compiled as `@inlinable` until its enum got
  `@usableFromInline`, and then raised 20 errors. Every type whose members A3 annotated is now public or
  `@usableFromInline`. Set T's and tier 2's annotations should be checked the same way.
- **A type that becomes `@usableFromInline` loses its inferred `Sendable`, and so does every type that stores
  one.** The compiler infers `Sendable` only for types that are not usable from inline code.
  `SelectionContextMenuReference` and `ResolvedScrollIndicators` state it, because without it their
  `static let`s stopped compiling. Four more lost it silently, because nothing asked yet: `ClaimingRow` (and with
  it `ScrollIndicatorLine`, which stores one), `ScrollAnchorMode`, `MouseHandlerLane` and `HandlerDrawing`. They
  state it now, and `UsableFromInlineSendabilityTests` requires it of all seven at compile time. State it
  whenever a value type becomes usable.
- **An environment key that becomes `@usableFromInline` needs its `defaultValue` `@usableFromInline` as well.** A
  usable type's witness to a public protocol's requirement must be usable too. The same goes for an `Equatable`
  `==`.
- **Inside the monolith A3 is not codegen-neutral at -O.**
  - `@usableFromInline` gives a declaration public linkage. A single-caller private helper is then no longer
    folded into its caller and deleted, and the accessors are emitted out of line.
  - Release build of the Stress product: `__text` +20,564 bytes (+0.22%), stripped binary +53,280 bytes
    (+0.41%), exported symbols +655.
  - Across the TUI objects, 485 functions outside the accessors' own family changed. 192 of them changed
    size, the largest the mouse-registration paths in B-SPA3-1 and `Text.init<S>`'s and TextField's
    specialisations, which shrank as B-SPA3-2 intended.
  - The other 293 kept their size. What changed in them, in the samples read, was a mangled name, a `#line`
    constant moved by the new doc comments, or a data reference to a newly exported symbol (a key's metadata,
    `ANSIRenderer.reset`), which the objects now load through the GOT (`adrp` + `ldr`, where it was `adrp` +
    `add`). The linker relaxes those again: in the linked Stress executable, the sample read
    (`RenderContext.makeGeometryAsk(role:)`, which reads `MouseEventDispatcherKey`) is `adrp` + `add`, as before.
  - **56 functions that existed before A3 gained a call to `swift_beginAccess`**, a dynamic exclusivity check
    (the session notes' `SPA3/r1/ba2.py`, over the same disassembly):
    - 30 are `focusID` witnesses (getter and setter) of 15 persisted focus handlers: getter 11 → 18 instructions,
      setter 4 → 20. Another 16 such witnesses (`modify`, one for each of those 15 and `ScrollViewHandler`) are
      new symbols. This was a new cost, and the fix round removed it (below).
    - 15 lost a call to a TUI function that made the check: 14 mouse-registration paths, through
      `registerInterned` or `register<A>(in:reportingChangesTo:_:)`, and a specialisation of
      `FocusManager.register(_:inSection:)`. The check moved into the caller with the inlining, so it is not a new
      cost.
    - 10 are render functions that lost a call to TUIView's `RenderContext.recordingEffectJournal` getter, which
      is now usable and so inlined into them. The check most likely came with it, so these are not a new cost
      either; unmeasured, because the getter's own code is in TUIView's objects, which the comparison did not
      cover.
    - 1 is `specialized debugFocusLog(_:)`.
  - **The witnesses' checks came from `PersistedFocusable` being `@usableFromInline`.** A settable requirement of a
    protocol usable from inline code hands every conformer's stored property to callers the whole-module
    optimiser cannot see, so it keeps the check. A probe (`SPA3/probe/r2`: a public `Focusable`, a settable
    `PersistedFocusable` refining it, two handlers, an `@inlinable` register) shows 4 checks in the `focusID`
    witnesses with the protocol usable, and none with it internal and the re-pointing out of line, as before A3.
    The fix round shipped that shape (B-SPA3-1). The whole-module disassembly after the fix is owed with the A/B:
    this lane may not build release.

### Corrections

- **Five of A3's commit messages say A3 is codegen-neutral inside the monolith**: the ones annotating tier 1's
  environment accessors, the Lists group's environment reads, focus and mouse registration, `ClaimingRow`, and
  `publishingContainerSize` with `onTapGesture` ("Inside one module nothing changes", "codegen-neutral inside the
  monolith"). That is wrong. The -O comparison above measured the opposite: accessors emitted out of line,
  symbols loaded through the GOT in the objects, `__text` +0.22%, and the exclusivity checks. The messages stay
  as they are, because the history is not rewritten. This file is the correction.
- `AssignedFocusID.claim(_:)` was made `@usableFromInline` for the `@inlinable` `register`, which never
  calls it: it only asks whether an id is on offer. The attribute is gone. The focus count in B-SPA3-1 is 20,
  where the first version of this file said 21: `claim(_:)` and `PersistedFocusable` left it, and
  `repointPersistedHandler(_:to:)` joined it.
- The commit that first wrote the tag paragraph above says 19 of the untagged annotations are "environment
  accessors whose key carries it". Four of the 19 read no key: `verticalScrollIndicators(overflowing:)`,
  `alwaysShowsVerticalTextIndicators`, `overscrollAllowances(overflowing:)` and `declaredAnchorModes`. Nothing
  tagged said why `alwaysShowsVerticalTextIndicators` is `@inlinable`, or why `SelectionEmphasisClock.environment`
  is `@usableFromInline`, so a grep for the tag never explained them. All five carry the tag now.
- The commit that removed the `focusID` witnesses' checks says the 30 existing witnesses belong to 16 persisted
  handlers, and that 24 of the 36 new symbols with a check are `focusID` `modify` witnesses. It is 15 handlers
  and 16 witnesses. `ScrollViewHandler` has only a new `modify` witness with a check, and the other 8 of the 24
  are specialisations of `register(context:handler:focusID:)` and its callees, which matched on the argument
  label. The same count in this file said 16 and 24 too (`SPA3/r1/ba2.py` now prints both groups).

## Completing the SwiftUI API: decisions from lane SPB1

*Lane SPB1 took step B1 of the module split
([`Module split plan, revision 4`](<The module split.md>),
§5), 2026-10-08: the target that compiles every planned module became
`TUIFoundation`, and `TUI` became an umbrella that only re-exports. It
changed no public API: `import TUI` gives an app what it gave before. This
file holds the judgement calls the step reached that the plan did not already
settle, in the format of
[the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>):*

- **A-SPB1-n — needs your decision.** Nothing has shipped for these.
- **B-SPB1-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPB1-n — declined.** With the reason.

### B. Shipped

#### B-SPB1-1. TUIFoundation re-exports the four lower modules

*Module structure — no API*

The single TUI module's `Exports.swift` `@_exported import`ed TUICore,
TUIStyling, TUIView and TUIImage. Within a module, those re-exports
put the lower modules' names in scope in every file of it, and the framework's
files lean on that: 482 of the 900 files B1 moves into TUIFoundation import
none of the lower modules, and most of them name `FrameBuffer`,
`RenderContext` or `Color` (counted 2026-10-08 with a grep for an
`import TUICore|View|Styling|Image` line; how many of the 482 use a lower
name was not counted).

**Shipped: `Sources/TUIFoundation/Exports.swift` re-exports the same four,**
so every file of TUIFoundation sees what it saw before, and the umbrella's
`Exports.swift` re-exports TUIFoundation and the four again (it must go on
giving them after TUIImage leaves TUIFoundation at step B5c). This is
the plan's own assumption (§4: "each module `@_exported`-imports its direct
dependencies", plan question Q4), applied to TUIFoundation now rather than
at the per-module products step, because B1 cannot compile without it or the
imports below.

**The other version:** no re-export, and an explicit import in each file that
uses a lower module, as MemberImportVisibility asks of members already.
**Price:** an import line or two in up to 482 files now, and the same kind of
edit at each carve that moves a file to a module whose dependencies differ;
and `import TUIFoundation` alone would no longer give an importer the
lower modules, which no app can do today anyway (TUIFoundation is not a
product). Nothing user-visible changes either way, so it can be revisited at
step C9b, with the per-module products.

#### B-SPB1-2. Swift Package Index documents each library module on its own

*Documentation hosting — no API*

Swift Package Index (SPI) hosts the documentation the project template links
to (`swiftpackageindex.com/wadetregaskis/TUIkit/main/documentation/tui`,
in `project-template/tuikit` and `project-template/README.md`). It does not
run `Tools/BuildDocs/build-docs.sh`: it runs `generate-documentation` for each
target `.spi.yml`'s `documentation_targets` names, one archive per target,
behind a selector whose first entry is the landing page (SPIManifest's
"Common use cases" page, read 2026-10-08). The list named only `TUI`. That
archive already lacked the lower modules' types (`View`, `Color`, `Binding`);
since B1 the umbrella declares nothing, so it would hold the catalog's
articles and no API at all.

**Shipped: `.spi.yml` lists `TUI` first, then `TUIFoundation`,
`TUIView`, `TUIStyling`, `TUICore` and `TUIImage`,** every module
of `unify_symbol_graphs.py`'s `MODULES`. The landing page and the template's
link stay the umbrella's (its articles; its links to symbols render as plain
text, as the links to the lower modules' types already did), and every public
symbol is documented, under the module that declares it. A new
`Tools/BuildDocs/check_spi_targets.py`, run first by `build-docs.sh` (so by
CI's docs job), fails when the list lacks a module of `MODULES` or does not
start with the umbrella. Unmeasured: SPI's build of the new list (it runs only
on SPI, after a push); the selector and the per-target archives are SPI's
documented behaviour.

**Price:** the reader sees the module structure the unified build hides
(`Tools/BuildDocs/README.md`: "leaks exactly the structure we want hidden"),
and must know which module declares a type to find its page there; each carve
adds a module to the list and to the selector.

**The other version:** one reference, as `build-docs.sh` builds it. SPI
cannot build that archive, but `.spi.yml` can point at one hosted elsewhere
(`external_links: documentation: <url>`, in place of the builder's
`documentation_targets`): the CI docs job already builds it with
`--static-hosting`, and would gain a publish step (GitHub Pages, say).
**Price:** a publish step to write and the hosting to switch on, which is the
owner's to do; the template's link would change to that host (or SPI's page
would link through to it).

## Completing the SwiftUI API: decisions from lane SPB2

*Lane SPB2 took step B2 of the module split
([`Module split plan, revision 4`](<The module split.md>),
§5), 2026-10-08: the first carve, in which TUIStrings and TUITerminalHost
leave TUIFoundation for targets of their own. It changed no public API:
TUIFoundation re-exports both, so `import TUI` gives an app what it gave
before, and an app's `TUI.X` reaches their types through two re-exports
(`UmbrellaQualifiedNameTests`). An app can still see three things, which every
carve changes; they are listed under [What an app can
see](#what-an-app-can-see). This file holds the judgement calls the step
reached that the plan did not already settle, in the format of
[the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>):*

- **A-SPB2-n — needs your decision.** Nothing has shipped for these.
- **B-SPB2-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPB2-n — declined.** With the reason.

### What an app can see

These are not judgement calls: the plan (§5, row C9a) lists all three for the
release notes, and C9a writes them. They are recorded here because this step
made them. Each name below was `TUIFoundation`'s after step B1, and
`TUI`'s in v0.6.0.

- **Reflected names.** `String(reflecting:)`, `dump` and the debugger name a
  moved type's new module: `TUIStrings.LocalizationService.Language`,
  `TUIStrings.SystemFormatStyle.Timer`, `TUITerminalHost.TerminalClient`.
  `UmbrellaQualifiedNameTests` pins these three.
- **The resource bundle** is `TUI_TUIStrings.bundle`. An app run from
  its build directory finds it there, as before. An app shipped with the bundle
  copied beside its executable must copy it under the new name. SwiftPM's
  generated `Bundle.module` looks beside the main bundle, then in the build
  directory, and stops the process (`fatalError`) if neither holds the bundle.
  That happens at the first translation the framework looks up, or the first
  read of `tuiKitVersion`. (Read in the generated
  `resource_bundle_accessor.swift`, macOS, debug build.) Since lane BNDL
  (e5445e2cd) the missing bundle no longer stops the process: TUI looks for
  its bundle itself, never through `Bundle.module`, and without it reads its
  own words in English and its version as "unknown" (README, "Shipping a
  program"; decisions BNDL).
- **A saved `NavigationPath.CodableRepresentation`** stores each value's type
  by its mangled name, which names the declaring module. So a saved path
  holding `LocalizationService.Language` or one of the four `SystemFormatStyle`s
  (`Timer`, `Stopwatch`, `DateReference`, `DateOffset`) no longer decodes: it
  throws `DecodingError`, as `codable`'s documentation says. These are the only
  `Codable` public types that moved; TUITerminalHost declares none.
  `NavigationPathCodableTests` pins the module name a saved path now holds.

### B. Shipped

#### B-SPB2-1. TerminalHost.swift spells a tmux client's pid `Int32`, not `pid_t`

*`TerminalHost.TmuxClient.pid`, the tmux hook builders — internal, no API*

Step B2 makes TUITerminalHost an advisory step of the Windows lane, and
decisions B-SPA2-5 left `TerminalHost.swift` naming `pid_t` outside any `#if`:
the tmux client's `pid`, `owningApplicationPath(ofTmuxClient:)`'s parameter,
the parse of `#{client_pid}`, and the six builders of hook and unhook
arguments. Windows' C runtime declares no `pid_t` (the premise
`ProcessAncestry.swift` already rests on), so the file could not compile there.

**Shipped: those signatures take `Int32`.** It is the type `pid_t` aliases on
every platform that has one (Darwin, Glibc, Musl, WASI) and the type
`ProcessInfo.processIdentifier` has everywhere, so nothing changes where the
file compiled before: the hook installers lose their `pid_t(pid)` conversions,
and the tests spell their expected pids `Int32`. Only the Darwin walk (the
tmux client's ancestry, `executablePath(ofProcess:)`) still reads a `pid_t`,
inside the `#if canImport(Darwin)` arms it already had. Unmeasured on Windows:
this machine has no Windows toolchain, so the CI lane is the first build there.

**The other version** is B-SPA2-5's: compile the tmux client probe and the hook
builders only where `pid_t` exists, with `nil` and empty Windows arms. It
keeps the POSIX type's name at the cost of four `#if` arms and a TmuxClient
whose stored layout differs by platform, for a probe that never runs on
Windows (`isTmux` reads `TMUX`, which no Windows terminal sets). About an hour,
if the name is wanted back.

#### B-SPB2-2. The carved modules' tests stay in TUITests, which `@testable import`s them

*Test layout — no API*

The lower four modules each have a test target that links only that module
(`TUICoreTests` and the rest), so a unit test that leans on a higher layer
does not compile. B2 made TUIStrings and TUITerminalHost modules of the
same kind, and their tests live in `TUITests` beside everything else.

**Shipped: the tests stay where they are.** The 35 test files that reach
either module's internals gained `@testable import TUIStrings` (17) or
`@testable import TUITerminalHost` (18), next to their
`@testable import TUIFoundation`, and `TUITests` names both modules as
dependencies. What the framework itself now reaches across the new boundary is
`package` instead; a test reaching an internal member (an initializer such as
`LocalizationService(configDirectoryPath:)`, a `@TaskLocal` pin such as
`TerminalClient.$drawsBoldPin`) does so through `@testable`, so no declaration
was widened for a test alone.

**The other version:** `TUIStringsTests` and `TUITerminalHostTests`,
each linking only its module and TUICore, with a row each in
`Tools/validate-test-boundaries.sh` and an advisory Windows build like the
lower modules' test targets. **Price:** sorting the 35 files, and more where a
suite also renders (`RendersEnglishUI` and the localized-render suites use the
umbrella's render helpers, so they would stay); how many of the 35 use only
their module was not counted. Two more test bundles to build and link. Worth
doing with the per-module products (step C9b), or when a Windows test build of
these modules is wanted.

## Completing the SwiftUI API: decisions from lane SPB3

*Lane SPB3 took step B3 of the module split
([`Module split plan, revision 4`](<The module split.md>),
§5), 2026-10-08: the carve of TUIApp, the first module built on
TUIFoundation rather than under it. It changed no public API: the umbrella
re-exports TUIApp beside TUIFoundation, so `import TUI` gives an app
what it gave before, and an app's `TUI.X` reaches TUIApp's types through
one re-export (`UmbrellaQualifiedNameTests`). What an app can still see is
listed under [What an app can see](#what-an-app-can-see). This file holds the
judgement calls the step reached that the plan did not already settle, in the
format of [the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>):*

- **A-SPB3-n — needs your decision.** Nothing has shipped for these.
- **B-SPB3-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPB3-n — declined.** With the reason.

### What an app can see

Not judgement calls: the plan (§5, row C9a) lists these for the release notes,
and C9a writes them. They are recorded here because this step made them. Each
name below was `TUIFoundation`'s after step B1, and `TUI`'s in v0.6.0.

- **Reflected names.** `String(reflecting:)`, `dump` and the debugger name a
  moved type's new module: `TUIApp.WindowGroup<TUIFoundation.Text>`,
  `TUIApp.DefaultWindowToolbarStyle`. `UmbrellaQualifiedNameTests` pins
  both.
- **`renderOnce(content:)` is TUIApp's** (the plan names it for C9a).
  `TUI.renderOnce` and the unqualified name resolve as before.
- **The bundle and saved paths are unchanged.** TUIApp holds no resources,
  so the bundle is still `TUI_TUIStrings` (decisions SPB2); and it
  declares no `Codable` public type, so no saved
  `NavigationPath.CodableRepresentation` changes.

### B. Shipped

#### B-SPB3-1. Tests reach TUIApp's internals through `@testable import TUIApp`, in 479 files

*Test layout, and where `EnvironmentValues.applyRuntimeServices(from:)` lives — no API*

B-SPB2-2 kept the carved modules' tests in `TUITests`, each file that
reaches a carved module's internals gaining `@testable import` of it. Step B3
follows that pattern, at a larger scale: 478 files of `TUITests` and one of
`ExampleTests` (which now names TUIApp as a dependency) gained
`@testable import TUIApp`, found from the pre-carve index (every test file
that names a non-public declaration of a `Sources/TUIApp` file) and
confirmed by the build. No declaration was widened for a test alone.

300 of the 479 need TUIApp for one method only:
`EnvironmentValues.applyRuntimeServices(from:)`
(`Sources/TUIApp/Environment/ServiceEnvironment+Runtime.swift`), which wires
a `TUIContext`'s services into an environment, and which those tests call to
build the environment a render pass reads. The module map puts it in TUIApp
because its two framework callers, `RenderLoop` and `ViewRenderer`, are
TUIApp's, although everything it reads and writes is TUIFoundation's.

**Shipped: the map as it stands.** The method stays in TUIApp, internal.

**The other version:** move `ServiceEnvironment+Runtime.swift` (69 lines) to
`Sources/TUIFoundation/Environment/` with a `package` method, so only the
179 test files that reach the run loop itself (`HeadlessApp`, `RenderLoop`,
`InputHandler`, `FrameDiffWriter`, `Terminal` …) import TUIApp. **Price:**
a `git mv`, one widened method, the module map re-run (the file has no other
dependents), and dropping the 300 imports; about an hour. The run loop's
once-a-frame call would then cross into TUIFoundation, where today it
stays in TUIApp (one call a frame; not measured). Worth doing if the
import count bothers anyone; it moves nothing an app sees.

## Completing the SwiftUI API: decisions from lane SPB4

*Lane SPB4 took step B4 of the module split
([`Module split plan, revision 4`](<The module split.md>),
§5), 2026-10-08: the carve of TUIColorPicker, the second module built on
TUIFoundation rather than under it, after TUIApp. It changed no public
API: the umbrella re-exports TUIColorPicker beside TUIApp and
TUIFoundation, so `import TUI` gives an app what it gave before, and an
app's `TUI.X` reaches its types through one re-export
(`UmbrellaQualifiedNameTests`). What an app can still see is listed under
[What an app can see](#what-an-app-can-see). This file holds the judgement
calls the step reached that the plan did not already settle, in the format of
[the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>):*

- **A-SPB4-n — needs your decision.** Nothing has shipped for these.
- **B-SPB4-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPB4-n — declined.** With the reason.

### What an app can see

Not judgement calls: the plan (§5, row C9a) lists these for the release notes,
and C9a writes them. They are recorded here because this step made them. Each
name below was `TUIFoundation`'s after step B1, and `TUI`'s in v0.6.0.

- **Reflected names.** `String(reflecting:)`, `dump` and the debugger name a
  moved type's new module: `TUIColorPicker.ColorPicker`,
  `TUIColorPicker.ColorPickerPanel`, `TUIColorPicker.ToneCurveEditorPanel`.
  `UmbrellaQualifiedNameTests` pins all three.
- **The bundle and saved paths are unchanged.** TUIColorPicker holds no
  resources (its labels come from TUIStrings' tables, through
  `LocalizationService`), so the bundle is still `TUI_TUIStrings`
  (decisions SPB2); and it declares no `Codable` type, public or not, so no
  saved `NavigationPath.CodableRepresentation` changes.

### B. Shipped

#### B-SPB4-1. TUIColorPicker names TUIImage as a dependency, and re-exports it

*Package.swift and `Sources/TUIColorPicker/Exports.swift` — no API*

The plan's map gives TUIColorPicker every lower module ("all (uses
Image)": `rules.json` has no `lower` list for it), and the step's brief asked
for an explicit TUIImage edge only if that list said so. It says nothing
either way, and TUIFoundation re-exports TUIImage today, so the module
would build on TUIFoundation alone.

**Shipped: the edge is explicit.** `.target(name: "TUIColorPicker",
dependencies: ["TUIFoundation", "TUIImage"])`, and its Exports.swift
`@_exported import`s both, as plan §4 (Q4) has each module re-export its
direct dependencies. Three reasons, all checked in the tree: the two curve
editors `import TUIImage` themselves; TUIImage's `ASCIIToneCurve`
(`Sources/TUIImage/ASCIIToneCurve.swift`) is in their public initializers
(`ToneCurveEditorPanel(stops:isPresented:)` takes `[ASCIIToneCurve.Stop]`,
`ChannelCurveEditorPanel(channels:isPresented:)` an `ASCIIToneCurve.Channels`),
so `import TUIColorPicker` alone must give an app that type; and step B5c
removes TUIImage from TUIFoundation's dependencies (plan §5), at which
point the transitive route goes away. TUIAppKit, the other target built on
TUIFoundation that uses TUIImage directly, already names both.

**The other version:** `dependencies: ["TUIFoundation"]` and one
re-export, leaving B5c to add the edge. **Price:** nothing now, and one more
line for B5c to remember. The explicit edge orders nothing new: TUIImage
already builds before TUIFoundation, which depends on it, so
TUIColorPicker's job starts at the same point either way.

## Completing the SwiftUI API: decisions from lane SPB5

*Lane SPB5 took step B5 of the module split
([`Module split plan, revision 4`](<The module split.md>),
§5), 2026-10-08: the carve of the Navigation group, the third module built on
TUIFoundation rather than under it, after TUIApp and TUIColorPicker,
and the first coarse group: one target, TUINavigation, that compiles two
planned modules' directories, `Sources/TUINavigation` and
`Sources/TUIPresentation`, until step C1 peels the second into a target of
its own. It changed no public API: the umbrella re-exports TUINavigation
beside TUIFoundation, so `import TUI` gives an app what it gave before.
This file holds the judgement calls the step reached that the plan did not
already settle, in the format of
[the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>):*

- **A-SPB5-n — needs your decision.** Nothing has shipped for these.
- **B-SPB5-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPB5-n — declined.** With the reason.

### What an app can see

Not judgement calls: the plan (§5, row C9a) lists these for the release notes,
and C9a writes them. They are recorded here because this step made them. Each
name below was `TUIFoundation`'s after step B1, and `TUI`'s in v0.6.0.

- **Reflected names.** `String(reflecting:)`, `dump` and the debugger name a
  moved type's new module: `TUINavigation.NavigationPath`,
  `TUINavigation.NavigationSplitViewVisibility`. That includes the types
  of `Sources/TUIPresentation`, which compile into TUINavigation until
  step C1: `TUINavigation.Alert<TUIFoundation.Button>`,
  `TUINavigation.PresentationDetent`. Those names change again at C1, to
  `TUIPresentation.`, so the release notes should give the C1 name for a
  presentation type if C1 ships in the same release. `UmbrellaQualifiedNameTests`
  pins all four.
- **Saved navigation paths.** `NavigationSplitViewVisibility` is the one
  public `Codable` type of the two directories. A
  `NavigationPath.CodableRepresentation` stores each value's mangled type
  name, so a saved path holding one names TUINavigation now, and a path
  saved between steps B1 and B5 (naming TUIFoundation) no longer decodes.
  `NavigationPathCodableTests` pins the new name, and `NavigationPath.codable`'s
  doc comment lists it among the types that moved. Paths holding only an
  app's own types, the usual case, are unaffected.
- **The bundle is unchanged.** Neither directory holds a resource (both hold
  Swift files only; the alerts' and dialogs' labels come from TUIStrings'
  tables through `LocalizationService`), so the bundle is still
  `TUI_TUIStrings` (decisions SPB2).
- **The documentation lists the group's modifiers on `View` and on the
  group's own types, not on TUIFoundation's.** `symbolgraph-extract` copies
  a protocol extension's members onto the conforming types of its own module
  only. So `Text`'s page no longer lists `sheet(isPresented:onDismiss:content:)`
  among its default implementations, while `View`'s and `NavigationStack`'s
  pages still do, and so does `Text`'s for TUIFoundation's
  `popover(isPresented:attachmentAnchor:arrowEdge:content:)` (checked in the
  strict docs build's archive, 2026-10-08). The archive has 63,396 pages
  against step B4's 69,823, on the same tree but for this step; how many of
  the 6,427 are such copies was not counted. Two doc links had resolved only
  through those copies and now name their declaring type
  (`PopoverPresentationModifier.swift`, `NavigationSplitViewStyle+Variants.swift`).
- **`import TUIColorPicker` brings the navigation containers too**, once
  per-module products ship: it re-exports TUINavigation, its new direct
  dependency (its panels are `Dialog`s presented through `.modal`). After C1
  it re-exports TUIPresentation instead. Under the umbrella, which is the
  only product today, nothing changes.

### B. Shipped

#### B-SPB5-1. Tools/ModuleMap checks a coarse group's members as the modules the map plans

*`Tools/ModuleMap` (its README's "Coarse groups") — no API, no code*

The step's brief asked that the module map's upward, witness and lower checks
treat the group as one compile unit until C1, since `map.json` still gives the
files under `Sources/TUIPresentation` to TUIPresentation while they
compile into TUINavigation.

The checks have never modelled targets. They hold every planned module to the
planned map, including the fifteen that TUIFoundation still compiles as one
module, and a group is the same case at a smaller scale. For a group that is
stricter than the build and never looser: the group's target sees everything
its members' planned dependencies give them (TUIPresentation's edge to
TUIChrome is satisfied inside TUIFoundation until step B5b), so what
passes the checks compiles. The only findings a one-unit view would remove are
edges between the two members. Those compile in the group, but step C1 would
have to break each of them before it could peel TUIPresentation. On this
tree there are none: `check` reports 0 new findings before and after the
carve, and `assign` moves no declaration.

**Shipped: no change to the checks.** The README documents how the tool reads a
group: the index's units name the group's target, which the tool reads like any
module of the map; a member's file that the group's `sources:` leaves out is an
`uncompiled` finding; and an edge between members stays a finding. Steps B6
and B7 need nothing more here.

**The other version:** a `groups` entry in `rules.json` (`{"TUINavigation":
["TUIPresentation"]}`), with `Rules.sees` answering yes between members
until the entry is removed at the peel, so that `upward`, `witness` and `lower`
treat the group as one module. **Price:** about 20 lines in `rules.py` and the
three checks, two unit tests, and one entry per group. The cost is that, until
C1, a reference from `Sources/TUINavigation` to `Sources/TUIPresentation`
(or back) passes CI. C1 then has to break that edge, or keep the two modules
together, which the plan's map does not allow. Worth taking only if the owner
wants the coarse stage to allow such edges.

#### B-SPB5-2. The group's target lists every other directory under Sources in `exclude:`

*Package.swift — no API*

A target with `path: "Sources"` and a `sources:` list still sees every other
file under `Sources`, and SwiftPM reports each one it does not compile as
unhandled ("found N file(s) which are unhandled", a warning). This was checked
on a three-target probe package, and TUIFoundation's own comment says the
same. So TUINavigation's target names its two directories in `sources:` and
the other 31 in `exclude:`, as TUIFoundation does.

**Shipped: the literal list.** It stays fixed until C1 (the carves of B5b, B5c,
B6 and B7 exclude directories it already excludes). Only a new directory under
`Sources` changes it, and the zero-warnings gate catches one that is left out.

**The other version:** one list of `Sources`' directories at the top of the
manifest, with each `path: "Sources"` target excluding the complement of its
own `sources:` (TUIFoundation's too, and B6's and B7's groups). **Price:**
reworking TUIFoundation's declaration as well as the new one, in a pure
refactor commit first. It pays off once B6 and B7 have added two more
31-entry lists, and either step can do it then.

## Completing the SwiftUI API: decisions from lane SPB5b

*Lane SPB5b took step B5b of the module split
([`Module split plan, revision 4`](<The module split.md>),
§5), 2026-10-09: the carve of three leaves built on TUIFoundation, each a
module of the plan's map and a target of its own, not a coarse group:
TUIChrome (`Sources/TUIChrome`: the status bar view, toolbars,
notifications, tooltips and `.help`, the window chrome host, the overlay
compositor, the screen selection's highlight and Copy menu), TUIEffects
(`Sources/TUIEffects`: transitions, content transitions, `.symbolEffect`,
`.visualEffect`, `.scrollTransition` and the colour effects) and TUIMenus
(`Sources/TUIMenus`: `Menu`, `ControlGroup`, `.contextMenu`, `.menuStyle`
and the menu styles). It changed no public API: the umbrella re-exports all
three beside TUIFoundation, so `import TUI` gives an app what it gave
before. This file holds the judgement calls the step reached that the plan did
not already settle, in the format of
[the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>):*

- **A-SPB5b-n — needs your decision.** Nothing has shipped for these.
- **B-SPB5b-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPB5b-n — declined.** With the reason.

### What an app can see

Not judgement calls: the plan (§5, row C9a) lists these for the release notes,
and C9a writes them. They are recorded here because this step made them. Each
name below was `TUIFoundation`'s after step B1, and `TUI`'s in v0.6.0.

- **Reflected names.** `String(reflecting:)`, `dump` and the debugger name a
  moved type's new module: `TUIChrome.StatusBar`,
  `TUIChrome.NotificationService`, `TUIChrome.ToolbarItem<…>`,
  `TUIEffects.AnyTransition`, `TUIEffects.ScrollTransitionPhase`,
  `TUIMenus.Menu<…>`, `TUIMenus.MenuOrder`. `UmbrellaQualifiedNameTests`
  pins one from each module. The plan's map moves no type between these
  modules later, so these names are final.
- **Saved state is unaffected.** None of the three declares a `Codable` type.
  Three of their public types are `Hashable` (`TransitionPhase`,
  `ScrollTransitionPhase`, `MenuOrder`) and so can be values of a
  `NavigationPath`, but a path holding one has no `codable` representation,
  which is the only saved form that stores type names (decisions SPB5, "Saved
  navigation paths").
- **The bundle is unchanged.** The three directories hold Swift files only, so
  the bundle is still `TUI_TUIStrings` (decisions SPB2).
- **The documentation lists the three modules' modifiers on `View` and on
  their own types, not on TUIFoundation's.** As at steps B5 and B6:
  `symbolgraph-extract` copies a protocol extension's members onto the
  conforming types of its own module only, so `Text`'s page no longer lists
  `toolbar(content:)`, `help(_:)`, `transition(_:)`, `contextMenu(menuItems:)`
  or `menuStyle(_:)` among its default implementations, while `View`'s page
  still does, and so do the new modules' own types' (`Menu`'s lists
  `contextMenu` and `menuStyle`, `StatusBar`'s `help` and `toolbar`):
  checked in the strict docs build's archive, 2026-10-09. The archive has
  55,840 pages against step B6's 59,764; how many of the 3,924 are such
  copies was not counted. No doc link had resolved only through one: the
  strict build reports nothing.
- **The modules' edges, which is what each import will bring once per-module
  products ship.** Each of the three depends on TUIFoundation alone and
  re-exports it. TUIApp depends on TUIChrome (the run loop draws the
  window chrome, the status bar and the notifications around the content) and
  re-exports it, so `import TUIApp` brings `.toolbar`, `.help` and
  `.statusBarItems`, as plan §4 has it. TUINavigation depends on
  TUIChrome too (the map's edge from Presentation, whose directory it
  compiles until step C1: a presentation draws its notifications with
  `notificationHost(width:)`, and a modal docks its presenter through the
  presentation dock) and re-exports it, so `import TUINavigation` brings
  the window chrome as well. No module depends on TUIEffects or
  TUIMenus but the umbrella: `import TUIApp` does not bring `Menu`,
  `.contextMenu` or `.transition` (plan §4, "…with row context menus:
  + TUIMenus"). TUILists and TUIColorPicker gained no edge: the
  pre-carve index records no reference from either to a declaration of the
  three (and neither did the build ask for one).

### B. Shipped

#### B-SPB5b-1. The three modules are targets at their default paths, not `directories:` targets of one directory each

*Package.swift — no API*

The step's brief asked for the three targets "using the `directories:` helper
B6 added". The manifest's own rule, beside that helper, is the other way:
the helper is for "a target that compiles more than one" directory under
Sources, and "a carve adds `.target(name: "TUIX", …)` at its default path"
(TUIFoundation's comment), as steps B2, B3 and B4 did.

**Shipped:** `.target(name: "TUIChrome", dependencies: ["TUIFoundation"],
…)` and the same for the other two, at `Sources/TUIChrome` and so on, as
TUIApp is. SwiftPM compiles the same files either way.

**The other version:** `.target(name: "TUIChrome", …, directories:
["TUIChrome"])`, which passes `path: "Sources"`, `sources:` the one
directory and `exclude:` the rest. **Price:** none in the build; the
helper's comment and TUIFoundation's would then have to say that a single
module may use it too, and every later single-module carve would choose.

#### B-SPB5b-2. The presentation dock reaches the focus manager's pane ledger through methods, not through `panes`

*Sources/TUIFoundation/Focus/FocusManagerPanes.swift, Sources/TUIChrome/Focus/FocusManagerPresentationDock.swift — no API*

`FocusManagerPresentationDock.swift`, which the map puts in TUIChrome,
extends `FocusManager` and read and wrote its `panes`, a stored property of
the class that holds the docks each live sheet posts. CONTRIBUTING.md
("Crossing a module boundary") forbids widening a class's stored property and
offers a `package` accessor over private storage instead. A `get`/`set`
accessor over the whole ledger would copy it at every write through it, and
each write here changes one of its dictionaries or sets in place
(`docks[id] = …`, `dockedBeforeTheWalk.insert(id)`): each would copy that
collection.

**Shipped:** seven small `package` members on `FocusManager`, beside the
pane members in FocusManagerPanes.swift, one per thing the dock does
(`postDock(inSection:presenter:resolver:)`, `postedDocks`,
`previouslyPostedDocks`, `noteDockedBeforeTheWalk(_:)`,
`anyDockedBeforeTheWalk`, `noteDocksLeftUndrawn(windowedOut:)`,
`isUndrawnUnderItsDock(_:)`). `panes` stays internal; `PaneLedger` and its
`PostedDock` are `package` only because two of those members return the
docks. Each runs once per frame, or once per live sheet per frame.

**The other version:** a `package func updatePanes(_ body: (inout
PaneLedger) -> Void)`, one member in place of seven. **Price:** every field
of the ledger would be `package`, and the dock's code would mutate the
ledger inside a closure.

#### B-SPB5b-3. The colour effects call `SGRColorRewrite.rewriting` out of line, not `@inlinable`

*Sources/TUIFoundation/Modifiers/OpacityModifier.swift — no API*

The plan (§5, "The per-row crossings") names `@inlinable package` on
`rewriting` as the remedy if the colour effects' crossing shows. The static
picture in a release `Stress` (Xcode's Swift 6.2.4) says it would cost more
than it saves:

- Before the carve, `rewriting` was inlined into the effects' per-line
  closures, and its per-escape call went to a copy of `rewritingSGR`
  specialised with its `emitted` parameter's default (a closure that does
  nothing) propagated and removed.
- After it, each line makes one direct call to `rewriting` (268 bytes, in
  TUIFoundation), whose per-escape call still goes to that specialised
  copy. The `transform` closure is called once per colour code in both, as
  before: no specialisation of the transform existed before the carve either.
- `@inlinable` on `rewriting` would inline it into TUIEffects, which cannot
  see `rewritingSGR`'s body: each escape sequence would then call the general
  `rewritingSGR` with the default `emitted`, an indirect call per colour code
  in place of one direct call per line.

**Shipped:** neither annotation; one call per line. The coordinator's A/B
measures it (`modifiers --variant color-effects`).

**The other version:** `@inlinable` on both `rewriting` and `rewritingSGR`
(and `@usableFromInline` on `SGRColorRewrite`, `extendedColor`,
`rewrittenBasic` and `colonFormColor`), so that TUIEffects specialises the
whole rewrite. **Price:** about 3 KB of `rewritingSGR` compiled again in
TUIEffects, and five more declarations exposed, for one call per line. Or
the plan's other remedy, `ColorEffectModifiers.swift` back in TUIFoundation
(≈0.1 s of its build).

#### B-SPB5b-4. An open menu's popup draws through the unspecialised `renderMenuPopup`

*Sources/TUIFoundation/Modifiers/MenuPopover.swift — no API*

Before the carve, TUIFoundation held two specialisations of
`renderMenuPopup<Items>`, for `MenuStyleConfiguration.Content` (a `Menu`'s
popup) and for `Button` (the screen selection's Copy menu), 4,716 bytes each
(c181ec0f9 held four, 18.9 KB, which option S1a's no-specialise attribute was
to save). Their callers moved to TUIMenus and TUIChrome, which call
`presentMenuPopover<Items>` across the boundary, unspecialised, as the lists'
and tables' row menus have since step B6: the carve removes both copies
(−9.4 KB), so S1a has nothing left to save. What runs unspecialised is the
popup's frame, once per frame while a menu is open: the column's stack over
its items (`_MenuSectionedItems<Items>`), its anchor and placement. Each row
reaches that stack as a type-erased child either way, and draws through
TUIFoundation's menu engine (the row, its highlight, the row sink), which
did not move.

**Shipped:** nothing; the coordinator's A/B measures it (`menus`).

**The other version:** `@_specialize(exported: true, where Items ==
MenuStyleConfiguration.Content)` on `presentMenuPopover`, which TUIFoundation
can name because the type is its own: the copy comes back, and TUIMenus
calls it. **Price:** an underscored attribute (the owner's call, as SPH3's
B-SPH3-1 put it), and the 4.7 KB back. `@inlinable` instead would need the
whole popup machinery `@usableFromInline`.

### C. Declined

#### C-SPB5b-1. Step 0a, the profile of M3's cold truncate and app-shapes runs, is not run

*Plan §5, row 0a — nothing*

The plan made step 0a binding before B5b, because M3's trial split held 22
of the 42 files TUIChrome and TUIEffects take, and its app-shapes cold
regression (+2.3%) was never attributed. Since step B5 each carve is checked
by another method, which this step follows: static gates in a release
`Stress` against the pre-modularisation build's (c181ec0f9) and against the
carve's base, the coordinator's A/B against c181ec0f9, and a profile of any
residual before landing (SPH, SPH2, SPH3). That method measures this carve's
own boundary, where 0a would have profiled a different split's; the brief
for this step marks 0a superseded.

## Completing the SwiftUI API: decisions from lane SPB5c

*Lane SPB5c took step B5c of the module split
([`Module split plan, revision 4`](<The module split.md>),
§5), 2026-10-09: the carve of TUIBitmaps (`Sources/TUIBitmaps`:
`Image(_:)` from a file or URL, `Image(_:bundle:)`, `AsyncImage`,
`_ImageCore` with its render cache, templates, resizing and orientation,
`.terminalGraphics(_:)` and the `.image*` options, asset catalogues and
`Color(_:bundle:)`, the `image:` initialisers of `Label` and
`ContentUnavailableView`), a leaf built on TUIFoundation and TUIImage,
and with it the plan's other half of the row: TUIFoundation no longer
depends on TUIImage or CSTBImage. It changed no public API: the umbrella
re-exports TUIBitmaps, and names TUIImage itself, so `import TUI`
gives an app what it gave before. This file holds the judgement calls the
step reached that the plan did not already settle, in the format of
[the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>):*

- **A-SPB5c-n — needs your decision.** Nothing has shipped for these.
- **B-SPB5c-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPB5c-n — declined.** With the reason.

There is no A entry: nothing waits on the owner.

### What an app can see

Not judgement calls: the plan (§5, row C9a) lists these for the release notes,
and C9a writes them. They are recorded here because this step made them. Each
name below was `TUIFoundation`'s after step B1; of the types, only
`ImageSource` was in v0.6.0, as `TUI.ImageSource`.

- **Reflected names.** `String(reflecting:)`, `dump` and the debugger name a
  moved type's new module: `TUIBitmaps.AsyncImage<…>`,
  `TUIBitmaps.AsyncImagePhase`, `TUIBitmaps.ImageSource`,
  `TUIBitmaps.ImageFitTarget`. `Image` itself stays
  `TUIFoundation.Image`, whichever initialiser made it.
  `UmbrellaQualifiedNameTests` pins four of them. The plan's map moves no
  type out of TUIBitmaps later, so these names are final.
- **Saved state is unaffected.** TUIBitmaps declares no `Codable` type.
  One of its public types is `Hashable` (`ImageFitTarget`) and so can be a
  value of a `NavigationPath`, but a path holding one has no `codable`
  representation, which is the only saved form that stores type names
  (decisions SPB5, "Saved navigation paths").
- **The bundle is unchanged.** The directory holds Swift files only, so the
  bundle is still `TUI_TUIStrings` (decisions SPB2). An image named in
  a bundle is read from the app's bundle, as before.
- **The documentation lists the module's options on `View` and on its own
  types, not on TUIFoundation's.** As at steps B5, B6 and B5b:
  `symbolgraph-extract` copies onto a module's conforming types the
  protocol-extension members that module can see, its own and its
  dependencies', so neither `Text`'s page nor `Image`'s (which stays
  TUIFoundation's) lists `imageColorMode(_:)`, `terminalGraphics(_:)`,
  `imageCharacterSet(_:)` or `imageFitTarget(_:)` among its default
  implementations any more, while `View`'s and `AsyncImage`'s pages do;
  `scaledToFit()`, which stays, is on all four: checked in the strict docs
  build's archive, 2026-10-09. The archive has 53,761 pages against step B5b's
  55,840; how many of the 2,079 are such copies was not counted. No doc link
  had resolved only through one: the strict build reports nothing.
- **The modules' edges, which is what each import will bring once
  per-module products ship.** TUIBitmaps depends on TUIFoundation and
  TUIImage and re-exports both, so `import TUIBitmaps` brings the
  options' `ASCIIColorMode`, `ASCIIToneCurve` and the rest. No module of the
  map depends on it but the umbrella: `import TUIApp` does not bring
  `AsyncImage` or `Image(_:bundle:)` (plan §4, "Any app using … bitmaps:
  + TUIBitmaps"), and no longer brings TUIImage either:
  TUIFoundation does not re-export it. TUIAppKit, the AppKit bridges,
  depends on TUIBitmaps (B-SPB5c-1). `Image(systemName:)`, `.resizable()`,
  `.aspectRatio`, `.scaledToFit()`, `.scaledToFill()` and `.imageCellAspect`
  stay TUIFoundation's (the plan's S1), so an app that draws only symbols
  needs neither module.

### B. Shipped

#### B-SPB5c-1. TUIAppKit depends on TUIBitmaps

*Package.swift, Sources/TUIAppKit — no API*

The plan (§8) found that TUIAppKit reaches `Color.catalogColor` and
`catalogColorScheme`, which the map puts in Bitmaps, "through the umbrella's
re-export". TUIAppKit does not depend on the umbrella: its target depends
on the modules whose types it extends (Package.swift's comment on it), which
were TUIFoundation and TUIImage. After the carve, those declarations,
and `Image(_:decoded:)`, `_DecodedImage`, `ImageSource` and
`Image.bundleResource(named:in:)`, which an image made from a `CGImage`, an
`NSImage` or a compiled asset catalogue draws through, are TUIBitmaps'
(21 references from 2 files, all `package` or public already).

**Shipped:** TUIAppKit depends on TUIBitmaps, beside the other two, and
its two files that use it import it. It is no module of the map, so the
map's "pure leaf" is unaffected: no module of the map depends on Bitmaps but
the umbrella.

**The other version:** TUIAppKit depends on the umbrella, as the plan's
sentence assumed. **Price:** every module would be built before the bridges
could be, and an app that takes the bridges à la carte, once per-module
products ship, would take the whole framework with them; the target's
comment says why it does not.

#### B-SPB5c-2. `placeholderRows` is a non-generic core under an `@inlinable` generic shim

*Sources/TUIFoundation/Rendering/TerminalImageStore.swift — no API*

PRESPEC (session notes, recommendation.md) recommends making
`TerminalImageStore.placeholderRows<Signature>` non-generic at this step: its
only generic work is erasing the signature, and after the carve
`_ImageCore` (TUIBitmaps) called the unspecialised generic once a frame
for every image drawn with Kitty graphics. Its other three callers, and their
signature types, are TUIFoundation's until step B7 carves
NumericControls.

**Shipped:** the inventory's form: a two-line `@inlinable` generic shim that
erases the signature in the caller's module, specialised there, and a
non-generic `@usableFromInline` internal core. The class,
`AnyImageSignature` and `ImageStoreSignature` are `@usableFromInline` for it.
The store's private stored properties were checked dynamically before
(every copy of the method holds 15 `swift_beginAccess` calls, in c181ec0f9
too), so nothing changes there. The bucket goes to the core as a closure, so
it is still computed only on a miss.

**The other version:** each caller erases the signature itself and calls a
non-generic `package` method, with no shim. **Price:** the erasure spelled at
four sites, and `AnyImageSignature`'s initializer would still have to be
`@inlinable` for TUIBitmaps' call to be specialised: the same exposure,
more code. `@_specialize(exported:)` is not available: TUIFoundation
cannot name `TerminalImageSignature`.

#### B-SPB5c-3. The image's environment reads, `Image.init(raster:)` and `Label`'s designated initializer stay calls

*Sources/TUIFoundation — no API*

After the carve, `_ImageCore` calls across the boundary, once a frame for
each image drawn, fourteen environment accessors TUIFoundation declares
(`imageCellAspect`, `imageContentMode`, `imageAspectRatio`,
`scrollViewportSize`, `terminalImageStore`, `lifecycle` and the rest). In
c181ec0f9 each was inlined into its caller, which then called a
specialisation of the environment subscript: a dictionary lookup and a cast
out of `Any`. Now the caller calls the accessor (152 to 184 bytes, or a tail
call to that specialisation, 28 to 64), which does the same. The step's
brief puts a call that does its own work outside tier 2, as B5b did for the
scroll transition's geometry reads.

`Image.init(raster:)` (68 bytes: it boxes the raster into the image's
content) and the generic `Label.init(title:icon:iconIsVisible:)` run once a
body evaluation of a view built with an image name (`Image("name", bundle:)`,
`Label(_:image:)`, `ContentUnavailableView(_:image:description:)`).

**Shipped:** all three stay calls. The plan's tier 2 at B5c lists more of
these accessors than are inlined; the commit that inlines
`isNaturalExtentBudget(_:)` and `_ImageResizing`'s `slices` and `filling`,
each less work than its call, says which.

**The other version:** `@inlinable` on each. **Price:** for the accessors,
each environment key `@usableFromInline` (they are `private` today) and one
call and return saved beside a dictionary lookup, per accessor per image per
frame; for `Image.init(raster:)`, `Image.Content` and the raster protocol
(R2's seam) `@usableFromInline`, which exposes the seam to every module's
inline code; for `Label`'s initializer, the initializer of its `styles`
property wrapper would run out of line from every inlined copy
(CONTRIBUTING's rule on stored-property defaults), adding a call where one
is saved. The coordinator's A/B decides; no Stress scenario reaches them
(no scenario draws a bitmap), Example's image pages and IdleProbe do.

### C. Declined

#### C-SPB5c-1. `_OpacityView.fading` is left generic

*Sources/TUIFoundation/Modifiers/OpacityModifier.swift — nothing*

PRESPEC recommended moving `_OpacityView.fading` (generic in name only) off
the generic type at step B5b; that step's carve did not. It is not this
step's crossing: its only caller in another module is TUIEffects'
`_ColorEffectView`, since B5b, and TUIBitmaps does not call it. The
release binary shows c181ec0f9 called it out of line from the same caller
too (SPH2's edgecmp: one call per colour-effect render in both). It is
B5b's A/B's to call for (`modifiers --variant color-effects`).

## Completing the SwiftUI API: decisions from lane SPB6

*Lane SPB6 took step B6 of the module split
([`Module split plan, revision 4`](<The module split.md>),
§5), 2026-10-08: the carve of the Lists group, the fourth module built on
TUIFoundation rather than under it, and the second coarse group: one
target, TUILists, that compiles four planned modules' directories,
`Sources/TUILists`, `Sources/TUITables`, `Sources/TUITabs` and
`Sources/TUIGrid`, until steps C2, C3 and C4 peel the last three into
targets of their own. It changed no public API: the umbrella re-exports
TUILists beside TUIFoundation, so `import TUI` gives an app what it
gave before. This file holds the judgement calls the step reached that the
plan did not already settle, in the format of
[the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>):*

- **A-SPB6-n — needs your decision.** Nothing has shipped for these.
- **B-SPB6-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPB6-n — declined.** With the reason.

### What an app can see

Not judgement calls: the plan (§5, row C9a) lists these for the release notes,
and C9a writes them. They are recorded here because this step made them. Each
name below was `TUIFoundation`'s after step B1, and `TUI`'s in v0.6.0.

- **Reflected names.** `String(reflecting:)`, `dump` and the debugger name a
  moved type's new module: `TUILists.EditMode`,
  `TUILists.SidebarListStyle`. That includes the types of
  `Sources/TUITables`, `Sources/TUITabs` and `Sources/TUIGrid`, which
  compile into TUILists until steps C2, C3 and C4:
  `TUILists.Table<…>`, `TUILists.TableColumnCustomizationBehavior`,
  `TUILists.TabViewCustomization`, `TUILists.TabBarPlacement`,
  `TUILists.GridItem`, `TUILists.GridItem.Size`. Those names change
  again at each peel, to `TUITables.`, `TUITabs.` and `TUIGrid.`, so
  the release notes should give the peeled name for a type if its peel ships
  in the same release. `UmbrellaQualifiedNameTests` pins at least one from
  each directory.
- **Saved state is unaffected.** The four directories declare two public
  `Codable` types, `TableColumnCustomization` and `TabViewCustomization`. Each
  encodes its data under coding keys of its own, with no type name, so a
  customization an app saved (to `@AppStorage` or `@SceneStorage`, as SwiftUI
  suggests) still decodes. Neither is `Hashable`, so neither can be a value in
  a `NavigationPath`, whose saved representation is the one that stores type
  names (decisions SPB5, "Saved navigation paths").
- **The bundle is unchanged.** The four directories hold Swift files only (the
  rows', tables' and tabs' labels come from TUIStrings' tables through
  `LocalizationService`), so the bundle is still `TUI_TUIStrings`
  (decisions SPB2).
- **The documentation lists the group's modifiers on `View` and on the
  group's own types, not on TUIFoundation's.** As at step B5:
  `symbolgraph-extract` copies a protocol extension's members onto the
  conforming types of its own module only, so `Text`'s page no longer lists
  `listStyle(_:)`, `tabViewStyle(_:)` or `gridCellColumns(_:)` among its default
  implementations, while `View`'s and `List`'s and `TabView`'s pages still do
  (checked in the strict docs build's archive, 2026-10-08). The archive has
  59,764 pages against step B5's 63,396; how many of the 3,632 are such
  copies was not counted. No doc link had resolved only through one: the
  strict build reports nothing.
- **`import TUIColorPicker` brings lists, tables, tabs and grids too**, once
  per-module products ship: it re-exports TUILists, its new direct
  dependency (its panel lays its modes out in a `TabView` of `Tab`s). After C3
  it re-exports TUITabs instead, which re-exports TUILists (plan §4).
  Under the umbrella, which is the only product today, nothing changes.
- **`import TUINavigation` does not bring `List`.** TUINavigation does
  not depend on TUILists: no file of its two directories names a
  declaration of the group's four (the pre-carve index: 0 references; the
  split views take their columns as any `View`), and the plan's map has no
  such edge. An app that writes `NavigationSplitView { List … }` gets `List`
  from the umbrella today, and from `import TUILists` once per-module
  products ship.

### B. Shipped

#### B-SPB6-1. `Group`'s initializers for table columns, table rows and tabs build it through a package factory

*Sources/TUIFoundation/Views/Group.swift — no API*

`Group` is TUIFoundation's, and its `let content` is set by a `fileprivate
init(grouping:)`, so that no memberwise `init(content:)` exists for a trailing
closure to bind to (`Group { … }` with `Content` unconstrained would match it
with the closure as the content). Three of its public initializers live with
the builders they take, which the group declares: `init(content:)` for
`@TableColumnBuilder`, `@TableRowBuilder` and `@TabContentBuilder`. Each
assigned `self.content` itself, which an initializer in an extension declared
in another module may not do ("'let' property 'content' may not be
initialized directly", the class step B5 met with `Button(_:action:)`).

B5 moved its initializer into the type's own file. These three cannot move:
TUIFoundation cannot see the builders. A `package init(grouping:)` would
let the trailing closure bind again, now from every module of the package.

**Shipped:** `package static func grouping(_ content:) -> Self`, which calls
the `fileprivate` initializer; the three initializers say `self =
.grouping(content())`. A static function cannot be reached by `Group { … }`.

**The other version:** a `package` initializer with a second, unlabelled
parameter no closure can fill (say `init(grouping:_: Void)`). **Price:** none
in code, but it is an initializer whose shape exists only to dodge overload
resolution, which the factory states plainly.

#### B-SPB6-2. No Stress scenario for grids, and none for tab views beyond a session, is added here

*Sources/Stress — nothing shipped*

The step's brief asks for the per-row and per-cell crossings the carve
creates, the scenarios that exercise each, and a proposal where a hot crossing
has none. Two of the group's four directories have none in `Stress --bench`'s
scenario list:

- **Grids.** No scenario draws a `Grid`, `LazyVGrid` or `LazyHGrid` (checked
  by grep over Sources/Stress, 2026-10-08). The per-cell crossings
  (`GridLattice.placement` → `HorizontalAlignment.childOffset` and
  `VerticalAlignment.childOffset`; `placeSubviews` → `LayoutSubviews`'
  subscript, `LayoutSubview.place` and `sizeThatFits`) are measured by
  nothing.
- **Tab views.** Only the `notes` session (`--bench --scenario
  session/notes`) draws a `TabView`; no scenario does. Its strip assembles
  each tab's cells through `ClaimingRow`, set L and `@inlinable` since step
  A3; what crosses uninlined is one `HorizontalAlignment.childOffset` per
  strip line, and the per-frame calls of `TabView` itself.

**Shipped: nothing.** A scenario added in this lane would exist only on the
carved side of the coordinator's A/B, which compares the same scenario on
both trees.

**The other version:** a `ScenarioVariant` of `dashboard`, `grid`: the same
metric panels in a `LazyVGrid(columns: [GridItem(.adaptive(minimum: 24))])`,
and a second, `grid-fixed`, in a `Grid` of `GridRow`s (about 30 lines with
their summaries).

**Built 2026-10-19 (lane TOOLING), as a scenario of its own rather than a
`dashboard` variant:** the sweep runs each scenario's default variant only, so
`grids` takes `lazy` (the panels in an adaptive `LazyVGrid`, the default, and
what decisions B71 owes a lazy grid's cost to) and `fixed` (a `Grid` of
`GridRow`s). The sidebar tab view is `app-shapes/sidebar-tabs`. **Price:** a scenario the sweep then runs on every A/B (a
second or two), landed on main before the next carve's A/B so that both sides
have it. Worth it before step C4 peels Grid, the first step whose own A/B
would otherwise have nothing to measure.

## Completing the SwiftUI API: decisions from lane SPB7

*Lane SPB7 took step B7 of the module split
([`Module split plan, revision 4`](<The module split.md>),
§5), 2026-10-09: the carve of the TextInput group, the third coarse group and
the last carve of the plan's coarse stage: one target, TUITextInput, named
after the module the peels leave, that compiles five planned modules'
directories, `Sources/TUITextInput`, `Sources/TUIPickers`,
`Sources/TUIForms`, `Sources/TUISearch` and
`Sources/TUINumericControls`, until steps C5 to C8 peel the last four into
targets of their own. TUIFoundation compiles only its own directory since,
and is an ordinary target at `Sources/TUIFoundation`. The step changed no
public API but one underscored witness (B-SPB7-2): the umbrella re-exports
TUITextInput beside TUIFoundation, so `import TUI` gives an app what
it gave before. This file holds the judgement calls the step reached that the
plan did not already settle, in the format of
[the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>):*

- **A-SPB7-n — needs your decision.** Nothing has shipped for these.
- **B-SPB7-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPB7-n — declined.** With the reason.

### What an app can see

Not judgement calls: the plan (§5, row C9a) lists these for the release notes,
and C9a writes them. They are recorded here because this step made them. Each
name below was `TUIFoundation`'s after step B1, and `TUI`'s in v0.6.0.

- **Reflected names.** `String(reflecting:)`, `dump` and the debugger name a
  moved type's new module: `TUITextInput.TextField<TUIFoundation.Text>`,
  `TUITextInput.TabWidth`. That includes the types of `Sources/TUIPickers`,
  `Sources/TUIForms`, `Sources/TUISearch` and
  `Sources/TUINumericControls`, which compile into TUITextInput until
  steps C5 to C8: `TUITextInput.RadioButtonOrientation`,
  `TUITextInput.DatePickerComponents`, `TUITextInput.AutomaticFormStyle`,
  `TUITextInput.GroupedFormStyle`, `TUITextInput.SearchFieldPlacement`,
  `TUITextInput.SearchFieldIconPlacement`, `TUITextInput.TrackStyle`,
  `TUITextInput.IndeterminateStyle`. Those names change again at each peel,
  to `TUIPickers.`, `TUIForms.`, `TUISearch.` and
  `TUINumericControls.`, so the release notes should give the peeled name
  for a type if its peel ships in the same release. `UmbrellaQualifiedNameTests`
  pins at least one from each directory.
- **Saved state is unaffected.** None of the five directories declares a
  `Codable` type (checked by grep, 2026-10-09), so nothing an app saved names
  one of them, and none can be a saved value in a `NavigationPath` (decisions
  SPB5, "Saved navigation paths").
- **The bundle is unchanged.** The five directories hold Swift files only (the
  fields', pickers' and search's labels come from TUIStrings' tables
  through `LocalizationService`), so the bundle is still `TUI_TUIStrings`
  (decisions SPB2).
- **The documentation lists the group's modifiers on `View` and on the
  group's own types, not on TUIFoundation's.** As at steps B5 and B6:
  `symbolgraph-extract` copies a protocol extension's members onto the
  conforming types of its own module only, so `Text`'s page no longer lists
  `textFieldStyle(_:)`, `pickerStyle(_:)`, `formStyle(_:)` or `gaugeStyle(_:)`
  among its default implementations, while `View`'s and `TextField`'s,
  `Picker`'s, `Form`'s and `Slider`'s pages still do (checked in the strict
  docs build's archive, 2026-10-09). The archive has 47,313 pages. No doc link
  had resolved only through such a copy: the strict build reports nothing.
- **`import TUIColorPicker` brings the text inputs, pickers, forms, search
  and numeric controls too**, once per-module products ship: it re-exports
  TUITextInput, its new direct dependency (its editors are `Slider`s, its
  panel's hex field a `TextField`, its channel-curve editor a
  `RadioButtonGroup`). After the peels it re-exports the modules they make
  (plan §4). Under the umbrella, which is the only product today, nothing
  changes.
- **No other carved module brings them.** TUILists, TUINavigation,
  TUIChrome, TUIMenus, TUIEffects, TUIBitmaps and TUIApp do not
  depend on TUITextInput: no file of theirs names a declaration of the
  group's five directories (the pre-carve index: 0 references), and no build
  error asked for an edge. A searchable list (`List { … }.searchable(text:)`,
  as Stress's inbox session writes it) is TUISearch's modifier on a
  TUILists view: the app imports both, and today gets both from the
  umbrella.
- **`TimelineView` states `_handsOverChildren` itself** (B-SPB7-2): a public
  member, underscored like the protocol requirement it witnesses, with the
  value the default gave it.

### B. Shipped

#### B-SPB7-1. TUIFoundation applies the five modifiers whose result types TUITextInput cannot see, in seven methods: two draw in place and five erase

*Sources/TUIFoundation/Extensions/View+BuiltForAnotherModule.swift — no public API*

The carve left fifteen call sites in TUITextInput that look an opaque
result's type up at run time (`swift_getOpaqueTypeMetadata2` and
`…Conformance2`, which demangle the type's name each time): the five public
modifiers `border`, `id`, `foregroundStyle`, `focused` and `onAppear`, whose
`some View` results name types only TUIFoundation can see, applied in the
group's views (release Stress, 513 opaque-runtime call sites against the
base's 498). One of them was hot: `_StyledFieldFrame`, which wraps every
`TextField` and `SecureField`, asked for `border(style:)`'s type at the top of
its render and its measure, so every field paid the lookup on every frame,
bordered or not. The rest are on paths no Stress scenario reaches: an `if`
among a form's rows (`id`), a grouped form's section box (`border`), a search
token (`foregroundStyle`), a text editor's open find bar (`focused`,
`onAppear`).

**Shipped:** seven `package` methods on `View` in TUIFoundation, each of
which applies one of those modifiers there, where the type is concrete.
`renderBordered(style:context:)` and `measureBordered(style:proposal:context:)`
draw and measure the bordered view as `_StyledFieldFrame` did, with nothing
erased. `erasedBorder()`, `erasedID(_:)`, `erasedForegroundStyle(_:)`,
`erasedFocused(_:)` and `erasedOnAppear(perform:)` return the modified view in
an `AnyView`: the same value for the form's `if` groups, which were erased
already; one more `AnyView` per evaluation of a grouped section or a token
chip, and two per evaluation of an open find bar (`focused` and `onAppear`).
The static count is the base's again (498).

**The other version:** for the four cold callers, a `Renderable & Layoutable`
wrapper per modifier in TUIFoundation, which draws and measures the
modified view at its own identity, as `_StyledFieldFrame` now does through the
first two methods, so nothing is erased. **Price:** five more types, each of
which must forward what its view's type tells a container (its member count,
`_providesAlignmentGuide`, which `ConditionalView` forwards for `border`'s
result), where a missed forward is a silent layout change; for an allocation
per evaluation on paths no scenario reaches. Or leave those lookups, about
one per evaluation on the same paths, and the static gate above the base's.

#### B-SPB7-2. `TimelineView` states `_handsOverChildren`

*Sources/TUIFoundation/Views/TimelineView.swift — a public underscored member*

`ProgressView(timerInterval:)` labels itself with `DefaultDateProgressLabel`
(TUITextInput), whose body is a `TimelineView`. Its `_handsOverChildren`
witness is View's default, `Body._handsOverChildren`, and TUITextInput
inlined that default twice over: through `TimelineView`'s own default, it
asked for `TimelineView`'s body type, whose underlying core is private to
TUIFoundation, and looked it up at run time on every child walk (one of
B-SPB7-1's fifteen).

**Shipped:** `TimelineView` (TUIFoundation) declares
`public static var _handsOverChildren: Bool`, returning its core's answer,
which is what the default returned. Naming the private core keeps the witness
out of every other module's inline code, so the label calls it.

**The other version:** `DefaultDateProgressLabel` states its own answer,
`false`, in TUITextInput. **Price:** no change to `TimelineView`'s public
surface, but a second module then hard-codes what a TUIFoundation type's
private core answers, and goes on answering it if the core changes.

#### B-SPB7-3. The small per-frame calls the carve puts out of line stay calls

*Sources/TUIFoundation — no API*

Against the base's release Stress, the carve adds out-of-line calls from
TUITextInput, per frame for a control, to callees TUIFoundation inlined
before (call sites by callee, base -> after the carve, all modules):
`ANSIRenderer.colorize` 45 -> 137 (per styled run of a field's text, a caret
frame and an editor row); `MenuHighlight`'s methods 19 -> 55 (a picker's menu
and a field's suggestions, per keystroke and per frame while open);
`FocusRegistration`'s statics 116 -> 123; `TextStyle`'s initializer and setters
118 -> 136 (a graphical date picker's day cells); `StyleChain` 28 -> 43 (the
styled controls' bodies); `CursorTimer`'s and `IndicatorCycleTiming`'s statics
81 -> 93 (a focused field's caret); `DropdownMenu` 79 -> 89; and the
environment accessors the plan's tier 2 lists at B7 (`styleCascade`,
`cursorTimer`, `indicatorCycleTiming`, `indicatorAnimationSpeeds`,
`appearsActive`).

**Shipped:** all stay calls, as steps B5c (B-SPB5c-3) and B6 left theirs.
`colorize` builds an escape string in `ANSIRenderer.render`, which it called
out of line before too, and an environment accessor is a dictionary lookup
beside its call; `MenuHighlight` is a class whose stored properties
CONTRIBUTING forbids widening, so its methods cannot be inlined into another
module without making every access to them checked at run time; the rest are
a call each per control per frame. The coordinator's A/B decides which
deserve the plan's tier 2: the hot ones are listed in the carve's commit
message, with their scenarios.

**The other version:** `@inlinable package` on the pure ones now:
`CursorTimer.blinkVisible(atFrame:)` and `pulsePhase(atFrame:of:)`,
`FocusRegistration.isFocused(context:focusID:)` (tier 2 since B4), and
`TextStyle`'s initializer and colour setters. **Price:** `CursorTimer` and
`TextStyle`'s storage `@usableFromInline`; one call and return saved per
control per frame, or per day cell, which no scenario draws.

#### B-SPB7-4. No Stress scenario is added for the group's paths none reaches

*Sources/Stress — nothing shipped*

No scenario draws a `DatePicker`, a `RadioButtonGroup`, a grouped `Form`, a
`SecureField`, a search token, a timer `ProgressView` or a text editor's find
bar (checked by grep over Sources/Stress, 2026-10-09). So the date picker's
per-cell calls (B-SPB7-3), the radio group's per-item ones
(`styleCascade`, `StyleCascade.resolve(for:)`, the selection emphasis), and
the four cold paths of B-SPB7-1 are measured by nothing. The text field's hot
path is measured by `controls/fields`, `app-shapes/settings-form` and the
chat, inbox, notes and settings sessions; pickers by
`app-shapes/settings-form` and the menus, settings and themes sessions;
forms by `app-shapes/settings-form`, `dashboard` (`Panel`, `Card`) and the
settings session; the numeric controls by `controls/progress`, `dashboard` and
`app-shapes/settings-form` (a `Slider` and a `Stepper` per group); search by
the inbox session.

**Shipped: nothing**, for B-SPB6-2's reason: a scenario added in this lane
would exist only on the carved side of the coordinator's A/B.

**The other version:** a `ScenarioVariant` of `controls`, `pickers`: rows of
a graphical `DatePicker`, a `RadioButtonGroup` and a segmented `Picker`, and
a second, `grouped-form`, a `Form` in `.formStyle(.grouped)` with an `if`
section (about 40 lines with their summaries).

**Built 2026-10-19 (lane TOOLING)** as the scenario `pickers`: `rows` (the
default, so the sweep runs it) and `grouped-form`. `SecureField`, search
tokens, a timer `ProgressView` and the find bar are still drawn by no
scenario. **Price:** as B-SPB6-2's, two
scenarios the sweep runs on every A/B, landed on main before the next carve's
A/B; worth it before step C8 peels Pickers.

## Completing the SwiftUI API: decisions from lane SPC1

*Lane SPC1 took step C1 of the module split
([`Module split plan, revision 4`](<The module split.md>),
§5), 2026-10-09: the first PEEL. `Sources/TUIPresentation` left the
Navigation group of step B5 for a target of its own, TUIPresentation, built
on TUIFoundation and TUIChrome; the residual TUINavigation compiles
only the navigation containers, on TUIFoundation alone. Neither module
depends on the other. The step changed no public API: the umbrella re-exports
TUIPresentation beside TUINavigation, so `import TUI` gives an app
what it gave before. This file holds the judgement calls the step reached that
the plan did not already settle, in the format of
[the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>):*

- **A-SPC1-n — needs your decision.** Nothing has shipped for these.
- **B-SPC1-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPC1-n — declined.** With the reason.

### What an app can see

Not judgement calls: the plan (§5, row C9a) lists these for the release notes,
and C9a writes them. They are recorded here because this step made them. Each
name below was `TUINavigation`'s from step B5, `TUIFoundation`'s after
step B1, and `TUI`'s in v0.6.0.

- **Reflected names.** `String(reflecting:)`, `dump` and the debugger name a
  presentation type's new module: `TUIPresentation.Alert<TUIFoundation.Button>`,
  `TUIPresentation.PresentationDetent`. They
  read `TUINavigation.` from step B5 until this step (decisions SPB5, "What
  an app can see", said they would change here), so a release that ships both
  steps should give the C1 name. `UmbrellaQualifiedNameTests` pins the alert
  and the detent. The navigation containers' names are unchanged
  (`TUINavigation.NavigationPath`).
- **Saved state is unaffected.** No declaration of `Sources/TUIPresentation`
  is `Codable` (checked by grep, 2026-10-09), so no saved
  `NavigationPath.CodableRepresentation` names one. The one `Codable` type of
  the two directories, `NavigationSplitViewVisibility`, stays in
  TUINavigation (decisions SPB5, "Saved navigation paths").
- **The bundle is unchanged.** The directory holds Swift files only, so the
  bundle is still `TUI_TUIStrings` (decisions SPB2).
- **The documentation lists each module's modifiers on `View` and on that
  module's own types only.** `symbolgraph-extract` copies a protocol
  extension's members onto the conforming types of its own module only, and
  the two directories are two modules now: `NavigationStack`'s page lists
  neither `sheet` nor `alert` among its default implementations (it listed
  `sheet` after step B5, decisions SPB5), and `Dialog`'s and `Alert`'s list
  no `inspector`, while `View`'s lists all three (checked in the strict docs
  build's archive, 2026-10-09). The archive has 46,868 pages against step B7's
  47,313. No doc link had resolved only through such a copy: the strict build
  reports nothing.
- **`import TUIColorPicker` brings the presentations, and no longer the
  navigation containers**, once per-module products ship: it re-exports
  TUIPresentation in place of TUINavigation (its panels are `Dialog`s
  presented through `.modal`; it names nothing of the navigation
  containers'). Through TUIPresentation it brings TUIChrome as well.
- **`import TUINavigation` no longer brings the presentations, nor
  TUIChrome**, once per-module products ship: an app that presents a sheet
  from a `NavigationStack` imports both modules, as plan §4's "Typical" row
  already lists TUIPresentation. Under the umbrella, which is the only
  product today, nothing changes.
- **No other module gained an edge.** TUIApp, TUIChrome, TUILists,
  TUIMenus and TUITextInput name no declaration of either directory (the
  pre-peel index: 0 references), and no build error asked for one.

### B. Shipped

#### B-SPC1-1. Both modules are ordinary targets at their default paths

*Package.swift — no API*

The brief for this step described the peel in terms of the coarse groups'
`directories:` helper: TUINavigation's list drops
`Sources/TUIPresentation`, and a new target compiles that directory.

**Shipped:** each of the two compiles one directory, so each is declared as
an ordinary target at its default path (`Sources/TUINavigation`,
`Sources/TUIPresentation`), as TUIFoundation became once step B7 took the
last group out of it. Package.swift's own rule says `directories:` (`path:
"Sources"` with the other 32 directories excluded) is for a target that
compiles more than one directory. The files each compiles are the same either
way (the build, and Tools/ModuleMap's `uncompiled` check: 0).

**The other version:** `directories: ["TUINavigation"]` and
`directories: ["TUIPresentation"]` through the helper. **Price:** two more
targets over the whole of `Sources` with a 32-entry `exclude:` each, which the
next peel would carry, for no difference in what compiles.

#### B-SPC1-2. TUIPresentation depends on TUIChrome as well as TUIFoundation

*Package.swift — no API*

The brief named TUIFoundation as the new module's one dependency, citing
plan §1's Presentation row; that row, and `rules.json`'s entry, give it
TUIChrome as well.

**Shipped:** both, as the map has them and as the build needs: the
presentations name four TUIChrome declarations (the index, 2026-10-09): a
presentation draws its notifications with `NotificationHostModifier`'s
`init(content:width:)` (`View+Presentation.swift`), and a modal docks its
presenter's focus through `notePresentationDock(id:presenter:resolver:)` and
`presenterWentUndrawnUnderItsDock(_:)` (`ModalPresentationModifier+Live.swift`).
The navigation containers name none, so TUINavigation drops the TUIChrome
edge it had since step B5b only for the presentations.

**The other version:** TUIPresentation on TUIFoundation alone. **Price:**
the notification host and the presentation dock move from TUIChrome into
TUIFoundation, or behind a slot of K1's kind in TUIFoundation; step B5b
put both in TUIChrome deliberately (the window chrome the run loop draws),
and TUIApp, which draws them, would then reach them through
TUIFoundation.

#### B-SPC1-3. A presentation's background view goes on in TUIFoundation; the navigation stack's bar keeps its three run-time type lookups

*Sources/TUIPresentation/Views/PresentationBackground.swift, Sources/TUINavigation/Views/NavigationStack.swift — no API*

The crossing predictor, re-pointed at both sides of the peel, flags one
opaque-result hazard on each side; the release Stress shows which run on
every call (SPC1/opqdis.py, on the base's binary and the peel's, which
agree). Both have been there since step B5 carved the two directories out of
TUIFoundation, before the predictor had the check (lane SPM1); neither is
the peel's.

- **TUIPresentation:** `_PresentationBackgroundView.presentationBackground(behind:)`
  resolved `background(alignment:content:)`'s result at run time on every
  frame of a presentation with a background view. Fixed in this lane: the
  modifier is applied in TUIFoundation (`erasedBackground(alignment:_:)`,
  B-SPB7-1's pattern), where the presenter already received an `AnyView`, so
  nothing else changed (opaque-runtime call sites 498 -> 496).
- **TUINavigation:** `_NavigationStackCore`'s bar, drawn on every frame a
  screen is pushed, asks for three conformances: `buttonStyle(_:)`'s result
  (the primitive-style overload, for the Back button's `.borderless`), once in
  `renderBar` and once in `navigationBar`, and `layoutPriority(_:)`'s (the
  subtitle's `-1`) in `navigationBar`, each `swift_getOpaqueTypeConformance2`.
  Stress reaches it in the inbox session's pushed variant and in the notes
  session while a note is open. The predictor sees only `layoutPriority`:
  `buttonStyle(_:)`'s underlying type names an internal type through a generic
  argument (the environment key's value), which it cannot see.

**Shipped for TUINavigation: nothing.** The lookups predate this step and
were inside the coarse stage's measurements, which the coordinator found
neutral against c181ec0f9; the remedy changes what the bar is made of, which
the peel itself does not touch.

**The other version:** B-SPB7-1's: `erasedButtonStyle(_:)` and
`erasedLayoutPriority(_:)` on `View` in TUIFoundation, and the bar's Back
button and subtitle built through them. **Price:** two `AnyView`s per pushed
frame (one boxing each, and a render-cache probe on each draw and measure),
unmeasured against the three lookups they replace; the Back button then sits
inside an `AnyView`, so a test that pins its focus identity must be checked;
and the commit's A/B owes the inbox session's pushed variant and the notes
session. Or, without erasure, a `package` view type per modifier in
TUIFoundation whose body applies it (the bar names the type, whose `View`
conformance is concrete, and the body's type is resolved inside
TUIFoundation). **Price:** two more types, each of which must forward what
its content's type tells a container (B-SPB7-1's caution).

## Completing the SwiftUI API: decisions from lane SPC2

*Lane SPC2 took step C2 of the module split
([`Module split plan, revision 4`](<The module split.md>),
§5), 2026-10-09: the second PEEL, after set T. `Sources/TUITables` left the
Lists group of step B6 for a target of its own, TUITables, built on
TUIFoundation and TUILists; the residual TUILists compiles lists, tabs
and grids, on TUIFoundation alone, and does not depend on the new module.
The step changed no public API: the umbrella re-exports TUITables beside
TUILists, so `import TUI` gives an app what it gave before. This file
holds the judgement calls the step reached that the plan did not already
settle, in the format of
[the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>):*

- **A-SPC2-n — needs your decision.** Nothing has shipped for these.
- **B-SPC2-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPC2-n — declined.** With the reason.

### What an app can see

Not judgement calls: the plan (§5, row C9a) lists these for the release notes,
and C9a writes them. They are recorded here because this step made them. Each
name below was `TUILists`' from step B6, `TUIFoundation`'s after step
B1, and `TUI`'s in v0.6.0.

- **Reflected names.** `String(reflecting:)`, `dump` and the debugger name a
  table type's new module: `TUITables.Table<…>`,
  `TUITables.TableColumnCustomizationBehavior`. They read `TUILists.`
  from step B6 until this step (decisions SPB6, "What an app can see", said
  they would change at C2), so a release that ships both steps should give
  the C2 name. `UmbrellaQualifiedNameTests` pins the table and the
  customization behaviour. The lists', tabs' and grids' names are unchanged
  (`TUILists.EditMode`, `TUILists.TabViewCustomization`,
  `TUILists.GridItem`).
- **Saved state is unaffected.** The directory's one `Codable` type,
  `TableColumnCustomization`, encodes the columns' stated visibilities by
  identifier, their order and their widths, and no type name
  (`TableColumnCustomization.swift`, `encode(to:)`), so a customization an app
  saved through `@SceneStorage` or `@AppStorage` decodes as before. No
  declaration of the directory is something a `NavigationPath` stores by name,
  and nothing in the directory saves a type's name (checked by grep,
  2026-10-09, again 2026-10-10: no `_mangledTypeName` or
  `String(reflecting:)`; the four `"\(Self.self)"` interpolations, which are
  `String(describing:)` and give the unqualified name, label a fit-width memo
  and a served row for the render cache's verifier, `Table.swift`, and two
  assertion messages, `TableColumnContent.swift` and `TableRowContent.swift`,
  none of them saved).
- **The bundle is unchanged.** The directory holds Swift files only, so the
  bundle is still `TUI_TUIStrings` (decisions SPB2).
- **The documentation lists each module's modifiers on `View`, on that
  module's own types, and on those of the modules built on it, not on a
  sibling's.** `symbolgraph-extract` copies a protocol
  extension's members onto the conforming types of its own module only
  (decisions SPC1), and lists and tables are two modules now: `List`'s,
  `TabView`'s and `Grid`'s pages list neither `tableStyle` nor
  `tableColumnHeaders` among their default implementations, while `View`'s
  lists both (checked in the strict docs build's archive, 2026-10-09).
  `Table`'s page still lists TUILists' `listStyle` and
  `listRowSeparator`. "Its own module" qualifies the conforming types, not the
  extension: TUITables imports TUILists (and re-exports it, below), so
  TUILists' `View` extension is loaded when TUITables' graph is
  extracted, and its members are copied onto `Table`, a type of TUITables'
  own (`Table/listStyle(_:)` is in `TUITables.symbols.json`, extracted
  with Xcode's `swift-symbolgraph-extract`, 2026-10-10). TUILists loads
  nothing of the tables', so its types get no copy of theirs. Whether an
  import that does not re-export would do the same is unmeasured. The archive
  has 46,817 pages against step C1's 46,868.
  No doc link had resolved only through such a copy: the strict build
  reports nothing.
- **`import TUITables` brings lists too**, once per-module products ship:
  it re-exports TUILists (plan §4: "Tables re-exports Lists"), whose row
  engine a table runs on. **`import TUILists` no longer brings tables.**
  Under the umbrella, which is the only product today, nothing changes.
- **No other module gained an edge.** TUIColorPicker and every other
  carved module name no declaration of the directory (the pre-peel index: 0
  references), and no file of TUILists names one (the post-peel crossing
  report: 0 sites).

### B. Shipped

#### B-SPC2-1. Set T: the row memo crosses with its bodies; the handler's members a table calls once a frame stay out of line

*Sources/TUILists/Views/TableRowMemo.swift, Focus/ItemListHandler+Reorder.swift — no API*

Plan §5 and the A1′ re-cut (tiers-A1p) name set T: nine callees a table calls
in TUILists, `@inlinable package`, with the state their bodies touch
`@usableFromInline`. Five of them are `ItemListHandler`'s own members:
`publishRowBands(_:)`, `isSelected(at:)`, `id(at:)`,
`drawnBands(_:slide:rowsTop:lineCount:)` and `reorderRemovedRows`.

**Shipped:**

- The row memo's per-row members are `@inlinable package` on
  `@usableFromInline` structs: `TableRowMemoStore.keep(_:for:)`, both
  `TableRowMemoLine.answers`, which set T names, and on the same path
  `entry(for:)`, `refresh(row:for:)`, the line's initializer,
  `drawn(striped:)` and `keep(_:striped:)`, and an explicit
  `TableRowDrawnLine` initializer. The store is reached through
  `ItemListHandler.tableRowMemo`, which stays a stored property, changed in
  place (B-SPC2-2).
- `reorderDrawnRows(_:)` takes a `Range<Int>`, a concrete entry beside the
  generic `reorderDrawnRows(_:excluding:)` that `List` calls with an array:
  the generic one, called from another module with the caller's own type,
  is its unspecialised entry (crossing_hazards' HAZARD-GENERIC; SPB6's R1).
- The handler's five stay out of line, `package`: a table calls each once a
  frame (`isSelected(at:)` and `id(at:)` once a frame or per event; the
  per-row selection test is `drawsSelected(at:)`, which runs both inside
  TUILists).

**The other version:** the five `@inlinable`. **Price:** an `@inlinable`
member of a type that is neither public nor `@usableFromInline` gets no body
in another module, and a `@usableFromInline` class must make every member that
witnesses one of its protocols' requirements `@usableFromInline` too: the
build asked for at least 25 (`Focusable`, `ScrollableOffsetState`), among them
stored properties whose accesses are statically enforced (`focusID`,
`canBeFocused`, `scrollOffset`, `viewportHeight`), each of which would keep a
run-time exclusivity check from then on, or would need private storage under
an accessor. And the bodies read handler state that CONTRIBUTING's rule keeps
behind out-of-line accessors (`itemCount`, `idAt`, `visibleRowBands`,
`externalDropSlot`), so inlined they would make more calls than the one they
save. Worth revisiting only if the A/B finds the five.

#### B-SPC2-2. Four of the handler's stored properties are `package` and stored; 42 others are private storage under accessors

*Sources/TUILists/Focus/ItemListHandler.swift, Views/RowContextMenuHost.swift, Views/RowReorderPayload.swift — no API*

The peel widens what a table names in TUILists, and since a `package` class
must make each member that witnesses one of its protocols' requirements as
visible, the handler's witnesses too. CONTRIBUTING.md ("Crossing a module
boundary") keeps a class's stored property private, under a `package`
accessor, unless the binary shows every access to it dynamically enforced
already.

**Shipped:** 42 private storages under accessors (39 of the handler's, the
reorder grab point's `x` and `y`, the row menu state's `target`), and four of
the handler's `package` and stored, each with its evidence in its doc
comment: `tableRowMemo` and `returningRows`, which a table reads for every row
it draws (the first changed in place: under a getter and setter each change
would copy the store's dictionary), and `reorder` and `outlineActivation`,
whose checks stay whichever way they are written. Measured, in two release
binaries: widening all fourteen dynamically enforced properties stored gave
each a getter, setter and `modify` with a check of its own, for its property
descriptor (39 static `swift_beginAccess` sites that nothing calls); as
private storage under an accessor, ten of the twelve others lost every check,
which also takes checks off `List`'s and `Table`'s row composition; `reorder`
and `outlineActivation` kept theirs, in their accessors, which TUILists
then called where it had read them in place.

**The other version:** every one private storage under an accessor, as the
rule's letter has it. **Price:** a table's per-row memo test and keep through
a getter and setter copies the store's dictionary on each change (so through
seven forwarding methods on the handler instead, or a `_modify` accessor,
whose coroutine frame another module allocates on the heap, SPB6's R3), and
`returningRows` and `reorder` become calls where both modules read them in
place. Or every dynamically enforced one stored: +27 static sites of
accessors nothing calls, and the checks the ten others would keep.

### C. Declined

None.

### For the coordinator (not decisions)

- **peel.py (C2):** the known `tablecolumn` page-guard addition (undone by
  hand: `table` covers the directory); a false-positive warning that
  `ItemListHandler.swift` "seems to name TUITables's lastRow" (a local
  name; the build has no such edge); four `@testable import TUITables`
  it could not see textually (DrawnNothingPopupGestureTests,
  TableColumnGestureTests, TableColumnLineLimitTests, TableStyleTests, which
  reach `subscript(width:)`, `lineLimit` and a style's `Configuration`); and
  its CONTRIBUTING row draft says "peeled off" where C1's row says "peeled
  out of".

## Completing the SwiftUI API: decisions from lane SPC3

*Lane SPC3 took steps C3 and C4 of the module split
([`Module split plan, revision 4`](<The module split.md>),
§5), 2026-10-10: the third and fourth PEELS, the last two of the Lists group.
`Sources/TUITabs` left the Lists group of step B6 for a target of its own,
TUITabs, built on TUIFoundation and TUILists, and then
`Sources/TUIGrid` for TUIGrid, built on TUIFoundation alone; the
residual TUILists compiles the lists alone, an ordinary target, and depends
on neither new module. TUIColorPicker depends on TUITabs in place of
TUILists. The steps changed no public API: the umbrella re-exports both new
modules, so `import TUI` gives an app what it gave before. This file holds
the judgement calls the steps reached that the plan did not already settle, in
the format of
[the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>):*

- **A-SPC3-n — needs your decision.** Nothing has shipped for these.
- **B-SPC3-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPC3-n — declined.** With the reason.

### What an app can see

Not judgement calls: the plan (§5, row C9a) lists these for the release notes,
and C9a writes them. They are recorded here because these steps made them. Each
name below was `TUILists`' from step B6, `TUIFoundation`'s after step
B1, and `TUI`'s in v0.6.0.

- **Reflected names.** `String(reflecting:)`, `dump` and the debugger name the
  new modules: `TUITabs.TabView<…>`, `TUITabs.TabViewCustomization`,
  `TUITabs.TabBarPlacement`; `TUIGrid.Grid<…>`, `TUIGrid.GridItem`,
  `TUIGrid.GridItem.Size`. They read `TUILists.` from step B6 until these
  steps (decisions SPB6, "What an app can see", said they would change at C3
  and C4), so a release that ships both should give the new names.
  `UmbrellaQualifiedNameTests` pins them. The lists' names are unchanged
  (`TUILists.EditMode`, `TUILists.SidebarListStyle`).
- **Saved state is unaffected.** The two directories' one `Codable` type,
  `TabViewCustomization`, encodes the stated sidebar visibilities by tab
  identifier, each section's tab order and the section order, and no type name
  (`TabViewCustomization.swift`, `encode(to:)`), so a customization an app saved
  through `@SceneStorage` or `@AppStorage` decodes as before. No declaration of
  either directory is something a `NavigationPath` stores by name (checked by
  grep, 2026-10-10: no `_mangledTypeName`, `String(reflecting:)` or
  `String(describing:)` of a type in either directory).
- **The bundle is unchanged.** Both directories hold Swift files only, so the
  bundle is still `TUI_TUIStrings` (decisions SPB2).
- **The documentation lists each module's modifiers on `View`, on that
  module's own types, and on the types of a module that re-exports it.**
  Grid's and `LazyVGrid`'s pages no longer list TUILists' `listStyle`,
  `listRowSeparator`, `selectionDisabled` or `sectionActions`, and `List`'s
  lists no `tabViewStyle`; `TabView`'s and `Table`'s still list the lists'
  modifiers (TUITabs and TUITables re-export TUILists), and
  `View`'s lists them all (checked in the strict docs build's archive,
  2026-10-10). Member pages: `List` 358 -> 344, `Grid` 320 -> 290, `TabView`
  317 -> 313, against step C2's archive; the archive has 46,581 pages
  against its 46,817. No doc link had resolved only through such a copy: the
  strict build reports nothing.
- **`import TUITabs` brings lists too**, once per-module products ship: it
  re-exports TUILists, which a sidebar tab view lists its tabs in.
  **`import TUIGrid` brings TUIFoundation and nothing of the lists'.**
  **`import TUILists` no longer brings tab views or grids**, and
  `import TUIColorPicker` brings TUILists through TUITabs. Under the
  umbrella, which is the only product today, nothing changes.
- **No other module gained an edge.** No file of TUILists, TUITables or
  any other module names a declaration of either directory but
  TUIColorPicker's of the tabs' (the crossing reports after each peel: 0
  sites), and no grid file names one of TUILists'.

### B. Shipped

#### B-SPC3-1. A sidebar tab view's list is built in TUILists, not by the tab view

*Sources/TUILists/Views/SidebarSectionList.swift, Sources/TUITabs/Views/TabViewSidebar.swift — no API*

A `.sidebarAdaptable` tab view lists its tabs in a `.sidebar` `List`, one
section per run of tabs, each with its `TabSection`'s actions through
`sectionActions(content:)`. That modifier's `some View` names
`_SectionActionsView`, internal to TUILists, so once the tab views were a
module of their own the list's content asked the runtime for that type's
conformance on every evaluation of the sidebar (CONTRIBUTING.md, "Crossing a
module boundary"; seen in the carve's release Stress, and flagged by the
crossing predictor before it).

**Shipped:** TUILists builds the list: `_SidebarSectionList`, a `package`
view generic over the row's type, takes the sections (header, actions, rows by
place), the selection by place and the row, and applies the `.sidebar` style;
the tab view keeps each row's label, badge, spring loading and interactions,
`.textSelection(.disabled)` and Shift+F10. Nothing draws differently. The lookup
is gone; the list's body runs unspecialised in TUILists (it cannot name the
tab view's row type), about a dozen generic calls into TUIFoundation and
TUIView per evaluation through metadata the runtime keeps, unmeasured against
the lookup. The list sits one level deeper in the view identity.

**The other version:** keep the list in TUITabs and give it each section
through a `package` wrapper in TUILists that holds the section with its
actions and forwards the list's section protocols (`SectionPartsProviding`,
`SectionRowExtractor`, and `ChildViewProvider` for a section outside a list)
with the identity step its body adds. The list stays specialised in the tab
view's module, at one generic call per section. Price: about 40 lines that
duplicate what `_SectionActionsView` answers, and every protocol a list asks a
section must be forwarded and kept so, or a sidebar section silently draws as a
row. No Stress scenario had a sidebar tab view, so neither is measured; the
coordinator's A/B cannot see the difference. (Since 2026-10-19
`app-shapes/sidebar-tabs` has one, and `grids` the grids below.)

#### B-SPC3-2. Of plan tier 2's step-C3 callees, only `selectionDisabled(_:)` is annotated

*Sources/TUILists/Extensions/View+SelectionDisabled.swift, Modifiers/SelectionDisabledModifier.swift — no API*

The A1′ re-cut (tiers-A1p) lists six tier-2 callees that first cross at C3:
`EnvironmentValues.liftedSurface`, `List.init(selection:content:)`,
`listStyle(_:)`, `sectionActions(content:)`, `ListStyle.sidebar` and
`selectionDisabled(_:)`. The coordinator's rule for this step: annotate only
what the release binary shows called on a per-frame path.

**Shipped:** after B-SPC3-1 four of them are TUILists' own calls and do not
cross. `selectionDisabled(_:)` did, once for every row a sidebar lists on every
evaluation, unspecialised (inlined in the base and premod): it is `@inlinable`,
with `SelectionDisabledModifier`'s memberwise initializer `@inlinable` and its
two fields `@usableFromInline`; its result type was public already, and the
binary shows the call gone. `liftedSurface`, three calls a tab view's draw,
stays a plain `package` getter: premod called it out of line as well, so the
peel changed nothing that runs.

**The fuller version:** `liftedSurface` `@inlinable` too, which would make a
tab view's draw cheaper than premod's by three calls. Price: TUIView's
`surfaceBackground` accessor and its environment key `@usableFromInline` (or
`@inlinable package`), state no other module needs to see. Not done: nothing
regressed there.

### Not done here

- **Grid's crossings into TUIFoundation.** Step C4 adds none: a grid's calls
  into TUIFoundation have crossed a module boundary since step B6 carved the
  Lists group. The crossing report lists them (per cell: `CellRect`'s fields,
  stored; the lattice's alignment offsets; `LayoutSubview.sizeThatFits(_:)`,
  tier 2 at B6), and one opaque-result hazard: `layoutValue(key:value:)`, which
  `gridCellColumns(_:)` and the other cell modifiers call. No Stress scenario
  has a grid (grep), so none is measured; they are B6's, and unchanged here.

## Completing the SwiftUI API: decisions from lane SPC5

*Lane SPC5 took steps C6 and C5 of the module split
([`Module split plan, revision 4`](<The module split.md>),
§5), 2026-10-10: the first two PEELS of the TextInput group, the forms first.
`Sources/TUIForms` left the coarse group of step B7 for a target of its own,
TUIForms, built on TUIFoundation alone, and then `Sources/TUISearch`
for TUISearch, built on TUIFoundation and TUITextInput; the residual
TUITextInput compiles the text inputs, the pickers and the numeric controls
until steps C7 and C8, and depends on neither new module. The step numbers are
the plan's (C5 search, C6 forms); the lane took them in the other order, which
the map allows, since neither module depends on the other. The steps changed no
public API: the umbrella re-exports both new modules, so `import TUI` gives
an app what it gave before. This file holds the judgement calls the steps
reached that the plan did not already settle, in the format of
[the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>):*

- **A-SPC5-n — needs your decision.** Nothing has shipped for these.
- **B-SPC5-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPC5-n — declined.** With the reason.

There is no A or C entry: the steps reached no question that needs the owner,
and declined nothing.

### What an app can see

Not judgement calls: the plan (§5, row C9a) lists these for the release notes,
and C9a writes them. They are recorded here because these steps made them. Each
name below was `TUITextInput`'s from step B7, `TUIFoundation`'s after
step B1, and `TUI`'s in v0.6.0.

- **Reflected names.** `String(reflecting:)`, `dump` and the debugger name the
  new modules: `TUIForms.Form<…>`, `TUIForms.LabeledContent<…>`,
  `TUIForms.GroupBox<…>`, `TUIForms.Card<…>`, `TUIForms.Panel<…>` and
  the form, group box and labeled content styles (`TUIForms.AutomaticFormStyle`,
  `TUIForms.GroupedFormStyle` …); `TUISearch.SearchFieldPlacement`,
  `TUISearch.SearchFieldIconPlacement`, `TUISearch.DismissSearchAction`,
  `TUISearch.SearchScopeActivation` and the toolbar behaviours. They read
  `TUITextInput.` from step B7 until these steps (decisions SPB7, "What an
  app can see", said they would change at the peels), so a release that ships
  both should give the new names. `UmbrellaQualifiedNameTests` pins them. The
  text inputs', pickers' and numeric controls' names are unchanged
  (`TUITextInput.TextField<…>`, `TUITextInput.TabWidth`,
  `TUITextInput.TrackStyle`).
- **Saved state is unaffected.** Neither directory declares a `Codable` type,
  and no declaration of either is something a `NavigationPath` stores by name
  (checked by grep, 2026-10-10: no `Codable`, `_mangledTypeName`,
  `String(reflecting:)` or `String(describing:)` of a type in either
  directory).
- **The bundle is unchanged.** Both directories hold Swift files only, so the
  bundle is still `TUI_TUIStrings` (decisions SPB2).
- **The documentation lists each module's modifiers on `View`, on that
  module's own types, and on the types of a module that re-exports it**
  (decisions SPC3). `Form`'s, `GroupBox`'s and `LabeledContent`'s pages list
  the forms' style modifiers and no longer TUITextInput's (`searchable`,
  `textFieldStyle`, `pickerStyle` and the rest), and `TextField`'s and
  `Picker`'s list neither the forms' nor search's; `View`'s lists them all
  (checked in the strict docs build's archive, 2026-10-10: member pages `Form`
  287, `GroupBox` 290, `LabeledContent` 293, `TextField` 333, `Picker` 335,
  `View` 520). The archive has 45,548 pages, against 46,581 in lane SPC3's
  record of step C3 (step C4 moved some too). No doc link had resolved only
  through such a copy: the strict build reports nothing.
- **`import TUIForms` brings TUIFoundation and nothing of the text
  inputs'**, once per-module products ship. **`import TUISearch` brings
  TUITextInput too**: it re-exports it, since a search field is a
  `TextField` and its scope bar a `Picker`, so the text inputs, and the pickers
  and numeric controls until steps C7 and C8, come with it. **`import
  TUITextInput` no longer brings forms or search**, nor does `import
  TUIColorPicker`, which re-exports TUITextInput. Under the umbrella,
  which is the only product today, nothing changes.
- **No other module gained an edge.** No file of TUITextInput,
  TUIColorPicker or any other module names a declaration of either
  directory (the crossing reports after each peel: 0 sites), and no form file
  names one of TUITextInput's.

### B. Shipped

#### B-SPC5-1. Of plan tier 2's step-C5 callees, all three are annotated; the search field's initializer is not

*Sources/TUITextInput/Views/TextInputSuggestions.swift — no API*

The A1′ re-cut (tiers-A1p) lists three tier-2 callees that first cross at C5:
`EnvironmentValues.textInputSuggestions`, `TextSuggestions.none` and
`TextSuggestions.offering(_:tokenSink:)`. The coordinator's rule for these
steps: annotate only what the release binary shows called on a per-frame path.

**Shipped:** the carve's release Stress showed all three called out of line
on every evaluation of a `.searchable` (the field's suggestions, the search
suggestions' environment default, and the key path the field's
`transformEnvironment` writes through), where the base and premod inlined them,
and the inbox session evaluates its searchable every frame. They are
`@inlinable package`, with `TextSuggestions`, its fields, `_TextSuggestionEntry`
and `SearchTokenSink` `@usableFromInline`, the environment key
`@usableFromInline package` rather than `private`, and `tokenSink` a `let` with
no default, so that the inlined initializer runs no stored-property default out
of line. The binary shows the three calls gone, and every static total
unchanged.

What still crosses out of line on that path, and did not in the base or
premod: the search field's `TextField.init(verbatimTitle:text:prompt:)`, one
call per evaluation, behind the public initializer that conservative
cross-module optimisation inlines; and `SearchTokenSink.init(choice:)`, once
per evaluation of a searchable with tokens, which no scenario has.

**The fuller version:** `TextField`'s internal initializer `@inlinable` too.
Price: the ten stored properties of `TextField` (the editing closures, the
value formatting and the selection channel among them) `@usableFromInline`, and
the defaults of `axis` and `selection` assigned in each initializer instead
(CONTRIBUTING.md, "Crossing a module boundary"), to save one call per frame of
a searchable, in which the field's construction itself is the cost. Not done:
the A/B (batch 2, the inbox session) prices the call first.

### Not done here

- **The forms' and search's crossings into TUIFoundation.** These steps add
  none: both directories' calls into TUIFoundation have crossed a module
  boundary since step B7 carved the TextInput group. The crossing reports list
  them (forms: 133 sites in 59 callees, among them B7's `erasedID` and
  `erasedBorder` entry points for a form's `if` groups and grouped section
  boxes, and 33 generic callees called unspecialised, the stacks' and
  `frame`'s; search: 76 sites in 33 callees). They are B7's, and unchanged
  here; the coordinator's batch-2 A/B measures app-shapes, the dashboard,
  framed columns, key rows and the settings and inbox sessions, which reach
  them.

## Completing the SwiftUI API: decisions from lane SPC7

*Lane SPC7 took steps C8 and C7 of the module split
([`Module split plan, revision 4`](<The module split.md>),
§5), 2026-10-10: the last two PEELS of the TextInput group, the pickers first.
`Sources/TUIPickers` left the coarse group of step B7 for a target of its
own, TUIPickers, built on TUIFoundation alone, and then
`Sources/TUINumericControls` for TUINumericControls, built on
TUIFoundation alone too; the residual TUITextInput compiles the text
inputs alone and depends on neither. TUISearch gained its planned edge to
TUIPickers, and TUIColorPicker its edges to both. After these steps every
planned module of the split is a target of its own at its default path, and
Package.swift's helper for a target over several directories is gone. The step
numbers are the plan's (C7 numeric controls, C8 pickers); the lane took them in
the other order, which the map allows, since neither module depends on the
other. The steps changed no public API: the umbrella re-exports both new
modules, so `import TUI` gives an app what it gave before. This file holds
the judgement calls the steps reached that the plan did not already settle, in
the format of
[the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>):*

- **A-SPC7-n — needs your decision.** Nothing has shipped for these.
- **B-SPC7-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPC7-n — declined.** With the reason.

There is no A or C entry: the steps reached no question that needs the owner,
and declined nothing.

### What an app can see

Not judgement calls: the plan (§5, row C9a) lists these for the release notes,
and C9a writes them. They are recorded here because these steps made them. Each
name below was `TUITextInput`'s from step B7 and `TUIFoundation`'s after
step B1 (and `TUI`'s in v0.6.0, for those it had).

- **Reflected names.** `String(reflecting:)`, `dump` and the debugger name the
  new modules: `TUIPickers.Picker<…>`, `TUIPickers.RadioButtonGroup<…>`,
  `TUIPickers.RadioButtonItem<…>`, `TUIPickers.DatePicker<…>`,
  `TUIPickers.DatePickerComponents`, `TUIPickers.RadioButtonOrientation`,
  `TUIPickers.RadioButtonGroupEdgeBehavior` and the picker and date picker
  styles (`TUIPickers.MenuPickerStyle`, `TUIPickers.SegmentedPickerStyle`,
  `TUIPickers.GraphicalDatePickerStyle` …);
  `TUINumericControls.Slider<…>`, `TUINumericControls.SliderTick<…>`,
  `TUINumericControls.Stepper<…>`, `TUINumericControls.Gauge<…>`,
  `TUINumericControls.ProgressView<…>`, `TUINumericControls.TrackStyle`,
  `TUINumericControls.IndeterminateStyle` and the gauge and progress view
  styles (`TUINumericControls.LinearCapacityGaugeStyle`,
  `TUINumericControls.CircularProgressViewStyle` …). They read
  `TUITextInput.` from step B7 until these steps (decisions SPB7, "What an
  app can see", said they would change at the peels), so a release that ships
  both should give the new names. `UmbrellaQualifiedNameTests` pins them. The
  protocols the styles conform to that TUIFoundation declares
  (`PickerStyle`, `AutomaticPickerStyle`, `GaugeStyle` and its configuration)
  keep their `TUIFoundation.` names, and the text inputs' are unchanged
  (`TUITextInput.TextField<…>`, `TUITextInput.TabWidth`).
- **Saved state is unaffected.** Neither directory declares a `Codable` type,
  and no declaration of either is something a `NavigationPath` stores by name
  (checked by grep, 2026-10-10: no `Codable`, `_mangledTypeName`,
  `String(reflecting:)` or `String(describing:)` of a type in either
  directory).
- **The bundle is unchanged.** Both directories hold Swift files only, so the
  bundle is still `TUI_TUIStrings` (decisions SPB2).
- **The documentation lists each module's modifiers on `View`, on that
  module's own types, and on the types of a module that re-exports it**
  (decisions SPC3). `Picker`'s, `DatePicker`'s and `RadioButtonGroup`'s
  pages list the pickers' style modifiers (`pickerStyle`, `datePickerStyle`,
  `radioButtonGroupEdgeBehavior`) and no longer the text inputs'
  (`textFieldStyle` and the rest) or the numeric controls' (`gaugeStyle`,
  `progressViewStyle`, `sliderShowsValue`); `Slider`'s, `Stepper`'s, `Gauge`'s
  and `ProgressView`'s list the numeric controls' and neither the pickers' nor
  the text inputs'; `TextField`'s lists neither; `View`'s lists them all
  (`trackStyle` is a member of `Slider` and `ProgressView` alone, as before).
  Checked in the strict docs build's archive, 2026-10-10: member pages
  `Picker` 310, `DatePicker` 303, `RadioButtonGroup` 291, `Slider` 304,
  `Stepper` 307, `Gauge` 297, `ProgressView` 309, `TextField` 316, `View` 520
  (lane SPC5's record of step C5: `Picker` 335, `TextField` 333, `View` 520).
  The archive has 45,228 pages, against 45,548 in that record. No doc link had
  resolved only through such a copy: the strict build reports nothing.
- **`import TUIPickers` and `import TUINumericControls` each bring
  TUIFoundation and nothing of the text inputs'**, once per-module products
  ship. **`import TUITextInput` no longer brings pickers or numeric
  controls.** **`import TUISearch` brings TUIPickers too**: it re-exports
  it, since its scope bar is a `Picker`, beside TUITextInput (a search field
  is a `TextField`). **`import TUIColorPicker` brings both**, beside
  TUITextInput: its editors are `Slider`s, its channel picker a
  `RadioButtonGroup`, its hex field a `TextField`. Under the umbrella, which is
  the only product today, nothing changes.
- **No other module gained an edge.** No file of TUITextInput,
  TUIPickers, TUINumericControls or any other module names a
  declaration of the other two peeled-apart directories (the crossing reports
  after each peel: 0 sites), and nothing but TUISearch and
  TUIColorPicker names the pickers, and nothing but TUIColorPicker the
  numeric controls.

### B. Shipped

#### B-SPC7-1. `TrackRenderer.gradientColor` stays in TUINumericControls, a `package` call from TUIColorPicker, not `@inlinable`

*Sources/TUINumericControls/Rendering/TrackRenderer.swift — no API*

`TrackRenderer.gradientColor(_:index:span:fallback:depth:)` gives the colour
of one cell of a gradient spread over a span of cells. The track renderer
calls it for every cell of a gradient track it draws, inside
TUINumericControls, and TUIColorPicker's gradient editor calls it once
per column of its preview strip and of each preset chip, every time the
editor's body is evaluated. Step B4 made it `package` for the colour picker,
when the colour picker became a module of its own; the step's brief asked
where it should live once the numeric controls are one too, decided by that
per-column call.

**Shipped:** it stays where it was, in the track renderer, `package` and not
`@inlinable`, so the per-cell calls stay inside the module that makes them,
and the colour picker's per-column call crosses into TUINumericControls
as it crossed into TUIFoundation from step B4 and into TUITextInput
from step B7 (the release binaries: the same two call sites, out of line in
the base and now; the one-module build before the split, c181ec0f9, inlined
both). Each call asks `Color.quantisedRamp` (TUIStyling) for the
gradient's ramp over the span, which serves a span of more than two cells
(the editor's are 36 and 8) from its cache once it holds it: a lock,
hashing the `Gradient` into the cache key, and a dictionary probe. Only a
miss samples the ramp, and at 256-colour depth repairs it into a monotone
one. Even the probe costs far more than a call (reasoned, unmeasured), so
a cross-module call adds nothing a strip column would notice; no Stress
scenario draws the editor. (Step C7's commit message, 059fa6908, says the
body quantises the whole ramp on every call; it does not.)

**The fuller version:** `@inlinable package`, with `TrackRenderer`
`@usableFromInline` and stating `Sendable` (CONTRIBUTING.md, "Crossing a
module boundary"; UsableFromInlineSendabilityTests would pin it), so the
colour picker inlines the five-line body. Price: one more `@usableFromInline`
type, for a call whose own work is a ramp-cache probe per column. Moving it
down into TUIFoundation instead would make every per-cell call of the
track renderer cross a module, which is the wrong way round.

### Not done here

- **The pickers' and numeric controls' crossings into TUIFoundation.**
  These steps add none: both directories' calls into TUIFoundation have
  crossed a module boundary since step B7 carved the TextInput group. The
  crossing reports list them (pickers: 319 member sites in 140 callees, 20 of
  them generic callees called unspecialised, the stacks', `Label`'s and the
  tag helpers'; numeric controls: 310 sites in 100 callees, 11 generic). They
  are B7's, and unchanged here; the coordinator's batch-3 A/B measures the
  menus, themes and settings sessions, app-shapes' settings form,
  control-rows' progress variant and the dashboard, which reach them.

## The module split's run-time cost, step by step (2026-10-07 to 2026-10-10)

> **Status:** recovered and landed by 2026-10-10 (the last remedies in `a773b5b61`, `5b65beb61` and `4462eb015`),
> with one small residual left open. **Decided by:** the owner (the goal and the gate), lanes and the coordinator
> (each remedy, recorded in the step's decisions file). **Working notes** (not in git): `SPB5/regress/`,
> `SPB5b/regress/`, `SPB6/regress/` (profiles and diagnoses), `CTL/diagnosis.md`, `perf/results/sp*` (the A/B runs),
> and the coordinator's ledger `plan/QUEUE.md`.

### Question

Splitting TUI's one module into about thirty turns some calls that were inside a module into calls across a
module boundary, where the optimiser can no longer see the callee. How much run time does that cost, and how is it
won back? The owner, 2026-10-08: "are these impacts cumulative? Are we losing a percent or two of performance with
every module that gets split out? Because that would be really bad." And: "I anticipate some initial performance
loss from the modularisation, but my hope is we can recover all the regressions with some care … Hopefully relevant
optimisations like inlining annotations etc can suffice. The baseline is pre-modularisation work."

### Answer

- **Against the pre-split build, the finished split is neutral.** Warm, over six code placements: `controls`
  −4.35% (faster than before the split), `table-tail` +0.55%, everything else flat. Cold: nothing slower. A stripped
  Stress is 1.06% larger (+137.5 KB, Xcode's 6.2.4).
- **The costs came in a few classes, each with a split-related remedy:**
  - a generic call made unspecialised by the boundary (a shortcut table per row, a list row's buffer, a tap
    gesture's `onEnded`, a table's scroll window): the callee `@inlinable` with the state it touches
    `@usableFromInline` (the plan's tier 2);
  - class properties widened to `package`, which gained dynamic exclusivity and main-actor checks: private storage
    under `package` accessors;
  - small getters no longer inlined (`Text`'s unstyled check, a bordered container's body lines): inlined again;
  - opaque result types naming another module's internal types, resolved at run time on every call (the inline
    menu column): the code moved back to where the types are concrete, and a CONTRIBUTING rule and a predictor for
    the next carves;
  - a `static let` read from another module calls its addressor: kept, by the owner's ruling (A-SPH2-1).
- **Much of what looked like cost was code placement.** `geometry`, `customlayout` and `app-shapes` moved by 1–1.6%
  when 1 KB of unrelated code was added, so they were judged by A/Bs averaged over six placements.

### Key measurements

`ab_bench`, paired, warm and cold, on a quiet machine, Xcode's 6.2.4 release `Stress`; the baseline is `premod-h`,
c181ec0f9 (the commit before the split's first refactor) with the benchmark harness's later fixes. Each regression
was profiled with `Tools/Profiling` and compared by static counts of runtime calls in the binary.

| step (modules carved) | worst against the baseline | cause | remedy |
|---|---|---|---|
| B1, B2 (Foundation, Strings, TerminalHost) | +0.7% warm and cold, against step A's build | — | none needed |
| B3 to B5 (App, ColorPicker, Navigation) | `app-shapes` +1.6% warm, +2.0% cold, from B3 to B5 | placement: a 1 KB pad moved the same scenarios as much | none for speed |
| B6 (Lists), with its first fixes | warm `megalist` +3.8%, `kitchensink` +3.5%; cold `tables-vstack` +3.5% | three unspecialised or out-of-line calls; exclusivity and main-actor checks on widened class properties | lanes SPH, SPH2, SPH3; then flat warm, cold `table-api` +0.5% |
| B5b, B5c (Chrome, Effects, Menus; Bitmaps) | `menus` cold +0.9% | the inline menu column's opaque results (≈0.15–0.24 points); the rest placement | lane SPM1 (with B5c's placement, nothing was slower cold already) |
| B7 (TextInput) | `controls` +0.4% warm; nothing cold | — | — |
| C1 to C8 (eight peels, in batches of two lanes) | warm `controls` +0.6% to +1.1%, `kitchensink` +1.1% (C3 to C6), `table-tail` +0.6% (C7, C8); cold up to +0.9% (C3 to C6), nothing after C8 | a table's scroll window not inlinable; a tap gesture's `onEnded` called generically for every row | `d7ce43ffd`; lane RES |
| after RES | warm `controls` −4.35%, `table-tail` +0.55%; cold nothing (C8's run) | `table-tail`: mostly unattributed | open, low priority |

Static counts in a release `Stress` after B7, against the baseline: main-actor executor checks 1,383 (1,488), access
checks 3,938 (4,194): both below the pre-split build.

### Reasoning

- **The gate changed with experience.** At first each carve was held until it was clean. The owner, 2026-10-09:
  "we're only trying to identify serious regressions that could be real showstoppers or require a different
  approach. Smaller regressions that merely require some optimisation can be done later, so long as we are pretty
  confident we know what to do". So the C steps landed in batches, each batch's small costs queued with a named
  remedy, and the goal of recovering everything stayed.
- **Three measurement faults were found and fixed on the way:** the profile analyser dropped repeated stacks, so
  shares before `65abd024e` counted 21–64% of the samples; the cold benchmark harness leaked each frame's context, so
  cold A/Bs before its fix (lane ST3) were invalid for the leaking scenarios; and `megalist`'s A/B cannot be resolved
  at all (identical bytes differ by 8% with the path length).
- **Remedies stayed split-related,** as the owner asked: inlining annotations, access levels, keeping hot code
  inside one module, non-generic helpers. Pre-made specialisations were evaluated and not adopted
  ([pre-specialisation](<Compile time and the test targets.md>)).

### Links

Decisions, one file per step and per recovery lane, in
the step records below: in particular
[SPH](<Winning back the module split's cost.md>),
[SPH2](<Winning back the module split's cost.md>),
[SPH3](<Winning back the module split's cost.md>),
[SPM1](<Winning back the module split's cost.md>)
and [RES](<Winning back the module split's cost.md>).
The plan: [Module split plan, revision 4](<The module split.md>). What the split
delivered: [build time, size and tests](<The module split.md>).

## What the module split delivered: build time, size and tests (2026-10-11)

> **Status:** landed: every planned module a target by 2026-10-10 (`e7f52c800`), library products for each on
> 2026-10-11 (`17a63a3a7`), the test suite in four targets on 2026-10-10 (`b377b5f24`). **Decided by:** the owner,
> 2026-10-07 (do the split, sooner) and 2026-10-11 (per-module products). **Working notes** (not in git):
> `buildtime/` (the analysis, the M3 trial split, the plan's revisions), `perf/c9bt/` (products against the
> umbrella), `TT1/` and `TT2/` (test targets), `TC2/baseline.md`, and the measurements quoted in each step's commit.

### Question

The owner, 2026-10-06: "I'm receiving reports that a full (clean) release build of TUI is taking many minutes
for some people … If we can reduce that significantly, that'll speed up our development, too", and, the same
evening, that release binary size matters as well. The plan that followed split the one 230,000-line module into an
umbrella over separately compiled modules, so that they compile in parallel and an app can depend on fewer of them
([plan, revision 4](<The module split.md>)). What did it deliver, against what the
plan estimated?

### Answer

- **Build time fell, but less than the plan's model said.** On Xcode's 6.2.4 the plan put a clean build of the
  finished split at 52.5 s (55.9 s conservatively) against 77.8 s measured before it; the steps' own measurements
  put the finished tree at about 57–58 s, on a busier machine. On 6.4.0 the same build went from about 102 s before
  the split to about 70 s. The build's peak memory roughly halved.
- **For a small app the larger win is the products:** a hello world on `TUIApp` compiles 8 of TUI's modules
  instead of 26, builds 15.6% faster from clean, and is 37.6% smaller stripped.
- **Run time is neutral** after the recoveries
  ([the split's run-time cost](<The module split.md>)); a stripped
  Stress is 1.06% larger.
- **Tests:** four umbrella test targets instead of one took a one-file test edit from about 60 to about 18 CPU
  seconds.
- **Faster than planned:** the coarse stage took 52 hours from the owner's go, against the plan's 3.5–4.5 weeks.

### Key measurements

The development machine, an arm64 macOS 15.8.1 VM with 12 cores, shared with other lanes except in a quiet window.

| what | before | after | how |
|---|--:|--:|---|
| clean release build, Xcode's 6.2.4 | 77.8 s | 63.1 s after the coarse stage (plan: 57.4 s); 57.3 s after step C2; 57.9 s after C5 and C6 | before: quiet box (plan rev. 4); after: one paired build per step, busy machine |
| clean release build, 6.4.0 | 102.4 s at the end of phase A | 69.2 s after C2; 69.1–72.2 s over C3 to C6 | before: `TC2/baseline.md`, a busy machine; after: each step's commit |
| peak memory of the build | 3.7–3.8 GB | 1.94 GB (Xcode's) and 2.25 GB (6.4.0) after B7 | before: the M3 trial's one-module baseline, quiet box; after: B7's commit |
| hello world, `TUI` against `TUIApp`, 6.4.0, clean build `-j 12` | 75.1, 68.9 s | 62.8, 58.7 s (−15.6%) | quiet window, two alternating rounds |
| the same, stripped | 9,552,376 B | 5,964,832 B (−37.6%) | with the internalize trait |
| the same, launch to first byte, and footprint | 7.1 ms, 2.85 MiB | 6.8 ms, 2.76 MiB | 20 runs each, in a PTY |
| stripped `Stress`, Xcode's 6.2.4 | 12,988,984 B | 13,126,504 B (+1.06%) | after step C8 |
| a one-file test edit, CPU | about 60 s | about 18 s | decisions TT2 |

The "after" build times are single pairs measured while other lanes built, by the commit of each step (`da8dbdb46`
for B7, `e2e8c7a3c` for C2); read the direction, not the tenths. No quiet-box clean build of the finished split, set
against the plan's estimate, is recorded in the working notes. The launch figures time the first byte the program
writes; its text appeared at about 1.5 s for both, because the PTY never answers TUI's terminal queries.

### Reasoning

- **Why less than the model:** the plan's model was fitted on the M3 trial split's quiet-box timings and does not
  model contention between parallel jobs, and the later measurements were taken on a shared machine. The critical
  path after the coarse stage was View, TUIFoundation, TUILists, TUIColorPicker and the umbrella, so
  TUIFoundation's job still bounds the build.
- **Why products matter more than parallelism for apps:** a release build compiles each module as one job whose type
  checking and SIL optimisation are single-threaded, so an app that compiles fewer modules saves more than one that
  compiles the same modules in parallel.
- **The split also cost bytes,** in the export table every app carried, which the
  [`UnexportTUISymbols`](<Binary size.md>)
  trait has since taken to 9 KB, and in duplicated weak definitions under Swift Build, about 16–33 KB per extra
  module until SwiftPM keeps private externs.

### Links

[Per-module products](<Per-module products.md>) (the products' design and trade-offs);
decisions for each step in
the step records below, and
[TT2](<Compile time and the test targets.md>);
README [Depending on fewer modules](../../../README.md#depending-on-fewer-modules) and
[Build time](../../../README.md#build-time); the
[compile time and binary size analysis](<Compile time and the test targets.md>) that led to
the split; [type-check time on Swift 6.4](<Compile time and the test targets.md>).
