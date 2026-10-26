# The module split's run-time cost, step by step (2026-10-07 to 2026-10-10)

> **Status:** recovered and landed by 2026-10-10 (the last remedies in `a773b5b61`, `5b65beb61` and `4462eb015`),
> with one small residual left open. **Decided by:** the owner (the goal and the gate), lanes and the coordinator
> (each remedy, recorded in the step's decisions file). **Working notes** (not in git): `SPB5/regress/`,
> `SPB5b/regress/`, `SPB6/regress/` (profiles and diagnoses), `CTL/diagnosis.md`, `perf/results/sp*` (the A/B runs),
> and the coordinator's ledger `plan/QUEUE.md`.

## Question

Splitting TUI's one module into about thirty turns some calls that were inside a module into calls across a
module boundary, where the optimiser can no longer see the callee. How much run time does that cost, and how is it
won back? The owner, 2026-10-08: "are these impacts cumulative? Are we losing a percent or two of performance with
every module that gets split out? Because that would be really bad." And: "I anticipate some initial performance
loss from the modularisation, but my hope is we can recover all the regressions with some care … Hopefully relevant
optimisations like inlining annotations etc can suffice. The baseline is pre-modularisation work."

## Answer

- **Against the pre-split build, the finished split is neutral.** Warm, over six code placements: `controls`
  −4.35% (faster than before the split), `table-tail` +0.55%, everything else flat. Cold: nothing slower. A stripped
  Stress is 1.06% larger (+137.5 KB, Xcode's 6.2.4).
- **The costs came in a few classes, each with a split-related remedy:**
  - a generic call made unspecialised by the boundary (a shortcut table per row, a list row's buffer, a tap
    gesture's `onEnded`, a table's scroll window): the callee `@inlinable` with the state it touches
    `@usableFromInline` (the plan's tier 2);
  - class properties widened to `package`, which gained dynamic exclusivity and main-actor checks: private storage
    under `package` accessors;
  - small getters no longer inlined (`Text`'s unstyled check, a bordered container's body lines): inlined again;
  - opaque result types naming another module's internal types, resolved at run time on every call (the inline
    menu column): the code moved back to where the types are concrete, and a CONTRIBUTING rule and a predictor for
    the next carves;
  - a `static let` read from another module calls its addressor: kept, by the owner's ruling (A-SPH2-1).
- **Much of what looked like cost was code placement.** `geometry`, `customlayout` and `app-shapes` moved by 1–1.6%
  when 1 KB of unrelated code was added, so they were judged by A/Bs averaged over six placements.

## Key measurements

`ab_bench`, paired, warm and cold, on a quiet machine, Xcode's 6.2.4 release `Stress`; the baseline is `premod-h`,
c181ec0f9 (the commit before the split's first refactor) with the benchmark harness's later fixes. Each regression
was profiled with `Tools/Profiling` and compared by static counts of runtime calls in the binary.

| step (modules carved) | worst against the baseline | cause | remedy |
|---|---|---|---|
| B1, B2 (Foundation, Strings, TerminalHost) | +0.7% warm and cold, against step A's build | — | none needed |
| B3 to B5 (App, ColorPicker, Navigation) | `app-shapes` +1.6% warm, +2.0% cold, from B3 to B5 | placement: a 1 KB pad moved the same scenarios as much | none for speed |
| B6 (Lists), with its first fixes | warm `megalist` +3.8%, `kitchensink` +3.5%; cold `tables-vstack` +3.5% | three unspecialised or out-of-line calls; exclusivity and main-actor checks on widened class properties | lanes SPH, SPH2, SPH3; then flat warm, cold `table-api` +0.5% |
| B5b, B5c (Chrome, Effects, Menus; Bitmaps) | `menus` cold +0.9% | the inline menu column's opaque results (≈0.15–0.24 points); the rest placement | lane SPM1 (with B5c's placement, nothing was slower cold already) |
| B7 (TextInput) | `controls` +0.4% warm; nothing cold | — | — |
| C1 to C8 (eight peels, in batches of two lanes) | warm `controls` +0.6% to +1.1%, `kitchensink` +1.1% (C3 to C6), `table-tail` +0.6% (C7, C8); cold up to +0.9% (C3 to C6), nothing after C8 | a table's scroll window not inlinable; a tap gesture's `onEnded` called generically for every row | `d7ce43ffd`; lane RES |
| after RES | warm `controls` −4.35%, `table-tail` +0.55%; cold nothing (C8's run) | `table-tail`: mostly unattributed | open, low priority |

Static counts in a release `Stress` after B7, against the baseline: main-actor executor checks 1,383 (1,488), access
checks 3,938 (4,194): both below the pre-split build.

## Reasoning

- **The gate changed with experience.** At first each carve was held until it was clean. The owner, 2026-10-09:
  "we're only trying to identify serious regressions that could be real showstoppers or require a different
  approach. Smaller regressions that merely require some optimisation can be done later, so long as we are pretty
  confident we know what to do". So the C steps landed in batches, each batch's small costs queued with a named
  remedy, and the goal of recovering everything stayed.
- **Three measurement faults were found and fixed on the way:** the profile analyser dropped repeated stacks, so
  shares before `65abd024e` counted 21–64% of the samples; the cold benchmark harness leaked each frame's context, so
  cold A/Bs before its fix (lane ST3) were invalid for the leaking scenarios; and `megalist`'s A/B cannot be resolved
  at all (identical bytes differ by 8% with the path length).
- **Remedies stayed split-related,** as the owner asked: inlining annotations, access levels, keeping hot code
  inside one module, non-generic helpers. Pre-made specialisations were evaluated and not adopted
  ([pre-specialisation](<../Compile time/Pre-specialisation across module boundaries (2026-10-08).md>)).

## Links

Decisions, one file per step and per recovery lane, in
[`SwiftUI parity/Decisions/Module split/`](<../../../SwiftUI parity/Decisions/Module split>): in particular
[SPH](<../../../SwiftUI parity/Decisions/Module split/Cost recovery after steps B4 to B6 (SPH).md>),
[SPH2](<../../../SwiftUI parity/Decisions/Module split/Cost recovery, inlinable audit and package storage (SPH2).md>),
[SPH3](<../../../SwiftUI parity/Decisions/Module split/Cost recovery, list and table remedies after step B6 (SPH3).md>),
[SPM1](<../../../SwiftUI parity/Decisions/Module split/Cost recovery, the inline menu column after step B5b (SPM1).md>)
and [RES](<../../../SwiftUI parity/Decisions/Module split/Cost recovery, the last warm residuals (RES).md>).
The plan: [Module split plan, revision 4](<../../Module split plan, revision 4 (2026-10-07).md>). What the split
delivered: [build time, size and tests](<What the module split delivered, build time, size and tests (2026-10-11).md>).
