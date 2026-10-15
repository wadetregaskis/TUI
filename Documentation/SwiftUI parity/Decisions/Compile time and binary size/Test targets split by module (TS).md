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
its helpers need: `TUIkitFoundationTests` (271 files), `TUIkitAppTests` (255),
one target per feature module (21, from 2 files to 115), and
`TUIkitIntegrationTests` (163), the one target that still depends on every
module. Helpers live in support targets split the same way:
`TUIkitTestSupport`, `TUIkitAppTestSupport`, and five feature ones. The 11,561
tests are the same, by name, before and after.

## Build times

Measured on a quiet machine, `swift build --build-tests`, from clean and then
after a private and a public edit in three modules, each reverted and rebuilt
(session notes, `TESTSPLIT/`):

| | 6.2.4 (Xcode's, native build system) before → after | 6.4.0 (swift-build) before → after |
|---|---|---|
| clean (two runs each) | 122, 121 → 105, 121 s | 120, 107 → 114, 112 s |
| no-op | 2.0 → 1.8 s | 3.0 → 3.8 s |
| an edit in TUIkitMenus (a leaf) | 59–65 → 22–23 s | 87–92 → 33–35 s |
| an edit in TUIkitLists (a middle) | 62–63 → 31–32 s | 90–94 → 53–54 s |
| an edit in TUIkitFoundation | 79–87 → 69–75 s | 119–121 → 130–137 s |
| an edit in TUIkitView (a low module) | 17 → 53–56 s | 109–113 → 133–141 s |

An edit to a feature module, where most work happens, rebuilds 40–65% less
time. A clean build is unchanged within the noise. An edit low in the stack
costs more on 6.4, and on 6.2 for TUIkitView: see B-TS-2 and A-TS-1.

## B. Shipped the safe option

### B-TS-1. A feature's tests that drive the App live with the feature, not with the integration tests

*61 files needed TUIkitLists and TUIkitApp, 36 TUIkitTables and TUIkitApp, …*

The request named an integration target for tests needing two modules. Most
tests that need a feature module also need TUIkitApp — `applyRuntimeServices(from:)`,
which builds a render pass's environment, or one of the App-level harnesses —
and sending them all to the integration target left it at 437 files, the
largest. A feature's target depends on TUIkitApp instead where one of its files
needs it. An edit to TUIkitApp then rebuilds those feature targets too, as it
rebuilds every target above TUIkitApp anyway; an edit to the feature still
rebuilds only the feature's tests and the integration ones.

### B-TS-2. A test target names every module its files import

*Package.swift, the generated `dependencies:` lists*

A test target depends on each module its files import, the low ones
(TUIkitCore, TUIkitView, …) included, although TUIkitFoundation re-exports
them. That is what makes an edit to TUIkitView take longer under 6.2's native
build system than before the split (17 s → 55 s): that build system rebuilds a
target only when one of the modules it names changes, and does not see a module
reached through a re-export (the stale-build bug the session notes record, with
a minimal repro on the owner's Desktop). Before the split, no test target named
TUIkitView, so an edit to it rebuilt no tests at all — tests that call
TUIkitView directly kept running stale code until a clean build. Naming the
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

Under 6.4's build system, which has no stale-build hole, an edit to TUIkitView
takes 133–141 s after the split against 109–113 s before (+23%), and one to
TUIkitFoundation 130–137 s against 119–121 s (+11%), while edits to feature
modules take 41–62% less. The likely cause is the number of test
products: swift-build links one per test target, 27 now against 10 before, and
an edit to a low module relinks them all. Options:

1. **Keep it as it is.** An edit to one of the 18 feature modules saves 35–60 s
   on 6.4; one to TUIkitFoundation or below costs 11–28 s more.
2. **Merge the smallest targets** (Forms 6 files, CurveEditors 2, AppKit 4, Grid 8,
   Search 12) into the integration target: fewer products, and those modules'
   own edits rebuild the integration tests instead. Not measured.
