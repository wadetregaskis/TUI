# TUI versus SwiftTUI (swifttui.sh): competitive evidence

Date: 2026-10-31. Written for TUI's owner. Nothing here is in the repo.

**Snapshots read**
- SwiftTUI: `SwiftTUI/swift-tui` at `207913d23` (2026-10-30, just after release 0.20.0). Cloned depth 1 to `competitive/src/swift-tui`. Also `swift-tui-examples` and `swift-tui-counter-demo`. Sibling READMEs are in `competitive/site/`.
- TUI: local `main` at `3d605c2c4`. `TUITesting` (commit `90567b665`) is on a lane, not on `main`, so it counts as in progress throughout.

**Claim marks**
- **[V]** verified in source, by me, in this session.
- **[M]** measured, by me, in this session.
- **[S]** stated by the project (its docs, changelog or site), not independently verified.
- **[I]** inferred.

**Path shorthand**
- `ST:` is the SwiftTUI repo root.
- `V/` is `ST:Sources/SwiftTUIViews/`.
- `REG:` is `V/SwiftTUIViews.docc/Divergences-And-Gaps.md`, their divergence register.
- Bare `Sources/…`, `Tools/…` and `Documentation/…` are in TUI.

**Limits that apply everywhere**
- **I did not build or run SwiftTUI.** `ST:Package.swift:578` has an `unsafeFlags` entry, and `counter-demo/counter/Package.swift:38` has one, so your condition for building failed.
  - Both are benign on reading. One is `--export-dynamic` for a Linux debug test target. The other is `/STACK:16777216` on Windows.
  - TUI's own manifest carries `unsafeFlags` too (`Package.swift:1143,1153`).
  - If you relax the rule, the rest of this report could get real numbers. Swift 6.4.0 is installed under swiftly.
- Consequently nothing about SwiftTUI's runtime behaviour, frame cost, idle CPU, binary size or compile time is measured here.
- Web pages were read as text only. No browser, so the live demo and page visuals were not seen. The forum thread was read through a summarising fetch, so treat its details as second-hand.

---

## 1. Identity: which project this is

**swifttui.sh is the site of `github.com/SwiftTUI/swift-tui`.**
- The site footer links that repo and credits OPTIONAL.DEV [V: `competitive/site/index.txt`].
- The repo's `homepage` is `https://SwiftTUI.sh`; GitHub org `SwiftTUI`, created 2026-05-15 [M: GitHub API].
- Author: Adam Zethraeus. Commits are by `adam-zethraeus` (`adam@zethrae.us`) [M: API].
- optional.dev is his personal site, lists SwiftTUI as its one project, and shows no paid offering [S: fetched].
- He announced it on the Swift Forums on 2026-08-18 [S: https://forums.swift.org/t/swifttui-a-terminal-ui-framework-for-swift/89032].
- MIT licence [V: `ST:LICENSE`]. Self-described as a public beta with breaking changes possible [S: `ST:README.md`].

**Names a reader could confuse**
- `rensbreur/SwiftTUI` is a different, older project: 1,537 stars, created 2022, last pushed 2024-07 [M: API]. The new project credits its research [S: forum].
- TUI's own site is `swift-tui.com`, while this project's repo is `SwiftTUI/swift-tui` and its site is `swifttui.sh`. Those names are nearly identical, so readers could mistake one for the other [I].
- `phranck/TUIkit` (73 stars) is TUI's upstream [V: `README.md` credits]. The forum thread names TUIkit, not TUI, as the comparable project [S].

---

## 2. One-page assessment

Ranked by how much each point matters to someone choosing a framework today.

| # | Deciding question | Who is ahead | The fact |
|---|---|---|---|
| 1 | How much of my SwiftUI code and knowledge carries over? | **TUI, by a wide margin** | Same extraction, same SwiftUI list: TUI has 4,338 of 6,767 SwiftUI symbols (64%), SwiftTUI 1,112 (16%) [M]. Against TUI, Todo typechecks with 0 errors and Browser with 2 [M]. SwiftTUI lacks 8 or more APIs that each of Todo, SortedTable and Browser uses, so all three would fail there; that is judged from its API list, not compiled [M, I, §4]. |
| 2 | Does it have the controls my app needs? | **TUI** for app chrome and forms. **SwiftTUI** for dashboards and embedded terminals. | SwiftTUI has no `contextMenu`, `searchable`, `Form`, `DatePicker`, `ColorPicker`, `Gauge`, `Grid`, `NavigationSplitView`, `NavigationLink`, `@AppStorage`, in-app drag and drop, or text-editor undo (§6). TUI has no charts, embedded terminal, command palette or `Canvas`. |
| 3 | Where can it run? | **SwiftTUI, clearly** | Windows terminal is shipped and tested in CI. It also has native macOS and iOS embedding, an Android preview, and a static browser bundle with no terminal emulator [V]. TUI runs on macOS, Linux and browser WASM through xterm.js; Windows is partial [V]. |
| 4 | Can I depend on it responsibly? | **SwiftTUI** | 35 GitHub releases, with `.upToNextMinor` pinning, 200 stars, Discord, external contributors, 64 PRs. TUI has no version tags, documents `branch: "main"`, has 2 stars, and 28 of its last 33 public CI runs on `main` failed [M]. |
| 5 | What toolchain must I have? | **TUI** | TUI needs Swift 6.2+ and macOS 14+. SwiftTUI needs Swift 6.4 and macOS 15+, because `swift-tools-version: 6.4` [V]. On a Mac, that means Xcode 27 or swiftly. |
| 6 | Will it look right in my terminal? | **TUI** on correctness; **SwiftTUI** on breadth | TUI has an 8,336-line measured survey, per-terminal advance compensation and identity probing. SwiftTUI's width is, in its own comment, intentionally approximate, and I found no per-terminal advance handling. SwiftTUI adds Sixel, SGR-pixel mouse and Windows consoles [V]. |
| 7 | Is it accessible? | **SwiftTUI, clearly** | Semantic tree, `--reader` mode, `accessibility*` modifiers, ARIA in browsers, cursor-follows-focus [V]. TUI's docs say "None" for VoiceOver and traits, and it has only preference reading (§7). |
| 8 | How is the developer experience? | **SwiftTUI** on tooling; **TUI** on compile-as-is | SwiftTUI has compiled hot reload, `RenderOnce`, a documented test product, `_printChanges`, named runtime issues, a debug bundle and a profiling product [V]. TUI's test product is still in progress; it has none of the others. |
| 9 | Which has the deeper app features? | **TUI** | File panels and documents, menu bar and `Commands`, materials, 7-language localisation, SF Symbols, 17 palettes, drag and drop with sessions, undo [V]. |
| 10 | How fast is it? | **Unknown** | SwiftTUI has the more ambitious engine: retained graph, off-main tail, frame dropping. TUI walks the tree on the main thread with memos. No head-to-head exists. Its author himself warns that mirroring SwiftUI's internals may cost performance, binary size and stability [S]. |

### TUI: pros
- Far larger SwiftUI vocabulary, and real SwiftUI programs mostly compile [M].
- Runs on older toolchains, which gives SwiftUI programmers a low entry cost [V].
- Terminal behaviour measured on real terminals and kept in a version-stamped record [V].
- App-level features SwiftTUI lacks entirely: menus, file panels, search, documents, drag and drop, localisation, materials [V].
- À-la-carte modules: 32 library products [S: SPI, `CHANGELOG.md`]. SwiftTUI lists 14 products, one of them an executable, and SPI counts 13 libraries [V, S].

### TUI: cons
- No releases or version tags, so no stable dependency story [M].
- Public CI is mostly red, and the README shows a CI badge [M].
- Almost no visible adoption: 2 stars, no external contributors, 0 PRs [M].
- No accessibility beyond reading preferences; no hot reload; no Windows; no native hosts [V].
- Single main author, as with SwiftTUI [M].

### SwiftTUI: pros
- Five host presentations from one app [V]. A release process, a community channel, real showcase apps [V, S].
- Dev tooling (hot reload, test support, diagnostics) [V].
- Accessibility taken seriously and documented honestly, including what is not qualified [V, S].
- An unusually candid public divergence register [V].
- Open style protocols across 28 families, against 21 in TUI [M].
- CI on macOS, Linux and Windows, mostly green [M].

### SwiftTUI: cons
- SwiftUI code generally needs rewriting, not porting, in many common cases. It deliberately omits or reshapes `NavigationLink`, `\.dismiss`, `keyboardShortcut`, `Font`, `Text` literals as keys, `Table` builders and `onHover` [V].
- Needs the newest toolchain [V].
- No localisation at all, and the register's `Text` stance rules out reinterpreting literals later [S: REG:84-90].
- Coarser terminal-quirk handling [V].
- Interactive launches start a loopback web server by default; the default product links it [S].
- Some known gaps: `withAnimation` does not animate `@Observable` writes, animations snap inside lazy rows, no `ScenePhase` [S: REG:119,978,985].

### What they do equivalently
Both of these are verified in source:
- MIT, SwiftPM source packages, compiled with the app, one main author, strict Swift 6, `@MainActor` `View`.
- `@State`, `@Binding`, `@Bindable`, `@Environment`, `@FocusState`, `@Observable`.
- Stacks, `Layout`, `AnyLayout`, `GeometryReader`, `ViewThatFits`, lazy stacks, preferences.
- `List`, `Table`, `OutlineGroup`, `ScrollView`, `TabView`, `NavigationStack`, sheets, alerts, popovers.
- Tap, drag, long-press gestures and their compositions.
- `withAnimation`, springs, keyframes, phases, matched geometry, transitions.
- Shapes, gradients including mesh, blend modes, Kitty graphics, Kitty keyboard, OSC 8, OSC 52, synchronised output, truecolor with fallback.
- Browser builds through WASI.
- No Xcode previews, and no hosted services or AI integration in either (§12).

---

## 3. Identity and maturity

| | TUI | SwiftTUI |
|---|---|---|
| Age | First commit 2026-01-28 as TUIkit; repo created 2026-05-04 [M] | Org 2026-05-15, repo 2026-06-07, first release 0.9.0 on 2026-08-16 [M] |
| Commits | 8,149 local `main` [M] | 4,208 [M: API] |
| Commits since 2026-10-24 | 687 [M: API] | 123 [M: API] |
| Contributors | wadetregaskis 7,092; phranck 761; Actions bot 236 [M] | adam-zethraeus 4,144; detail-app bot 45; echoz 13; vmarcella 5; subpop 1 [M] |
| Stars / forks | 2 / 0 [M] | 200 / 10 [M] |
| Releases | None; only a `media` release for clips [M] | 35 GitHub releases, about 121 tags [M, S: SPI]. 0.20.0 on 2026-10-30 |
| Issues / PRs | 16 / 0 [M] | 6 (0 open) / 64 [M] |
| Licence | MIT [V] | MIT, vendored code keeps its own [V] |
| Swift | 6.2, 6.3, 6.4; tools 6.2 [V: `Package.swift:1`, `ci.yml:34-39`] | Tools 6.4; pinned 6.4.0 [V: `ST:Package.swift:1`, `.swift-version`]. SwiftPM cannot read a 6.4 manifest with an older toolchain [I] |
| Platforms | macOS 14+, Linux, WASM; Windows partial: lower modules only [V: `CONTRIBUTING.md:162`, `README.md`] | macOS 15+, iOS 18 (host), Linux, Windows 10 1809+, WASI, Android arm64 preview [V: `Package.swift`, `Hosts-And-Platforms.md`] |
| Dependencies | swift-syntax (macros), docc plugin, benchmark (opt-in) [V: `Package.swift:181,196,1171`] | swift-collections, async-algorithms, argument-parser, docc plugin [V: `ST:Package.swift:54-70`], plus vendored figlet, gif, jpeg, png, UnixSignals [V] |
| Distribution | SwiftPM, `branch: "main"` [V: `GettingStarted.md`] | SwiftPM tags, npm for web, Maven AAR for Android [S] |
| Source lines | 451,856, including Example 34,050 and Stress 17,080 [M] | 254,175 in `Sources` and `Platforms`; vendor 10,085 [M]. Charts, terminal view, SwiftUI host and Android live in other repos, uncounted |
| Test lines | 373,218 [M] | 354,232 [M] |
| `@Test` occurrences | 14,059 [M: grep, parameterised not expanded] | 9,308, plus 16 XCTest-style [M: grep] |
| CI | One `ci.yml` plus Pages; 28 failures, 4 passes, 1 cancelled in the last 33 CI runs on `main`; latest failed [M: API]. Cause not investigated | 6 named workflows; in the last 40 runs on `main`, 35 succeeded, 4 cancelled, 1 failed; latest of each workflow succeeded [M: API]. 2,500 runs in total against TUI's 92 |
| Windows CI | Ratchet: the set that builds must keep building [V: `ci.yml:20-23`] | Builds, and runs test lanes, nightly on `windows-11-arm` and `windows-2022` [V: `windows-build.yml:83-129`, `docs/HOSTS-AND-PLATFORMS.md`] |
| Package index | Listed; score 65; "no releases" [S: SPI] | Listed; 121 releases [S: SPI] |

**Process observations**
- Their coordination repo `swift-tui-org` is cited by docs but returns 404 publicly, so some of their process is private [M]. It may be a private repo.
- Both projects are evidently developed with heavy AI assistance: `ST:AGENTS.md` and a `CLAUDE.md` symlink, and TUI's `.claude/CLAUDE.md` [V]. So commit counts say little about either side's human effort.

---

## 4. SwiftUI API compatibility

### Method
TUI's `Tools/APIParity/api_parity.py` was used for the SwiftUI side and the TUI side, unchanged, through its `load_symbols`.

- It needs a built module for the target, so SwiftTUI could not be extracted directly.
- Instead I used SwiftTUI's own checked-in symbol-graph list, `ST:docs/.public-api-baseline.txt`, 5,751 lines, generated by `swift package dump-symbol-graph` on 2026-10-24 [V]. Keys have the same `Owner.name(labels:)` form after removing the module.
- Scripts: `competitive/scripts/parity3.py`, `parity4.py`, `matrix.py`.
- Toolchain: Xcode's Swift 6.2.4, macOS 26 SDK target, the same as your run this morning (6,767 SwiftUI symbols).
- TUI's modules were existing debug modules stamped 12:15 today, about 6.5 hours behind `main` [M].

### Result [M]

| Measure | SwiftUI | TUI | SwiftTUI |
|---|---:|---:|---:|
| Live public symbols, unique keys | 6,767 | 8,171 (11,915 following aliases) | 5,546 |
| SwiftUI keys present, exact | | **4,338 (64.1%)**; 4,352 with aliases, matching your tool | **1,112 (16.4%)** |
| Upper bound with label-subsequence credit, defaults unchecked | | 4,357 | 1,182 |
| Same base name, ignoring labels (of 5,937) | | 3,703 | 1,078 |
| Top-level types (of 752) | | 585 (78%) | 234 (31%) |
| `View.*` members, exact (of 563) | | 393 (70%) | 117 (21%) |
| `View.*` base names (of 419) | | 295 | 113 |
| Symbols the other lacks | | 3,273 only in TUI | 47 only in SwiftTUI |

- **The 47 are nearly all accessibility**: `AccessibilityTraits`, `AccessibilityFocusState`, `accessibilityLabel` and so on, plus `Canvas`, `ProposedViewSize`, `fixedSize()` and `focusSection()` by exact spelling.
- **How to read this fairly**
  - It is vocabulary, not behaviour. A symbol existing says nothing about how well it works.
  - Your tool classifies 2,359 further SwiftUI symbols as deliberately absent from TUI; the same symbols are absent from SwiftTUI for the same reasons. Excluding them, SwiftTUI covers about a quarter of what is applicable [I].
  - SwiftTUI's absences are mostly deliberate: implementing only a subset is its stated policy [S: REG:8-11, `Coming-From-SwiftUI.md:222-231`]. This is a scope difference, not a defect count.
  - The baseline is 7 days old; 0.20.0's changelog has Changed, Fixed, and Tests and documentation sections, with no Added section [V: `ST:CHANGELOG.md:11`].

### Can real SwiftUI code compile?

TUI was typechecked with `competitive/scripts/tc2.sh`, importing TUI in place of SwiftUI [M]. SwiftTUI was judged by reading and by checking each API used against its baseline with `competitive/scripts/progcheck.py`; the same script's answers for TUI matched the compiler on Todo and Browser, which calibrates it [M].

| Program | TUI errors [M] | Absent from SwiftTUI, and why it would not compile as written [M, V] |
|---|---:|---|
| **Todo** | **0** | `ContentUnavailableView`, `ToolbarItem`, `contextMenu`, `keyboardShortcut`, `onDelete`, `onMove`, `swipeActions`. Also `ForEach($items) { $item in }`, which they document as not compiling (REG:261-266). `Button(_:systemImage:action:)`, `Image(systemName:)` and `Text(_:style:)` have no such inits (`ST:docs/.public-api-baseline.txt:3638-3639,4074-4076,5216-5218`). `.font` is absent. `@Observable` without `@MainActor` fails the `Sendable` bound on `.environment` (REG:148-154). |
| **SortedTable** | **1** (a solver timeout at :53, not a missing API) | `Table` has no column builder or `sortOrder` (REG:476-481; the app sorts its own records, `V/Foundation/StylePrimitives.swift:24-26`). `Grid`, `GridRow`, `SceneStorage`, `TableColumnCustomization`, `ToolbarItemGroup`, `contextMenu`, `searchable`, `\.dismiss`, `keyboardShortcut`, `Text(_:format:)`, `fontWeight`. |
| **Browser** | **2** (`ShareLink`; `List(data, selection:)` with a non-ID selection) | `NavigationSplitView`, `NavigationLink`, `NavigationPath`, `AsyncImage`, `LazyVGrid`, `GridItem`, `ShareLink`, `ContentUnavailableView`, `ToolbarItem`, `SidebarCommands`, `searchable` and friends, `refreshable`, `textSelection`, `navigationSubtitle`. |
| TabsAndSheets | 0 | `Form`, `ToolbarItem(Group)`, `keyboardShortcut`, `presentationDetents`, `interactiveDismissDisabled`, `shadow`. |
| SettingsForm | 2 | `AppStorage`, `ColorPicker`, `DatePicker`, `Form`, `Gauge`, `LocalizedStringKey`, `Settings`, `monospacedDigit`. |
| DocumentFlow | 4 | `DocumentGroup`, `FileDocument`, `CommandMenu`, `CommandGroup`, `Window`, `fileImporter`, `fileExporter`, `@Entry`, `keyboardShortcut`, `onOpenURL`. |
| CustomStyles | 21 | `@Entry`, `onHover`, `scaleEffect`, CoreGraphics types; custom styles are their strength, so this one would be closest. |
| AnimationGestures | 6 | `monospacedDigit`, `rotationEffect`, `scaleEffect`. Both frameworks reject `CGFloat` geometry. |

**Conclusion.** TUI's "write SwiftUI, get a terminal app" is substantially true at the compile level for the programs tested. SwiftTUI's own tagline is deliberately narrower (semantics and shape), and its docs tell SwiftUI developers what to retrain. Its site's opening sentence for SwiftUI developers, that if you write SwiftUI you already write SwiftTUI, is true of the concepts rather than of whole files [I].

### Faithfulness beyond the symbol list
- **SwiftTUI reshapes on purpose**: `onKeyPress(_:perform:)` with no phases (REG:626-635), `keyCommand` in place of `keyboardShortcut` (REG:600-604), `onPointerHover` in place of `onHover` (REG:720), `\.openLinkAction` in place of `\.openURL` (REG:636), required `Slider(in:)` (REG:539), `Text(_:)` always literal (REG:84).
- **Their stricter concurrency leaks into call sites**: `Binding(get:set:)` closures are `@MainActor` (REG:155), environment models must be `Sendable` (REG:148), `ForEach` IDs must be `Sendable` (REG:226).
- **SwiftTUI has something TUI lacks: an automated behavioural differential**. Six fixtures compile against both SwiftTUI and real SwiftUI in macOS CI [V: `ST:Tools/PublicSemanticOracle.swift`; S: `ST:docs/PUBLIC-SEMANTIC-FIXTURES.md`]. It is small. TUI's `Tools/SwiftUIProbes` records far more behaviours, but they are hand-run with results kept by hand [V].
- **TUI's compile corpus** (`Tools/APIParity/CompileCorpus.swift`) proves call sites; I found no SwiftTUI equivalent.
- **The registers**: theirs is 1,337 lines, one page, tagged Ratified, Provisional or Gap, and public on the site [V]. TUI's `Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md` is 2,501 lines and internal; `ComingFromSwiftUI.md` is the public digest [V].

---

## 5. Rendering model and architecture

| | TUI | SwiftTUI |
|---|---|---|
| Model | Each frame is a synchronous pass that walks the tree and writes a frame buffer [V: `RenderCycle.md:7`, `:37-42`] | Retained `ViewGraph` with dependency tracking; a compiler-style pipeline of immutable products: resolve, measure, place, semantics, draw, raster, commit [V: `ST:Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc/Runtime-Render-Pipeline.md:12-19`, `Sources/SwiftTUIGraph/Resolve/`] |
| What re-evaluates | Whole walk, cut by memos and caches. Your notes say List and Table memos serve 0% when an ancestor write moves data [S: memory `memos-die-on-an-ancestor-write`] | Dirty frontier after the boot frame, plus retained reuse and memo gates with read certificates; not promised to hit [S: `Hosts-And-Platforms.md`, REG:1229-1237] |
| Threading | Rendering on the main thread [V: `RenderCycle.md:33`] | Body evaluation on main actor; measure to raster on a worker queue where permitted [V: `Sources/SwiftTUIRuntime/Rendering/FrameTailLayoutWorker.swift:80`, `docs/ARCHITECTURE.md:733-745`] |
| Under load | Coalesces via flags; animation replay without re-render [V: `RenderCycle.md:18-32`] | Frame cancellation, completed-frame drop policy, offscreen elision [S: pipeline doc; names V in `RunLoop+FrameDropBlockerDerivation.swift`] |
| Layout | Two-pass proposal: measure then render [V: `Architecture.md`] | Proposal: measure, place on heap work stacks, iterative, with a guard script [S: REG:1209-1222; V: `Scripts/check_layout_work_stack_guardrails.sh`] |
| Deep nesting | Recursion on the 8 MB main stack, with `StackGuard` truncation [S: memory `deep-nesting-stack-and-requadratic`] | Iterative built-ins; re-entry bounded at custom `Layout` and collections. Windows needs a linker stack flag or degrades to a lean profile [S: REG:1209-1222, `Distributing-Your-App.md:95-103`] |
| Output diff | `FrameDiffWriter`, per line and intra-line, with advance compensation [V: `Sources/TUIApp/Rendering/FrameDiffWriter.swift:40,593`] | Per-row cell span diff [V: `Sources/SwiftTUIRuntime/Terminal/TerminalSurfaceDamageRendering.swift:74`] plus scroll-region translation [V: `TerminalHostEscapeSequences.swift:145-184`, `TerminalCapabilityProfile.swift:23-31`]. TUI only resets the region at exit (`Terminal.swift:866`) |
| State | `StateStorage` keyed by identity path [V: `RenderCycle.md:74`, project rules] | Graph-scoped slots, bound at capture; loud diagnostic on stale reads [S: REG:202-213] |
| Observation | `withObservationTracking` around body evaluation [V: `Sources/TUIView/Rendering/ChildInfo.swift:959`, `FrameObservation.swift:59`] | Same mechanism, recording per-identity certificates [V: `V/Environment/Observation.swift:141`] |
| `withAnimation` on `@Observable` | Animates; has a dedicated test [V: `Tests/TUIIntegrationTests/ObservedChangeTransactionTests.swift`] | **Does not animate**: a recorded gap [S: REG:985-990] |
| Concurrency strictness | Swift 6, `@MainActor` `View` [V: `Sources/TUIView/Core/View.swift:58`] | Swift 6, plus strict memory safety and a ban on `@unchecked Sendable` and `nonisolated(unsafe)` [V: `ST:Package.swift:99-100`, `ARCHITECTURE.md:733-745`] |
| Singletons | Rule against, with listed exemptions [V: project rules] | Not assessed |
| Invariant checking | Memo verifier, storm suites [S: memory] | Soundness oracles, debug byte-equivalence, release soundness lane in CI [V: `docs/SOUNDNESS-ORACLES.md`, `release-soundness.yml`] |

**Analysis**
- SwiftTUI's design is the more ambitious and, in principle, should scale better for small updates to big trees and keep input responsive under heavy frames.
- It pays for that in API constraints (`Sendable` bounds), code size per feature, and engine complexity.
- TUI's model is simpler and has been heavily profiled and optimised.
- Which is faster for real apps is unknown (§10). Do not assume; their own changelog records heavy frames at 131 ms for an effect-heavy case [S: `ST:CHANGELOG.md:749`].

---

## 6. Views and controls: feature matrix

"absent" means no public declaration of that name in a scan of `Sources` and `Platforms` (`competitive/scripts/locate.py`) and not in the baseline [M]. Location is the first declaration found, in `Sources/` for TUI and `V/` for SwiftTUI unless noted.

### Collections and layout

| Feature | TUI | SwiftTUI |
|---|---|---|
| `List` | `TUILists/Views/List.swift:112` | `Collections/List.swift:7`. Needs explicit `.tag` to select (REG:486); adds `onActivate` |
| `List` selection from data elements | Requires `Element.ID`; this is the Browser error | Not checked |
| `onDelete`, `onMove` | `TUIFoundation/Views/DynamicViewContent.swift:137,167` | absent |
| `swipeActions` | `TUIFoundation/Modifiers/SwipeActionsModifier.swift:54` | absent |
| `Table` | `TUITables/Views/Table.swift:153`, column builder, `sortOrder` | `Collections/Table.swift:32`, value `[TableColumn]` and positional cells; sort is a display value only (REG:476; `Foundation/StylePrimitives.swift:24-26`) |
| Windowing of large data | Yes; 1,000,000-row Stress scenario [S: `Sources/Stress/README.md`] | Yes; csvui on 34,000 rows [S]; viewport-bounded at every size [S: `CHANGELOG.md:2353`] |
| `OutlineGroup`, `DisclosureGroup` | `OutlineGroup.swift:121`, `DisclosureGroup.swift:69` | `Collections/OutlineViews.swift:26`, `Controls/ValueControls.swift:256` |
| `Grid`, `LazyVGrid`, `LazyHGrid` | `TUIGrid/Views/Grid.swift:200`, `LazyGrids.swift:250` | absent |
| Lazy stacks, `ScrollView`, reader | `TUIFoundation/Views/LazyStacks.swift:108`, `ScrollView.swift:76` | `Stacks/LazyVStack.swift:4`, `ScrollView/ScrollView.swift:4`. Nested wheel hand-off documented |
| Custom `Layout` | `TUIFoundation/Views/Layout.swift:81` | `Layout/CustomLayout.swift:265` |
| Split views | `HSplitView`, `TUINavigation/Views/SplitView.swift:42` | absent |

### Navigation and presentation

| Feature | TUI | SwiftTUI |
|---|---|---|
| `NavigationStack` | `TUINavigation/Views/NavigationStack.swift:74` | `NavigationViews/NavigationStack.swift:8`; homogeneous `Binding<[Route]>` only |
| `NavigationSplitView` | `TUINavigation/Views/NavigationSplitView.swift:147` | absent, stated out of scope (REG:75) |
| `NavigationLink`, `NavigationPath` | `NavigationLink.swift:69`, `NavigationPath.swift:40` | absent on purpose (REG:59,73) |
| `TabView` | `TUITabs/Views/TabView.swift:46` | `TabViews/TabView.swift:5`; dormant-tab state archive documented |
| `sheet`, `alert`, `confirmationDialog`, `popover`, `fullScreenCover` | `TUIPresentation/Extensions/` | `Presentation/`; FIFO prompt queue; `\.dismiss` absent (REG:65) |
| `toast`, `popoverTip` | Notification service, not `toast` | `Presentation/ToastPresentation.swift:550`, `PopoverTip.swift:23` |
| `inspector` | `TUINavigation/Views/Inspector.swift:51` | absent |
| `toolbar` | `ToolbarItem` builder | `toolbarItem(_:)` with value config (REG:642) |
| Menu bar, `Commands`, `CommandMenu` | `TUICommands/Commands/Commands.swift:44`, `MenuBar/` | absent |
| `Menu` | `TUIMenus/Views/Menu.swift:80` | `Controls/Menu.swift:27` |
| `contextMenu` | `TUILists/Modifiers/View+SelectionContextMenu.swift:87`, `TUIFoundation/Modifiers/ContextMenuModifier.swift` | absent; listed as a bare absence (`Coming-From-SwiftUI.md:224`) |
| Command palette | absent | `paletteCommand`, `ActionScopes/PaletteCommandModifier.swift:49`; `PaletteStyle` |
| Status bar | `TUIChrome/StatusBar/StatusBar.swift:47` | absent as such; `Panel` and bottom toolbar styles |
| `Dialog`, `Card`, `Panel` | `TUIPresentation/Views/Dialog.swift:58`, `TUIForms/Views/Card.swift:73`, `Panel.swift:74` | `ActionScopes/Panel.swift:28` |
| `Window`, `Settings`, multiple scenes | `TUIApp/App/Window.swift:38`, `TUIScenes/Settings.swift:38` | one active root scene (REG:115); attach secondary scenes from another terminal or the browser [V: `Platforms/CLI/.../RunnerCLI.swift:71`] |

### Controls and text

| Feature | TUI | SwiftTUI |
|---|---|---|
| `Button`, `Toggle`, `Stepper`, `Slider`, `Picker`, `Link` | All | All |
| `Slider` default range | SwiftUI-shaped | `in:` required (REG:539) |
| `Form`, `FormStyle` | `TUIForms/Views/Form.swift:57` | absent |
| `GroupBox`, `LabeledContent`, `Label` | Yes | Yes |
| `DatePicker` | `TUIPickers/Views/DatePicker.swift:56` | absent |
| `ColorPicker` | `TUIColorPicker/Views/ColorPicker.swift:54` | absent |
| `Gauge` | `TUINumericControls/Views/Gauge.swift:56` | absent; `Meter` in charts package [S] |
| `ProgressView`, `Spinner` | Yes | Yes |
| `TextField`, `SecureField`, `TextEditor` | `TUITextInput/Views/` | `Controls/ValueControls.swift:111`, `Input/SecureField.swift:4`, `Input/TextEditor.swift:5` |
| Text undo | `TUITextInput/Focus/TextUndoHistory.swift` | none found in `V/` or Core [M: grep]; GIF editor has app-level undo |
| Mouse text selection and drag in fields | Yes [V: `SelectingText.md`, `DragAndDrop.md`] | Selection exists in editor state; copy on Ctrl+C [S: `Hosts-And-Platforms.md:59`]; drag not found |
| `textSelection` on read-only text | `TUIFoundation/Views/TextSelectability.swift:92` | absent |
| `searchable`, tokens, scopes | `TUISearch/` | absent (REG:613) |
| `Font`, `.font(.title)` | `TUIFoundation/Styling/Font.swift:50` | absent on purpose (REG:91); emphasis lives on `Text` |
| Localisation | `LocalizedStringKey.swift:61`; `TUIStrings`; 7 languages | absent; no `Locale`, no bundle lookup (REG:84-90) |
| RTL layout | Not yet [V: `ComingFromSwiftUI.md`] | absent (REG:89-90) |
| `@AppStorage`, `@SceneStorage` | `TUIFoundation/State/AppStorage.swift:376`, `SceneStorage.swift:51` | absent |
| `ScenePhase` | `ScenePhaseEnvironment.swift:62`, via focus reports | absent (REG:119) |
| Documents and file panels | `FileDocument.swift:49`, `fileImporter`, `fileExporter`, `fileMover` | absent |
| `DocumentGroup` | absent | absent |
| `ContentUnavailableView` | `TUIFoundation/Views/ContentUnavailableView.swift:40` | absent |
| Charts | absent | Separate `swift-tui-charts`: 13 primitives, not Swift Charts' grammar [S] |
| Embedded terminal programs | absent | Separate `swift-tui-terminal-view`, SwiftTerm-based, macOS and Linux [S]; gaps REG:1196-1202 |
| FIGlet banners | absent | `Primitives/TextFigure.swift:5` |
| Animated GIF | Not found as a named view | `SwiftTUIAnimatedImage/AnimatedImage.swift:2` |
| Open style protocols | 21, excluding `ShapeStyle` [M] | 28, excluding `ShapeStyle` [M]; includes `Slider`, `Stepper`, `Sheet`, `Popover`, `Prompt`, `Toast`, `ScrollView`, `Spinner` |

**Reading this.** TUI wins on breadth by a large margin for app-style programs. SwiftTUI's unique items are valuable for dashboards, developer tools and multiplexers. Its style system is genuinely more open.

---

## 7. Input, focus and accessibility

| | TUI | SwiftTUI |
|---|---|---|
| Kitty keyboard | Yes, flag set chosen, press and release [V: `Sources/TUIApp/Rendering/Terminal+KeyboardProtocol.swift:59`, `TerminalSupport.md`] | Yes, flag 1 only, disambiguation; off inside multiplexers [V: `TerminalHostEscapeSequences.swift:34`, `TerminalHostCapabilities.swift:122-137`] |
| Key APIs | `keyboardShortcut`, `onKeyPress(phases:)`, `onModifierKeysChanged` [V] | `keyCommand`, `onKeyPress(perform:)`; modifier-less bindings reserved [V: REG:600-635] |
| Mouse | SGR, motion, hover [V: `Terminal.swift:740,1166`] | SGR, motion, **SGR-pixels** (`?1016`) after a DECRQM probe, with cited evidence per terminal [V: `TerminalHostEscapeSequences.swift:89-107`, `PointerPrecisionPolicy.swift:170-200`]. TUI has none of `?1016` [M: grep] |
| Gestures | Tap, drag, long press, composition | Same, plus typed composition; cell-denominated defaults (REG:691); no magnify or rotate on either |
| Hover | `onHover`, `onContinuousHover` | `onPointerHover` (renamed) |
| Scroll wheel | Built into scroll views | Also public `onScrollWheel` with routing result [V: `Gestures/ScrollWheel.swift:32`] |
| In-app drag and drop | Yes: `draggable`, `dropDestination`, `DropDelegate`, sessions, keyboard route [V: `TUIFoundation/Modifiers/DragAndDrop.swift:628,663`, `DragAndDrop.md`] | **No.** File drop only, on `ActionScope`, from pasted paths [V: `ActionScopes/DropDestinationModifier.swift:4-17`] |
| Focus | Sections, `FocusState`, default focus | Geometry-aware traversal that wraps (REG:589), `FocusContainment`, `focusScope` |
| Focus reports, colour-scheme reports | `?1004`, `?2031` [V: `Terminal.swift:694,710`] | Neither sequence found [M: grep]; appearance queried by OSC 10 and 11 [V: `TerminalAppearanceDetection.swift`] |
| Clipboard | OSC 52, tmux passthrough, MIME paste `?5522` [V: `ClipboardWriter.swift:199-203`, `TerminalMIMEPaste.swift:172`] | OSC 52, `clipboardWriteAction` [V: `TerminalClipboard.swift:132`] |
| Accessibility API | **None.** `ComingFromSwiftUI.md:183` says so. The parity map justifies it: a terminal has no assistive stack (`Tools/APIParity/parity-map.json:21-27`) | `accessibilityLabel`, `Hint`, `Value`, `Hidden`, `Element`, traits, actions, `AccessibilityFocusState`, `AccessibilityAnnouncer` [V: `V/Modifiers/ViewMetadataModifiers.swift:63`, baseline] |
| Assistive runtime | Reads reduce-motion and similar preferences [V: `TUITerminalHost/Environment/TerminalClient+Accessibility.swift`] | **`--reader`**, a sequential semantic text mode with `read`, `next`, `activate`, `set`, `find`, F12 to toggle; `--accessible`, `--cursor-follows-focus`; browser ARIA, AppKit, UIKit and Compose overlays [S: `Terminal-Reader.md`; flags V: `SwiftTUIOptions.swift:35-65`] |
| Honest limits | | Assistive qualification incomplete; no WCAG suite; Android one-way [S: REG:1143-1176] |

**Analysis.** TUI's parity-map rationale needs revisiting. A terminal does have screen-reader users, and SwiftTUI shows one way of serving them. I have not tested whether their reader works with a real screen reader, and their own register says qualification is incomplete. TUI remains clearly ahead on rich keyboard and drag input.

---

## 8. Graphics and styling

| | TUI | SwiftTUI |
|---|---|---|
| Colour depth | Truecolor, 256, degraded nearest [V: `TerminalSupport.md`] | none, 16, 256, truecolor [V: `TerminalCapabilityProfile.swift:11-16`] |
| Themes | 17 palettes, `Palette` protocol [S: `PaletteReference.md:7`; V: `TUIStyling/Theme/Theme.swift:38`] | `Theme`, Codable, semantic roles, light, dark, high contrast; no bundled set found [V: `SwiftTUIPrimitives/Styling/Theme.swift:3`; S: `Styling-And-Theming.md`] |
| Materials | `Material` with terminal-pixel frost [V: `TUIFoundation/Styling/Material.swift:54`] | absent |
| Colour science | Encoded sRGB blending, opacity pipeline [S: memory] | OKLab, OKLCH, Lab, LCH, deltaE, gamut mapping public on `Color` [V: baseline lines 1338-1380] |
| Pictures: Kitty | Yes [V: `TUICore/Extensions/KittyGraphics.swift`] | Yes [V: `TerminalImageKittyRendering.swift`] |
| Pictures: **Sixel** | No [M: grep; one comment mention] | Yes [V: `TerminalImageSixelRendering.swift`] |
| Picture fallback | Rich: glyph sets, shape matching, dithering, curves [S: README; V: `TUIImage/ASCIIPalette.swift`] | ASCII, half-block at 16, 256, truecolor [V: `TerminalImageFallbackRendering.swift`] |
| Formats | stb_image via `CSTBImage` (many formats) [V: `Sources/CSTBImage`] | Vendored PNG, JPEG, GIF [V: `ST:Vendor/`] |
| SF Symbols | Table and `Image(systemName:)` [V: `TUIStrings/SFSymbols/`] | absent; `Image` takes data, path or URL string only [V: baseline 4074-4076] |
| `AsyncImage` | `TUIBitmaps/Views/AsyncImage.swift:223` | absent |
| Animation API | `withAnimation`, springs, keyframes, phases, matched geometry, transitions, content transitions | Same list; adds roll-numeric text; `Duration` units (REG:849) |
| Animation pacing | 60 Hz multiples [S: memory] | Sampled against a frame clock; 33 ms named budget [S: changelog] |
| Reduced motion | `accessibilityReduceMotion` [V] | Same, plus flag and `CI=true` static forms [S] |
| Shapes, gradients | Yes, including `UnevenRoundedRectangle`, `EllipticalGradient`, `ContainerRelativeShape` [M] | Yes, cell-centre clips; path morph [S]; no `offset` or `transform` on shapes [S: `Shapes.md:271-274`] |
| `Canvas` | absent; `GraphicsContext` only with `TextRenderer`; parity map says waiting (`parity-map.json:895-897`) | `V/Canvas.swift:46`, cell-space drawing, Braille and pixel grids |
| `TextRenderer`, `visualEffect`, `shadow`, `mask`, colour effects | Yes [V: `TUIFoundation/Modifiers/ShadowModifier.swift:155`, `MaskModifier.swift:43`] | absent; `blur`, `shadow`, `scaleEffect` named as absent (`Coming-From-SwiftUI.md:224-226`) |
| Blend modes | Per cell [V: `TUIEffects/Modifiers/VisualEffect.swift:253`] | Per cell, and composites images in linear sRGB [S: REG:1285-1306] |
| Borders | `.border`, styles, `controlStyle(.lines)` | Inset by default, `outset`, per side, gradients deprecated (REG:1120) |

---

## 9. Terminal compatibility

| | TUI | SwiftTUI |
|---|---|---|
| Knowledge base | `Documentation/Terminals/Terminal compatibility survey.md`, 8,336 lines, version-stamped, with probes in `Tools/TerminalProbes/` [V] | Comments and per-terminal evidence tables in code, some with source URLs [V: `PointerPrecisionPolicy.swift:170-200`]. No measured survey found |
| Identification | Env, DA1, DA2, XTVERSION; works over ssh [V: `TerminalIdentityQuery.swift:49`, `TUITerminalHost/Rendering/TerminalIdentity.swift`] | Env (`TERM`, `TERM_PROGRAM`, `COLORTERM`, `VTE_VERSION`, `WT_SESSION`), plus feature probes for Kitty graphics, Sixel, keyboard, DECRQM [V: `TerminalCapabilityProfile.swift:93-110,290-352`, `TerminalGraphicsCapabilities.swift:65-93`]. No XTVERSION or DA2 use found [M: grep] |
| Per-terminal rendering compensation | Yes: advance compensation, chrome glyph choice [V: `FrameDiffWriter.swift:593`; survey] | Not found: no `Apple_Terminal` string anywhere [M: grep]. Whether absolute positioning avoids the drift was not established |
| Unicode width | Character tables, width corpus, emoji measured per host [V: `Sources/TUIWidthCorpus`, survey] | Per-`Character` heuristic from Unicode properties, commented as intentionally approximate [V: `Sources/SwiftTUIPrimitives/Content/TextCellWidth.swift:1-50`] |
| tmux | Measured section; mouse, images, clipboard documented; passthrough for OSC 52 [V: `TerminalSupport.md:79-87`, survey `:2203`, `ClipboardWriter.swift:201`] | Detects `TMUX` or `TERM` prefix; disables Kitty keyboard and SGR pixels [V: `TerminalMouseCoordinateResolution.swift:85-94,104`]. No Kitty-under-tmux passthrough found |
| Terminals named | Ghostty, iTerm2, Warp, Apple Terminal, GNOME, tmux, xterm.js [V: `TerminalSupport.md:14-22`] | WezTerm, kitty, Ghostty, Alacritty, foot, Konsole, mintty, iTerm2, Windows Terminal, VS Code, VTE [V] |
| Windows console | Not supported [V: `CONTRIBUTING.md:162`] | Supported; own controller; stack caveat [V: `WindowsTerminalController.swift`; S: docs] |
| `TERM=dumb`, non-TTY | Hang was reported by the newcomer survey today; quit work in progress, so recheck | Stable output when not a TTY, `RenderOnce`, documented diagnostic [S: `Coming-From-SwiftUI.md`, `Browser-Companion.md`] |
| Plain options | `NO_COLOR` read [V: `TUIStyling/Color/ColorDepth.swift`]; no standard flags | `--no-color`, `--force-color`, `--ascii`, `--reduce-motion`, `--stable-output` in every app [V: `SwiftTUIOptions.swift`] |
| Self-test | `swift run TerminalClientQuirks`, `Example` [V] | Not found as a dedicated tool |

**Analysis.** TUI's record is much the deepest thing either project has here, and I would expect fewer visible glitches in the specific terminals measured [I]. SwiftTUI covers more surfaces with less depth. I have no runtime evidence that its rendering is actually wrong anywhere.

---

## 10. Performance

| | TUI | SwiftTUI |
|---|---|---|
| Frame cost | Recorded by scenario in `Documentation/Performance/` [S] | **Unmeasured here.** Its own record: 10,000-row first frame about 360 ms after fix (`CHANGELOG.md:2355`); 50 screen-blended ripples at 180x60 at 131 ms per release frame (`:749`); WebKit steady 10.8 ms per frame (`:2572`) [S]. Not comparable to TUI figures |
| Idle CPU | Recorded 0.5% on a button page after fixes, 2026-08 [S: `Documentation/Performance/Full performance profile…:357-361`]. Not remeasured | **Unmeasured.** Designed to sleep on a read source on Darwin and Linux [V: `InputPollBackoff.swift:3-5`, `InputReader.swift:38`]; animations gated similarly [S] |
| Binary size | Stripped release `Stress` 11.27 MB (`Documentation/Future options.md:41`) [S]; hello world on `TUIApp` about 40% smaller than on `TUI` [S: `ChoosingProducts.md`]; debug `Example` 73 MB, `Stress` 63 MB [M: `ls`] | **Unmeasured.** Default `SwiftTUI` links the web host and a 260 KB browser bundle [M: `du`; S: `Distributing-Your-App.md`]. Figlet fonts in a 7.2 MB vendor dir are in the runtime's dependencies [M, V]; how much reaches a binary is unknown |
| Compile time | Clean release, `-j 4`, about 74 s for `Stress` (`Future options.md:43`) [S]; sample programs typecheck in seconds, with solver timeouts of 40 to 60 s on two [M] | **Unmeasured.** Source-only, states it as a known cost [S: REG:1313-1321]. Smaller source than TUI; no swift-syntax [M, V]. TUI's macros are opt-in [V] |
| Memory | Stress tracks it [S] | `TermUIPerf` has memory growth analysis [V: `MemoryGrowthAnalyzerTests.swift`] |
| Perf tooling | `Stress`, `TUIBenchmarks`, `Tools/Profiling`, profile records in commits [V] | `Tools/TermUIPerf`, 16,562 lines, about 37 scenarios [M]. Deterministic counter baselines, debug and release, checked in CI [V: `Baselines/bench-counters.json`, `termui-perf-tests.yml`]. `SwiftTUIProfiling` is a shipped product for app authors [V] |
| Author-facing perf docs | Performance docs are mostly internal | `Performance-For-App-Authors.md` [V] |

**The honest position:** no comparison of runtime speed can be made from this evidence. Their counter-based CI gates are worth noting: they avoid the timing-on-a-busy-box problem that your memory notes record [I].

---

## 11. Developer experience

| | TUI | SwiftTUI |
|---|---|---|
| Getting started | `GettingStarted.md`, 36 articles [M] | `Your first hour` sequence on the site, 69 DocC articles across catalogs [M]; live counter on the home page [S] |
| Coming from SwiftUI | `ComingFromSwiftUI.md`, 227 lines [M] | `Coming-From-SwiftUI.md`, plus the register, plus a site page [V] |
| Internal explanation | `RenderCycle.md`, `Architecture.md` | `/pipeline/` interactive walkthrough, `docs/ARCHITECTURE.md` 978 lines [V] |
| Quit on first run | **Newcomer survey found Ctrl-C did not quit; new quit behaviour is in progress** | Ctrl-C quits by default, and copies instead when text is selected [S: `Hosts-And-Platforms.md:53-59`] |
| First-contact failures | Newcomer survey findings in `survey/newcomer.md` are partly fixed: README `platforms:` is now there; `tuikit` scaffold mention gone [M: grep]. `renderOnce` behaviour not rechecked | Toolchain demand is the main hurdle [I] |
| Previews | None | None. `SwiftUIHost` could in principle embed a view in Xcode previews [I]; no doc found claiming this |
| **Hot reload** | None [M: grep] | **Yes.** `swifttui-dev` rebuilds and dlopens images, keeps Codable `@State`, focus, scroll offsets; macOS and Linux debug only; needs a small `@_cdecl` export [V: `Tools/SwiftTUIDev/`, `Sources/SwiftTUIRuntime/HotReload/`; S: `Compiled-Hot-Reload.md`] |
| Testing for app authors | `TUITesting` **in progress**, not on `main`. Internal `TUITestSupport` only | `RenderOnce`, `DefaultRenderer` snapshot, `SwiftTUITestSupport` PTY journeys, poll-free signals, style fixtures [V: `Testing-Your-App.md`, `ST:Package.swift:127`] |
| Debugging | `Tools/`; no `_printChanges` [M: grep] | `_printChanges`, `_logChanges`, `--debug` bundle, `SWIFTTUI_PROFILE`, frame diagnostics sink, runtime issues routed to a separate TTY [V: REG:45-55, `Logging-And-Diagnostics.md`] |
| Runtime misuse messages | Compile errors; `@available` stubs were recommended by the API survey; I found none for `foregroundColor` [M: grep] | Named deduplicated runtime issues, like `picker.unrepresentableOptionContent`, and traps with precise messages [V: REG:495-503, `ST:Sources/SwiftTUI/App.swift:82`] |
| Compile diagnostics | Solver timeouts on unsupported chains [M: 2 programs here] | Not measured |
| CLI | `App` is your type | `App` is an `AsyncParsableCommand`: standard flags, your flags, shell completions, `attach`, `--json`, `--web` [V: `Sources/SwiftTUI/App.swift`, `Platforms/Arguments/`, `RunnerCLI.swift`]. Con: reserved flag names, and `MyApp.main()` traps [V] |
| Examples | `Example` target, 135 files and 34,050 lines; `Stress`; `Tools/ScreenClips` [M] | 18 example directories, including real apps: GIF editor, csvui, mrkdwn, sextant, git-viz, terminal-workspace [M: `competitive/src/swift-tui-examples`] |
| Style | Plain prose, no marketing excess [I] | Same; candid on limits [I] |

---

## 12. What they offer that TUI lacks entirely

All verified as absent from TUI by grep [M], present in SwiftTUI as marked.

1. **Host portability** [V]
   - Native SwiftUI embedding on macOS and iOS (`swift-tui-swiftui`): a SwiftTUI scene inside an ordinary SwiftUI window.
   - Android Compose host (`Platforms/Android`, arm64 preview; runtime acceptance not closed, REG:1178).
   - Static browser bundle painting to Canvas or DOM, no terminal emulator, via npm `@swifttui/web`.
2. **Browser companion** [S, V]: an interactive app prints a loopback URL with a bearer token. Open it, and the same running app appears in a browser with accessible controls. `--web` runs browser-only. Default-on, with `--companion off`. Trade-off: every default app has a listening local socket.
3. **Windows terminal** [V, S]: shipped.
4. **Compiled hot reload** [V].
5. **Terminal reader** and the accessibility surface [V, S].
6. **Scene attach** [V]: `myapp attach <scene>` from another terminal, on a PTY (POSIX).
7. **`TerminalView`** [S]: a real shell inside a view; a `terminal-workspace` example is a small multiplexer.
8. **Charts** package [S].
9. **Command palette** [V].
10. **Standard app flags and shell completions** [V].
11. **`RenderOnce` as a real CLI story** [V]: render one frame to stdout for report-style tools. TUI's `renderOnce` exists, and the survey found it overwrites the screen (not rechecked).
12. **Community and release surface** [M]: Discord, RSS update feed, per-release stories, a `Projects using SwiftTUI` list (empty today), a public comparison page against Bubble Tea, Textual, Ratatui and Ink. That page does not mention TUI [V].
13. **Sixel**, **SGR-pixels**, **FIGlet**, **`Canvas`**, **GIF view**, **toast** [V].
14. **Mobile-minded adaptation guidance** [S: `Adapting-To-Hosts.md`].

**Things I looked for and did not find in either:** hosted or paid services, AI or LLM integration as a feature (`AGENTS.md` is for contributors), a project scaffold CLI, Xcode previews, `DocumentGroup`, `MenuBarExtra`.

---

## 13. Project positioning

- **SwiftTUI** presents itself as SwiftUI semantics drawn in terminal cells, terminal first, not terminal only, and aimed at iOS and macOS engineers who should not have to relearn UI [S: `ST:docs/VISION.md:5-9`]. It compares itself with Bubble Tea, Textual, Ratatui and Ink, so it pitches to anyone picking a TUI framework. It calls itself a beta; its author has said 1.0 is nearing while the project is still rough [S: forum, `ST:README.md`].
- **TUI** presents itself as the Swift terminal UI framework: write SwiftUI, get a terminal app, with a "learn once, write anywhere" goal and an emphasis on visual polish and terminal correctness [S: `README.md`]. It states it is close to 1.0.
- **The real difference** [I]: TUI's bet is that the SwiftUI vocabulary should simply work, for macOS and Linux apps that feel complete. SwiftTUI's bet is a faithful engine and a narrow, reshaped surface that travels to every host. A developer porting a SwiftUI app should choose TUI. A developer wanting one UI on terminal, browser, iOS and Windows, or wanting a dashboard with charts and embedded shells, should lean to SwiftTUI.

---

## 14. What TUI could learn

Ranked by value for effort. Sizes are rough: **S** days, **M** one to two weeks, **L** a month or more, **XL** architectural.

| # | Item | Size | Why |
|---|---|---|---|
| 1 | **Tag releases and make CI green on `main`** | S | Packages cannot responsibly depend on `branch: "main"`, and a red badge on the README is the first thing evaluators see. Cheapest gain in the list. Cause of the CI failures not investigated. `Tools/Release/release.sh` already exists. Your stated plan is 1.0 after compatibility work, but 0.x tags are independent of that. |
| 2 | **Announce it** | S | 2 stars against 200. The forum thread already discusses TUIkit, not TUI, and that post is where Swift developers look. The rename means the name recognition sits elsewhere. |
| 3 | **Land `TUITesting`, with a `RenderOnce`-grade story** | M, in progress | A public, deterministic way to assert frames. Their `Testing-Your-App.md` is a good model. |
| 4 | **Standard app flags and CLI conventions** | S to M | `--no-color`, `--ascii`, `--reduce-motion`, `--accessible`. Cheap, and helps accessibility and CI. Optional, without making `App` an ArgumentParser command. |
| 5 | **Accessibility, in stages** | M, then L | First cursor-follows-focus and the `accessibility*` modifiers storing metadata, then a reader mode. The parity map's reasoning (`parity-map.json:27`) deserves a re-read in light of `Terminal-Reader.md`. Needs a semantic pass over the tree, which is the expensive part. |
| 6 | **Command palette** | M | High user value, fits TUI's chrome, reuses `searchable` and menu work. |
| 7 | **Hot reload** | L | The biggest DX gap, and a differentiator among Swift TUI options. Their driver is only 729 lines, but the runtime side (state schema, `Codable` replay) is the work. |
| 8 | **Charts package** | M | Dashboards are a core TUI use case. Keep it a separate module. |
| 9 | **Maintained real apps as showcase** | M each | They show that it scales: csvui, a Markdown reader, a file browser. TUI's `Example` is a catalog, and clips are demos. |
| 10 | **A single public divergence register** | S | Publish a tagged Ratified, Provisional or Gap page. Readers trust it, and the content mostly exists. |
| 11 | **Named runtime issues and `_printChanges`** | M | Silent no-ops are the worst SwiftUI-porting experience. |
| 12 | **`@available` stubs for common omissions** | S | Recommended by your API survey; solver timeouts on `.scaleEffect` chains recur in this run. |
| 13 | **Sixel** | M | Wider real-pixel reach (foot, xterm, Windows Terminal). |
| 14 | **SGR-pixel mouse** | S to M | Sub-cell drag precision where supported; useful to your sliders and knobs. Their probe and fallback are a model. |
| 15 | **Automated behavioural differential against SwiftUI in CI** | M | Turns selected `Tools/SwiftUIProbes` into fixtures compiled against both frameworks. |
| 16 | **Counter-based performance gates** | M | Deterministic and runnable on a busy machine. |
| 17 | **Scroll-region output** | M | Large byte reductions on scrolling views, if the survey shows it is safe per terminal. |
| 18 | **`Canvas`** | M | Your parity map is waiting on it; a real SwiftUI program uses it, and SwiftTUI has it. |
| 19 | **Windows terminal** | L | Already on your path. It removes SwiftTUI's clearest platform claim. |
| 20 | **Native hosts** (SwiftUI, browser Canvas, loopback companion) | XL | TUI's pipeline emits ANSI strings, and hosts want a structured raster and semantic frame [I]. Decide whether you want this at all; not worth chasing merely to match. |
| 21 | **Off-main frame tail** | XL | Not recommended now. It has a real API cost in `Sendable` bounds, and there is no evidence it is needed. |

**What not to copy** [I]
- Their reshaped `onKeyPress`, `keyCommand`, `onPointerHover`, and missing `NavigationLink`, `\.dismiss` and `Font`: TUI's compile-as-is is its main advantage.
- A default-on local web server.
- A 6.4-only toolchain floor.
- Making every `App` an argument parser with reserved flags.

---

## 15. Where the comparison is uncertain

- **SwiftTUI's runtime quality is unobserved.** No app was built or run. Everything about how well its controls behave comes from reading and from its own docs.
- **All speed, memory, size and compile-time comparisons are open.** Figures quoted come from each project's own records, on different machines and scenarios, and are not comparable.
- **Symbol counts are a blunt instrument.** They measure names, not behaviour, and the TUI figure includes API with narrow terminal semantics. SwiftTUI's public list is 7 days old, and TUI's modules were 6.5 hours behind `main`. `@Test` counts are grep counts.
- **SwiftTUI's sibling repos were read at README level only**, so charts, terminal view, SwiftUI host and Android claims are mostly [S].
- **"Absent" means by the names I searched.** A feature under a different name could exist, as `onPointerHover` does. High-traffic absences are confirmed by their own doc (`Coming-From-SwiftUI.md:224-226`).
- **TUI's CI failures were not diagnosed.** They may be environmental or a single flaky lane. The count is from the GitHub API, filtered to `main`.
- **Forum content** came through a summarising fetch; its quotes and sequence are not verified line by line.
- **Stars and adoption** partly reflect TUI's very recent rename and repo move; `phranck/TUIkit` holds 73 stars.
- **The newcomer survey's first-run findings for TUI** were checked only where noted, and new quit behaviour is landing now.
- **I did not check** Android or iOS builds, the live site demo, Windows behaviour, screen-reader use, or whether either project's docs compile end to end for SwiftTUI.
