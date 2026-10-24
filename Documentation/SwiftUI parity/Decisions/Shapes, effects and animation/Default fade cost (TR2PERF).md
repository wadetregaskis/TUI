# The default fade's cost: decisions from lane TR2PERF

*Lane TR2PERF, 2026-10-19. Lane TRANSITIONS2 made the branch an `if`/`else`
takes and leaves, a `switch`'s case and a `ForEach`'s row fade in and out with
no `.transition` written, as SwiftUI's do (decisions
[B-TRANSITIONS2-1](<Transition follow-ups (TRANSITIONS2).md#b-transitions2-1-a-branch-a-case-and-a-row-fade-in-where-a-container-remembers-its-children>)).
The owner's rule for the default transition (2026-10-14) was "prototype B
(fade both ways) + A/B, fall back to C (fade-in only) if significant cost esp.
with no animation". This lane measured what B cost with nothing animating,
tried the cheaper form of B the TRANSITIONS2 lane had priced, and took the
fallback. Nothing here needs a decision; the calls are written in the main
decisions file's format:*

- **B-TR2PERF-n — shipped the safe option.** Says what the fuller version
  would be, and its price.

## B. Shipped the safe option

### B-TR2PERF-1. A branch, a case and a row fade in, and go at once

*`ChildFade`, `BranchTransition`, `PlacementStore.Record`, `ConditionalRecord`;
Deliberate deviations A10*

**What B cost with nothing animating.** The coordinator's release A/B of
`Stress`, W1B against W1B + TRANSITIONS2 (2026-10-19; 32/32 frame checksums
the same; box at load 11). Almost none of its scenarios animate, so this is
B's price with nothing animating: `tables-scroll` +7.2% (CI +2.1..+10.6), `churn`
+3.5%, `menus` +3.4%, `kitchensink` +2.9%, `table-churn` +2.9%, `deep` +2.7%
with its footprint 17.1 → 32.6 MB, `fanout` +2.6% (+3.7 MB), `textwall`
+2.0%, `tables-vstack` +2.0%, `keyrows` +1.9%, `framedcolumns` +1.3%, and 16
indistinguishable.

**Where the time went** (Time Profiler, 10 s a scenario,
`perf/profile1017.sh`; release builds inline differently, so these are the
frames TRANSITIONS2 added or grew, as inclusive shares of each trace):

| Scenario | W1B | TRANSITIONS2 | What it is |
|---|---|---|---|
| `tables-scroll` | `glidingPlacements` 0.4% | 2.5%; malloc 12.3 → 14.1% | the root column freeing last frame's pictures, mostly the scroll view's viewport; buffers living a frame longer |
| `churn` | `glidingPlacements` 2.8% | `glidingStackBuffer` 5.9% | 300 rows of four, each row's stack keeping its members' pictures; freeing `FrameBuffer`s 1.4 → 2.5% |
| `menus` | 0.4% | 1.7% | the stacks' stored pictures |
| `deep` | `recordConditionalBranch` 1.3% | `ConditionalView.present` 2.7%, `glidingStackBuffer` 2.6% | every level's conditional and column keeping what the levels below drew |
| `kitchensink` | 0.2% | 0.9% | the stacks' stored pictures |

The pictures, then, and not only the stored array. Kept from one frame to the
next, they cost a release each frame, frees that happen a frame late, a
heap that holds two frames of buffers instead of one, and the footprint
(`Stress --bench`, `footprint-peak`: `deep` 16.7 → 45.7 MB, `fanout` 26.4 →
32.4 MB at 120×40).

**The middle way, measured.** B-TRANSITIONS2-1 priced a middle way at about
half a day: keep pictures only for the children that can go, which are a
`ForEach`'s rows, a branch, a case and an `if`'s views, and not for a tuple's
plain members. A prototype did that (a child kept its picture if it had a key,
a resolved identity, a default transition or a departing slot; a container
none of whose children could go stored nothing). It was not committed. Its
profile against the two above:

| Scenario | Middle way | Still kept |
|---|---|---|
| `tables-scroll` | `glidingStackBuffer` 1.5% | the rows of the column inside the scroll view |
| `churn` | 4.8% | the column's 300 rows, drawn afresh each frame |
| `menus` | 1.0% | the menus' rows |
| `deep` | `ConditionalView.present` 2.5% | every level's branch: a nested page is branches |
| `kitchensink` | 0.5% | |

Footprint: `deep` 37.3 MB, `fanout` 32.1 MB. What the middle way keeps is by
definition what can go, and in these scenarios that is rows and branches, so
it couldn't get `churn` or `deep` to about 1%. The owner's fallback applies.

**What shipped: C, fade-in only.** A branch, a case or a row that a change
puts in under an animation fades in where it lands, as before. One the change
takes out goes at once, as before TRANSITIONS2, unless it carries a
transition of its own: that removal still plays where it was, from what the
view left in the `DepartureStore` (TRANSITIONS2's own-removal, under the
change's animation or one the transition names). A conditional drawn whole
does the same at its origin. Nothing keeps a picture any more:
`PlacementStore.Record` has no `pictures`, and `ConditionalRecord` is eight
bytes, a pass and four flags, where it held a `FrameBuffer` and a leaving
branch's (`ConditionalRecordTests`).

A settled container does what it did before TRANSITIONS2: it looks its record
up, as FB16's glides need, and writes nothing. An empty eager stack or
`Layout` still looks its record up each frame. That keeps the record alive
for a row arriving in it to fade in, and lets a last row with a transition of
its own play its removal; it is one dictionary probe per empty container, and
it was not hot in any profile.

Kept from TRANSITIONS2: each half of an asymmetric transition's own animation,
`.animation(nil)`, a transition's own removal played by the stack, B-O4-1 (a
matched view leaving is carried with the one arriving, for a removal that
plays: an `if`'s view, or one with a transition of its own), B-O4-2, and the
stale-record fix.

What changes for an app: the branch an `if`/`else` leaves, a `switch`'s case,
a `ForEach`'s row and the views of an `if` holding several now vanish on the
frame of an animated change, where SwiftUI's fade out. The views around them
glide into the room as before. A hero written as `if`/`else` with
`matchedGeometryEffect` draws the arriving view carried from where the one
leaving was, but not the one leaving, unless that one is given
`.transition(.opacity)`, which is SwiftUI's default written out.

**Measured on C** (the same profiles; footprints from `Stress --bench` at
120×40, warm at 300 frames, the ranges over three runs on a busy box):

| Scenario | W1B | TRANSITIONS2 | C |
|---|---|---|---|
| `tables-scroll` | 0.4% | 2.5%, malloc 14.1% | 0.9%, malloc 12.6% |
| `churn` | 2.8% | 5.9% | 3.9% |
| `menus` | 0.4% | 1.7% | 0.7% |
| `deep`, the conditional | 1.3% | 2.7% | 1.0% |
| `deep`, the columns | 0.4% | 2.6% | 0.4% |
| `kitchensink` | 0.2% | 0.9% | 0.4% |
| `deep` warm, footprint-peak | 16.7 MB | 46.3 MB | 16.7 MB |
| `deep` warm, rss-peak | 24.7 MB | 57.8 MB | 24.8 MB |
| `fanout` warm, footprint-peak | 24.9–27.2 MB | 33.5–34.0 MB | 29.8–30.8 MB |

The cold footprints the A/B reported growing (`kitchensink` 72.8 → 124.5 MB,
`deep`, `dashboard`) varied by more between runs of one binary than between
the three binaries here: `kitchensink`'s cold rss-peak was 104–136 MB for
each. `churn`'s column check is still about a point above W1B's, in copies
of each child's `FrameBuffer` and `ChildView` that W1B's build had inlined
away. Frame checksums: the same as TRANSITIONS2's in all 33
scenarios, `session/glides` and `animating` included.

**The A/B owed:** this branch against W1B and TRANSITIONS2 on `tables-scroll`,
`churn`, `menus`, `kitchensink`, `deep` and `fanout`, cold and warm, with the
footprint beside the time.

**The fuller version: B, fade both ways.** That's TRANSITIONS2 as shipped,
whose price is above. A design that fades out with no memory kept from frame
to frame would need the picture from somewhere else: the render cache already
holds a memoised row's last buffer, so a row the cache served could fade out
from that at no cost to frames where nothing changes, while a row drawn
afresh, or a branch, would still go at once. That's untried; I'd guess about
a day, and it covers memoised rows only.

### B-TR2PERF-2. An `if`'s view keeps its fade-out

*`DefaultTransition`, `OptionalPresence`; Deliberate deviations A10*

Fade-in only (B-TR2PERF-1) applies to what lane TRANSITIONS2 added: a branch,
a case, a row, and a conditional drawn whole. An `if`'s view fades out as well
as in, as it has since 2026-10-14. That was B for the `if`, finished after its
own A/B (2026-10-14, "B2": warm `keyrows` +1.7%, `menus` +1.2%; cold `menus`
+3.4%; the rest indistinguishable), and fade-in only was found no cheaper
there: an `if` needs a record either way, to tell an arrival from a first
sight. Its `if` keeps what the view drew on its last frame, one picture per
`if`, in the record it writes every frame anyway, now in one access (lane
TRANSITIONS2). That cost is in both binaries of the A/B in B-TR2PERF-1, so
that A/B doesn't price it.

So `if a { X }` fades `X` out, and `if a { X } else { Y }` lets `X` go at once.
In a stack, an `if` whose content is several views, a `Group` (with a modifier
on it or not) or an `if`/`else` of its own lets them go at once too: those are
the stack's children, not the `if`'s. So does the view of an `if` with `.id`
written on it. Each fades in, as a row does; TRANSITIONS2's stack faded each
out from the picture it kept (`BranchAndRowFadeTests`, the handed-over
shapes; `TransitionRemovalAddressTests`). Rendered directly, as a view's whole
`body` or a modifier's content, an `if` holds whatever it holds and fades it
out.

**The fuller version:** one rule for every default. Fading in only here too
would drop the `if`'s picture, and an `if`'s view with no transition would go
at once: about half a day, with the tests of the `if`'s fade-out
(`DefaultTransitionTests`, `TransitionTests`, the Example's
`AnimationPageShowHideTests`) changing, and an A/B to say what the picture per
`if` costs. Not done: one picture per `if` is a cost of a different order from
one per child of every container, it passed its own A/B, and the fade-out of
an `if`'s view is the one people see most.
