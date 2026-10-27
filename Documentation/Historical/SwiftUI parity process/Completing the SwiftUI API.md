# Completing the SwiftUI API

*How the work to close every gap `Tools/APIParity` reported was run: the work
log of August and September, the decisions process (an owner's document of
A, B and C entries, then a file per lane), the parked questions, and the
reorganisation of the documentation that followed. The live plan is
[SwiftUI API completion plan](<../../SwiftUI parity/SwiftUI API completion plan.md>).*

## In short

From 2026-10-03 the gaps (2,022) were worked in waves; every point where the
call was the owner's, or where a call was made the owner might revisit, went
into one decisions document, then into a decisions file per lane, each entry
in three parts: A (needs a decision), B (shipped the safe option, with the
fuller version priced), C (declined). The owner answered them in batches
(2026-10-04, 10-12, 10-23 to 26). From 2026-10-26 those records were
dissolved into the stories of this folder, by subject. What follows: the
decisions document as it last stood (its remaining entries are in the
stories), the work log, the questions once parked, and the reorganisation's
own decisions.



## The decisions document, as it last stood

*The companion to [`SwiftUI API completion plan.md`](<../../SwiftUI parity/SwiftUI API completion plan.md>).
That file is the plan. This one collects every point the work reached where the
call was the owner's, or where I made a call that the owner may want to revisit.
It is written to be read once, at the end of the straightforward work.*

Three parts:

- **A. Needs your decision.** Nothing has shipped for these. Each entry gives
  the options, what each costs, and my recommendation.
- **B. Shipped the safe option.** A basic, honest form is in. Each entry says
  what the fuller version or the alternative reading would be, and what it
  would cost.
- **C. Declined without asking.** Gaps I recorded in `parity-map.json` as not
  implementable, because the reason seemed unarguable. Listed so they can be
  vetoed.

Each entry names the SwiftUI symbols it covers, so `api_parity.py` output can be
traced back to it.

Ideas that were measured or designed and then deliberately not taken, here or in
the lane files, are in [`Future options.md`](<../../Future options.md>), each with what
would make it worth revisiting.

### Start here: the questions in one list

Every gap `api_parity.py` still reports names one of these entries, and
nothing else is waiting. The batch closed the rest: 2,022 gaps when it started
and 404 when it ended (the count rose from 392 at the end, when 14
drag-session modifiers a wrong refusal had hidden became gaps under A53); 232
on 2026-10-12, and 90 on 2026-10-19 (94 on 2026-10-23, when C11's four `Tab` forms left the map for the baseline) (93 on 2026-10-24, when B96 closed `tabBarMinimizeBehavior(_:)`; 84 before C11's four shipped and 80 after) (`Tools/APIParity/baseline.json`), plus
three overloads only CI's SDK lists. Besides the gaps, the refusal review's
implementable P items have shipped, and so has Wave 11b, underline and
strikethrough patterns and colours, which you read on real terminals on
2026-10-18.

**How your answers are recorded.** Your review of 2026-10-04 (A1–A54,
B1–B37), my answers to its questions of 2026-10-05 (which you answered
"Proceed", so their proposals count as approved) and your rulings of
2026-10-12 are folded into the entries, each dated. An entry whose work has
landed is removed, and no entry is renumbered. **Lane owed** marks an entry
that is decided and waits only on its implementation.

**Still yours to answer.** None of the A entries: A27 (pixel effects) and A48
(swipe actions) were answered on 2026-10-26, A27 with option 2 and A48 with
its recommendation, and are lanes owed. A34 (the blur transition) was answered on
2026-10-23 with its option 2 and has shipped (lane VISUALS, decisions
`Historical/Shapes, effects and animation/`, by id).

**Decided, waiting on a measurement.** A16's colour provider waits on an A/B on
the quiet machine. A40's default dissolve was measured on 2026-10-15 and, as
agreed, not shipped: it cost far more than 1% (see A40).

**Decided, lane owed.** A0's ruled O items but O1, O2, O7, O17 and O16 (deferred), and with them
A22 and A26 (O9) and A24 (O0, O15); A42, B19 (after its A/B). B22's look at
the faint tiers was taken on 2026-10-19 (lane EFFECTS): the faintest vanish at
16 and 256 colours, and what to do is A-EFFECTS-1, in
[Blend modes and image details (EFFECTS)](<../Shapes, effects and animation/Pixel effects: transforms, masks, drawingGroup, blend modes and meshes.md>).
B3's lane shipped on 2026-10-13 with most of A21; A21 lists what is left.
Shipped on 2026-10-14 (their entries removed): A25; O7 with A12; O1; O17; O2 with A37.
Shipped on 2026-10-18: O0's shapes (lane W1); O3's merging and additive
retargets with A38; O5's materials with A41, and its glass; O6's shadows;
O13's menu bar; O4 with A23 and A36.
Shipped on 2026-10-19: O8's refusals, with A11 and A51.

**Deferred.** A3, and B8's mirroring, with right-to-left (B1); A50 and A53
until macOS 26 or 27 can be measured.

**Waiting on another answer.** None: A39 was answered with A27 (declined,
2026-10-26).

---

### A. Needs your decision

### B. Shipped the safe option

### C. Declined without asking

## The work log (2026-08 to 2026-09)

*A running record of what I am doing, what I decided and why, and what I would
like a second opinion on. Newest at the bottom. Questions are marked **Q** —
none of them block me; each says what I did in the meantime.*

### 2026-08-19 — animation

#### Done

| | |
|---|---|
| `withAnimation`, `Animation`, `Animatable`, `VectorArithmetic`, `Transaction` | shipped |
| `.animation(_:value:)`, `.transaction(_:)`, `Binding.animation(_:)` | shipped |
| `Animatable`: `.opacity`, `.offset`, `.padding`, fixed `.frame`, `EdgeInsets`, `UnitPoint`, `CellSize`, `CellRect`, any app `ViewModifier` | shipped |
| Colour fades on `.foregroundStyle` / `.background` / `.border` | shipped |
| `.transition(_:)` with the seven built-in effects | shipped |
| `repeatForever` on `.opacity` served by pre-rendered runs (no render passes) | shipped |
| Example page, Stress scenario, DocC article, parity re-baseline | shipped |

#### Decisions worth a second look

**1. Colours do not go through `Animatable`.** A semantic `Color` is not
components until it meets a palette, and `animatableData` has no palette. So
the painting modifiers ask a helper at render time instead. SwiftUI solves the
same problem the same way (an internal resolved-colour type). App-facing API is
unchanged.

**Q1.** `Text.foregroundStyle(_:) -> Text` still does not fade — that overload
carries the colour in the view *value*, so no modifier is left to ask. Making it
fade means a store lookup per `Text`, which is the most-rendered view there is.
*Meanwhile:* documented on the modifier and pinned by a test. I think the cost
is not worth it, but you may disagree.

**2. Removal transitions need a surviving slot.** An `if` inside a stack had
none: a stack asks children to flatten and a `nil` optional flattened to *no
children*. Such a view animated in and jumped out.

**Q2 — answered, and done (2026-08-20).** You called the jump wrong, and it was.
The fix is narrower than I had feared: a `nil` keeps a slot only while the store
confirms something is still leaving from that exact address (parent identity +
the wrapped view's type), so a `nil` in an app that animates nothing costs one
`isEmpty` check and contributes no child — identities and stack spacing under
every existing `if` are untouched. The slot borrows `Wrapped`'s identity, which
is the address the present view rendered at, so it finds the picture that view
left behind.

**3. `PhaseAnimator` / `KeyframeAnimator` are recorded as not-implemented**,
with the reason: pre-rendering a subtree once per phase runs its render *side
effects* once per phase too. That is the same thing that killed the general
diffing engine in `Animating your own view efficiently.md` §5.3.

#### Performance

Everything is A/B'd against the commit before the animation work
(`ab_bench.py`, 41 reps, paired, order randomised).

| stage | `table` | `deep` | `kitchensink` | `megalist` |
|---|---|---|---|---|
| first cut | +0.8% | +1.0% | +1.0% | ~0 |
| after three rounds | +0.7% | +0.6% | +0.7% | ~0 |
| after `.padding`/`.frame` became animatable | +1.4% | **+14.0%** | +1.8% | +1.0% |
| after the generic witness | +0.7% | +7.6% | +1.0% | +1.4% |
| after the store stopped rebuilding its tables | ~0 | **+7.5%** | ~0 | ~0 |

The +14% is the lesson of the batch: `view as? any Animatable` **boxes**, and
with layout modifiers animatable that is a heap allocation per layout node per
walk — on a tree whose whole shape is nested layout, measured O(depth²) times.
Replaced with a static `View._animated` witness where `Self` is concrete, so
nothing is boxed and nothing is cast back. A second round stopped
`endRenderPass` rebuilding a whole dictionary per pass and stopped
`beginRenderPass` sweeping every record to clear a flag almost none of them set.

`table`, `kitchensink` and `megalist` — the three that look like real app
shapes — are now **indistinguishable** from before any of this existed.

**Q3.** `deep` stays at **+7.5%**, and I have stopped chasing it. It is the
deliberately pathological scenario: nested layout modifiers, re-measured once
per enclosing level (O(depth²)), so every animatable `.padding` / `.frame` pays
a store probe that many times. The only remaining fix is a per-frame "could
anything animate at all?" gate that skips the probe — and it is not sound as
designed, because a record has to exist BEFORE a change in order to know what
the value was before it. Every gate I tried either drops the first animated
change or is open permanently once an app animates anything once.
*Meanwhile:* accepted and recorded. My read is that a 7.5% on the deep-nesting
stress case is a fair price for `.padding`/`.frame` animating at all, given the
realistic shapes measure clean — but it is a judgement call and it is yours.

**Q3, measured again (2026-10-24, owner ruling WL-Q3 (b): measure first,
then A/B).** Counted, not timed, with temporary counters in
`animatedValue(of:owner:context:isMeasuring:)` over five warm frames of the
`deep` tree through `RenderLoopHarness` (counters removed after). Every
probe a frame makes is a padding's — `deep` writes no `.frame`; its
`.padding(1)` and its `.border()`'s inner padding are the two owners:

| depth | probes a frame | measure walk | render walk | answered by the settled fast path |
|---|---|---|---|---|
| 10 | 160 | 140 | 20 | 160 |
| 20 | 506 | 466 | 40 | 506 |
| 40 (the scenario) | 1,786 | 1,706 | 80 | 1,786 |

So the render walk asks twice per level, and the measure walks ask the rest,
growing as about depth^1.8 (O(depth²), as the entry says). Every probe ends at
`AnimationStore.isSettled`: one key built (the identity and the owner), one
dictionary lookup, and two `Any`-to-`EdgeInsets.AnimatableData` casts of the
record's target and origin; no environment read, nothing allocated, no
volatile read. What that costs in time is the A/B's to say: main against the
branch `wlq3-animatable-layout-off` (533b7b0ab, from main b8acc3898), where
`.padding` and `.frame` keep their conformances but answer the walks as types
that are not animatable — `Stress --bench --scenario deep` on the quiet
machine, and `kitchensink` and `table` as controls. Close the item if `deep` is
within a few percent, as the ruling says.

**Q3, the A/B (2026-10-24).** The owner's, release, warm, 15 reps:

    deep        −28.5% [−29.1, −28.1] faster without animatable padding/frame  (≈ +40% for it)
    kitchensink  +0.0% indistinguishable
    table        −1.3% [−2.0, −1.0] faster

Not within a few percent, so the item stays open. The cost did not grow
fivefold since August: the August numbers above were taken on a bench that
called `renderToBuffer` in a loop with no per-pass lifecycle, so the measure
memo was never emptied and served each frame's measures from the frames
before. Counted on the August commit (da01c6842) with temporary counters: 84
memo hits and 1 miss a frame, and 80 store probes a frame, all on the render
walk; no measure walk reached a padding. Since 87f260029 (2026-09-05) the
bench runs the app's lifecycle (it moved `deep` from 2,186 to 10,547 µs a
frame), and now: 9,366 measure lookups a frame at 9.2% hits, and 1,800 probes,
1,720 of them measuring. Each probe that finds its record compares the key's
identity node by node to the root, because a record keeps the nodes of the
frame that first saw it and each frame builds new ones: seven nodes per
nesting level, 187 on average; identity comparisons visit about 363,000 nodes
a frame, nearly all in these lookups, a retain and a release each. In the profile of main's release build that is
`animatedValue` 25.8% inclusive, `Dictionary.index(forKey:)` 22.5%,
`IdentityNode.structurallyEqual` 21.3%. Details in the VISUALS decisions file.

**Q3, a fix (2026-10-24), A/B owed.** Not the per-frame "could anything
animate?" gate this entry calls unsound: that one dropped the first animated
change, because a record has to exist before the change. This gate is on the
MEASURE walk only, which writes nothing: where no record is running or settled
away from its target, no transition scrub is installed and no animation is in
the transaction, every lookup would answer the target, so it is not made. The
render walk still makes the record at first sight, and on the frame an
animated change lands the transaction carries the animation, so the measure
asks. Profiled on `deep`: `animatedValue` 25.5% → 1.8% inclusive.


### 2026-08-19 — parity, continued

Working down the gap list, picking the ones a character grid can honour
*exactly* rather than approximately.

#### Done

- **Seven colour effects**: `.brightness`, `.contrast`, `.saturation`,
  `.grayscale`, `.hueRotation`, `.colorInvert`, `.colorMultiply`. These sound
  graphical and are not — each is a function from colour to colour, and a
  terminal names its colours explicitly in escapes it has already emitted.
  `.opacity`'s SGR walk turned out to be the general case and became one
  (`SGRColorRewrite`). All animatable, all size-neutral.
- **`Angle`**, which comes with `.hueRotation` and is the one place a geometric
  type earns its keep here: a hue *is* an angle, so this rotates colours exactly
  while nothing about the cells moves.
- **`.position(x:y:)` / `.position(_:)`** — the absolute counterpart to
  `.offset`, including SwiftUI's rule that a positioned view fills the space it
  is offered.
- **`Binding.animation(_:)`**.

A/B after the colour effects: `table`, `megalist`, `kitchensink`
indistinguishable. (`deep` unchanged at its known +7.7% — see Q3.)

#### Pulled before shipping

**Q4.** `.background(alignment:content:)` — I wrote it and then took it out,
because "draw this *behind* that" has no honest meaning when every cell is
opaque. SwiftUI's background shows through wherever the content is transparent;
here the content's spaces are cells like any other, so a background under
`Text("Total")` is simply covered by the word. The options are (a) treat a
space in the content as transparent, which is a real and defensible rule but a
new one, (b) ship it as "visible only where the content is shorter", which
would be surprising, or (c) leave it out. I left it out.
*Meanwhile:* `.overlay(alignment:content:)` already exists and is unambiguous,
and `.background(_ color:)` covers the common case.

*Reversed, 2026-10-03.* The premise went twelve days later, with 590e71a4f
("A glyph and the colour behind it are two statements"): a cell that names no
background now keeps the field under it. That gives "behind" an exact meaning
— the content composited over the background — and it is what SwiftUI's
picture comes to in a grid: every cell the content does not colour shows the
background's colour, translucent ones included, and a background *glyph* is
covered under any cell the content draws, which is `ZStack`'s rule already. So
`.background(alignment:content:)` ships, on the composite `.overlay` uses with
the layers swapped. None of (a)–(c) was needed.

#### Not attempted, and why

- **`deleteDisabled(_:)` / `moveDisabled(_:)`** — these belong on the ROWS of a
  `ForEach`, read by the enclosing `List`'s delete/reorder machinery. TUI has
  `onDelete` / `onMove` on `ForEach` itself, so wiring a per-row veto means
  threading an environment value through the reorder host. Worth doing; wants
  more room than the end of a batch.
- **`labelsHidden()` / `labelsVisibility(_:)`** — cheap to add, but only
  meaningful once `Toggle`, `Slider`, `Stepper`, `Picker` and `DatePicker` all
  honour it. Adding the modifier without that is the "silently does nothing"
  shape I have been avoiding all session.

## Parity work blocked on a decision (2026-10-12)

*Historical (moved here 2026-10-15): the last entry was answered and built on
2026-10-12, leaving the file empty, as its own review below says. Kept for the
reasoning recorded in its answered-so-far paragraph; questions for the owner now
go in each lane's decisions file under `Documentation/SwiftUI parity/Decisions/`.*

SwiftUI APIs that `Tools/APIParity` reports as gaps, where the gap is **not** a
matter of effort. Each needs a call that changes what existing TUI code does,
or picks between two defensible meanings. Implementing one of these without the
decision would be guessing on the owner's behalf, so they are parked here rather
than shipped.

Everything *not* on this list is ordinary work and is being done.

**Answered so far:** §1 (`opacity:` initialisers) and §2 (`Color.clear`) were
both **answered by building them**, on 2026-09-10: `Color` carries a real alpha,
resolved at the composite against what is actually behind the cell. The entries
are gone rather than ticked, as this file's last section requires; the design and
what it does NOT yet cover are in
[`Opacity as composition.md`](<../../Colour and styling/Opacity as composition.md>). Also: §9 (`Text.bold(_:)` and its siblings) — resolved by taking
its option (a): `TextStyle`'s five cascaded flags became tri-state, the merge
became nearest-wins, and the parameters followed. §6 (`labelsHidden()`) and §7
(`deleteDisabled`/`moveDisabled`) were both implemented after the last review —
`LabelsVisibility.swift` with `_CollapsingLabel`, `ColorPicker`, `Toggle`,
`ProgressView` and `DatePicker` all honouring it, and
`RowEditRestrictionModifiers.swift` with `RowEditRestrictionTests`. §1
(`Color.primary`/`.secondary`), §2 (`Color.accentColor`) and §8
(`focusEffectDisabled`) were answered on 2026-08-24. The colours were
implemented together: the whole "Semantic Colors" block now
means the palette roles it is named after, and the SwiftUI spelling replaced
`Color.accent`. `focusEffectDisabled` took the strict reading — every focus
indication goes, not only the animated part — with the caret and the
`DatePicker`'s field marker surviving as insertion points rather than
announcements, gated through one `RenderContext.indicatesFocus(_:)` so it
cannot be honoured by some controls and forgotten by others. The
reasoning is in those commits; the entries are gone from here rather than
marked done, as this file's last section requires.

Last reviewed: 2026-10-12. **No question is left, and no entry.** The last,
§1 (`View.help(_:)`), shipped on 2026-09-09; the owner answered its remaining
question on 2026-10-12 (views that cannot take the focus have help too, by
hover and by an app-wide help feature), and lane HELP built that the same day:
[Tooltips and help in a terminal](<../../Controls and presentation/Tooltips and help in a terminal.md>)
and [decisions HELP](<../Presentation and windows/Help and tooltips on every view.md>).
The two opacity entries went by being built. With nothing left in it, this file
moved to `Historical/` on 2026-10-15.

**An entry ends in a recommendation.** It is a recommendation, not a decision:
the point of this file is that the call is not mine to make. But an option list
with no opinion attached is a worse thing to be handed than one with an opinion
you can disagree with.

---

### Recording the answers

An answered item should end in one of two places, not in this file:

- **Implemented** — with the reasoning in the commit message, and
  `Tools/APIParity/api_parity.py --accept` re-run so the gap count moves.
- **Declined** — as an entry in `Tools/APIParity/parity-map.json` under
  `notImplemented` or `differentShape`, with the `why`. `--stale` will then keep
  that entry honest if the code later changes underneath it.

## The documentation reorganisation of 2026-10-12 (REORG)

*A companion to [the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>),
written by the lane that carried out the owner's request of 2026-10-12: "use human-readable names
(e.g. spaces between words, not underscores or hyphens) with reasonable detail … And arrange things
into subfolders when there's multiple related items (related in topic, not merely date)." Every
document under `Documentation/` but `Historical/` moved or was renamed (116 files, `git mv`, so
`git log --follow` keeps their history), and every reference to one, in the documentation, the code's
comments, the tools, CI and `.claude/CLAUDE.md`, names the new path. `git diff -M --name-status b95d6039f bbe8e918f`
lists every old-to-new name. No document was split, merged or rewritten. It holds only what
that work raised that the request did not settle, in the main file's three parts.*

- **A. Needs your decision.** Nothing has shipped for these. None.
- **B. Shipped the safe option.** Each entry says what the fuller version would be, and its price.
- **C. Declined without asking.** None.

### B. Shipped the safe option

#### B-REORG-1. The main decisions document moved, and only its references changed

*[the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>)*

The brief said not to edit it: the owner is reading it, and the coordinator removes finished items
from it himself. The request moves it beside its companions, and a move breaks every relative link
in it. It moved, and 16 of its lines changed, each one only where it names another document: a link
target (to the plan, `Future options.md`, the refusal review, the text-editing design study, the
DYNP file, the deviations page) or a file named in prose (`Terminal compatibility survey.md`,
`Scroll anchoring.md`). Nothing else in it changed.

**Fuller version:** none needed. **Price:** a removal of a finished item that touches one of those
16 lines conflicts when this commit is merged; the resolution is to keep the removal.

#### B-REORG-2. A link with a space in it is written `<like this.md>`

Two spellings work on GitHub: CommonMark's pointy-bracket destination, `[x](<../../SwiftUI parity/Decisions/Some name.md>)`, and
percent escapes, `[x](<../../SwiftUI parity/Decisions/Some%20name.md>)`. The names now carry spaces, commas and parentheses, and
`Some%20name%2C%20A28%20%282026-10-04%29.md` is not readable in the source, so every relative link
whose target has a space or a parenthesis uses the brackets, and the old `%20` links (to
`Historical/`) were converted. A link without a space stays plain. Absolute URLs would still be
percent-escaped; no committed document has one into `Documentation/`.

**Fuller version:** none. **Price:** a Markdown renderer that is not CommonMark-conformant reads
`<…>` as text; GitHub, DocC and the Swift Package Index (which shows GitHub's rendering of the
README) are not such renderers (unmeasured for the last).

#### B-REORG-3. A hyphen inside a compound word stays

"Spaces between words, not … hyphens" is read as: a hyphen that SEPARATED the words of a name
(as in the old names of the compatibility guide and the review batches) became a space; a hyphen
that is part of a word's spelling stays (`Keyboard drag-and-drop.md`, `Out-of-band styling surface.md`, `Intra-line output
diffing.md`, `the input-reader loop`, `opt-in`, `write-back`, the package name `swift-syntax`, and
ISO dates). `Out of band styling surface.md` would misspell the document's own title.

**Fuller version:** none. **Price:** none known.

#### B-REORG-4. `Historical/` keeps its prose

`Historical/`'s files are records of their time and were already readably named; none moved. Its
prose names documents by their names of the day 17 times (the live-sheets study 10, the geometry
study 3, the module split plan 2, the emoji note 2); those stay, as quoted history. No file in
`Historical/` has a relative link, so no link there broke.

**Fuller version:** rename those mentions too. **Price:** history that no longer says what it said,
for a reader who can follow `git log --follow` from either name.

#### B-REORG-5. Links that were broken before the move are fixed; one stale reference is left

`Tools/validate-markdown-links.py` (new, run in CI beside the table check) found 16 broken links in
the tree before the move, and they were fixed in the commit that adds it:

- 15 in `Gradients where a colour is accepted.md` were written from the repository's root with a
  line number, `Sources/X.swift:123`, which GitHub reads as a file named `X.swift:123` beside the
  document. Each now points at the file from the document, with GitHub's line anchor (`#L123`).
- 1 in the deviations page named B-D3M-1's heading without the U+FE0F variation selector of its ⚠️.
  GitHub's slug keeps combining marks (its filter keeps letters, marks, numbers, `_`, `-` and space),
  so the anchor now carries it, escaped as `%EF%B8%8F`. Unmeasured on GitHub itself.

Three references named wave decisions files that had been folded into the main document (wave 12:
B52–B61; wave 11a: B48–B51). The two to wave 12 (`Transaction.swift`, B55; the compatibility guide's
Animation row, B52) now name the main document, where both items still are. The one to wave 11a
(`TimeSpan.swift`, the unit spellings) is left as it was: its item is no longer in the main document,
so there is nothing to point it at. The text-editing design study's sentence that names wave 6b's
decisions file as one "which no longer exists" is about that absence and stays.

**Fuller version:** point `TimeSpan.swift` at the commit that folded wave 11a in (3c8fcbff0) or at
wherever the owner keeps finished items. **Price:** a comment pointing at history. **Done 2026-10-19**
(lane DOCS): the comment names 3c8fcbff0 and the `git show` that reads the file as it was.

#### B-REORG-6. Inside `Decisions/`, two topic folders, and step order for the module split

`Decisions/` holds the main document and every per-lane companion. Two groups are one topic each and
got a folder: **Module split/** (23 lanes: the steps, their cost recovery, the per-module products)
and **Compile time and binary size/** (BT1, TC1, TT2, SHIP, SHIP2, BNDL). The module split's files
are named "Step B5b, carving …", "Steps C3 and C4, peeling …", so a listing reads in step order, and
its cost-recovery lanes sort together as "Cost recovery, …". The SwiftUI API lanes, and the fixes and
follow-ups recorded in the same format, stay flat: their topics overlap (one lane covers input and
gestures, another lists and scrolling), so finer folders would split them arbitrarily. Every file
keeps its lane tag in parentheses at the end of its name, because commit messages and notes cite the
tags. This file is here rather than at `Documentation/SwiftUI-API-completion-decisions-REORG.md`,
the old scheme's path, which the move retires.

**Fuller version:** topic folders for the flat lanes too (input, lists and tables, presentation).
**Price:** a lane in two topics lives in one; the owner's call if the flat list grows.

**Built 2026-10-23** (the owner's (a), lane DOCS): 57 lane files moved into nine topic folders —
Scrolling; Layout and geometry; State and dynamic properties; Input, clipboard and text editing;
Terminals; Lists and tables; Shapes, effects and animation; Presentation and windows; Menus,
toolbars and chrome — and SIZEDOCS into Compile time and binary size. A lane in two topics lives in
the one its title leads with (D4X with input; D5G with layout; O12's pointer shapes with terminals).
Seven stay flat, each a topic of its own or a mix (BITEMS1, D6M, FORMS, FU2, PARITYMISC, REORG,
and the main document). Every link was rewritten by resolving it against its file's old place, and
every path in code comments and tools followed (`validate-markdown-links.py` clean).
