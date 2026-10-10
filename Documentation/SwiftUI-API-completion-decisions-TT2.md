# Completing the SwiftUI API: decisions from lane TT2

*Lane TT2 landed the test-target split the owner approved on 2026-10-08 ("fine,
if it has a notable benefit"), which lane TT1 had measured as an experiment: the
umbrella suite, one test target of 1,178 files, is four test targets by area
and a plain support target, TUIkitTestSupport. It changed no public API and
nothing the library does. This file holds the judgement calls the work reached
that the brief did not already settle, in the format of
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md):*

- **A-TT2-n — needs your decision.** Nothing has shipped for these.
- **B-TT2-n — shipped the safe option.** Says what the fuller version would be,
  and its price.
- **C-TT2-n — declined.** With the reason.

There is no A or C entry.

## B. Shipped the safe option

### B-TT2-1. The support target compiles empty in a release build, and a release test build turns it on by hand

*TUIkitTestSupport: 42 files, every one `@testable import`ing library modules*

`swift build` builds every target that is not a test target, so a plain support
target is built by `swift build -c release` too, where nothing has testability,
and its `@testable import`s fail the build. CI builds release on two lanes
(macOS 26 with Swift 6.4, Linux 6.3 arm64), and README and CONTRIBUTING tell
contributors to. Measured first, in probe packages, on Xcode 26's Swift 6.2.4
and swiftly's 6.3.3 and 6.4.0, and on 6.3.3's static Linux SDK (session notes,
TT2/probe; the support-target commit's message has the table):

| shape | `swift build -c release` | `swift test -c release` |
|---|---|---|
| plain target | fails on all three, and on Linux | passes |
| a test target the others depend on | passes on 6.2.4 and 6.3.3; fails on 6.4.0, whose build system builds it anyway | passes |
| plain target, CI building `--product` instead | fails on 6.2.4 and 6.3.3: a library product's `--product` builds every target | — |
| `package` access instead of `@testable` | passes everywhere | passes |
| plain target, files under `#if DEBUG` | passes everywhere | fails: the module is empty |
| **plain target, files under a define set for debug builds (shipped)** | **passes everywhere** | **fails unless the define is passed** |

**Shipped:** every file of the target is wrapped in
`#if TUIKIT_TEST_SUPPORT && canImport(Testing)`, and the target defines
`TUIKIT_TEST_SUPPORT` for debug builds only. `canImport(Testing)` because the
static Linux SDK has no Testing module, and a debug build of the whole package
for it failed at the support target without it. `Tools/validate-test-boundaries.sh`
fails a file that is not wrapped.

**The price:** a release *test* build must pass the define itself:
`swift build -c release --build-tests -Xswiftc -enable-testing -Xswiftc -DTUIKIT_TEST_SUPPORT`
(MainActorBox.swift's recipe says so). Without it the four test targets fail to
compile, loudly, with "cannot find … in scope". `#if DEBUG` was the simpler
spelling, but the only way back from it, `-Xswiftc -DDEBUG`, would also turn on
the library's own `#if DEBUG` code in the build meant to test release.

**The fuller version** is `package` access: no guard and no define, because
nothing would need `@testable`. Its price is that every library internal a
helper reaches would become `package`, visible to every module of the package;
how many that is was not measured.

### B-TT2-2. ParallelTest's weight cache is documented, not migrated

*Tools/ParallelTest, `fill_weights`*

The cache is keyed by test ID, and an ID names its module, so the 6,628 tests
that moved out of `TUIkitTests` are unknown to a cache calibrated before the
split, and their suites' recorded work is filed under `TUIkitTests.<Suite>`,
which `fill_weights` does not match to `TUIkitAppTests.<Suite>`. They are priced
at the median until `--calibrate` runs again, which the README now says. CI
keeps no cache.

**The fuller version:** let `fill_weights` match a moved suite's lost work by
the suite's name without its module, so that a move between test targets costs
nothing. A few lines; the price is that two suites of one name in different
targets would share each other's lost work, and a recalibration is cheaper
than either.
