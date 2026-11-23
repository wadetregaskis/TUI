# When a body runs: the plain-body memo

*Whether an app's plain view (one with no `==` of its own) runs `body` on
every frame, or only when something it depends on changed, as in SwiftUI.
Studied 2026-11-01, built and turned on 2026-11-02. Id: PLAIN-MEMO. It
extends Option C, told in [the update model](<The update model - when effects run.md>).*

## In short

Until 2026-11-02 every plain view's `body` ran on every frame, and usually
twice (once to measure, once to draw), so two sibling bodies of 50 ms cost
about 200 ms a key whatever key it was. SwiftUI runs neither. A study
measured both frameworks, priced four options, and recommended a memo on
an app's plain views that compares their fields, in two tiers, after which
a body nothing tracked asks for does not run. The owner ruled it on by
default on 2026-11-02, accepting SwiftUI's contract: a read in `body` that
nothing tracks (a plain class, a global, the clock) stays as drawn until
something tracked changes. That case went from 201 ms to 1.0 ms (SwiftTUI:
28 ms). `TUI_RUN_BODY_ON_EVERY_FRAME=1` restores the old rule.

## The problem

The [SwiftTUI comparison](<../SwiftTUI comparison, 2026-11/README.md>)
found TUI's one clear engine weakness: two siblings whose bodies take 50 ms
and whose inputs never change cost 216 ms a key in TUI and 28 ms in
SwiftTUI. On 2026-11-01 the owner asked for more work on running bodies
less. The memo that could have answered it existed (`renderValueMemoized`),
but only `.equatable()` and `ForEach` rows over `Equatable` elements asked
it: nothing asked on the composite path.

That was history, not oversight. An automatic memo on exactly this path was
built and reverted repeatedly in August 2026 (sections 19 to 28 of
[the August profile](<../../Performance/Full performance profile of Stress and the Example (2026-08).md>)):
keyed by raw bytes it served stale focus, its environment digest never hit,
and a view's bytes carry fresh pointers (`@State`, arrays, closures) that
poison every ancestor. That profile named the way forward: "a synthesised
structural comparator that ignores heap identity". Option C (2026-09-23 to
10-25) then built SwiftUI's contract for `Equatable` rows only, and the
update-model study of 2026-10-24 rejected per-view dependency tracking at
three to six months.

## How it unfolded

1. **2026-11-01, the study** (the record below), against `3d605c2c4`, with
   a prototype on an unlanded branch. It counted when a plain body runs
   (`Tests/TUIIntegrationTests/PlainBodyRunCountTests.swift`), probed
   SwiftUI for the first time on this question
   (`Tools/SwiftUIProbes/Plain body re-evaluation/`, `1dac495bd`), and priced
   options (a) to (d). It recommended (c), built in six steps, off by
   default until measured, and **not** (a) first. It put one question to the
   owner before any of it: the contract change.
2. **2026-11-02, built** (steps 1 to 5), off behind `TUI_PLAIN_MEMO=1`:
   environment stamps made from what differs from the pass's first
   environment (`e464bb53a`); a real app's environment made comparable
   (`9db36ba90`, which also made Option C's re-check run in real apps for
   the first time); the memo (`eb3f4f520`); and, on by default because
   nothing can observe it, a slow body kept from its measure for its draw
   (`0476bb1da`): 201 ms to 101 ms.
3. **2026-11-02, the owner: on.** Optimise what regressed afterwards
   (`session/notes`, `session/log`, and the memory), and rename the
   variable. Turned on in `66159dae8` as `TUI_RUN_BODY_ON_EVERY_FRAME=1`
   (the way out, in the end user's table), with deviation S8 and
   `RenderCycle` rewritten in the same commit.
4. **2026-11-02, the regressions.** `bf2c32afd` (a pass keeps 32 of the
   environments it stamped, not all), `ebf3b6d43` (a composite inside a
   value memo asks only if it takes real time), `7ca183533`, `c13e4536d`.

## Where it stands

On by default. What remains is in "For a future reader".

## For a future reader

- **The contract.** A body reading something no key, observation or state
  tracks is not refreshed by an unrelated frame. SwiftUI behaves the same,
  so a SwiftUI program already expects it. `TUI_VERIFY_RENDER_MEMO` names
  such a view, and `TUI_RUN_BODY_ON_EVERY_FRAME=1` shows it fresh.
  Deviation S8 in [Deliberate deviations](<../../SwiftUI parity/Deliberate deviations from SwiftUI.md>)
  records where TUI stays behind SwiftUI: a closure or `Binding` held below a
  parent's write counts as changed, since TUI cannot look into a closure's
  captures without reflection the runtime does not offer.
- **The verifiers cannot see a dropped per-frame write.** They compare
  buffers. The audit the memory "memo verifier blind to side effects" asks
  for was done as `PlainMemoRegistryTests` (39 scenes: key, mouse, shortcut
  and drag tables, focus ring, screen and input against the memo off).
  Read from source only, not tested: tab menu openers, toolbar
  customisation drags and menu columns. Re-audit when the storable set
  widens again.
- **Identifying an app's own views** was a list of module names in the
  prototype. Check what replaced it before relying on it.
- **Still owed, from the ruling:** the remaining `session/log` and
  `session/notes` cost (+4.0% and +5.5% CPU at the last A/B, on a shared box).
- **Not measured:** bodies under the geometry correction
  (`RenderWalkCheckpoint`); the memory of nested entries on a deep app; why
  SwiftUI's first one or two writes re-run a child that later writes do not.
- **The gate** (a composite stops asking for 4, 8 … 64 passes after two
  failures running) replaced a hit-rate gate on purpose: §28 of the August
  profile showed a simple rate gate is wrong both ways.
- **Measurements below are release builds on a box other lanes shared,**
  except the study's counts and allocations, which are debug. Treat a few
  percent as noise unless repeated. The malloc interposer that found the
  fragmentation (below) was not kept.

## The record

### PLAIN-MEMO. Should a plain view's body be allowed not to run, when nothing tracked says it must?

Asked on the owner's questions page of 2026-11-02, as "the big one":

> Today every body runs on every frame, so reading a plain class, a global or
> `Date()` in a body picks up the new value on any frame, for any reason.
> Under the memo it stays as drawn until something tracked invalidates it.
> That is SwiftUI's rule too, so a SwiftUI program already expects it. A body
> doing a sort currently pays for that sort on every key.

| Option | What it meant | Its cost |
|---|---|---|
| **on** (recommended) | On by default, a variable as the way out; the pinned tests rewritten, the rule and the deviation documented. Suits the aim of beating SwiftTUI everywhere, and SwiftUI programs already expect it. | Up to 13.4 MB more on long sessions; a few percent CPU there; a body reading untracked state goes stale, as on SwiftUI. |
| off | Opt-in behind the variable. | None, but most of the point is lost: an author who knows to opt in can already write `.equatable()`. |
| trim | Work on the RAM first, then decide again. | More time; no promise it gets to zero. |

The RAM was put to the owner because it counts against the standing rule of
no memory-for-speed trades.

**The owner, 2026-11-02:** on by default; queue optimising what regressed
(`session/notes`, `session/log`) and the memory; rename the variable (for
example `TUI_RUN_BODY_ON_EVERY_FRAME`). No further reason was recorded beyond
choosing the recommended option as offered. The memory turned out not to be
the memo's entries at all (below).

### The study, 2026-11-01

Written against `main` at `3d605c2c4`. **[M]** measured; **[I]** inferred.
Counts don't depend on the build; allocations are from a debug build.

#### When a plain body runs

A leaf's `@State` written between frames, counted in the frame after:

| The sibling | Runs | Measure | Draw |
|---|---:|---:|---:|
| Plain, in a `VStack` or `HStack`; under `.padding`, `.frame`, `.border`, `.background`; holding `@State`, an unchanged `@Observable`, a closure, `@Environment` or an array; in a `ScrollView`, `LazyVStack` or `List` | 2 | 1 | 1 |
| Plain, in a `ZStack`, or `.overlay` content | 1 | 0 | 1 |
| Under `.fixedSize()`; a `ViewThatFits` candidate chosen | 3 | 2 | 1 |
| A `Button`'s label; a frame walked again because an `onChange` wrote state | 4 | 2 | 2 |
| `.equatable()`, or a `ForEach` row over `Equatable` elements | **0** | | |

A stack measures every child (a composite's size is its body's), then draws
it, evaluating the body again; nothing is kept between the two. With values
whose bytes aren't stable (an array built in a parent's body), each nesting
level adds a measure: three nested composites ran 2, 3 and 4 times. A static
tree of 85 composites ran **234** bodies a frame. [M] So 2 siblings × 50 ms ×
2 is 200 of the 216 ms.

#### SwiftUI's rule, measured

`Tools/SwiftUIProbes/Plain body re-evaluation/` on macOS 15.8's SwiftUI. A
write in a sibling leaf runs only the leaf; an `@Observable` property nobody
read runs nothing. A write in the parent, counting the children re-run over
four writes in a row: [M]

| The child holds | 1st | 2nd | 3rd | 4th |
|---|---:|---:|---:|---:|
| `Int`, short `String`, own `@State`, `@Environment`, same class object, `@Observable`, a `Binding`, a closure capturing nothing | · | · | · | · |
| A long `String` or array built anew, `@ViewBuilder` content | 1 | · | · | · |
| A closure capturing an unchanged `let` | 1 | 1 | · | · |
| A closure capturing the value that changed; a new class object; `AnyView` | 1 | 1 | 1 | 1 |

So SwiftUI compares fields, and looks through to what a closure captured
(or something equivalent); it does not treat every closure as changed, as
had been assumed. Why the first writes differ was not established.

#### The options

| | (a) Keep the body for the pass | (b) Memo, fields only | **(c) Two tiers** |
|---|---|---|---|
| Sibling's bodies, leaf write | 1 | 0 | **0** |
| Same, parent's write | 1 | 0 | **0** |
| Sibling holding a closure, leaf write | 1 | 2, never served | **0** |
| Same, parent's write | 1 | 2 | 2 (SwiftUI: 1, then 0) |
| The 216 ms case, inferred | ~110 ms | ~15 ms | ~15 ms |
| Contract change | None | Yes | Yes |

- **(a)** keeps the body a measure evaluated, for the draw at the same
  identity and value. It halves the count and fixes the nesting, but a
  body that sorts still sorts every frame. Built: 4 of 14,064 tests failed.
  Its sound form needs the environment compared by stamp: trusting the
  measure's environment failed 11 more tests, and stamps cost **27,926
  allocations a frame against 7,864** on the fan.
- **(b)** never serves anything holding a closure, and a `Button` in a
  composite's content is one, so it stops at the controls where most real
  pages sit.
- **(c)** asks two questions. **Not suspect** (nothing above wrote since the
  entry was stored): value fields must match, a closure or `Binding` is
  ignored, since a parent that wrote nothing had no reason to build anything
  different. **Suspect** (a parent wrote, Option C's mark): a closure counts
  as changed. Both tiers compare the environment by stamp; only the app's
  own composites are memoized. Prototype: 0 bodies for every sibling above,
  closures, `Button` labels and `List` rows included; the fan 234 → 0.
- **(d), not recommended:** a dependency graph (rejected 2026-10-24 at
  months); a "worth it" gate by subtree size (§28); docs alone (they ask an
  author to write `==` for what SwiftUI does unasked).

**Why not (a) first:** it does not close the gap (half of 200 ms is still
100 ms a key); its sound form costs what (c) costs, the stamp; and (c)
makes most of it moot. It composes with (c), so it could follow. (In the
event, the slow-body half of it landed, on by default, kept only for a body
seen to take time.)

**What building (c) found**, each failing first: a kept scope that reports
hard kills every row below (`session/notes` composed 12 rows a step, then
**99**: the memory "memos die on an ancestor write", recreated), so a kept
scope reports soft; a composite and a value memo at one identity clobbered
each other; a size kept above a windowed stack went stale (`served 6x300`,
fresh `6x600`); bitfields were missed by the field list; and the environment
must be compared on every hit (trusting it failed 7 tests and 2 selfcheck
cases).

**The cost when nothing can be saved** [M, debug]:

| One written frame | Bodies, off → (a) → (c) | Allocations, off | (a) exact | (c) |
|---|---|---:|---:|---:|
| 85-composite fan, leaf written | 234 → 85 → 0 | 8,206 | 27,926 | 3,530 |
| 16 rows, all change | 32 → 16 → 32 | 7,720 | 7,700 | 13,300 |
| Small page, parent written | 2 → 1 → 0 | 982 | 978 | 6,726 |

Suite with (c) on: 30 of 14,064 failed. 25 pinned a count or control, 4 were
the contract change itself (each mutates a plain class between frames and
expects a redraw, which SwiftUI would not do), and 1 was unexplained
(`ScrollViewIdealWidthMarkTests.steadyFrames`). Every `Stress --selfcheck`
case and session passed under both memo verifiers.

#### The decision put first

> **Should a plain view's body be allowed not to run when nothing tracked says it must?**

The study's reasoning: the owner's rule (the memory "don't copy SwiftUI
limitations") is to change only where a SwiftUI program would misbehave, and
here one does, since a body's sort costs it every key; this extends what the
owner approved for `Equatable` rows on 2026-09-26; but it reaches every app
view, not rows that opted in, so it is the owner's to rule. Opt-in would keep
the machinery and lose the point.

### Built, 2026-11-02

Steps 1 to 5. Release builds, `ab_bench.py` (CPU per frame, 10 reps,
randomised order) or the SwiftTUI comparison's `siblings` scene, on a
shared box.

| Two sibling bodies of 50 ms, a written leaf, key to screen | median | CPU |
|---|---:|---:|
| Before | 201 ms | 200 ms |
| A slow body kept for its draw (on by default) | 101 ms | 100 ms |
| The memo | 1.0 ms | 1.0 ms |
| SwiftTUI | 28 ms | |

What changed from the study, and why:

- **The stamp** is made against the pass's first environment, by what
  differs, because `EnvironmentValues` holds a bare dictionary with no parent
  to derive from. Stamps fell from 56% to 25% of `session/notes` under the
  memo.
- **The gate:** two failures running stop a composite asking for 4, 8 … 64
  passes; a serve ends it, and emptying the cache forgets the count. A
  failure is a frame's: a pass counts once, and a draw while measuring, where
  nothing is stored, is no evidence (2026-11-18, PERFCASE-F15 in
  `Historical/Performance/A declarative perf-case table.md`). It is
  not a hit rate or a subtree cost, for §28's reasons. `session/notes`, memo
  off → on, across the builds:

  | Build | CPU per frame | RAM |
  |---|---:|---:|
  | First | +374.4% | +23.4 MB |
  | Before the gate | +109.2% | +24.6 MB |
  | With the gate | +4.0% | +2.8 MB |

- **Why nothing was served in a real app:** `URLOpenerKey` held a value with
  nothing to compare by in a real app, so a real app's environment had no
  stamp, and Option C's re-check had never run outside tests either. The key
  was made neutral (`9db36ba90`).
- **`steadyFrames` explained:** a windowed stack answers its scroll view
  through a per-render mailbox that a served subtree does not write. An
  `.equatable()` around a `LazyVStack` had the same hole; a hit now says it
  again.
- **Keeping bodies for every composite** cost up to +28% (`session/notes`
  +27.9%, `session/chat` +18.1%), so only a body seen to take 20 µs is kept,
  timed in full for 8 passes and then every 16th. After that, every scenario
  was within -5% to +6%.

The memo, off → on, last A/B before default-on:

| Scenario | µs a frame | Change | RAM |
|---|---:|---:|---:|
| `fanout` | 4,255.0 → 196.9 | -95.3% | -8.4 MB |
| `kitchensink` | 424.2 → 38.9 | -90.8% | -1.5 MB |
| `modifiers` | 1,122.3 → 126.4 | -88.7% | -2.8 MB |
| `menus` | 183.0 → 33.5 | -81.6% | -0.2 MB |
| `dashboard` | 67.6 → 25.1 | -63.1% | 0 |
| `churn` | 8,372.5 → 8,442.5 | indistinguishable | -0.2 MB |
| `session/log` | 2,597.4 → 2,710.3 | +4.0% | +13.4 MB |
| `session/notes` | 5,687.2 → 6,012.2 | +5.5% | +6.6 MB |

Suite with the memo on: 25 of 14,334 failed; 22 pinned a count or control and
3 were the contract. None unexplained.

### On by default, 2026-11-02

What regressed, in the order found:

- **The memory was not the stored entries.** `vmmap` showed allocated bytes
  within 300 KB of memo off; the extra megabytes were the allocator's
  fragmentation. Interposing malloc found two causes: every environment a
  stamp was asked of was kept to the pass's end (5.6 KB each), now 32
  (`bf2c32afd`); and `AnimationStore.endLogging` shared the log's buffer
  through `Array(slice)`, 8 KB a row.

  | `session/notes` after 4 s | allocated | fragmented | footprint |
  |---|---:|---:|---:|
  | memo off | 3,501 KB | 5.5 MB | 11.8 MB |
  | memo on, before | 3,608 KB | 15.3 MB | 21.9 MB |
  | memo on, after | 3,477 KB | 9.1 MB | 15.4 MB |

- **A composite inside a value memo** was the time: a row's value already
  covers it, and each windowed sample is a new composite with no history, so
  the gate can't see failure. Now one asks only after three timed measures
  running have taken 100 µs; `tree-root` needs that, since a row that isn't
  `Equatable` is dropped by a parent's write (`ebf3b6d43`: without it,
  1.9 ms a key became 38 ms).

Not worth it, measured: a serve taking one failure off the gate rather than
all, and a size stored in consecutive passes counted as a failure. Neither
moved the counters.

### O-26. Plain data compared by its bytes, 2026-11-21

The comparison a composite's memo is keyed by took a field's `==` before it
looked at its kind, so a `Double` field compared with `==`: `-0.0` after `0.0`
was served showing `0.0`, a field holding `.nan` was drawn every frame, and a
plain struct whose `==` reads an id alone was served stale when another field
changed (bug hunt UNSAFE-4). A SwiftUI probe settled the rule
(`Documentation/SwiftUI parity/POD-COMPARE`, macOS 15.8.3, SwiftUI 6.5.4): a view
of plain data is compared by its bits, `Equatable` or not; a field of plain data
in any view by its bits; a view that is not plain data and is `Equatable` by its
`==`; `.equatable()` and `EquatableView` as equal when the bits OR `==` say so.
(SwiftUI's very first compare of a type is bitwise wherever it is, while its
layout is computed in the background, which `AG_ASYNC_LAYOUTS=0` removes; TUI
copies the steady state.)

Asked as O-26 ("compare a POD field with all bytes defined by its bytes?"), the
owner chose (a), bytes, on 2026-11-21. Built so:

- A type that is `_isPOD` and whose hash plan reads it whole — every byte
  proved defined by the rules the value hash already goes by, no padding, no
  payload enum, no step — is compared by its bytes, and its `==` is not asked
  (`ValueHashPlanBuilder.readsWhole`). Anything else keeps its `==`: a
  `String`, an array, a struct with padding, a payload enum, a reference, a type
  whose metadata the walk cannot read. Padding is never read: the owner's
  standing rule, after `Text`'s padding once made memos miss at random on Linux.
- `EquatableView` asks its lookups to compare bytes too (`comparesBytes`):
  equal when the bytes are the same, where every one is defined, or `==` says
  so, for its buffer and its size. The re-check below a parent's write does the
  same for every row type of plain data: the same bytes build the same row.
  (A key wrapper around the content did the same first, but it made the memo's
  key a different type, and with it the reader a kept scope is filed under:
  `ObservationLeaseTests.servedMemoKeepsItsScope` counted one scope fewer.)
- A `ForEach` row is still keyed by its element's `==`: SwiftUI's rule for that
  key was not measured.

Pinned by `PlainDataComparisonTests` and `ValueComparisonTests`.

### O-21. Suspects kept below an entry re-checked unchanged, 2026-11-23

Bug hunt VIEWR-4 (2026-11-20, verdict PARTLY: a recorded decision, its cost
unmeasured). A page's `@State` write marks every entry kept below the page
suspect. The walk re-checks the pane below it, finds its value and environment
unchanged, serves it, and visits nothing below. The rows in it were still
suspect at the pass's end, and the prune dropped them, so the next change
inside the pane (one row's write) drew every row: on a page owning `@State
query` above a plain-memoized `Sidebar` of 200 `ForEach` rows, 200 rows and 202
memos composed for one row's write. The decision at
`RenderCache.removeInactive()` had been to drop every suspect left at the
pass's end, since kept marked they were walked by every later drain (2.6× the
entries a clear visited on `scrollfollow`). The owner asked to explore keeping
them and to bring the A/B cost (O-21); with the cost measured at about zero, they chose to take it
(owner 2026-11-23, O-21 (b)).

**What was built.** A re-check that finds an entry unchanged notes its identity
as a verified root for the pass; one that finds it changed at any lookup in the
pass unmakes it. At the prune, a suspect strictly below a verified root, and
live as any entry must be, is unmarked and kept: an ordinary entry, which later
drains treat as any other, so the cost the old decision measured, suspects
walked by every drain, does not come back. One `RetainedSubtreeIndex` over the
roots answers it, the question the prune already asks of retained roots
(`VerifiedSubtrees`).

**Why it is sound.** Before the drain every kept entry was current. The write
reaches an entry below a verified root only through that root: a write at the
root or between it and the entry drops the root (a writer's ancestors go), so
the root could not have been re-checked. The root's value compared equal (a
plain composite's suspect comparison counts a closure or `Binding` as changed;
a row with an `==` of its own is equal when that says so), and so did its
environment, by a stamp that covers every key a render below reads. What is
below it is built from those, from the state between (unwritten) and from what
it observes (whose change reports at or below the root, which drops it). So it
would be drawn as it was. This is what serving the root's buffer, which holds
these entries' drawing, already rests on; the documented gap of an `==` that
leaves something out is the gap serving the root has, no wider. One case looks
wider and is SwiftUI's: below a row whose `==` leaves out a closure, a kept
entry keeps the closures it was drawn with, and a later write beside it, which
draws the row's body again, finds it unchanged (not suspect, so a closure does
not count) and serves it. SwiftUI runs neither the row's body nor that entry's
for a sibling's write, so it keeps the same closures.

**What is excluded, and why.**
- A second soft drain in the pass, a walk made again for what effects wrote:
  it marks afresh, and a root verified before it says nothing of what it marked
  (a writer between the root and an entry drops the root's entry, but not the
  root's place in the verified set). Every soft drain forgets the verified
  roots, so the pass keeps only what it re-checks after it.
- A member drawn away from its own identity (a `Subview` a container puts
  elsewhere) whose place is not itself below a verified root: it is drawn under
  the place's environment, which the root's re-check did not compare. It and
  what is below it are not kept; a place inside an excluded member is excluded
  in turn, to a fixed point.
- A suspect at the root's own identity: kept only if its own lookup re-checks
  it, as before.

**Measured.** Rows composed on the second frame of the page above (write the
page's query, then one row's state): 200 before, 1 after; memos composed 202
before, 3 after (the row, and the sidebar and page above the write). Pinned by
`VerifiedSubtreeKeepTests`.

**The A/B** (2026-11-23, release `Stress`, Xcode 6.2, `ab_bench.py` cpu-per-frame,
10 reps in the exclusive slot, base `b44334ac7`; the box was busy, load 3 to 13):

| scenario | base µs | kept µs | change | 95% CI | verdict |
|---|---|---|---|---|---|
| `scrollfollow` | 415.3 | 430.1 | +2.4% | −0.1% to +4.5% | indistinguishable |
| `churn` | 8580.0 | 8659.8 | +0.1% | −1.2% to +2.6% | indistinguishable |
| `session/notes` | 5431.9 | 5424.2 | −0.1% | −1.4% to +7.6% | indistinguishable |
| `kitchensink` | 12.2 | 12.1 | +0.0% | −1.6% to +0.4% | indistinguishable |
| `megalist` | 9.0 | 9.0 | +0.0% | −2.2% to +3.3% | indistinguishable |
| `session/chat` | 2057.1 | 2058.1 | −0.5% | −2.5% to +4.7% | indistinguishable |
| `table-churn` | 389.4 | 391.0 | +0.0% | −0.4% to +1.3% | indistinguishable |

Memory moved by less than 1 MB either way. `ab_counters.py` found no count moved
past 1% on the five bench scenarios: none of them writes a page's state above a
pane that is then re-checked and served, so the path does not run there and the
old cost (suspects walked by every drain) cannot come back on them. The two
sessions' counts differ by as much between two runs of the base binary as
between base and the change (their composites learn what to memoize from
measured time), so they say nothing either way; their census (`Stress --session
notes --census`, and `chat`, a debug build) keeps 0 suspects below a re-checked
entry. So on the scenarios measured the change costs nothing and buys nothing.
Of the 70 perf cases (`Stress --check-counts`) one moved, `sheet-item-switch`'s
Escape, which dismisses an item sheet over the page below it: memos composed
25 → 3, bodies run 60 → 16, measure misses 44 → 0, served 22 → 44, the same
2,440 bytes written (re-recorded). That and the page-above-pane shape the test
pins are what it buys. `TUI_VERIFY_RENDER_MEMO=1 Stress --selfcheck` passed
(214 cases, 103 sessions verified). Results:
`TUIkit-session-notes/perf/results/o21/`.
