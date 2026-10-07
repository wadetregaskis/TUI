# TUIkit: clean release build time and binary size

> **What this is.** The analysis behind the 2026-10 compile-time and binary-size work: where a clean release build
> of an app using TUIkit spends its time and where the shipped bytes go, with the levers ranked and priced. Written by
> five analyst agents, a synthesis and a skeptic's check (2026-10-07), with the coordinator's later measurements
> appended at the end. It led to two decisions: the project's own builds use Xcode's Swift 6.2.4 rather than
> swiftly's assertions build (−26% to −42%), and TUIkit is split into modules (see
> `Module split plan, revision 4 (2026-10-07).md`, beside this file).
>
> **Paths.** Evidence is cited by paths relative to the maintainers' working notes (`buildtime/…`, `split/…`,
> `challenge/…`); those files are not in this repository.

TUIkit at 14d09c6a0, 2026-10-07. Measured on a shared 12-core arm64 VM, so wall times are noisy: rank within one run and prefer counters. Revised after the skeptic's review: figures are re-based to Xcode's toolchain, and the claims the review refuted are removed.

## Summary

1. **Most of the gap is the toolchain.** The baseline compiler, swiftly's swift.org 6.2.4, is an assertions build: `swift --version` prints `Build config: +assertions`. On macOS it also rebuilds 19 SDK module interfaces that Xcode ships prebuilt. In a paired run, Xcode 26's own 6.2.4 reached the end of the TUIkit job in **86.4 s instead of 116.7 s (−30.2 s, −26%)**. It generated the same IR (1,413,093 vs 1,413,591 instructions; 36,317 SILGen functions in both). Every saving below is re-based to Xcode's toolchain unless it says otherwise.
2. **Inside the build, SIL optimisation dominates.** On Xcode's toolchain the TUIkit job takes 68.1 s: SIL optimisation 39.6 s (58%), type checking 10.5, LLVM 5.4, IRGen 3.2, SILGen 2.3. The chain Core → View → TUIkit runs serially, so the build gets only about 1.7× parallelism.
3. **Only one package-side lever is large: splitting the TUIkit module.** It saves at most about 21 s before the `@inlinable` repairs that runtime needs, and it costs bytes. The runtime-neutral package-side changes together save **about 3 s** (about 3.5%).
4. **Dead stripping keeps nearly all of TUIkit.** Hello and Typical differ by only 16,560 B. Public symbols are marked `[no dead strip]`, and conformance records root the witness tables. The two large byte levers are flags that an app developer passes to `swift build`: `-internalize-at-link` (−1.64 MB, −14.7%) and `-Osize` (−1.02 MB, −9.1%; its runtime cost is unmeasured). Neither is available to Xcode consumers. Package-side source changes save about 0.3 MB.
5. **A package used as a dependency can't use `unsafeFlags`, so only source changes reach every consumer.** Compiler flags work only when the app developer passes them on the `swift build` command line. Xcode builds packages with its own per-configuration settings.

## Where the time goes

Paired clean `swift build -c release -j 8 --target TUIkit`: same commit, same SDK, fresh scratch path each time, all in one slot window (`challenge/tc3.sh`, `tc3.log`). Times are seconds from the first frontend job.

| Toolchain | Core ends | TUIkit job | TUIkit ends | Sema | SILGen | SIL opt | IRGen | LLVM | Outer wall |
|---|---|---|---|---|---|---|---|---|---|
| Xcode 26 6.2.4 | 12.2 | 68.1 | **86.4** | 10.5 | 2.3 | 39.6 | 3.2 | 5.4 | 97.4 |
| swiftly 6.2.4, +assertions (the baseline's) | 21.3 | 88.2 | 116.7 | 13.3 | 4.9 | 48.6 | 4.8 | 6.5 | 123.6 |
| swift.org 6.4.0, native build system | 16.7 | 78.5 | 101.4 | 11.7 | 3.1 | 46.9 | 3.4 | 5.2 | 111.7 |

- **Where the −30 s comes from.** About 9 s is Core's imports: a cold import of Core's import set takes 9.19 s on swiftly (19 interface rebuilds) and 1.22 s on Xcode (none). About 20 s is the TUIkit job itself (−23%).
- **Noise.** One configuration (6.4.0, native) varied by ±7 s in the TUIkit job between sessions (85.6 s vs 78.5 s). Compare toolchains only within one paired run, and only by outer wall time.
- **Critical path.** Core → View → TUIkit. Styling → Image ends within 0.1 s of Core, but View ends about 7 s after Image, so a shorter Core job does shorten the build.
- **Type checking is spread thin.** There are 67k expressions, and half of the time goes to expressions that take under 1 ms. No expression is pathological. The "29,386" in the stats is the *ordinal* of the largest constraint system, not its attempt count. That system is `IndeterminateRenderer.swift:355` and takes 74 ms; one closure annotation brings it to about 1 ms.
- **SIL optimisation.** TUIkit's own non-generic code takes 53% of the pass time, and stdlib specialisations take 20%. That is 0.23 ms per source line overall, or 0.14 ms per line for TUIkit's own non-generic code.

## Compile-time levers

Savings are seconds off the critical path of a clean release build on Xcode 26's toolchain, which is about 86 s to the end of the TUIkit job. Levers that were measured on swiftly are scaled by 0.77, the paired TUIkit-job ratio (68.1 / 88.2).

| # | Lever | Saving | Stripped bytes | Runtime risk | Effort | Who gets it |
|---|---|---|---|---|---|---|
| 1 | Build with a non-assertions toolchain (Xcode's) | **−30 s** (paired) | 0 | none: same IR | config / docs | anyone, including the project's own gate and lanes |
| 2 | Split TUIkit: a base, then 4 parallel modules, then a thin top | **≤ −21 s**, before `@inlinable` repairs | +0.2 MB unless internalized (at most +1.64 MB) | 737 generic call sites cross a module boundary | large | everyone |
| 3 | `-Osize` | ≈ −12 s (−15.6 s on swiftly) | −1.02 MB | unmeasured (M2) | trivial | `swift build` users only |
| 4 | `-debug-info-format none` | ≈ −2.7 s in-job, plus dsymutil (unmeasured) | 0 | none, but crash reports lose symbols | docs | `swift build` users only |
| 5 | Static tables become static data | ≈ −1.3 s | 0 | neutral (cold lookups) | small | everyone |
| 6 | `@_optimize(none)` on cold code | ≈ −0.9 s | small | none, if the code is truly cold | small | everyone |
| 7 | Type-check rewrites, tier A | ≈ −0.65 s | 0 | none: assembly identical | patch exists | everyone |
| 8 | Collections guideline | ≈ −0.2 s now | small | neutral | guideline | everyone |
| 9 | Foundation out of the lower modules | ≤ −1.5 s on Xcode (about −7 s only on swift.org macOS toolchains) | 0 | none | medium | everyone |

Rows 5–8, the runtime-neutral package-side changes, total **about −3 s**.

**1. Toolchain.**
- Document that macOS users should build with Xcode's toolchain: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release`. The swift.org/swiftly 6.2.4 toolchain pays for both its assertions and the SDK interface rebuild.
- Move the project's per-commit gate and its lanes off swiftly 6.2.4; every build here currently pays 23–26%. Debug builds were not measured, but in the release run their dominant phases fell: Sema −21%, SILGen −53%, IRGen −34%.
- If compiler-assertion coverage matters, keep one assertions lane in CI.
- Linux users are a plausible source of the "many minutes" reports. CI prints `swift --version` (`ci.yml:481`); check the `Build config` line of the `swift:6.x-noble` images (M6).

**2. Split (scenario C, `split/proposal_modules.txt`).** The module layout is a base holding about 42% of TUIkit's code, then four parallel modules of 10–16% each, then a top of 4%.
- *The calibration is an upper bound.* Both trial arms were built with `-enable-testing`, which hid the cost of exposing internals. Measured on Hello, `-enable-testing` adds 12.1 s to the TUIkit job and 1,637,024 B (+14.7%) to the stripped binary.
- *Visibility cost.* Scenario C must widen 3,591 declarations to `package`, about 11% of TUIkit's internal definitions. `package` symbols are `[no dead strip]`, just as `public` ones are. Only `-internalize-at-link` clears that, and Xcode consumers can't use it.
- *Runtime cost.* 113 generic callables, used at 737 sites, cross the boundary; `View.environment` alone accounts for 160 of those sites. Across modules they would be called unspecialised. Unspecialised cross-module generics cost up to 16.6% of a frame before EnvironmentValues' getter was made `@inlinable`. Each `@inlinable` repair re-specialises the code in every module that imports it, which takes back some of the saving.
- *Unmeasured.* Peak RSS with 3–4 modules compiling in parallel (the monolith peaks at 4.1 GB).
- *Windows.* POSIX-only code must stay in the umbrella module.

**3. `-Osize`.** From the size lane's stats, the TUIkit job ends at 124.8 s at `-O` and at 109.1 s with `-Osize`. Core goes from 21.6 to 19.6 s, View from 7.3 to 6.0 s, and the TUIkit job from 95.4 to 83.0 s. Only `swift build` users can apply it; Xcode consumers can't.

**4. Debug info.** These are in-job figures from the same session, R2 vs R1: the TUIkit job ends 3.4 s earlier, IRGen goes from 5.1 to 2.4 s, and LLVM from 7.1 to 6.4 s. The earlier wall-time comparison mixed in a different driver setting. SwiftPM also runs `dsymutil` on release executables (`size/b1.log`), and turning debug info off should remove that step; it has not been timed.

**5. Static tables.** On swiftly, SIL spends 1.20 s initialising six TUIkit tables: `codepointOffsets` 428 ms and `nameStarts` 427 ms (`SFSymbolTable.generated.swift:9172`, `:8498`), `cssNamedRaw` 151 and `crayonsRaw` 56 (`SwatchPalettes.swift:89`, `:145`), `namedReferences` 98 (`InlineMarkdownParser+References.swift:100`), and `systemColors` 42 (`AssetCatalog.swift:267`). It spends another 0.48 s on `TerminalWidthCorpus.all` and `categoryNotes` in **TUIkitCore**, which is on the critical path. Only the tests and the `TerminalClientQuirks` app use that table, so move it into its own target. Together that is 1.68 s × 0.77 ≈ 1.3 s, and type checking and IRGen add a little more. The optimiser already folds these tables into static data in the binary, so this lever saves compile time only.

**6. `@_optimize(none)`.** The candidates are the terminal-probing code (0.81 s of SIL on swiftly), `ShortcutTable` (0.36 s), and `description` getters (0.11 s). After pass-timer overhead and the mandatory passes, that is about −0.9 s. Three limits apply:
- One-time initialisers are already covered by row 5.
- The attribute can't be attached to a `static let` initialiser, and synthesised `Codable` code can't take it either.
- Palette derivation would add about 0.9 s, but only if it is proven cold.

**7. Type checking.** `typecheck/rewrites.patch` makes 31 mechanical rewrites in 22 files. It removes 1.07 s of type checking, of which 0.85 s is on the critical path (TUIkit 0.71 s, Core 0.14 s, measured on swiftly). For the three lower modules, assembly at `-O` is identical. Land it without the Gauge hunk. Tier B, every remaining expression over 10 ms, adds about 0.4 s more. The rest is a floor set by the size of the operator overload sets: 98 `==` overloads with the stdlib alone, and 395 in a file that imports Foundation. Only a module split moves that floor.

**8. Collections.** Each distinct `Dictionary` type costs about 19 ms of SIL (2.5 s over 134 types). The three named stable-sort sites (`Styling/Theme.swift:260`, `ZStack.swift:91`, `_SliderCore+Ticks.swift:80`) cost about 50 ms each. Adopt this as a guideline for new code rather than as a sweep.

**Not recommended**
- *Swift 6.4 from swift.org.* Against Xcode's 6.2.4 it is +15 s to the end of the TUIkit job. The earlier "−29 s" compared Swift Build's self-reported time, which leaves out about 15 s, with an assertions toolchain. The package couldn't require 6.4 anyway. Xcode 27's toolchain vs Xcode 26's is unmeasured (M5).
- *`-emit-module-separately-wmo`.* The TUIkit job ends 4.8 s later (R2b vs R2).
- *Machine outliner.* It saves 0.35 MB, but one run took 20–28 s longer.
- *Dropping Foundation from TUIkit.* 149 of the 161 files that import Foundation need it.

## Binary-size levers

Baseline: stripped Hello is 11,150,408 B. `__text` is 8.15 MB of the 9.45 MB `__TEXT` segment: TUIkit 6.55 MB, Core 0.51, View 0.50, Styling 0.31, Image 0.17. By kind: `specialized` symbols 2.05 MB (4,448), value witnesses about 0.78 MB, closures about 0.69 MB, protocol witness thunks about 0.41 MB (10,641).

| Lever | Stripped Hello (B) | Change | Compile time | Runtime | Who gets it |
|---|---|---|---|---|---|
| baseline | 11,150,408 | | | | |
| `-Xswiftc -Xfrontend -Xswiftc -internalize-at-link` | 9,506,648 | −1,643,760 (−14.7%) | no saving | none expected (linkage only) | `swift build` users |
| `-Osize` | 10,131,400 | −1,019,008 (−9.1%) | ≈ −12 s | unmeasured (M2) | `swift build` users |
| SF symbol names front-coded, block size ≥ 32 | | ≈ −150 KB | slightly less | a lookup decodes one block | everyone |
| Result builders `@_alwaysEmitIntoClient` | | ≈ −108 KB | apps compile what they use | neutral or better | apps that don't internalize, including every Xcode consumer |
| Fewer witness thunks for the boolean View-trait requirements (358 conformances) | | ≈ −33 KB | | neutral | everyone, including apps that internalize |
| Optional: public `View.*` modifier wrappers `@_alwaysEmitIntoClient` (547 symbols) | | ≤ −0.1 MB | apps compile what they use | neutral or better | apps that don't internalize |

- **SF front-coding.** The name blob is 200,347 B and the `nameStarts` index 33,868 B. Front-coded in blocks of 8/16/32/64 they save 135.5/144.9/149.8/152.0 KB. This reverses the generator's stated "no String, no runtime parsing" design (`SFSymbolTable.generated.swift:12`). That is harmless, but it is a design change (D3).
- **Overlap with internalize runs one way.** Internalize already drops the builder blocks (`TableColumnBuilder+Blocks` 37,448 → 0 B, `TableRowBuilder+Blocks` 21,912 → 0 B), so the builder row helps only apps that don't internalize. The View-trait thunks are reached through witness tables, which conformance records keep alive, so internalize keeps them and that row helps every app.
- **Why so little is stripped.** A reachability model (`size/reach/modes.txt`, a model and not a build) puts the live atoms at 9.08 MB with internalize alone. If conformance records were also conditional, it falls to 3.66 MB. No build of that configuration was tried.

## CI guard against type-check regressions

Pass these flags on the command line only, never in `Package.swift`. Run them on one pinned non-assertions 6.2.4 toolchain, because solver scope counts change between compiler versions.
- Gate: `-Xswiftc -Xfrontend -Xswiftc -solver-scope-threshold=3000`. It is deterministic. It fails today on 17 sites (`typecheck/scope-sites-3000.txt`), so land tier B first or start with a higher threshold.
- Report only, not a gate: `-Xswiftc -Xfrontend -Xswiftc -warn-long-expression-type-checking -Xswiftc -Xfrontend -Xswiftc 30`. This flag takes a separate argument (`fe-help-hidden.txt:1204`). It is timing-based, so it is noisy.

## Measurements owed (coordinator, quiet box)

- **M1.** Re-run the baseline and every lever's A/B with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Don't use `xcrun swift` here: `xcode-select -p` points at CommandLineTools, whose Swift 6.1.2 can't read a 6.2 manifest, and changing `xcode-select` is a system setting.
- **M2.** Runtime A/B of `-Osize`, and of internalize (expected to be neutral).
- **M3.** Re-run the split calibration without `-enable-testing`, using real `package` access on one module. Record stripped bytes and peak RSS.
- **M4.** Time `dsymutil` on a release executable.
- **M5.** Xcode 27's toolchain against Xcode 26's.
- **M6.** The `Build config` line of the `swift:6.x-noble` CI images.
- **Unmeasured hypothesis.** An Xcode Release build of a universal app compiles TUIkit once per architecture.

## Decisions for the owner

- **D1. Split TUIkit.** At most −21 s on Xcode's toolchain, minus whatever the `@inlinable` repairs take back. +0.2 MB unless internalized. Peak RSS is unknown. Decide after M3.
- **D2. `@_optimize(none)` on cold code.** About −1 s. It needs a guarantee that the code stays off hot paths.
- **D3. SF front-coding.** −150 KB. It reverses the generator's "no runtime parsing" design.
- **D4. Document `-Osize` and internalize for `swift build` users.** After M2. Neither can be a package default without `unsafeFlags`.
- **D5. Toolchain policy.** Move the gate and lanes to a non-assertions toolchain, and decide whether to keep one assertions lane.

**Do now (no decision needed):** the toolchain docs; the type-check rewrites (tier A, then tier B); static tables, with `TerminalWidthCorpus` moved out of TUIkitCore; the collections guideline. All of these build with Swift 6.2 and leave the four lower modules' Windows build alone. Commits motivated by these measurements must quote the numbers, per CLAUDE.md.

## Evidence

All under `TUIkit-session-notes/buildtime/`:
- `challenge/`: `tc3.sh`, `tc3.log`, `st-{xc,sw,s64}` (paired toolchains); `vis.sh`, `vis.log`, `st-vis-*` (cost of `-enable-testing`).
- `outside/`: `rel-R*.log`, `st-R*`, `imports/results*.txt`.
- `typecheck/`: `analysis.md`, `rewrites.patch`, `scope-sites-*.txt`.
- `silopt/`: `tk_pt.report.txt`, `core_pt.report.txt`, `*.bydecl.pkl`, `fe-help-hidden.txt`.
- `size/`: `variants*.log`, `reach/modes.txt`.
- `split/`: `proposal_modules.txt`, `trial-*.patch`, `boundary.py`, `generic_xb.py`.
- `stats/` and `textsyms.pkl` (baseline).

## Coordinator addenda (2026-10-07 03:40)
- M1: on Xcode's 6.2.4 a clean release app build is 81-83 s wall (147 s user), debug 18 s (m1m2.log).
- M2: -Osize: Stress stripped -14.3%, runtime ~+10% (+4.5..+20.5%, ab-osize-warm.txt). -internalize-at-link: -12.3%, runtime within ±1% (ab-internal-warm.txt).
- M6: CI's Linux release images (6.2.4, 6.3.3, 6.4; x86_64 and arm64) are not assertions builds; only the main nightly is.
- bt1 (landed e50e10c2a), paired clean release app builds on Xcode's 6.2.4, A=fe245ada2 / B=e50e10c2a alternating: A 91.2, 81.1 s; B 87.2, 79.2 s (user 155.7/146.7 vs 150.7/144.6 s) -> about -2..-4 s, as estimated. Runtime: full sweep warm and cold within ±1% (perf/results/bt1/).
