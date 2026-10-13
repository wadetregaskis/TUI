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
is open. When that decision lands, the summary moves to `Historical/Investigations/`, dated in its
name as `Historical/`'s other files are, so that this folder lists only what is still being decided.

## Working notes

`Documentation/Working notes/` is not committed: `.gitignore` excludes it, and it exists only on the
machine that made it. It holds an investigation's raw material — notes as they were taken, probe
programs and scripts, captured terminal output, traces, benchmark runs — which is large, easily
reproduced, or both. Nothing committed may depend on it: a document links to a summary here, never
into the working notes, and `Tools/validate-markdown-links.py` fails on a link into them, because
nobody else has those files. What a reader needs from an investigation belongs in its summary.

## Index

Each row names the working-notes folders that hold the investigation's raw material, for whoever has
them; the summary is what everyone else reads. `Historical/Investigations/` groups its summaries in
topic folders (`Binary size/`, `Compile time/`, `Module split/`); a summary that moves there joins its
topic's folder, or starts one when a second summary shares its topic.

### Still being decided (this folder)

| summary | decision | working notes |
|---|---|---|
| Binary size: [Full LTO, conditional runtime records and the reflection descriptor request](<Full LTO, conditional runtime records and the reflection descriptor request.md>) (2026-10-10, 2026-10-11) | deferred; a feature request is drafted for the owner to file | `SIZE3/q/lto`, `CONDREQ` |
| Terminal graphics: [Thin lines between rows with Kitty graphics](<Thin lines between rows with Kitty graphics.md>) (2026-10-08) | feasible on Ghostty and iTerm2; the prototype waits to be scheduled | `KGP` |

### Decided (`Historical/Investigations/`)

| summary | decision | working notes |
|---|---|---|
| Dynamic properties: [Finding dynamic properties from values or from types](<../Historical/Investigations/Finding dynamic properties from values or from types (2026-10-12).md>) | the hybrid, keeping TUIkit's reaches: lanes DYNVFIX and DYNVCLAIM landed | `DYNP/optional`, `DYNV`, `DYNV2`, `DYNVFIX`, `DYNVCLAIM` |
| Binary size: [Where the bytes of a TUIkit app go](<../Historical/Investigations/Binary size/Where the bytes of a TUIkit app go (2026-10-10).md>) | products, internalize, unexport and package changes landed; flags stay the app's | `SIZE2`, `SIZE3` |
| Binary size: [A program copied out of its build stopped at launch, libswiftCompatibilitySpan](<../Historical/Investigations/Binary size/A program copied out of its build stopped at launch, libswiftCompatibilitySpan (2026-10-11).md>) | swift-collections dropped; CI check; upstream drafts unfiled | `SIZE3/q/span`, `SIZE3/q/spanq`, `NODQ` |
| Binary size: [Dead-stripping TUIkit's unused API from the package](<../Historical/Investigations/Binary size/Dead-stripping TUIkit's unused API from the package (2026-10-11).md>) | the default trait `DeadStripUnusedAPI` | `SIZE3/q/internalize-pkg`, `SHIP` |
| Binary size: [Whether -deduplicate is safe for TUIkit](<../Historical/Investigations/Binary size/Whether -deduplicate is safe for TUIkit (2026-10-11).md>) | safe today; the app's opt-in; `Tools/DedupCheck` in CI | `SIZE3/fu/dedup`, `SIZE3/fu/dedup-pty`, `SIZE3/q/dedup-check` |
| Binary size: [Which links TUIkit's flags reach, and the debug map](<../Historical/Investigations/Binary size/Which links TUIkit's flags reach, and the debug map (2026-10-11).md>) | no app-wide flags from the package, except TUIkit's own unexport patterns | `SYMS` |
| Binary size: [SwiftUI's size beside TUIkit's](<../Historical/Investigations/Binary size/SwiftUI's size beside TUIkit's (2026-10-10).md>) | context only | `SIZE3/q/swiftui` |
| Compile time: [Type-check time on Swift 6.4, test expectations and exit tests](<../Historical/Investigations/Compile time/Type-check time on Swift 6.4, test expectations and exit tests (2026-10-08).md>) | test rewrites and the test-target split landed; exit tests are the owner's (A-TC1-1) | `TC1`, `TC2`, `EXITTC`, `buildtime/typecheck` |
| Compile time: [Selective optimisation attributes](<../Historical/Investigations/Compile time/Selective optimisation attributes (2026-10-08).md>) | the hint cache only; no attribute | `OPTN` |
| Compile time: [Pre-specialisation across module boundaries](<../Historical/Investigations/Compile time/Pre-specialisation across module boundaries (2026-10-08).md>) | adopt none; `@inlinable` stays the remedy | `PRESPEC` |
| Module split: [The module split's run-time cost, step by step](<../Historical/Investigations/Module split/The module split's run-time cost, step by step (2026-10-10).md>) | recovered; `table-tail` +0.55% left open | `SPB5`, `SPB5b`, `SPB6`, `CTL`, `RES`, `perf/results` |
| Module split: [What the module split delivered](<../Historical/Investigations/Module split/What the module split delivered, build time, size and tests (2026-10-11).md>) | landed: modules, products, four test targets | `buildtime`, `perf/c9bt`, `TT1`, `TT2` |

### Recorded elsewhere

These investigations already have a committed record of their own, so they have no summary here.

| investigation | working notes | where it is recorded |
|---|---|---|
| The SF Symbols name table: front-coding against DEFLATE or the resource bundle (2026-10-10) | `SIZE3/q/sf-table`, `SFQ` | [Baking a large static lookup table in Swift](<../Swift language/Baking a large static lookup table in Swift.md#front-coding-the-names-2026-10-11>), and commits `f8ec22f19` and `8d3260d05` |
| Single-module LLVM emission (2026-10-11) | `perf/results/sme`, `SYMS` | [Future options](<../Future options.md#single-module-llvm-emission>) |
| The machine outliner and mergeable traps (2026-10-11) | `SYMS` | [Future options](<../Future options.md#the-machine-outliner-and-mergeable-traps>) |
| Per-module library products, and mixing them with the umbrella (2026-10-11) | `C9B` | [Per-module products](<../Historical/Per-module products (2026-10-11).md>) and decisions [C9B](<../SwiftUI parity/Decisions/Module split/Library products for every module (C9B).md>) |
| Running without the resource bundle (2026-10-10) | `BNDL` | decisions [BNDL](<../SwiftUI parity/Decisions/Compile time and binary size/Running without the resource bundle (BNDL).md>) |
| Where a clean release build's time goes (2026-10-07) | `buildtime` | [Compile time and binary size analysis](<../Historical/Compile time and binary size analysis (2026-10-07).md>) |
| The module map, and how to split the module (2026-10-07) | `buildtime/split2` | [Module split plan, revision 4](<../Historical/Module split plan, revision 4 (2026-10-07).md>), and the decisions file of each step in [Decisions/Module split](<../SwiftUI parity/Decisions/Module split>) |
| Swift 6.3.3's release error in `Theme.swift` (2026-10-08) | `R63` | the message of commit `fed3b535e`, which holds the two-module reduction and the SIL that shows the lost isolation |
| Test targets split by area (2026-10-10) | `TT1`, `TT2` | decisions [TT2](<../SwiftUI parity/Decisions/Compile time and binary size/Test targets split by area (TT2).md>), and [Future options](<../Future options.md#the-rest-of-the-test-targets-expect-floor>) |
| Pay-for-use run-loop services (2026-10-11) | `PAYU` | [Future options](<../Future options.md#pay-for-use-run-loop-services>) (deferred by the owner, 2026-10-12) |
| Large pastes and over-long input sequences (2026-10-11, 2026-10-12) | `PASTE`, `PASTE2` | decisions [PASTE](<../SwiftUI parity/Decisions/Large pastes and over-long input sequences (PASTE).md>) |
| Alignment guides outside their view, and the owner's questions on them (2026-10-11, 2026-10-12) | `GUIDE`, `GUIDE2` | decisions [GUIDE](<../SwiftUI parity/Decisions/Alignment guides outside their view (GUIDE).md>) |
| The owner's 2026-10-12 rulings on the B entries and the O items | `DECB`, `REFO` | the main [decisions document](<../SwiftUI parity/Decisions/SwiftUI API completion decisions.md>) and [Refusals re-examined](<../SwiftUI parity/Refusals re-examined, wave 17 (2026-10-03).md>) |
| State keys inside a `DynamicProperty` (2026-10-11) | `SKEY` | decisions [SKEY](<../SwiftUI parity/Decisions/State keys inside a DynamicProperty (SKEY).md>) |
| Class properties held by several views (2026-10-12) | `DYNVCLAIM` | [the design, condensed](<../Historical/Class properties held by several views, design (2026-10-12).md>), decisions [DYNVFIX](<../SwiftUI parity/Decisions/Finding dynamic properties from declared types (DYNVFIX).md>) B-DYNVFIX-3, and decisions [DYNVCLAIM](<../SwiftUI parity/Decisions/Class properties held by several views (DYNVCLAIM).md>) |
| Deliberate behavioural differences from SwiftUI (2026-10-12) | `DEVS` | [Deliberate deviations from SwiftUI](<../SwiftUI parity/Deliberate deviations from SwiftUI.md>) |
| The decisions files of the other API-completion lanes | the lane's tag | [Decisions](<../SwiftUI parity/Decisions>), one file per lane |
