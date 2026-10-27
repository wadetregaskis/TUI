# Investigations

This folder holds the committed summaries of investigations: one page each, for a question that
took measuring, probing or reading to answer, and whose answer someone will want again. A summary
says:

- **the question**, as it was asked, and by whom;
- **the answer**, up front, in a sentence or two;
- **the key measurements**, with how and on what each was taken (toolchain, OS, terminal and its
  version, commit), so that a reader can repeat one;
- **the reasoning** that gets from the measurements to the answer, including what was ruled out
  and why;
- **links**: to the code, the commits, the decisions entry and the living documents
  (for example `Terminals/Terminal compatibility survey.md`) that the answer changed.

A summary is written while its investigation is live, and stays here while the decision it informs
is open. When that decision lands, the summary joins the story of its subject in `Historical/` (as
an appendix, or as a story of its own when nothing else covers the subject), so that this folder
lists only what is still being decided.

## Working notes

`Documentation/Working notes/` is not committed: `.gitignore` excludes it, and it exists only on the
machine that made it. It holds an investigation's raw material — notes as they were taken, probe
programs and scripts, captured terminal output, traces, benchmark runs — which is large, easily
reproduced, or both. Nothing committed may depend on it: a document links to a summary here, never
into the working notes, and `Tools/validate-markdown-links.py` fails on a link into them, because
nobody else has those files. What a reader needs from an investigation belongs in its summary.

## Index

Each row names the working-notes folders that hold the investigation's raw material, for whoever has
them; the summary is what everyone else reads. A decided summary's row links to the story that now
holds it.

### Still being decided (this folder)

| summary | decision | working notes |
|---|---|---|
| Binary size: [Full LTO, conditional runtime records and the reflection descriptor request](<Full LTO, conditional runtime records and the reflection descriptor request.md>) (2026-10-10, 2026-10-11) | deferred; a feature request is drafted for the owner to file | `SIZE3/q/lto`, `CONDREQ` |

### Decided (in the `Historical/` stories)

| summary | decision | working notes |
|---|---|---|
| Architecture: [SwiftUI's update model beside TUI's](<../Historical/State and dynamic properties/The update model: when effects run.md>) (2026-10-24) | landed: effects run after the walk in SwiftUI's order, and a frame they change is walked again before it is written (`910819db3`, decisions B-D5G-11); §6 step 3, toolbars and focused values through the same loop, is not built | none |
| SwiftUI behaviour: [SwiftUI's update and effect ordering, measured](<../Historical/State and dynamic properties/The update model: when effects run.md>) (2026-10-24) | informed the convergence above; context only | none |
| Terminal graphics: [Thin lines between rows with Kitty graphics](<../Historical/Lists, tables and tabs/Stripes, surfaces and separators.md#appendix-thin-lines-between-rows-with-kitty-graphics-2026-10-08>) (2026-10-08) | landed: the `.hairline` separator look on Ghostty (decisions A-D6L-2), its row marking memoised (`e807fce55`) | `KGP` |
| Linux toolchain: [GNU ld RWX LOAD segment warning on Linux aarch64](<../Historical/Module split, compile time and binary size/The linker's RWX warning on Linux aarch64.md>) (2026-10-23) | documented; no change to TUI: the workaround is `-Xlinker -z -Xlinker separate-code` | none |
| Dynamic properties: [Finding dynamic properties from values or from types](<../Historical/State and dynamic properties/Finding dynamic properties, and writing back what update() changes.md>) | the hybrid, keeping TUI's reaches: lanes DYNVFIX and DYNVCLAIM landed | `DYNP/optional`, `DYNV`, `DYNV2`, `DYNVFIX`, `DYNVCLAIM` |
| Binary size: [Where the bytes of a TUI app go](<../Historical/Module split, compile time and binary size/Binary size.md>) | products, internalize, unexport and package changes landed; flags stay the app's | `SIZE2`, `SIZE3` |
| Binary size: [A program copied out of its build stopped at launch, libswiftCompatibilitySpan](<../Historical/Module split, compile time and binary size/Binary size.md>) | swift-collections dropped; CI check; upstream drafts unfiled | `SIZE3/q/span`, `SIZE3/q/spanq`, `NODQ` |
| Binary size: [Dead-stripping TUI's unused API from the package](<../Historical/Module split, compile time and binary size/Binary size.md>) | the default trait `DeadStripUnusedAPI` | `SIZE3/q/internalize-pkg`, `SHIP` |
| Binary size: [Whether -deduplicate is safe for TUI](<../Historical/Module split, compile time and binary size/Binary size.md>) | safe today; the app's opt-in; `Tools/DedupCheck` in CI | `SIZE3/fu/dedup`, `SIZE3/fu/dedup-pty`, `SIZE3/q/dedup-check` |
| Binary size: [Which links TUI's flags reach, and the debug map](<../Historical/Module split, compile time and binary size/Binary size.md>) | no app-wide flags from the package, except TUI's own unexport patterns | `SYMS` |
| Binary size: [SwiftUI's size beside TUI's](<../Historical/Module split, compile time and binary size/Binary size.md>) | context only | `SIZE3/q/swiftui` |
| Compile time: [Type-check time on Swift 6.4, test expectations and exit tests](<../Historical/Module split, compile time and binary size/Compile time and the test targets.md>) | test rewrites and the test-target split landed; exit tests are the owner's (A-TC1-1) | `TC1`, `TC2`, `EXITTC`, `buildtime/typecheck` |
| Compile time: [Selective optimisation attributes](<../Historical/Module split, compile time and binary size/Compile time and the test targets.md>) | the hint cache only; no attribute | `OPTN` |
| Compile time: [Pre-specialisation across module boundaries](<../Historical/Module split, compile time and binary size/Compile time and the test targets.md>) | adopt none; `@inlinable` stays the remedy | `PRESPEC` |
| Module split: [The module split's run-time cost, step by step](<../Historical/Module split, compile time and binary size/The module split.md>) | recovered; `table-tail` +0.55% left open | `SPB5`, `SPB5b`, `SPB6`, `CTL`, `RES`, `perf/results` |
| Module split: [What the module split delivered](<../Historical/Module split, compile time and binary size/The module split.md>) | landed: modules, products, four test targets | `buildtime`, `perf/c9bt`, `TT1`, `TT2` |

### Recorded elsewhere

These investigations already have a committed record of their own, so they have no summary here.

| investigation | working notes | where it is recorded |
|---|---|---|
| The SF Symbols name table: front-coding against DEFLATE or the resource bundle (2026-10-10) | `SIZE3/q/sf-table`, `SFQ` | [Baking a large static lookup table in Swift](<../Swift language/Baking a large static lookup table in Swift.md#front-coding-the-names-2026-10-11>), and commits `f8ec22f19` and `8d3260d05` |
| Single-module LLVM emission (2026-10-11) | `perf/results/sme`, `SYMS` | [Future options](<../Future options.md#single-module-llvm-emission>) |
| The machine outliner and mergeable traps (2026-10-11) | `SYMS` | [Future options](<../Future options.md#the-machine-outliner-and-mergeable-traps>) |
| Per-module library products, and mixing them with the umbrella (2026-10-11) | `C9B` | [Per-module products](<../Historical/Module split, compile time and binary size/Per-module products.md>) and decisions [C9B](<../Historical/Module split, compile time and binary size/Per-module products.md>) |
| Running without the resource bundle (2026-10-10) | `BNDL` | decisions [BNDL](<../Historical/Module split, compile time and binary size/Binary size.md>) |
| Where a clean release build's time goes (2026-10-07) | `buildtime` | [Compile time and binary size analysis](<../Historical/Module split, compile time and binary size/Compile time and the test targets.md>) |
| The module map, and how to split the module (2026-10-07) | `buildtime/split2` | [Module split plan, revision 4](<../Historical/Module split, compile time and binary size/The module split.md>), which holds each step's record too |
| Swift 6.3.3's release error in `Theme.swift` (2026-10-08) | `R63` | the message of commit `fed3b535e`, which holds the two-module reduction and the SIL that shows the lost isolation |
| Test targets split by area (2026-10-10) | `TT1`, `TT2` | decisions [TT2](<../Historical/Module split, compile time and binary size/Compile time and the test targets.md>), and [Future options](<../Future options.md#the-rest-of-the-test-targets-expect-floor>) |
| Pay-for-use run-loop services (2026-10-11) | `PAYU` | [Future options](<../Future options.md#pay-for-use-run-loop-services>) (deferred by the owner, 2026-10-12) |
| Large pastes and over-long input sequences (2026-10-11, 2026-10-12) | `PASTE`, `PASTE2` | decisions [PASTE](<../Historical/Input, keys and gestures/Large pastes and over-long input sequences.md>) |
| Alignment guides outside their view, and the owner's questions on them (2026-10-11, 2026-10-12) | `GUIDE`, `GUIDE2` | [the story](<../Historical/Layout and geometry/Alignment guides that travel out of their view.md>) |
| The owner's 2026-10-12 rulings on the B entries and the O items | `DECB`, `REFO` | [Completing the SwiftUI API](<../Historical/SwiftUI parity process/Completing the SwiftUI API.md>) and [Refusals re-examined](<../Historical/SwiftUI parity process/The refusals re-examined (wave 17).md>) |
| State keys inside a `DynamicProperty` (2026-10-11) | `SKEY` | decisions [SKEY](<../Historical/State and dynamic properties/Finding dynamic properties, and writing back what update() changes.md>) |
| Class properties held by several views (2026-10-12) | `DYNVCLAIM` | [the design, condensed](<../Historical/State and dynamic properties/A class property held by several views.md>), decisions [DYNVFIX](<../Historical/State and dynamic properties/Finding dynamic properties, and writing back what update() changes.md>) B-DYNVFIX-3, and decisions [DYNVCLAIM](<../Historical/State and dynamic properties/A class property held by several views.md>) |
| Deliberate behavioural differences from SwiftUI (2026-10-12) | `DEVS` | [Deliberate deviations from SwiftUI](<../SwiftUI parity/Deliberate deviations from SwiftUI.md>) |
| The decisions files of the other API-completion lanes | the lane's tag | the [Historical](<../Historical/README.md>) stories, found by id through the [index of decision ids](<../Historical/Index of decision ids.md>) |
