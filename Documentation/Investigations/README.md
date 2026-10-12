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
them; the summary is what everyone else reads.

### Still being decided (this folder)

| summary | decision | working notes |
|---|---|---|
| Binary size: [Full LTO, conditional runtime records and the reflection descriptor request](<Binary size/Full LTO, conditional runtime records and the reflection descriptor request.md>) (2026-10-10, 2026-10-11) | deferred; a feature request is drafted for the owner to file | `SIZE3/q/lto`, `CONDREQ` |

### Decided (`Historical/Investigations/`)

| summary | decision | working notes |
|---|---|---|
| Binary size: [Where the bytes of a TUIkit app go](<../Historical/Investigations/Binary size/Where the bytes of a TUIkit app go (2026-10-10).md>) | products, internalize, unexport and package changes landed; flags stay the app's | `SIZE2`, `SIZE3` |
| Binary size: [A program copied out of its build stopped at launch, libswiftCompatibilitySpan](<../Historical/Investigations/Binary size/A program copied out of its build stopped at launch, libswiftCompatibilitySpan (2026-10-11).md>) | swift-collections dropped; CI check; upstream drafts unfiled | `SIZE3/q/span`, `SIZE3/q/spanq`, `NODQ` |
| Binary size: [Dead-stripping TUIkit's unused API from the package](<../Historical/Investigations/Binary size/Dead-stripping TUIkit's unused API from the package (2026-10-11).md>) | the default trait `DeadStripUnusedAPI` | `SIZE3/q/internalize-pkg`, `SHIP` |
| Binary size: [Whether -deduplicate is safe for TUIkit](<../Historical/Investigations/Binary size/Whether -deduplicate is safe for TUIkit (2026-10-11).md>) | safe today; the app's opt-in; `Tools/DedupCheck` in CI | `SIZE3/fu/dedup`, `SIZE3/fu/dedup-pty`, `SIZE3/q/dedup-check` |
| Binary size: [Which links TUIkit's flags reach, and the debug map](<../Historical/Investigations/Binary size/Which links TUIkit's flags reach, and the debug map (2026-10-11).md>) | no app-wide flags from the package, except TUIkit's own unexport patterns | `SYMS` |
| Binary size: [SwiftUI's size beside TUIkit's](<../Historical/Investigations/Binary size/SwiftUI's size beside TUIkit's (2026-10-10).md>) | context only | `SIZE3/q/swiftui` |

### Recorded elsewhere

These investigations already have a committed record of their own, so they have no summary here.

| investigation | working notes | where it is recorded |
|---|---|---|
| The SF Symbols name table: front-coding against DEFLATE or the resource bundle (2026-10-10) | `SIZE3/q/sf-table`, `SFQ` | [Baking a large static lookup table in Swift](<../Swift language/Baking a large static lookup table in Swift.md#front-coding-the-names-2026-10-11>), and commits `f8ec22f19` and `8d3260d05` |
| Single-module LLVM emission (2026-10-11) | `perf/results/sme`, `SYMS` | [Future options](<../Future options.md#single-module-llvm-emission>) |
| The machine outliner and mergeable traps (2026-10-11) | `SYMS` | [Future options](<../Future options.md#the-machine-outliner-and-mergeable-traps>) |
| Per-module library products, and mixing them with the umbrella (2026-10-11) | `C9B` | [Per-module products](<../Historical/Per-module products (2026-10-11).md>) and decisions [C9B](<../SwiftUI parity/Decisions/Module split/Library products for every module (C9B).md>) |
| Running without the resource bundle (2026-10-10) | `BNDL` | decisions [BNDL](<../SwiftUI parity/Decisions/Compile time and binary size/Running without the resource bundle (BNDL).md>) |
