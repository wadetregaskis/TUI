# The broad bug hunt of 2026-09-12

*A read-only bug hunt over the whole codebase on 2026-09-12: fourteen finders over disjoint territories,
two adversarial verifiers per finding, 104 agents in all. What it found, what was fixed, and what it
taught about the method. [The full log](<../../Reviews/Review batch, 2026-09-12, broad bug hunt.md>)
stays in place as the per-finding record: site, mechanism, failing input, reach, test gap, proposed fix
and each verifier's correction. Ids: none.*

## In short

Forty-five findings came back, fifteen of them rated high. Forty-one survived both verifiers, four
were contested (one verifier killed the finding, the other did not) and none was killed by both. The
backlog was written down the same afternoon (`de29648d3`), every item was re-derived by hand from the
code before anything was changed, and the fixes landed over 2026-09-12 and 13 in at least 47 commits
that cite an entry. Forty-three were fixed in the batch, one of them (#45) partly. One (#32) was
addressed five weeks later by a wider change; one contested finding (#42) has no fix, because a
verifier showed by running it that the bug does not happen.

## The problem

The 2026-09-09 deep dives ([their log](<../../Reviews/Review batch, 2026-09-09, three deep dives.md>))
had gone deep on three areas. This hunt went wide instead. Each of the fourteen finders took one
territory and read only that:

- **recent-fixes**: the last thirty commits, looking for sites a recent sweep or fix had missed;
- **framebuffer**: overlays, punching, clipping, compositing;
- **text-width**: measurement, the width tables, ANSI slicing;
- **layout-stacks**: stacks, measure/render parity, `Grid`;
- **scrolling**: `ScrollView`, windows, anchoring, scroll bars;
- **list-table**: `List` and `Table`, the twins;
- **focus-keyboard**: the focus system and key dispatch;
- **mouse-drag**: mouse dispatch, hit testing, drag and drop;
- **animation**: transitions, animated runs, the clocks;
- **colour-opacity**: colour, opacity, palettes, themes;
- **images**: decoding, resampling, dithering, graphics protocols;
- **runloop-terminal**: the render loop, the host, the diff writer, signals;
- **state-identity**: state, environment, identity, the render and measure memos;
- **presentation**: modals, overlays, menus, navigation, status chrome.

Every finding then went to two verifiers who had not seen each other's work, each told to *refute* it
through a different lens. One attacked the mechanism from the code. The other attacked the claim that
the defect is reachable through public API, untested, and not already a recorded decision.

## How it unfolded

1. **The hunt and the verification**, in one session, read-only throughout.
2. **The backlog written down before it evaporated** (`de29648d3`). The uncondensed dossiers were
   session-local; each entry was condensed to what is needed to re-derive it, and every verifier's
   correction was quoted, since that is where the second pass earned its place.
3. **The fixes**, one commit per finding or per half of one, each citing its entry and most stating
   which verifier corrections they followed. Several fixes followed a verifier who narrowed the
   proposed fix (#2, #3, #30) or widened the reach (#13, #24, #25).

## What was found

The high-severity findings, by territory:

- **recent-fixes.** #1: a `.mono` image handed a faded palette's ink and paper straight to the ANSI
  emitter, the seventh site the faded-palette sweep (§68 of
  [Opacity as composition](<../../Colour and styling/Opacity as composition.md>)) had missed.
- **framebuffer.** #2: opacity resolution trapped (index out of range, in release too) on a run a
  leading-edge cut had left at a negative offset. #3: a layer cut at its leading edge kept its runs at
  negative offsets, and a later positive shift landed them on rows that were not the layer's.
- **layout-stacks.** #4: a column holding a `Spacer` painted the full offered width while measuring as
  its widest child.
- **scrolling.** #5: a control revealed by focus under an overscroll push was drawn off-screen. #6:
  hit regions pushed out by overscroll still took clicks outside the viewport.
- **list-table.** #7: a footer that wrapped ate the list's last row. #9: a titled `.plain` List mapped
  every click one row too high.
- **focus-keyboard.** #8: a pushed screen's own `.onKeyPress(.escape)` did not run, because the stack
  registered its pop first (a verifier noted "can never fire" overstated it).
- **colour-opacity.** #10: every colour effect was a no-op on displaced (offset) content.
- **runloop-terminal.** #11: a status-bar height change (a tooltip coming or going) left a stale row,
  because the diff was invalidated on the bar's presence only. #12: an app-header spinner froze as soon
  as the page also animated on the same clock.
- **state-identity.** #13: two sibling `ForEach` loops one level down landed on one identity, and the
  row memo drew the first loop twice. #14: an `if`/`else` that was a container's only child shared
  `@State` across its branches.
- **presentation.** #15: a presentation nested in another reset focus every frame, and the run loop
  never idled.

Among the medium and low ones: a sixteen-codepoint hole in the East-Asian-Wide table (#19); wrap memos
that survived a host switch (#20); gaps charged for zero-extent children in stacks and lazy stacks
(#21, #22); a squeezed `Grid` measured against the wrong width (#23); two ScrollView indicator-line
miscounts (#24, #25); zebra stripes counted from the first visible row (#27); a focus probe that left
key handlers, shortcuts and status-bar items live (#28); a hue wrapped only once (#34); transparent
pixels counted as black by the adaptive palette and the Otsu threshold (#35, #36); `lighter(by:)` and
`darker(by:)` dropping alpha (#41); and a VT key number parsed with a signed `Int(_:)` forty lines below
the parser written to close that hole (#40).

## What changed

| # | Fixed in | # | Fixed in |
|---|---|---|---|
| 1 | `82d1cf4b6` | 24 | `1f696f5e2` |
| 2 | `2c9114a0d` | 25 | `d6a86a93a` |
| 3 | `0662f22c7` | 26 | `60dbcd6f1` |
| 4 | `e6331bfa1` | 27 | `167d4a0bd` |
| 5 | `bb3a9fd98`, `7ba77e269` | 28 | `8d508a9a6` |
| 6 | `625668aaa` | 29 | `7080ea4dc` |
| 7 | `2b1c85744` | 30 | `8e912b407` |
| 8 | `b807b48c6` | 31 | `5dfbe3ee2` (with #12: one mechanism, found twice) |
| 9 | `f590dba62` | 32 | `460568666` (2026-10-19; does not cite the entry) |
| 10 | `de94d4e0a` | 33 | `7e7fd3f6d` |
| 11 | `664c628bf` | 34 | `f90eabb43` |
| 12 | `5dfbe3ee2` | 35 | `670873c8f` |
| 13 | `6c851e022`; a remaining case in `8c6f988c7` | 36 | `fa0d456fc` |
| 14 | `86b6416e0` | 37 | `a8c225f6a` |
| 15 | `d76f8f9a5` | 38 | `7e3cf7a0f` |
| 16 | `480bf939e`, `a59abbd57`, `e61c990a5` | 39 | `3b75d8dc0` |
| 17 | `cd3dc9479` | 40 | `f4146d8de` |
| 18 | `0cb03c969` | 41 | `808bc4f36`, `e6360d547` |
| 19 | `d23bc8ab6` | 42 | none (see below) |
| 20 | `b8cb8c0af` | 43 | `e5213890a` |
| 21 | `7a13dd0b8`, `9c9472b15` | 44 | `fa3e3b63d` |
| 22 | `9c9472b15` | 45 | `29a5aebaf` (partly; see below) |
| 23 | `2fb352cc1` | | |

`0d6c31100` (2026-09-14) followed #16: the List row's claims expression had grown too hard for Swift
6.2 to type-check.

## Where it stands

- **#42, contested, not fixed.** The finder said `sanitizedForTerminal` slices a String with scalar
  indices and so leaks an escape's terminator byte when an orphaned `Extend` scalar follows. One
  verifier ran it on Swift 6.3.3 and showed no leak: the String range subscript has been scalar-aligned
  since Swift 5.7. The other confirmed by reading only. No commit cites the entry and the three
  `self[runStart..<index]` sites are unchanged.
- **#43, contested, fixed.** One verifier refuted it as a duplicate: the same hole was finding 31 of
  [the semantic audit of August 2026](<../SwiftUI parity process/The semantic audit of August 2026.md>),
  still open. It was fixed here (`e5213890a`), and the fix found that forwarding hover, as the audit had
  recommended, was not enough.
- **#44, contested, fixed.** One verifier refuted it as a recorded, remedy-declined hole. The other
  widened it: `ForEach` wraps every `Equatable` row in a memo, so no `.equatable()` opt-in was needed to
  hit it. The fix (`fa3e3b63d`) says the earlier record's "never hit because it is opt-in" had
  overlooked that.
- **#45, contested, partly fixed.** `29a5aebaf` stops a mono image papering over its transparent
  surround, and says what it left: a cell only partly covered keeps its paper whole, so a logo's edge
  can carry up to half a cell of it. Whether that was done later is not recorded.
- **#32** played no removal transition inside `if`/`else`; no commit of the batch fixed it, and the
  default-transition work of `460568666` (2026-10-19) made a flipped branch play its removal.

## For a future reader

- **A verifier told to refute still mostly confirms.** 41 of 45 survived both, the same suspiciously
  high rate as the 2026-09-09 dive. Read "confirmed" as "worth an hour", never as "true", and re-derive
  by hand before changing anything. The verifiers' value was in their corrections: wrong lines, wrong
  first trap, triggers wider or narrower than claimed, a proposed fix that would not have fixed it
  (#12), a refutation by actually running the code (#42).
- **The one refutation that ran the code was the one that held.** Reading-only confirmation of a claim
  about standard-library behaviour is weak.
- **Sweeps miss sites.** #1 was the seventh site the faded-palette sweep missed; #16 was a sibling drop
  site the §69.4 fix did not cover; #17 was a new assertion that tripped on a legitimate case; #40 sat
  forty lines from the fix for its own class. When a class is fixed, grep for every site.
- **Measure/render parity** recurred (#4, #7, #21, #22, #23, #24, #26): a view that measures one size
  and draws another. So did **leading-edge cuts** leaving payloads at negative offsets (#2, #3, #18) and
  **memos keyed on less than they read** (#13, #20, #44).
- **Tests that never arm their assertion.** Many test gaps were a suite for the exact function that
  rendered with an opaque palette, no selection, or the safe arrangement, so the failing path never
  ran.
- **A finding can already be on the books.** Check the dated audits and decisions first (#43, #44);
  a recorded excuse can also be stale.
