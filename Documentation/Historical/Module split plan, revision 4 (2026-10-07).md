# Splitting TUI into modules: the plan, revision 4 (the refined map, checked)

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

## 0. The answer in one screen

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

## 1. The module map

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

### Names, as the owner asked

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

### Granularity

Five modules hold about 1% of the code or less: Menus 0.8%, Grid 0.7%, Search 0.7%, Forms 1.0% and TerminalHost 1.1%.
The owner's test is whether they lengthen an import list.
- **Under (b), nobody imports them.** `import TUI` stays the only import.
- **TerminalHost and Strings are never imported, even later.** Base re-exports them.
- **The leaves each earn their place (est.).** Folding Grid or Forms into Base puts +0.7 s or +0.5 s on every clean
  build, because Base is on every path; folding Menus into Base costs +0.9 s; folding Search into TextInput makes
  TextInput depend on Pickers. The cheapest merge, if fewer modules are wanted, is Grid into Forms: no build cost, and
  +0.07 MB for form apps à la carte.

### What Base holds now, and what left it

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

## 2. Base before and after: every cut, its seam, price and A/B

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

## 3. Critical path, and what apps compile and link

### The full clean build: every app's build under (b)

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

### When the win arrives (est., change in the family's end time after each step)

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

### What each kind of app compiles and links

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

## 4. Imports

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

## 5. What changes in the plan's steps

### The refactors (every seam)

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

### Runtime and the annotation tiers

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

### The steps, revised

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

## 6. What is not worth doing

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

## 7. Decisions for the owner

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

## 8. Verification (measured)

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

## 9. Files

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
