# Open owner decisions

Everything waiting on you, gathered in one place. It was compiled on 2026-10-18 from a full inventory of the docs, notes, memory and code (361 items), each entry checked against main. **Every entry was re-checked against main at 737febb32 on the evening of 2026-10-18,** after CHURN, FB16, W1 and O6 landed: 110 still stood as written, 17 were corrected below, and one (the Trash) had been done. **They were re-checked again against main at 01d6da6a9 on 2026-10-19,** after lanes O13, APPSTATE, PARITYMISC, INPUT, O4 and GLASS landed: 43 entries were corrected below, and none had been settled by the work that landed.

Answer by id and option (for example, "A-D6L-1: 4"); a bare "yes" takes the recommendation. Lanes still building add their questions to the last section as they land, and this document is re-checked before it is handed over as final.

- **73 decisions for you**, below by area, with a summary table first.
- **47 questions settled by your earlier rulings.** They're being built or kept as recommended, and are listed so you can veto any of them.
- **Lane questions** at the end.
- **Owner actions** first.

## Owner actions

- **PUSH: Push local main to GitHub (your action).** When will you push local main, now 1,984 commits ahead of origin/main (which is still d259fb308, 2026-10-01), so that CI runs on it? (b) today, then merge when it's green. It gets CI's Linux, Windows and macOS 27 results without publishing first.

- **STASH: A git stash from 2026-09-01 that no agent made.** Should the git stash from 2026-09-01 (stash@{0}, 'WIP on main: e4155942 RTL: the override is refused…') be kept or dropped? (b) if you're unsure; (a) if you know it's superseded.

- **Compiler bug reports:** yours to file, as you said on 10-18. Three are on the Desktop, one file per bug, written for 6.4.0 first: `swift-6.4-LoopUnroll-guaranteed-phi-dictionary-lookup.md`, `swift-6.4-PackMetadataMarkerInserter-merged-pack-values.md` and `swift-6.2-JumpThreadSimplifyCFG-Character-borrow-not-on-6.4.md`. The fourth, `swift-6.2.4-debug-type-roundtrip-boxed-CGFloat.md` (swift.org's 6.2.4 asserts on a boxed `CGFloat` in an optimised `-g` build; worked around in TUIkit), has left the Desktop, so I take it you have it.

## Your answers of 2026-10-23

This section records the answers you gave on 2026-10-23, what each one sets in motion, and the replies to the follow-up questions you asked.

| Id | Your answer | What happens now |
|---|---|---|
| [A-TS-1](#a-ts-1) | Keep the small test targets separate for now. | Done (lane DOCS2): the investigation is written up in the TS decisions file; the split stays. |
| [B-BNDL-1](#b-bndl-1) | (a) seems okay; asked why over the others. | Kept as shipped; the reasons are below. |
| [B-D6M-2](#b-d6m-2) | Check (c); take (c) if it works, else (a). | Trait experiment queued; (a) stands meanwhile. |
| [B-DYNVFIX-3](#b-dynvfix-3) | Asked for a (d) covering timers and detached tasks, and (b) against (c). | Answered below — your call. |
| [B-REVIEW](#b-review) | (a); remind you where they are and make sure they are up to date. | Partly done (lane DOCS2): the stale entries the follow-up names are corrected (six headings, B-DYNVFIX-3's price, the TimeSpan citation, the A/B lines with a recorded result); the other A/B-owed lines are not all checked. |
| [B-SIZEDOCS-1](#b-sizedocs-1) | (a). | Done (lane DOCS2): the probes are in Tools/SwiftUIProbes/ and their citations repointed. |
| [BINARY-DISTRIBUTION](#binary-distribution) | Distil the compiler bugs into Desktop reports; remind you of purpose, replace or augment, and toolchain support. | Two Desktop reports exist (`swift-6.4-library-evolution-crash-synthesized-modify.md`, `swift-6.4-cmo-everything-opaque-result-client-crash.md`); reminder below. |
| [DOCS-HOSTING](#docs-hosting) | Interested; explore a site like upstream's tuikit.dev; domain to be decided. | Plan below. |
| [DORMANT-DESIGNS](#dormant-designs) | Not deciding now. | Kept open; return after the SwiftUI API compatibility work. |
| [MACOS27-PARITY](#macos27-parity) | A to-do for when a macOS 27 machine is available. | Kept open until that machine is available. |
| [OOB-STYLING](#oob-styling) | Explore later along (a). | Kept open; reminder when the queue runs out. |
| [PACKAGE-RESOLVED](#package-resolved) | You committed it; asked for other considerations. | Committed (965a4884b); pros and cons below — your call. |
| [SDK15-CI](#sdk15-ci) | Asked about the newest SDK on 15.8 and an Xcode with the 6.2 standard library. | Answered below — your call. |
| [SINGLETON-CACHES](#singleton-caches) | (c). | Partly done (lane DOCS2): the rule is clarified and the palette store documented; injecting URLImageCache and bounding it still needs code (queued). |
| [WINDOWS-PORT](#windows-port) | (b); don't make future Windows work harder. | Bookkeeping queued for after the push. |
| [A-D6L-1](#a-d6l-1) | Not deciding yet; keep open. | Kept open; reminder at the end of the queue. |
| [A-D6L-2](#a-d6l-2) | (4). | Queued: the Kitty hairline prototype comes first. |
| [B-D2S-6](#b-d2s-6) | Asked whether "0 more" should ever show. | Answered below — your call. |
| [S3-NO-EXTENT-SPACING](#s3-no-extent-spacing) | Leaning (2); asked why SwiftUI does this. | Answered below — your call. |
| [B27-ANIMATING](#b27-animating) | (3). | Queued (a short design note first). |
| [B-D5G-4](#b-d5g-4) | (2), placed towards the end of the queue. | Queued near the end of the queue. |
| [RC5](#rc5) | Concur with the recommendation. | (a) with (c)'s test sweep, queued. |
| [TABLE-CLOSURE-COLUMN](#table-closure-column) | (b); asked about a "pure" closure overload. | (b) queued; the overload is answered below. |
| [SA-82-TABVIEW-PLAIN](#sa-82-tabview-plain) | (b). | Done (lane DOCS2): declined in C16; the slated row is closed. |
| [A21-TABPOPOVER](#a21-tabpopover) | (1). | Done (lane TABS, 2026-10-24): a tab's popover adapts as `View.popover`'s does; TUIkitTabs depends on TUIkitPresentation (+3.1% for an app on TUIkitApp and TUIkitTabs with no sheet of its own; decisions A21). |
| [B72-CAPSULE](#b72-capsule) | Mock up options B and C. | Mock-ups: [https://claude.ai/artifact/CAnzvGdKq3BqRMZNHYBSdY](https://claude.ai/artifact/CAnzvGdKq3BqRMZNHYBSdY) — your call. |
| [B75](#b75) | Asked what SwiftUI does. | Answered below — your call. |
| [B76-SELECT](#b76-select) | (b) for now. | No change. |
| [B78-VISIBILITY](#b78-visibility) | (b). | Queued. |
| [COLORPICKER-MODEBAR](#colorpicker-modebar) | (1). | No change. |
| [CONTROLGROUP-LOOK](#controlgroup-look) | (a). | Queued. |
| [FB3-BLANK](#fb3-blank) | (a). | No change. |
| [FB3-OTHERCAPS](#fb3-othercaps) | (2). | Queued; the Lines switch goes on a probe card first. |
| [STEPPER-WIDTH](#stepper-width) | (1). | Done: `.stepperValueWidth(_:)`, fitting the bounds by default (lane STEPPER). |
| [TAB-IMAGE-NAME](#tab-image-name) | (a). | Partly done (lane DOCS2): C11, the parity map, the guide and Tab's doc comment are corrected; the String forms in TUIkitBitmaps still need code (queued). |
| [TABBARMIN](#tabbarmin) | (b). | Done (lane TABS, 2026-10-24): `tabBarMinimizeBehavior(_:)` ships, and `.automatic` minimizes `.bordered` and `.grouped` tab views to the strip in a compact size class (decisions B96); the map's decline is gone with the gap. |
| [DRAWERS](#drawers) | (1). | Done (lane DOCS2): the draft is retired to Historical. |
| [B-D5C-1](#b-d5c-1) | Asked why SwiftUI has no if/else in SceneBuilder. | Answered below — your call. |
| [DEPR-ALERT-NAME](#depr-alert-name) | (b). | Done: `AlertPanel` (lane landing 2026-10-23). |
| [B-D1K-1](#b-d1k-1) | Deliver ⌘ to onKeyPress; default shortcuts stay on non-command modifiers; command shortcuts when a developer opts in. | Plan below; queued. |
| [B63-CTRLJ](#b63-ctrlj) | Asked for context, examples and how it works elsewhere. | Answered below — your call. |
| [B63-KITTY](#b63-kitty) | TextEdit's Ctrl-Return opens the context menu; asked where it is a line separator, and about Ctrl-Return for context menus. | Answered below — your call. |
| [B77-KEYTIME](#b77-keytime) | Where type select exists, bare keys never pass to shortcuts. | Plan below; queued. |
| [B77-SELECT](#b77-select) | Keep cursor-only. | No change. |
| [B89](#b89) | Asked for the real-world benefit. | Answered below — your call. |
| [B90](#b90) | Keep cells for now. | No change. |
| [A48](#a48) | Prefer revealed in-row buttons; asked about downsides, keys and the horizontal wheel. | Answered below — your call on the keys. |
| [A53-KEYBOARD-DRAG](#a53-keyboard-drag) | Explore a keyboard drag mode that limits focus to drop destinations. | Design sketch below. |
| [B-BITEMS1-1](#b-bitems1-1) | Follow macOS conventions; asked for more than a blanket default. | Proposal below — your call. |
| [B82](#b82) | Draw the pending state; system delay when local, with an override; SwiftUI's per-control defaults. | Plan below; queued. |
| [FB9-REDO](#fb9-redo) | (a), with the shortcut hint following focus. | Queued. |
| [B-KS-1](#b-ks-1) | Menu spelling by default, with an option for the case-sensitive one. | Queued. |
| [O13-KEYS](#o13-keys) | Asked for other macOS routes, per-menu jump keys and earlier CLI systems; propose. | Proposal below — your call. |
| [SCROLLX-UPSTREAM](#scrollx-upstream) | Nothing now; support it if a recognised client adds it. | No action. |
| [B-HELP-2](#b-help-2) | No shared key; modifiers on "?" for show-all; a default menu item toggling all help. | Rule adopted; key proposal below. |
| [A42-Q8](#a42-q8) | The recommendation. | Queued: menu now, chords through TextFormattingCommands. |
| [B-PASTE-1-EDITOR](#b-paste-1-editor) | Asked why not UTF-8 storage, and its downsides. | Answered below — your call. |
| [B-D4X-7-17](#b-d4x-7-17) | Tentatively concur; configurability by a modifier may be wise. | Option 1 queued, with a modifier considered. |
| [D4X-LOCALITY](#d4x-locality) | Screen and tmux paths seem fine; asked about asking keepers for clients. | Passthroughs queued; client queries answered below. |
| [B85-KEYBOARD](#b85-keyboard) | Full control. | Queued. |
| [B86](#b86) | Asked about Foundation's Markdown parser and version variation. | Answered below — your call. |
| [B51-LIVE](#b51-live) | Live everywhere it makes sense; measure; case by case. | Queued. |
| [DEPR-CATCHALL](#depr-catchall) | (b). | Queued. |
| [A27](#a27) | Remind you of the details. | Reminder below — your call. |
| [A34](#a34) | (2); asked how good (3) could be and its cost. | Option 2 queued; option 3 answered below. |
| [B61](#b61) | (2). | Queued (lands if the A/B is within a few percent). |
| [B95](#b95) | (2); also asked about ▌ and quadrant or diagonal glyphs. | Option 2 queued; the glyph questions answered below. |
| [O5-FROSTED](#o5-frosted) | (b), watching performance; (c) if it is significant. | Queued. |
| [O1-LOOSEN](#o1-loosen) | (a). | No change. |
| [P5](#p5) | (c). | Queued. |
| [WL-Q3](#wl-q3) | (b); measure the current impact first. | Queued (measurement first). |
| [NAMED-COLOURS-DARK](#named-colours-dark) | (a). | Built 2026-10-24 on lane `lane-colours` (D6M B-D6M-3); an A/B is owed before it lands. |
| [B-D6M-1](#b-d6m-1) | Always render correctly in subtrees with a changed colour scheme; try it and measure. | Measured: needs your choice, see the follow-up below. |

### Follow-up answers

#### B-BNDL-1

(a) costs least and cannot ship wrong; the others change more than they save.

The entry's numbers are stale. Today en.json is 8,099 B and 207 keys, so (a) costs about 8.1 KB per app, 0.07% of a stripped Hello (11,502,960 B). Its working cost is one paste per key-adding commit: 20 such commits in 13 days. A forgotten paste cannot reach main, because `BuiltInEnglishTests.copyIsTheFile` fails and names the keys. (b) saves the same 8 KB, only in the bundle. It moves English for translators from JSON into Swift, and en.json is the reference that `LocalizationKeyConsistencyTests` compares the other six languages with. (c) is worth having later: it removes the paste, the test stays the gate, and the repo has precedents (`Tools/RowFillValues/generate.py --check` in CI, `Tools/GenerateSFSymbols/generate.sh`). (d) matters only to an app that prints `tuiKitVersion` without its bundle, and it adds a second place to update at each release.

Recommendation: keep (a), and build (c) with a `--check` mode when the paste becomes a complaint. Nothing needed from you.

#### B-DYNVFIX-3

No (d) exists that is right for timers and detached tasks.

A closure carries no record of which holder made it, and Swift cannot inspect its captures. A probe on 6.2.4 tested which ambient values survive. A `@TaskLocal` reaches synchronous calls and `Task { }`, even past an `await`. It does not reach `Task.detached`, GCD or `Timer`. So an all-cases rule would have to decide which holder an object reads at rest, and no such rule is right for both "timer started by the page" and "timer started by the sheet". Three narrower designs exist. (d1) is (b) plus capturing the holder when TUIkit registers a handler. It is large, and every new closure API must remember to wrap. (d2) special-cases `dismiss` only. (d3) does as SwiftUI does and drops the extension you kept on 10-12. (b) covers the reported case, because the sheet holds the focus, and it applies to timers too. Its trade-off: a page's timer firing while the sheet is focused reads the sheet's environment. (c) is large and still wrong for the cases you named. The DYNVCLAIM A/B (busy box, indicative) was flat within about ±1.2% overall. `identity-churn` cold was +8.9%.

Recommendation: prototype (b), landing it only if its A/B is flat; decline (c). Need: your yes to (b).

#### B-REVIEW

They are all under `Documentation/SwiftUI parity/Decisions/`.

The main file is `SwiftUI API completion decisions.md`. The entries you have not seen since 10-04 are B38, B54-B58, B60-B95 and C1-C15. The per-lane entries are `### B-<LANE>-<n>` and `### C-<LANE>-<n>` headings in 92 files, including the subfolders `Compile time and binary size/` and `Module split/`. `grep -rn '^### [BC]-' "Documentation/SwiftUI parity/Decisions"` lists them. The count is now 380 B and 28 C in 92 files, against the entry's 277, 19 and 73. Several entries are out of date. B2, B19, B20, B28, B31 and B35 are headed by their first, safe form, but the fuller version has since shipped. B-DYNVFIX-3's price paragraph still says the A/B is owed; it ran on 10-13. Other "A/B owed" lines may already be measured, just not on a quiet box. `TimeSpan.swift:96` cites a file that no longer exists. 24 Decisions files cite probes that exist only in the working notes; B-SIZEDOCS-1 fixes those. The markdown link check passes.

Recommendation: correct these before you start reading (queued). Need: nothing until the corrections land.

#### BINARY-DISTRIBUTION

Both compiler bugs are on your Desktop. A binary would add to the source package, never replace it.

The purpose is to save a consumer from compiling the modules: a clean Hello build on 6.4.0 release takes 63-75 s. It would not make apps smaller. The source package stays the master for Linux, Windows, WebAssembly, the package traits, `TUIkitMacros` and CI. The binary would be an xcframework for Apple platforms only, behind a `.binaryTarget`. A binary needs library evolution. That makes `.swiftmodule` 37% smaller and `__text` 3.7% larger, gives slower resilient access, and limits the `@inlinable` tuning. The 7 TUIkitFoundation errors follow the language rule on all three compilers; they are not a compiler bug. Toolchains, tested on a toy module: an interface printed by 6.2 or 6.3 imports on 6.2, 6.3 and 6.4. One printed by 6.4 fails on 6.2. So a release built with 6.2 serves 6.2 and newer. Still untested: whether `package`-access declarations print usably into the interface. The reports are `swift-6.4-library-evolution-crash-synthesized-modify.md` (7 lines; crashes 6.2.4 to 6.4.0) and `swift-6.4-cmo-everything-opaque-result-client-crash.md` (6.4.0 only).

Recommendation: (a), source only, as the entry says. Need: your choice of (a), (b) or (c), and whether to file the two reports.

#### DOCS-HOSTING

Plan: one GitHub Pages site deployed from Actions, with a hand-written landing page and the unified DocC reference under `/docs/`.

Upstream runs two repositories: an Astro landing site and a stock DocC docs site, each on its own Pages site. Its site repository has no licence, so we build our own and take ideas only. Here, `build-docs.sh` already builds the one unified archive. It needs a `--hosting-base-path` option, an index redirect and its own 404 page; upstream's 404 copy would hijack every 404 under a `/docs/` base. The landing page would be about 10 static files under `Website/`: the pitch, install snippet, per-module products, feature blocks, recordings and links. The recordings would be asciinema casts written by a small recorder on the existing PTY harness. The WebAssembly Example would be a lazy "Try it" page with the `coi-serviceworker` shim, because Pages cannot set COOP/COEP headers. The main risk is size. Past runs give 45,000-70,000 pages, probably two files each. Pages allows a 1 GB site and a 10-minute deploy, and Cloudflare's 20,000-file cap rules it out for the docs. One measuring run decides. The first milestone (docs live on github.io) takes about 1 day; the whole plan about 4-6 days.

Recommendation: start with the measuring run, then that first milestone. Need: the domain, a site name and branding, and your go-ahead.

#### PACKAGE-RESOLVED

It only affects TUIkit's own builds and CI, never a consumer, because SwiftPM ignores a dependency's `Package.resolved` (general knowledge).

It pins swift-docc-plugin 1.4.5, swift-docc-symbolkit 1.0.0 and swift-syntax 604.0.0. **Pros:** CI is reproducible. It holds swift-syntax's prebuilt binaries, which exist only for certain version and toolchain pairs. Bisects get each commit's own versions. **Cons:** CI tests versions no consumer gets. Consumers resolve the newest in `602.0.0..<700.0.0`, so a breaking swift-syntax 605 goes unnoticed until someone runs `swift package update`. One lockfile serves a 6.2-6.4 matrix. The file needs manual updates, and benchmark runs rewrite it. Dependabot and Renovate raise lower bounds, which is wrong for a library. Three things now contradict the committed file and need fixing either way: `BRIEF-1018.md` tells agents never to commit it, the ci.yml comment says "every other lane tests the newest", and `Tools/verify-versioned-consumer.sh:43` describes it wrongly.

Recommendation: the research leans to untracking it again, since CI already tests the floor (602 on Linux 6.2) and the newest elsewhere. The alternative is to keep it and add a scheduled update job. Need: your choice.

#### SDK15-CI

The 15.5 SDK is the last macOS 15 SDK, but not the newest that runs on 15.8. And there is such an Xcode: Xcode 26.x.

Verified here: Xcode 26.3 runs on macOS 15.8.1. Its compiler is 6.2.4, and its 26.2 SDK has Swift 6.2 interfaces, including `InlineArray` and `Observations`. The 15.5 SDK comes from the Command Line Tools 16.4. It is what a CLT-only swiftly user gets, and its interfaces are 6.1.2. No macOS 15.x SDK carries the 6.2 standard library. Today's test also contradicts the entry and CONTRIBUTING. With swift.org 6.2.4, 6.3.3 and 6.4.0 on the 15.5 SDK, `InlineArray`, `Observations`, `Task(name:)` and `@Observable` all compile. The standard library, Concurrency and Observation load from the toolchain; only platform modules come from the SDK. So the `InlineArray` and task-name guards look unnecessary for swift.org toolchains. That is not proven: TUIkit was not rebuilt without them. Platform differences, such as `UndoManager`'s main-actor isolation and `FoundationModels`, do need guards.

Recommendation: (a). A lane catches exactly the platform-API regressions, and CONTRIBUTING's "6.1 standard library under a 6.2 compiler" sentence should be corrected whatever you decide. Need: (a) or (c).

#### B-D2S-6

No, there is no strong reason for "0 more" to show.

Under a scroll target behaviour the two indicator lines are reserved at every stop, so pages land whole. At a count of zero the code draws "▲ 0 more" on purpose (`ScrollIndicator.swift:135-138`). The one real argument for drawing something is that a blank reserved line looks like blank content or padding. A dim arrow alone answers that; the number adds nothing. The focus argument fails: when content overflows, at least one line always has a count above zero and still breathes. The click argument fails too: no click is routed to an indicator line. `.visible` is the "always shown" case, like a scrollbar thumb at the top, so it should get the same treatment.

Recommendation: at zero draw the bare arrow in the resting tertiary ink, or a blank line, under both a behaviour and `.visible`. Keep the counts from 1 up. It costs minutes plus re-recorded goldens, and lists and tables change too. Need: arrow or blank.

#### S3-NO-EXTENT-SPACING

SwiftUI charges spacing for each pair of members, whatever their size. It never asks about extent.

Measured: in `VStack(spacing: 10)` an empty `VStack` between two Texts adds both gaps (42 → 52). `EmptyView` adds nothing, even through `.frame`, `.padding`, `.onAppear`, `Group` and `AnyView`, because it is not a member at all. With nil spacing, empty stacks and `Spacer` report a `ViewSpacing` of 0, so they add no gap (32). In an `HStack` an empty stack even removes the Texts' default gap. The likely reason (inferred): a stack subtracts its spacing before it sizes its children. A gap that depended on a child's resulting size would be circular, and it would make neighbours jump when a child animates up from zero height. TUIkit's nil spacing is a constant, not per-pair preferences. So "charge every member" alone would add a column to `HStack { Text; VStack {}; Text }` where SwiftUI adds none.

Recommendation: option 2 in three parts. Members take gaps under an explicit spacing. `EmptyView` stays a non-member through modifiers. Empty stacks and spacers state a zero `ViewSpacing` under nil spacing. Need: your yes to all three parts.

#### TABLE-CLOSURE-COLUMN

No realistic case needs a "pure" overload beyond (b). `.equatable()` already covers the rest, and does it more safely.

There are four kinds of case (b) does not cover. Composite or styled cells use a small `Equatable` cell view returned as `.equatable()`. TUIkit's `EquatableView` is memoised by the view's value, so formatting runs only when the value changes. Formatting that depends on captured state, such as a units toggle, locale or search term, is where a pure marker is wrong: it would keep drawing stale cells after the toggle flips. In (b) the `FormatStyle` value is part of what the memo compares. Several properties in one cell take a key path to a computed property. Interactive cells cannot be memoised by any marker. A pure overload would be TUI-only, unchecked and unsafe for captures. One thing is not measured: whether a table's `.view` cell reaches the `EquatableView` memo. That needs a quick bench on `app-shapes/file-browser`.

Recommendation: build (b), document `.equatable()` cells, and run the bench. If the bench fails, teach Table to recognise `EquatableView` rather than adding a marker. Nothing needed from you.

#### B72-CAPSULE

Mock-ups of options a, b and c (Solid, and two Lines cap styles), in the default Green palette with a cursor row: [https://claude.ai/artifact/CAnzvGdKq3BqRMZNHYBSdY](https://claude.ai/artifact/CAnzvGdKq3BqRMZNHYBSdY). Under your item 19 (Block the default control appearance again), option c draws the tinted field by default and line caps under Lines.

#### B75

SwiftUI never draws the label view. It keeps the first Text's string and the first Image and hands those to AppKit.

Measured on macOS 15.8.1 with six tabs in a default `TabView`. The macOS style is an `NSTabView`, and `NSTabViewItem.label` is a `String`. An `HStack` of a red Text, a circle and a second Text shows "Red": not red, no circle, no "Two". A circle alone gives an empty segment. Bold italic Text draws plain. A `Label`'s heart and a `Tab`'s system image are dropped from the macOS 15 top strip. Under `.sidebarAdaptable` the label is rebuilt as a title, subtitle and icon row, and the circle is still dropped. So the shipped (a), the label's text in the strip's ink, already matches. (b) would do something macOS does not. Two small differences remain. TUIkit takes the label's first rendered line, so that HStack gives roughly "Red ● Two" (inferred). And TUIkit draws the SF Symbol before the title, which macOS 15's top strip leaves out.

Recommendation: keep (a). If you want exact parity, copy the first-Text rule. Need: whether you want that.

#### B-D5C-1

SwiftUI blocks a plain `if` in `SceneBuilder` on purpose. It did not just forget `buildEither`.

In the macOS 26.2 SDK, the generic `buildOptional` is marked unavailable with the message "if statements in a SceneBuilder can only be used with #available clauses". Only `if #available` works, through `buildLimitedAvailability`, which already erases to an existential scene. Every other builder (Commands, ToolbarContent, TableColumn, TabContent) has full branching. Where SwiftUI wants a scene property to change at run time, it adds a value or `Binding` parameter instead. The closest case is `immersionStyle(selection: Binding<any ImmersionStyle>, in:)`. Why, inferred: scenes become long-lived platform objects (windows, menu items, state restoration, `UISceneSession`s). Removing one by a condition has no good answer for its open windows, and flipping a branch would destroy and recreate every window in it. `#available` never flips.

Recommendation: keep option 1, the existential overload. If the shared name bothers you, a binding-shaped spelling such as `windowToolbarStyle(selection:)` is the SwiftUI idiom; behaviour is the same. Need: only whether you want that rename.

#### B-D1K-1

Plan, as you set it.

Under the kitty protocol, a ⌘ chord that the terminal lets through arrives with the Super bit. TUIkit will deliver it as `.command` instead of dropping it, so `onKeyPress` sees `[.command]` as in SwiftUI. Every consumer that matches a bare character must then refuse a ⌘ chord, or ⌘K types a "k". Those consumers are text fields, type select, the status bar, the theme and appearance keys, and the Example's page keys. Default shortcuts stay where they are: a `KeyboardShortcut` with `.command` keeps firing on its stand-in (`.commandKey`, Ctrl by default). It does not start firing on a real ⌘ just because a terminal happens to pass one. That keeps shortcuts the same from terminal to terminal. A developer who wants real ⌘ shortcuts opts in, and those then fire on a real ⌘ where the protocol delivers it. Following the modifier-first rule, the opt-in would be a modifier or environment value; it is not designed yet. None of this is measured: whether kitty and Ghostty pass a given ⌘ chord comes from their docs.

Recommendation: build it as above (queued). Need: nothing now; the opt-in's name comes with the lane.

#### B63-CTRLJ

Return sends CR (0x0D) and Ctrl-J sends LF (0x0A). TUIkit reads both as Return. The question is whether LF should become Ctrl-J, a newline key in vertical fields.

The two bytes look the same at a shell prompt only because cooked mode turns CR into LF. TUIkit runs raw, so it can tell them apart. Ctrl-M is CR, so it can never be told apart from Return. Elsewhere: shells and Vim treat Ctrl-J as Return. In Emacs it is a newline without indent. The macOS text system does nothing with it. Claude Code uses Ctrl-J as the newline that "works in any terminal". Crossterm (under Ratatui) reads LF as Ctrl+J in raw mode, and the kitty protocol sends it as itself. Examples: in Terminal.app, Ctrl-J in a vertical field would insert a newline; everywhere else it still acts as Return through the existing fallback. The risk is automation that sends `"hello\n"` meaning Return: in a vertical field that would insert a newline instead of submitting. The repo's own PTY harnesses all send `\r`.

Recommendation: option 2, plus one doc line saying automation should send CR for Return. Need: your yes.

#### B63-KITTY

You are right. On macOS 15+, Control-Return is a system shortcut, "Show contextual menu". U+2028 comes from the text system's key bindings, below that layer.

AppKit's `StandardKeyBinding.dict` maps Ctrl-Return to `insertLineBreak:` (U+2028). A probe that hands synthetic events to an `NSTextView` or a SwiftUI field confirms it. Those events skip the system shortcut layer, so the probe cannot see the menu. Your observation and third-party pages establish the menu; they also say turning the shortcut off restores the line break. The probe could not post real key events. So the entry's premise holds only for the key bindings, not for what a user gets by default. As a context-menu key: legacy terminals send Ctrl-Return as plain CR. Only kitty-protocol hosts (flag 8, which TUIkit requests) send it as itself, and that is unmeasured on any host. macOS may also consume it before the terminal sees it. By default `.commandKey` is Ctrl, so an app's `⌘↩` shortcut already is Ctrl-Return in TUIkit.

Recommendation: drop the U+2028 options. Add Ctrl-Return as a second context-menu key only under the kitty protocol, only when no app shortcut is on it, and only after measuring in iTerm2 and Ghostty. Keep Shift-F10. Need: yes or no.

#### B77-KEYTIME

Plan, as you set it: wherever type select exists, a bare key never reaches a shortcut, whether or not a row matches.

Today, with a list or table focused, any unmodified character joins the type-select prefix. The exception is a first letter that is bound to something: TUIkit's own q (quit), t (theme), a (appearance) and the help key, or an app's bare `.keyboardShortcut`. Those give way (`typeSelectGivesWay`, `InputHandler.swift`). The change removes that exception, so type select takes every bare character. This matches macOS, makes every row reachable by typing, and does not need every row's text when a key arrives. The consequence: while a list or table has focus, bare-key shortcuts do not fire. The user leaves the list, or uses a modified key, F-key or the menu bar. Inferred: this includes "?" for help, so the help route inside lists needs a modified key or F1 (see B-HELP-2). The status bar should stop advertising bare keys that cannot fire there.

Recommendation: build as stated (queued). Need: nothing.

#### B89

The real-world payoff is narrow but concrete. It shows up in SwiftUI code that puts gestures on controls.

As recognisers, controls gain three things. First, a control that can also be dragged. On macOS, pressing a plain button and moving off it fails the button, and an attached drag takes over. That is how chip and swatch toolbars that are clicked and dragged work, and kanban cards that are a `Button` plus a `DragGesture`. Ported code like that gets an undraggable button here. Second, immediate pressed feedback when a gesture ranks ahead. A row with `.onTapGesture(count: 2)` waits about a third of a second before showing the selection, which reads as lag. A button under `.highPriorityGesture(LongPressGesture())` shows no pressed state until the long press fails. Third, clean cancellation when a sheet opens or a scroll starts under the press (inferred; not audited). It does nothing for the keyboard, nothing for bordered buttons (macOS ignores attached gestures there, measured), and nothing for apps that put no gestures on controls. It costs about a day and a half across fifteen-odd controls and touches every click path.

Recommendation: build it when a port or the Example hits the first or second case. One cheap slice is the button's immediate pressed state (unpriced; inferred under a day). Need: keep it waiting, or take the slice.

#### A48

Revealed buttons (option 2) are viable. The real risks are three interaction failures, not hours of work.

Downsides beyond the work:
- A trackpad swipe arrives as a burst of wheel ticks. "A second wheel is the full swipe" would fire Delete from one gesture, so bursts must be told apart (an idle gap of roughly 150-300 ms, unmeasured).
- Vertical scrolling leaks horizontal ticks, so the reveal needs axis locking.
- Three text buttons take about 25 cells and need a narrow form.
- The buttons are a second focus level inside the row. They must coexist with keyboard reorder, which also claims Return and Escape, and with type select.
- Row memos must key on the revealed state.

Keys: Ctrl-R is taken by reorder. Option-letters do not arrive on Apple Terminal by default. macOS takes ⌃←/→. ⌥←/→ expand and collapse outlines. Proposed: ⇧→ reveals the leading edge and ⇧← the trailing, flipped under right-to-left text. The same chord again is the full swipe. Ctrl-L and Ctrl-T are the fallbacks for terminals that drop Shift on arrows. Both pairs are rebindable `RowAction`s. Wheel: the reveal joins the existing edge-hold chaining. It consumes ticks only when there is something to reveal, so it cannot trap an outer horizontal scroll.

Recommendation: option 2 with these keys, plus a PTY test that replays a recorded trackpad burst. Need: approval of the keys.

#### A53-KEYBOARD-DRAG

A carry mode that limits focus to drop destinations answers both objections from the 07-30 study. A stray Return can no longer drop on an unrelated list, because unrelated lists leave the ring.

Sketch: `.draggable` becomes a focus stop. Ctrl-R picks up, the same chord as list reorder; so does Space, or "Pick Up" in the context menu. While carrying, Tab and the arrows cycle only destinations that accept the payload, plus the origin and spring-loadable "navigator" controls. Those navigators are an existing SwiftUI-named class, so there is no new API. Return drops, or activates a navigator. Escape or the chord again cancels. The carried chip is drawn at the focus with its badge. The focused destination gets `isTargeted`. Every ring member needs a new "can drop here" cue. A status line and an idle expiry complete it. Risks:
- Ring membership is another per-frame side effect, so it must be journalled or cached subtrees fall out. The memo verifier cannot catch that.
- Lazy lists register only their visible rows, so a List should be one destination with an internal cursor.
- Keyboard drops need a synthesised `DropInfo`.
- The cost looks like several days (estimate).

Recommendation: ship the cheap prerequisite first (`.draggable` as a focus stop with Copy and Paste), then the carry. Need: your yes to that order.

#### B-BITEMS1-1

Follow macOS's three-party model rather than a blanket default.

On macOS the source declares the operations it allows, modifier keys narrow them, the destination picks one, and the badge shows what the destination picked. Finder moves within a volume and copies across volumes. Option forces a copy, Command a move, and Option-Command makes an alias. Inferred, unmeasured: an image well shows no "+" because it answers Generic, not Copy. Terminals pass one usable pointer modifier: ⌥ on Apple Terminal, ⌘ on iTerm2. Proposal:
1. Finish `dragConfiguration(_:)` so the source states its mask. A row reorder says `[.move]`; `.draggable` says `[.copy]`.
2. The destination proposes move when the drop lands in the container the drag came from and copy otherwise. `ActiveDrag` must then remember its source container.
3. One modifier flips between the proposal and its alternate. Its name comes from the host table. Alias is left to destinations that propose it.
4. The badge shows the effective operation. A replace-style destination returns nil, which means no badge.
5. The badge refreshes on any key event during a drag.
6. On the keyboard, the operation is chosen at pick-up, or toggled during a carry.

Recommendation: adopt this model, not a fixed `.copy` on `dropDestination`, and probe the image well in a real window. Need: your yes.

#### B82

Plan, as you set it.

1. **Draw the pending state.** The control draws as hovered while the spring-load timer runs, and as pressed on the frame it fires, as macOS does. Today it fires with no warning.
2. **Delay.** Use the system's spring-loading delay when the session is local, read the way reduce motion is read through `SessionLocality`. Use the fixed 0.5 s otherwise. Allow an override through an environment variable and a TUIkit-only modifier. Which macOS setting holds the delay, and its key, still has to be confirmed by a probe. Remote sessions keep 0.5 s.
3. **Per-control defaults.** Keep SwiftUI's, as measured on macOS 15.8 and already shipped: buttons, links, `.button` toggles and segmented pickers spring-load only under `.enabled`, and a tab view does under `.automatic`. The ColorPicker's well follows whatever macOS's colour well does. That has not been measured, so a probe decides it. Until then it stays as built.

The keyboard route mid-drag (Tab and Return) already exists and is unchanged.

Recommendation: build 1 first, then 2, with the probe for the setting and the colour well (queued). Need: nothing.

#### O13-KEYS

The macOS menu-bar keys cannot reach a terminal app. Earlier text UIs all used one pattern: a short mode entered with one key, with letters local to that mode. Proposal: make F10 enter that mode.

macOS offers Control-F2 (focus the menu bar), Control-F8 and Shift-Command-?. No Fn-M shortcut was found. The system handles these keys for the terminal emulator's own menu bar and never forwards them. One narrow exception (inference): a user who turns off Control-F2 in System Settings frees it, and TUIkit already decodes it. CUA/Windows (F10 or Alt, underlines shown only then), Turbo Vision, Midnight Commander (F9), Emacs (M-`), WordPerfect and Lotus (`/`, recalled) all work this way. Today TUIkit's F10 opens the first menu. Alt-letter needs Option sent as Meta, and File and Format both claim F. The proposal:
- F10 highlights the first title, opens nothing, and underlines the mnemonics only now.
- A letter opens its menu; arrows, Return and Escape work as before; any other key leaves the mode.
- Items keep type select.
- Each title gets a distinct mnemonic, taken from the first free letter of its words. One table serves bar mode and Alt-letter.
- Nothing new competes with global shortcuts.

Recommendation: build bar mode, and measure F10 and fn-F10. The cost is one extra keypress to open a menu. Need: your yes.

#### B-HELP-2

Your rule is adopted. "?" keeps one meaning: the focused control's help. A modified "?" shows all help. A default menu item, enabled only when some help exists, toggles all help on and off.

Which modifier can arrive is the open part. All of what follows is general knowledge or inference, not measured here. On US layouts "?" is already Shift-/, so Shift-? is just "?". Ctrl-? usually reaches a legacy terminal as DEL (0x7F), the same byte as Backspace, and Ctrl-/ as 0x1F. Neither works as a portable key. Alt-? arrives only where Option is sent as Meta, which Apple Terminal does not do by default. Under the kitty protocol, which TUIkit requests, Ctrl-? and Alt-? should arrive as themselves. Two more points: a focused text field types "?" itself, and under B77-KEYTIME a focused list takes "?" for type select. So a key that works everywhere cannot be a "?" chord.

Proposal: Alt-? and Ctrl-? toggle all help where they arrive as themselves. Shift-F1 is the portable key, given that TUIkit already undoes Apple Terminal's re-coding of shifted F-keys. The menu item is the route that works on every terminal, through F10. Measure Shift-F1 per host first. Need: approval of Shift-F1.

#### B-PASTE-1-EDITOR

Your instinct is right about memory. UTF-8 storage alone does not buy the speed the entry hopes for, it changes some behaviour, and most of the gain comes from undo, which is independent of storage.

Measured on a 16 MiB document: a `Character` is 16 bytes. Splitting into `[[Character]]` takes 0.51 s and 305 MiB, and the join done on every edit takes 0.25 s. A line table over UTF-8 takes 0.009 s and 1.4 MiB. Downsides beyond the work:
- The editor's coordinates are grapheme clusters. With a byte buffer, edits can merge or split clusters (flags re-pair, combining marks join), so the caret must re-snap after every edit.
- `String.Index` is not a stable coordinate, so integer offsets are needed internally.
- The binding is a `String`, so each key still costs at least a copy-on-write (1 ms measured).
- CRLF is one `Character` in Swift. A byte scan for LF would split it.
- The line table needs updating on every edit.
- `[Character]` appears across the wrapping, tab and word code.

Undo as edits works with today's storage and removes the 800 MiB of snapshots.

Recommendation: measure, then do undo as edits inside R1. After that, if memory still matters, use one `String` plus a line table, building `[Character]` only for drawn lines. Need: your yes to that order.

#### D4X-LOCALITY

Nothing blocks the screen and tmux passthroughs; both are queued.

OSC 52 goes down the terminal stream to the terminal the user is looking at, so passthrough is safe whatever the locality. Its only weakness is that the app cannot confirm the copy, so the status says "Sent", not "Copied". screen needs chunked DCS wrapping; the 256-byte limit comes from Chromium's script and is unmeasured. tmux needs `allow-passthrough`, which is off by default (added in 3.3). tmux 3.7c is installed here for a probe. One design point remains: the precedence order, so a copy is not sent twice. Asking keepers for their clients: **pros:** it is the only way to be certain the user is at the desk. It makes `pbcopy` work where the terminal ignores OSC 52, and it makes the desk's clipboard readable for paste, which passthrough cannot do. tmux already works this way. **Cons:** every keeper has a different interface (screen's `-Q`, zellij unclear, dtach and abduco have none). The answer is a snapshot, and a stale "local" puts text on the wrong machine. Tracing processes is heuristic. Each copy runs a subprocess. It does nothing over ssh.

Recommendation: passthroughs now, with tmux `set-clipboard on` checked before passthrough. Client queries only for a keeper someone uses and asks for. Need: nothing.

#### B86

Not recommended. Foundation's parser exists only on Apple platforms, and this repo has never tested how it varies between OS versions.

On Linux, neither swift-foundation `main` nor the 6.3.3 static SDK has a Markdown parser. So a Darwin-only path would give two parsers whose output differs by platform. TUIkit's 138-case table was measured on macOS 15.8, and the 550,000-string differential ran once on the same machine. CI's macOS 15, 26 and 27 lanes compare TUIkit against that frozen table, not against each OS's Foundation. Version-specific bugs did exist in older releases (an iOS 16 report), which shows it can vary, but no difference between 15.8 and 26 is known. Using it would also cost the atom scheme for interpolations, an `AttributedString` per parse on a hot path, and behaviour that follows the user's macOS.

Recommendation: keep TUIkit's parser as the one implementation. Add a Darwin-only differential test that runs the corpus plus seeded random strings through the live `AttributedString(markdown:)` on each macOS CI lane, about half a day. Then a red lane tells you if Foundation's behaviour moves. Need: your yes.

#### A27

Reminder: these are Wave 16's pixel-effect leftovers, all eight of which fail to compile today.

They are the six view transforms (`scaleEffect`, `rotationEffect`, `rotation3DEffect`, `projectionEffect`, `transformEffect`, and the spellings A39 waits on), plus `mask(alignment:_:)` and `drawingGroup`. A separate question is linear-light blending for `drawingGroup(colorMode: .linear)`. A glyph cannot be scaled or rotated, so a view transform can only be declined or faked; shapes, unlike views, can rotate since W1. The options:
- **1.** Decline the transforms. Ship `mask` (content kept where the mask draws, at its alpha). Ship `drawingGroup` as `compositingGroup`, with `.linear` documented as ignored. About half a day.
- **2.** Option 1, plus real linear blending inside such a subtree. It is cheap through lookup tables, and the sRGB decode already exists.
- **3.** `scaleEffect` drawn as a reveal from its anchor. A 0.95 press effect would then silently do nothing.
- **4.** Decline everything.

Since the entry was written: `mask` should use `clipShape`'s half-cell coverage rule, so the two agree as they do in SwiftUI.

Recommendation: option 2. Need: your pick.

#### A34

Option 3 could be honest: a real low-pass filter at cell resolution. But it would show only two or three coarse blur steps in a 0.35 s transition.

Its best form (inferred): the radius grows to about one cell at the peak. Each cell takes the average of its neighbourhood's displayed colours, glyph ink weighted by coverage. Glyphs lose contrast and then drop out under the existing ½ rule. Optionally, ▀ half-blocks double the vertical resolution where blocks fill the line. Edges get partial alpha. The pipeline already has most pieces: transitions work from the kept buffer, the compositor resolves colours in linear light, and the O5-FROSTED design describes neighbour sampling. Limits: `OpacityRegion` has one alpha per rectangle, so per-cell edge alpha is new plumbing and most of the day. 256- and 16-colour terminals would fall back to option 2. Cost (inferred): CPU is small, under 100 µs a frame for 40×10, paid only while the transition runs. Bytes are the real cost, because a blur breaks SGR runs. That is about 330 KB per transition for 40×10 and about 24 MB/s for a full screen, which matters over ssh.

Recommendation: ship option 2 now. Revisit option 3 alongside O5-FROSTED (b), which you have chosen and which shares its neighbour sampling, coverage table and per-cell alpha. Need: nothing.

#### B95

▌ is possible but worth much less than ▀. Quadrants and diagonals work for non-rectilinear gradients, with limits.

A cell shows two colours split by one glyph's partition: ▀ splits top from bottom, ▌ left from right, ▙▛▜▟ cut off a corner, and ◢◣◤◥ split the diagonal. A cell is 1 wide and 2 tall, so the vertical direction is the coarse one. A horizontal gradient already gets one step per column. ▌ therefore helps only narrow horizontal spans. A per-cell choice between ▀ and ▌, by which way the colour changes more, is cheap and never worse. For radial, angular and mesh gradients, a best-of-candidates two-colour split follows curved isolines better; the `.blocks` image path already does this. Limits:
- Exclude ▚▞, which read as noise.
- Apple Terminal draws block elements short of the line.
- Corner triangles fill the cell only in Ghostty and iTerm2 (measured), so they need the `cornerTrianglesFillTheCell` gate.
- ◢◣◤◥, ▀ and ▌ are East Asian Ambiguous width.
- A cell's diagonal runs at about 63°.
- Text over a gradient keeps only one sample.
- Gradient areas cost about twice the SGR bytes.

Recommendation: option 2 through the shapes' half-block emitter, so gradient Rectangles and Circles agree. Add the ▀/▌ choice if it is cheap there. Leave quadrants and diagonals as a follow-up, since sharing TUIkitImage's matcher is a design question. Need: your yes to that scope.

#### B-D6M-1

You asked that colours always render correctly in subtrees with a changed colour scheme, and to try it and measure. Named colours now do (NAMED-COLOURS-DARK, shipped): `Color` stays 5 bytes, because a name is one byte and its light and dark values are a constant table. An asset-catalogue colour cannot follow, because it needs two arbitrary RGB values (6 bytes) and `Color` has room for 3. I built the bigger `Color` to measure it (branch `lane-colours-schemed-wip`, not wired up):

| Type | Before | After |
|---|---|---|
| `Color` | 5 | 8 |
| `TextStyle` | 40 | 52 |
| `Text` | 72 | 84 |
| `FlexibleFrameView<Text>` | 168 | 180 |
| `TextTap` | 101 | 117 (gains padding; its value hash drops from dense to runs) |

- **1. Keep choosing the variant when the colour is made.** *Price:* Free. Wrong in a pinned subtree of the other scheme; exact for a set with one colour, the common case.
- **2. Grow `Color` to 8 bytes.** The only option that is always correct. *Price:* About a day more (re-lay out `Text` and `TextStyle` so nothing gains padding; wire the asset catalogue, `TUIkitAppKit`'s compiled catalogue and dynamic `NSColor`), then an A/B on the text-heavy scenarios. Every `Text` grows about 20%.
- **3. An index into a process-wide table of catalogue colours.** Fits in 5 bytes. *Price:* About a day, plus an exception to "No Singletons": an index that gives a colour its meaning is not a cache.
- **4. Choose by the scheme in force where the view's body runs**, through a task-local the palette and scheme modifiers set, as `ColorDepth` works. *Price:* Half a day, no size change. Not always correct: a colour made above a pin and drawn below it gets the outer scheme.

Recommendation: 4 now, which fixes the common case (a pinned subtree whose views make their own colours) at no cost to every `Text`; 2 only if a real app is caught by the remaining case. Need: your choice.

## Summary

| Id | Question | Recommended | If you don't answer |
|---|---|---|---|
| [A-TS-1](#a-ts-1) | Do you accept that, on Swift 6.4, test rebuilds after an edit to TUIkitFoundation or a module below it are 11-23% slower since the per-module test split, or should I measure merging the five smallest test targets into the integration target? | Run option 2 as the experiment you already allowed, and keep the split meanwhile. If the merge recovers most of the low-module loss without slowing those five modules' own edits much, land it with your OK. Either way, record the investigation in TS.md. | The split stays as it is, and on 6.4 most edits (those to low modules) rebuild tests 11-23% slower. TS.md still needs the investigation written up. |
| [B-BNDL-1](#b-bndl-1) | Should TUIkit keep its English both compiled in and in the bundle, and keep the version reading 'unknown' when there is no bundle, or change either? | (a). The test already catches a stale copy, and neither the byte cost nor the 'unknown' version matters enough to change how translators work or how releases are made. | The shipped behaviour stands, which is fine. |
| [B-D6M-2](#b-d6m-2) | Should the @Animatable and @Entry macros move into a separate package, in a second repository, so apps that don't use them never resolve swift-syntax? | (a) for now, and measure (c) cheaply. Take (b) only if users complain about resolution time or conflicts, because two packages are an ongoing release cost. | Things stay as they are: every client resolves swift-syntax and only macro users compile it. |
| [B-DYNVFIX-3](#b-dynvfix-3) | When several views hold one class object, closures made in any of them read the first holder's environment. Do you accept that limit, want the cheap 'focused holder becomes primary' fix prototyped, or want the full per-dispatch fix built? | (b), landing it only if the A/B is flat. Decline (c). | The limit stays documented, and a sheet that shares its page's object needs the workaround. |
| [B-REVIEW](#b-review) | Do you want to review the B entries (safe option shipped) and C entries (declined) in the decisions files, read a one-page digest of the ones that change behaviour, or let them all stand? | (b). | They all stand as shipped. |
| [B-SIZEDOCS-1](#b-sizedocs-1) | Should I commit the remaining SwiftUI probes that only decision documents cite (about 438 KB of sources, text outputs and notes, without the pixel dumps) and point their citations at the committed copies? | (a). It is the same kind of material you approved, at about twice the size. The pixel dumps are large and reproducible, which your 10-12 rule keeps out of git. | The citations stay machine-local, and the evidence is at risk if the notes are pruned or the disk fails. |
| [BINARY-DISTRIBUTION](#binary-distribution) | Do you want TUIkit offered as a prebuilt binary, for example an xcframework, or only as source through SwiftPM? | (a). | In effect (c): nothing is built, and the library-side levers stay unpursued. |
| [DOCS-HOSTING](#docs-hosting) | Should the unified DocC reference (with its 'which module provides it' index) be published on GitHub Pages, should the index be committed as a file, or should it stay reachable only locally? | (a). The docs job already builds the publishable form; only the publish step and your settings switch are missing. | The index stays local-only, and readers use SPI's per-module pages. |
| [DORMANT-DESIGNS](#dormant-designs) | For four dormant design documents (layout constraints, locating things without drawing them, configurable focus indication, actor isolation), should I retire them to Historical with entries in Future options, or schedule their open parts? | (a). (3) and (4) already recommend doing nothing until something forces it; (1)'s SwiftUI half has shipped and its FrameSize idea conflicts with your frames ruling; (2)'s user-visible goals shipped by other routes. Decide OOB-STYLING at the same time. | The four stay in live folders as stale plans. |
| [MACOS27-PARITY](#macos27-parity) | When the work moves to a macOS 27 machine, should the SwiftUI parity baseline move to the newest SDK, counting its new APIs as gaps and removing what it deprecates, or stay on the macOS 26 SDK? | (a). It's what your 10-18 task(name:) ruling implies and what the parity rule asks for, and it needs nothing until the machine moves. | Parity stays on the 26 SDK, and TASK-NAME and DEPR-MACOS27 stay blocked. |
| [OOB-STYLING](#oob-styling) | Should I schedule the spike that decides the out-of-band styling design (each row stored as plain text, with styles in a separate list of runs), or retire the design to Historical? | (b), decided together with DORMANT-DESIGNS. | It stays 'proposed' in a live folder. |
| [PACKAGE-RESOLVED](#package-resolved) | Should Package.resolved be committed fresh once, as an exception to your 'never commit it' rule, or removed from git and ignored? | (b). It matches your never-commit rule permanently and ends the noise. (a) is the census's earlier suggestion if you'd rather keep pins. | The stale file stays committed, and every worktree carries a local modification that agents must skip. |
| [SDK15-CI](#sdk15-ci) | Should CI build TUIkit with a swift.org 6.2 toolchain against the macOS 15.5 SDK, which is what a swiftly user on macOS 15 with the default Command Line Tools gets? | (a) if you want swiftly users on macOS 15 supported (your 10-07 point that users may not use Xcode); otherwise (c). I lean (a). | In effect (b): it builds today and may silently stop. |
| [SINGLETON-CACHES](#singleton-caches) | Do the two process-wide caches, URLImageCache.shared and the ASCII palette search-index store, count as singletons under CLAUDE.md's 'No Singletons' rule? | (c). The palette store is a memo whose contents nothing can observe. The image cache holds downloaded data the app sees, grows without limit, and can't be swapped for tests. | Both stay as they are, and the rule's text and the code disagree. |
| [WINDOWS-PORT](#windows-port) | Should the Windows port of the console layer (TUIkitApp's Windows code) be scheduled now, or should Windows stay 'easy to port later', with only the small CI bookkeeping done? | (b). | Windows stays a goal, and even (b)'s bookkeeping can't happen until a push. |
| [TERMCAPS-API](#termcaps-api) | Item #9: should TUIkit tell an app what the terminal it runs in can draw (patterned underlines, overlines, blink, graphics…), read-only, so that a page can say "your terminal doesn't draw this"? Three questions on naming, granularity and scope. | Build it as the proposal says, about a day: `terminalCapabilities` and `Feature`, colour depth left as `ColorDepth`, patterned underlines as one group, only what TUIkit measures. | Nothing is exposed; the Example keeps saying what each terminal does in its own text. |
| [A-D6L-1](#a-d6l-1) | Should the `.surface` look (no border; rows on a lifted background) stay an opt-in style, become what `.automatic` draws for tables (and perhaps lists), or replace what `.inset` draws? | Option 4. You have already been using `.surface` in the Example, and the table border is the heaviest chrome. Decide lists together with A-D6L-2. It is a question of look, so it is yours. | Tables and lists stay bordered by default, and `.surface` stays an opt-in style whose doc comments still call it a prototype that may be renamed or removed. |
| [A-D6L-2](#a-d6l-2) | Should lists draw a separator line under every row by default, as SwiftUI's do on macOS, given that here each separator takes up a whole terminal line? | Keep option 1 for now. Revisit as option 4 when the hairline prototype is scheduled, since it removes the cost that makes option 2 bad. If you make the surface look a default (A-D6L-1), decide option 3 at the same time. | Separators stay off unless an app, section or row asks for them. The Example's "Separators between rows" toggle remains the way to see them. |
| [B-D2S-6](#b-d2s-6) | Under a scroll target behaviour such as `.paging`, should a `.text`-indicator scroll view keep its '▲ N more' / '▼ N more' lines drawn at every stop (shipped), or let them come and go and make every page two lines shorter? | Option 1, unless the '▲ 0 more' line at the top bothers you on the Example's Scroll View page. | The pair stays drawn at every stop under a scroll target behaviour. |
| [S3-NO-EXTENT-SPACING](#s3-no-extent-spacing) | Should a stack put its spacing on both sides of a child that takes no rows (an empty `VStack`, `Color.clear.frame(height: 0)`), as SwiftUI does, or keep TUIkit's rule that such a child takes no gap? | Option 2. Your stack-spacing rulings so far all followed SwiftUI (A-BITEMS1-1, L12, L14), and the gap is the app's own spacing request. Ship it only after the audit shows framework internals won't add stray gaps. | TUIkit's rule stays, the Example keeps relying on it, and it stays an open divergence in guide §3. |
| [B27-ANIMATING](#b27-animating) | Do you want animated scrolling, where a `scrollTo` or scroll-position change made inside `withAnimation` moves line by line over several frames and reports `ScrollPhase.animating`, instead of jumping? | If you want motion, option 2, preceded by a short design note to price it. SwiftUI code that writes `withAnimation { proxy.scrollTo(id) }` moves there and jumps here. It is low priority either way. | Scrolls keep jumping, `.animating` is never reported, and R1 stands. |
| [B-D5G-4](#b-d5g-4) | When geometry correction draws a subtree twice in one frame, should its side effects be held back so that only the kept drawing's take effect (days of work), or should this stay a known issue? | Keep option 1 for now, and price option 3: `onChange` is the effect apps notice. | It stays a pinned known issue, and a reader's first frame inside a corrected subtree can fire one extra `onChange`. |
| [RC5](#rc5) | When a container that sorts its content by asking each child's type drops something it does not recognise, should that go through one shared fallback that stops a debug build (SoftTrap), instead of being found and fixed case by case? | (a), scoped to genuine gaps and placed in the shared member resolution, with (c)'s test sweep for the remaining seams. | Fixes continue one by one, and RC5 stays OPEN in the audit. |
| [TABLE-CLOSURE-COLUMN](#table-closure-column) | Should TUIkit add a way to tell a Table that a closure column's cells depend only on the row, so that unchanged rows skip rebuilding, and do you want to post the Swift-forums 'purity effect' pitch? | Re-profile file-browser first. If formatting is still a large share, do (b); otherwise (c). Post the pitch if you want to. | Closure columns keep rebuilding every drawn cell each frame, and the pitch stays an unposted draft. |
| [SA-82-TABVIEW-PLAIN](#sa-82-tabview-plain) | Should TabView accept plain views as pages through SwiftUI's non-deprecated `TabView(content:)` (where SelectionValue == Int), or should that form stay declined? | (b). On macOS the plain form is useful only together with the deprecated `.tabItem`, so adding it would mostly compile code that shows unlabelled tabs. | Plain-view TabView content keeps failing to compile, and the slated row ('the fix draws the tagged children as pages; no ruling') stays open. |
| [A21-TABPOPOVER](#a21-tabpopover) | When an app sets a compact size class, should a tab's popover (TabContent.popover) turn into a sheet like every other popover, at the cost of TUIkitTabs depending on TUIkitPresentation? | Option 1. It is the only option that honours your ruling without a silent gap. First measure what it adds to an app that imports only TUIkitTabs, and fall back to option 3 if that cost is out of proportion to an edge case. | Tab popovers stay popovers under .compact. Every other popover, sheet and split view adapts as ruled. |
| [B72-CAPSULE](#b72-capsule) | Should a list row's .standard badge sit in a capsule, a tinted field such as ` 12 `, as macOS draws it, instead of today's plain dim text? | Option c if FB3-OTHERCAPS goes ahead, otherwise a. Under the Lines default, a solid fill would be the only filled element on screen. | Badges stay plain text. The shipped option stands, open to your veto. |
| [B75](#b75) | Should a tab whose label is the app's own view (Tab(content:label:)) draw that view inside its chip in the tab strip, instead of only its first line as plain text? | Option a, unless you want pictures in chips for TAB-IMAGE-NAME, in which case b. | Chips keep drawing a custom label as text. The shipped option stands, open to your veto. |
| [B76-SELECT](#b76-select) | In a .sidebarAdaptable tab view's sidebar, should moving the cursor select the tab, as a macOS sidebar does, or should the user keep choosing with Return, Space or a click? | Option a. A sidebar is a navigator with a single selection, Return has nothing else to do there, and this is how macOS behaves. | Return, Space or a click choose the tab. |
| [B78-VISIBILITY](#b78-visibility) | Should section actions show only while the focus is inside their section or the pointer is over it, or always, as now? | Option b. It keeps a keyboard route, matches macOS for the mouse, and cuts Tab stops. | Actions stay visible all the time. |
| [COLORPICKER-MODEBAR](#colorpicker-modebar) | Should ColorPicker's panel switch modes with a segmented Picker or a row of Buttons instead of its 10-tab TabView, and should TUIkitTabs stop depending on TUIkitLists? | Re-measure under today's products first. If the saving holds, choose option 2, which keeps one Tab stop and the feel of a single control. Leave option 4 alone until an app that uses only Tabs needs it. | The panel keeps its TabView, and Tabs keeps depending on Lists. |
| [CONTROLGROUP-LOOK](#controlgroup-look) | Should a ControlGroup draw its buttons as one segmented face, with caps only at the two ends and a rule between buttons, as macOS and TUIkit's own segmented Picker do? | Option a, drawn exactly as the segmented Picker is, whatever FB3-OTHERCAPS settles for its caps. | ControlGroups keep drawing as touching capsules under Lines. |
| [FB3-BLANK](#fb3-blank) | Under the Lines appearance, should a text field's caps be `│text│` (shipped, one cell each) or `│ text │`, with a blank cell inside each cap? | Option a. | Fields keep │text│. |
| [FB3-OTHERCAPS](#fb3-othercaps) | Should segmented pickers and TabView chips (including those in the colour picker's panel) take their end caps from the Appearance family, as buttons and text fields now do, instead of always drawing ▐ ▌ half-blocks? | Option 1 now. Put the toggle's Lines look on a probe card (option 2) before building it. | Segments and chips keep their half-block caps under Lines. |
| [STEPPER-WIDTH](#stepper-width) | Should a Stepper reserve the width of its widest value by default, so that ▶ never moves, or should reserving be opt-in? | Option 1. A row that jitters is cosmetic, but an arrow moving under a repeating click is a functional bug. | No modifier is added, and the arrow keeps moving. |
| [TAB-IMAGE-NAME](#tab-image-name) | Ship Tab's `image:` initialisers, which take an image name (a String), the same way Label(_:image:) already ships, or keep them declined with a corrected reason? | Option a, which is consistent with P12 and Label. Whatever you pick, correct C11 and the parity-map reason now; that fix is factual and costs nothing. | The forms stay declined under a reason that is wrong. The factual correction should still be made. |
| [TABBARMIN](#tabbarmin) | On macOS, tabBarMinimizeBehavior takes only .automatic, which shrinks the tab bar when the window is short of room. Should TUIkit honour it by collapsing a tab view to the compact strip, and if so, triggered by what? Or should it refuse the modifier? | Option b. It honours the API, changes no default (your B3 rule), and reuses the size-class collapse already shipped. Correct the map's reason whatever you choose. | It stays a gap with a stale reason in the map. |
| [DRAWERS](#drawers) | Build a TUI-only drawer (and perhaps a slideover) from the draft, or retire the draft to Historical, now that .inspector, split views and docked live sheets cover the cases it was written for? | Option 1. The cases the draft wanted are covered by APIs that carry SwiftUI's names, and a TUI-only drawer would duplicate .inspector. | The draft stays in Documentation as an open item and keeps appearing in the census. |
| [B-D5C-1](#b-d5c-1) | Keep TUIkit's extra windowToolbarStyle(_: any WindowToolbarStyle) overload, replace it with if/else support in SceneBuilder, or have the Example choose its toolbar style only at launch? | Option 1. | The overload stays. |
| [DEPR-ALERT-NAME](#depr-alert-name) | Rename TUIkit's `Alert` view, whose name matches SwiftUI's soft-deprecated `Alert` struct? | Option b. CLAUDE.md keeps TUI-only APIs apart from SwiftUI's, and the current name reads as SwiftUI's retired type. | The name stays. |
| [A-MENUBAR-1](#a-menubar-1) | Should TUIkit offer a standard set of display-option commands, `DisplayCommands()`, adding View ▸ Palette ▸ and View ▸ Border Style ▸ to any app's menu bar, as the Example now writes for itself? | Option 2, acting on the app's palette and appearance managers as the `t` and `a` keys do. | Apps write their own, as the Example does. |
| [B-D1K-1](#b-d1k-1) | Where the kitty keyboard protocol lets a ⌘ chord through, should TUIkit deliver it as ⌘ (.command) instead of dropping it, and if so should KeyboardShortcut("s") fire on the real ⌘S, on its Ctrl-S stand-in, or on both? | Deliver ⌘ and fire on both. It's the only precedence that never makes a shortcut unreachable, and it gives onKeyPress SwiftUI's [.command]. Not urgent: nothing breaks while it waits. | ⌘ chords stay dropped under the kitty protocol, and ⌘ shortcuts are reached only through the stand-in key. |
| [B63-CTRLJ](#b63-ctrlj) | Should the input parser read LF (0x0A) as Ctrl-J instead of Return, so a vertical TextField can bind Ctrl-J to insert a newline on every terminal? | Parse LF as Ctrl-J. The existing fallback limits the risk to vertical fields, and the result is a newline key that works on every terminal, Apple Terminal included. | LF stays Return. In a vertical field a newline is Ctrl-O everywhere, or Option-Return where Option is sent as Meta. |
| [B63-KITTY](#b63-kitty) | Under the kitty keyboard protocol, should Ctrl-Return in a vertical TextField insert U+2028 LINE SEPARATOR, as SwiftUI does, instead of submitting? | Insert U+2028, as SwiftUI does, once the text-path work is priced. If that comes to more than about a day, ship '\n' for now. | Ctrl-Return submits a vertical field on every terminal, as it does today. |
| [B77-KEYTIME](#b77-keytime) | Should type select decide when the key arrives, taking a first letter whenever some row starts with it and passing it on when none does, instead of today's rule that a bound first letter always goes to its binding? | Keep. A bound key should never change meaning with the contents of a list, and the alternative costs a day plus a measure of every row on every keystroke. | A bound first letter keeps going to its binding. Rows starting with q, t, a, ? or an app's bare-key letter can't be found by typing that letter first. |
| [B77-SELECT](#b77-select) | Should type select also select the row it lands on, as macOS does, rather than only moving the keyboard cursor? | Keep cursor-only, so type select behaves like the arrows. If you want macOS's behaviour, take it through V2 so the two keys don't diverge. | Type select moves the cursor, and the user presses Space or Return to select. |
| [B89](#b89) | Should every control's press become a full gesture recognizer that can wait, fail and be cancelled, as SwiftUI's plain-style button is? | Keep for now. Build it when a port needs a gesture on a control to hear a press that failed: the cases are narrow, and the change touches every control's click path. | Controls never fail or wait, and the two differences stay as documented. |
| [B90](#b90) | Should gesture distances (DragGesture.minimumDistance, LongPressGesture.maximumDistance, a tap's slop) be in points, converted through the terminal's reported cell size, instead of whole cells? | Keep cells. Every other TUIkit distance is in cells, and O0 just chose cell units for shapes. The porting note covers the trap. | Distances stay in whole cells, so DragGesture(minimumDistance: 10) means ten cells. |
| [A48](#a48) | How should SwiftUI's .swipeActions be reached in a terminal: as an edge menu opened by a row chord or a horizontal wheel, as buttons revealed in the row, or not at all? | Option 1. A swipe action is a context menu for one edge, and the menu engine already provides the keyboard handling, dismissal and colours. | swipeActions stays unbuilt (two parity gaps), and SwiftUI code that uses it does not compile. |
| [A53-KEYBOARD-DRAG](#a53-keyboard-drag) | Should .draggable get a keyboard route, overriding your 2026-07-30 decision to table keyboard drag-and-drop on modality, or should .draggable be recorded as an explicit exception to the no-mouse-only rule? | Confirm the tabling as an explicit exception and document the .copyable/.pasteDestination route. The modality objection still stands, and the same copy-and-paste route is what SwiftUI offers on macOS. | .draggable stays mouse-only with no recorded exception, an open breach of the no-mouse-only rule. |
| [B-BITEMS1-1](#b-bitems1-1) | Beyond the badges ruled on 10-12 (+ for copy, ↗ for link, ⊘ for forbidden, nothing for move), should a .delete drop wear a glyph, and should dropDestination propose .copy so its drags show +? | Leave .delete bare. Have dropDestination propose .copy only once a real-window macOS probe shows the +, since TUIkit shouldn't claim macOS behaviour it hasn't measured. | Only item-provider drops show badges; .delete, .cancel and TUIkit's own destinations show none. |
| [B82](#b82) | Which of spring loading's three unbuilt pieces do you want: drawing the pending state, a delay setting, or the colour well's opt-out? | Draw the pending state: firing without warning is the gap a user actually feels. Leave the delay setting until an app asks for it, and the colour well until it's measured. | A paused drag fires spring-loaded controls with no visual warning, after a fixed 0.5 s, and a ColorPicker's well opens under .enabled. |
| [FB9-REDO](#fb9-redo) | Should ⌃Y be bound to redo app-wide, with text fields keeping it as yank, so that some redo key reaches the app on every terminal? | (a). ⌃Y is the one portable redo key, and fields keep the macOS yank they already have. | On Apple Terminal at its defaults there is no redo key, and the status bar shows a ⌥_ redo hint that does nothing. |
| [B-KS-1](#b-ks-1) | Should a status-bar item's single-character key be drawn the way a macOS menu draws it ('Q quit', '⇧N new') instead of as the app typed it ('q quit', 'N new')? | Menu spelling. It completes your 10-05 request and ends the mixed styles within one bar. | Status-bar items keep showing keys as typed ('q quit') beside menu-style hints such as '⌃Z undo'. |
| [O13-KEYS](#o13-keys) | For the menu bar that O13 has now landed on main, should the keys stay the ones you accepted on 10-04 (F10, Alt-letter, a click), with no extra chord and no TUI-only menuBarVisibility for now? | The 10-04 keys. The 10-05 objection was about spending F-keys on a minor feature, and opening a menu bar is F10's standard use. Measure F10 (the lane landed without measuring it), and add a chord or menuBarVisibility only if an app asks. | The menu bar keeps the keys it shipped with (F10, Alt-letter, click), with no extra chord and no menuBarVisibility. |
| [SCROLLX-UPSTREAM](#scrollx-upstream) | Do you want to propose, or back, a scroll-delta-and-phase mouse mode upstream with kitty, or skip it? | Skip for now, and join kitty's effort when it starts; SCROLLX found joining cheaper than leading. A one-comment +1 is fine if you want to signal interest. | Nothing is filed. Scroll velocity stays (0, 0), and .decelerating is never produced. |
| [B-HELP-2](#b-help-2) | Should '?' pressed when the focused control has no help show every help panel on screen, with '?' again hiding them, as the keyboard route to the help on views that can't take focus? | '?' reveals all. It closes the mouse-only gap that your 10-12 ruling and the no-mouse-only rule both point at, using the help key users already know. | Non-focusable help stays keyboard-reachable only where the app turns on .tooltips(.always), and '?' with no help on the focused control does nothing. |
| [A42-Q8](#a42-q8) | In the rich-text TextEditor (A42), should bold, italic and underline be reached only through the context menu (Shift-F10 or right-click), with key chords coming only when an app declares SwiftUI's TextFormattingCommands in the O13 menu bar? Or should the editor have default chords of its own? | Menu now, chords through TextFormattingCommands. That is how SwiftUI adds the shortcuts, it costs nothing extra, and it keeps the Emacs keys you called a bonus. | The A42 lane ships the Shift-F10 and right-click menu with no chords, and the question stays recorded as an A entry. |
| [B-PASTE-1-EDITOR](#b-paste-1-editor) | Should TextEditor and TextField be redesigned for large text: undo that records edits instead of whole-text copies, and possibly UTF-8 storage? If so, should it be folded into A42's storage refactor once the 16 MiB paste has been measured? | Measure first, then do undo-as-edits inside R1: it is the big, cheap win. Take on the UTF-8 storage redesign only if the measurement shows a 16 MiB document is unusable. | Nothing changes. Large texts keep the memory costs above, and R1 keeps whole-text undo. |
| [B-D4X-7-17](#b-d4x-7-17) | With text selection enabled on a Table, should a selection stay inside one cell, as macOS keeps it, or keep TUIkit's row-wide selection that crosses columns? | Fix the leak whatever else you decide: a modifier reaching past its own view is a bug, and it breaks row clicks. For table-wide scopes, keep crossing columns (option 1). TUIkit's screen selection already crosses from one Text to the next everywhere else (deviation T6), and exact per-Text selection is on hold. | Table-wide selections keep crossing columns, as T6 records. The leak should still be fixed as a bug, since that needs no ruling. |
| [D4X-LOCALITY](#d4x-locality) | Should TUIkit get copies through the session keepers it currently gives up on: GNU screen's wrapper sequence, tmux's wrapper sequence when allow-passthrough is on, and asking a keeper which clients are attached? | Screen passthrough first, checked with the probe, because screen copies nothing anywhere today. tmux passthrough next. Client queries only if someone asks. | Copies under screen, and over ssh under default-configured tmux, keep reporting 'Not copied'. Nothing breaks. |
| [B85-KEYBOARD](#b85-keyboard) | Should links inside a Text (from Markdown or an attributed string) become focusable controls: Tab stops, Return or a click to show or copy the link, and Shift-F10 for the link menu? | Full control, after B85-LINKDISPLAY. It completes your 'menu on every hyperlink' request for the links that still have none. | Links inside a Text stay hyperlinked labels only, and Apple Terminal users can't reach their destinations. |
| [B86](#b86) | Should TUIkit's Markdown parse close its two known differences from Foundation's: all 2,125 HTML named entities, and link reference definitions? | Leave both until a translation needs them, as the decision doc says. If you want the parse identical, do reference definitions first, since they cost no bytes. | Both differences stay, recorded in T3. |
| [B51-LIVE](#b51-live) | Should the APIs that take a Text only for its string keep a live Text (a timer, a relative date) updating, as SwiftUI does? These are navigationTitle(Text), help(Text), dismissalConfirmationDialog's title, and the titles still kept as strings. | Leave it until an app asks; none has. Meanwhile, check that B87's controls really are live now. | Live titles in these places stay at their value from when they were built, until the view around them is rebuilt. |
| [DEPR-CATCHALL](#depr-catchall) | For `Text("… \(anything)")`, should TUIkit keep its silent catch-all interpolation? Or add typed overloads and then mark the catch-all deprecated, as SwiftUI does on the 26 SDK? Or add typed overloads and then remove it? | (b). It matches SwiftUI on the current SDK, warning included, and the typed overloads are needed either way. | The catch-all stays live and silent: an exception to [21] that nobody has approved. |
| [A-TEXT2-1](#a-text2-1) | A drag begun inside a bordered container now stays inside it (#10). Should a mouse gesture from inside widen it to the pane, beyond starting the drag on the border? | Option 1: the border is the handle, and `.textSelectionScope(.pane)` restores the old reach for a whole app. | Only a drag begun on the border or outside the box reaches the page. |
| [A27](#a27) | For Wave 16's leftovers, do you take the recommended set (decline the six transforms, ship mask(alignment:_:) at cell coverage, ship drawingGroup as compositingGroup)? And should linear-light blending be added so that drawingGroup(colorMode: .linear) is honoured rather than ignored? | Option 2. Declining the transforms keeps rule 2 (nothing is silently ignored), mask and drawingGroup have honest cell readings, and linear blending is cheap and makes drawingGroup's colorMode honoured instead of documented as ignored. | All eight stay as gaps that fail to compile, A39 keeps waiting, and blending stays in encoded sRGB only. |
| [A34](#a34) | Should BlurReplaceTransition ship as a scale plus a fade (the blur drawn as a fade), stay out, or also get a cell 'blur' made of shade blocks? | Option 2. At cell resolution a blurred view reads as a faded one, so the gap closes for about an hour of work. | It stays out, and .blurReplace in ported code fails to compile. |
| [B61](#b61) | Should the content-transition dissolve move into Text and Image, with each reading \.contentTransition as SwiftUI's leaf views do, built as the first piece of A40's cheaper-design study? | Option 2, landed if the A/B on text-heavy scenarios (textwall, fanout, menus) is within a few percent. It adds SwiftUI's leaf semantics, and A40's study needs it as a base. | The subtree dissolve stays. |
| [B95](#b95) | On terminals that draw no pictures, should gradient views use the upper half block (▀) to show two colour samples per cell, doubling vertical resolution? | Option 1. The gain shows on few terminals, Apple Terminal would show bands, and the copied text gets worse. Skip the slope-cap probe: it can move a colour by under one level. | Gradients stay at one sample a cell, and the slope cap stays as the box reading. |
| [O5-FROSTED](#o5-frosted) | Now that the redone demo shows the tint-only materials, is the frosted add-on worth about two days? It would drop the glyphs beneath a material and average the neighbouring colours. | Option c first: it cheaply removes what makes text on a material hard to read. Option b only if the flat look disappoints. This is your taste call. | Materials stay tint-only, and so does glass, which shipped on them with a rim (lane GLASS). |
| [O1-LOOSEN](#o1-loosen) | Should the host's Reduce Motion also count when only the environment says the session is local (isLocal() \|\| isLikelyLocal()), relaxing your 'certain' standard? | Option b. A wrong 'local' can only add reduced motion, usually for the same person, while a wrong 'not local' withholds it from someone who asked for it. | The current rule stays: the host setting counts only with positive evidence that the session is local. |
| [P5](#p5) | Should reduce transparency, differentiate without colour and increase contrast be read as reduce motion is (host setting in local sessions only, each with a TUIKIT_* override), and should TUIkit's own drawing honour them? | Option c. Design TUIkit's own non-colour focus and selection cues for differentiate-without-colour separately, after you have seen them, because they touch your focus-colour rules. | Only reduce motion is read, and the other values stay refused. |
| [WL-Q3](#wl-q3) | Do you accept the cost that animatable .padding and .frame add to the deep-nesting scenario (+7.5% when last measured in August), or should the search for a fix continue? | Option b, then a. | The cost stays, recorded in the work log as provisionally accepted. |
| [NAMED-COLOURS-DARK](#named-colours-dark) | Should Color.red, .blue and the other named colours take Apple's dark values under a dark colour scheme, resolved where they are drawn, reversing the 09-15 'light values for now'? | Option a. The terminal gives no reason to deviate, and answering the light value in a body keeps what the 09-15 decision protected. | Named colours stay at the light values on dark pages, listed as slated to change. |
| [B-D6M-1](#b-d6m-1) | Should a named colour from an asset catalogue choose its light or dark variant where it is drawn, not when it is made? That needs either a colour table reachable without the environment, or a bigger Color. | Option 1 for now. Revisit it together with A16's benchmark and NAMED-COLOURS-DARK. | The variant stays chosen when the colour is made. |

## Project, process and infrastructure

### A-TS-1

**Swift 6.4: since the per-module test split, test rebuilds after edits to low modules are 11-23% slower.** Do you accept that, on Swift 6.4, test rebuilds after an edit to TUIkitFoundation or a module below it are 11-23% slower since the per-module test split, or should I measure merging the five smallest test targets into the integration target?

Since 9df2c1c1a the suite has one test target per module. Under 6.4's swift-build, an edit to a feature module now rebuilds its tests 41-62% faster (Menus 87-92 → 33-35 s). An edit lower down is slower: TUIkitView 109-113 → 133-141 s, TUIkitFoundation 119-121 → 130-137 s. On Xcode's 6.2.4, the gate compiler, a TUIkitFoundation edit got faster (79-87 → 69-75 s). The 10-15 investigation you asked for found two causes: swift-build compiles test targets one after another, and an edit to a private declaration still cascades to dependent targets. Reports for you to file were written (QUEUE.md:622). Since 10-10, 425 of the 604 commits that touched Sources touched TUIkitFoundation or a module below it (git log at 01d6da6a9), so the slower case is the common one. TS.md:93-106 does not yet record the investigation.

- **1. Keep it as it is.** Leave the split unchanged. *Price:* No effort. On 6.4, low-module edits cost 11-28 s more per test rebuild and feature-module edits save 35-60 s.
- **2. Experiment: merge the smallest targets.** Merge the Forms (6 files), CurveEditors (2), AppKit (4), Grid (8) and Search (12) test targets into TUIkitIntegrationTests, then time it on a quiet machine. Nothing lands without your word. *Price:* About half a day plus a timing run. Test products drop from 28 to 23 (lane O13 added a 28th target, TUIkitCommandsTests, 5 files, 6d627ee4e). Edits to those five modules would then rebuild the integration tests.
- **3. Wait for an upstream fix.** You file the swift-build reports, and we wait for a toolchain with the fix. *Price:* No effort here. Rebuilds stay slow until that toolchain ships.

**Recommended:** Run option 2 as the experiment you already allowed, and keep the split meanwhile. If the merge recovers most of the low-module loss without slowing those five modules' own edits much, land it with your OK. Either way, record the investigation in TS.md.

**If you don't answer:** The split stays as it is, and on 6.4 most edits (those to low modules) rebuild tests 11-23% slower. TS.md still needs the investigation written up.

<sub>Sources: Documentation/SwiftUI parity/Decisions/Compile time and binary size/Test targets split by module (TS).md:26-42, :93-106; Documentation/Working notes/plan/MORNING-QUESTIONS-1015.md:36-41; Documentation/Working notes/plan/QUEUE.md:604, :621-622; memory/optimize-for-swift-6-4.md; git log --since=2026-10-10 -- Sources (425 of 604 commits touch TUIkitFoundation or below)</sub>

### B-BNDL-1

**Running without the resource bundle: English compiled in, and the version reading 'unknown' (B-BNDL-1, B-BNDL-2).** Should TUIkit keep its English both compiled in and in the bundle, and keep the version reading 'unknown' when there is no bundle, or change either?

Since e5445e2cd, a TUIkit app runs without its resource bundle instead of trapping at launch. TUIkit's English is a pasted copy of en.json compiled into the binary (Sources/TUIkitStrings/Localization/LocalizationService+BuiltInEnglish.swift). en.json was 5,462 B when this landed and is 6,748 B today, after 11 commits that each added keys to both copies (the last three are lane O13's menu-bar keys: 0e019632f, 86994e4f2, 07b51a846). BuiltInEnglishTests fails, naming the keys, until the copy matches the file. Without the bundle, `tuiKitVersion` reads "unknown". One behaviour changed: a binary copied out of .build no longer reads the bundle left there. It used to, but only on the machine that built it; now it reads English and 'unknown' everywhere. This was flagged on 10-10 with no reply. (Option (a)'s price is about 6.7 KB in the binary plus the bundle's file, and option (b)'s saving about 6.7 KB, not 5.5 KB.)

- **(a) Keep as shipped.** Two copies of English: compiled in, and in the bundle. A translator adds an English key to en.json and pastes the file into the Swift file; the test fails until they do. *Price:* Nothing. An app that has the bundle carries both copies (5.5 KB in the binary, plus the bundle's file).
- **(b) One English: drop en.json from the bundle.** The compiled-in table becomes the only English. *Price:* Small effort. The bundle is 5.5 KB lighter and the binary is unchanged. Translators edit the Swift file for English instead of JSON.
- **(c) Generate the Swift file from en.json.** A script under Tools/ writes the compiled-in copy, so nobody pastes it. *Price:* Small effort. One more tool, and a step to run when adding a key; the test still catches a forgotten run.
- **(d) Compile the version in too (B-BNDL-2).** `tuiKitVersion` stops reading 'unknown' without the bundle. *Price:* A second place to update at every release, or another generator. It only matters where an app prints TUIkit's version.

**Recommended:** (a). The test already catches a stale copy, and neither the byte cost nor the 'unknown' version matters enough to change how translators work or how releases are made.

**If you don't answer:** The shipped behaviour stands, which is fine.

*(Corrected in the evening re-check.)*

<sub>Sources: Documentation/SwiftUI parity/Decisions/Compile time and binary size/Running without the resource bundle (BNDL).md:18-51, :86-97; Documentation/Working notes/plan/QUEUE.md:94; Documentation/Working notes/CENSUS/census.md (B-BNDL-1..4 row)</sub>

### B-D6M-2

**A separate package for the macros, so TUIkit-only clients never resolve swift-syntax.** Should the @Animatable and @Entry macros move into a separate package, in a second repository, so apps that don't use them never resolve swift-syntax?

Package.swift:172 takes swift-syntax "602.0.0"..<"700.0.0" for the opt-in TUIkitMacros product. SwiftPM resolves dependencies by package, so every TUIkit client clones swift-syntax, though it compiles none of it unless it uses the macros. The wide range avoids version conflicts: a 602..<603 cap failed to resolve beside a package needing 603 (measured). SwiftPM cannot take a package from a subfolder of a remote repository, so separating the macros means a second repository. TUIkitMacros depends on TUIkitCore (Package.swift:585).

- **(a) Keep as is.** One package, with the wide range. *Price:* Nothing. Every client's first resolve clones swift-syntax; nothing is built for non-users.
- **(b) A second repository for TUIkitMacros.** The macros move to their own package, which depends on TUIkit for TUIkitCore. Macro users add a second dependency. *Price:* Medium effort to set up, then a second package to version and tag with every release. With @Entry in the product, the second dependency also falls on any app that declares a custom environment, transaction, container or focused value the one-line way. TUIkit-only clients never resolve swift-syntax.
- **(c) Try a package trait first.** Make swift-syntax conditional on an opt-in trait, as Package.swift already does for DeadStripUnusedAPI and UnexportTUIkitSymbols. *Price:* Small effort if it works. Whether SwiftPM then skips resolving swift-syntax is unmeasured, so measure before choosing. Macro users would enable the trait.

**Recommended:** (a) for now, and measure (c) cheaply. Take (b) only if users complain about resolution time or conflicts, because two packages are an ongoing release cost.

**If you don't answer:** Things stay as they are: every client resolves swift-syntax and only macro users compile it.

<sub>Sources: Documentation/SwiftUI parity/Decisions/Named colours, localisation lookup and the swift-syntax range (D6M).md:53-88; Package.swift:135-172, :583-590</sub>

### B-DYNVFIX-3

**A sheet's dismiss called through a shared object closes the page instead of the sheet (closures read the primary holder's environment).** When several views hold one class object, closures made in any of them read the first holder's environment. Do you accept that limit, want the cheap 'focused holder becomes primary' fix prototyped, or want the full per-dispatch fix built?

Since DYNVCLAIM (landed 2026-10-13), an object shared by several views reads each holder's environment while that holder draws. Closures that run later (button actions, tasks, timers) read the 'primary' holder's environment: the first view drawn holding the object. So a sheet sharing its page's object and calling the object's `dismiss` acts for the page, and the sheet stays open (DYNVFIX.md:291-296; Deliberate deviations, S6). SwiftUI installs nothing inside a class, so its @Environment there just reads the default. This is TUIkit's own extension, which your 10-12 ruling kept. The other limits listed at DYNVFIX.md:288-345 are rarer.

- **(a) Accept and document.** Keep today's behaviour. The documented workaround is to read `dismiss` in the view, or hold it in a struct property. *Price:* Nothing.
- **(b) Prototype the cheap candidate.** At the end of each pass, make the primary the holder whose subtree holds the focus. That fixes the sheet case, because the sheet holds the focus. *Price:* Small-to-medium effort plus an A/B; the cost is unmeasured. Closures run from timers still read whichever holder is primary.
- **(c) Dispatching identity.** Set a 'current holder' around every key, mouse, gesture and task dispatch, and keep an environment per holder in each object. *Price:* Large effort, and a branch on every @Environment read in every app. Still wrong for timers and detached tasks.

**Recommended:** (b), landing it only if the A/B is flat. Decline (c).

**If you don't answer:** The limit stays documented, and a sheet that shares its page's object needs the workaround.

<sub>Sources: Documentation/SwiftUI parity/Decisions/State and dynamic properties/Finding dynamic properties from declared types (DYNVFIX).md:146-383; Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md:507-540, :1850; Documentation/Working notes/plan/QUEUE.md:455, :477; memory/owner-decisions-2026-10-12.md [8]</sub>

### B-REVIEW

**Your review or veto of the shipped-safe-option (B) and declined (C) entries.** Do you want to review the B entries (safe option shipped) and C entries (declined) in the decisions files, read a one-page digest of the ones that change behaviour, or let them all stand?

Counted today: 277 B and 19 C headings in 73 per-lane decisions files under Documentation/SwiftUI parity/Decisions/ (heading grep at 01d6da6a9). That includes the 64 B and 5 C entries the 10-18 lanes added: FB16 (B-FB16-1..13), O6 (B-O6-1..3), W1 (B-W1-1..14, C-W1-1..2), O13 (B-O13-1..8, C-O13-1..3), O4 (B-O4-1..7), GLASS (B-GLASS-1..7), PARITYMISC (B-PARITYMISC-1..5), APPSTATE (B-APPSTATE-1..4) and INPUT (B-INPUT-1..3). The census on 10-11 counted 161 and 9. In the main decisions doc, B38, B54-B58, B60-B95 and C1-C15 haven't been reviewed since 10-04. All of them shipped, nothing blocks on them, and every entry that asks something or owes work has been pulled out as a separate item.

- **(a) Full review.** Read every B and C entry. *Price:* Several hours of your reading.
- **(b) One-page digest.** I list, one line each, only the B and C entries that change user-visible behaviour or differ from SwiftUI, for a 10-minute veto pass. *Price:* A small effort for me; one page for you.
- **(c) Let them stand.** Veto any of them when you come across it. *Price:* Nothing.

**Recommended:** (b).

**If you don't answer:** They all stand as shipped.

*(Corrected in the evening re-check.)*

<sub>Sources: Documentation/Working notes/CENSUS/census.md:22, :67; Documentation/SwiftUI parity/Decisions/ (heading count at 01d6da6a9: 277 B-*, 19 C-* in 73 files)</sub>

### B-SIZEDOCS-1

**Commit the remaining SwiftUI probes that only decision documents cite.** Should I commit the remaining SwiftUI probes that only decision documents cite (about 438 KB of sources, text outputs and notes, without the pixel dumps) and point their citations at the committed copies?

On 10-12 you approved committing the probes that the code cites (~233 KB, "substantial but worth it"). SIZEDOCS also committed two more sets (57 KB) into Tools/SwiftUIProbes/. The rest are still only in the git-ignored working notes: waves 6b, 8a, 8b, 10 and 11a; lanes 17, 17d, 17g and 17m; D5G; DECB; since 10-18, W1's shape probes (`W1/probe`) and FB16's insertion/removal probe (`plan/fb16`, 36 KB); and, since the 10-18 evening, PARITYMISC's probes (`PARITYMISC/probes`: b87, locale, binding_anyhashable; 3.7 MB on disk with built binaries), INPUT's undo probes (`INPUT/probes`: undo, undo2, undo3, about 14 KB of source plus binaries) and O13's menu probe (`O13/probe/menus.swift`, 7 KB). O4's and APPSTATE's were committed into Tools/SwiftUIProbes/ (053870c38, ed0185a8e). Committed docs cite them, for example the main decisions doc at :174, :534, :1515 and :1615, Deliberate deviations at :143, :548, :604, :1426, :1528 and :1778, Shapes (W1).md:5-6, Insertion and removal model (FB16).md:4, Small parity items (PARITYMISC).md:107, The menu bar (O13).md:19 and Kitty keyboard protocol, key-press phases and UndoManager (D1K).md:220. O13's and INPUT's probes are cited by code (e.g. Sources/TUIkitCommands/Commands/CommandGroup.swift:26 and 8 other files; Sources/TUIkitFoundation/Focus/TextUndoBridge.swift:124 and TextUndoCoalescingTests.swift:6), so your 10-12 approval already covers committing them, whatever the answer here. To anyone without this machine those citations point nowhere, and the working notes are not backed up. (Option (a)'s 438 KB / 189 files grows by the two new sets, leaving out W1's two built binaries, and by the PARITYMISC and INPUT sources, unmeasured without their binaries.)

- **(a) Commit them without the pixel dumps.** Sources, text outputs and notes go into Tools/SwiftUIProbes/, and their citations are repointed: 41 lines in Documentation, Sources and Tests on 2026-10-19 (22 when SIZEDOCS counted), about half of them O13's and FB16's probes, which code cites. *Price:* 438,206 B in 189 files (measured) in every clone. Small effort.
- **(b) Also the pixel dumps and renders.** Add lanes 17m's and 8b's images as well. *Price:* 5.48 MB in every clone.
- **(c) Probe sources only.** Commit the .swift files and drop the outputs. *Price:* Smaller (size unmeasured). The measured outputs are lost, and re-measuring needs a Mac with the matching SDK.
- **(d) Leave them.** No change. *Price:* Nothing now, but the citations stay machine-local, and pruning the notes would lose the evidence.

**Recommended:** (a). It is the same kind of material you approved, at about twice the size. The pixel dumps are large and reproducible, which your 10-12 rule keeps out of git.

**If you don't answer:** The citations stay machine-local, and the evidence is at risk if the notes are pruned or the disk fails.

*(Corrected in the evening re-check.)*

<sub>Sources: Documentation/SwiftUI parity/Decisions/Compile time and binary size/Binary-size study and SwiftUI probes in the repository (SIZEDOCS).md:19-57; Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md:174, :534, :1515, :1615; Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md:143, :548, :604, :1426, :1528, :1778; memory/owner-decisions-2026-10-12.md (docs: large/reproducible data never committed)</sub>

### BINARY-DISTRIBUTION

**A binary distribution (e.g. an xcframework).** Do you want TUIkit offered as a prebuilt binary, for example an xcframework, or only as source through SwiftPM?

This was asked in the SIZE3 report (§5 Q7) and never answered. A binary distribution needs library evolution (the compiler mode for binary-stable libraries). Today that mode crashes the compiler on TUIkitCore: a 7-line repro, on 6.2.4, 6.3.3 and 6.4.0 (SIZE3/q/crash-evolution). Past the crash, TUIkitFoundation has 7 ordinary source errors under that mode (SIZE3/answers.md:39). SIZE3's advice listed library evolution under 'Don't'. If the answer is no, the size levers that act on the built libraries before linking (report §3.1) only shrink build directories and CI disk, and can be dropped.

- **(a) No: source only, through SwiftPM.** Record the decision, and drop the library-side size levers for good. *Price:* Nothing.
- **(b) Yes.** You file the compiler crash. I fix the 7 source errors. Then we wait for a toolchain with the fix and design binary products. *Price:* Large and open-ended. Library evolution routes access to non-@frozen types through a slower indirect path across module boundaries, and limits the cross-module @inlinable/@frozen tuning done since 10-07. xcframeworks serve Apple platforms only.
- **(c) Not now, revisit later.** No decision. *Price:* Nothing now, but the library-side levers stay in limbo.

**Recommended:** (a).

**If you don't answer:** In effect (c): nothing is built, and the library-side levers stay unpursued.

<sub>Sources: Documentation/Working notes/SIZE3/report.md:648-684 (§5 Q7); Documentation/Working notes/SIZE3/answers.md:33-41, :281; Documentation/Historical/Binary size study (2026-10-10)/Where the bytes go in a release build.md</sub>

### DOCS-HOSTING

**Host the unified DocC reference, or commit the 'which module provides it' index.** Should the unified DocC reference (with its 'which module provides it' index) be published on GitHub Pages, should the index be committed as a file, or should it stay reachable only locally?

Since the per-module products landed (C9b), users have to know which module declares a symbol. Tools/BuildDocs/which_module.py generates that index (1,904 names) only into the reference that build-docs.sh builds. CI's docs job builds the publishable form (ci.yml:1430, --static-hosting) but publishes nothing. Users are pointed at the Swift Package Index (SPI), which builds one reference per module (.spi.yml) and shows only a placeholder on the index page. The README and the user guide mention the index but link no hosted copy, so today only `build-docs.sh --preview` shows it.

- **(a) Publish on GitHub Pages.** The docs job publishes what it already builds. README, the project template and .spi.yml (`external_links: documentation:`) point at it. *Price:* Small effort to write the publish step, plus you switching Pages on in the repository settings. It makes a second documentation site beside SPI's, or SPI links through to it.
- **(b) Commit the index.** Commit it as, say, Documentation/Module index.md, with a freshness check in CI. *Price:* Every commit that adds or moves public API must regenerate it, which needs a build. Parallel lanes would conflict on the file at every cherry-pick.
- **(c) Leave it.** Only a local --preview shows the index. *Price:* Nothing.

**Recommended:** (a). The docs job already builds the publishable form; only the publish step and your settings switch are missing.

**If you don't answer:** The index stays local-only, and readers use SPI's per-module pages.

<sub>Sources: Documentation/SwiftUI parity/Decisions/Module split/Library products for every module (C9B).md:20-40; Documentation/SwiftUI parity/Decisions/Module split/Step B1, TUIkitFoundation and the umbrella (SPB1).md:49-88; .spi.yml; .github/workflows/ci.yml:1406-1430</sub>

### DORMANT-DESIGNS

**Dormant design documents in live folders: adopt their open parts, or retire them to Historical.** For four dormant design documents (layout constraints, locating things without drawing them, configurable focus indication, actor isolation), should I retire them to Historical with entries in Future options, or schedule their open parts?

Your 10-12 ruling: keep docs current, and move them to Historical as soon as they're eligible.
(1) Layout constraint system.md: its SwiftUI parts (aspectRatio, containerRelativeFrame, layoutPriority) have shipped. Your 10-15 frames ruling kept FrameDimension, matching SwiftUI, which supersedes the document's proposed FrameSize type. Its TUI-only .weighted, .constraint(...) and .debugLayout() are unbuilt.
(2) Locating things without drawing them.md: Stage 2 (the locate visitor and reveal generation) and Stage 5's hoist are outstanding, and §13's Q2, Q3 and Q5-Q7 are open. Meanwhile .scrollPosition and ScrollViewReader shipped by other routes.
(3) Configurable focus indication.md: the API is undecided. The document recommends shipping nothing unless it's wanted, and otherwise only .automatic/.marker/.none.
(4) Actor isolation and the input-reader loop.md: its options 1-4 are open, and it recommends the status quo (option 1) until something forces the question. So the view-render benchmarks stay skipped (Benchmarks/TUIkitBenchmarks/LayoutBenchmarks.swift:25).

- **(a) Retire all four.** Move each to Historical with a closing note, and add its 'what would reopen it' to Future options.md. *Price:* Small effort, docs only. The TUI-only layout modifiers and the focus-indication API are then not planned.
- **(b) Retire (3) and (4); schedule parts of (1) and/or (2).** Build (1)'s TUI-only modifiers, or (2)'s Stage 2. *Price:* Medium-to-large effort each, adding new public API or changing behaviour.
- **(c) Leave them.** They stay in live folders. *Price:* Nothing, but they keep reading as pending plans, against the 10-12 ruling.

**Recommended:** (a). (3) and (4) already recommend doing nothing until something forces it; (1)'s SwiftUI half has shipped and its FrameSize idea conflicts with your frames ruling; (2)'s user-visible goals shipped by other routes. Decide OOB-STYLING at the same time.

**If you don't answer:** The four stay in live folders as stale plans.

<sub>Sources: Documentation/Layout and scrolling/Layout constraint system.md:3, :80-100; Documentation/Layout and scrolling/Locating things without drawing them.md:6-10, :1352-1357, :1475-1515; Documentation/Input and focus/Configurable focus indication.md:3-5, :140-175; Documentation/Input and focus/Actor isolation and the input-reader loop.md:3-9, :236-262; Documentation/Performance/Benchmark coverage and deferred MainActor benchmarks.md:1-30; memory/owner-decisions-2026-10-12.md (docs ruling; 10-15 frames); Documentation/Working notes/CENSUS/census.md:79</sub>

### MACOS27-PARITY

**Which SwiftUI SDK parity targets: move the baseline to macOS 27 (Xcode 27)?.** When the work moves to a macOS 27 machine, should the SwiftUI parity baseline move to the newest SDK, counting its new APIs as gaps and removing what it deprecates, or stay on the macOS 26 SDK?

The parity baseline is the 6.3.3 / macOS 26.2 SDK. This Mac runs macOS 15.8 and can't run Xcode 26.4 or later, so newer SDKs can't be read here. Ruling [21] (10-12) said not to implement deprecated SwiftUI API and to audit what exists, and left macOS 27 parity undecided. On 10-18 you deferred the three task(name:…) overloads, which need Xcode 26.4+, to 'when the work moves to macOS 27' (completion plan row 14). From Apple's docs, DEPR found 4 TUIkit declarations deprecated in the 27 cycle: the rounded- and square-border text-field styles. TASK-NAME and DEPR-MACOS27 wait on this answer.

- **(a) Move to the newest SDK when a macOS 27 machine can run the tools.** Re-extract SwiftUI's API from that SDK. New APIs become gaps, and what it deprecates is removed from TUIkit. *Price:* No work until then; after that, effort scales with 27's changes (unknown). Removals change TUIkit's public API (pre-1.0, so no shims).
- **(b) Stay on 26.** Keep the current baseline. *Price:* No work. TUIkit lags SwiftUI's current API, which contradicts the 10-18 task(name:) deferral.
- **(c) Read 27's API on CI's Xcode 27 lane now.** A CI step extracts SwiftUI's symbol graph from the Xcode 27 SDK. *Price:* A small CI job, and it needs a push (PUSH). Gives the data earlier.

**Recommended:** (a). It's what your 10-18 task(name:) ruling implies and what the parity rule asks for, and it needs nothing until the machine moves.

**If you don't answer:** Parity stays on the 26 SDK, and TASK-NAME and DEPR-MACOS27 stay blocked.

<sub>Sources: memory/owner-decisions-2026-10-12.md [21]; Documentation/SwiftUI parity/SwiftUI API completion plan.md:147; Documentation/Working notes/DEPR/notes.md; Documentation/Working notes/plan/DAY-REPORT-1018.md:15-16; .github/workflows/ci.yml:343</sub>

### OOB-STYLING

**Out-of-band styling surface: schedule its gating spike, or retire it.** Should I schedule the spike that decides the out-of-band styling design (each row stored as plain text, with styles in a separate list of runs), or retire the design to Historical?

Documentation/Colour and styling/Out-of-band styling surface.md (730 lines) has been 'proposed (design panel recommendation, 2026-07-20)' ever since. It is provisional on a spike clearing its §7 thresholds, and the spike never ran. It would move styling out of FrameBuffer's ANSI-coded strings into a separate list of style runs per row, addressed by cell. Today FrameBuffer still stores ANSI-coded line strings (Sources/TUIkitCore/Rendering/FrameBuffer.swift:26). The ANSI clipping and measuring code has since been made byte-wise and faster (memory ansi-clip-byte-paths), and the 10-16 perf pass's fixes were all elsewhere. Nobody ever deferred it; the census asked, with no answer.

- **(a) Run the spike.** Prototype and measure against §7's thresholds; adopt only if they clear. *Price:* Days for the spike. If it clears, a very large migration: every buffer operation, the overlay and hit-test threading, and snapshot tests rekeyed (the §9 risks).
- **(b) Retire to Historical.** Move it with a closing note, plus a Future options entry saying what would reopen it: a profile where ANSI string handling dominates, or a feature needing per-cell style access. *Price:* Small effort, docs only.

**Recommended:** (b), decided together with DORMANT-DESIGNS.

**If you don't answer:** It stays 'proposed' in a live folder.

<sub>Sources: Documentation/Colour and styling/Out-of-band styling surface.md:3, :679-720; Documentation/Working notes/CENSUS/census.md:79; memory/ansi-clip-byte-paths.md; memory/perf-pass-2026-10-16.md</sub>

### PACKAGE-RESOLVED

**The committed Package.resolved is stale: commit a fresh one, or stop tracking it.** Should Package.resolved be committed fresh once, as an exception to your 'never commit it' rule, or removed from git and ignored?

The committed Package.resolved (last changed in 9af0e1221, June) pins swift-collections 1.5.1, which Package.swift no longer uses, and lacks swift-syntax (Package.swift:172). Every checkout carries a local modification. Main's working copy now drops swift-collections and pins swift-syntax 604.0.0 (git diff, measured). You told the agents never to commit the file (BRIEF-1018.md), and the 10-11 question about an exception has had no answer. SwiftPM ignores a dependency's Package.resolved, so only TUIkit's own builds and CI read it.

- **(a) Commit the fresh file once.** Commit main's current working copy. *Price:* Small effort. TUIkit's own builds pin swift-syntax 604.0.0 (CI's Linux 6.2 lane already pins 602.0.0 explicitly). It goes stale again when a dependency moves, and benchmark runs keep rewriting it.
- **(b) Stop tracking it.** `git rm --cached Package.resolved` and add it to .gitignore, as libraries often do. *Price:* Small effort. Contributors and CI resolve the newest versions in range, which is what happens today anyway. Agents can no longer sweep it into a commit by mistake.
- **(c) Leave it.** No change. *Price:* Nothing, but every worktree shows it modified, and lanes must keep skipping it.

**Recommended:** (b). It matches your never-commit rule permanently and ends the noise. (a) is the census's earlier suggestion if you'd rather keep pins.

**If you don't answer:** The stale file stays committed, and every worktree carries a local modification that agents must skip.

<sub>Sources: Documentation/Working notes/answers-2026-10-11.md:360-361; Documentation/Working notes/CENSUS/census.md:112 (D-19); Documentation/Working notes/plan/BRIEF-1018.md (commit rules); git diff Package.resolved; git log -- Package.resolved; memory/build-profiling-env-constraints.md</sub>

### SDK15-CI

**A CI lane for swift.org 6.2 with the macOS 15.5 SDK.** Should CI build TUIkit with a swift.org 6.2 toolchain against the macOS 15.5 SDK, which is what a swiftly user on macOS 15 with the default Command Line Tools gets?

All of CI's macOS lanes use Xcode 26's SDK (ci.yml:277-343). The 15.5 SDK carries Swift 6.1's standard library and Observation under a 6.2 compiler. 1f49c77e9 and f4c5ff5e3 added guards around InlineArray, task names and UndoManager so that TUIkit's own modules build there (CONTRIBUTING.md:221-231). The Example/Stress @Observable failure reported on 10-16 didn't reproduce from a clean build (EVENING-REPORT-1016.md:56). Nothing in CI catches a regression on that SDK. Separately, CONTRIBUTING.md still says the apps fail there; that correction is owed whatever you decide (CONTRIB-MACOS15).

- **(a) A library-only lane.** On a macos-15 runner, swiftly 6.2 with an Xcode 16 / 15.5 SDK selected. Whether the runner image has it needs confirming. *Price:* Small effort and one more macOS build per CI run. It also commits TUIkit to that SDK: each new use of InlineArray, Span or other 6.2 standard-library API needs a guard there, though CLAUDE.md encourages using them freely.
- **(b) No lane, best effort.** Keep the guards but don't test them. *Price:* Nothing. Support for that SDK will rot unnoticed.
- **(c) Declare the 15.5 SDK unsupported.** README/CONTRIBUTING say to use Xcode's SDK or Command Line Tools 26, and no more guards get added. *Price:* Docs only. Swiftly users on macOS 15 with the old tools get a build error, plus the documented fix.

**Recommended:** (a) if you want swiftly users on macOS 15 supported (your 10-07 point that users may not use Xcode); otherwise (c). I lean (a).

**If you don't answer:** In effect (b): it builds today and may silently stop.

<sub>Sources: Documentation/Working notes/plan/QUEUE.md:631, :644; Documentation/Working notes/plan/MORNING-QUESTIONS-1016.md:100-113; Documentation/Working notes/plan/EVENING-REPORT-1016.md:56; CONTRIBUTING.md:221-231; .github/workflows/ci.yml:277-343; memory/compile-time-and-binary-size-request.md (owner 10-07 on swiftly users)</sub>

### SINGLETON-CACHES

**Are the two process-wide caches exempt from 'No Singletons'?.** Do the two process-wide caches, URLImageCache.shared and the ASCII palette search-index store, count as singletons under CLAUDE.md's 'No Singletons' rule?

URLImageCache is declared at Sources/TUIkitImage/ImageLoader.swift:497 as `public static let shared = URLImageCache()`. It is public API, and every image loaded from a URL uses it (Sources/TUIkitBitmaps/Views/_ImageCore.swift:435 passes `.shared`), so an app or test can't hand views a different one. It has no eviction: its doc comment says entries persist for the lifetime of the application. The palette store is at Sources/TUIkitImage/ASCIIPalette+SearchIndex.swift:215, `nonisolated(unsafe) static var shared = Store()`. It is private, and a memo of a pure function of the palette's entries. The question was asked on 10-11 with no answer. Of the state singletons, AppState.shared is gone: lane APPSTATE gave each app its own (2026-10-18). LocalizationService.shared goes with draw-time lookup, and three more process-wide statics (the notification queue, the default store, the URL opener) are a question of their own; both are in the lanes section at the end (A-APPSTATE-1, A-APPSTATE-2).

- **(a) Exempt both as caches.** Add a sentence to CLAUDE.md's rule exempting caches that hold no app-visible state. *Price:* Docs only. URLImageCache stays unbounded and can't be replaced.
- **(b) Inject both.** URLImageCache travels through the environment, so an app or test can give views its own; the palette store travels through the render context. *Price:* Medium effort. It changes public API (pre-1.0, so no shims).
- **(c) Split them.** Exempt the palette store, which is a pure memo with nothing observable. Inject URLImageCache through the environment and give it a size bound. *Price:* Medium effort for the image cache, including a public API change.

**Recommended:** (c). The palette store is a memo whose contents nothing can observe. The image cache holds downloaded data the app sees, grows without limit, and can't be swapped for tests.

**If you don't answer:** Both stay as they are, and the rule's text and the code disagree.

<sub>Sources: Documentation/Working notes/answers-2026-10-11.md:357-359; Documentation/Working notes/CENSUS/census.md:100 (D-7); Sources/TUIkitImage/ImageLoader.swift:489-522; Sources/TUIkitImage/ASCIIPalette+SearchIndex.swift:195-215; Sources/TUIkitBitmaps/Views/_ImageCore.swift:435; .claude/CLAUDE.md (No Singletons)</sub>

### WINDOWS-PORT

**Windows: the console-layer port, and TUIkitView failing on Windows Swift 6.2.** Should the Windows port of the console layer (TUIkitApp's Windows code) be scheduled now, or should Windows stay 'easy to port later', with only the small CI bookkeeping done?

CLAUDE.md says Windows is a port in progress, with the goal of keeping it easy; it doesn't ask for the port now. CONTRIBUTING.md:125-215 lists five blockers, all in TUIkitApp/TUIkitTerminalHost: (1) waking on stdin through ReadConsoleInput, since libdispatch refuses console handles; (2) resize via WINDOW_BUFFER_SIZE_EVENT; (3) console raw mode and VT output; (4) a ConPTY smoke harness; (5) the Win32 clipboard and locality. TUIkitView fails to build on Windows with Swift 6.2, cause undiagnosed (CONTRIBUTING.md:139). TUIkitCommands (lane O13), built on TUIkitApp, has no Windows step either (CONTRIBUTING.md:159). The 17 modules carved since 10-08 are advisory on Windows until CI sees them green, and CI hasn't run since 10-01 (PUSH).

- **(a) Schedule the port.** Build the Windows code for all five blockers. *Price:* Very large: weeks of Win32 work that this Mac can only check through CI. A Windows machine or VM would help.
- **(b) Not now; do the bookkeeping.** After a push, make each Windows step that CI shows green binding, and diagnose the TUIkitView failure from the CI log. *Price:* Small effort, but it needs CI (PUSH) or a Windows machine.
- **(c) Drop Windows as a goal.** Docs only. *Price:* Frees the four lower modules from having to build on Windows.

**Recommended:** (b).

**If you don't answer:** Windows stays a goal, and even (b)'s bookkeeping can't happen until a push.

<sub>Sources: .claude/CLAUDE.md (Cross-platform); CONTRIBUTING.md:125-215; Documentation/Reviews/Upstream review/notes/PR 46, module tests.md:58-70</sub>

### TERMCAPS-API

**Terminal capabilities for apps (your item #9).** The draft is [Terminal capabilities for apps, a proposal (2026-10-23)](<Terminals/Terminal capabilities for apps, a proposal (2026-10-23).md>): a read-only, TUI-specific `\.terminalCapabilities` value answering, per `Feature`, what TUIkit already knows of the terminal (its host tables and the measured survey), so that a page can say "your terminal doesn't draw curly underlines" instead of showing nothing. Three questions:

- **Naming.** `terminalCapabilities` and `Feature`, or something shorter; and whether colour depth belongs here (a user can force it at run time) or stays `ColorDepth`.
- **Granularity.** One `patternedUnderline` (curly, dotted and dashed together), or one case per shape. Every terminal measured so far treats them as a group.
- **Scope.** Only what TUIkit measures, or also keys an app might want (the kitty protocol's modifier-only reports, which item #25's mnemonic underlines would use).

*Price:* About a day, including the Example's notes in seven languages. Additive.

**Recommended:** Build it as the proposal says, with the names as drafted, colour depth left as `ColorDepth`, one patterned-underline group, and only what TUIkit measures.

**If you don't answer:** Nothing is exposed.

<sub>Sources: Documentation/Terminals/Terminal capabilities for apps, a proposal (2026-10-23).md, "Open questions for the owner"</sub>

## Layout, scrolling and lists

### A-D6L-1

**Surface look for tables and lists: keep opt-in, make it the default, or fold it into .inset.** Should the `.surface` look (no border; rows on a lifted background) stay an opt-in style, become what `.automatic` draws for tables (and perhaps lists), or replace what `.inset` draws?

Lane D6L shipped `SurfaceTableStyle` / `SurfaceListStyle` on 2026-10-07 as an opt-in prototype. Your A29/A46 condition was to drop the border only if collections get a distinct background. You have since tuned it in the Example (FB4, FB5, E8, E10–E12 fixed its fills, header and stripes), but nobody has ruled on a default, and both declarations still call this "the owner's open question" (Sources/TUIkitTables/Styles/TableStyle.swift:180-183, Sources/TUIkitLists/Styles/ListStyle+Variants.swift:76). At 16 colours the surface rounds back to the page's own colour on 13 of 16 palettes, so a borderless default there needs a border fallback.

- **1. Keep opt-in (shipped).** `.automatic` stays bordered for tables and lists; `.surface` stays a TUIkit-only named style. *Price:* Free.
- **2. Surface look becomes the default (tables, lists or both).** `.automatic` draws the surface look; `.bordered` and `.inset` stay as named styles. The two border lines go to the rows, and click targets move a line up and a cell left. *Price:* About half a day, mostly re-baselining golden and render tests, plus about an hour for a 16-colour fallback that draws the border where the surface can't show.
- **3. Fold it into `.inset`.** `.inset` comes to mean 'no border, on a surface', and the separate `.surface` style is deleted. *Price:* Free apart from docs. Every app that names `.inset` changes look.
- **4. 3, then 2 for tables only (the lane's recommendation).** One borderless style, used by default where the border reads heaviest; lists keep the border unless the same test says otherwise. *Price:* Options 2 and 3 combined: about half a day plus the hour for the fallback.

**Recommended:** Option 4. You have already been using `.surface` in the Example, and the table border is the heaviest chrome. Decide lists together with A-D6L-2. It is a question of look, so it is yours.

**If you don't answer:** Tables and lists stay bordered by default, and `.surface` stays an opt-in style whose doc comments still call it a prototype that may be renamed or removed.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/Lists and tables/List and table stripes, surfaces, pinned headers and separators (D6L).md:12-65; /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md:1324-1340; /Users/robot/Documents/TUIkit/Sources/TUIkitTables/Styles/TableStyle.swift:168-193; /Users/robot/Documents/TUIkit/Sources/TUIkitLists/Styles/ListStyle+Variants.swift:76; /Users/robot/Documents/TUIkit-session-notes/plan/QUEUE.md:429; /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/owner-decisions-2026-10-04.md (A29/A46)</sub>

### A-D6L-2

**Should lists draw a separator under every row by default, as SwiftUI does?.** Should lists draw a separator line under every row by default, as SwiftUI's do on macOS, given that here each separator takes up a whole terminal line?

Separators shipped as a faint `─` rule on a line of its own (A47 option 2). Every built-in style resolves `.automatic` to hidden (Sources/TUIkitFoundation/Modifiers/ListSeparatorPreference.swift:31-33). SwiftUI draws a hairline under every row in `.automatic`, `.inset`, `.bordered` and `.plain`, but not in `.sidebar`. Here that doubles the height of a list of one-line rows: the Example's Lists styles demo shows 3 entries instead of 6. The Kitty-graphics hairline study found a 1–2 px line that takes no row feasible on Ghostty and iTerm2, estimated at about 5–6 days to prototype, and it names this default as waiting on it.

- **1. Off by default (shipped).** Lists keep their density; apps or rows opt in with `.listRowSeparator(.visible)`. *Price:* Free.
- **2. SwiftUI's default.** On under `.automatic`, `.inset`, `.bordered` and `.plain`; off under `.sidebar` and `.insetGrouped`. *Price:* Every list doubles in height, and row click targets and page distances grow with it. Most of a day re-baselining tests.
- **3. Inset family only, or multi-line rows only.** On for `.inset` and `.surface`, where no border separates the rows, or only for rows taller than one line, where a line costs proportionally less. *Price:* Partial test re-baselining. Tied to A-D6L-1.
- **4. Wait for the Kitty hairline.** Build the TUI-only `.hairline` separator look, then adopt SwiftUI's default wherever the host can draw a line that takes no row, and stay off elsewhere. *Price:* About 5–6 days for the prototype. Lists then look different from terminal to terminal.

**Recommended:** Keep option 1 for now. Revisit as option 4 when the hairline prototype is scheduled, since it removes the cost that makes option 2 bad. If you make the surface look a default (A-D6L-1), decide option 3 at the same time.

**If you don't answer:** Separators stay off unless an app, section or row asks for them. The Example's "Separators between rows" toggle remains the way to see them.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/Lists and tables/List and table stripes, surfaces, pinned headers and separators (D6L).md:67-104; /Users/robot/Documents/TUIkit/Documentation/Investigations/Thin lines between rows with Kitty graphics.md:1-30; /Users/robot/Documents/TUIkit/Sources/TUIkitFoundation/Modifiers/ListSeparatorPreference.swift:20-40; /Users/robot/Documents/TUIkit-session-notes/morning-questions.md:76-84</sub>

### B-D2S-6

**With a scroll target behaviour, the '▲/▼ N more' pair is drawn at every stop.** Under a scroll target behaviour such as `.paging`, should a `.text`-indicator scroll view keep its '▲ N more' / '▼ N more' lines drawn at every stop (shipped), or let them come and go and make every page two lines shorter?

Shipped (621c4a86e, refined in 1e55f80ef): when the content overflows, the pair is reserved at every offset, as `.visible` does. This lets pages sized with `containerRelativeFrame` land whole, and every line is read at some stop. The cost is the look at the very top, where '▲ 0 more lines above' takes the first line. Two reviews had pulled opposite ways on this before the current rule.

- **1. Pair always drawn (shipped).** Pages land whole between the two indicator lines at every stop. *Price:* Free. At the top, '▲ 0 more' takes up a line.
- **2. Hint comes and goes.** Keep `.automatic`'s behaviour of showing an indicator only when something is hidden that way, and size the container to the lines between the two indicators whatever is drawn. *Price:* About as small (hours). A page is two lines shorter even at the top, and the container's size depends on whether a behaviour is set, or every `.text` scroll view loses two lines.

**Recommended:** Option 1, unless the '▲ 0 more' line at the top bothers you on the Example's Scroll View page.

**If you don't answer:** The pair stays drawn at every stop under a scroll target behaviour.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/Scrolling/Scroll anchors, target behaviours and clipping (D2S).md:132-169</sub>

### S3-NO-EXTENT-SPACING

**A child with no extent takes no stack spacing (SwiftUI charges it).** Should a stack put its spacing on both sides of a child that takes no rows (an empty `VStack`, `Color.clear.frame(height: 0)`), as SwiftUI does, or keep TUIkit's rule that such a child takes no gap?

In SwiftUI, a `VStack(spacing: 10)` of two Texts is 42 pt tall; an empty VStack or `Color.clear.frame(height: 0)` between them makes it 52, while a nil or EmptyView adds nothing (measured 2026-09-24). TUIkit charges spacing only between children that take a row or are spacers (`totalLinearSpacing(occupiedChildren:spacing:)`, pinned by Tests/TUIkitFoundationTests/EmptyContentLayoutTests.swift:95). The Example's Animation page relies on this: its un-kept slot is an empty stack in a `VStack(spacing: 1)`. Matching SwiftUI first needs EmptyView told apart from a zero-size view (S3-EMPTYVIEW-FRAME). Every framework view that draws nothing in some state would then start taking a gap unless it too counts as no member.

- **1. Keep TUIkit's rule and record it as deliberate.** Empty children never cost a blank line. *Price:* Docs only. SwiftUI code with empty containers gets less space here than in SwiftUI.
- **2. Match SwiftUI.** Charge spacing to every child except one that is nothing. Do S3-EMPTYVIEW-FRAME first, then audit the framework's views that render nothing so they count as no member, and rework the Animation page to use an `if`. *Price:* Unpriced beyond 'S'. The audit is the risk: a missed internal view adds stray blank lines. Re-baseline the tests.

**Recommended:** Option 2. Your stack-spacing rulings so far all followed SwiftUI (A-BITEMS1-1, L12, L14), and the gap is the app's own spacing request. Ship it only after the audit shows framework internals won't add stray gaps.

**If you don't answer:** TUIkit's rule stays, the Example keeps relying on it, and it stays an open divergence in guide §3.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/SwiftUI compatibility guide.md:1224-1246; /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md:1519; /Users/robot/Documents/TUIkit/Tests/TUIkitFoundationTests/EmptyContentLayoutTests.swift:90-110; /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/owner-decisions-2026-10-12.md (A-BITEMS1-1, L12, L14)</sub>

### B27-ANIMATING

**Animated scrolling (ScrollPhase.animating and an animated scrollTo).** Do you want animated scrolling, where a `scrollTo` or scroll-position change made inside `withAnimation` moves line by line over several frames and reports `ScrollPhase.animating`, instead of jumping?

Today every scroll jumps. `.animating` is declared but never produced (Sources/TUIkitFoundation/Views/ScrollPhase.swift:45-47), and deviation R1 records 'Scrolling moves in whole lines and is never animated'. SwiftUI animates an animated `scrollTo` and reports idle → animating → idle (measured, B27). This was never put to you. Under reduce motion (A-D3M-1, spatial motion only) it would jump, as animated offsets do now.

- **1. No.** Keep jumping and record R1 as deliberate. *Price:* Free.
- **2. Animate programmatic scrolls.** `scrollTo`, `ScrollPosition` writes and anchor changes made inside an animation move in whole-line steps at 60 Hz along the animation's curve and report `.animating`. They jump under reduce motion. *Price:* Unpriced, likely days: it interacts with scroll anchoring, target behaviours and scroll transitions, and redraws the viewport every frame while it runs (CPU cost only during the animation).
- **3. Option 2 plus animated keyboard paging.** Page Up/Down and Home/End glide as well, as a TUI-only opt-in modifier. *Price:* More of the same work, plus one new TUI-only modifier.

**Recommended:** If you want motion, option 2, preceded by a short design note to price it. SwiftUI code that writes `withAnimation { proxy.scrollTo(id) }` moves there and jumps here. It is low priority either way.

**If you don't answer:** Scrolls keep jumping, `.animating` is never reported, and R1 stands.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md:1455-1517; /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md:1048-1070; /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/Presentation and windows/Dialogs, image sizes, format styles and reduce motion (D3M).md:130-155; /Users/robot/Documents/TUIkit/Sources/TUIkitFoundation/Views/ScrollPhase.swift:40-66</sub>

### B-D5G-4

**Side effects inside a corrected subtree run for both drawings.** When geometry correction draws a subtree twice in one frame, should its side effects be held back so that only the kept drawing's take effect (days of work), or should this stay a known issue?

A coordinate-space owner, a scroll view or the root may correct geometry by drawing its subtree again in the same walk. Registrations made by the first drawing are rolled back (`RenderWalkCheckpoint`), but what the first drawing actually did cannot be undone. An `onChange` that fired runs again. On a reader's first frame, `.onChange(of: proxy.frame(in: …).minY)` fires once (guess → answer), where SwiftUI fires nothing. This is pinned as a known issue at Tests/TUIkitTablesTests/CoordinateSpaceTests.swift:461 (`correctedSubtreeSideEffects`) and recorded under B-D5G-4 in the D5G decisions. The committed deviations page does not list it. At the root, a missed `.global` prediction re-runs every effect in the scene for that frame. It is rare, because prediction keeps corrections rare.

- **1. Keep as a known issue.** No change. *Price:* Free.
- **2. Stage every side effect.** Every side effect is held per walk, and only the last drawing's are adopted. *Price:* Days, across every side-effecting modifier, with an unmeasured per-walk bookkeeping cost.
- **3. Narrow fix for onChange.** Roll back `onChange`'s remembered value with the checkpoint and hold its actions back until the drawing is kept. This covers the pinned case; other effects still run twice. *Price:* Smaller than option 2 but unpriced.

**Recommended:** Keep option 1 for now, and price option 3: `onChange` is the effect apps notice.

**If you don't answer:** It stays a pinned known issue, and a reader's first frame inside a corrected subtree can fire one extra `onChange`.

*(Corrected in the evening re-check.)*

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/Layout and geometry/Coordinate spaces, geometry and scroll visibility (D5G).md:109-140; /Users/robot/Documents/TUIkit/Tests/TUIkitTablesTests/CoordinateSpaceTests.swift:461-480; /Users/robot/Documents/TUIkit-session-notes/plan/QUEUE.md:582</sub>

### RC5

**Semantic audit root cause 5: one shared, debug-loud fallback for reflecting containers.** When a container that sorts its content by asking each child's type drops something it does not recognise, should that go through one shared fallback that stops a debug build (SoftTrap), instead of being found and fixed case by case?

Root cause 5 of the semantic audit (SwiftUI semantic audit (2026-08).md:223-231): containers that classify their children by type silently dropped content they did not recognise. Several of those seams have since moved onto the shared member resolution. Picker options (82ebaf2dd), text-field suggestions (f578978b1) and alert actions (Sources/TUIkitPresentation/Views/Alert.swift:565-600) now go through it. TabView content is now a compile-time `TabContentBuilder`, and `PickerOptionProvider` and `TabContentProvider` no longer exist. Still reflecting by type: `SectionRowExtractor`, `GridRowProviding`, `ListRowExtractor` and Form rows. Some drops are deliberate and match SwiftUI (an alert leaves out a member that isn't a button), so a blanket assert would stop debug builds of valid SwiftUI code. `SoftTrap` asserts in debug builds and reports once in release (Sources/TUIkitCore/Diagnostics/SoftTrap.swift).

- **(a) One shared, debug-loud rule.** A SoftTrap fires only where TUIkit drops content SwiftUI would show, ideally inside the shared member resolution that most seams now use. Deliberate drops are listed so they never assert. *Price:* Medium. Debug builds stop on genuine gaps; a missed entry in the list of deliberate drops would assert on valid code.
- **(b) Case by case (status quo).** Keep fixing silent drops as audits find them. *Price:* Free now. New silent drops are found only by audits.
- **(c) Close RC5 as overtaken.** Treat the move to member resolution as the shared rule, plus a test sweep of the four remaining seams with modified, erased and app-own content. *Price:* Small to medium. Nothing becomes loud in debug.

**Recommended:** (a), scoped to genuine gaps and placed in the shared member resolution, with (c)'s test sweep for the remaining seams.

**If you don't answer:** Fixes continue one by one, and RC5 stays OPEN in the audit.

*(Marked decidable by its writer; a skeptical second reading sent it to you: QUEUE 10-14 lists 'RC5 loud reflection fallback' as needing your ruling and it was never answered. Asserting in users' debug builds is a real trade-off with false-assert risk.)*

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/SwiftUI semantic audit (2026-08).md:223-231; /Users/robot/Documents/TUIkit-session-notes/plan/QUEUE.md:564; /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/swiftui-semantic-audit.md; /Users/robot/Documents/TUIkit/Sources/TUIkitPresentation/Views/Alert.swift:551-600; /Users/robot/Documents/TUIkit/Sources/TUIkitCore/Diagnostics/SoftTrap.swift:1-45</sub>

### TABLE-CLOSURE-COLUMN

**A closure TableColumn rebuilds every cell every frame: purity pitch and a workaround.** Should TUIkit add a way to tell a Table that a closure column's cells depend only on the row, so that unchanged rows skip rebuilding, and do you want to post the Swift-forums 'purity effect' pitch?

A Table can skip building an unchanged row's cells only when every column names a String property (`namesAProperty`, Sources/TUIkitTables/Views/TableColumn.swift:132). A closure column — `TableColumn(_:value:content:)`, which you need when what is shown differs from what is sorted — rebuilds and compares every drawn cell every frame. Measured on 2026-09-22: 18.6% of `app-shapes/file-browser` went to `Int.formatted(.byteCount)` and `Date.formatted` for 36 rows. But profiler shares from before 2026-10-08 are indicative only, and the table paths were reworked in the 10-16 perf pass, so this needs re-profiling. Swift has no way to mark a closure pure (verified on 6.2.4). The pitch (Documentation/Swift language/A closure that reads nothing but its arguments.md) proposes a purity effect inferred the way `throws` is; posting it is your call.

- **(a) Opt-in modifier.** A `.columnContentDepends(on:)`-style modifier where the app promises the cells depend only on the row. *Price:* Hours to a day. The promise is unchecked, so a wrong use draws stale cells.
- **(b) Key path + FormatStyle column init.** A TUI-only TableColumn init that takes a key path and a FormatStyle (an Equatable value), so the cell is a pure function by construction and qualifies for the fast path. An extra init is allowed by your 10-14 rule. *Price:* About a day, unpriced. No stale-cell risk; covers formatting only, not arbitrary cell views.
- **(c) Neither; document a workaround.** Keep the formatted strings in the row model, so the closure only reads a property and the comparison is cheap. *Price:* Docs only.
- **Separately: post the pitch.** Post the drafted Swift Evolution pitch. *Price:* Your time only; no code.

**Recommended:** Re-profile file-browser first. If formatting is still a large share, do (b); otherwise (c). Post the pitch if you want to.

**If you don't answer:** Closure columns keep rebuilding every drawn cell each frame, and the pitch stays an unposted draft.

<sub>Sources: /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/table-row-memo-tiers.md; /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/swift-has-no-purity-annotation.md; /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/profiler-shares-before-2026-10-08-deduplicated.md; /Users/robot/Documents/TUIkit/Documentation/Swift language/A closure that reads nothing but its arguments.md; /Users/robot/Documents/TUIkit/Sources/TUIkitTables/Views/TableColumn.swift:125-260</sub>

### SA-82-TABVIEW-PLAIN

**TabView with plain-view content (children as pages).** Should TabView accept plain views as pages through SwiftUI's non-deprecated `TabView(content:)` (where SelectionValue == Int), or should that form stay declined?

TUIkit's TabView accepts only `TabContentBuilder` content (Sources/TUIkitTabs/Views/TabView.swift:67, :137), so `TabView { Text("A"); Text("B") }` fails to compile. That replaced the silent blank screen the audit found. In SwiftUI, `init(selection:content:)` with `@ViewBuilder` and `.tabItem` are deprecated, but `extension TabView where SelectionValue == Int { init(@ViewBuilder content:) }` is not (SwiftUI.swiftinterface:2655-2657). So the 10-14 answer ('deprecated forms only') was wrong, and [21] does not settle this. Without `.tabItem` (deprecated and not implemented here), these pages have no labels, so TUIkit would have to invent a tab strip: numbered tabs, blank tabs as macOS shows, or a page indicator.

- **(a) Add `TabView(content:)` for plain views.** Each child becomes a page, the first is selected, and the strip shows numbered or blank labels. *Price:* Medium (about a day, unpriced). SwiftUI code compiles, but the look is TUIkit's own invention.
- **(b) Decline.** Add a parity-map entry ('on macOS its only label source is the deprecated tabItem') and close the slated row on the deviations page. *Price:* Free. Stays a compile error, which is rule 2's correct failure.

**Recommended:** (b). On macOS the plain form is useful only together with the deprecated `.tabItem`, so adding it would mostly compile code that shows unlabelled tabs.

**If you don't answer:** Plain-view TabView content keeps failing to compile, and the slated row ('the fix draws the tagged children as pages; no ruling') stays open.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/SwiftUI semantic audit (2026-08).md:1003-1009; /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md:1515; /Users/robot/Documents/TUIkit-session-notes/plan/QUEUE.md:564,590; /Users/robot/Documents/TUIkit/Sources/TUIkitTabs/Views/TabView.swift:60-145; /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/SwiftUI.framework/Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface:2635-2662</sub>

## Controls and chrome

### A21-TABPOPOVER

**A tab's popover in a compact size class.** When an app sets a compact size class, should a tab's popover (TabContent.popover) turn into a sheet like every other popover, at the cost of TUIkitTabs depending on TUIkitPresentation?

On 10-12 you ruled A21 option 3: when an app sets .compact, popovers adapt and split views collapse. Popovers and sheets shipped 10-13 (b4bcb9b54, deb93f8f6). The one exception is TabContent.popover. TUIkitTabs draws it with Foundation's PopoverPresentationModifier, and it does not depend on TUIkitPresentation, where the sheet and cover presenters live (Package.swift:381-382; TabContentInteractions.swift:82). The decisions doc left this for you (A21, 'Shipped 2026-10-13: the popover half'). It matters only to an app that sets .compact itself, because the defaults stay regular.

- **1. Add the dependency.** TUIkitTabs depends on TUIkitPresentation, and a tab's popover adapts the way View.popover does. *Price:* About half a day. `import TUIkitTabs` then also brings TUIkitPresentation and TUIkitChrome. That byte cost is unmeasured. Umbrella users pay nothing, and ColorPicker already links both.
- **2. Environment hook.** Foundation's popover modifier calls an adaptation closure from the environment, which the app installs at its root. *Price:* About a day and one TUI-only API. An app that forgets the hook gets unadapted tab popovers with no error: a silent partial honour.
- **3. Leave it.** Tab popovers stay popovers in a compact class, recorded as a deviation. *Price:* No work. One edge case of your 10-12 ruling stays unhonoured.

**Recommended:** Option 1. It is the only option that honours your ruling without a silent gap. First measure what it adds to an app that imports only TUIkitTabs, and fall back to option 3 if that cost is out of proportion to an edge case.

**If you don't answer:** Tab popovers stay popovers under .compact. Every other popover, sheet and split view adapts as ruled.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md (A21, ~:336-360); /Users/robot/Documents/TUIkit-session-notes/plan/QUEUE.md:550 (deferred: Tabs→Presentation dependency); /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/owner-decisions-2026-10-12.md ([19] B3); /Users/robot/Documents/TUIkit/Package.swift:250-253, :339-343, :381-383; /Users/robot/Documents/TUIkit/Sources/TUIkitFoundation/Modifiers/PopoverPresentationModifier.swift:44; /Users/robot/Documents/TUIkit/Sources/TUIkitPresentation/Views/PresentationCompactAdaptation.swift</sub>

### B72-CAPSULE

**Capsule behind a list's .standard badge.** Should a list row's .standard badge sit in a capsule, a tinted field such as ` 12 `, as macOS draws it, instead of today's plain dim text?

Measured on macOS 15.8: a .standard badge is bold grey text in a light grey capsule, .decreased has no capsule, and .increased looks the same as .standard. TUIkit draws .standard as plain text in the palette's tertiary ink and .decreased in the quaternary ink (decisions B72; _ListCore.swift:4171; deviation V3). Since 10-15 the default appearance is Lines, under which rounded buttons have no fill at all.

- **a. Keep plain text.** No change. *Price:* None.
- **b. Tinted capsule everywhere.** .standard badges get a field one cell wider on each side, in every appearance. *Price:* Half a day. Every badged list changes look, and the golden snapshot tests that show badged rows need re-recording. The field colour has to be chosen per palette so it still reads on the cursor row's breathing highlight.
- **c. Capsule in the Appearance family.** A tinted field under Solid, and line caps from the FB14 cap set under Lines. *Price:* About a day. Best done alongside FB3-OTHERCAPS.

**Recommended:** Option c if FB3-OTHERCAPS goes ahead, otherwise a. Under the Lines default, a solid fill would be the only filled element on screen.

**If you don't answer:** Badges stay plain text. The shipped option stands, open to your veto.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md (B72, :2596-2624); /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md (V3); /Users/robot/Documents/TUIkit/Sources/TUIkitLists/Views/_ListCore.swift:4171; /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/owner-decisions-2026-10-12.md (10-15 button looks, Lines default)</sub>

### B75

**Draw a tab's custom label view into its chip.** Should a tab whose label is the app's own view (Tab(content:label:)) draw that view inside its chip in the tab strip, instead of only its first line as plain text?

The strip draws each tab as a chip in the strip's own ink, with ▐ ▌ caps, and the active chip breathes while the strip has focus (TabViewStrip.swift:33-51). A title, or a title with an SF Symbol, draws in full; since 585bb31d7 (B-PARITYMISC-3) a title drops its key's Markdown delimiters but doesn't draw its styles, which doesn't affect custom label views. A custom label view is measured, and only its first line is taken, without its colours (decisions B75; Tab.swift:32).

- **a. Keep text.** No change. *Price:* None.
- **b. Draw the view.** Render the label at the chip's height, with the strip's ink as its foreground and the chip's fill as its background, and repaint it on each breathing frame. *Price:* Half a day, mostly the breathing animation and the folder style's walls. An app's own colours and layout could then clash with the strip's single ink.

**Recommended:** Option a, unless you want pictures in chips for TAB-IMAGE-NAME, in which case b.

**If you don't answer:** Chips keep drawing a custom label as text. The shipped option stands, open to your veto.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md (B75, :2683-2705); /Users/robot/Documents/TUIkit/Sources/TUIkitTabs/Views/TabViewStrip.swift:33-51; /Users/robot/Documents/TUIkit/Sources/TUIkitTabs/Views/Tab.swift:32, :396</sub>

### B76-SELECT

**Sidebar tab view: select as the cursor moves.** In a .sidebarAdaptable tab view's sidebar, should moving the cursor select the tab, as a macOS sidebar does, or should the user keep choosing with Return, Space or a click?

TUIkit lists keep the keyboard cursor separate from the selection (deviation V2, whose reason is not recorded): the arrows move the cursor, and Return, Space or a click selects. The sidebar follows that rule (TabViewSidebar.swift:96-106). A macOS sidebar selects as the cursor moves, so every arrow press swaps the content beside it.

- **a. Select on move (sidebar only).** Add a list mode that selects as the cursor moves, or have the sidebar watch the cursor. *Price:* About 2 hours. Holding ↓ flips through every tab's content, and each step renders that tab.
- **b. Keep Return/Space/click.** No change. *Price:* None. It differs from macOS but matches every other TUIkit list.

**Recommended:** Option a. A sidebar is a navigator with a single selection, Return has nothing else to do there, and this is how macOS behaves.

**If you don't answer:** Return, Space or a click choose the tab.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md (B76 'Choosing a tab', :2732-2737); /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md (V2, :1606-1620); /Users/robot/Documents/TUIkit/Sources/TUIkitTabs/Views/TabViewSidebar.swift:96-106</sub>

### B78-VISIBILITY

**When section actions are shown.** Should section actions show only while the focus is inside their section or the pointer is over it, or always, as now?

macOS shows them only while the pointer is over the section, which leaves the keyboard no way to reach them. TUIkit shows them all the time, and each one is a Tab stop (decisions B78). The change is about one line.

- **a. Always (shipped).** Every section's actions are visible and are Tab stops. *Price:* None. Headers are busier, and Tab has to cross every section's actions.
- **b. Focus or hover.** A section's actions show while the cursor or focus is in that section, or the pointer is over it. *Price:* One line plus tests. Headers are quieter and fewer Tab stops are registered, while a keyboard user still reaches the actions by moving into the section.

**Recommended:** Option b. It keeps a keyboard route, matches macOS for the mouse, and cuts Tab stops.

**If you don't answer:** Actions stay visible all the time.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md (B78, :2819-2821); /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/no-mouse-only-interactions.md</sub>

### COLORPICKER-MODEBAR

**ColorPicker's mode switcher, and Tabs depending on Lists.** Should ColorPicker's panel switch modes with a segmented Picker or a row of Buttons instead of its 10-tab TabView, and should TUIkitTabs stop depending on TUIkitLists?

With per-module products (C9b, 17a63a3a7; landed at 3df96c964), an app that uses only ColorPicker links TUIkitTabs, and through it TUIkitLists (Package.swift:286-289, :381-382), because the sidebar tab style builds its list in TUIkitLists (B-SPC3-1). The SIZE3 estimates were emulated and have not been re-measured under today's products: a row of Buttons saves about 898 KB (315 KB in an app that already links Lists), and a segmented Picker about 665 KB. The editors split from the same list shipped as TUIkitCurveEditors. Both questions were asked on 10-10 and never answered.

- **1. Keep the TabView.** No change. *Price:* None. ColorPicker apps carry Tabs and Lists.
- **2. Segmented Picker.** The 10 modes become one segmented control. *Price:* Under a day (estimate), saving about 665 KB (estimate). The panel keeps a single Tab stop, and segments replace the chip look.
- **3. Row of mode Buttons.** Each mode becomes its own button. *Price:* Under a day (estimate), saving about 898 KB (estimate). Each mode becomes a separate Tab stop.
- **4. Cut Tabs→Lists.** Move the sidebar tab style into a module of its own, or have it reach the list through an interface. *Price:* 1 to 2 days (estimate). `.sidebarAdaptable` would then need an extra import. Every app that imports Tabs without Lists benefits.

**Recommended:** Re-measure under today's products first. If the saving holds, choose option 2, which keeps one Tab stop and the feel of a single control. Leave option 4 alone until an app that uses only Tabs needs it.

**If you don't answer:** The panel keeps its TabView, and Tabs keeps depending on Lists.

<sub>Sources: /Users/robot/Documents/TUIkit-session-notes/SIZE3/answers.md:129-147, :272; /Users/robot/Documents/TUIkit/Documentation/Working notes/CENSUS/census.md:70-71, :145-146; /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/Module split/Steps C3 and C4, peeling TUIkitTabs and TUIkitGrid (SPC3).md:57-70; /Users/robot/Documents/TUIkit/Package.swift:286-289, :381-383; /Users/robot/Documents/TUIkit/Sources/TUIkitColorPicker/Views/ColorPickerPanel.swift; /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/compile-time-and-binary-size-request.md</sub>

### CONTROLGROUP-LOOK

**ControlGroup as one segmented face.** Should a ControlGroup draw its buttons as one segmented face, with caps only at the two ends and a rule between buttons, as macOS and TUIkit's own segmented Picker do?

AutomaticControlGroupStyle (and the navigation and palette styles) puts the buttons in an HStack with no spacing, and each button draws its own face (ControlGroup.swift:199-215). Under the Lines appearance, the default since 10-15, the 10-16 Example survey found three touching capsules: '( − )( 100% )( + )' (EXSURVEY/notes.md:24). The code's own comment calls the style 'a segmented control's shape', and macOS draws a ControlGroup as one segmented control. The question was flagged for a morning report but never asked.

- **a. One segmented face.** The group tells each button, through the environment, whether it is first, middle or last. Caps are drawn only at the ends, with a rule between buttons, the same way the segmented Picker draws. *Price:* Half a day to a day, plus re-recorded golden snapshots.
- **b. Leave.** No change. *Price:* None. The touching capsules remain under Lines.

**Recommended:** Option a, drawn exactly as the segmented Picker is, whatever FB3-OTHERCAPS settles for its caps.

**If you don't answer:** ControlGroups keep drawing as touching capsules under Lines.

*(Marked decidable by its writer; a skeptical second reading sent it to you: A glyph-level look for a control under Lines. It was flagged for your morning report and never asked, you have ruled every control look personally, and it depends on FB3-OTHERCAPS.)*

<sub>Sources: /Users/robot/Documents/TUIkit-session-notes/EXSURVEY/notes.md:24; /Users/robot/Documents/TUIkit/Sources/TUIkitMenus/Views/ControlGroup.swift:199-260; /Users/robot/Documents/TUIkit/Sources/TUIkitPickers/Views/_PickerSegmentsCore.swift:27-55; /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/owner-decisions-2026-10-12.md (10-15 evening: aesthetic ⟂ shape, a family)</sub>

### FB3-BLANK

**Text-field caps: │text│ or │ text │.** Under the Lines appearance, should a text field's caps be `│text│` (shipped, one cell each) or `│ text │`, with a blank cell inside each cap?

On 10-16 you chose FB3 option (a): fields keep their surface and get line caps, shown in the question as `│ text │`. aacb393ca shipped one-cell caps without the blank, because the blank costs 2 cells per field and squeezed the colour picker's numeric fields. That was raised in EVENING-REPORT-1016 ('Say if you want the blank') and has had no answer.

- **a. Keep │text│.** No change. *Price:* None.
- **b. Blank everywhere.** Every field draws `│ text │`. *Price:* 2 more cells per field. The colour picker's fields or panel must be widened, and golden snapshots re-recorded.
- **c. Blank only where there's room.** The blank is added when the field's frame has spare cells. *Price:* About half a day. Fields would look different from one another.

**Recommended:** Option a.

**If you don't answer:** Fields keep │text│.

<sub>Sources: /Users/robot/Documents/TUIkit-session-notes/plan/EVENING-REPORT-1016.md:48; /Users/robot/Documents/TUIkit-session-notes/plan/MORNING-QUESTIONS-1016.md:89-98; /Users/robot/Documents/TUIkit-session-notes/plan/QUEUE.md:661, :696</sub>

### FB3-OTHERCAPS

**Segmented pickers and tab chips follow the Appearance family.** Should segmented pickers and TabView chips (including those in the colour picker's panel) take their end caps from the Appearance family, as buttons and text fields now do, instead of always drawing ▐ ▌ half-blocks?

Buttons follow Appearance (4311750a1; FB14 shapes in 1fc876f94), and so do text fields (aacb393ca). The segmented picker (`▐ S │ M │ L ▌`, _PickerSegmentsCore.swift:4, :30) and the tab strip (TabViewStrip.swift:47, :51) do not. The toggle's ▐▌ (_ToggleCore.swift:48) is its switch knob, not a cap, so it needs its own design. On 10-15 you made Appearance the API and asked that shapes look coherent side by side as a family, and O14 records that the controls other than buttons are still owed. This follow-on was raised in EVENING-REPORT-1016 and not answered.

- **1. Segments and chips follow.** Their end caps come from the button's cap table, per appearance and the FB14 shape set. The rules between segments stay. ControlGroup gets the same treatment. *Price:* About a day, plus re-recorded golden snapshots.
- **2. Also redesign the switch under Lines.** A Lines-family switch, shown to you on a probe card first. *Price:* About half a day more, and it is your taste.
- **3. Leave.** ▐ ▌ stays under every appearance. *Price:* None. Controls look inconsistent under Lines.

**Recommended:** Option 1 now. Put the toggle's Lines look on a probe card (option 2) before building it.

**If you don't answer:** Segments and chips keep their half-block caps under Lines.

*(Marked decidable by its writer; a skeptical second reading sent it to you: EVENING-REPORT-1016 asked you directly ('Want them to follow?') and you didn't answer. Your 10-15 family ruling was about button shapes, and control looks are your taste.)*

<sub>Sources: /Users/robot/Documents/TUIkit-session-notes/plan/EVENING-REPORT-1016.md:49; /Users/robot/Documents/TUIkit-session-notes/plan/QUEUE.md:698, :783; /Users/robot/Documents/TUIkit/Sources/TUIkitPickers/Views/_PickerSegmentsCore.swift; /Users/robot/Documents/TUIkit/Sources/TUIkitTabs/Views/TabViewStrip.swift:33-51; /Users/robot/Documents/TUIkit/Sources/TUIkitFoundation/Views/_ToggleCore.swift:31-49; /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md:124-126 (O14); /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/owner-decisions-2026-10-12.md (10-15)</sub>

### STEPPER-WIDTH

**Stepper's ▶ moves when the value gains a digit.** Should a Stepper reserve the width of its widest value by default, so that ▶ never moves, or should reserving be opt-in?

TUIkit's Stepper draws `◀ value ▶`, so going from `◀ 9 ▶` to `◀ 10 ▶` moves the right arrow one column, possibly while a repeating click is on it. You parked this on 09-02 until the format: initialisers existed, because a format style is what bounds the width of a rendering. They now exist (Stepper.swift:909, :929, :947). The plan is a TUI-only `.stepperValueWidth(_:)` modifier, like `.colorPickerLabelWidth(_:)`. You said then that app authors will disagree about the default, and left it to yourself.

- **1. Default: fit the bounds.** With bounds, reserve the width of the wider of the two formatted ends. With no bounds, reserve nothing. The modifier overrides either way. *Price:* About half a day. Stepper rows get wider by the reserved cells, and the arrow never moves under a click.
- **2. Default: reserve nothing.** The same modifier, but opt-in. *Price:* About half a day. Today's look stays, and the arrow still moves unless the app asks.

**Recommended:** Option 1. A row that jitters is cosmetic, but an arrow moving under a repeating click is a functional bug.

**If you don't answer:** No modifier is added, and the arrow keeps moving.

<sub>Sources: /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/stepper-value-width-pinned.md; /Users/robot/Documents/TUIkit/Sources/TUIkitNumericControls/Views/Stepper.swift:20-21, :909-950</sub>

### TAB-IMAGE-NAME

**Tab(_:image:…) takes an image name, not an ImageResource.** Ship Tab's `image:` initialisers, which take an image name (a String), the same way Label(_:image:) already ships, or keep them declined with a corrected reason?

Decision C11 and the parity-map rule decline Tab's image: forms on the grounds that they name an asset-catalogue ImageResource. That is wrong. The installed SDK declares every Tab `image:` parameter as Swift.String (SwiftUI.swiftinterface:14812-14844, :14913-14915). Only Button, Toggle, Picker, Menu and ControlGroup take ImageResource. Label(_:image:) with a name already ships and draws a 2×1-cell picture (refusal review P12; ImageNameInitializers.swift:42). Tab's own doc comment (Tab.swift:35-36) gives the same asset-catalogue reason and says, wrongly, that Label's image: forms are not offered, so it is a third place to correct. TUIkitTabs doesn't depend on TUIkitBitmaps, and tab chips draw text only (B75).

- **a. Ship the String forms.** Add an extension in TUIkitBitmaps, like Label's, that finds the name as Image(_:bundle:) does. The picture shows in the sidebar list. Strip chips show only the title, as they already do for a symbol the terminal can't draw. *Price:* About half a day.
- **b. Ship them together with B75.** Chips also draw the 2-cell picture. *Price:* About a day.
- **c. Keep declined, with a true reason.** State that a one-line chip has no room for a picture, and split the entry from the ImageResource family. *Price:* About 15 minutes.

**Recommended:** Option a, which is consistent with P12 and Label. Whatever you pick, correct C11 and the parity-map reason now; that fix is factual and costs nothing.

**If you don't answer:** The forms stay declined under a reason that is wrong. The factual correction should still be made.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md (C11, :3617-3626); /Users/robot/Documents/TUIkit/Tools/APIParity/parity-map.json:138-147; /Users/robot/Documents/TUIkit/Tools/APIParity/baseline.json:178-179; /Users/robot/Documents/TUIkit/Sources/TUIkitTabs/Views/Tab.swift:35-36; /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Refusals re-examined, wave 17 (2026-10-03).md (P12, :682-693); /Users/robot/Documents/TUIkit/Sources/TUIkitBitmaps/Views/ImageNameInitializers.swift:14-55; /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface:14812-14844, :14913-14915</sub>

### TABBARMIN

**tabBarMinimizeBehavior.** On macOS, tabBarMinimizeBehavior takes only .automatic, which shrinks the tab bar when the window is short of room. Should TUIkit honour it by collapsing a tab view to the compact strip, and if so, triggered by what? Or should it refuse the modifier?

In the installed SDK, .never, .onScrollDown and .onScrollUp are iOS-only. On macOS the only value is .automatic, and Apple documents that it minimises the bar under reduced space (SwiftUI.swiftinterface:9252-9283). The API is therefore not inert on macOS, and your O8 ruling (refuse APIs that are inert on macOS too) does not cover it. View.tabBarMinimizeBehavior(_:) is still a gap (baseline.json:154), and the map's reason for declining TabBarMinimizeBehavior (a 'translucent floating pill') is stale (parity-map.json:761-763). TUIkit's default style is already the compact strip, so only .bordered, .grouped and .sidebarAdaptable would collapse. .sidebarAdaptable already becomes the strip in a compact size class (4c9850af3). The refusal review and the A28 study both recommend honouring it.

- **a. Collapse when the terminal is short of room.** .bordered, .grouped and .sidebarAdaptable collapse to the compact strip below a size threshold, by default, as on macOS. *Price:* Half a day to a day. The default changes for apps using those styles in small terminals, and the threshold is a new judgement call.
- **b. Collapse in a compact size class.** .automatic collapses when the app sets a compact size class, extending what .sidebarAdaptable already does to .bordered and .grouped. *Price:* Half a day. Defaults don't change, in line with your B3 ruling.
- **c. Refuse.** Decline it with a correct reason. *Price:* About 15 minutes.

**Recommended:** Option b. It honours the API, changes no default (your B3 rule), and reuses the size-class collapse already shipped. Correct the map's reason whatever you choose.

**If you don't answer:** It stays a gap with a stale reason in the map.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Refusals re-examined, wave 17 (2026-10-03).md:133, :1069-1084; /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Design studies/Toolbars and opt-in chrome design study, A28 (2026-10-04).md:335-336; /Users/robot/Documents/TUIkit/Tools/APIParity/parity-map.json:761-763; /Users/robot/Documents/TUIkit/Tools/APIParity/baseline.json:154; /Users/robot/Documents/TUIkit/Sources/TUIkitTabs/Styles/TabViewStyle.swift:22-70; /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md:82-83, :115-118 (O8); /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface:9252-9283</sub>

### DRAWERS

**Drawers and slideovers draft.** Build a TUI-only drawer (and perhaps a slideover) from the draft, or retire the draft to Historical, now that .inspector, split views and docked live sheets cover the cases it was written for?

The doc is still marked 'draft for decision'. Of its plan, only §4c, the sheet's detent grabber, shipped (A19), and that settled Q3 (the grabber glyph) and Q6 (snapping, which happens as it moves). Q5, whether the grabber is a Tab stop, is settled in practice: split-view dividers, the inspector's divider and the sheet grabber are all focus stops. Still open: Q1 (split-view column or a control of its own), Q2 (a separate slideover) and Q4 (the size as an app-visible binding). Since the draft was written, .inspector has shipped as a resizable trailing column with a focusable divider and a hide ▶ (Inspector.swift:15-50). A leading pane is NavigationSplitView's sidebar, and a bottom pane is a detented live sheet docked like a VSplitView (your A19 framing). With window chrome now opt-in (A28), the slideover's one visible difference, a header row, is mostly gone. No drawer code exists.

- **1. Retire the draft.** Move it to Historical with a note saying which shipped APIs cover each case. *Price:* About 15 minutes. No new API.
- **2. Build the drawer.** A TUI-only `.drawer(isPresented:edge:…)` built on the split-view machinery, with an optional size binding so an app can persist the user's size through @AppStorage. *Price:* Not priced in the draft; likely a few days. It overlaps .inspector.
- **3. Drawer and slideover.** Option 2, plus a screen-anchored slideover on the overlay path that modals use. *Price:* More again. Its value is small now that chrome is opt-in.

**Recommended:** Option 1. The cases the draft wanted are covered by APIs that carry SwiftUI's names, and a TUI-only drawer would duplicate .inspector.

**If you don't answer:** The draft stays in Documentation as an open item and keeps appearing in the census.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/Controls and presentation/Drawers, sheets and slideover panes.md:3, :160-180, :186-260, :293-310; /Users/robot/Documents/TUIkit/Sources/TUIkitNavigation/Views/Inspector.swift:15-50; /Users/robot/Documents/TUIkit-session-notes/answers-2026-10-11.md:342; /Users/robot/Documents/TUIkit/Documentation/Working notes/CENSUS/census.md; /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/owner-decisions-2026-10-04.md (A19 'mapping … to vertical split views')</sub>

### B-D5C-1

**windowToolbarStyle with a style chosen at run time.** Keep TUIkit's extra windowToolbarStyle(_: any WindowToolbarStyle) overload, replace it with if/else support in SceneBuilder, or have the Example choose its toolbar style only at launch?

SwiftUI's modifier is generic, so the style is fixed at compile time. A scene modifier also cannot be chosen with `if`, because SwiftUI's SceneBuilder has no buildEither (the SDK shows buildBlock, buildOptional and buildLimitedAvailability only), and neither does TUIkit's. The Example's Theme page therefore couldn't apply a user's choice. TUIkit shipped a @_disfavoredOverload existential overload (Scene+WindowToolbarStyle.swift:174) beside the generic one (:161), so SwiftUI source still binds to the generic form. The Example uses it at main.swift:51. The decisions file says 'your call if the name sharing bothers you'.

- **1. Keep the overload.** No change. *Price:* None.
- **2. SceneBuilder if/else.** A TUIkit extension that lets any scene modifier be chosen at run time; the overload is removed. *Price:* About half a day. It is a broader TUI-only addition.
- **3. Choose at launch.** Drop the overload, so the Example picks its style once at launch. *Price:* Small. The Example loses switching the toolbar style live.

**Recommended:** Option 1.

**If you don't answer:** The overload stays.

*(Marked decidable by its writer; a skeptical second reading sent it to you: The D5C decision file explicitly leaves this to you ('your call if the name sharing bothers you'). It's a taste veto on a TUI-only overload.)*

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/Menus, toolbars and chrome/Toolbars and opt-in window chrome (D5C).md:14-36; /Users/robot/Documents/TUIkit/Sources/TUIkitApp/App/Scene+WindowToolbarStyle.swift:161, :174; /Users/robot/Documents/TUIkit/Sources/Example/main.swift:51; /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/swiftui-source-compat-rules.md</sub>

### DEPR-ALERT-NAME

**TUIkit's Alert shares SwiftUI's deprecated Alert name.** Rename TUIkit's `Alert` view, whose name matches SwiftUI's soft-deprecated `Alert` struct?

TUIkit's `struct Alert<Actions: View>` (Sources/TUIkitPresentation/Views/Alert.swift:64) is an alert-shaped panel view that an app can compose inline or pass to .modal; `.alert(…)` builds one internally (AlertPresentationModifier.swift:122). SwiftUI's `Alert` is the old value type for alert(isPresented:content:). It is soft-deprecated, meaning marked deprecated without a compiler warning, and none of its API exists in TUIkit (DEPR/notes.md, 'Name only'). Old SwiftUI code such as `Alert(title: Text(…), dismissButton: …)` correctly fails to compile, but the error points at a different type. There are about 30 uses in Sources and Tests (5 in the Example's OverlaysPage), plus docs.

- **a. Keep the name.** No change. *Price:* None.
- **b. Rename.** Rename it, for example to AlertPanel, without a compatibility alias, per your pre-1.0 no-shims rule. *Price:* About an hour plus docs. Apps that name the type directly must update.

**Recommended:** Option b. CLAUDE.md keeps TUI-only APIs apart from SwiftUI's, and the current name reads as SwiftUI's retired type.

**If you don't answer:** The name stays.

<sub>Sources: /Users/robot/Documents/TUIkit-session-notes/DEPR/notes.md ('Name only'); /Users/robot/Documents/TUIkit/Sources/TUIkitPresentation/Views/Alert.swift:7-64; /Users/robot/Documents/TUIkit/Sources/Example/Pages/OverlaysPage.swift:620-645; /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/no-backwards-compat-shims.md</sub>

### A-MENUBAR-1

**A standard command set for display options.** Your item #6 asked for "maybe a default TUIkit View menu with display options". The Example's View menu now has Palette ▸, Border Style ▸ and Text Styling ▸, written in the Example. Should TUIkit offer the same to every app, as SwiftUI offers `ToolbarCommands` and `SidebarCommands`?

- **1. Nothing in TUIkit** (today). An app writes its own, about twenty lines of `Picker`s over `PaletteRegistry.all` and `AppearanceRegistry.all`. *Price:* None.
- **2. `DisplayCommands()`**, a TUIkit-only standard set adding View ▸ Palette ▸ and View ▸ Border Style ▸, acting on the app's palette and appearance managers as the `t` and `a` keys do. An app that holds its palette itself and applies it with `.palette(_:)` at the scene, as the Example does, overrides the manager, so the set's Palette would do nothing visible there; it is documented as acting on the managers. *Price:* Half a day with tests.
- **3. 2, plus a binding form**, `DisplayCommands(palette: $palette)`, for an app that holds its palette. *Price:* A day.

**Recommended:** Option 2.

**If you don't answer:** Apps write their own, as the Example does.

<sub>Sources: Documentation/SwiftUI parity/Decisions/Menus, toolbars and chrome/The menu bar behaves as macOS's (MENUBAR).md, A-MENUBAR-1</sub>

## Input, keys and gestures

### B-D1K-1

**⌘ chords under the kitty protocol.** Where the kitty keyboard protocol lets a ⌘ chord through, should TUIkit deliver it as ⌘ (.command) instead of dropping it, and if so should KeyboardShortcut("s") fire on the real ⌘S, on its Ctrl-S stand-in, or on both?

Under the kitty protocol, a ⌘ chord the terminal doesn't keep for itself arrives with the Super bit (kitty and Ghostty on macOS, per their docs; not measured). TUIkit drops any Super/Hyper/Meta chord that types no text, though it still updates the modifier state (Sources/TUIkitCore/Input/KittyKeyboardProtocol.swift:61-70, :262-266). So onKeyPress never sees .command, and a ⌘ shortcut fires only through .commandKey's stand-in, Ctrl by default (Sources/TUIkitFoundation/Views/KeyboardShortcut.swift:424-462). Delivering ⌘ means every consumer that matches a bare character must learn to refuse it: text fields, type select, the status bar, the theme and appearance keys, the Example's page keys. Otherwise ⌘K types a 'k'.

- **Keep dropping (today).** ⌘ chords stay dropped. ⌘ shortcuts work only through the stand-in key, and onKeyPress never sees .command. *Price:* Free.
- **Deliver ⌘; a shortcut fires on both.** onKeyPress sees [.command] as in SwiftUI. KeyboardShortcut("s") fires on a real ⌘S where the terminal passes it, and on the stand-in everywhere. *Price:* About a day, mostly auditing bare-key consumers. A consumer the audit misses would type a letter on ⌘-letter. No runtime cost.
- **Deliver ⌘; real ⌘ only where the protocol is on.** The stand-in is switched off under the protocol. *Price:* The same day. Terminals keep many ⌘ chords for themselves (⌘C, ⌘V, ⌘Q and others), so those shortcuts would become unreachable. Not recommended.

**Recommended:** Deliver ⌘ and fire on both. It's the only precedence that never makes a shortcut unreachable, and it gives onKeyPress SwiftUI's [.command]. Not urgent: nothing breaks while it waits.

**If you don't answer:** ⌘ chords stay dropped under the kitty protocol, and ⌘ shortcuts are reached only through the stand-in key.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/Input, clipboard and text editing/Kitty keyboard protocol, key-press phases and UndoManager (D1K).md:13-37; /Users/robot/Documents/TUIkit/Sources/TUIkitCore/Input/KittyKeyboardProtocol.swift:61-70,250-266; /Users/robot/Documents/TUIkit/Sources/TUIkitFoundation/Views/KeyboardShortcut.swift:424-480</sub>

### B63-CTRLJ

**Read LF as Ctrl-J, a newline key on every terminal.** Should the input parser read LF (0x0A) as Ctrl-J instead of Return, so a vertical TextField can bind Ctrl-J to insert a newline on every terminal?

In raw mode the Return key sends CR, and only Ctrl-J sends LF, but the parser reads both as .enter (Sources/TUIkitCore/Input/KeyEvent.swift:363). In a vertical field today, a newline comes from Ctrl-O (every terminal) or Option-Return (only where Option is sent as Meta). SwiftUI's field does nothing on Ctrl-J, so this is a TUIkit extra; Ctrl-J is the newline key of many terminal chat and prompt tools. A safety net already exists: a Ctrl-J nothing binds goes round again as Return (Sources/TUIkitApp/App/InputHandler.swift:207-216; KeyEvent.legacyControlEquivalent, KeyEvent.swift:319). So outside a vertical field, Return would behave as today even on a path that sends LF for it.

- **Keep (LF is Return).** No change. A newline stays Ctrl-O, or Option-Return where Meta is on. *Price:* Free.
- **Parse LF as Ctrl-J; vertical field binds it.** Ctrl-J inserts a newline in a vertical field on every terminal. An unbound Ctrl-J still acts as Return through the existing fallback. *Price:* About half a day with tests. Risk: on a path that delivers LF for Return (none known with ICRNL off; a multiplexer or serial line would need checking), Return in a vertical field inserts a newline instead of submitting, and an app's own Ctrl-J binding fires on Return.
- **Bind Ctrl-J only under the kitty protocol.** No parser change. The vertical field binds Ctrl-J where the protocol already delivers it as itself. *Price:* About an hour, no risk. Absent on legacy terminals such as Apple Terminal.

**Recommended:** Parse LF as Ctrl-J. The existing fallback limits the risk to vertical fields, and the result is a newline key that works on every terminal, Apple Terminal included.

**If you don't answer:** LF stays Return. In a vertical field a newline is Ctrl-O everywhere, or Option-Return where Option is sent as Meta.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md:2353-2393 (B63); /Users/robot/Documents/TUIkit/Sources/TUIkitCore/Input/KeyEvent.swift:309-331,358-365; /Users/robot/Documents/TUIkit/Sources/TUIkitApp/App/InputHandler.swift:207-216</sub>

### B63-KITTY

**Ctrl-Return in a vertical field under the kitty protocol.** Under the kitty keyboard protocol, should Ctrl-Return in a vertical TextField insert U+2028 LINE SEPARATOR, as SwiftUI does, instead of submitting?

Measured on macOS 15.8: in a vertical field, Ctrl-Return inserts U+2028, while Return, Shift-Return and keypad Enter submit (DEC B63). Without the protocol, Ctrl-Return arrives as a plain CR and has to submit. Under it, Ctrl-Return arrives as itself, but the vertical field handles only Option-Return (Sources/TUIkitTextInput/Focus/TextFieldHandler+Vertical.swift:119) and every other Return submits (TextFieldHandler.swift:571-577). Shift-Return already submits, as SwiftUI's does. The real work is the character itself: nothing in Sources mentions U+2028, so SoftWrapLayout, and Text wherever the value is shown, would have to treat it as a line break.

- **Insert U+2028, as SwiftUI.** Ctrl-Return inserts U+2028, and the text paths learn that it breaks a line. *Price:* The key is one line. Teaching the text paths U+2028 is not priced; the inventory's 'small' covers only SoftWrapLayout. It would also make an app string containing U+2028 draw correctly.
- **Insert '\n' instead.** Ctrl-Return inserts an ordinary newline. Documented as a deviation. *Price:* Minutes. The app receives a different character from the one SwiftUI gives it.
- **Keep submitting (today).** Ctrl-Return submits, as on legacy terminals. *Price:* Free.

**Recommended:** Insert U+2028, as SwiftUI does, once the text-path work is priced. If that comes to more than about a day, ship '\n' for now.

**If you don't answer:** Ctrl-Return submits a vertical field on every terminal, as it does today.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md:2353-2393 (B63); /Users/robot/Documents/TUIkit/Sources/TUIkitTextInput/Focus/TextFieldHandler+Vertical.swift:110-125; /Users/robot/Documents/TUIkit/Sources/TUIkitTextInput/Focus/TextFieldHandler.swift:571-577</sub>

### B77-KEYTIME

**Type select versus bare-key bindings.** Should type select decide when the key arrives, taking a first letter whenever some row starts with it and passing it on when none does, instead of today's rule that a bound first letter always goes to its binding?

Type select shipped in 2d529eb21: with a list or table focused, an unmodified character joins a prefix, and the cursor moves to the first matching row. Unlike macOS, TUIkit binds bare keys: its own q (quit), t (theme), a (appearance) and the help key, plus any bare .keyboardShortcut an app declares. So the first character of a prefix gives way to such a binding (Sources/TUIkitApp/App/InputHandler.swift:345 and typeSelectGivesWay at :476-504). A row whose name starts with a bound letter can't be found by typing that letter first. Any other character is taken whether or not a row matches, as on macOS. The alternative needs every row's text when the key arrives, measured outside a render.

- **Keep: the binding wins on the first letter.** A bound key always does the same thing. A row starting with t is reached with the arrows. *Price:* Free.
- **Decide at key time.** A letter some row starts with goes to type select even if bound. A letter no row answers to passes on to the bindings and page handlers. *Price:* About a day. Each key typed in a focused list measures every row's text, a cost that grows with row count. A bound key's meaning then depends on the list's contents: t cycles the theme in one list and jumps to 'Tokyo' in another.

**Recommended:** Keep. A bound key should never change meaning with the contents of a list, and the alternative costs a day plus a measure of every row on every keystroke.

**If you don't answer:** A bound first letter keeps going to its binding. Rows starting with q, t, a, ? or an app's bare-key letter can't be found by typing that letter first.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md:2760-2799 (B77); /Users/robot/Documents/TUIkit/Sources/TUIkitApp/App/InputHandler.swift:340-350,476-504</sub>

### B77-SELECT

**Type select also selects the row.** Should type select also select the row it lands on, as macOS does, rather than only moving the keyboard cursor?

Type select moves a list's or table's cursor to the matching row (2d529eb21), and selecting it too is a one-line change (DEC B77). Throughout TUIkit, the keyboard cursor is kept apart from the selection: the arrows move the cursor, and Space or Return selects. On macOS the cursor is the selection. That is deviation V2 (Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md:1606-1620), decided by a lane, with its reason 'not recorded', not by you. If only type select selected, it would be the one key that commits a selection while browsing. In a single-selection sidebar, every typed letter would switch the detail pane.

- **Keep: cursor only.** Type select moves the cursor, as the arrows do. *Price:* Free.
- **Select as well.** The matched row is selected, as on macOS. *Price:* One line. It becomes inconsistent with the arrows, and each typed character fires the selection's onChange.
- **Reopen V2 as a whole.** The arrows select too, as on macOS, and type select follows them. *Price:* A separate, larger question touching every list and table. Not priced.

**Recommended:** Keep cursor-only, so type select behaves like the arrows. If you want macOS's behaviour, take it through V2 so the two keys don't diverge.

**If you don't answer:** Type select moves the cursor, and the user presses Space or Return to select.

*(Corrected in the evening re-check.)*

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md:2760-2782 (B77); /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md:1606-1620 (V2)</sub>

### B89

**Controls as gesture recognizers.** Should every control's press become a full gesture recognizer that can wait, fail and be cancelled, as SwiftUI's plain-style button is?

The gesture arena (Sources/TUIkitFoundation/App/GestureArena.swift) ranks the gestures and controls under a press. A gesture is a recognizer, but a control's press handler acts at once. So a control gets the press only after everything ranked ahead of it has given up, and then it owns the press. Two differences from macOS 15.8, both measured (DEC B89). First, a control never fails: a plain button released off itself doesn't fail, so a DragGesture attached to it never hears the end. Second, a control behind an undecided gesture gets the press late: it shows no pressed state under a high-priority tap until that tap fails. macOS's bordered Button ignores attached gestures altogether, so the gap is mostly plain-style buttons and custom controls.

- **Keep (today).** Controls take the press once the gestures ahead give up. The two differences stay documented. *Price:* Free.
- **Make controls recognizers.** Each control's press reports possible, recognized and failed, and accepts a cancel. *Price:* About a day and a half: fifteen-odd controls and every mouse test that reads a control's press. A broad change to the click path, so regression risk is real. No expected runtime cost.

**Recommended:** Keep for now. Build it when a port needs a gesture on a control to hear a press that failed: the cases are narrow, and the change touches every control's click path.

**If you don't answer:** Controls never fail or wait, and the two differences stay as documented.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md:3241-3273 (B89); /Users/robot/Documents/TUIkit/Sources/TUIkitFoundation/App/GestureArena.swift</sub>

### B90

**Gesture distances in points or cells.** Should gesture distances (DragGesture.minimumDistance, LongPressGesture.maximumDistance, a tap's slop) be in points, converted through the terminal's reported cell size, instead of whole cells?

SwiftUI counts Euclidean points: a drag starts at 10, a long press fails past 10, a tap fails past 40. TUIkit counts whole cells along either axis, as Int (Sources/TUIkitFoundation/Gestures/DragGesture.swift:98,114; LongPressGesture.swift:60,71). The defaults are 1 cell, and 5 columns or 2 rows for a tap. So SwiftUI code that writes DragGesture(minimumDistance: 10) asks for ten cells here, which the compatibility guide's §2.1 porting note records. Since the shapes landed (W1, 2026-10-18), TUIkit's API does take CGFloat lengths: a shape's path, lineWidth, cornerRadius, dash and offset, in square units (one column across, about two units per row; §2.12, your 10-12 O0 ruling). So points would not be the first floating-point measurement, but they would be the only one in points, and the only one that needs the terminal's pixel cell size. Interface measurements stay Int cells (§2.1), and the shadows that landed the same day kept whole-cell Int radius and offsets (O6).

- **Keep cells.** Distances stay whole cells; ported values above 1 or 2 need rewriting. *Price:* Free. Consistent with §2.1 and O0.
- **Points via the cell size.** Distances are compared in points, using the terminal's reported cell size (TIOCGWINSZ, CSI 16 t). *Price:* About half a day. Needs a default cell size where none is reported (tmux, some hosts). The parameter type changes to a floating-point value, which reopens §2.1 for these three.

**Recommended:** Keep cells. Every other TUIkit distance is in cells, and O0 just chose cell units for shapes. The porting note covers the trap.

**If you don't answer:** Distances stay in whole cells, so DragGesture(minimumDistance: 10) means ten cells.

*(Corrected in the evening re-check.)*

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md:3300-3318 (B90); /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/SwiftUI compatibility guide.md:176-221 (§2.1); /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/owner-decisions-2026-10-12.md (O0)</sub>

### A48

**Swipe actions: keys and pointer.** How should SwiftUI's .swipeActions be reached in a terminal: as an edge menu opened by a row chord or a horizontal wheel, as buttons revealed in the row, or not at all?

On macOS, a two-finger swipe on a list row reveals its swipe actions, and a full swipe performs the first one. No terminal reports swipes. Terminal.app and iTerm2 send a trackpad's horizontal scroll as the horizontal wheel buttons (answered 2026-10-05). The no-mouse-only rule also needs a keyboard route. Nothing is built: both swipeActions forms are baseline gaps (Tools/APIParity/baseline.json:76,153). The decisions doc lists A48 as 'still yours to answer'.

- **1. Edge menu.** A row chord, bindable through .rowShortcuts (say Ctrl-L for the leading edge and Ctrl-T for the trailing), or a horizontal wheel over the row, opens that edge's actions in the context-menu engine at that edge. A full swipe is not modelled. *Price:* Half a day. The menu, the shortcuts and the wheel already exist.
- **2. Revealed buttons.** The actions slide in over the row's trailing cells, Tab moves through them, and Escape hides them. A second wheel in the same direction is the full swipe. *Price:* A day and a half. The row needs a revealed state that the list draws and memoises, and its focus ring must admit the buttons.
- **3. Decline.** Recorded as a gesture terminals don't have. *Price:* Free. SwiftUI code using .swipeActions won't compile.

**Recommended:** Option 1. A swipe action is a context menu for one edge, and the menu engine already provides the keyboard handling, dismissal and colours.

**If you don't answer:** swipeActions stays unbuilt (two parity gaps), and SwiftUI code that uses it does not compile.

*(Corrected in the evening re-check.)*

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md:746-782 (A48), :44-45; /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/owner-decisions-2026-10-04.md (A48); /Users/robot/Documents/TUIkit/Tools/APIParity/baseline.json:76,153; /Users/robot/Documents/TUIkit/Sources/TUIkitLists/Views/RowShortcuts.swift</sub>

### A53-KEYBOARD-DRAG

**A keyboard route for .draggable.** Should .draggable get a keyboard route, overriding your 2026-07-30 decision to table keyboard drag-and-drop on modality, or should .draggable be recorded as an explicit exception to the no-mouse-only rule?

A .draggable view can only be picked up by the pointer. Only list rows have a keyboard move: Ctrl-R (Sources/TUIkitLists/Views/RowShortcuts.swift:90), which stays inside one control. On 2026-07-30 you tabled keyboard drag between views on modality (Documentation/Input and focus/Keyboard drag-and-drop.md; commit 8ef01ab69). A chord-entered carry has no gesture holding it open and can be forgotten, until Return on some unrelated List completes a drop. On 2026-09-08 you ruled out mouse-only interactions 'unless we make an explicit exception'. The A53 proposal (a chord picks up, arrows and Tab carry, Return drops, Escape returns the item) is exactly such a mode. One keyboard transfer already ships: SwiftUI's own .copyable, .cuttable and .pasteDestination, which act on the focused view (Sources/TUIkitFoundation/Extensions/View+Transfer.swift).

- **Confirm the tabling as an exception.** The no-mouse-only rule records .draggable as its exception, and the docs point apps to .copyable and .pasteDestination for a keyboard route. *Price:* About an hour of docs.
- **Bridge to copy and paste.** A focused .draggable answers Copy with its payload, and a focused drop destination answers Paste. No mode. *Price:* Not priced. It needs .draggable to become a focus stop, which it isn't today. It writes the system clipboard, and a Paste drops whatever text is on it.
- **Build a bounded carry.** The A53 mode, with the three conditions the 07-30 note sets for a revisit: the carried item is drawn with the focus (not in the status bar), the pick-up chord puts it back, and the carry expires on a page change or after a timeout. *Price:* About a day (DEC A53), plus the visibility and expiry work, which isn't priced.

**Recommended:** Confirm the tabling as an explicit exception and document the .copyable/.pasteDestination route. The modality objection still stands, and the same copy-and-paste route is what SwiftUI offers on macOS.

**If you don't answer:** .draggable stays mouse-only with no recorded exception, an open breach of the no-mouse-only rule.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md:851-857 (A53); /Users/robot/Documents/TUIkit/Documentation/Input and focus/Keyboard drag-and-drop.md:1-88; /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/no-mouse-only-interactions.md; /Users/robot/Documents/TUIkit/Sources/TUIkitFoundation/Extensions/View+Transfer.swift:1-80</sub>

### B-BITEMS1-1

**Drop badges for delete and dropDestination.** Beyond the badges ruled on 10-12 (+ for copy, ↗ for link, ⊘ for forbidden, nothing for move), should a .delete drop wear a glyph, and should dropDestination propose .copy so its drags show +?

The drag preview's badge shipped (212d9dc4a, b4e179cf1). A .delete gets no badge, and neither does .cancel, which proposes no drop. The candidates offered for .delete were × (U+00D7, East Asian Ambiguous width) and ✕ (U+2715, Neutral); neither was confirmed. TUIkit's own destinations propose no operation, so they show no badge: dropDestination, a List's or Table's insertion and reorder, and a tab's drop zone (Sources/TUIkitFoundation/Modifiers/DragAndDrop.swift:381-392). macOS is believed to draw + over a dropDestination, but that's unmeasured: an offscreen probe has no window server. Correction to the inventory: the cursor-badge proposal was written. The 10-05 answer was approved by 'Proceed', and you confirmed the glyphs on 10-12 (DEC B10).

- **Keep as shipped.** No badge for .delete, .cancel or TUIkit's own destinations. *Price:* Free.
- **dropDestination proposes .copy.** Every dropDestination drag shows +. *Price:* One line in DropDestinationModifier, plus a probe in a real macOS window first (minutes with computer use, or your hands).
- **Also badge .delete with ✕.** A delete drop shows ✕. *Price:* A width row in the terminal survey, measured on four terminals (about an hour), plus the glyph choice. × risks double width under East Asian ambiguous-width settings.

**Recommended:** Leave .delete bare. Have dropDestination propose .copy only once a real-window macOS probe shows the +, since TUIkit shouldn't claim macOS behaviour it hasn't measured.

**If you don't answer:** Only item-provider drops show badges; .delete, .cancel and TUIkit's own destinations show none.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/Default focus, drop badges and stack spacing (BITEMS1).md:61-97; /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md:1192-1240 (B10); /Users/robot/Documents/TUIkit/Sources/TUIkitFoundation/Modifiers/DragAndDrop.swift:381-392</sub>

### B82

**Spring loading: drawing, delay, colour well.** Which of spring loading's three unbuilt pieces do you want: drawing the pending state, a delay setting, or the colour well's opt-out?

While a drag is in flight, resting the pointer for half a second on a spring-loaded control activates it as a click would (Sources/TUIkitFoundation/Modifiers/SpringLoading.swift). As measured on macOS 15.8, buttons, links, .button toggles and segmented pickers spring-load only under .enabled; a tab view does under .automatic. Three gaps remain (DEC B82). Nothing is drawn: macOS highlights the control while it waits and emphasises it as it fires, but TUIkit's fires with no warning. The delay is fixed at 0.5 s: macOS reads the user's setting, which a terminal app can't. And a ColorPicker's well opens its editor under .enabled because it is built on a button; whether macOS's colour well does was not measured. The keyboard route (Tab and Return mid-drag) already exists.

- **Nothing more.** As shipped. *Price:* Free.
- **Draw the pending state.** The control draws as hovered while it waits and as pressed on the frame it fires. *Price:* About half a day. A drawing change, run under the Stress self-check.
- **Delay setting.** A TUIkit-only environment value for the pause. *Price:* Small, but nothing asks for it yet.
- **Colour-well opt-out.** The ColorPicker's well stops spring-loading. *Price:* About an hour, but it should wait for a macOS measurement.

**Recommended:** Draw the pending state: firing without warning is the gap a user actually feels. Leave the delay setting until an app asks for it, and the colour well until it's measured.

**If you don't answer:** A paused drag fires spring-loaded controls with no visual warning, after a fixed 0.5 s, and a ColorPicker's well opens under .enabled.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md:2918-2983 (B82); /Users/robot/Documents/TUIkit/Sources/TUIkitFoundation/Modifiers/SpringLoading.swift</sub>

### FB9-REDO

**⌃Y as the portable redo key.** Should ⌃Y be bound to redo app-wide, with text fields keeping it as yank, so that some redo key reaches the app on every terminal?

Redo is bound to ⌃⇧Z and ⌃_, which only the kitty protocol tells apart from ⌃Z and ⌃-, and to ⌥_ where Option is sent as Meta (Sources/TUIkitFoundation/Undo/UndoShortcuts.swift:24-46). On Apple Terminal at its defaults none of these arrives, yet the status bar names ⌥_ there (21160e719). ⌃Y arrives as 0x19 on every terminal in raw mode (Sources/TUIkitApp/Rendering/Terminal+LineDiscipline.swift:59-66), and it is redo on Windows and in many Linux editors. But it is also the text controls' yank. TextField and TextEditor keep a one-slot ⌃K/⌃Y kill buffer, separate from the pasteboard (TextFieldHandler.swift:62, :212; TextEditorHandler.swift:134, :794), so the inventory's kill-buffer sub-question is moot. Correction: EVENING-REPORT-1016 said '⌃Y is redo in fields', which is wrong; in fields ⌃Y is yank. You first asked for a canonical redo key on 10-04. Since O13 landed (86994e4f2), an app that declares .commands also has Edit ▸ Redo in its menu bar (TUIkitCommands/MenuBar/SceneOwnCommands.swift:85-87). It is reached by a click, or by F10 (fn-F10 on a Mac keyboard; documented, not yet measured) and the menu's keys. The item shows the status bar's hint key (AppUndoKeys.shortcut(for:), UndoShortcuts.swift:305-318), so ⌥_ on a legacy terminal. Apple Terminal at its defaults still has no redo key, and an app without .commands has no menu bar.

- **(a) ⌃Y redo app-wide; fields keep yank.** ⌃Y redoes everywhere except in a focused text field, where it still yanks. *Price:* Small. The bar's ⌃Y redo hint is wrong while a field has focus, unless the hint follows focus; that is a little more work, since the hints are cached today (d909004f3).
- **(b) ⌃Y redo everywhere; drop yank.** Fields lose yank. *Price:* Small. ⌃K loses its partner, a departure from macOS's emacs keys.
- **(c) No ⌃Y redo; hide an undeliverable hint.** Show no redo hint where no redo key can arrive. *Price:* Small. Apple Terminal at its defaults has no redo key at all.

**Recommended:** (a). ⌃Y is the one portable redo key, and fields keep the macOS yank they already have.

**If you don't answer:** On Apple Terminal at its defaults there is no redo key, and the status bar shows a ⌥_ redo hint that does nothing.

<sub>Sources: /Users/robot/Documents/TUIkit-session-notes/plan/MORNING-QUESTIONS-1016.md:24-40; /Users/robot/Documents/TUIkit-session-notes/plan/EVENING-REPORT-1016.md:7; /Users/robot/Documents/TUIkit/Sources/TUIkitFoundation/Undo/UndoShortcuts.swift:24-82; /Users/robot/Documents/TUIkit/Sources/TUIkitTextInput/Focus/TextFieldHandler.swift:62,212; /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/owner-decisions-2026-10-04.md (A1)</sub>

### B-KS-1

**Status-bar keys in macOS spelling.** Should a status-bar item's single-character key be drawn the way a macOS menu draws it ('Q quit', '⇧N new') instead of as the app typed it ('q quit', 'N new')?

Since lane KS, one formatter names every key TUIkit shows, macOS-style: menu shortcut columns, KeyboardShortcut.displayString, the Shortcut constants, and the undo and redo hints. You asked on 10-05 for macOS symbols and order 'wherever possible'. A StatusBarItem's own shortcut string is still drawn as typed (Sources/TUIkitFoundation/StatusBar/StatusBarItem.swift:201-202). That string does three jobs: it is what the bar draws, it is the bound key (Shift spelled as the letter's case), and it identifies the item. So TUIkit's quit item reads 'q quit' next to a '⌃Z undo' hint. Drawing the key the menu's way needs the bar to draw from the bound key rather than from the string. A StatusBar view now exists (Sources/TUIkitChrome/StatusBar/StatusBar.swift), but it still draws the string.

- **Keep as typed.** The TUI convention, where lowercase means no Shift. *Price:* Free. Styles stay mixed beside the ⌃Z hints.
- **Menu spelling for single-character items.** Q, ⇧N. Multi-character strings such as '1-9' and '↑↓' stay unchanged. *Price:* About half a day once the bar draws from the bound key. Every app's status bar changes, and a TUI user may read Q as needing Shift.

**Recommended:** Menu spelling. It completes your 10-05 request and ends the mixed styles within one bar.

**If you don't answer:** Status-bar items keep showing keys as typed ('q quit') beside menu-style hints such as '⌃Z undo'.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/Input, clipboard and text editing/Keyboard shortcut symbols (KS).md:26-58; /Users/robot/Documents/TUIkit/Sources/TUIkitFoundation/StatusBar/StatusBarItem.swift:181-260; /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/owner-decisions-2026-10-04.md (key symbols, 10-05)</sub>

### O13-KEYS

**Menu bar keys.** For the menu bar that O13 has now landed on main, should the keys stay the ones you accepted on 10-04 (F10, Alt-letter, a click), with no extra chord and no TUI-only menuBarVisibility for now?

On 10-04 you accepted A28's answers, including F10, Alt-letter and a click to open the menu bar. On 10-05 you declined F-keys for the mouse hand-off key as 'prime and unreliable' (the fn setting and OS shortcuts decide whether they arrive). REFO Q11 asks whether that reasoning reopens F10 for the menu bar, and it hasn't been answered (Documentation/Working notes/REFO/notes.md:787-803, :998-1000). Opening a menu bar is F10's conventional job (Windows, GTK). On a Mac keyboard it needs fn unless F-keys are set as standard. Alt-letter needs Option sent as Meta, which Apple Terminal doesn't do by default. Commands with shortcuts work with the bar closed. The only chord left is ⌃^, which you called 'maybe too obscure'; Apple Terminal sends it only for ⌃⇧6. menuBarVisibility(.hidden) would keep commands live and show the bar only while F10 holds it open; it is TUI-only, and REFO says to build it only if an app wants it. The menu bar landed on main on 2026-10-18 (module TUIkitCommands; 6d627ee4e…439afd6a6) with exactly the 10-04 keys: F10, Alt with a title's first letter, and a click (3215311d4). The app's own menu takes no letter (39c953758; decisions B-O13-5). There is no ⌃^ and no menuBarVisibility, and the page's own F10 handler is asked before the bar's (439afd6a6). Its survey entry (Terminal compatibility survey.md:5229-5258) still records F10 as documented but not yet measured.

- **The 10-04 keys.** F10 or fn-F10, Alt-letter, a click, plus each command's own shortcut. *Price:* About an hour to measure F10 and fn-F10 in Terminal.app, iTerm2 and Ghostty with cat -v.
- **Add ⌃^.** A chord route as well. *Price:* Small. Obscure, and on Apple Terminal it is really ⌃⇧6.
- **Add menuBarVisibility.** A TUI-only scene modifier for commands without a permanent row. *Price:* Not priced. New TUIkit-only API.

**Recommended:** The 10-04 keys. The 10-05 objection was about spending F-keys on a minor feature, and opening a menu bar is F10's standard use. Measure F10 (the lane landed without measuring it), and add a chord or menuBarVisibility only if an app asks.

**If you don't answer:** The menu bar keeps the keys it shipped with (F10, Alt-letter, click), with no extra chord and no menuBarVisibility.

*(Marked decidable by its writer; a skeptical second reading sent it to you: REFO Q11 put this to you and is still unanswered. You yourself called F-keys 'prime and unreliable' on 10-05, so whether F10 stays is your call on how keys should feel.)*

*(Corrected in the evening re-check.)*

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/Working notes/REFO/notes.md:573-592,719-838,998-1000; /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/owner-decisions-2026-10-04.md (A28 answers; A13.2 10-05); /Users/robot/Documents/TUIkit-session-notes/plan/LANE-O13.md; Documentation/SwiftUI parity/Decisions/Menus, toolbars and chrome/The menu bar (O13).md (B-O13-5)</sub>

### SCROLLX-UPSTREAM

**Propose a scroll-delta mouse mode to kitty.** Do you want to propose, or back, a scroll-delta-and-phase mouse mode upstream with kitty, or skip it?

No terminal protocol carries a scroll delta, phase or velocity. So B27's scroll velocity is (0, 0) at start and end, and .decelerating is never produced. You ruled on 10-12 not to normalise wheel speed per host (da18d5b87). kitty's maintainer called a new pointer-events protocol with scroll support 'the proper solution' and put it on their to-do list (kitty #10273, 2026-07-21), and a ghostty-org member and a Codex developer have asked for the same. It's low priority and unblocks nothing soon (SCROLLX notes §6.5, §7.5). Documentation/Future options.md:303-320 already parks it. Filing upstream or commenting there is yours to do.

- **Skip.** Revisit if kitty starts the protocol. Future options already records the trigger. *Price:* Free.
- **Back kitty #10273.** A short use-case comment: delta, device class, phase. *Price:* Minutes of your time. Signals demand without committing to anything.
- **Write a full proposal.** A specification plus a reference parser in TUIkit. *Price:* Days of work, then months of waiting. tmux, Apple Terminal and Warp wouldn't send it unless they adopt it.

**Recommended:** Skip for now, and join kitty's effort when it starts; SCROLLX found joining cheaper than leading. A one-comment +1 is fine if you want to signal interest.

**If you don't answer:** Nothing is filed. Scroll velocity stays (0, 0), and .decelerating is never produced.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/Working notes/SCROLLX/notes.md:954-1066; /Users/robot/Documents/TUIkit/Documentation/Future options.md:303-320; /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/owner-decisions-2026-10-12.md (wheel speed)</sub>

### B-HELP-2

**A keyboard route to non-focusable help.** Should '?' pressed when the focused control has no help show every help panel on screen, with '?' again hiding them, as the keyboard route to the help on views that can't take focus?

You ruled on 10-12 that help(_:) must work on views that can't take focus, by hover and by any app-wide help feature. Hover works, and .tooltips(.always) shows every panel. But '?' and .onFocus act only on the focused control (TooltipState.swift:566-576, toggleKeyboardReveal; the help key is declared at :238), and with no help there, '?' falls through unconsumed. So a keyboard user reaches a Text's help only if the app turns on .always, which leaves non-focusable help mouse-only, against the no-mouse-only rule. A focused text field types '?' itself, so the route can't work while one has focus.

- **'?' reveals all when the focus has no help.** '?' toggles every panel on screen. *Price:* Half a lane-day to one, with tests. The reveal must reach views served from the render cache (a screen-wide flag that clears the memo when it changes). The key may be consumed only when there is help to show, so every help(_:) must register in a way that replays from the memo. '?' gains a second meaning.
- **The same on F1.** F1 toggles every panel. *Price:* The same work. F1 is free and isn't typed by fields, but you called F-keys unreliable on 10-05.
- **Leave it to apps.** An app offers .tooltips(.always) as a setting, as the Example's Help page does. *Price:* Free.

**Recommended:** '?' reveals all. It closes the mouse-only gap that your 10-12 ruling and the no-mouse-only rule both point at, using the help key users already know.

**If you don't answer:** Non-focusable help stays keyboard-reachable only where the app turns on .tooltips(.always), and '?' with no help on the focused control does nothing.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/Presentation and windows/Help on views that cannot take the focus (HELP).md:1-12,211-228; /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/owner-decisions-2026-10-12.md ([17]); /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/tooltips-unbuilt-and-the-help-key.md</sub>

## Text, editing and the clipboard

### A42-Q8

**Formatting keys in the rich-text editor.** In the rich-text TextEditor (A42), should bold, italic and underline be reached only through the context menu (Shift-F10 or right-click), with key chords coming only when an app declares SwiftUI's TextFormattingCommands in the O13 menu bar? Or should the editor have default chords of its own?

You approved A42 (rich-text editing) on 2026-10-04. It is not built: Sources has no AttributedTextSelection and no attributed editor. The RICHTEXT lane brief ships the menu route and leaves chords to you. A terminal never delivers ⌘B, ⌘I or ⌘U, and TUIkit maps ⌘ to Ctrl, so they would land as Ctrl-B (the editor's back-a-character), Ctrl-I (the same byte as Tab, so it can never arrive) and Ctrl-U (erase the line). Your 09-23 ruling already lets an app's declared shortcut win over the Emacs chords. Your 10-04 note on undo said keys must work without the menu bar, which is why this is your question. The O13 menu bar, landed on main on 2026-10-18 (module TUIkitCommands, 6d627ee4e…439afd6a6), leaves TextFormattingCommands out. The type does not compile, and the bar records it as owed with A42 (C-O13-3), so the menu-bar route to chords arrives only when A42 adds TextFormattingCommands to it.

- **Menu now, chords through TextFormattingCommands.** Shift-F10 or right-click offers Cut, Copy, Bold, Italic, Underline and Strikethrough. An app that declares TextFormattingCommands (in O13's menu bar, now on main) gets Ctrl-B and Ctrl-U, which win over the Emacs chords. Italic stays in the menu, since Ctrl-I is Tab. *Price:* Nothing beyond A42 and O13. Until an app opts in, formatting by keyboard takes two or three presses.
- **Default chords in every rich editor.** Ctrl-B and Ctrl-U format with no menu bar, plus a TUI-only key for italic. *Price:* Small. Rich editors lose Emacs back-a-character and erase-line, someone has to choose an italic key, and SwiftUI has no such default.
- **Chords only under the kitty keyboard protocol.** On terminals that speak the protocol, Ctrl-Shift-B, I and U arrive as themselves and can format without touching the Emacs keys. *Price:* Small. Does nothing on terminals without the protocol (Apple Terminal), where the menu stays the only route.

**Recommended:** Menu now, chords through TextFormattingCommands. That is how SwiftUI adds the shortcuts, it costs nothing extra, and it keeps the Emacs keys you called a bonus.

**If you don't answer:** The A42 lane ships the Shift-F10 and right-click menu with no chords, and the question stays recorded as an A entry.

*(Corrected in the evening re-check.)*

<sub>Sources: Documentation/SwiftUI parity/Design studies/Text selection and editing design study, A13, A42 and A43 (2026-10-04).md:842-846 (§10 Q8), §7.1; Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md:688-711 (A42); Documentation/SwiftUI parity/Decisions/Menus, toolbars and chrome/The menu bar (O13).md:230-235 (C-O13-3); /Users/robot/Documents/TUIkit-session-notes/plan/LANE-RICHTEXT.md; memory/owner-decisions-2026-10-04.md:13-16 (A1: keys must work without the menu bar); memory/owner-bug-batch-2026-09-23.md:63-65 (app shortcut beats Emacs chords); Sources/TUIkitFoundation/Modifiers/ContextMenuPresentation.swift:72 (Shift-F10); Sources/TUIkitTextInput/Focus/TextEditingCommand.swift:54 (Option-B taken)</sub>

### B-PASTE-1-EDITOR

**Text storage and undo for very large documents.** Should TextEditor and TextField be redesigned for large text: undo that records edits instead of whole-text copies, and possibly UTF-8 storage? If so, should it be folded into A42's storage refactor once the 16 MiB paste has been measured?

Since your 10-12 ruling [4] (accept pastes of any size), a paste arrives whole. Estimated from the code, not measured: TextEditor keeps its text as lines of Character, at 16 bytes each, so 16 MiB of ASCII takes about 256 MiB and the insert peaks near 300-600 MiB. Both controls' undo (TextUndoHistory.swift:48-58, which still stores whole texts) keeps up to 50 copies of the document, up to 800 MiB, and every key walks the document: the editor joins its lines into one String and compares it with the text before the key (TextEditorHandler.swift:203, :336). Since the INPUT lane (8112629ea, 2026-10-18), a run of typing is one undo step, so the 50 copies are 50 steps (a run of typing, a paste, a cut, a forward delete) rather than 50 keys. The measurement (PASTE-MEASURE) is still owed. A42's first step, R1, already turns every edit into a range replacement and makes TextUndoHistory generic.

- **Measure first.** Run PASTE-MEASURE in a release build: 16 MiB into a focused TextField, and into a TextEditor over a long document with a few keys typed after. *Price:* Small. No code changes, and the costs above stay meanwhile.
- **Undo as edits, inside A42's R1.** While R1 turns edits into range replacements, record each undo step as the replaced range and its old text rather than the whole document. Both controls share TextUndoHistory, so both benefit. *Price:* Not priced, on top of R1's day. Removes the up-to-800 MiB of undo copies and the per-key walk of the document. Storage stays at 16 bytes a character.
- **Full redesign.** UTF-8 storage instead of lines of Character, incremental wrapping, and undo as edits. *Price:* XL, not priced. Touches every edit, the wrap layout and drawing, and needs A/Bs on the notes and text-editor scenarios.
- **Leave it.** Document the memory cost of very large texts. *Price:* Free, but a large paste or document can take hundreds of MiB.

**Recommended:** Measure first, then do undo-as-edits inside R1: it is the big, cheap win. Take on the UTF-8 storage redesign only if the measurement shows a 16 MiB document is unusable.

**If you don't answer:** Nothing changes. Large texts keep the memory costs above, and R1 keeps whole-text undo.

<sub>Sources: Documentation/SwiftUI parity/Decisions/Input, clipboard and text editing/Large pastes and over-long input sequences (PASTE).md:126-188; memory/owner-decisions-2026-10-12.md:12 ([4] pastes of any size); Sources/TUIkitTextInput/Focus/TextUndoHistory.swift:48-58, :128-141; Sources/TUIkitTextInput/Focus/TextEditorHandler.swift:198-203 (lines of Character); Design studies/Text selection and editing design study … (2026-10-04).md:664-680, :997-1001 (R1); /Users/robot/Documents/TUIkit-session-notes/plan/QUEUE.md:33 (measurement owed)</sub>

### B-D4X-7-17

**Text selection in a Table: one cell or the whole row.** With text selection enabled on a Table, should a selection stay inside one cell, as macOS keeps it, or keep TUIkit's row-wide selection that crosses columns?

A Table files one selectable region per row that spans every column (Table.swift:3809-3838), so a selection crosses columns (B-D4X-7). There is also a leak (B-D4X-17): `.textSelection(.enabled)` on one column's Text makes the whole row's text selectable. By B-D4X-7's rule, a click on another column's text then selects nothing, and no longer selects the row. macOS keeps a selection inside one Text, and so inside one cell (measured on 15.8). Your 10-04 hold on exact per-Text selection (A13.5) covers a larger design. On 10-06 you asked to probe draggable rows and match macOS.

- **Fix the leak; a table-wide scope still crosses columns.** The table files each column's geometry with its rows. Only cells whose content enabled selection can be selected, and each selection stays in its cell. A `.textSelection(.enabled)` around the whole table still selects across columns. *Price:* About half a day (B-D4X-17's fuller version). Keeps TUIkit's ability to copy a row in one drag, which differs from macOS for table-wide scopes.
- **Match macOS fully.** As above, and every selection stays in one cell, whatever enabled it. *Price:* About two hours more on the same work. A drag can no longer copy a whole row.
- **Leave it.** Selection stays row-wide, and one cell's modifier keeps reaching its siblings. *Price:* Free, but while one column is selectable, a click on another column's text does nothing.

**Recommended:** Fix the leak whatever else you decide: a modifier reaching past its own view is a bug, and it breaks row clicks. For table-wide scopes, keep crossing columns (option 1). TUIkit's screen selection already crosses from one Text to the next everywhere else (deviation T6), and exact per-Text selection is on hold.

**If you don't answer:** Table-wide selections keep crossing columns, as T6 records. The leak should still be fixed as a bug, since that needs no ruling.

<sub>Sources: Documentation/SwiftUI parity/Decisions/Input, clipboard and text editing/Clipboard, screen selection and the wrapping editor (D4X).md:101-182, :385-403; Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md (T6); Sources/TUIkitTables/Views/Table.swift:3809-3838; Sources/TUIkitFoundation/App/MouseEventDispatcher+PressRoles.swift:40-59; memory/owner-decisions-2026-10-04.md:109-112 (A13.5 held), :170-172 (match macOS on draggable rows); /Users/robot/Documents/TUIkit-session-notes/morning-questions.md:21-24</sub>

### D4X-LOCALITY

**Copying under GNU screen, tmux passthrough and other session keepers.** Should TUIkit get copies through the session keepers it currently gives up on: GNU screen's wrapper sequence, tmux's wrapper sequence when allow-passthrough is on, and asking a keeper which clients are attached?

Under GNU screen nothing is copied, even at the desk. Screen passes an app's clipboard escape (OSC 52) on only inside its own wrapper sequence, a DCS passthrough, which TUIkit doesn't send (TerminalClipboardSupport.swift:59, :160). So a copy from iTerm2 through screen, which pbcopy used to make, now says 'Not copied'. Under tmux, OSC 52 is sent only when set-clipboard is on, and the default ignores it. Neither a nested tmux nor screen is asked for its clients, so neither counts as local at the desk. Every case fails safe: the terminal's own selection and paste, and TUIKIT_OSC52=1, still work.

- **Screen passthrough.** Wrap OSC 52 in screen's DCS sequence, chunked under screen's string limit. *Price:* About half a day plus a probe row. Unmeasured, including screen 5.
- **tmux passthrough.** Wrap OSC 52 in tmux's DCS sequence when allow-passthrough is on, so it reaches the outer terminal whatever set-clipboard says. *Price:* About half a day with a probe row. It helps only users who turned allow-passthrough on.
- **Ask keepers for their clients.** Query screen's and zellij's session sockets and an outer tmux's client list, and trace each client back to its terminal, as is done for tmux. *Price:* About half a day per keeper. Not possible for dtach or abduco, which keep no client list.
- **Leave it.** As today: these cases fail safe. *Price:* Free, but screen users get no copies at all.

**Recommended:** Screen passthrough first, checked with the probe, because screen copies nothing anywhere today. tmux passthrough next. Client queries only if someone asks.

**If you don't answer:** Copies under screen, and over ssh under default-configured tmux, keep reporting 'Not copied'. Nothing breaks.

<sub>Sources: Documentation/SwiftUI parity/Decisions/Input, clipboard and text editing/Clipboard, screen selection and the wrapping editor (D4X).md:42-50 (B-D4X-2), :289-306 (B-D4X-13), :434-446; Sources/TUIkitTerminalHost/Rendering/TerminalClipboardSupport.swift:59, :160; Documentation/Terminals/Terminal compatibility survey.md:5915-5966</sub>

### B85-KEYBOARD

**Links inside a Text as keyboard-reachable controls.** Should links inside a Text (from Markdown or an attributed string) become focusable controls: Tab stops, Return or a click to show or copy the link, and Shift-F10 for the link menu?

A link inside a Text is drawn tinted and underlined, with an OSC 8 hyperlink, but takes no focus and no click (DEV T4). On a terminal without OSC 8, such as Apple Terminal, its destination can't be reached. The Link control has since gained the Show Link popover, the Copy Link / Copy Label / Copy as Markdown menu (N1, your 10-16 request for a menu on every hyperlink) and .linkActivation(.copy) (N2), but none of these reach links inside a Text. SwiftUI's text links are clickable. A click-only version would break the no-mouse-only rule, so the keyboard half is required.

- **Leave it.** Links inside a Text stay hyperlinks only. *Price:* Free; T4 stands.
- **Full control.** Each link registers a focus stop (text-link-<identity path>#<run>) and breathes when focused. Return and a click do what Link does, and Shift-F10 opens Link's menu. *Price:* About two days (the decision doc's price, set before Link's menu existed to reuse). Every page with inline links gains Tab stops, which macOS doesn't add by default (unmeasured).
- **URL on the row only (B85-LINKDISPLAY).** Honour .linkDisplay so the URL can be read and selected; no focus or activation. *Price:* About half a day.

**Recommended:** Full control, after B85-LINKDISPLAY. It completes your 'menu on every hyperlink' request for the links that still have none.

**If you don't answer:** Links inside a Text stay hyperlinked labels only, and Apple Terminal users can't reach their destinations.

<sub>Sources: Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md:3112-3131 (B85); Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md:842-856 (T4); git f653ca736, 5335b8733, 20e013827, c695b9787 (Link's menu, .linkActivation, the URL modes); /Users/robot/Documents/TUIkit-session-notes/plan/QUEUE.md:666-667 (N1, N2); memory/no-mouse-only-interactions.md</sub>

### B86

**Markdown: full HTML entity table and link reference definitions.** Should TUIkit's Markdown parse close its two known differences from Foundation's: all 2,125 HTML named entities, and link reference definitions?

Foundation's Markdown parser exists only on Apple platforms, so TUIkit parses Text keys with its own InlineMarkdown. It agrees with Foundation on a 138-case table and on 550,000 random strings, except in two places (DEV T3). Named entities beyond about 140 common ones are drawn as written (`&Aacute;`), and a `[label]: destination` line isn't consumed. The entity table is in TUIkitStrings, which every app that draws Text links.

- **Leave both.** T3 keeps recording both differences. *Price:* Free.
- **Link reference definitions.** Consume definition lines and resolve `[label]` links. *Price:* About half a day. No size cost.
- **Full entity table.** All 2,125 names, from a generated table. *Price:* About an hour. Adds 20 KB of generated source to a module every app links; compiled size unmeasured.

**Recommended:** Leave both until a translation needs them, as the decision doc says. If you want the parse identical, do reference definitions first, since they cost no bytes.

**If you don't answer:** Both differences stay, recorded in T3.

<sub>Sources: Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md:3136-3204 (B86); Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md (T3); Sources/TUIkitStrings/Rendering/InlineMarkdownParser+References.swift:100-110; memory/compile-time-and-binary-size-request.md</sub>

### B51-LIVE

**Keep live text live where an API takes it as a string.** Should the APIs that take a Text only for its string keep a live Text (a timer, a relative date) updating, as SwiftUI does? These are navigationTitle(Text), help(Text), dismissalConfirmationDialog's title, and the titles still kept as strings.

A live Text redraws its words every frame, but these consumers read it once, when they are built (DEV T5; View+Preferences.swift:189 keeps only title.content). On 10-04 you said making the consumers live was separate from B51's formatting A/B, and you didn't rule on it. Since B87 (10-15), Toggle, Label, Link, Section, Picker and others build their label as Text(titleKey), and since PARITYMISC (585bb31d7, 10-18) so does a TextField's title, which the field renders as its placeholder when it has no prompt. So their keys probably stay live now (unverified). Still strings: Button and ColorPicker titles, a SecureField's title and a value TextField's title, TableColumn headers and Tab titles (now the key's Markdown words, titleWords), navigationTitle and help. That SwiftUI keeps them live is inferred, not measured.

- **Leave it.** These consumers keep reading a live text once. *Price:* Free; T5 records it.
- **Measure SwiftUI, then match.** For each consumer SwiftUI keeps live, store and draw the Text. A changing title then re-measures the bar it sits in. *Price:* About two hours per consumer. Apps with live titles pay a bar re-measure on each change; others pay nothing.

**Recommended:** Leave it until an app asks; none has. Meanwhile, check that B87's controls really are live now.

**If you don't answer:** Live titles in these places stay at their value from when they were built, until the view around them is rebuilt.

<sub>Sources: Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md:1912-1937 (B51), :3205-3248 (B87 shipped; TextField's title 2026-10-18); Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md:857-868 (T5); memory/owner-decisions-2026-10-04.md:102; Sources/TUIkitFoundation/Extensions/View+Preferences.swift:188-189; Sources/TUIkitFoundation/Views/Toggle.swift:478-484</sub>

### DEPR-CATCHALL

**The catch-all LocalizedStringKey interpolation SwiftUI deprecated.** For `Text("… \(anything)")`, should TUIkit keep its silent catch-all interpolation? Or add typed overloads and then mark the catch-all deprecated, as SwiftUI does on the 26 SDK? Or add typed overloads and then remove it?

Your 10-12 ruling [21] says not to implement deprecated SwiftUI API. TUIkit's appendInterpolation(_ value: some Any) (LocalizedStringKey.swift:487) mirrors a catch-all that the macOS 26 SDK added already deprecated: it warns that the result is an unlocalized debug description. The 15.5 SDK had no catch-all. TUIkit has no String or number overloads, so String, Int and the other numbers all go through it; removing it first would stop `Text("Count: \(n)")` localizing. Since Text + Text was removed (c50e98b10), a gradient-styled fragment interpolated into a key also lands here and is written as its description, as SwiftUI's deprecated catch-all writes it (B-PARITYMISC-4). Under (b) that would at least warn, as SwiftUI does. The DEPR audit left the choice to you, with no recommendation.

- **(a) Keep it silent.** Record it as an exception to [21]. *Price:* Free, but it is an exception only you can grant.
- **(b) Typed overloads, catch-all deprecated.** Add SwiftUI's typed overloads, then mark the catch-all deprecated with SwiftUI's message. *Price:* M. Same lookup and warning as SwiftUI 26, and the zero-warnings rule moves TUIkit's own uses onto typed forms. It keeps a deprecated declaration; the audit counted that as meeting [21], because SwiftUI uses the deprecation to warn of misuse.
- **(c) Typed overloads, catch-all removed.** As (b), then delete the catch-all. Any other value falls back to the verbatim String initialiser, as it did before SDK 26. *Price:* M. The strictest reading of [21]. Text built from such values is no longer looked up for translation, unlike SwiftUI 26, and gives no warning.

**Recommended:** (b). It matches SwiftUI on the current SDK, warning included, and the typed overloads are needed either way.

**If you don't answer:** The catch-all stays live and silent: an exception to [21] that nobody has approved.

<sub>Sources: Sources/TUIkitFoundation/Localization/LocalizedStringKey.swift:486-510; Documentation/SwiftUI parity/Decisions/Small parity items (PARITYMISC).md:128-151 (B-PARITYMISC-4); /Users/robot/Documents/TUIkit-session-notes/DEPR/notes.md:13, :163-167, :258; /Users/robot/Documents/TUIkit-session-notes/plan/QUEUE.md:21, :554; memory/owner-decisions-2026-10-12.md:42-43 ([21]); memory/zero-compiler-warnings.md</sub>

### A-TEXT2-1

**A gesture that widens a container's selection to the pane.** Since #10, a drag selection begun inside a bordered container stays inside it. You asked for suggestions for getting past that from the mouse. Option (a rectangle), Shift (a rectangle's moving corner, and many terminals' own bypass) and Control (the secondary click) are taken. What already works: start the drag on the container's border, or in the blank cells beside it, and it crosses the container as it always did.

- **1. Nothing beyond the border** (shipped). *Price:* None. A drag from the middle of a card's text cannot reach the page.
- **2. A drag that leaves the container by more than N cells widens to the pane.** *Price:* Small to build, but ambiguous: a drag to "the end of the card" overshoots the bottom border by a row or three as a matter of course, so a fast drag crosses any N by accident and the selection jumps out to the page mid-gesture.
- **3. A double-press-and-drag on the border selects the whole box and extends from there.** *Price:* Small; a new rule to learn.

**Recommended:** Option 1. `.textSelectionScope(.pane)` restores the old reach for an app that wants it everywhere.

**If you don't answer:** Only a drag begun on the border or outside the box reaches the page.

<sub>Sources: Documentation/SwiftUI parity/Decisions/Input, clipboard and text editing/Ctrl-U, selection kept to a container, undoable reorders (TEXT2).md, A-TEXT2-1</sub>

## Visuals, animation and colour

### A27

**Pixel effects: transforms, mask, drawingGroup, linear blending.** For Wave 16's leftovers, do you take the recommended set (decline the six transforms, ship mask(alignment:_:) at cell coverage, ship drawingGroup as compositingGroup)? And should linear-light blending be added so that drawingGroup(colorMode: .linear) is honoured rather than ignored?

The decisions doc names A27 as one of the three items still yours to answer (SwiftUI API completion decisions.md:44-45, :481-532). None of scaleEffect, rotationEffect, rotation3DEffect, projectionEffect, transformEffect, mask(alignment:_:) or drawingGroup exists in Sources, and all eight are still gaps in Tools/APIParity/baseline.json (:132-168; the VisualEffect spellings A39 waits on are :170-174). A glyph cannot be scaled or turned, so view transforms can only be declined or faked. Since W1 landed on 10-18, shapes themselves can be rotated, scaled and transformed (Shape.rotation/scale/transform, rasterized per half cell), but scaleEffect's receiver is any view. W1 also shipped clipShape(_:style:). It keeps a cell where the shape covers at least half of it and clears the rest (Shapes (W1) B-W1-11; deviation C9). W1's owed list names that rule as the natural one for mask. That bears on option 1. Its rule (keep the content wherever the mask draws a glyph or a background) would make .mask(Circle()) keep edge cells that .clipShape(Circle()) clears, because the rasterizer draws a partial edge as ▀/▄. Using the clip rule, or the coverage as alpha, keeps the two consistent, as they are in SwiftUI. mask and drawingGroup do have honest per-cell readings. You asked on 10-04 whether linear blending was possible. The 10-05 answer was yes, and cheap (decode, blend, re-encode through lookup tables; Color+Compositing.swift already decodes sRGB to linear), but nobody decided it. A39 follows this answer. While transforms are declined, a scrollTransition or visualEffect closure that scales its content fails to compile, even though both modifiers ship.

- **1. Recommended set; .linear documented as ignored.** Decline all six transforms. Ship mask: a cell where the mask draws a glyph or a background keeps the content at the mask's alpha, and a blank cell with no background masks out. Ship drawingGroup as compositingGroup, with .linear and .extendedLinear blended non-linearly and documented. *Price:* About half a day for mask, plus a small amount for drawingGroup. Ported scaleEffect calls fail to compile and get removed. At runtime .linear quietly blends as non-linear.
- **2. Option 1 plus linear blending.** As option 1, but inside a drawingGroup(colorMode: .linear) subtree the compositor blends in linear light. extendedLinear is the same, clamped at the end on an SDR terminal. *Price:* Called cheap in the 10-05 answer; not priced in hours. Needs a per-group flag on the opacity path. No cost to code that doesn't use it.
- **3. scaleEffect as a reveal.** Draw scaleEffect the way the .scale transition does, as a reveal from the anchor; the other transforms are declined. Mask and drawingGroup as in option 1 or 2. *Price:* Half a day. A scale too close to 1 to reveal a whole cell (a 0.95 press effect) draws unchanged unless a threshold rule is invented, which is the silent no-op rule 2 forbids.
- **4. Decline everything.** Transforms, mask and drawingGroup all stay refused. *Price:* Free. More ported code fails to compile.

**Recommended:** Option 2. Declining the transforms keeps rule 2 (nothing is silently ignored), mask and drawingGroup have honest cell readings, and linear blending is cheap and makes drawingGroup's colorMode honoured instead of documented as ignored.

**If you don't answer:** All eight stay as gaps that fail to compile, A39 keeps waiting, and blending stays in encoded sRGB only.

*(Corrected in the evening re-check.)*

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md:44-45, :481-532; /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/SwiftUI API completion plan.md:149; /Users/robot/Documents/TUIkit/Tools/APIParity/baseline.json:132-174; /Users/robot/Documents/TUIkit/Sources/TUIkitStyling/Color/Color+Compositing.swift:16; /Users/robot/Documents/TUIkit/Sources/TUIkitEffects/Geometry/ScrollTransition.swift; /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/owner-decisions-2026-10-04.md (A27 question)</sub>

### A34

**Blur-replace transition.** Should BlurReplaceTransition ship as a scale plus a fade (the blur drawn as a fade), stay out, or also get a cell 'blur' made of shade blocks?

SwiftUI's blurReplace combines a blur with a scale. TUIkit already has the scale half, the .scale reveal; blur is declined in the parity map's per-pixel family. The decisions doc lists A34 as still yours (SwiftUI API completion decisions.md:540-568). It recommends option 2 once Wave 16 gives blur no cell reading of its own, and Wave 16 has since declined blur. All nine symbols are gaps in baseline.json (lines 30-36, 115-116).

- **1. Leave it out.** Code that uses .blurReplace fails to compile. *Price:* Free.
- **2. Scale plus fade.** .downUp is the reveal from the centre plus a fade. .upUp does the same on insertion and only fades on removal, because a reveal cannot grow past its slot. The doc comment says the blur is drawn as a fade. *Price:* About an hour with tests. Uses the existing opacity compositor.
- **3. Option 2 plus a cell blur.** Also soften the glyphs on the way out, with shade blocks (▓▒░) or the dim attribute. *Price:* About a day. Nothing else in TUIkit draws this way. Shares work with O5's frosted add-on.

**Recommended:** Option 2. At cell resolution a blurred view reads as a faded one, so the gap closes for about an hour of work.

**If you don't answer:** It stays out, and .blurReplace in ported code fails to compile.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md:44-45, :540-568; /Users/robot/Documents/TUIkit/Tools/APIParity/parity-map.json:178-199; /Users/robot/Documents/TUIkit/Tools/APIParity/baseline.json:30-36, :115-116</sub>

### B61

**Per-leaf content dissolve in Text and Image.** Should the content-transition dissolve move into Text and Image, with each reading \.contentTransition as SwiftUI's leaf views do, built as the first piece of A40's cheaper-design study?

Today .contentTransition(_:) dissolves the whole drawing of the subtree it wraps (Sources/TUIkitEffects/Modifiers/ContentTransitionModifier.swift; SwiftUI API completion decisions.md:2272-2306; Deliberate deviations A4). So an inner .contentTransition(.identity) does not exempt its part, as it would in SwiftUI. The fuller version, a dissolve per leaf, is about a day plus an A/B. A40's dissolve by default kept a drawing for every Text and cost up to +500% (fanout). On 10-15 you asked only for a cheaper design. A per-leaf dissolve that keeps drawings only under a written .contentTransition is the natural first piece of that design.

- **1. Keep the subtree dissolve.** Deviation A4 stays as documented. *Price:* Free.
- **2. Per-leaf dissolve.** Every Text and Image reads one environment value per draw. A leaf keeps its last drawing only when an ancestor set a transition other than .identity, so an inner .identity is exempt. *Price:* About a day plus an A/B. One environment read per Text and Image draw on every page, and a record per changed leaf under the modifier.
- **3. Wait and bring it back with A40.** Same work as option 2, but presented together with A40's study. *Price:* Same cost, later.

**Recommended:** Option 2, landed if the A/B on text-heavy scenarios (textwall, fanout, menus) is within a few percent. It adds SwiftUI's leaf semantics, and A40's study needs it as a base.

**If you don't answer:** The subtree dissolve stays.

*(Marked decidable by its writer; a skeptical second reading sent it to you: This is the first piece of the A40 per-Text design you reserved ('we could consider it'). It adds a per-Text and per-Image cost on every page, and your bar for that kind of cost is about 1%, not the 'few %' the entry cites.)*

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md:628-671, :2272-2306; /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md:1203-1216; /Users/robot/Documents/TUIkit/Sources/TUIkitEffects/Modifiers/ContentTransitionModifier.swift; /Users/robot/Documents/TUIkit-session-notes/plan/QUEUE.md (2026-10-15 07:30 and 07:50 OWNER, A40); /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/perf-regression-tolerance.md</sub>

### B95

**Gradients with two samples a cell (▀) on glyph-only terminals.** On terminals that draw no pictures, should gradient views use the upper half block (▀) to show two colour samples per cell, doubling vertical resolution?

Gradient views, .background(gradient) and rectangle-family fills take one colour sample per cell on terminals that only draw glyphs. Terminals that take pictures get a picture (SwiftUI API completion decisions.md:3414-3502; Sources/TUIkitFoundation/Rendering/MeshColourField.swift; deviation C2). Since W1 landed on 10-18, a gradient or mesh filling any other shape is already sampled per half cell and drawn with ▀/▄. That covers Circle, Ellipse, Path and a wide or dashed stroke, on every terminal, Apple Terminal and picture terminals included (_ShapeCore.swift:120-125, :226-235; ShapeHalfBlocks.swift:95-108; deviation C8). Deviation C2 does not yet say so. Option 1 is meant to avoid two costs: copied text gives block characters, and Apple Terminal, which draws Block Elements short of the line (Terminal compatibility survey.md:731), shows bands. Rasterized shapes already pay both. Option 1 also now leaves a gradient Circle at twice the vertical resolution of the same gradient in a Rectangle or a background. Images also draw with ▀ (ASCIIConverter+HalfBlocks.swift). The ▀ change for gradient views is priced at half a day, plus the self-check and a look in Apple Terminal and Warp. It could share the shapes' half-block emitter (W1's B-W1-1 fuller version). A separate one-hour probe could tell whether SwiftUI caps a mesh's colour slope as a box or a circle; the difference is under one colour level.

- **1. Keep one sample a cell.** Unchanged. *Price:* Free.
- **2. ▀ where block elements fill the line.** Two samples a cell on glyph-only terminals such as Warp. Apple Terminal (blockElementsFillTheLine false) keeps one sample. *Price:* Half a day plus looks. Every gradient on those terminals looks different, and copying gives ▀ instead of spaces.
- **3. ▀ on every glyph-only terminal.** As option 2, Apple Terminal included. *Price:* Half a day. Bands on Apple Terminal.
- **4. Opt-in modifier.** A TUIkit-only modifier switches it on; the default is unchanged. *Price:* Half a day, plus a new public TUIkit-only API to maintain.

**Recommended:** Option 1. The gain shows on few terminals, Apple Terminal would show bands, and the copied text gets worse. Skip the slope-cap probe: it can move a colour by under one level.

**If you don't answer:** Gradients stay at one sample a cell, and the slope cap stays as the box reading.

*(Corrected in the evening re-check.)*

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md:3414-3502; /Users/robot/Documents/TUIkit/Sources/TUIkitFoundation/Rendering/MeshColourField.swift; /Users/robot/Documents/TUIkit/Sources/TUIkitImage/ASCIIConverter+HalfBlocks.swift; /Users/robot/Documents/TUIkit/Documentation/Terminals/Terminal compatibility survey.md:731-745</sub>

### O5-FROSTED

**Frosted add-on for materials.** Now that the redone demo shows the tint-only materials, is the frosted add-on worth about two days? It would drop the glyphs beneath a material and average the neighbouring colours.

Materials shipped tint-only on 10-18 (e9e4250f3; Sources/TUIkitFoundation/Styling/Material.swift; Deliberate deviations C5): what is behind shows through tinted, and its glyphs stay. Your 10-12 O5 ruling allowed no blur unless an insight made it much simpler, and the frost was to be offered once the materials showed in the Example (Refusals re-examined:976-1003). The demo was redone (c74d77a2b), and DAY-REPORT-1018 leaves the question open. Because a cell holds one glyph, letters behind a material show between the words on it, which is the detail a material exists to hide.

- **a. Keep tint-only.** As shipped. *Price:* Free.
- **b. Full frost.** Drop the glyphs beneath the material. Give each cell the box average of its neighbours' effective colours (from the opacity compositor, plus a constant glyph-coverage table), then tint it. *Price:* About 2 days. Neighbour sampling for every material cell.
- **c. Drop glyphs only.** A material's blank cells hide the glyphs behind them. Backgrounds are tinted as now, with no averaging. *Price:* Unpriced; a fraction of option b.

**Recommended:** Option c first: it cheaply removes what makes text on a material hard to read. Option b only if the flat look disappoints. This is your taste call.

**If you don't answer:** Materials stay tint-only, and so does glass, which shipped on them on 10-18 with a highlighted rim (lane GLASS, Deliberate deviations C11); a frost would reach glass too.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Refusals re-examined, wave 17 (2026-10-03).md:976-1003; /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md:1003-1020 (C5), :1113-1146 (C11); /Users/robot/Documents/TUIkit/Sources/TUIkitFoundation/Styling/Material.swift; /Users/robot/Documents/TUIkit-session-notes/plan/DAY-REPORT-1018.md:22-35; /Users/robot/Documents/TUIkit-session-notes/plan/MORNING-REPORT-1017.md:73-78; /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/owner-decisions-2026-10-12.md ([20] O5)</sub>

### O1-LOOSEN

**Count the host's Reduce Motion on the environment's word.** Should the host's Reduce Motion also count when only the environment says the session is local (isLocal() || isLikelyLocal()), relaxing your 'certain' standard?

Shipped 10-14: HostReduceMotionRefresher counts the macOS or GNOME Reduce Motion setting only where SessionLocality.isLocal() holds (Sources/TUIkitApp/App/HostReduceMotionRefresher.swift:80). That test needs positive evidence: no SSH variables, no remote-session daemon among the process's parents, every tmux client local, and no session keeper. Your 10-12 ruling was to use the host setting only if same-host is certain. isLocal() answers 'not local' even at the desk inside screen, zellij, abduco, shpool, dtach, tmate or a WezTerm mux. isLikelyLocal() (TERM_PROGRAM set and no SSH variable) already decides the display scale for pictures (Sources/TUIkitTerminalHost/App/SessionLocality.swift:157-168). The loosening was proposed on 10-14 and is awaiting your ruling (QUEUE:568).

- **a. Keep isLocal() only.** Users at the desk inside a session keeper set TUIKIT_REDUCE_MOTION=1 themselves. *Price:* Free.
- **b. isLocal() || isLikelyLocal().** The environment's word counts too. *Price:* About an hour with tests. A screen or tmux session started at the desk and later attached from elsewhere picks up the desk machine's Reduce Motion, if it is on.

**Recommended:** Option b. A wrong 'local' can only add reduced motion, usually for the same person, while a wrong 'not local' withholds it from someone who asked for it.

**If you don't answer:** The current rule stays: the host setting counts only with positive evidence that the session is local.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Refusals re-examined, wave 17 (2026-10-03).md:832-876; /Users/robot/Documents/TUIkit/Sources/TUIkitApp/App/HostReduceMotionRefresher.swift:70-80; /Users/robot/Documents/TUIkit/Sources/TUIkitTerminalHost/App/SessionLocality.swift:17-68, :157-168; /Users/robot/Documents/TUIkit-session-notes/plan/QUEUE.md:568; /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/owner-decisions-2026-10-12.md ([20] O1)</sub>

### P5

**Accessibility preferences beyond reduce motion.** Should reduce transparency, differentiate without colour and increase contrast be read as reduce motion is (host setting in local sessions only, each with a TUIKIT_* override), and should TUIkit's own drawing honour them?

Only \.accessibilityReduceMotion ships (B53's environment variable plus O1's host read). The other preference values are refused under the parity map's Accessibility* family (parity-map.json:19-28). \.colorSchemeContrast ships as a constant .standard (Sources/TUIkitFoundation/Environment/DeviceEnvironment.swift:143-147). The O1 ruling left this extension to you (Refusals re-examined:866-868; REFO Q1). \.accessibilityVoiceOverEnabled stays refused, because a remote session would answer a wrong false, and the members that feed an accessibility tree stay declined.

- **a. Reduce motion only.** As now. *Price:* Free. Ported code that reads the other values fails to compile.
- **b. Three values, set by TUIKIT_* variables.** Ship the three as environment values, set from TUIKIT_* variables or .environment. TUIkit honours reduce transparency (materials drawn opaque, as an inactive one already is) and increased contrast (colorSchemeContrast answers .increased). *Price:* About a day (my estimate). Adds new TUIkit-only variable names.
- **c. Option b plus the host read.** Also read the host's settings where SessionLocality says the session is local, reusing the O1 refresher. These would be macOS's universalaccess keys; GNOME equivalents are unchecked. *Price:* About half a day on top of option b.

**Recommended:** Option c. Design TUIkit's own non-colour focus and selection cues for differentiate-without-colour separately, after you have seen them, because they touch your focus-colour rules.

**If you don't answer:** Only reduce motion is read, and the other values stay refused.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Refusals re-examined, wave 17 (2026-10-03).md:549-563, :866-876; /Users/robot/Documents/TUIkit/Documentation/Working notes/REFO/notes.md:984-986; /Users/robot/Documents/TUIkit/Tools/APIParity/parity-map.json:19-28; /Users/robot/Documents/TUIkit/Sources/TUIkitFoundation/Environment/DeviceEnvironment.swift:143-147; /Users/robot/Documents/TUIkit/Sources/TUIkitFoundation/Styling/Material.swift</sub>

### WL-Q3

**Deep-nesting cost of animatable .padding and .frame.** Do you accept the cost that animatable .padding and .frame add to the deep-nesting scenario (+7.5% when last measured in August), or should the search for a fix continue?

Making .padding and .frame animatable cost the deep scenario +7.5% after two rounds of optimisation, while table, kitchensink and megalist measured indistinguishable from before (SwiftUI parity work log.md:57-87). deep nests layout modifiers on purpose, so each is re-measured once per enclosing level. The only further fix found, a per-frame 'could anything animate?' gate, is not sound. The number is two months old: the October performance pass moved the animatable substitute out of line, which made deep 2.0% faster (Performance pass after the SwiftUI API batch (2026-10).md:305). Your standing tolerance: a few percent is fine, about ten is uncomfortable.

- **a. Accept and close.** Record it as accepted. *Price:* Free.
- **b. Re-measure first.** Build main with the animatable path for padding and frame switched off, A/B it against main on deep on a quiet machine, and close the item if the cost is within a few percent. *Price:* A couple of hours plus quiet-machine time.
- **c. Keep hunting for a sound gate.** Look for a gate that skips the probe without losing the first animated change. *Price:* Open-ended; none found so far.

**Recommended:** Option b, then a.

**If you don't answer:** The cost stays, recorded in the work log as provisionally accepted.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/SwiftUI parity work log.md:57-87; /Users/robot/Documents/TUIkit/Documentation/Performance/Performance pass after the SwiftUI API batch (2026-10).md:305; /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/perf-regression-tolerance.md</sub>

### NAMED-COLOURS-DARK

**Named colours under a dark appearance.** Should Color.red, .blue and the other named colours take Apple's dark values under a dark colour scheme, resolved where they are drawn, reversing the 09-15 'light values for now'?

The fifteen names are fixed RGB at Apple's light values (Sources/TUIkitStyling/Color/Color.swift:278-320). Commit 1aafda572 chose that 'as the owner decided for now', so a named colour can be measured and mixed in a view body. SwiftUI adapts these hues to a dark appearance. TUIkit knows the scheme (\.colorScheme, from OSC 11 and the like), but the names don't follow it; the deviations page lists this under 'Slated to change' as 'Not yet' (Deliberate deviations :1846; compatibility guide §1 row 163, §2.5). Dark terminal themes are common. A Color is 5 bytes, and a new case with a one-byte payload fits; its light and dark values would be a constant table, not a registry.

- **a. Resolve by scheme where drawn.** A 'system colour' case looked up in a constant light/dark table by the palette's scheme. Arithmetic done in a view body (opacity(_:over:), lerp, rgbComponents) answers the light value, as SwiftUI's resolve(in: EnvironmentValues()) does. resolve(in:) answers per environment. *Price:* 1-2 days (the inventory's estimate): a new case in every switch over ColorValue (D6M counts 26), some on the hot path. An A/B is owed, plus an hour's probe for SwiftUI's dark values.
- **b. Keep the light values.** Move the row from 'Slated to change' to a recorded deviation. *Price:* An hour of docs.

**Recommended:** Option a. The terminal gives no reason to deviate, and answering the light value in a body keeps what the 09-15 decision protected.

**If you don't answer:** Named colours stay at the light values on dark pages, listed as slated to change.

<sub>Sources: /Users/robot/Documents/TUIkit/Sources/TUIkitStyling/Color/Color.swift:140-200, :278-320; /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md:940-951, :1846; /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/SwiftUI compatibility guide.md:163, :540-559; /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/SwiftUI semantic audit (2026-08).md:460; git 1aafda572</sub>

### B-D6M-1

**Asset-catalogue colours choose light or dark where drawn.** Should a named colour from an asset catalogue choose its light or dark variant where it is drawn, not when it is made? That needs either a colour table reachable without the environment, or a bigger Color.

Color(_:bundle:) picks the variant when the colour is made, using the default palette's scheme. So an app whose palette, or a .colorScheme pin, is of the other scheme gets the wrong variant; a set with one colour, the common case, is exact (D6M.md:16-51; Deliberate deviations C1). The doc's fuller version, an index into an app-scoped table of catalogue colours resolved beside .semantic, is about a day plus A16's benchmark. It needs a process-wide table that a Color made in a view body can reach, which the doc calls a singleton by another name and CLAUDE.md forbids. A16's custom colour provider (your 10-04 ruling: benchmark thoroughly, decline if costly) waits on the same A/B.

- **1. Keep choosing when made.** As now; documented. *Price:* Free.
- **2. Build with A16.** If A16's benchmark passes, add a ColorValue case holding a table index. *Price:* About a day plus A16's benchmark. Still needs a home for the table that isn't a singleton, which nobody has found.
- **3. Grow Color to hold both variants.** Color goes from 5 to 8 bytes, with no table. It would also serve NAMED-COLOURS-DARK. *Price:* Not priced in the doc. Every Text and cell run grows, an A/B is owed, and the size pins change.

**Recommended:** Option 1 for now. Revisit it together with A16's benchmark and NAMED-COLOURS-DARK.

**If you don't answer:** The variant stays chosen when the colour is made.

<sub>Sources: /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/Named colours, localisation lookup and the swift-syntax range (D6M).md:16-51; /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md:205-239 (A16); /Users/robot/Documents/TUIkit/Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md:940-951; /Users/robot/Documents/TUIkit/Tests/TUIkitStylingTests/ColourAlphaStorageTests.swift:56-59; /Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/owner-decisions-2026-10-04.md (A16)</sub>

## Settled by your earlier rulings (veto any)

Each was an open question that a ruling of yours, a CLAUDE.md rule or your standing guidance already settles; a skeptical second reading agreed. "Keep" means nothing changes; anything else is queued in a lane and not built yet.

| Id | Question | Taken | Settled by |
|---|---|---|---|
| A-TC1-1 | Should the 60 exit tests' bodies (28 files across 9 test targets) move into helper functions to save type-check time, or stay as written? | (c). About 2 s (≈0.2%) was measured at 43 exit tests; at 60 the saving is still well under 1%, which doesn't pay for tests that hide what they check. | Measured at about 0.2% saved against a readability cost. Leaving the tests needs no action. |
| A28-CUSTOMIZATION | Build toolbar customisation (toolbar(id:), CustomizableToolbarContent and the customisation behaviours and options, 14 gaps), or refuse it? | Option 1, following the shape of the existing column and tab customisation. Both the study's 'gap, not a refusal' and your 10-18 instruction point there. | The A28 study you accepted on 10-04 calls it 'a gap, not a refusal', and your 10-18 instruction says finish compat. The design follows the B45 and B79 precedents. |
| A39 | Should VisualEffect's rotation, scale and transform members simply follow whatever A27 decides for the View modifiers of the same names? | Option 1. | The reuse rule says follow A27 exactly. The real question is A27's, which stays with you. |
| B-C9B-3 | Should TUIkitView re-export TUIkitCore and TUIkitStyling, and TUIkitImage re-export TUIkitStyling, as every carved module re-exports what it is built on? | (a). It follows the split plan's own rule and your 10-07 concern about long import lists, and changes no behaviour. Built 2026-10-19. | The split plan's own rule (each module re-exports its direct dependencies) and your 10-07 import-list concern settle it, at negligible cost. |
| B-D1S-1 | Should `LazyVStack`/`LazyHStack` take their sections apart into rows and pin headers from row positions (SwiftUI's model, about 3 days), or keep drawing each section whole as now? | Option 2, as one lane with B68 and B-D1S-5's index. You asked on 10-18 to finish SwiftUI compatibility, and your perf tolerance already covers the risk. It is low-value parity (rare shapes), so schedule it after the cheaper items. | L8 is a 'Lane' deviation open to veto, not an owner ruling. Parity plus the 10-18 'finish SwiftUI compat' set the direction, and the perf risk is gated by your A/B tolerance. What's left is effort and scheduling. |
| B-D1S-6 | Should a modifier on a view of the app's own whose body is several views reach each of those views, as SwiftUI's does, and should an if/else body be taken apart too? The suggestion is one lane together with the B19 guide work you already approved. | Option 2, run as the B19 lane you already approved. Effect modifiers must keep firing once, not once per member (measured: `.onAppear` on a two-member Group fires once). | Your 10-12 B19 ruling ('explore perf') and the 10-18 instruction cover it. Effects firing once is measured SwiftUI behaviour, and the A/B tolerance decides whether it lands. |
| B-D2S-5 | Under `scrollClipDisabled`, should a scroll view's overflow also show through the blank cells between the words of a later view (SwiftUI's literal transparency), or only beside that view's painted run on each line, as now? | Option 1. Your wish not to force clipping (B-GUIDE-3) is already met at the line ends, and inside a line the medium can show only one glyph per cell. | Keeping the shipped per-line rule needs no action. One glyph per cell is a terminal constraint CLAUDE.md allows, and B-GUIDE-3 is already met at line ends. |
| B-D2S-7 | Should scroll target behaviours (`.paging`, `.viewAligned`) measure their container and targets inside the content margins, as SwiftUI documents, once a probe confirms that SwiftUI really does this? | Option 2. | Probing SwiftUI and then matching it is the parity rule applied directly, at half a day and no runtime cost. |
| B-D3M-3 | Now that most hosts give an image its natural size, should tiled images repeat at that size and read cap insets in points, as SwiftUI's do? | Option 2. **Built 2026-10-19.** | The parity rule plus your B42 ruling (sizes that follow the font are accepted) settle it, at two hours and no runtime cost. |
| B-D3M-4 | Should TUIkit read PDFs again through Core Graphics, and should the CGColor/CGImage bridges move back into TUIkit so they need no extra import? | Option 4. **Built 2026-10-19.** | B50 covered AppKit, not Core Graphics. Rule 1 favours both changes, and neither adds runtime cost or new dependencies. |
| B-DYNVFIX-4 | Should a class that is both a DynamicProperty and a ViewModifier, held in a view's field, get its update() called, if SwiftUI does that? | (b). Measure SwiftUI and follow it. Leave the never-applied half alone, since it already matches SwiftUI. | Probing SwiftUI and then matching it is the parity rule, and one set lookup is within tolerance. |
| B-DYNVFIX-5 | When one view value is drawn at two places, should @FocusState, @Namespace, @FocusedValue and @FocusedBinding each get a store per place, as @State and @Environment now do? | (b), probing SwiftUI first. It's low priority, but the parity rule and correctness > perf favour it. | Parity plus correctness > perf, with a compare-per-body cost like @State's. Probe first. |
| B-F2-4 | Should the stall watchdog stay (it lets a hung app quit at the second ⌃\ under the kitty keyboard protocol), or do you veto it? | Keep. It meets your own requirement at a cost far below 'a few %'. Check it once on a real kitty-protocol host (Ghostty) at the next probe session. | Keeping it needs no action and meets your own 10-05 requirement (⌃\ quits a hung app). A veto would break that requirement. |
| B-REORG-6 | Should the flat per-lane decisions files be grouped into topic folders, as Module split/ and Compile time and binary size/ already are? | (a), done between lanes so that no cherry-pick conflicts with the moves. | Your 10-12 documentation rule (subfolders when several items share a topic) settles it. |
| B33-SUBCELL | Should a fill-style slider with neutralValue: draw its edge at the neutral value to a fraction of a cell, as it already does at the knob? | Option 2 if a PTY check shows clean edges; otherwise option 1. | A minor fidelity gain for a rarely used API, with no runtime cost for anyone else, gated on a PTY check. |
| B34-FULLER | Should the one-frame lag of a focused-value reader drawn ahead of its publisher be removed, with a publisher-only pre-walk or by drawing readers last, or kept? | Option 1. | Keeping it needs no action. The lag is one self-correcting frame, and both fixes cost every frame. |
| B38 | Keep the shipped rule that search scopes show while the search field has focus or a query, and hide on dismissSearch or when leaving an empty field, or show them whenever the field is on screen? | Option a. Add an always-visible activation only if an app asks for one. | Keeps a faithful mapping of both SwiftUI activations. The alternative would break .onTextEntry. |
| B54 | Should a scale transition with a factor above 1 animate, by cropping the view to its middle and widening the crop, or keep drawing the view whole from the first frame? | Option 1 until a port asks for it. | Keeps the shipped, doc-recommended behaviour. The alternative reads as the opposite motion, and nothing asks for it. |
| B62-FULLER | Should the vertical (wrapping) TextField get its three fuller parts: a lean per caret at a wrap point as macOS keeps, a scroll indicator when its text is taller than the field, and mouse-wheel scrolling (together with TextEditor)? | Do the lean (together with B-D4X-16) and the wheel. The lean is measured macOS behaviour, and a Mac text view scrolls with the wheel. Add the indicator only if a probe shows macOS drawing one. **The wheel built 2026-10-19; the lean waits on its NSTextView probes.** | The lean is measured parity and wheel scrolling is standard Mac text-view behaviour. The indicator waits on a probe. The only cost is effort. |
| B65 | Should TextField and TextEditor draw and edit a selection of several ranges written by the app, instead of using only the first range? | Low priority, after A42's R1: measure NSTextView, then draw and edit several ranges, and report the editor's block as ranges. | Parity work once NSTextView is measured. The only cost is effort, and it's scheduled low. |
| B66 | Should a pinned section header keep covering the row text under it (shipped), or let the row text show past the end of the header's text, as SwiftUI's transparent header does? | Option 1. | Keeps the shipped behaviour. One glyph per cell is the terminal-constraint exception, and backgrounds already stay see-through. |
| B67 | With `.scrollIndicatorStyle(.text)`, should a pinned header keep sitting below the '▲ N more above' line (shipped) rather than under it? | Option 1. | The text indicator is TUIkit-only, so there's no SwiftUI behaviour to match, and the alternative just hides the header. |
| B68 | Should a lazy stack decide which sections are its own (and so pin) by marking its children as it draws them, instead of today's test ('the next stack down, and one sibling step')? | Option 3 if B-D1S-1's fuller version is built; otherwise option 1. | A minor internal heuristic whose only miss is a rare shape. Folding it into B-D1S-1 or keeping it costs nothing. |
| B73 | Should background prominence (the 'raised' state that keeps text readable on an accent fill) also apply to hand-written list rows and to content under .background(.selection), as it does in SwiftUI? | Option 1, with the benchmark. A row that loses contrast only because the app wrote it by hand is a correctness defect. | A correctness parity fix with no API change, gated by an A/B within your tolerance. |
| B74 | Keep \.sidebarRowSize read-only, so that writing it fails to compile, or make it settable with a terminal meaning invented for it? | Option a, until an app needs it. | Rule 2 (what can't be honoured fails to compile) is exactly what the read-only value does. Keeping it needs no action. |
| B76-HEADER | Should .tabViewSidebarHeader and .tabViewSidebarFooter scroll with the tab list, as SwiftUI's do, instead of staying fixed? | Option 1. | An hour of SwiftUI parity. SwiftUI already provides the pinned variant as its own API. |
| B78-FLUSH | In a list that fills its width, should a section's .sectionActions sit at the trailing edge of the header, as on macOS, instead of one cell after the title? | Option 1. | Layout parity where the terminal allows it, with no API or runtime cost. |
| B79 | Should the user be able to reorder the sections of a sidebar bound to a TabViewCustomization, by keyboard and by drag, with the new order written back to the app's customization? | Option 1. It matches macOS, and your no-mouse-only rule is met by the keyboard route beside the drag. | Parity covers the drag and your no-mouse-only rule covers the keyboard route. The folds answer the open design question, and perf is gated by A/B. |
| B80 | Should loops inside a hierarchical (outline) table accept insertions through .dropDestination and .onInsert, as loops in a flat table already do? | Option 1. | Small parity work with no API or runtime trade-off, after a probe. |
| B81 | Should the find bar open with Ctrl-F (TUIkit's stand-in for ⌘F), with Ctrl-G as Find Next while the bar is closed, and should it highlight every match and gain the options menu? | Do all three, starting with highlighting every match. Each follows SwiftUI and your earlier rulings on keys. **Built 2026-10-19.** | Your 09-23 ruling (Emacs chords are a bonus; Ctrl-F find is common) and the N6 Ctrl-V precedent settle the key. Match highlighting and the options menu are SwiftUI behaviour whose only cost is effort. |
| B85-LINKDISPLAY | Should .linkDisplay(.urlInParentheses) and .linkDisplay(.urlOnly) apply to links inside a Text as well, not only to Link? | Honour it. It makes an existing modifier reach its whole subtree, and it is the cheap way to make text links readable on Apple Terminal. **Built 2026-10-19.** | CLAUDE.md's modifier-first rule says a TUI option should reach its whole subtree. The default doesn't change, and only apps that opt in pay. |
| B88 | Should a live Text(_:format:) over a TimeDataSource, whose format produces an AttributedString, draw the attributes (colours and so on), as the one-off form already does? | Build it, at low priority: it is small, matches SwiftUI, and costs other texts nothing. **Built 2026-10-19.** | Matches SwiftUI for half a day, and other texts pay nothing. |
| B91 | Should DragGesture's velocity come from a least-squares fit over the last 100 ms of reports, as UIKit's pan recognizer computes it, instead of today's running average? | Do it the next time a lane touches DragGesture. It's cheap, internal, and holds up better against bursty reports. Not urgent. **Built** (lane INPUT, 2026-10-18, ec2dfc24c). | About two hours, internal, no API change. SwiftUI's estimator is unknown, so parity argues neither way, and your 10-12 'velocity if cheap' leans the same way. |
| B92 | Should a long press's and a multi-tap's deadline start at the arming event's report time, rather than at the first frame after it? | Do it. It's an hour, brings timing closer to SwiftUI's, and costs nothing at run time. **Built** (lane INPUT, 2026-10-18, d0532db22). | About an hour with no runtime or API cost, and it brings timing closer to SwiftUI. Nobody would choose to keep the lag. |
| B93 | Should taps and row double-clicks share one double-click interval, or keep their own (0.35 s for TapGesture, 0.4 s for a row's clickCount)? | Keep two, as measured. Separately and unasked: the row window could move from 0.4 s to macOS's 0.5 s. | Keeping both intervals needs no action, and each matches its measured macOS counterpart. |
| C7 | Should ScrollView gain SwiftUI's settable `showsIndicators` property? It is not deprecated, although its initializer is. | Option 2. **Built** (lane PARITYMISC, 2026-10-18). | The decline was a lane reason, not an owner ruling (C-W10-2 has no ruling). The SDK doesn't deprecate the property, so [21] doesn't apply, and the fix is about 20 minutes. |
| CURSOR-BLINK-CI | Should CI's full-depth smoke test run the real app in a pseudo-terminal and check from its output that the caret blink is regular? | (a). Built 2026-10-19 (`raw_probe.py --blink`, advisory). | A minor CI addition. Making it advisory first removes the flake risk, and it costs about 10-20 s on an 11-minute run. |
| D4X-FULLER | Should the three recorded leftovers be built: a lean per caret at a wrap (B-D4X-16), passing a Table cell's position down to geometry readers (B-D5G-2), and keeping a screen selection when its content moves inside an unchanged area (B-D4X-15)? | Build the per-caret lean together with B62-FULLER, since it is measured macOS behaviour. Do the cell positions only if a profile shows readers in table cells. Keep B-D4X-15 recorded until someone runs into it. | The per-caret lean is measured macOS behaviour, and the other two are conditional (profile-first, no design yet). Nothing here is taste. |
| DEPR-DROPDEST | Keep the soft-deprecated dropDestination(for:action:isTargeted:) until A53 is unpinned, unpin part of A53 now so it can be replaced, or remove it now? | Option c: keep the overload (DragAndDrop.swift:519) until the macOS 26/27 pass. One doc line is owed: the compatibility guide should record it as SwiftUI's soft-deprecated spelling, kept while A53 is pinned (the DOCS lane will write it). | [21] says to audit existing deprecated APIs, not remove them, and the A53 pin stands. Keeping it needs no action and preserves a capability. |
| DEPR-TFSTYLES | Replace .roundedBorder and .squareBorder with macOS 27's .bordered plus textInputBorderShape(_:) now, or at the macOS 27 pass? | Option b. | Your 10-18 ruling that newer-SDK work waits for macOS 27 applies for the same reason. Waiting needs no action. |
| O2-KEYFRAMES | Under reduce motion, should KeyframeAnimator's tracks keep moving as SwiftUI's do, or be held still? | Option a. | Your A-D3M-1 ruling (only spatial motion is held) plus the parity default settle it. Keeping it needs no action. |
| PICKER-POINTER-OPEN | When the pointer opens a Picker's drop-down, should it keep highlighting the current value, or highlight nothing, as a pointer-opened Menu and combo box do? | Keep. The 07-27 rule guards against a highlight on an arbitrary first item, and a picker's highlight sits on the current value, where a mis-click changes nothing. Confirm macOS's pop-up button with a quick probe when convenient. | Keeping it costs nothing, and the reason for the 07-27 rule (mis-clicking an arbitrary first item) doesn't apply to a highlight on the value already chosen. |
| S3-EMPTYVIEW-FRAME | Should `EmptyView().frame(…)` and `EmptyView().padding(…)` take no space in stacks, as in SwiftUI, instead of keeping the frame's or padding's rows? | Option 2. No capability is lost (a kept slot is `Color.clear.frame(height:)` or a stack, which behave the same in both), it fixes what SwiftUI code means, and it ends the disagreement between the stacks and the subview walks. It is also the first step S3-NO-EXTENT-SPACING would need. | Under your 10-11 guidance, extra TUIkit behaviour gives way when it makes SwiftUI code mean something different. That's the case here, and the same effect is still available another way. The cost is small. |
| SIZE-SMALL-LEVERS | Should I re-measure the small package size levers under today's defaults and land those that still pay, or drop them? | (a), measurement first. Drop any lever worth under about 1% of Hello. Land the rest only if the A/B is within tolerance. | Measure first, then your order (runtime > bytes > compile time) and your A/B tolerance decide each lever. |
| TEXTFIELD-CLEAR-BUTTON | Should the compatibility guide's 'clear button in a TextField' row be dropped, since SwiftUI's macOS TextField has none, or should TUIkit add an opt-in clear button? | Drop the row, and check the search field as a separate parity item, since that is where macOS shows one. **Row corrected, and the search field's ✕ built, 2026-10-19.** | A doc correction to a wrong premise. The search-field check is ordinary parity work. |
| W5 | Should TUIkit implement SwiftUI's blend modes per cell, as the Wave 17 review found it can, or confirm Wave 16's decline? | Option a. **Built 2026-10-19** (`View.blendMode`, `VisualEffect.blendMode`, `ShapeStyle.blendMode`). The review showed blend modes can be honoured per cell, exactly as the colour effects that already ship are. | The decline was a Wave 16 lane decision that the Wave 17 review rebutted, not an owner ruling. Parity plus the 10-18 instruction settle it, opacity's pipeline is the precedent, and unused code pays nothing. |
| WL-Q1 | Should Text(…).foregroundStyle(color), the overload that returns a Text, fade inside withAnimation as View.foregroundStyle does, if it can be made cheap enough? | Study it with A40 and adopt only under the ~1% bar. Meanwhile write the note and the deviation entry, which are owed either way. **Note and deviation T10 written 2026-10-19**; the study waits on A40. | The docs are owed now under docs-as-you-go, and adoption is gated by your own A40 bar (about 1%). Nothing new is asked of you. |

## For awareness: blocked

Nothing to decide unless you want to unblock one.

- **A50:** Search in a tab view (macOS 26): TabSearchActivation, tabViewSearchActivation. Unblocked by a macOS 26+ machine. Then implement as documented (about half a day).
- **A53:** Drag-session behaviour (macOS 26): callbacks, configurations, containers, formations (B83's values ship). When unblocked, three questions: what an operation means; DropSession versus DropInfo; keyboard drags (A53-KEYBOARD-DRAG). Recommendation 1: sessions on single-item drags (a day). DEPR-DROPDEST depends on this.
- **B-D3M-2:** Image natural size on kitty, WezTerm, foot and Alacritty, and Ghostty's display scale. Needs another machine or a GPU VM.
- **B-D4X-1-3:** OSC 52 to every terminal as best effort; treat iTerm2's DA1 52 as honoured. About an hour plus half a day.
- **B-DYNVFIX-2:** Indirect enum payloads, and payloads on WebAssembly/Windows, are updated on a copy. Unblocked only by a supported Swift runtime or language route.
- **B-G2-2:** Autowrap off on Apple Terminal: read the edge card. Once the card is read, drop keepsAutowrap and tighten the clip (about half a day).
- **B33-MEASURE:** Measure SwiftUI's slider ticks, neutral value, enabled bounds and thumb on macOS 26. Needs a macOS 26+ machine or CI runner.
- **DEPR-MACOS27:** Full macOS 27 deprecation sweep. Run deprs.py against CI's xcode-27 or a macOS 27 machine.
- **E6-KITTY-PASTE:** E6: an OSC 5522 paste has never run on a real kitty. The owner runs the paste half of clipboard_mime_probe.py.
- **FO-FULL-LTO:** Full LTO with conditional runtime records. Blocked upstream, then needs a runtime A/B.
- **MACOS26-PASS:** macOS 26 measurement passes owed by waves 06 and 11a (text-field newline keys; A32-A33, B48-B51 strings, including ~200 SystemFormatStyle probes). Unblocked by a macOS 26+ machine. B49's three-field clock-face probe could run now, but the owner said no action.
- **PROBES-PERSON:** Readings that need a person or restored screen capture. Unblocked by the owner running or reading the cards, or by restoring Screen Recording.
- **TASK-NAME:** The three task(name:…) overloads that only newer SDKs declare. Follow a30b8b179's pattern.

## For awareness: deferred by you

Parked by your own rulings (*Future options*, or an explicit "later"). Listed so you can bring any back.

- **A-SPH2-1:** Computed constants for cross-module static lets. *Ruling:* Owner 2026-10-12: keep the addressor.
- **A-SPH2-2:** Typed feature-object keys (a sound unsafeDowncast). *Ruling:* Owner 2026-10-12: keep as?.
- **A13.2:** A key that hands the mouse back to the terminal. *Ruling:* Owner 2026-10-05: punt; every candidate key declined.
- **A13.5:** Exact per-Text selection (D2). *Ruling:* Owner 2026-10-04: remember the idea, don't build it now.
- **A17:** preferredColorScheme, and toolbarColorScheme(_:for:) with it. *Ruling:* Owner 2026-10-04: omit for now. The toolbar form follows it.
- **A3:** layoutDirectionBehavior and the text alignment/writing-direction strategies (with right-to-left). *Ruling:* Owner 2026-10-04: defer with right-to-left.
- **ANIM-SPELLINGS-RETIRE:** Retire the TUIkit-only animation spellings once SwiftUI APIs match their cost.
- **B-D3M-1:** A large caution picture for critical dialogs (Kitty graphics). *Ruling:* Owner 2026-10-04: a later graphics project.
- **B-GUIDE3-1-P3:** Containers report a size past their proposal (a fixed .frame keeps its width when offered less). *Ruling:* Owner 2026-10-12: keep the safe option for now.
- **B-TC1-1-INTEGRATION:** #expect type-check floor in TUIkitIntegrationTests.
- **B1:** Right-to-left layout support (a settable layoutDirection, mirroring at every layout site). *Ruling:* 2026-10-04 and 2026-10-12: still wanted, out of scope for now; pinned until there is a solid plan, after everything else.
- **B22-PALETTE-TIERS:** Per-palette faded tiers for an arbitrary foreground.
- **B8:** KeyboardShortcut.Localization mirroring under RTL. *Ruling:* 2026-10-12: mirror once right-to-left lands. Remapping stays out.
- **D3:** Canvas and GraphicsContext (with ColorMatrix, ColorRenderingMode).
- **DEEP-QUADRATIC:** O(depth²) re-measure on deep plain nesting.
- **GHOSTTY-V13:** XTGETTCAP RGB truecolour detection.
- **HIDDEN-DEMAND:** An animation under .hidden() still asks for renders.
- **IMAGE-UNIFORM-CELLS:** Draw uniform image cells as a space with a background.
- **IND-RASTER-FILLS:** Indeterminate gradient pictures ignore fill glyphs other than █.
- **KGP:** Kitty-graphics hairline row separators (and the button underlay). *Ruling:* Owner 2026-10-04: 'a later project … keep in mind, not now'. 10-15: the button underlay is later.
- **KITTY-CLASSIC:** Kitty classic placement (a=p) for WezTerm, Konsole, Contour, Warp, Zellij, xterm.js.
- **MEGALIST-AB:** megalist A/B verdicts can't be resolved (layout sensitivity).
- **MEMO-KEY-ADDRESS:** A view storing an AnyView hashes a heap address.
- **MODE-1016:** SGR-Pixels mouse reports (mode 1016).
- **O11:** Formatter-based APIs: Text(_:formatter:), interpolation with formatter:, TextField(value:formatter:). *Ruling:* Owner 2026-10-12: deferred, 'we can always add them later'.
- **O16:** TextRenderer group: textRenderer(_:), Text.customAttribute(_:), TextProxy, Text.Layout. *Ruling:* 2026-10-12: defer.
- **ONAPPEAR-AFTER-FRAME:** Run onAppear after the frame is written.
- **PAYU:** Pay-for-use run-loop services. *Ruling:* Owner 2026-10-12 [9]: deferred.
- **RTL-IMAGE-MIRROR:** Apple Terminal mirrors an image drawn with an RTL .customRamp.
- **S1A:** Selective optimisation S1a.
- **SME:** Single-module LLVM emission. *Ruling:* Owner 2026-10-12 [3]: not now.
- **SPLIT-D2-D3:** Module split D2 (menu engine into TUIkitMenus) and D3 (the Phase D side layer). *Ruling:* Owner 2026-10-07: D2/D3 later, deferred 'until after Phase C and the battle-test'.
- **TOOLTIP-RULES-4-5:** Tooltip placement rules 4 (avoid the pointer) and 5 (re-wrap narrower).
- **TRANSITION-SNAPS:** Four wrappers' removals still snap.
- **UPSTREAM-DEFERS:** Upstream-review items deferred and never revisited: duplicate collection-ID diagnostic, terminal write-failure surfacing, the cell surface. *Ruling:* The cell surface: owner 2026-08-07, 'deferred. Not adopted, not closed.' The others were deferred by the review.
- **W06-OPTRETURN:** Option-Return in a one-line TextField (macOS inserts a newline).
- **W11a-EXAMPLE:** Example page for live time text.

## Found already settled while compiling this

- **B70:** B70: Sectioned LazyVGrid, headers and footers as spanning cells. The B70 entry says spacing does not fall between a header and its first row, and that headers keep a dimmed bold style. The code no longer does either. Spacing falls there too, as measured in SwiftUI (da4409000, pinned by Tests/TUIkitGridTests/LazyGridSectionTests.swift:84). Headers are drawn as written, with no styling of their own, as SwiftUI's are (Sources/TUIkitFoundation/Views/Section.swift:49-57, decisions B16). Its 'fuller version', which would make the header spacing SwiftUI's, is therefore moot. Nothing needs your decision. The B70 entry (SwiftUI API completion decisions.md:2537-2552) still describes the old behaviour and should be corrected.

## From the lanes building on 2026-10-18

Owner questions the implementation lanes wrote while building. Each links to its full entry, which gives the options and their prices.

- **[A-EFFECTS-1. The faint content levels vanish at 16 colours, and the faintest at 256](<SwiftUI parity/Decisions/Shapes, effects and animation/Blend modes and image details (EFFECTS).md#a-effects-1-the-faint-content-levels-vanish-at-16-colours-and-the-faintest-at-256>)** (lane EFFECTS). Under a `foregroundStyle`, `.secondary` to `.quinary` are that style at 0.5, 0.26, 0.1 and 0.05, composited at the cell. Rendered over each shipped palette's page with the colour depth forced, and the ink read back out of the emitted SGR (`FaintLevelsAuditTests`, 2026-10-19): **Recommendation:** 3. It keeps the levels visible and ordered as far as 16 colours can, with the attribute terminals already provide for exactly this, and changes nothing at 24-bit colour.

- **[A-WIDTHS-1. What does an unidentified host claim for a conjunct?](<SwiftUI parity/Decisions/Terminals/Conjunct widths on hosts that don't compose (WIDTHS).md#a-widths-1-what-does-an-unidentified-host-claim-for-a-conjunct>)** (lane WIDTHS). Today: `.clustered`, the cluster rule — the same "assume it renders correctly" reasoning every other unidentified-host claim follows, and right for a host that clusters graphemes. But of the five hosts measured, four advance per code point, and the terminals TUIkit cannot identify (xterm, VTE, Alacritty, kitty without its grapheme mode) are `wcwidth` terminals, which also advance per code point — none of them measured here (kitty cannot open a window on this VM). **Recommendation:** 1 for now, and measure xterm and VTE (and kitty where it can run) with `advance_probe.py` before choosing between 2 and 3 — the same "measure, then claim" order this lane followed.

- **[A-O10-1. Linux has no save panel: `fileExporter` takes only Apple-only types](<SwiftUI parity/Decisions/Presentation and windows/File panels (O10).md#a-o10-1-linux-has-no-save-panel-fileexporter-takes-only-apple-only-types>)** (lane O10). Every `fileExporter` form takes a value of an Apple-only protocol: a `Transferable` (CoreTransferable) or a `FileDocument` (whose `FileWrapper` is Objective-C Foundation's). Under A18 option 1 both are absent on Linux, and so is every exporter: a Linux app can open and move files through TUIkit's panels but cannot ask where to save one, though the save panel itself is portable (it is drawn by TUIkit and writes with `Data.write`). **Recommendation:** 2: the cheapest, it adds no second spelling of anything SwiftUI has, and it is what a Linux app needs. 3 and 4 make SwiftUI source compile on Linux, which none of the other Apple-only API does (A18).

- **[A-FORMS-1. A button written bare in a columns form: at the trailing edge, or in the value column?](<SwiftUI parity/Decisions/Forms and control density (FORMS).md#a-forms-1-a-button-written-bare-in-a-columns-form-at-the-trailing-edge-or-in-the-value-column>)** (lane FORMS). `Form`'s documentation says a `Button` is right-aligned "(macOS places confirmation buttons on the right)", and the form does that. Measured, SwiftUI's columns form puts a bare button in the value column, where a field's control goes (`rows.out`: "Button bare", 21 points against a value column at 17), and its grouped form at the row's leading edge; TUIkit puts it at the trailing edge in both. The deviations document has no entry for it, so it is either an undocumented deviation or a bug. **Recommendation:** 2. Parity is the rule, and the TUI-specific `formRowAlignment(_:)` already exists for the dialog's look.

- **[A-FB16-1. A container's own size changes at once, where SwiftUI's frame glides](<SwiftUI parity/Decisions/Shapes, effects and animation/Insertion and removal model (FB16).md#a-fb16-1-a-containers-own-size-changes-at-once-where-swiftuis-frame-glides>)** (lane FB16). **Re-checked 2026-10-18 (evening):** this is the unbuilt part of your ruling, not a new question. "FB16: (a′)" took SwiftUI's measured model, in which every view whose frame changes glides from its old frame to its new one: its size as well as its position. The lane built the positions. So option 1 would mean recording positions-only as a deviation from (a′). **Recommendation:** 1 now, 2 if the Example's section borders read badly in use.

- **[A-LAYOUT-1. A column shares an overfull height only once a child's minimum is cheap to ask](<SwiftUI parity/Decisions/Layout and geometry/Layout parity (LAYOUT).md#a-layout-1-a-column-shares-an-overfull-height-only-once-a-childs-minimum-is-cheap-to-ask>)** (lane LAYOUT). Not landed. The column half of L14 (47171484d) was reverted by 2400f2948 for its A/B: `tables-vstack` +32%, `stateful` +34%, the table scenarios +11 to +24%. The lane re-applied it and counted, rather than timed, what it does per frame (`Stress --bench --cold`, a debug build, temporary counters, all reverted): measure-memo lookups per frame went from 242 to 684 on `tables-vstack`, 705 to 1,263 on `stateful` and 15 to 39 on `table`, from a minimum-size walk down the whole tree every frame. The options are to keep placing children in order (free; a column cuts its trailing children where SwiftUI squeezes them all), to make a child's minimum cheap and then land it (about two days plus an A/B), or to share only where minimums are already known (about a day). **Recommendation:** make the minimum cheap, then land.

- **[A-APPSTATE-1. `LocalizationService.shared` goes with draw-time lookup (LOCALE-B), not before it](<SwiftUI parity/Decisions/State and dynamic properties/Per-app render state (APPSTATE).md#a-appstate-1-localizationserviceshared-goes-with-draw-time-lookup-locale-b-not-before-it>)** (lane APPSTATE). **Re-checked 2026-10-18 (night):** the draw-time lookup this waited on landed in the same batch, with lane PARITYMISC: a `Text` made from a key reads it again when drawn under a `\.locale` naming another language ([B-PARITYMISC-5](<SwiftUI parity/Decisions/Small parity items (PARITYMISC).md#b-paritymisc-5-a-locale-override-re-reads-a-texts-key-not-a-buttons-title>)). What still reads a key when it is made (a `Button`'s title, the framework's own words) is B-PARITYMISC-5's fuller version, about a day, and option (b) below would need it too. So this is live now. The service holds one language for the process, the strings an app registered, and the memo of what each key resolved to. Its frame requests no longer go through a shared render state: `setLanguage(_:)` and `register(translations:)` ask every app running from the service and the app whose work made the change (B-APPSTATE-4). The service itself is still `LocalizationService.shared`. **Recommendation: (b)**, built on LOCALE-B, with the tables cache decided together with SINGLETON-CACHES.

- **[A-APPSTATE-2. Three more process-wide statics: the notification queue, the default store, the URL opener](<SwiftUI parity/Decisions/State and dynamic properties/Per-app render state (APPSTATE).md#a-appstate-2-three-more-process-wide-statics-the-notification-queue-the-default-store-the-url-opener>)** (lane APPSTATE). The inventory named four shared instances (census D-7); a search for mutable statics finds three more. None holds a frame request any longer — a post asks the apps that draw its host, a store write asks the app whose work made it — so none can draw one app's change in another. What each still shares: **Recommendation:** exempt `StorageDefaults.backend` (SwiftUI's model) and `runLoopOpener` (one runner per process, package-only), documented on the CLAUDE.md rule with the caches of SINGLETON-CACHES; make the notification queue per app in a later lane, with the API change.

- **[A-O12-1. A hand over every button, or over links only?](<SwiftUI parity/Decisions/Terminals/Pointer shapes (O12).md#a-o12-1-a-hand-over-every-button-or-over-links-only>)** (lane O12). The study's §C4 and the lane brief say "`pointer` over Link and Button"; the same study's question to the owner (§5, Q2), which the owner answered yes, says "over fields, links and dividers", without buttons; and a Mac's buttons keep the arrow (AppKit's convention; SwiftUI's unmeasured, see above). Shipped as the brief says, and off everywhere until a host's reset is read (B-O12-6), so nothing a user sees depends on the answer yet. **Recommendation:** links only. It's the Mac's convention and what your Q2 answer named; changing it is about an hour.

- **[A-CHURN-1. Presume last frame's scrollbar (hysteresis)](<SwiftUI parity/Decisions/Scrolling/Scrollbar overflow check (CHURN).md#a-churn-1-presume-last-frames-scrollbar-hysteresis>)** (lane CHURN). The first round has to be exact because a bar takes a column: wrapping content can fit at the full width W and overflow at W−1, so whether it gets a bar depends on asking at W. Hysteresis would skip that question while the view had a bar last frame, keeping it as long as the content still overflows at W−1 (which round 2 measures anyway), and drop it only when the content fits there. Recommended: **As now (recommended):** round 1 is asked every frame the content overflowed last; for an eager column it now costs a screenful of rows, not the whole column.

- **[A-CHURN-2. Overlay scrollbars that take no column](<SwiftUI parity/Decisions/Scrolling/Scrollbar overflow check (CHURN).md#a-churn-2-overlay-scrollbars-that-take-no-column>)** (lane CHURN). **Re-checked 2026-10-18 (evening):** this would reverse two standing rules. Deliberate deviations R5 says a bar is a column of the viewport (kept on 10-12 under B24), and R4 says `ScrollGeometry` leaves the bars out (owner: keep, 10-12). It isn't needed for performance now, since with the early stop round 1 is a screenful. Suggested: keep R4 and R5 and decline this, unless you want macOS's overlay look for its own sake. No recommendation written.

- **[A-O9-1. `\.supportsMultipleWindows` is `true`](<SwiftUI parity/Decisions/Presentation and windows/Several scenes on one surface (O9).md#a-o9-1-supportsmultiplewindows-is-true>)** (lane O9). The refusal review proposed shipping it as `false` (X5), when nothing opened a second window; under O9 (b) `openWindow` opens one, over the window in front. SwiftUI's own example reads the value to decide whether to offer an "Open New Window" button, and here the button works. **Recommendation:** `true`, as shipped: it's a minor call I made under your rule for minor questions, and overruling it is a one-line change.

- **[A-W1-1. Should `import TUIkit` bring Foundation's geometry with it?](<SwiftUI parity/Decisions/Shapes, effects and animation/Shapes (W1).md#a-w1-1-should-import-tuikit-bring-foundations-geometry-with-it>)** (lane W1). A shape of an app's own is written against `path(in rect: CGRect)`, and `CGRect` is Foundation's (on Apple platforms, CoreGraphics'). SwiftUI re-exports Foundation, so a SwiftUI file that imports only SwiftUI compiles; a TUIkit file that imports only TUIkit does not — `cannot find type 'CGRect' in scope` (measured with a probe against the built modules). The same is already true of `Date`, `URL` and `SortDescriptor` (the compile corpus imports Foundation for them), so this lane changed nothing;… **Recommendation:** 2. It is what a ported file expects, and the cost of Foundation in scope is one SwiftUI apps already pay.

- **[A-MODALS-1. Keys declared outside a modal sheet still work behind it](<SwiftUI parity/Decisions/Presentation and windows/Sheets, the page around them and their content (MODALS).md#a-modals-1-keys-declared-outside-a-modal-sheet-still-work-behind-it>)** (lane MODALS). A modal presentation makes the page behind it inert on four channels (memory: modal input channels). The mouse is inert across the whole screen, because the dimmed backdrop drops every hit region. Focus is held by the modal's section, which Tab cannot leave. `onKeyEvent` handlers are silenced across the whole tree by `grabInput`. The page drawn beneath the sheet is isolated (`isolatedForBackground()`), so its own status bar items and `.keyboardShortcut`s neither show nor fire. **Recommendation:** 3. The dimmed backdrop already says that the whole screen behind a modal sheet is inert. Three channels of five already behave that way, and a key that works behind the dimming contradicts the picture.

- **[A-PARITYMISC-1. Core Data's FetchRequest family: build it now, or when an app asks?](<SwiftUI parity/Decisions/Small parity items (PARITYMISC).md#a-paritymisc-1-core-datas-fetchrequest-family-build-it-now-or-when-an-app-asks>)** (lane PARITYMISC). Your A18 ruling (2026-10-12, option 1) allows Apple-only API behind `#if canImport` where it is honoured on Apple platforms, and says Core Data's `FetchRequest` "becomes possible" — not that it be built. Nothing is built; the parity map now says the family is permitted and waiting on this, where it used to say a policy forbade it. **Recommendation:** 2. A Core Data app is a GUI app's data layer; a terminal port of one is rare, and the work is days.

- **[A-TRANSITIONS2-1. B52: a custom transition that changes its view's size — lay the body out at each frame's size?](<SwiftUI parity/Decisions/Shapes, effects and animation/Transition follow-ups (TRANSITIONS2).md#a-transitions2-1-b52-a-custom-transition-that-changes-its-views-size--lay-the-body-out-at-each-frames-size>)** (lane TRANSITIONS2). **What SwiftUI does** (`tr1.out` T7, T7b, a `Transition` whose body sets `.frame(height: phase.isIdentity ? nil : 0)` on a 60-point view between two 10-point ones, under an 8 s change): the view's frame grows and shrinks, and the view below moves with it in step — 70 → 63 → 55 → … → 10 as it folds away, 10 → 17 → 25 → … → 70 as it opens. **Recommendation:** option 1, leave it as is. The case B52 was opened for — a collapsing transition whose gap does not close — closes now, through FB16, in every container that glides; what option 2 would add is visible only where a transition names an animation different from its change's.
