# Compile time and the test targets

*Where a build's time goes, the toolchain choice, type-check time on Swift 6.4,
pre-specialisation and optimisation attributes, and splitting the tests by
module and then by area. The analysis of 2026-10-07 and the investigations and
lanes that followed it.*

## In short

The project's own builds use Xcode's Swift 6.2.4 rather than swiftly's
assertions build (−26% to −42%); inside a build SIL optimisation dominates.
Type-check time is guarded by a gate. The tests were split by module (TS),
then by area (TT2: four bundles), cutting the edit-to-test loop; the owner
kept the small test targets separate (A-TS-1, 2026-10-23).

## The analysis: clean release build time and binary size (2026-10-07)

> **What this is.** The analysis behind the 2026-10 compile-time and binary-size work: where a clean release build
> of an app using TUI spends its time and where the shipped bytes go, with the levers ranked and priced. Written by
> five analyst agents, a synthesis and a skeptic's check (2026-10-07), with the coordinator's later measurements
> appended at the end. It led to two decisions: the project's own builds use Xcode's Swift 6.2.4 rather than
> swiftly's assertions build (−26% to −42%), and TUI is split into modules (see
> `Module split plan, revision 4 (2026-10-07).md`, beside this file).
>
> **Paths.** Evidence is cited by paths relative to the maintainers' working notes (`buildtime/…`, `split/…`,
> `challenge/…`); those files are not in this repository.

TUI at 14d09c6a0, 2026-10-07. Measured on a shared 12-core arm64 VM, so wall times are noisy: rank within one run and prefer counters. Revised after the skeptic's review: figures are re-based to Xcode's toolchain, and the claims the review refuted are removed.

### Summary

1. **Most of the gap is the toolchain.** The baseline compiler, swiftly's swift.org 6.2.4, is an assertions build: `swift --version` prints `Build config: +assertions`. On macOS it also rebuilds 19 SDK module interfaces that Xcode ships prebuilt. In a paired run, Xcode 26's own 6.2.4 reached the end of the TUI job in **86.4 s instead of 116.7 s (−30.2 s, −26%)**. It generated the same IR (1,413,093 vs 1,413,591 instructions; 36,317 SILGen functions in both). Every saving below is re-based to Xcode's toolchain unless it says otherwise.
2. **Inside the build, SIL optimisation dominates.** On Xcode's toolchain the TUI job takes 68.1 s: SIL optimisation 39.6 s (58%), type checking 10.5, LLVM 5.4, IRGen 3.2, SILGen 2.3. The chain Core → View → TUI runs serially, so the build gets only about 1.7× parallelism.
3. **Only one package-side lever is large: splitting the TUI module.** It saves at most about 21 s before the `@inlinable` repairs that runtime needs, and it costs bytes. The runtime-neutral package-side changes together save **about 3 s** (about 3.5%).
4. **Dead stripping keeps nearly all of TUI.** Hello and Typical differ by only 16,560 B. Public symbols are marked `[no dead strip]`, and conformance records root the witness tables. The two large byte levers are flags that an app developer passes to `swift build`: `-internalize-at-link` (−1.64 MB, −14.7%) and `-Osize` (−1.02 MB, −9.1%; its runtime cost is unmeasured). Neither is available to Xcode consumers. Package-side source changes save about 0.3 MB.
5. **A package used as a dependency can't use `unsafeFlags`, so only source changes reach every consumer.** Compiler flags work only when the app developer passes them on the `swift build` command line. Xcode builds packages with its own per-configuration settings.

### Where the time goes

Paired clean `swift build -c release -j 8 --target TUI`: same commit, same SDK, fresh scratch path each time, all in one slot window (`challenge/tc3.sh`, `tc3.log`). Times are seconds from the first frontend job.

| Toolchain | Core ends | TUI job | TUI ends | Sema | SILGen | SIL opt | IRGen | LLVM | Outer wall |
|---|---|---|---|---|---|---|---|---|---|
| Xcode 26 6.2.4 | 12.2 | 68.1 | **86.4** | 10.5 | 2.3 | 39.6 | 3.2 | 5.4 | 97.4 |
| swiftly 6.2.4, +assertions (the baseline's) | 21.3 | 88.2 | 116.7 | 13.3 | 4.9 | 48.6 | 4.8 | 6.5 | 123.6 |
| swift.org 6.4.0, native build system | 16.7 | 78.5 | 101.4 | 11.7 | 3.1 | 46.9 | 3.4 | 5.2 | 111.7 |

- **Where the −30 s comes from.** About 9 s is Core's imports: a cold import of Core's import set takes 9.19 s on swiftly (19 interface rebuilds) and 1.22 s on Xcode (none). About 20 s is the TUI job itself (−23%).
- **Noise.** One configuration (6.4.0, native) varied by ±7 s in the TUI job between sessions (85.6 s vs 78.5 s). Compare toolchains only within one paired run, and only by outer wall time.
- **Critical path.** Core → View → TUI. Styling → Image ends within 0.1 s of Core, but View ends about 7 s after Image, so a shorter Core job does shorten the build.
- **Type checking is spread thin.** There are 67k expressions, and half of the time goes to expressions that take under 1 ms. No expression is pathological. The "29,386" in the stats is the *ordinal* of the largest constraint system, not its attempt count. That system is `IndeterminateRenderer.swift:355` and takes 74 ms; one closure annotation brings it to about 1 ms.
- **SIL optimisation.** TUI's own non-generic code takes 53% of the pass time, and stdlib specialisations take 20%. That is 0.23 ms per source line overall, or 0.14 ms per line for TUI's own non-generic code.

### Compile-time levers

Savings are seconds off the critical path of a clean release build on Xcode 26's toolchain, which is about 86 s to the end of the TUI job. Levers that were measured on swiftly are scaled by 0.77, the paired TUI-job ratio (68.1 / 88.2).

| # | Lever | Saving | Stripped bytes | Runtime risk | Effort | Who gets it |
|---|---|---|---|---|---|---|
| 1 | Build with a non-assertions toolchain (Xcode's) | **−30 s** (paired) | 0 | none: same IR | config / docs | anyone, including the project's own gate and lanes |
| 2 | Split TUI: a base, then 4 parallel modules, then a thin top | **≤ −21 s**, before `@inlinable` repairs | +0.2 MB unless internalized (at most +1.64 MB) | 737 generic call sites cross a module boundary | large | everyone |
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

**2. Split (scenario C, `split/proposal_modules.txt`).** The module layout is a base holding about 42% of TUI's code, then four parallel modules of 10–16% each, then a top of 4%.
- *The calibration is an upper bound.* Both trial arms were built with `-enable-testing`, which hid the cost of exposing internals. Measured on Hello, `-enable-testing` adds 12.1 s to the TUI job and 1,637,024 B (+14.7%) to the stripped binary.
- *Visibility cost.* Scenario C must widen 3,591 declarations to `package`, about 11% of TUI's internal definitions. `package` symbols are `[no dead strip]`, just as `public` ones are. Only `-internalize-at-link` clears that, and Xcode consumers can't use it.
- *Runtime cost.* 113 generic callables, used at 737 sites, cross the boundary; `View.environment` alone accounts for 160 of those sites. Across modules they would be called unspecialised. Unspecialised cross-module generics cost up to 16.6% of a frame before EnvironmentValues' getter was made `@inlinable`. (Added 2026-10-08: that share is `Tools/Profiling/analyze_timeprofile.py`'s, from before that day, when it counted each distinct stack once. Treat it as indicative; `Tools/Profiling/README.md` has the details.) Each `@inlinable` repair re-specialises the code in every module that imports it, which takes back some of the saving.
- *Unmeasured.* Peak RSS with 3–4 modules compiling in parallel (the monolith peaks at 4.1 GB).
- *Windows.* POSIX-only code must stay in the umbrella module.

**3. `-Osize`.** From the size lane's stats, the TUI job ends at 124.8 s at `-O` and at 109.1 s with `-Osize`. Core goes from 21.6 to 19.6 s, View from 7.3 to 6.0 s, and the TUI job from 95.4 to 83.0 s. Only `swift build` users can apply it; Xcode consumers can't.

**4. Debug info.** These are in-job figures from the same session, R2 vs R1: the TUI job ends 3.4 s earlier, IRGen goes from 5.1 to 2.4 s, and LLVM from 7.1 to 6.4 s. The earlier wall-time comparison mixed in a different driver setting. SwiftPM also runs `dsymutil` on release executables (`size/b1.log`), and turning debug info off should remove that step; it has not been timed.

**5. Static tables.** On swiftly, SIL spends 1.20 s initialising six TUI tables: `codepointOffsets` 428 ms and `nameStarts` 427 ms (`SFSymbolTable.generated.swift:9172`, `:8498`), `cssNamedRaw` 151 and `crayonsRaw` 56 (`SwatchPalettes.swift:89`, `:145`), `namedReferences` 98 (`InlineMarkdownParser+References.swift:100`), and `systemColors` 42 (`AssetCatalog.swift:267`). It spends another 0.48 s on `TerminalWidthCorpus.all` and `categoryNotes` in **TUICore**, which is on the critical path. Only the tests and the `TerminalClientQuirks` app use that table, so move it into its own target. Together that is 1.68 s × 0.77 ≈ 1.3 s, and type checking and IRGen add a little more. The optimiser already folds these tables into static data in the binary, so this lever saves compile time only.

**6. `@_optimize(none)`.** The candidates are the terminal-probing code (0.81 s of SIL on swiftly), `ShortcutTable` (0.36 s), and `description` getters (0.11 s). After pass-timer overhead and the mandatory passes, that is about −0.9 s. Three limits apply:
- One-time initialisers are already covered by row 5.
- The attribute can't be attached to a `static let` initialiser, and synthesised `Codable` code can't take it either.
- Palette derivation would add about 0.9 s, but only if it is proven cold.

**7. Type checking.** `typecheck/rewrites.patch` makes 31 mechanical rewrites in 22 files. It removes 1.07 s of type checking, of which 0.85 s is on the critical path (TUI 0.71 s, Core 0.14 s, measured on swiftly). For the three lower modules, assembly at `-O` is identical. Land it without the Gauge hunk. Tier B, every remaining expression over 10 ms, adds about 0.4 s more. The rest is a floor set by the size of the operator overload sets: 98 `==` overloads with the stdlib alone, and 395 in a file that imports Foundation. Only a module split moves that floor.

**8. Collections.** Each distinct `Dictionary` type costs about 19 ms of SIL (2.5 s over 134 types). The three named stable-sort sites (`Styling/Theme.swift:260`, `ZStack.swift:91`, `_SliderCore+Ticks.swift:80`) cost about 50 ms each. Adopt this as a guideline for new code rather than as a sweep.

**Not recommended**
- *Swift 6.4 from swift.org.* Against Xcode's 6.2.4 it is +15 s to the end of the TUI job. The earlier "−29 s" compared Swift Build's self-reported time, which leaves out about 15 s, with an assertions toolchain. The package couldn't require 6.4 anyway. Xcode 27's toolchain vs Xcode 26's is unmeasured (M5).
- *`-emit-module-separately-wmo`.* The TUI job ends 4.8 s later (R2b vs R2).
- *Machine outliner.* It saves 0.35 MB, but one run took 20–28 s longer.
- *Dropping Foundation from TUI.* 149 of the 161 files that import Foundation need it.

### Binary-size levers

Baseline: stripped Hello is 11,150,408 B. `__text` is 8.15 MB of the 9.45 MB `__TEXT` segment: TUI 6.55 MB, Core 0.51, View 0.50, Styling 0.31, Image 0.17. By kind: `specialized` symbols 2.05 MB (4,448), value witnesses about 0.78 MB, closures about 0.69 MB, protocol witness thunks about 0.41 MB (10,641).

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

### CI guard against type-check regressions

Pass these flags on the command line only, never in `Package.swift`. Run them on one pinned non-assertions 6.2.4 toolchain, because solver scope counts change between compiler versions.
- Gate: `-Xswiftc -Xfrontend -Xswiftc -solver-scope-threshold=3000`. It is deterministic. It fails today on 17 sites (`typecheck/scope-sites-3000.txt`), so land tier B first or start with a higher threshold.
- Report only, not a gate: `-Xswiftc -Xfrontend -Xswiftc -warn-long-expression-type-checking -Xswiftc -Xfrontend -Xswiftc 30`. This flag takes a separate argument (`fe-help-hidden.txt:1204`). It is timing-based, so it is noisy.

### Measurements owed (coordinator, quiet box)

- **M1.** Re-run the baseline and every lever's A/B with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Don't use `xcrun swift` here: `xcode-select -p` points at CommandLineTools, whose Swift 6.1.2 can't read a 6.2 manifest, and changing `xcode-select` is a system setting.
- **M2.** Runtime A/B of `-Osize`, and of internalize (expected to be neutral).
- **M3.** Re-run the split calibration without `-enable-testing`, using real `package` access on one module. Record stripped bytes and peak RSS.
- **M4.** Time `dsymutil` on a release executable.
- **M5.** Xcode 27's toolchain against Xcode 26's.
- **M6.** The `Build config` line of the `swift:6.x-noble` CI images.
- **Unmeasured hypothesis.** An Xcode Release build of a universal app compiles TUI once per architecture.

### Decisions for the owner

- **D1. Split TUI.** At most −21 s on Xcode's toolchain, minus whatever the `@inlinable` repairs take back. +0.2 MB unless internalized. Peak RSS is unknown. Decide after M3.
- **D2. `@_optimize(none)` on cold code.** About −1 s. It needs a guarantee that the code stays off hot paths.
- **D3. SF front-coding.** −150 KB. It reverses the generator's "no runtime parsing" design.
- **D4. Document `-Osize` and internalize for `swift build` users.** After M2. Neither can be a package default without `unsafeFlags`.
- **D5. Toolchain policy.** Move the gate and lanes to a non-assertions toolchain, and decide whether to keep one assertions lane.

**Do now (no decision needed):** the toolchain docs; the type-check rewrites (tier A, then tier B); static tables, with `TerminalWidthCorpus` moved out of TUICore; the collections guideline. All of these build with Swift 6.2 and leave the four lower modules' Windows build alone. Commits motivated by these measurements must quote the numbers, per CLAUDE.md.

### Evidence

All under `TUI-session-notes/buildtime/`:
- `challenge/`: `tc3.sh`, `tc3.log`, `st-{xc,sw,s64}` (paired toolchains); `vis.sh`, `vis.log`, `st-vis-*` (cost of `-enable-testing`).
- `outside/`: `rel-R*.log`, `st-R*`, `imports/results*.txt`.
- `typecheck/`: `analysis.md`, `rewrites.patch`, `scope-sites-*.txt`.
- `silopt/`: `tk_pt.report.txt`, `core_pt.report.txt`, `*.bydecl.pkl`, `fe-help-hidden.txt`.
- `size/`: `variants*.log`, `reach/modes.txt`.
- `split/`: `proposal_modules.txt`, `trial-*.patch`, `boundary.py`, `generic_xb.py`.
- `stats/` and `textsyms.pkl` (baseline).

### Coordinator addenda (2026-10-07 03:40)
- M1: on Xcode's 6.2.4 a clean release app build is 81-83 s wall (147 s user), debug 18 s (m1m2.log).
- M2: -Osize: Stress stripped -14.3%, runtime ~+10% (+4.5..+20.5%, ab-osize-warm.txt). -internalize-at-link: -12.3%, runtime within ±1% (ab-internal-warm.txt).
- M6: CI's Linux release images (6.2.4, 6.3.3, 6.4; x86_64 and arm64) are not assertions builds; only the main nightly is.
- bt1 (landed e50e10c2a), paired clean release app builds on Xcode's 6.2.4, A=fe245ada2 / B=e50e10c2a alternating: A 91.2, 81.1 s; B 87.2, 79.2 s (user 155.7/146.7 vs 150.7/144.6 s) -> about -2..-4 s, as estimated. Runtime: full sweep warm and cold within ±1% (perf/results/bt1/).

## Type-check time on Swift 6.4, test expectations and exit tests (2026-10-08)

> **Status:** decided; the test rewrites landed 2026-10-08, and the test-target split that followed on 2026-10-10.
> Two items stay open elsewhere: exit tests' bodies (decisions A-TC1-1, the owner's) and the `#expect` scaling
> report, drafted for the owner to file. **Decided by:** the owner set the target and the rule (6.4 first, no
> regression on 6.2 or 6.3); lanes TC1 and TC2 chose the rewrites by it. **Working notes** (not in git): `TC1/`
> (the 6.2.4 profile), `TC2/` (6.4 against 6.2.4: `profile.md`, `baseline.md`), `EXITTC/` (`research.md`, and
> `expect-scaling/` with the report and its reproducer), `buildtime/typecheck/`.

### Question

The owner asked on 2026-10-07 for TUI's clean release compile time to come down, starting with the simple fixes
a type-check profile finds (lane TC1, on Xcode's 6.2.4). On 2026-10-08 he moved the target: "our main focus for
improving the compile time … should be the 6.4 compiler. We still need 6.3 and 6.2 to work … We know that 6.4 is in
some ways slower than 6.2, so it might be worth rerunning an evaluation there." He also asked whether the exit-test
double type-check is reported, fixed, avoidable by a flag, and still in 6.4.

### Answer

- **6.4 type-checks TUI faster than 6.2.4, not slower:** function bodies in the nine carved library modules −13%,
  in TUIFoundation −17%, in the test targets −2%. One test target was slower (TUIViewTests, +15%), and
  TUITests' whole-module type check peaked at 5.6 GB of memory on 6.4 against 3.3 GB (+72%).
- **What is slower on 6.4 is specific:** the first use of an overload set in each frontend (5–14 ms against 2–6 ms,
  paid once per batch job); a leading-dot operand of `==` inside `#expect` (`== .rgb(…)`: +67% on the 159 lines that
  had one), since it is inferred through every `==` in scope; and a per-`#expect` floor about 10% higher.
- **The library had nothing left to fix on 6.4;** every candidate rewrite saved under 5 ms and was reverted. In the
  test targets, four rewrites saved 1.65 s on 6.4, 1.03 s on 6.3.3 and 1.02 s on 6.2.4, slower on no compiler.
- **The cost of an `#expect` grows with how many a module holds:** linear up to about 8,000, then 2.3 to 2.5 times
  the CPU for twice the expectations. It follows the number of `#expect` expansions, not suites or tests. TUITests
  held about 25,000. That made splitting the test targets worth doing.
- **The exit-test double type-check is by design and has no flag.** SE-0382 type-checks a macro's arguments before
  expansion, and the exit-test macro then copies the body into a function the compiler checks again. Nobody had
  reported it; it is still there in 6.4.0; in TUI it costs about 2 s of a whole-module check (≈0.2%), not the
  7–10 s lane TC1 first estimated.

### Key measurements

Swift 6.4.0 and 6.3.3 (swift.org, no assertions) and Xcode 26.3's 6.2.4, on the development machine (arm64 macOS
15.8.1 VM, shared with other lanes, so absolute times are noisy: rankings, same-session pairs and minimum-of-N runs
were trusted). Base c25452779 (part-way through the module split). Function bodies with
`-debug-time-function-bodies`, expressions with `-debug-time-expression-type-checking`, per file as primary (min of 3
or 5) and per module whole (`-typecheck`).

| | Xcode's 6.2.4 | 6.4.0 |
|---|--:|--:|
| carved library modules, function bodies | 4,538 ms | 3,957 ms |
| TUIFoundation, function bodies | 7,608 ms | 6,323 ms |
| test targets, whole-module | 770 s | 752 s |
| TUITests, peak memory | 3.3 GB | 5.6 GB |
| trivial `#expect`, TUITests | 4.93–6.24 ms | 5.18–6.77 ms |

`#expect` scaling, a generated package (20 trivial `#expect`s per test), 6.4.0, test target rebuild CPU:

| `#expect`s | 1,000 | 2,000 | 4,000 | 8,000 | 16,000 |
|---|--:|--:|--:|--:|--:|
| debug | 5.9 s | 12.3 s | 24.5 s | 50.2 s | 117.8 s |
| release (whole-module) | 7.1 s | 14.0 s | 29.3 s | 68.6–76.9 s | 192.7 s |

With one `#expect` per test, the same suites and tests stay linear (7.2 s and 14.3 s); without `@Suite` the curve
barely changes. 6.2.4 and 6.3.3 show the same shape (8,000 to 16,000: 2.2× and 3.0×, `swiftc -typecheck -wmo`).

### Reasoning

- **Rewrites only where they pay on 6.4 and do not cost on 6.2 or 6.3**, measured per file on all three: the row-fill
  goldens built by appends (`f6ce6fc20`), named values in the worst `#expect`s of nine files (`2aceec998`), colour
  operands that name `Color` (`7e19ae3d2`), and two named verdicts (`1f883cc53`). TC1's 6.2.4 rewrites came first
  (`f0be9f936` and others; decisions TC1).
- **A first-use cost is not a property of its site:** rewriting one moves the cost to the next first use, as a
  warm-up probe showed (sites dropped from 5–14 ms to 0.3–2 ms when another file paid first). So no library code was
  changed for it.
- **The split test targets** (`b377b5f24`, decisions TT2) took a one-file test edit from about 60 to about 18 CPU
  seconds; that, and the rest of the `#expect` floor, are in
  [Future options](<../../Future options.md#the-rest-of-the-test-targets-expect-floor>).
- **Exit tests:** moving each body into a function halves the check, and a local `func inChild()` passed as
  `performing:` is the smallest such rewrite. For about 2 s it would hide what the child process checks, so the
  recommendation is to leave them
  ([A-TC1-1](#a-tc1-1-exit-tests-bodies-could-move-into-helper-functions),
  [Future options](<../../Future options.md#exit-tests-bodies-as-functions>)).

### The modules carved after it (2026-10-19)

The owner asked for a per-module pass once the split had a first solid draft. This record's profile predates
thirteen modules: Chrome, Effects, Menus, Bitmaps, Lists, TextInput, Tables, Tabs, Grid, Forms, Search, Pickers and
NumericControls. They were profiled on swift.org 6.4.0, in a debug build of the library (a fresh scratch path) with
`-warn-long-expression-type-checking=5` and `-warn-long-function-bodies=5`. That reported 152 expressions and 436
function bodies of 5 ms or more in those modules, on a busy machine. Each candidate was then re-measured by touching
its file and rebuilding its module three times, keeping the minimum. The two kinds this record describes account for
the rest:

- **First use.** `_SidebarSectionList.body`'s `List(selection:) { … }`, the worst expression (48 ms of a 66 ms
  body), stayed at 48–49 ms with the section moved to a method of its own, and again with the whole content moved to
  a builder method. A trivial `List(selection:) { EmptyView() }` placed before it took the 48 ms, and the real call
  dropped under 5 ms: the cost belongs to the first use of `List`'s initializers in that frontend, not to the site.
  The next worst (`List+BindingTree.swift:33`, `Table+Children.swift:53`, `Table+Customization.swift:32`,
  `List+RequiredSelection.swift:36`, 25–34 ms) have the same shape: one `self.init` into an overloaded set.
- **Bodies of many cheap expressions.** `TrackRaster.picture` (26 ms, min of 3) has no expression over 6 ms. The
  two `==` bodies on the list (`ProgressView`, 14 ms; the image placeholder's, 11 ms) are guard lists already, the
  form this record's fixes used; what they pay is the first use of `==`.

One site was a real one: `PanelToggleButton.name` trimmed a label as
`String(line.drop { … }.reversed().drop { … }.reversed())`, 11 ms. Found by index, its body went from 16 to 11 ms;
the 5 ms left is the first use of `String.init`. Nothing else qualified, which is this record's finding for the
first nine modules too.

### Side findings

- Swift 6.3.3 could not build TUI in release (`Theme.swift:198`, a false data-race error): its `-O` pipeline
  clones a nested function without its main-actor isolation. Fixed in `fed3b535e`, whose message holds the
  reduction; CI has built release on 6.3 and 6.4 since `87139596a`.
- The release build's whole Sema phase is longer on 6.4 (TUIFoundation's job 9.1 s against 6.7 s), outside
  function bodies; where is unmeasured.

Related: the [compile time and binary size analysis](<Compile time and the test targets.md>)
(on 6.2) and decisions
[TC1](<Compile time and the test targets.md>) and
[TT2](<Compile time and the test targets.md>).

## Pre-specialisation across module boundaries (2026-10-08)

> **Status:** decided 2026-10-08: adopt neither attribute; `@inlinable` (the split plan's tier 2) stays the remedy
> for a hot generic call that crosses a module boundary. Two small non-generic rewrites it suggested landed during
> the split. **Decided:** recommended 2026-10-08 and reported to the owner; the coordinator's ledger records the
> question as decided (no ruling text of the owner's is quoted here). **Working notes** (not in git):
> `PRESPEC/recommendation.md` (with `research.md`, `experiment.md` and the crossing-by-crossing `inventory.md`).

### Question

Once TUI is split into modules, a generic function called from another module runs unspecialised unless the
caller can see its body. Could pre-made specialisations, `@_specialize(exported: true, where …)` or SE-0460's
`@specialized` behind an `#if`, recover the cost instead? The owner, 2026-10-08, asked for an evaluation, and set
its limit: it "only really works if the specializations … are relatively few and predictable".

### Answer

- **SE-0460's `@specialized` does not help other modules.** It first shipped in Swift 6.3, it specialises only
  inside the defining module (a type check at the start of the generic function), and callers in other modules
  still call the generic entry point. On 6.2 it needs `#if compiler(>=6.3)`; `#if hasAttribute(specialized)` is
  false on 6.2.4, 6.3.3 and 6.4.0.
- **`@_specialize(exported:)` does help, narrowly.** It emits a public specialised symbol, and an optimised client
  whose call names exactly that type calls it directly; every other type, every `-Onone` client and every call
  through a witness table gets the generic entry point. It also switches off default cross-module optimisation for
  that function, so a small function that would have been inlined gets an opaque call instead.
- **None of TUI's hot crossings fits.** They are generic over the caller's own views, data and IDs, which
  TUIFoundation cannot name. The few closed sets are better served by an `@inlinable` shim, by making the function
  non-generic, or by nothing.

### Key measurements

A toy library and client, release (whole module, default cross-module optimisation), on Swift 6.2.4, 6.3.3 and 6.4.0,
on the development machine (arm64 macOS 15.8.1 VM); compiler source read at each tag. The crossings come from an
inventory of the split's call sites at main c25452779: 392 callees with 1,846 sites, 95 of them protocol
requirements or stored properties.

| call from the client | what it calls (all three compilers) |
|---|---|
| `f(3)`, with `@_specialize(exported: true, where T == Int)` | the specialised symbol, directly |
| `f("s")`, no `String` specialisation | the generic entry point |
| a library type made generic over a client type | generic |
| a partial specialisation (`T: _Trivial(64)`) called with concrete types | the optimised client's compiler crashes |

Each pre-made body is code every app keeps, used or not, unless TUI is compiled with `-internalize-at-link` (on
macOS release builds by default since 2026-10-11): in the toy, six bodies were about 1,004 B, and the linked
`__text` grew by 868 B.

### Reasoning

A crossing fits an exported specialisation only when it is generic, hot, has a few type arguments TUIFoundation
can name, and has concrete callers. Measured against the inventory:

- **Containers, modifiers, stacks, `Button.init`:** the type arguments are the caller's views; nothing writable.
- **Render-walk entry points:** every view type, and they crossed modules before the split too.
- **The seven `init<S: StringProtocol>` overloads:** `S == String` at every site checked, and the attribute would
  bind on five of them, but an `@inlinable` shim onto a concrete `String` core, as step A3 wrote for `Text`, is
  better: it keeps cross-module optimisation, specialises `Substring` too, and can be written for all seven.
- **`StateStorage.storage<Value>`:** `Value == Bool` for `Button`, `Toggle` and `Picker` would bind; left as a
  candidate to measure first.
- **`TimeSpanSpelling.init` and `TerminalImageStore.placeholderRows`:** generic only in name; made non-generic
  instead.

### What landed

- `ebebe1e42`: `TimeSpanSpelling.init` takes an array of units, which every caller passes.
- `77f690ffa`: a picture's Kitty placement erases its signature in its own module and calls the image store's
  non-generic core (step B5c).
- `_OpacityView.fading`, also generic only in name, was left generic: its one cross-module caller calls it out of
  line, as before the split (decisions
  C-SPB5c-1 in [SPB5c](<The module split.md>)).
- No `@_specialize` or `@specialized` in `Sources` at 5369ea867. The split's own recoveries used `@inlinable`
  ([the module split's run-time cost](<The module split.md>)).

Related: [selective optimisation attributes](<Compile time and the test targets.md>), and the split
plan, which held `@_specialize(exported:)` in reserve:
[Module split plan, revision 4](<The module split.md>).

## Selective optimisation attributes (2026-10-08)

> **Status:** decided 2026-10-08. One change landed, the status bar's undo-hint cache (`d909004f3`, `cad89cd17`);
> no optimisation attribute did. **Decided by:** the owner. **Working notes** (not in git): `OPTN/options.md` (the
> options table and the raw numbers beside it), `OPTN/patches/`.

### Question

Could `@_optimize(none)`, `@_optimize(size)`, no-specialisation and similar attributes on cold code cut TUI's
compile time or bytes without costing run time? The owner, 2026-10-08: "I'm open to the concept. I think the bar has
to be higher for merely reducing compilation time because ultimately compilation is a relatively rare thing compared
to the accumulated runtime cost … I'm a little more inclined to accept a trade-off there if it reduces the binary
size … start with you presenting some options you've evaluated, and I'll try and make a judgment."

### Answer

- **`@_optimize(none)` grows the binary** wherever it was tried on non-generic code, by 1.6 to 30 KB per set: an
  unoptimised body is bigger and loses its inlining. It also costs microseconds to milliseconds on its path.
- **Per-function `-Osize` saves little:** closures inside an annotated function are separate functions and do not
  inherit the attribute, and a size-mode function changes what its callers inline. The sets saved 3–5 times less
  than the module-wide `-Osize` measurement had suggested.
- **The one clear win was not an attribute:** caching the status bar's undo and redo hints, which were rebuilt from
  the shortcut table up to four times a render (6.9 µs to 0.05 µs per bar render).
- **All the sets together** would have saved 44 KB of a stripped Stress (51 KB of `__text`) and about 1.4 s of
  compile CPU, for 597 annotated declarations to keep cold.

### Key measurements

Main 695d4c2cd, Xcode's Swift 6.2.4, on the development machine (an arm64 VM with no performance counters, shared
with other lanes): run time is thread-CPU time, the minimum over batches and the median of three rotated runs, so
factors within ±3–5% are noise. Bytes are stripped release binaries (moving in 16 KB pages; `__text` resolves the
rest). Compile time is SIL-optimisation CPU per set, from per-function pass timers.

| set (what is annotated) | run-time cost | bytes saved, Stress (`__text`) | compile CPU saved |
|---|---|--:|--:|
| S1a: no specialisation on `renderMenuPopup` | none measurable | 16.6 KB (18.7) | 0.16 s |
| S1b: S1a, the hint cache, and the shortcut tables unoptimised | faster overall; ×2.2 on a table rebuild | 30.8 KB (42.1) | 0.45 s |
| S2b, S3b, S5b, S6b, S7b, S8a: `none` on cold sets | none measurable (S2b) to ×14 on their paths | grows by 18–55 KB | 0.13–0.77 s |
| S4: one shared unspecialised sort | the ASCII image converter ×2.7 | 16.5 KB | 0.11 s |
| ALL (S1b, S2a, S3a, S4c, S5a, S6a, S7a, S8a) | sessions ×0.98–1.02 | 44.0 KB (50.9) | 1.6 s whole-job |

The ALL build passed the full suite (10,908 tests) with no warnings, and its stripped binaries matched the per-set
relinks to the byte for Hello and Stress.

### Reasoning

The owner ranks run time above bytes above compile time. Against that: every `none` variant failed on bytes; the
`-Osize` sets saved a few kilobytes each for a maintenance cost of keeping hundreds of declarations cold; the shared
sort moved large structs through value witnesses and ran 40 times slower, so it was dropped on measurement; S1b
slowed table rebuilds. S1a alone paid on all three counts, but carving the menus into their own module was expected
to remove the same specialised copies by making those calls cross-module.

### What was decided

The owner, 2026-10-08: "definitely do P0 … Do not do S1B. Because we definitely don't want to slow down tables.
And obviously don't do optimize none, because that clearly just makes everything worse. The other options … S1A and
the small call sets … are on the table … if it makes more sense to wait until the menu module is factored out, then
that's fine too." P0, the hint cache, landed (`d909004f3`, then `cad89cd17` so a kept hint follows a change of
language). S1a and the small sets were not taken up: `Sources` has no `@_optimize` or no-specialisation attribute at
5369ea867. Carving the menus out (step B5b) removed the specialised popup copies S1a was to save, so it has nothing
left to save (decisions
[B-SPB5b-4](<The module split.md#b-spb5b-4-an-open-menus-popup-draws-through-the-unspecialised-rendermenupopup>)).

Related: [pre-specialisation across module boundaries](<Compile time and the test targets.md>),
the same day's other attribute question; and the earlier
[compile time and binary size analysis](<Compile time and the test targets.md>), whose D2
proposed `@_optimize(none)` on cold code.

## Completing the SwiftUI API: decisions from lane TC1

*Lane TC1 is the type-check half of the owner's request of 2026-10-07 to cut
TUI's clean release compile time: profile the build with
`-debug-time-function-bodies` and `-debug-time-expression-type-checking` and
make the simple fixes that ease the compiler's work, in the modules the split
has already carved out and in the test targets, which every lane builds. It
changed no public API and no behaviour. This file holds the judgement calls the
work reached that the request did not already settle, in the format of
[the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>):*

- **A-TC1-n — needs your decision.** Nothing has shipped for these.
- **B-TC1-n — shipped the safe option.** Says what the fuller version would be,
  and its price.
- **C-TC1-n — declined.** With the reason.

All times are Xcode 26.3's Swift 6.2.4 on the shared 16 GiB VM. "WMO" is a
module type-checked whole (`-typecheck`), "primary-file" is the given files
type-checked as primaries with the rest of their target secondary (as a debug
build's batch jobs do), min of 3 runs; both are noisy to about ±10%.

### A. Needs your decision

#### A-TC1-1. Exit tests' bodies could move into helper functions

*38 `#expect(processExitsWith:)` tests in 18 files of TUITests*

Swift Testing 6.2's exit-test macro type-checks the closure's body twice: once
where it is written, as part of the `#expect` expression, and once in the
function the macro generates from a copy of it. Each of these closures holds a
whole test (`await MainActor.run { … }` with several `#expect`s inside), so
each exit test costs 200–700 ms to type-check, the largest single items left in
TUITests after this lane.

Moving a body into a `@MainActor private static func …Body()` and calling it
from the closure (`await MainActor.run { Self.gateOpenReachesTheOpenerBody() }`)
measured, for the two largest in `TerminalURLOpeningTests.swift`
(primary-file): the file's expressions 714.7 → 369.3 ms, about −170 ms per exit
test, plus the generated copy's body (about 100–170 ms each in WMO). Across all
38: roughly −7 to −10 s of type checking in a WMO run, −4 to −6 s of CPU in a
debug build (extrapolated from two, unmeasured as a whole).

**The price** is readability: each exit test's assertions move out of the test
function into a helper beside it, where the `#expect(processExitsWith:)` no
longer shows what the child process checks. The lane's brief said "contorting
a test is not [fine]", so nothing shipped. **Options:** (a) do it for all 38;
(b) only where the body is over ~20 lines; (c) leave them (the default).

**2026-10-12, the owner asked what the price means.** An exit test's trailing
closure is the code the *child process* runs: Swift Testing relaunches the test
binary to run only that closure, and the parent checks how the child exited,
with the child's own `#expect`s forwarded to it. So the closure's body *is*
what the child checks. Moved into a helper, the test reads only

```swift
await #expect(processExitsWith: .success) {
    await MainActor.run { Self.overridePublishesBody() }
}
```

and its setup and expectations are in another function. **What was measured
since** (session notes `EXITTC/research.md` §8.1, on 6.4.0): the exit tests'
in-place type-check totals about 2 s of a ~700 s whole-module type check of the
test target (≈0.2%), so the −7 to −10 s above overstated it at least 3.5
times. That was over 43 exit tests; on 2026-10-19 there are 60, in 28 files across nine test targets. The
recommendation stays **(c), leave them**; if the saving is ever wanted, a
smaller rewrite keeps the body in the test as a local `inChild()` function
passed as `performing:` ([Future options](<../../Future options.md#exit-tests-bodies-as-functions>)).
Still yours to answer.

### B. Shipped the safe option

#### B-TC1-1. TUITests' `#expect` floor: only the outliers were rewritten

*TUITests, about 25,000 `#expect`/`#require` lines*

In TUITests an `#expect` costs 14.8 ms to type-check on average in a WMO run
and 8.2 ms in the debug build's batch jobs; in the per-module test targets
(TUICoreTests, TUIStylingTests, TUIViewTests, TUIImageTests) it is
3–4 ms (5.4 in batch). With 25,000 of them, that floor is most of the target's
374 s (WMO) / 241 s (batch CPU) of expression type checking. The lane rewrote
the outliers only: about a hundred lines of 44 ms to 4.4 s each, by naming an
operand that was an operator chain, a literal, a closure or an implicit member
in a typed `let` before the `#expect` (`#expect` keeps the comparison, so the
failure message still prints both sides).

A probe (40 trivial `#expect(xs.count == N)`, primary-file, median of 3)
priced the floor's parts:

| probe file's imports | in TUITests | in TUICoreTests |
|---|---|---|
| `Testing` only | 5.9 ms per `#expect` | 3.6 ms |
| `Testing`, `TUICore` | 6.3 ms | 3.6 ms |
| `Testing`, `TUI` | 7.0 ms | — |
| `Testing`, `TUI`, `@testable TUIFoundation` | 8.1 ms | — |

So about two thirds of the difference is the module itself, not the file's
imports: a plain `a == b` in TUITests weighs 169 `==` overloads against 105
in TUICoreTests, the 64 extra being TUITests' own hand-written `static
func ==` (66 of them, mostly memo-test views whose partial equality is the
point of the test, so they cannot be synthesized). The rest is the umbrella
import and `@testable`.

**The fuller versions, and their price:**

- **Rewrite every `#expect` over 20 ms** (4,100 lines, 123 s in WMO, 48 s of
  batch CPU): a churn pass over a fifth of the suite for perhaps half of that,
  each line a typed `let` more. Not recommended.
- **Move tests out of TUITests as the split carves modules**, into per-module
  test targets that import only their module: the floor there is half, and
  each target compiles in parallel. This is the structural lever, and it
  belongs to the split's test-target plan rather than to this lane.

**Status, 2026-10-10.** Lane TT2 (b377b5f24) split the umbrella suite into four
test targets **by area**, each under 8,000 `#expect`s, rather than into
module-only targets: all four still import the umbrella and `@testable`
TUITestSupport. Measured by TT2 (CPU, two repeats): a one-file test edit
costs about 18 CPU s instead of about 60, and a rebuild of every test file
100 s (6.2.4) and 228 s (6.4.0) less, at or above what the module-only lever
was estimated to buy; wall time moved only 5 to 12 s. What is left is the import
part of the floor, unmeasured since the split (at most about 72 CPU s a full
rebuild, by estimate); both fuller versions are recorded in
[Future options](<../../Future options.md#the-rest-of-the-test-targets-expect-floor>).

### C. Declined

#### C-TC1-1. MemberImportVisibility on the test targets

It would hide Foundation's operator members from the test files that do not
import Foundation (950 of TUITests' 1,177). Measured on two such files
(primary-file, 547 expressions): 1,009.2 ms without it, 1,016.2 ms with it —
no change, and two files needed `import Foundation` added. Operator lookup is
not what that feature scopes.

#### C-TC1-2. Rewrites that changed the optimised code

The library rewrites were each checked against whole-module `-O` assembly,
function by function. Four first spellings changed it and were respelled or
dropped: `UInt8(truncatingIfNeeded:)` in `StripeKey.colour` made it cheap enough
for the inliner to take into more callers; the same in `RowFills.entry`'s
`near` re-scheduled `rowFills(at:over:)`; `Int(truncatingIfNeeded:)` in
`KittyGraphics.base64`'s tail lost the optimiser's proof that `index + 1`
cannot overflow; and `RowFills.rowFills(at:over:)`'s `packed` (6.8 ms) split at
typed lets re-scheduled its registers. The first two keep their checked
conversions with a named, typed `UInt32` mask instead. The third keeps its
checked `Int` conversions and its mask, already a named, typed constant, and
types its first two sextets as `UInt32` lets instead. The fourth is
unchanged. Two more rewrites saved nothing and were dropped (`App.swift`'s
`frameDumpEnabled`, `changeIsMotionOnly(to:from:)`).

## Test targets split by module: decisions

*The owner asked on 2026-10-12 (B-TC1-1) for the suite to be a test target per
module, so that an edit to a module rebuilds only the tests that can see it, and
on 2026-10-14 for it to be scripted. It landed on 2026-10-14, replacing the
four targets by area of [TT2](<Compile time and the test targets.md>). This file
holds the judgement calls the work made that the request did not settle, in the
format of [the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>):*

- **A-TS-n — needs your decision.**
- **B-TS-n — shipped the safe option.** Says what the fuller version would be,
  and its price.
- **C-TS-n — declined.** With the reason.

### The shape

A test file lives in the target of the highest module it needs, counting what
its helpers need: `TUIFoundationTests` (271 files), `TUIAppTests` (255),
one target per feature module (21, from 2 files to 115), and
`TUIIntegrationTests` (163), the one target that still depends on every
module. Helpers live in support targets split the same way:
`TUITestSupport`, `TUIAppTestSupport`, and five feature ones. The 11,561
tests are the same, by name, before and after.

### Build times

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

### B. Shipped the safe option

#### B-TS-1. A feature's tests that drive the App live with the feature, not with the integration tests

*61 files needed TUILists and TUIApp, 36 TUITables and TUIApp, …*

The request named an integration target for tests needing two modules. Most
tests that need a feature module also need TUIApp — `applyRuntimeServices(from:)`,
which builds a render pass's environment, or one of the App-level harnesses —
and sending them all to the integration target left it at 437 files, the
largest. A feature's target depends on TUIApp instead where one of its files
needs it. An edit to TUIApp then rebuilds those feature targets too, as it
rebuilds every target above TUIApp anyway; an edit to the feature still
rebuilds only the feature's tests and the integration ones.

#### B-TS-2. A test target names every module its files import

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

#### B-TS-3. The placement is read from the compiler's index, not from compiling until it builds

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

### A. Needs your decision

#### A-TS-1. A low-module edit is slower on 6.4

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

## Completing the SwiftUI API: decisions from lane TT2

*Superseded on 2026-10-14 by a test target per module: see
[`Test targets split by module (TS).md`](<Compile time and the test targets.md>).
The four targets by area below no longer exist; the support target's guard
(B-TT2-1) carries over to every support target.*

*Lane TT2 landed the test-target split the owner approved on 2026-10-08 ("fine,
if it has a notable benefit"), which lane TT1 had measured as an experiment: the
umbrella suite, one test target of 1,178 files, is four test targets by area
and a plain support target, TUITestSupport. It changed no public API and
nothing the library does. This file holds the judgement calls the work reached
that the brief did not already settle, in the format of
[the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>):*

- **A-TT2-n — needs your decision.** Nothing has shipped for these.
- **B-TT2-n — shipped the safe option.** Says what the fuller version would be,
  and its price.
- **C-TT2-n — declined.** With the reason.

There is no A or C entry.

### B. Shipped the safe option

#### B-TT2-1. The support target compiles empty in a release build, and a release test build turns it on by hand

*TUITestSupport: 42 files, every one `@testable import`ing library modules*

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

#### B-TT2-2. ParallelTest's weight cache is documented, not migrated

*Tools/ParallelTest, `fill_weights`*

The cache is keyed by test ID, and an ID names its module, so the 6,628 tests
that moved out of `TUITests` are unknown to a cache calibrated before the
split, and their suites' recorded work is filed under `TUITests.<Suite>`,
which `fill_weights` does not match to `TUIAppTests.<Suite>`. They are priced
at the median until `--calibrate` runs again, which the README now says. CI
keeps no cache.

**The fuller version:** let `fill_weights` match a moved suite's lost work by
the suite's name without its module, so that a move between test targets costs
nothing. A few lines; the price is that two suites of one name in different
targets would share each other's lost work, and a recalibration is cheaper
than either.

## The swift-syntax range

The macros (`@Animatable`, `@Entry`) need swift-syntax, which everyone resolves and only macro users compile. The owner kept it in the package (B-D6M-2, (a), 2026-10-26, after (c) was measured to cost the repository's own builds more than priced).

### B-D6M-2. swift-syntax is taken from 602.0.0 up to the next major, not pinned to 602

*The `TUIMacros` product's swift-syntax dependency (A52)*

**Shipped:** `"602.0.0"..<"700.0.0"`. A52 asked for swift-syntax "pinned to the
toolchain's release line", and it first shipped as `"602.0.0"..<"603.0.0"`,
Swift 6.2's line. But every client of TUI resolves that range, macros or
not: SwiftPM builds by target and resolves by package (measured: a client of
the `TUI` product alone clones swift-syntax and compiles none of it). So
the cap refused any app that also depends on a package wanting a newer
swift-syntax — measured: a client with TUI and a package requiring
`from: "603.0.0"` failed `swift package resolve` with a conflict, and
resolves with the wide range. Swift 6.3's 603 and 6.4's 604 are out, so that
is any app with a current macro package in it. The wide range is what macro
packages commonly declare.

**The price:** prebuilts. SwiftPM resolves the newest in range (604.0.0 today)
and takes swift-syntax prebuilt only where one is published for that version
and the toolchain: measured on download.swift.org, only 602.0.0 for Swift
6.2.x (Linux and Windows; none for macOS, none for 603 or 604 under any
toolchain). So an app on Swift 6.2 that uses the macros now compiles
swift-syntax once, unless it pins `exact: "602.0.0"` itself, which the
Package.swift comment says. Checked that the plugin builds and expands
against 604.0.0 with Swift 6.2.4 (zero warnings; a probe using `@Animatable`
reads and writes its data correctly). CI's Linux 6.2 lane pins 602.0.0
(`swift package resolve swift-syntax --version 602.0.0`), which keeps it on
the prebuilt and tests the range's floor; every other lane tests its top.

**The fuller version** keeps a client off swift-syntax entirely: the macros in
a package of their own, in a second repository (SwiftPM cannot take a package from a subfolder of a remote one), so
that a TUI-only client never resolves it. That is a release-process cost
(versioning two packages together) for the owner to weigh; nothing in the
code would change.

**A package trait instead (option (c), measured 2026-10-24, lane MISC).** The
owner asked for (c) to be checked and taken if it works. The experiment, on a
shallow clone of the tree tagged as a version and resolved by `file://` URL
as a client resolves a release, changed two things. It added a non-default
trait, `Macros`. It made the plugin's two swift-syntax products conditional
on it, `condition: .when(traits: ["Macros"])`. The results:

- A client of the `TUI` product with no traits listed resolves
  `["tuikit"]`: no swift-syntax in its `Package.resolved`, none in
  `.build/checkouts`.
- A client of `TUIMacros` with `traits: [.defaults, "Macros"]` resolves
  `["swift-syntax", "tuikit"]`. So does every client of the unchanged tree.
- Both held with Xcode's Swift 6.2.4 and swift.org's 6.3.3 and 6.4.0.
- The root package resolves the same way. A plain `swift package resolve`
  rewrote the committed `Package.resolved` without the swift-syntax pin.
  `--enable-all-traits` resolved it again, and
  `swift package --enable-all-traits resolve swift-syntax --version 602.0.0`
  took the 6.2 prebuilt.

So (c) works for clients. Its cost to the repository is a second build
configuration and a `Package.resolved` that differs between them. Its cost to
macro users is a trait to write, and an unpointed error when they forget it.
These were not in its price, so they went back to the owner (Open owner
decisions, follow-up B-D6M-2). The shipped range stands meanwhile.
