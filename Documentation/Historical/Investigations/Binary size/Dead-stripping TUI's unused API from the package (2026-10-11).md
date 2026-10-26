# Dead-stripping TUI's unused API from the package: `-internalize-at-link` (2026-10-11)

> **Status:** landed, 2026-10-11 (`a3218056d`): the default-on package trait `DeadStripUnusedAPI`. **Decided by:**
> the owner, 2026-10-11 (internalize through a default-on trait: yes). **Working notes** (not in git):
> `SIZE3/q/internalize-pkg/notes.md` (acceptance, plugins, dynamic linking), `SHIP/measure.sh` (the landing
> measurement), `SYMS/notes.md` §2.1 (debugging).

## Question

Swift marks every public symbol "no dead strip", so a statically linked app kept all of TUI's public API whether
it called it or not. `-Xfrontend -internalize-at-link` removes that mark, and an app could pass it, but few would.
Can TUI set it on its own modules from its manifest, so that every app gets the saving with no action, and what
does it break? SwiftPM used to refuse `unsafeFlags` in a dependency resolved by version; whether it still did was
the first thing to find out.

## Answer

- **Yes.** SwiftPM 6.2 lifted the rule (swift-package-manager #8896, in 6.2 as #8914). Every consumer tried accepts
  the flag from a versioned dependency, with no diagnostic, and it reaches only TUI's own compile lines.
- **It saves about 15%** of a stripped hello world and 12% of Stress, the 95% of the every-module saving that TUI's
  modules account for.
- **It breaks one kind of app:** a statically linked app whose `dlopen`ed plugin calls TUI API that the app
  itself never calls. That plugin no longer loads ("symbol not found in flat namespace"). Such an app turns the
  trait off with `traits: []`. A dynamically linked TUI is unaffected.
- **Debugging loses only what was dropped:** lldb's `expr` and breakpoints by name cannot reach public API the
  app never calls, as they already could not reach unused internal functions.

## Key measurements

On the development machine (arm64 macOS 15.8.1 VM). A test library with three tags (no flag; the flag; the flag
behind a default trait) was consumed by version over a `file://` URL:

| consumer | accepted | flag on the library's compile lines | `traits: []` turns it off |
|---|---|---|---|
| SwiftPM 6.2.4 (Xcode 26.3), native and Swift Build | yes | yes | yes |
| SwiftPM 6.3.3, native and Swift Build | yes | yes | yes |
| SwiftPM 6.4.0, Swift Build and native | yes | yes | yes |
| `xcodebuild` 26.3: a root package, and a project with a remote versioned reference | yes | yes | — |

GitHub https remotes and the Xcode GUI were not tried. The landing measurement (`a3218056d`), trait off then on,
stripped, release:

| | Swift 6.4.0 | Xcode's 6.2.4 |
|---|--:|--:|
| Hello | 11,374,080 → 9,700,016 (−14.7%) | 11,476,208 → 9,764,816 (−14.9%) |
| Stress | 12,863,200 → 11,305,104 (−12.1%) | 12,997,296 → 11,402,672 (−12.3%) |
| Hello, unstripped | 25,212,792 → 20,940,200 (−16.9%) | 25,071,080 → 20,742,536 (−17.3%) |

Checks at landing: Stress `--selfcheck` passed and a stripped Hello drew in a PTY, on both toolchains; the Span
check passed. The plugin case was measured on a small library: without the flag the host exported 20 unused symbols
and the plugin loaded; with it, 10, and `dlopen` failed. A dynamic library of the same modules exported the same
24,778 symbols either way. Run time: a quiet-box A/B on the split tree before this work found the flag neutral (warm
−0.3 to −0.9%, cold −1.7 to +1.3%, launch −2.6%); the A/B of the landed trait is owed.

## Reasoning

- **A trait, on by default.** No frontend flag negates `-internalize-at-link`, so a trait is a client's only way
  out. The name says what the trait lets the app's linker do, in the words of `-dead_strip` and Xcode's "Dead Code
  Stripping"; the compiler's word, internalize, tells a reader of a client's manifest nothing.
- **Release builds on macOS only.** Debug builds (and so `swift test` and DocC) are untouched; Linux and Windows are
  unmeasured.
- **Every module a library product ships**, computed in the manifest; not the test support or width-corpus targets,
  which no app links.
- **Xcode apps** get the saving only with `DEAD_CODE_STRIPPING = YES`, which is not Xcode's default (measured,
  Xcode 26.3); the README says so.
- **The manifest check** that once failed on any `unsafeFlags` now enforces what such a flag may reach: a compile
  flag only behind a trait, and no link flag but TUI's own unexport patterns (decisions
  [B-SHIP-2](<../../../SwiftUI parity/Decisions/Compile time and binary size/Shipping size (SHIP).md#b-ship-2-packageswifts-unsafe-flags-every-one-behind-a-trait-link-flags-only-tuis-unexport-patterns>)).

## Since

The unexport list became a second default trait, `UnexportTUISymbols`, on 2026-10-12, because ld refuses it beside
an export list of the developer's own (decisions
[B-SHIP2-1](<../../../SwiftUI parity/Decisions/Compile time and binary size/Shipping size and products, second round (SHIP2).md#b-ship2-1--unexported_symbol-is-a-trait-of-its-own-unexporttuisymbols-beside-deadstripunusedapi>)).
See also [which links TUI's flags reach](<Which links TUI's flags reach, and the debug map (2026-10-11).md>),
README [Shipping size](<../../../../README.md#shipping-size>), and
[where the bytes of a TUI app go](<Where the bytes of a TUI app go (2026-10-10).md>).
