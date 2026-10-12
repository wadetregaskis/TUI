# What the module split delivered: build time, size and tests (2026-10-11)

> **Status:** landed: every planned module a target by 2026-10-10 (`e7f52c800`), library products for each on
> 2026-10-11 (`17a63a3a7`), the test suite in four targets on 2026-10-10 (`b377b5f24`). **Decided by:** the owner,
> 2026-10-07 (do the split, sooner) and 2026-10-11 (per-module products). **Working notes** (not in git):
> `buildtime/` (the analysis, the M3 trial split, the plan's revisions), `perf/c9bt/` (products against the
> umbrella), `TT1/` and `TT2/` (test targets), `TC2/baseline.md`, and the measurements quoted in each step's commit.

## Question

The owner, 2026-10-06: "I'm receiving reports that a full (clean) release build of TUIkit is taking many minutes
for some people … If we can reduce that significantly, that'll speed up our development, too", and, the same
evening, that release binary size matters as well. The plan that followed split the one 230,000-line module into an
umbrella over separately compiled modules, so that they compile in parallel and an app can depend on fewer of them
([plan, revision 4](<../../Module split plan, revision 4 (2026-10-07).md>)). What did it deliver, against what the
plan estimated?

## Answer

- **Build time fell, but less than the plan's model said.** On Xcode's 6.2.4 the plan put a clean build of the
  finished split at 52.5 s (55.9 s conservatively) against 77.8 s measured before it; the steps' own measurements
  put the finished tree at about 57–58 s, on a busier machine. On 6.4.0 the same build went from about 102 s before
  the split to about 70 s. The build's peak memory roughly halved.
- **For a small app the larger win is the products:** a hello world on `TUIkitApp` compiles 8 of TUIkit's modules
  instead of 26, builds 15.6% faster from clean, and is 37.6% smaller stripped.
- **Run time is neutral** after the recoveries
  ([the split's run-time cost](<The module split's run-time cost, step by step (2026-10-10).md>)); a stripped
  Stress is 1.06% larger.
- **Tests:** four umbrella test targets instead of one took a one-file test edit from about 60 to about 18 CPU
  seconds.
- **Faster than planned:** the coarse stage took 52 hours from the owner's go, against the plan's 3.5–4.5 weeks.

## Key measurements

The development machine, an arm64 macOS 15.8.1 VM with 12 cores, shared with other lanes except in a quiet window.

| what | before | after | how |
|---|--:|--:|---|
| clean release build, Xcode's 6.2.4 | 77.8 s | 63.1 s after the coarse stage (plan: 57.4 s); 57.3 s after step C2; 57.9 s after C5 and C6 | before: quiet box (plan rev. 4); after: one paired build per step, busy machine |
| clean release build, 6.4.0 | 102.4 s at the end of phase A | 69.2 s after C2; 69.1–72.2 s over C3 to C6 | before: `TC2/baseline.md`, a busy machine; after: each step's commit |
| peak memory of the build | 3.7–3.8 GB | 1.94 GB (Xcode's) and 2.25 GB (6.4.0) after B7 | before: the M3 trial's one-module baseline, quiet box; after: B7's commit |
| hello world, `TUIkit` against `TUIkitApp`, 6.4.0, clean build `-j 12` | 75.1, 68.9 s | 62.8, 58.7 s (−15.6%) | quiet window, two alternating rounds |
| the same, stripped | 9,552,376 B | 5,964,832 B (−37.6%) | with the internalize trait |
| the same, launch to first byte, and footprint | 7.1 ms, 2.85 MiB | 6.8 ms, 2.76 MiB | 20 runs each, in a PTY |
| stripped `Stress`, Xcode's 6.2.4 | 12,988,984 B | 13,126,504 B (+1.06%) | after step C8 |
| a one-file test edit, CPU | about 60 s | about 18 s | decisions TT2 |

The "after" build times are single pairs measured while other lanes built, by the commit of each step (`da8dbdb46`
for B7, `e2e8c7a3c` for C2); read the direction, not the tenths. No quiet-box clean build of the finished split, set
against the plan's estimate, is recorded in the working notes. The launch figures time the first byte the program
writes; its text appeared at about 1.5 s for both, because the PTY never answers TUIkit's terminal queries.

## Reasoning

- **Why less than the model:** the plan's model was fitted on the M3 trial split's quiet-box timings and does not
  model contention between parallel jobs, and the later measurements were taken on a shared machine. The critical
  path after the coarse stage was View, TUIkitFoundation, TUIkitLists, TUIkitColorPicker and the umbrella, so
  TUIkitFoundation's job still bounds the build.
- **Why products matter more than parallelism for apps:** a release build compiles each module as one job whose type
  checking and SIL optimisation are single-threaded, so an app that compiles fewer modules saves more than one that
  compiles the same modules in parallel.
- **The split also cost bytes,** in the export table every app carried, which the
  [`UnexportTUIkitSymbols`](<../Binary size/Which links TUIkit's flags reach, and the debug map (2026-10-11).md>)
  trait has since taken to 9 KB, and in duplicated weak definitions under Swift Build, about 16–33 KB per extra
  module until SwiftPM keeps private externs.

## Links

[Per-module products](<../../Per-module products (2026-10-11).md>) (the products' design and trade-offs);
decisions for each step in
[`SwiftUI parity/Decisions/Module split/`](<../../../SwiftUI parity/Decisions/Module split>), and
[TT2](<../../../SwiftUI parity/Decisions/Compile time and binary size/Test targets split by area (TT2).md>);
README [Depending on fewer modules](<../../../../README.md#depending-on-fewer-modules>) and
[Build time](<../../../../README.md#build-time>); the
[compile time and binary size analysis](<../../Compile time and binary size analysis (2026-10-07).md>) that led to
the split; [type-check time on Swift 6.4](<../Compile time/Type-check time on Swift 6.4, test expectations and exit tests (2026-10-08).md>).
