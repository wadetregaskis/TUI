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
