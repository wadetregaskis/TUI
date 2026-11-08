# The three deep dives of 2026-09-09: bugs, documentation and performance

*A bug hunt, a documentation audit and a performance pass, run on one day as twelve-lens fan-outs whose
every finding a second agent tried to refute; then a drain the same day that fixed or decided all of it.
This is the story; [the full log](<../../Reviews/Review batch, 2026-09-09, three deep dives.md>) stays in
place as the verified per-item record. Ids: none (the D- and P-numbers below are the log's own item labels,
not decision ids).*

## In short

Three reviews of the whole codebase confirmed **35 defects** (two more were raised and knocked down),
**64 documentation inaccuracies** and **23 optimisations worth measuring** out of 42 proposed. A first
pass that night fixed ten defects, the DocC link rot (with a `--strict` check so it stays fixed) and
measured three optimisations; the backlog was written down (`e993d14a6`) so it would outlive the session.
A second pass later on 9 September drained the rest in 87 commits: every defect fixed, every inaccuracy
corrected, and every performance candidate either measured or declined with a reason. Eleven
optimisations landed, three were measured and reverted, four were declined.

The part worth keeping is what the drain's own re-derivation caught: all 25 open defects survived a second
refutation, but **six of the proposed fixes did not**, and two of those would have shipped a new bug.

## The problem

Each dive split the codebase by **lens** rather than by file, twelve to a dive:

- **Bugs**: the log does not name these lenses; its defects span focus, scrolling, lists and tables,
  layout, rendering and overlays, images, storage and input.
- **Documentation**: design records, DocC references, docs against code (core, focus and app, rendering,
  styling and images, views), parameter docs, test docs, and undocumented public API.
- **Performance**: per-cell rendering, measure and layout, environment and context, caches and memos,
  lists/tables/scrolling, the image pixel path, idle wakes, allocation and ARC, first frame and startup.

Every finding a lens produced went to a second agent told to **refute** it, with the code at hand. Only
what survived was kept: a defect with a concrete failing input, a sentence with the line that contradicts
it, an optimisation that passed four screening questions (among them: has it been tried, is it really
hot, what does it risk) and carried a pre-registered prediction and measurement plan. Of the 42
optimisations proposed, 19 fell at screening: 13 not hot, 4 too risky for the gain, 2 already tried and
reverted.

## How it unfolded

1. **The first pass (the night of 8 to 9 September).** It opened on two bugs already in hand: an adaptive
   palette that asked for five colours and drew four (`4f0bf6ca1`) and a blank line at the bottom of a
   table (`44896b702`). Then ten of the confirmed defects, among them a default-focus winner decided by the
   hash seed (`69e43b053`), a preference scope that discarded its parent's contributions on close
   (`320b5e7b7`), a five-button mouse's Back button read as a left click (`239e0d6b5`), an unsynchronised
   storage-failure handler (`f9468e4bc`), a column line limit below 1 meaning unlimited (`ef9cfb735`), three
   places where the reserved and drawn indicator lines disagreed (`054154b66`), and a Spinner frozen in the
   app header (`03d0a5577`). On the docs side, 435 DocC diagnostics with the check that keeps them out
   (`60b845dd4`, covering the log's 82 broken references) and the front-door counts (`3405823a0`). Three
   optimisations were measured: the Otsu threshold every picture paid for and only mono read, −13.6% on
   the pixel path (`7deef49d6`); the row-shortcut chord table rebuilt every pass, −2.8% on `tables-vstack`
   (`9aaf254eb`); and the settled fast path generalised to three more call sites, a wash, reverted
   (`746bcdc7f`). The backlog went into the log (`e993d14a6`).
2. **The drain (later on 9 September).** Each open item went to a fresh agent to prove again from the code
   at HEAD, and then to another told to refute **both the finding and the proposed fix**. Fixes landed one
   per commit; eighteen performance candidates were staged as patches, and each was either A/B-measured
   against its prediction or declined with a reason.
3. **What the re-derivation caught.** All 25 defects held. Six fixes did not:
   - **`ViewThatFits`** (`199dd1474`). The proposed detector for a greedy candidate missed a `Table` with a
     `.ratio(_:)` column, which reports a fraction of the probe. The landed version compares two probes one
     cell apart, sound for every greedy shape. Running it also falsified the review's claim that a bare
     `Slider` names a real minimum (its body is an `HStack`), so that deviation is pinned by a test.
   - **The stack gap** (`ad1b7b255`). The proposed fix would have under-reported: `Text("")` renders one
     line of pure escape bytes, so it took the contributing branch while the new measure called it empty.
     Behind it sat a stranger bug: that row's drawn width depended on colour depth, 6 cells in colour and
     4 with `--no-color`.
   - **Greyscale dithering** (`5d17a2fba`, `5631fde3d`). Refuted for its placement: putting the ramp
     posterisation in the shared quantiser would have banded the glyph path twice, and since the ramp
     entries are not fixed points of the bands, a dithered highlight would have come out a step dark,
     silently, because nothing tested `.grayscale` with dithering.
   - **`@AppStorage`** (`3b4d779f3`) kept its mechanism but not its cost story: the claim that it costs
     what an `@Observable` mutation already costs was false, and it is the framework's first per-user-action
     full cache clear.
   - **D12** was replaced by the two-line grounding idiom the codebase already used, and **D20** and
     **D21** had their test plans rewritten, because the planned tests could not fail.
4. **What the drain turned up on the side.** Four findings came from fixing something else (see below).
5. **P13, later.** Re-derived on its own, it had drifted twice: the staged patch would have silently
   reverted the greyscale fix, and its plan named two `ImageHarness` modes that do not exist. Its first
   commit landed, the glyph renderer's per-cell lock, **ansi256 −18.3%** (`4f1d89ea9`); its second measured
   as a wash, as its own prediction had bet, and was reverted (`9fe39597d`). §57 of the
   [August performance profile](<../../Performance/Full performance profile of Stress and the Example (2026-08).md>)
   has both tables.

## What changed

Counts: 35 defects fixed (10 in the first pass, 25 in the drain), 64 documentation inaccuracies corrected.
Optimisations: 14 landed (11 in the drain, 2 in the first pass, P13's first commit), 5 measured and reverted
(3 in the drain, 1 in the first pass, P13's second), 4 declined.

Notable defects, all fixed:

| Defect | Fix |
|---|---|
| A multi-line list's bottom walk measured its shortfall against a rejected top, hiding the last line | `89d9dcb46` |
| The reveal of a row taller than the budget always showed its tail, row 0 included | `10144c987` |
| Dismissing a modal restored focus without validating it: an unpaired `onFocusLost` | `fa3c35459` |
| Status-bar clicks were routed by the previous frame's header height | `08de388e5` |
| A clipped List row told the control inside it the wrong line was clicked | `14776eb99` |
| A Table's sort order could only be changed with a mouse | `027812083` |
| `ViewThatFits` with a `Spacer` never fit; and it measured one candidate and drew another | `199dd1474`, `8a7e474f2` |
| A `Divider` inside `AnyLayout`'s stacks took its axis from the enclosing stack | `adaa73100` |
| A fade wider than a ScrollView reached the sibling beside it; two fades on one row, one frozen | `4c9015852`, `e8379ca9c` |
| `renderOnce` never composited layers or fades, so `.opacity` and popovers did nothing there | `2cb54f4a0` |
| A bumped measure generation the value memo's size key could not see | `2af79219d` |
| Quitting with a text field focused threw away what was typed in it | `7ac47bf28` |

Optimisations that landed in the drain, by the log's measurements (its intervals in brackets):

| Commit | Change | Scenario and result |
|---|---|---|
| `bff6f47eb` | Table cells padded without three throwaway strings | `tables-scroll` −7.6% [−8.3, −6.7] |
| `0f2db8f23` | A multi-line row wrapped once, not twice | `table-multiline` −8.7% [−10.0, −8.2] |
| `7db94fe97` | Two cache keys shed the identity chain | `fanout` / `modifiers` / `anyview` ≈ −6.3% |
| `5e2392982` | Environment writes stop re-deriving two fixed services | `deep` −5.1%, `menus` −5.3%, 1.7 MB off `deep` |
| `9348de75e` | Unsharp mask walks rows, not columns | image pixel path −19.8% (sharpened) |
| `5d9e7006f` | Resampler computes column geometry once | −16.5% ansi256, −23.5% truecolor |
| `21be67433`, `3b935ee5f` | Blend and SGR parsing without strings or growing arrays | `translucent` −3.5%, −3.6% |
| `fa71351df` | The measure memo's gate off the environment dictionary | `menus` −2.6%, `fanout` −2.4% |
| `097a0c2d8` | A ramp fill memoises its background escape | `gradients` −1.4%, as predicted |
| `288d33ce2` | Two stacks build guide sizes only when asked | `modifiers` −1.3%, `fanout` −0.9% |

Reverted after measuring: **P06**, `RenderContext`'s depth as a packed `UInt16` (`anyview` +3.0%,
`modifiers` +1.6%, both intervals clear of zero); **P20**, static `childViews` requirements (warm `deep`
+1.6% to buy a cold `fanout` −1.8%, a steady-state cost for one first frame); **P04**, one slot array per
HStack row (a wash, `menus` +0.8%).

## Where it stands

Declined without measuring, with reasons: **P02** and **P09**, whose hotness the refutation knocked down
(below what the harness resolves); **P16**, whose own prediction was "the wash of the batch"; **P08**,
superseded by `fa71351df`. The nineteen candidates rejected at screening are listed in the log with their
reasons, so they are not proposed again.

One fix was listed too early. Carrying the header's overlay layer through its rebuild (`03d0a5577`) was a
prerequisite, not the fix: the header buffer went straight to the terminal and was never composited, so a
`Menu` in `.appHeader` still drew nothing. The real fix moved header-anchored layers onto the content
buffer (`260b976a1`, 2026-09-20).

Four things the drain found, recorded rather than fixed in it:

- **The resting-offset snap** in `ItemListHandler+Resting.swift` pushes an offset of 1 back to 0 under
  text indicators, on the premise that offset 0 shows strictly more; false when that row is itself
  clipped. It is why `663d98cc4` reaches the tail on the scrollbar arm and not the text one.
- **`DragAndDropSession` reads `hasContentBelow` through the protocol existential**, which happens to give
  a drag the extent it wants. Promoting that member to a protocol requirement would silently change it;
  `ee2cc94a4` writes the split down at both declarations.
- **Three copies of the same content-row question** (`contentY(in:)`, `_ListCore.dragContentY`, and
  `Table`'s): `c9ae127fa` fixed the one that had drifted; consolidating needs a shared type.
- **`StderrSuppressionTests`' concurrency case** failed once under a filtered run and passed alone and in
  the full suite. `8d6993f1f` made the test observe fd 2 under the lock it tests; the log does not say
  whether that closed the race, and treats the suite's silence as untrusted until a seeded order
  reproduces it.

## For a future reader

- **Refute the fix, not only the finding.** The verifier confirmed 35 of 37 defects, so the findings were
  sound; it was a quarter of the proposed *fixes* (six of 25) that were wrong, and two would have shipped a
  bug. A counterexample to a fix is cheap to find before it lands and expensive after.
- **Predictions are wrong in both directions.** `bff6f47eb` beat its prediction by a factor of two; P06 and
  P20 were predicted wins and measured as regressions. The ratio this batch produced, 11 wins to 3 reverts
  to 4 declines, is the ratio to expect, which is why nothing lands without its measurement.
- **Screening halves the list.** 23 of 42 candidates survived the four questions; "not hot" was the
  commonest reason, usually a multiplier off by orders of magnitude or a cost an existing memo already
  absorbed.
- **Placement is part of a fix.** The greyscale change was right in substance and wrong in the shared
  quantiser. Ask who else calls the code a fix moves into.
- **A test plan that cannot fail is not a test plan** (D20, D21): run the test against the unfixed code.
- **Check the feature end to end, not the step.** The header overlay was marked fixed on a prerequisite.
- **Write the backlog down before the session ends.** The first pass left 25 of its 35 defects open;
  `e993d14a6` is what let the drain pick them up.
