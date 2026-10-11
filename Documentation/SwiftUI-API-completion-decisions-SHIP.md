# Completing the SwiftUI API: lane SHIP's decisions for review

*A companion to [`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md),
written by the lane that shipped the owner's size decisions of 2026-10-11: the
`DeadStripUnusedAPI` trait, the README's "Shipping size", the `-deduplicate`
check (Tools/DedupCheck) and the Span check's place. It holds only what that
work raised that was not already decided, in the main file's three parts.*

- **A. Needs your decision.** Nothing has shipped for these.
- **B. Shipped the safe option.** A basic, honest form is in; each entry says
  what the fuller version would be, and what it would cost.
- **C. Declined without asking.** Listed so they can be vetoed.

## B. Shipped the safe option

### B-SHIP-1. The `-deduplicate` check runs on one toolchain, 6.4

*`.github/workflows/ci.yml` (the step "Deduplicated, stripped release programs
…"), `Tools/DedupCheck/ci-check.sh`*

**Shipped:** the check, and the stripped `--selfcheck` and PTY smoke, on the
"macOS 26 · Swift 6.4" lane only, which already builds release, so the step
only links (243 s on the development machine, nearly all of it the PTY smoke).

**What it misses:** which functions fold is the compiler's and the linker's.
Xcode's 6.2.4 folds `EnvironmentValues.buttonStyle` with
`installedButtonAppearance` and 6.4.0 does not (measured 2026-10-10; allowed in
the manifest with its review). A new pair that only 6.2 or 6.3 folds would
pass CI.

**Fuller version and price:** the same step on "macOS 15 · Xcode 26" (6.2.4)
and "macOS 26 · Xcode 26" (6.3), each needing a release build first: about
three minutes of `-O` compile per lane per run (176 s for the whole package on
the development machine with 6.4.0; runners unmeasured), plus the step's four.

### B-SHIP-2. Package.swift's unsafe flags: compile flags behind a trait, no link flags

*`Tools/validate-package-manifest.sh` (commit "A macOS release build lets the
app's link drop …")*

**Shipped:** the manifest check, which failed on any `unsafeFlags` because
SwiftPM used to refuse them in a versioned dependency, now fails on an
`unsafeFlags` LINKER setting (it would land on the app's own link: the owner's
rule that app-wide link flags are the developer's opt-in) and on a COMPILE one
whose condition names no trait. No compiler flag undoes another, so the trait
is the client's only way out (`traits: []`).

**The looser alternative:** allow compile flags without a trait. Simpler, and
no client could turn such a flag off; nothing in the package needs it today.

## C. Declined without asking

### C-SHIP-1. The libswiftCompatibilitySpan check stays in CI, not in the unit tests

*`Tools/check-span-compatibility.sh` (its header, "WHY NOT A UNIT TEST"), on
CI's "macOS 26 · Swift 6.4" lane*

**Asked:** a check that fails if TUIkit starts depending on
`libswiftCompatibilitySpan.dylib`, "ideally in unit tests, if it's cheap enough
and makes sense there, but at the very least in CI".

**Declined:** both forms of a unit test. A test runs a debug build, and a debug
build depends on the library where a release build of the same code does not.
Measured 2026-10-11, macOS 14 target, on Xcode's 6.2.4 and on 6.4.0: a `Span`
handed to a generic function, even an `@inline(__always)` one, leaves the
object an undefined `$ss4SpanVMn` (6.2.4) or `$ss4SpanVMa` (6.4.0) at -Onone
and nothing at -O. The same source built as a library gets an
`LC_LOAD_DYLIB @rpath/libswiftCompatibilitySpan.dylib` at -Onone and none at
-O.

- A test that reads the load commands of the image holding TUIkit's code (the
  form item 4 described) would fail on code that ships clean.
- A test that asserts the test process never loaded the library (review round
  1's suggestion; a 6.2.4 test run does not load it today, measured) fails in
  the same case: the debug image's strong load command makes dyld load the
  toolchain's copy. It adds nothing the first form lacks, and shares its false
  failure.

The debug test bundles are clean today (measured on both toolchains: no load
command names the library, and nothing is imported from it), so either test
would pass now and fail later on a change that ships nothing new.

**What ships instead:** the CI check on the 6.4 lane's release build. It reads
Stress, Example and the objects of every module a library product ships,
TUIkitAppKit's among them, which no executable links: "28 objects of 28
library modules … none refers to a Span-family symbol" on this tree.

**If you want a unit test anyway:** it is cheap, one image's load commands. The
price is the false failure above, the first time TUIkit hands a `Span` to a
generic function. Its fix would be an allow-list of debug-only references,
which is the release check's job.
