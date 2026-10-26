# Test targets split by module: decisions

*The owner asked on 2026-10-12 (B-TC1-1) for the suite to be a test target per
module, so that an edit to a module rebuilds only the tests that can see it, and
on 2026-10-14 for it to be scripted. It landed on 2026-10-14, replacing the
four targets by area of [TT2](<Test targets split by area (TT2).md>). This file
holds the judgement calls the work made that the request did not settle, in the
format of [`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>):*

- **A-TS-n — needs your decision.**
- **B-TS-n — shipped the safe option.** Says what the fuller version would be,
  and its price.
- **C-TS-n — declined.** With the reason.

## The shape

A test file lives in the target of the highest module it needs, counting what
its helpers need: `TUIFoundationTests` (271 files), `TUIAppTests` (255),
one target per feature module (21, from 2 files to 115), and
`TUIIntegrationTests` (163), the one target that still depends on every
module. Helpers live in support targets split the same way:
`TUITestSupport`, `TUIAppTestSupport`, and five feature ones. The 11,561
tests are the same, by name, before and after.

## Build times

Measured on a quiet machine, `swift build --build-tests`, from clean and then
after a private and a public edit in three modules, each reverted and rebuilt
(session notes, `TESTSPLIT/`):

| | 6.2.4 (Xcode's, native build system) before → after | 6.4.0 (swift-build) before → after |
|---|---|---|
| clean (two runs each) | 122, 121 → 105, 121 s | 120, 107 → 114, 112 s |
| no-op | 2.0 → 1.8 s | 3.0 → 3.8 s |
| an edit in TUIMenus (a leaf) | 59–65 → 22–23 s | 87–92 → 33–35 s |
| an edit in TUILists (a middle) | 62–63 → 31–32 s | 90–94 → 53–54 s |
| an edit in TUIFoundation | 79–87 → 69–75 s | 119–121 → 130–137 s |
| an edit in TUIView (a low module) | 17 → 53–56 s | 109–113 → 133–141 s |

An edit to a feature module, where most work happens, rebuilds 40–65% less
time. A clean build is unchanged within the noise. An edit low in the stack
costs more on 6.4, and on 6.2 for TUIView: see B-TS-2 and A-TS-1.

## B. Shipped the safe option

### B-TS-1. A feature's tests that drive the App live with the feature, not with the integration tests

*61 files needed TUILists and TUIApp, 36 TUITables and TUIApp, …*

The request named an integration target for tests needing two modules. Most
tests that need a feature module also need TUIApp — `applyRuntimeServices(from:)`,
which builds a render pass's environment, or one of the App-level harnesses —
and sending them all to the integration target left it at 437 files, the
largest. A feature's target depends on TUIApp instead where one of its files
needs it. An edit to TUIApp then rebuilds those feature targets too, as it
rebuilds every target above TUIApp anyway; an edit to the feature still
rebuilds only the feature's tests and the integration ones.

### B-TS-2. A test target names every module its files import

*Package.swift, the generated `dependencies:` lists*

A test target depends on each module its files import, the low ones
(TUICore, TUIView, …) included, although TUIFoundation re-exports
them. That is what makes an edit to TUIView take longer under 6.2's native
build system than before the split (17 s → 55 s): that build system rebuilds a
target only when one of the modules it names changes, and does not see a module
reached through a re-export (the stale-build bug the session notes record, with
a minimal repro on the owner's Desktop). Before the split, no test target named
TUIView, so an edit to it rebuilt no tests at all — tests that call
TUIView directly kept running stale code until a clean build. Naming the
modules makes those tests rebuild.

**The fuller version** would name only the top modules, restoring the old
times by restoring the hole. Correctness comes before compile time.

### B-TS-3. The placement is read from the compiler's index, not from compiling until it builds

*Tools/TestSplit*

A first version read each file's needs from its object file's undefined
symbols and fed the compiler's errors back a build at a time; the object files
miss what the optimiser inlined and what is named only as a type, and the loop
did not converge (one round reached 9,500 errors). The index store records
every reference by USR; looked up among the declarations each module's own
sources make, it gives each file's modules exactly. Its first plan built clean.
The scripts stay under `Tools/TestSplit` as the record of how each file was
placed; a new file is placed by hand, by CONTRIBUTING.md's rule, and
`Tools/validate-test-boundaries.sh` checks its imports.

## A. Needs your decision

### A-TS-1. A low-module edit is slower on 6.4

*Answered by the owner on 2026-10-23: keep the small test targets separate for
now.* Option 2 was not run, and nothing about the split has changed.

Under 6.4's build system, which has no stale-build hole, an edit to TUIView
takes 133–141 s after the split against 109–113 s before (+23%), and one to
TUIFoundation 130–137 s against 119–121 s (+11%), while edits to feature
modules take 41–62% less. The first draft of this entry guessed at the cause:
the number of test products, which swift-build links one per test target (27
then, against 10 before; 28 since lane O13 added `TUICommandsTests`). It had
not measured it. Options:

1. **Keep it as it is.** An edit to one of the 18 feature modules saves 35–60 s
   on 6.4; one to TUIFoundation or below costs 11–28 s more.
2. **Merge the smallest targets** (Forms 6 files, CurveEditors 2, AppKit 4, Grid 8,
   Search 12) into the integration target: fewer products, and those modules'
   own edits rebuild the integration tests instead. Not measured.
3. **Wait for an upstream fix** to the two causes below.

**What the owner asked.** On 2026-10-15 the owner asked for the slowdown to be
investigated: no merging of targets except as an experiment, the trade-off
being the owner's call, and a bug report written if the cause was in the
build system.

**What the investigation found.** Two causes, neither of them the product count.
The measurements are of a private edit to `BufferModifier.swift` in TUIView
on swiftly's 6.4.0, `swift build --build-tests`, with the running compiler
processes sampled every 0.25 s (session notes, `TESTSPLIT/slow64`).

- **swift-build compiles the test targets one after another.** Of the 133 s
  rebuild, the library modules took the first 30 s or so. The test targets then
  compiled from 32 s to 127 s, and in none of the 344 samples were two test
  targets' compilers running together, although one target's compile used up to
  14 processes. So the time is the sum of the test targets that have to be
  rebuilt, and an edit that reaches all of them pays for all. The earlier
  four-target experiment (TT1) saw swift-build compile test targets one after
  another too. The report lists what was tried: `-j`, `--disable-xctest`,
  `--disable-index-store` and the explicit-module flags. The build's trace
  reported target parallelisation as enabled.
- **An edit to a private declaration rebuilds the same modules as a public
  one.** Every module above the edited one is compiled again, private edit or
  public, and so are the test targets above it:

  | 6.4.0, after the split | private edit | public edit |
  |---|---|---|
  | TUIMenus | 33.6, 33.3 s | 34.7, 32.6 s |
  | TUILists | 53.2, 53.7 s | 54.3, 54.1 s |
  | TUIFoundation | 136.5, 136.0 s | 134.9, 129.6 s |
  | TUIView | 138.3, 141.1 s | 135.9, 133.4 s |

  (each edit and its revert.) A private edit changes nothing a dependent can
  see, yet it is rebuilt.

Two reports for the owner to file with the Swift project were written to the
Desktop on 2026-10-15, one for each cause, the first with the list of what was
tried. Neither is kept in the repository.

**Why it matters.** Since 2026-10-10, 425 of the 604 commits that touched
`Sources` touched TUIFoundation or a module below it (`git log` at
01d6da6a9), so the slower case is the common one. The faster one, an edit to a
feature module, is the edit the split was made for.

**What would change the answer.** An upstream fix for either cause: with
parallel test-target compilation, an edit low in the stack would cost the
longest target and not the sum of them, and the split would be a gain for every
edit. Short of that, the merge of option 2 is the experiment to run, on a quiet
machine, timing an edit to each of the five modules and to TUIFoundation
against the products as they are; it lands only on the owner's word.
