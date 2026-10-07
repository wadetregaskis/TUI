# What the SwiftUI-API batch cost, and what the pass got back

**Measured 2026-10-04** on macOS 15.8 / arm64 (the VM; SDK 26.2), release builds
of `Stress` with `-Xswiftc -g`. Every number is measured, and the method for each
is stated so it can be re-run.

The SwiftUI-API completion batch is 382 commits (`d259fb308..37f15159b`). This
pass measured what they cost against the tree before them, found the causes,
and fixed what could be fixed without changing behaviour: fifteen commits,
`37f15159b..d5fa453c5`. A dated record: symbols are as named on the day.

---

## 1. Method

- **Base and head.** `base` is `origin/main` (`d259fb308`), the tree before the
  batch; `head` is `37f15159b`, the batch's last commit. Both were built clean
  in detached worktrees.
- **A/B.** `Tools/Profiling/ab_bench.py`: CPU per frame, order randomised per
  rep, median of paired ratios with a bootstrap interval, 15 reps. Every
  scenario was run warm (the steady state) and `--cold` (every frame a cache
  miss: a page arriving). A null test at the start (one binary against a copy
  of itself, `--quick`) put every interval inside ±2.2%. No builds, tests or
  agents ran during a timing run.
- **Scenarios that matched.** The batch edited some Stress scenarios. The table
  and button-style edits are renames, so the scenario compares like for like.
  `gradients` also gained a mesh-gradient band, so it was also compared with a
  head build that had the band removed (`hdng`).
- **A new scenario.** The batch's costs sat in controls that no scenario draws
  on its own, so this pass added the `controls` matrix (`e44d4e567`). Each
  variant is rows of one control: tap, tap-stable, labels, fields,
  interpolated, markdown, progress, scroll-resize. "Base + scenario" (`B0`) is
  the base tree with that file applied.
- **Attribution.** Time Profiler traces, recorded by attaching to `Stress
  --bench` on the main thread, base against head. Each function's per-frame
  µs is its share of samples × that binary's ab_bench µs/frame. One caution
  came out of the pass: a profile share is a hypothesis, not a cost (§5).
- **Lane ladder.** One build at each of the 18 lane-fold commits. Every
  regressed scenario was run on each build, which put each regression inside
  one lane. Builds at a few commits inside that lane then found the commit.
- **Gates.** Each fix was A/B'd alone against its parent: a step build, or
  for an agent's commit, a build at that commit. Each was also run through the
  full suite on 6.2.4 (`parallel_test.py`), SwiftLint `--strict`, and
  `Stress --selfcheck`.

A read-only survey of the diff (six agents, 46 findings) said where to look
first. Its high-severity finding was right. Several of its medium findings
measured as nothing (§5).

## 2. What the batch cost

Base → head, CPU per frame, every interval clear of zero:

| Scenario | Warm | Cold |
|---|---:|---:|
| table-churn-wrapped | +106% | +194% |
| table-multiline | +80% | +116% |
| scrollfollow | +53% | +48% |
| menus | +32% | +8% |
| dashboard | +18% | +50% |
| churn | +18% | +18% |
| gradients, mesh band removed | +12% | +13% |
| kitchensink | +5% | +28% |
| customlayout | +1% | +24% |
| truncate | +6% | +22% |
| anyview | 0% | +13% |
| tables-scroll | +8% | +6% |
| preferences, scrolleager, framedcolumns, app-shapes | +3 to +5% | +2 to +4% |

The `controls` matrix, head against base + scenario: labels +99%, fields +68%,
interpolated text +55%, progress +48%, tap +23%, tap-stable +12%, Markdown
literals +172%. The last is a feature: base drew the asterisks as text.

Peak RSS grew by about 1 MB in every scenario. The `Stress` binary grew from
17.3 MB to 23.6 MB, which is code: the batch added 54,000 lines.

## 3. Causes, and the fixes

All numbers below are each change measured alone against its parent.

1. **Every interpolated `Text` literal ran the full Markdown parse**
   (`04910c445`).
   - Cause: an interpolation's placeholder is `%@`, and the byte scan in front
     of the parser took any `@` as a possible email autolink.
   - Fix: the scan now takes an `@` only after a byte an address's local part
     can end with, which is the rule the email scan itself applies.
   - Result: scrollfollow −33%, churn −14%, gradients −9%, interpolated
     controls −34%. Cold: customlayout −18%, kitchensink −14%, anyview −11%,
     dashboard −10%.
   - The largest single cause: most of the regression in churn, scrollfollow
     and gradients, and in customlayout, kitchensink and anyview cold.
2. **Plain `Text` cells in multi-line table columns rendered as views**
   (`31b17677b`, `4b8a5e75f`).
   - Cause: when column cells became views, only a one-line column kept the
     string path.
   - Fix: a plain `Text` on a multi-line column is now wrapped as `Text` wraps
     itself, with `TextWrapping.fit`, and its lines go straight to the row.
   - Result: table-multiline −29% then −23%, table-churn-wrapped −31% then
     −31%. Both are back at base or slightly under.
3. **Reflection over the new style hosts** (`5f5258e4e`).
   - Cause: `resolveEnvironmentProperties` walks a view with `Mirror` on every
     body that has an `@Environment`. The batch wrapped common controls in
     composites that hold one.
   - Fix: `ResolvesOwnEnvironment` lets a framework view list its own
     wrappers. 33 framework views adopt it. A debug build checks each
     adopter's list against the reflection the first time the view renders.
   - Result: labels −63%, progress −24%, fields −23%; dashboard cold −14%.
4. **`.buttonStyle(_:)` became two transform layers** (`51189fca0`).
   - Bisected to `262105085`, which took menus from +4% to +29% over base.
   - Fix: one environment write again, through computed environment values
     that install an appearance, or push a custom style, in one go.
   - Result: menus −14%.
5. **The end-of-pass sweep of conditional branch records** (`3782a00de`).
   - Cause: a memo-served page renders none of its `if`s, so every record took
     the retained-subtree check, and the first check per card climbs a
     30-level identity chain. Bisected to `c9248f843` (`ProgressView`'s body
     became an `if`/`else`): dashboard +1% → +12%.
   - Fix: the sweep now runs only when the table has doubled since the last
     one (plus 64).
   - Result: dashboard −12%, menus −6%, kitchensink −1%.
   - **`modifiers` −45% against base.** That cost was there before the batch:
     400 memo-served rows each holding a conditional. Checksums and every memo
     counter are identical before and after.
6. **Style hosts as composites with an `if`/`else`** (`a3e74eb4b`, `e5949a6f6`).
   - Fix: the text-field frame and the progress-view host read their style from
     the context and draw the chosen view in place, a style body under a branch
     identity of its own.
   - Result: fields −18%, progress −6%.
7. **Gesture attachments** (`85d5231c0`, `79647ebb5`, `d3a25fdf4`; an agent's
   work, timed here).
   - What changed: recognizers are built when a press needs them, not every
     frame (tap −1%). Region, role and feature requests file as one
     registration, journaled once, where it was four (tap −9%, tap-stable −8%).
     The attachment's fields are reordered so it has no padding: indistinguishable,
     kept for the layout rule.
   - A fourth commit (a list scan in place of a dictionary) measured nothing and
     was left out.
8. **Markdown literals parse once per template** (`e7a1deff9`, `e71119fa8`,
   `d5fa453c5`; an agent's work, timed here).
   - What changed: atoms are appended in place (−12%), the parser appends one
     character without an array (−2%), and the parse is kept per resolved
     template (−39%). Markdown literals −47% in all.
   - Checked byte-identical against the previous code on more than 500 cases.

## 4. Where it ends

Base → `d5fa453c5`, full sweep, 15 reps:

| Scenario | Warm | Cold | Notes |
|---|---:|---:|---|
| modifiers | **−45%** | +3.5% | the conditional sweep (§3.5) |
| table-churn-wrapped, table-multiline | −2% | −4% | |
| scrollfollow, churn, customlayout, anyview, textwall, deep, fanout | +2.3% at most | +1.8% at most | |
| framedcolumns, megalist, keyrows, alpharamp | +1 to +2.5% | +1.5 to +2.6% | megalist verdicts are unreliable |
| app-shapes, table, table-api, table-tail | under +1% | faster or flat | |
| truncate | +6% | **+23%** | §6 |
| tables-scroll | +7.5% | +6% | §6 |
| menus | +7% | +5% | §6 |
| dashboard | +5% | **+11%** | §6 |
| kitchensink | +4.5% | +5% | |
| preferences, scrolleager | +4 to +4.5% | +2 to +4% | |
| tables-vstack | +1% | +6.6% | |
| gradients | +8.5% | +8% | the mesh band this scenario gained (+8.8% of its frame); the rest is flat |

The `controls` matrix against base + scenario:

| Variant | Before the pass | After |
|---|---:|---:|
| labels | +99% | −26% |
| interpolated | +55% | +2% |
| fields | +68% | +6% |
| progress | +48% | +5% |
| tap | +23% | +10% |
| tap-stable | +12% | +3% |
| scroll-resize | +3% | +3% |
| markdown (a new feature) | +172% | +46% |

## 5. Tried, measured as nothing, and dropped

Each of these looked right in a profile or on reading, and measured
indistinguishable on the scenario that should have moved, so none was committed:

- `foregroundStyle` writing its two level nils only when set. The survey's
  "heap-boxed nil per write" was real, but it cost nothing measurable on menus,
  modifiers or gradients.
- A scroll view publishing its container size only for its ideal-size measure.
- Pass stamps on conditional records, in place of the active-set lookup. The
  profile put about 7 µs/frame in that filter, but the cost was the first
  retained-subtree climb, not the lookup. The amortised sweep (§3.5) was the
  fix.
- `ProgressView`'s timer `if`/`else` as a bridge: dashboard unchanged, progress
  −1.6%.
- `ButtonStyleConfiguration.Label`'s `if`/`else` as a bridge: menus −1.3%,
  with an interval through zero, so the `+4%` that `f6399a5b1` added to menus
  is not recovered by it.
- A list scan in place of the gesture participants' dictionary.

The lesson worth keeping: **a profile's share is a hypothesis, not a cost.**
Three times a profile pointed at a cost the A/B did not find: the conditional
filter, twice (about 9% of the dashboard profile, through two different
fixes), and the gesture rebuild (about 5% of the tap profile; −1% removed).
What the profiles measured were first-time costs the changes did not touch.
Only the A/B decided.

## 6. What is left, and why

- **truncate, cold +23% (warm +6%).** SwiftUI's column API builds a view per
  cell, so a single-line table builds a `Text` and checks that it is plain
  (style equality plus a newline scan), for every cell on every pass. A cold
  frame passes over every row several times: the `.fit` width scan, the
  analytic size and the render. `Table.init` also builds erased column specs,
  one closure each, on every body evaluation. Options: cache cell values for
  one pass across the fit scan, the size and the render; or give `Text` a
  cheaper "plain" check (a flag set by the plain initialisers). The first is
  bigger, and is the one that would show.
- **tables-scroll +7.5%.** Bisected to `6f41c73f7` (content margins inside
  the scroll area): +4.2%. The cost is spread over a dozen small scroll views:
  margin reads, the viewport helper and the bar span. About 0.3 µs per scroll
  view per frame. Left as it is.
- **menus +7%.** Of the rest, `f6399a5b1` (`configuration.label` as a view)
  is +4%, and the bridge tried above did not recover it. Unattributed.
- **dashboard, cold +11%.** Diffuse: deeper identity chains (node
  allocations), larger value hashes, more `ChildView` and `RenderContext`
  copies in the panel measures. No single site.
- **tap +10%, tap-stable +3%.** The gesture region stays on the hover-observer
  lane, which a hover test shows it must.
- **Markdown literals +46%.** A new feature. The parse is kept, and what is
  left is filling in each construction's values.
- **No scenario at all** for: scroll geometry and phase observers (B26/B27),
  `@FocusedValue` (B34), live time text (B51), `LazyVGrid` sections (B71),
  `.transition` (B52), and a mesh-gradient picture under a graphics terminal.
  The owed A/Bs for those stay owed.

The owed A/Bs the decisions doc names that this pass did run:

- **B86 (Markdown):** found the placeholder bug, §3.1. The entry records it.
- **B95 (MeshGradient):** the mesh band costs 8.8% of the gradients frame.
  The ramps without it are flat.
- **W17g (gestures):** §3.7.
- **B19 (alignment-guide witness):** deep −0.7%, fanout +0.6%, kitchensink
  +4.5% at the end. The kitchensink share is not separated from the rest.
- **B71 (pinning):** deep, megalist and kitchensink as above; megalist's
  verdicts are unreliable (path-length sensitivity).

## 7. Found on the way

- **A stale incremental build.** A stored property added to a TUIkitView
  class left the debug test build reading the old field offset of `public let
  animations`, and a test crashed 6/6 until the build directory was removed.
  Clean both build directories after any class layout change, before testing
  or timing.
- **`StdinArrivalNotifierTests` flakes under parallel load.** Two different
  tests, each passing alone. It looks like a descriptor race between tests
  running concurrently. Put to a separate task.
- **A single tap chained under a double tap fires once, then never.** Found by
  the gesture agent on unmodified code. Put to a separate task.

## 8. A second pass: what was left, and what was always there

The owner asked for more after §6. This pass profiled what was still slower
than base, and also looked for costs every app had paid all along. It is 31
commits, `4de3b6e3d..f62b3cc9d`.

**Method.** The same profiles as §1, base against `d5fa453c5`, on the
scenarios §6 left open. Five read-only agents then each read one group's
profile deltas and the code behind them, proposed changes and estimated what
each would save, and a skeptic per group checked each proposal against the
code and the traces. Two agents implemented the reviewed proposals in
worktrees, and a third reviewed each chain for behaviour changes; one
`TransformEnvironmentModifier` fix came out of that review. Every change was
built as a release binary of its own and A/B'd against its parent (15 reps,
quiet machine, same flags as §1). Every step binary was also checked to draw
byte-identical frames to `d5fa453c5` on nine scenarios. Four changes measured
as nothing or worse and were not committed.

**The largest find was not the batch's.** `EnvironmentValues`' key getter
lives in TUIkitCore, and every accessor that calls it is in another module,
so it ran unspecialised. Its `as? K.Value` makes a `K.Value?`, and the
compiler fetched `Optional<K.Value>`'s metadata at the getter's entry, on
every read, hit or miss. That was 16.6% of a `scrolleager` frame (base 14.5%)
and 9% of `controls`/`tap`. It is the "unexplained ~10% in the metadata cache"
an earlier environment study left open. Making the getter `@inlinable`
specialises each accessor to its key. The same hoisted `Optional<V>` sat at
the entry of the unspecialised `renderToBuffer` and `measureChildUncached`,
for the rare animatable branch, and moved out of line.

| Commit (short subject) | Scenario | Change |
|---|---|---|
| environment reads specialised | scrolleager / controls tap / menus / dashboard / kitchensink | −21.0% / −13.6% / −8.6% / −5.4% / −2.5% |
| animatable substitute out of line | dashboard cold / scrolleager / tables-scroll / deep | −2.8% / −2.6% / −2.4% / −2.0% |
| track fill spelled once per glyph, not per cell | controls progress / dashboard cold | **−65.5%** / −3.8% |
| field surface walked once and kept | controls fields | −24.3% |
| row builder: hidden requirement, no per-row cast | table-api rows-builder (new) | −55.9% (cold −53.4%) |
| flat row list kept as values | table-api rows-builder | −36.1% (cold −32.0%) |
| line feeds found by `memchr` | truncate / cold | −6.9% / −12.4% |
| concatenation runs attributed whole | controls markdown | −15.8% |
| Markdown template keeps merged runs | controls markdown | −8.7% |
| `%` tested as a byte before Foundation | controls markdown / interpolated | −8.1% / −4.8% |
| String and Int arguments without `String(describing:)` | controls interpolated / dashboard cold | −5.5% / −1.2% |
| bare `%@` templates substituted from bytes | controls interpolated | −4.9% |
| SGR introducer written as one string | controls markdown / menus / tap | −4.6% / −3.1% / −2.7% |
| picture token only when a picture can draw | controls progress | −6.8% |
| built-in progress style by metatype, drawn in place | controls progress / dashboard cold | −5.3% / −1.2% |
| scroll bar lines joined in one string | tables-scroll / preferences | −6.0% / −1.5% |
| ForEach reads `Identifiable` ids directly | scrolleager | −5.2% |
| observation leases behind a constant pointer | controls fields / progress | −4.2% / −2.9% |

Smaller commits, each A/B'd alone: the Text column cast once per column
(truncate cold −2.1%), the one-line fit scan (truncate cold −1.7%), the column
hidden requirement (truncate −1.1%), the auto-repeat token (tables-scroll
−1.3%), field caps memo (fields −3.4%), unbordered field core in place (fields
−3.1%), the list bar memo (kitchensink −1.9%), `noteAppliedEnvironment`'s
autoclosure (menus −1.3%), the transform environment's one projection (menus
−2.0%), and the read tracker's counters (fields −1.1%, dashboard cold −1.0%).
The shared button-cap introducer measured as nothing; it stays as the helper
the field-caps commit is built on.

`table-api`/`rows-builder` is a new Stress variant: `Table(of:columns:rows:)`
over `ForEach(rows) { TableRow($0) }`. Nothing measured the row builder
before. It cost 3,953 µs a frame against 441 for the same table built from a
collection; after these two commits it is about 973.

**Measured as nothing, not committed:** comparing a `TextStyle` to the
default by its bytes (+1.1% slower on truncate); stamping a table's column
indices in place; skipping the privacy read when `.privacy` is off (nothing,
once environment reads were cheap); deferring the status bar's Return verb.

**Lessons.**
- A cast to a protocol constrained by a generic argument (`as? any P<T>`)
  builds its metadata from a mangled name on every call.
- `as?` to a type parameter in unspecialised code costs an `Optional<T>`
  metadata lookup at the function's entry, taken or not. A pattern cast
  avoids it in a plain generic. A cross-module accessor needs `@inlinable`.
- An incremental release build after a class's stored layout changes can fail
  to link, because a dependent still references the old field-offset symbol.
  Build those steps clean.

**The sweep against base.** `f62b3cc9d` against base on all 28 scenarios,
release builds, 15 reps, CPU time, run on 2026-10-06 with no builds or
tests running:

| | Faster | Same | Slower | Largest changes |
|---|---|---|---|---|
| warm | 26 | 2 (app-shapes, customlayout) | 0 | modifiers −49.8%, scrolleager −30.0%, scrollfollow −22.5%, churn −16.9%, alpharamp −12.4%, preferences −10.4% |
| cold | 27 | 0 | 1 (truncate +2.9%) | scrolleager −26.9%, scrollfollow −21.2%, churn −16.0%, keyrows −15.9%, textwall −15.3%, preferences −14.4%, anyview −13.5% |

Most other scenarios are 3–9% faster than base. The batch's cost is gone
everywhere except cold `truncate`, which is +2.9% (95% CI +2.2..+3.5%).
Resident memory is 0.6–1.9 MB higher per warm scenario; that was not
investigated. During the warm run XProtect was scanning (load 4.4). CPU time
leaves out preemption but not cache contention. The cold run had a quiet
machine.
