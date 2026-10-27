# Scroll phases, animated scrolling, flash and bounce

*How a scroll view reports what its scrolling is doing (`ScrollPhase`), how a
programmatic scroll came to glide, and the two indicator behaviours that only
make sense with them: the flash and the bounce. Ids: B27 (and B27-ANIMATING),
B28, B31, B-SCROLLB-1 to 3, C6, SCROLLX-UPSTREAM; deviation R1.*

## In short

A user's scroll reports `.interacting`, ending in `.idle` after 250 ms of
quiet, because a terminal reports no gesture phases. A programmatic scroll
made inside `withAnimation` glides a line (or a list row) at a time and
reports `.animating`. Velocity is `(0, 0)` at every report, as SwiftUI
measured. `scrollIndicatorsFlash` gives the bar or its "N more" lines a
half-second flash a step past the focus breath, and `.always` bounce springs
back from a push of up to two lines.

## The problem

SwiftUI's phases come from trackpad gestures and momentum; a terminal sends
wheel notches and key repeats, with no begin, end, delta or velocity. And TUI
did not animate scrolling at all, so `.animating` and `.decelerating` had
nothing to describe, and an overlay scroller's flash had nothing to reveal: a
terminal's bar is always drawn when the content overflows.

## How it unfolded

1. **2026-10-12, B27.** Phases shipped with the end of a scroll inferred from
   250 ms of quiet. Asked what velocity should mean, the owner chose SwiftUI's
   measured `(0, 0)` at both changes over a last-speed estimate, so no
   estimator was built. Asked whether any terminal extension reports more
   about a wheel: none does (`Terminal compatibility survey.md`), and SGR-Pixels
   is parked in `Future options.md`.
2. **2026-10-12, B28 and B31.** The owner asked for the flash anyway (as a
   half-second pulse) and for a real bounce, both if cheap.
3. **2026-10-13, lane SCROLLB** shipped the flash, the bounce and the
   velocity, with the calls B-SCROLLB-1 to 3.
4. **2026-10-23, B27-ANIMATING.** The owner chose option 3: animated
   programmatic scrolling with `.animating`, and a TUI-only opt-in for the
   page keys. Designed and priced at about six days on 2026-10-24, and built
   the same day in eight pieces; the design note is the appendix below.
5. **2026-10-25, SCROLLX-UPSTREAM.** Asked whether to propose a
   scroll-delta-and-phase mouse mode to kitty upstream: skip for now, and join
   kitty's effort when it starts (the 10-18 to 10-25 record).

## Where it stands

All shipped. `.tracking` and `.decelerating` are never produced (no touch, no
momentum). `scrollInputBehavior` is declined: its kinds are watchOS's (C6).

## For a future reader

- **The 250 ms quiet** (`ScrollPhase.quietNanos`) splits a very slow wheel
  into several scrolls and delays "scrolling ended" by that much. It is one
  constant if a use argues for another.
- **If a terminal ever reports a wheel's delta or phase** (the kitty effort,
  or SGR-Pixels), revisit B27's velocity and `.decelerating`.
- **A bounce is pushed by keys as by the wheel** (B-SCROLLB-3); SwiftUI's
  keyboard scrolling does not rubber-band (unmeasured). The other version is
  an hour or two.
- **What still jumps:** a page key's move onto the other axis under a two-axis
  `.paging` behaviour, and a push into an overscroll allowance.
- **The flash peak** is not in the generated row-fill tables, so the colour
  rules' verifier does not check it (B-SCROLLB-1); add it there if a palette's
  flash proves hard to see.

## The record

### B27. Scroll phases: `.interacting` until a quarter of a second of quiet, and no velocity

*`ScrollPhase` (all five cases, `isScrolling`, `debugDescription`),
`ScrollPhaseChangeContext` (`geometry`, `velocity`), `View.onScrollPhaseChange(_:)`
(both); `CellVector`, new, as the counterpart of `CGVector`*

Measured in SwiftUI: the action runs once on appear, `.idle` to `.idle`; a
`scrollTo` without animation changes no phase; one with animation goes
`.idle` → `.animating` → `.idle`. I could not measure a mouse wheel: events
synthesized into an offscreen hosting view do not reach its scroll view.

**Shipped:** a user scroll — wheel, keys, scrollbar, a drag's auto-scroll,
either axis — makes the view `.interacting`; it returns to `.idle` once the
steps have stopped for 250 ms (fifteen 60 Hz frames, a wake requested for the
moment) and nothing is held (a scrollbar drag or auto-repeat). A terminal
reports no gesture phases, so the end of a scroll is inferred from quiet:
wheel ticks and key repeats arrive well inside 250 ms, a pause to read does
not. `.tracking`, `.decelerating` and `.animating` are never produced — there
is no touch, no momentum, and TUI does not animate scrolling, so an
animated `scrollTo` is a jump here and changes no phase. `velocity` is always
`nil`; SwiftUI's is optional for the same reason.

**What you might want different:**

- *The quiet interval.* Shorter makes "scrolling ended" arrive sooner and
  splits a slow wheel into several scrolls; longer the reverse. It is one
  constant (`ScrollPhase.quietNanos`).
- *A measured velocity* (lines per second over the last few steps) is cheap
  if a use turns up; I did not invent one nobody reads.
- *`.animating`* comes with animated scrolling, which is its own feature.

**Decided 2026-10-12: measure a velocity, if it is cheap.** It is, at run
time (estimate): on each user scroll step a subtraction, a division, an
averaging step and about three stores, and 24 bytes per scroll handler, which
is a class, not the render context; nothing per frame, since it is read only
when a phase change is reported to an observer. B91's drag estimator can be
shared.

**Asked 2026-10-12: what the number should mean.** TUI reports two
changes. From idle to interacting, one step in, there is no rate yet: `nil`.
From interacting to idle, 250 ms after the last step, the view is still.
SwiftUI documents the velocity as the speed "at the time of the scroll phase
change", and measured (0, 0) at its appear call and at both changes of an
animated `scrollTo` (macOS 15.8, `Tools/SwiftUIProbes/Scroll position, margins and disabled scrolling (DECB)/phase/`); its value
when a user's scroll starts decelerating could not be driven offscreen. Read
literally, TUI's change to idle reports (0, 0), and the number never says
anything. **Recommended:** report the speed the scrolling had when its steps
stopped. TUI's one change to idle stands for SwiftUI's two (interacting to
decelerating, then to idle), and the speed belongs to the first; B91's
precedent, measured on macOS, is that a still pointer keeps its last motion's
velocity. That is a deliberate deviation, recorded when it ships.

**Owner, 2026-10-12 (later):** (0, 0) at both changes, as SwiftUI reports
it, not the last speed. So no estimator is built: the change to
`.interacting` and the change to `.idle` both report (0, 0), and the
velocity is never `nil`. The owner also asked whether any terminal extension
reports more about a wheel or a trackpad. None reports a delta, a phase or a
velocity: [Terminal compatibility survey.md](<../../Terminals/Terminal compatibility survey.md#wheel-reports-per-notch--a-hosts-choice-not-normalised>)
records what a notch sends, and [Future options.md](<../../Future options.md>)
parks SGR-Pixels (mode 1016).

**Shipped 2026-10-13 (SCROLLB):** the velocity is `(0, 0)` at every report —
the first frame's and both changes — and never `nil`.

**Shipped 2026-10-24 (B27-ANIMATING, option 3, all eight pieces):** a
programmatic scroll made inside `withAnimation` — a `scrollTo`, a
`ScrollPosition` request (a row, an edge, an offset) or a written
`anchorPosition` edge — glides to its target and reports `.idle` →
`.animating` on the frame it starts and `.animating` → `.idle` on the frame it
lands, with velocity `(0, 0)` at both, as measured above: a `ScrollView`'s a
line or a column at a time (both axes at once for an offset with both,
`.animating` until both land), a `List`'s or a `Table`'s a row at a time. A
user's scroll during it stops it where it stands, `.animating` →
`.interacting` with no `.idle` between; a reveal of the focus or a list's
cursor move stops it too, a second animated request glides on from where it
is drawn, and an unanimated one jumps. An unanimated request and one under
reduce motion still jump and change no phase. The lists, which reported no
phase at all, report theirs as a `ScrollView` does: `.interacting` for a
user's scroll (the wheel, the scrollbar, a drag's auto-scroll; the cursor keys
move the cursor, and report none), `.animating` while a request glides. Under
the TUI-specific `scrollKeyboardAnimation(_:)` the page keys glide too: a
`ScrollView`'s stay `.interacting`, counted quiet from the landing, so a held
Page Down is one span; a list's move the cursor and report nothing ([the
design note](#appendix-animated-scrolling-the-design-and-its-price-b27-option-3)).

### B28. `scrollIndicatorsFlash` flashes the indicators for half a second

*`View.scrollIndicatorsFlash(onAppear:)`, `View.scrollIndicatorsFlash(trigger:)`*

A flash exists because an overlay scroller is hidden until something scrolls.
A terminal's bar, or its "N more" lines, is drawn on every frame the content
overflows, from the first — as macOS's legacy ("always show") scrollers are,
under which a flash changes nothing either. SwiftUI flashes only the
indicators configured to be visible, and those are the ones already drawn.
So both join the medium-guaranteed modifiers (`MediumGuaranteedModifiers.swift`),
with a test of the guarantee: an overflowing view's first frame shows its
indicator in either style.

**The fuller version** would be a brief highlight of the bar — its focus pulse
for half a second — to draw the eye, as a flash does. About two hours:
the bar memo is keyed on the pulse already, and the trigger needs a
per-view "last value" and a wake. I would only do it if a port asks.

**Decided 2026-10-12: implement it.** (On 2026-10-04 you pointed out that
TUI supports automatic visibility; the 2026-10-05 answer was that TUI's
`.automatic` shows the bar whenever the content overflows, with no fading, so
the bar is already visible whenever a flash could matter, and the alternative
is a half-second pulse.) **Lane owed** (shipped 2026-10-13, below): 2–3 commits, half a day to a day
(estimate), more than the two hours above: bars are drawn in at least five
views (`ScrollView`, `List`, `Table`, `TextEditor` and the field chrome);
`trigger:` needs a last-value store per view (a small `_*Core` with negative
state indices); and a focused bar already breathes, so the flash needs a
distinct peak within the focus and selection colour rules. A view that is not
flashing pays nothing.

**Shipped 2026-10-13 (SCROLLB):** both forms, in `ScrollView` (both bars and
its "N more" lines), `List` and `Table` (bar or lines) and `TextEditor` (its
bar). The field chrome draws no scroll indicator (`FieldChrome` is the caps
only), so there is nothing there to flash. A flash is half a second — ten
steps of three 1/60 s ticks — rising in two, held for four, fading over four;
the thumb and arrows, or the lines, go from where they rest to one
`hoveredForeground` step past the focused breath's far end (the focus
identity's own colour, so a focused bar's flash is told from its breathing),
drawn still, without the breath's runs. `trigger:` keeps its last value in a
`_ScrollIndicatorsFlashCore` (state index −150, a new reserved range); the
scrollable keeps when it first drew, for `onAppear:`. A scrollable that is not
flashing asks for no frame; where it draws an indicator, the flash costs one
environment read a frame. The peak and the shape are the lane's call:
[B-SCROLLB-1](#b-scrollb-1-a-flash-peaks-one-hover-step-past-a-focused-bars-breath).

### B31. Bounce behaviour gates the overscroll allowance, and `.always` springs back

*`ScrollBounceBehavior` (`.automatic`, `.always`, `.basedOnSize`; its
`differentShape` map entry goes), `View.scrollBounceBehavior(_:axes:)`,
`EnvironmentValues.verticalScrollBounceBehavior`,
`EnvironmentValues.horizontalScrollBounceBehavior`*

The refusal review called this a cheap alias over `ScrollOverscroll`, and the
two are close but not the same: SwiftUI's bounce springs back, TUI's
overscroll stays (that is what makes a deliberate push readable, §1.5 of
`Scroll anchoring.md`), and the allowance's size is TUI's own setting.

**Shipped:** the behaviour decides *when* the allowance applies, and
`.scrollOverscroll` keeps deciding *how far*:

- `.basedOnSize` — only while the content overflows, so content that fits
  sits still. This is the reason the modifier is written in practice, and it
  is the opt-out from your 2026-07-31 decision that a fitting view may still
  be pushed.
- `.always` and `.automatic` — whatever the content's size: TUI's default,
  as `.always` is SwiftUI's.

With no allowance (TUI's default) nothing is pushed at all, which is also
what macOS does under a mouse wheel. The allowance is vertical only, so the
horizontal value is recorded and decides nothing yet.

**The fuller version** is a real bounce: a default allowance of a line or two
under `.always`/`.automatic`, sprung back once the scroll phase returns to
idle (B27 gives the moment). Half a day, and it changes the default feel
of every scrollable, so it is yours to want.

**Decided 2026-10-12: a bounce, if it is cheap.** (You asked on 2026-10-04
whether a full bounce is easy; the 2026-10-05 answer proposed the scope
below.) It is cheap at run time (estimate): nothing new per frame for a view
that is not overscrolled, since the allowance and excursion tests run already;
one wake request per step while it is; a spring-back of one to two frames,
re-sliding a buffer already drawn; one flag per handler. **Scope:** `.always`
gets a sprung allowance of one or two lines; `.automatic` keeps today's feel;
an explicit `.scrollOverscroll` allowance keeps staying where it was pushed,
since that is TUI's deliberate-push signal. **Lane owed** (shipped 2026-10-13,
below): 2–3 commits, half a day to a day, which includes detecting the end of a scroll without a
phase observer (shared with B27) and the spring-back in `List` and `Table`.
Nothing is paid by an app that does not write `.always`.

**Shipped 2026-10-13 (SCROLLB):** under `.always` an end the app gave no
allowance gets a sprung one — two lines, one in a view under eight lines tall
([B-SCROLLB-2](#b-scrollb-2-the-bounce-is-two-lines-one-in-a-view-under-eight-lines-tall-per-end)).
A push into it is held while the user's steps keep coming, and once they have
been quiet for 250 ms (B27's `ScrollPhase.quietNanos`, no phase observer
needed) it springs back a line a 50 ms frame, in `ScrollView`, `List` and
`Table` alike (`ScrollableOffsetState.settleOverscroll`). `.automatic` and
`.basedOnSize` are as they were, and an allowance the app asked for stays
where it was pushed under every behaviour. Cost: a bounce-free view's frame is
unchanged but for one more comparison as its allowance is resolved; a pushed
view asks for the frames of its spring.

### B-SCROLLB-1. A flash peaks one hover step past a focused bar's breath

*`View.scrollIndicatorsFlash(onAppear:)`, `View.scrollIndicatorsFlash(trigger:)`*

The ruling asks for the bar's focus pulse for about half a second, with a
distinct peak within the focus and selection colour rules. A focused bar
already breathes between the accent and its lift (`ScrollbarColors.pulseLift`),
so a flash that only reached the lift would not be told from the breath.

**Shipped:** the thumb and arrows — or the "N more" lines — go from where they
rest to one `Palette.hoveredForeground` step past the breath's far end, the
step the pointer's own lift takes, so the flash stays in the focus identity's
colour and on the palette (no new hue). Where that step has no room (it lands
within the chrome pulse floor of the lift), the peak is the lift itself, which
an unfocused bar's resting grey still rises to. The lines use the same peak,
spent over the surface they sit on, so a bar and its lines flash alike. The
shape is ten 50 ms steps (three 1/60 s ticks each): ½, then full for five,
then down a fifth a step. Drawn still: the breath's runs would replay over it
from their first tick.

**The fuller version** would put the flash peak in the generated row-fill
tables (`Tools/RowFillValues`), checked by the colour rules' verifier at every
depth for every shipped palette, as the focus and selection colours are: half a
day, and only worth it if a palette's flash turns out hard to see.

### B-SCROLLB-2. The bounce is two lines, one in a view under eight lines tall, per end

*`ScrollBounceBehavior.always`, `View.scrollBounceBehavior(_:axes:)`*

The ruling gives `.always` a sprung allowance of one or two lines.

**Shipped:** two lines; one in a view whose content area is under eight lines,
so a push never hides more than a quarter of a small view. The allowance is per
end: an end the app gave an allowance (`.scrollOverscroll`) keeps it, and its
push stays where it was put; an end it gave none springs. A pushed bounce is
held while the steps keep coming and springs back one line a 50 ms frame once
they have been quiet for 250 ms (B27's quiet, `ScrollPhase.quietNanos`), so a
two-line push is gone in two frames.

**The fuller version** would let the app size the bounce — say a
`.scrollOverscroll` spelling for a sprung allowance. No SwiftUI spelling asks
for one; an hour if a port wants it.

### B-SCROLLB-3. An arrow or page key at the end pushes the bounce, as the wheel does

*`ScrollBounceBehavior.always`*

Every user step past an end takes one path (`userScrollFine`): the wheel, a
scroll view's arrow and page keys (and the focus section's scroll fallback),
the scrollbar's arrows. A focused `List`'s or `Table`'s arrow and page keys
move its cursor and never reach it, so they push nothing there. It is what makes a step that only
reaches the edge a graze and the next one a push (§1.3 of `Scroll
anchoring.md`), and an allowance the app asks for has always been pushed by a
key as by the wheel. SwiftUI's keyboard scrolling does not rubber-band on macOS
(unmeasured; the lane's review says so), and nor does a mouse wheel there: its
bounce is a trackpad's.

**Shipped:** the sprung allowance is an allowance like the others, so a key
pushes it too, and it springs back as a wheel's push does. A key at the end
shows the end, briefly, rather than doing nothing.

**The fuller version** pushes the bounce under the wheel only: the step's
source passed down to `userScrollFine` from its callers (the wheel, the key
handlers, the scrollbar's arrows and page track, the "N more" lines), and a
key's step left to graze the sprung end. An hour or two; the two allowances
would then answer different inputs, which is why it was not the default.

### C6. `scrollInputBehavior(_:for:)` and `ScrollInputKind`

*`ScrollInputKind`, `View.scrollInputBehavior(_:for:)`*

`ScrollInputKind`'s values are watchOS's — the Digital Crown and the
double-tap hand-gesture shortcut — and the macOS SDK defines none. No macOS
source can name a kind, so none can call the modifier: declining it changes
what compiles for nobody. A terminal has neither input. What macOS code can
ask — may this view scroll at all — is `.scrollDisabled`, already the
`ScrollInputBehavior` map entry.

## Appendix: animated scrolling, the design and its price (B27, option 3)

*Written 2026-10-24 for the owner's answer to
[B27-ANIMATING](<../SwiftUI parity process/The owner's decisions, 2026-10-18 to 2026-10-25.md#b27-animating>) (option 3,
2026-10-23). Line references are to `main` at `83d6292fd`.*

**Status: built, 2026-10-24, in the eight pieces below** (`git log --grep
B27-ANIMATING`). Where the build parts from this note:

- **The request frame does not draw the content twice by default.** The
  forced redraw at the start was measured unnecessary (what is placed by where
  it is drawn is worked out against the frame's final offset), so the frame
  draws again only where the band drawn at the request misses the start,
  `coverSnappedViewport`'s own rule (§1, "The request frame").
- **A glide asks for one more frame than its line changes:** the tick its
  animation ends on, which lands it and fires `withAnimation`'s completion.
- **A written `anchorPosition` edge glides too**, as an edge request does.
- **A `List` or a `Table` glides a row at a time, not a line** (§1 says "a line
  step for a list too"). A list's row height is known only by building the row,
  so line steps past rows a glide never draws would build them all to count
  their lines. The landing puts the list exactly where the jump would, a tall
  row's clipped lines included, so only the frames between are coarser.
- **The lists' cursor keys report no phase**, nor do their page keys' glides:
  they move the cursor, which is no scroll of the user's (SwiftUI not
  measured). The wheel, the scrollbar and a drag's auto-scroll are
  `.interacting`. The phase context's geometry counts each row above a list's
  top one as a line, rather than build rows to measure them.
- **A key's glide starts on the frame after the key** (event time has no frame
  clock), which draws its start, as every glide's first frame does.
- **What still jumps:** a page key's move onto the other axis by a two-axis
  `.paging` behaviour, and a push into an overscroll allowance (as §4 says).
- **The Stress `glide` scenario** needs the run loop's frame clock, which
  `--bench` gives only a scenario that asks for it
  (`DrivenScenario.runsAnimationClock`).

The ruling covers three things. Programmatic scrolls made inside an animation
(`ScrollViewProxy.scrollTo`, `ScrollPosition` writes, anchor changes) move in
whole-line steps at 60 Hz along the animation's curve. While they move, the
view reports `ScrollPhase.animating`: idle → animating → idle, as SwiftUI does
(measured, [B27](#b27-scroll-phases-interacting-until-a-quarter-of-a-second-of-quiet-and-no-velocity)).
Under reduce motion they jump. On top of that, Page Up/Down and Home/End can
glide, through a TUI-only opt-in modifier.

**Price: about 6 days (estimate), in 8 commits.** Idle cost is one nil test per
scrollable per frame. A glide frame costs what a one-line wheel step costs now,
and is drawn only on ticks where the line changes.

### 1. Where the animated offset lives, who moves it, and how a frame reads it

**Today.** A scroll view's offset is `ScrollViewHandler.scrollOffset`
(`Sources/TUIFoundation/Focus/ScrollViewHandler.swift:106`). It is in whole
lines and is the one value that both event-time code (keys, wheel) and the
render read. Programmatic placements go through `jumpProgrammatically(to:)`
(`ScrollViewHandler.swift:423-426`):

- a seek resolved by drawing the content at the request
  (`Sources/TUIFoundation/Views/ScrollView.swift:635-670`);
- a bound position's edge or offset (`ScrollView+ScrollPosition.swift:44-65`).

`scrollTo` parks a request on every registered scroll view and asks for a frame
(`ScrollViewReader.swift:154-162`). That request goes through
`AppState.setNeedsRender()`, which stamps the ambient transaction
(`Sources/TUIView/State/State.swift:63-66, 100`). The loop publishes that
transaction for exactly one pass (`Sources/TUIApp/App/RenderLoop+Animation.swift:70`).
So the frame that consumes the request already sees the `withAnimation`
transaction, which is how B30 reads `scrollTargetAnchor`
(`ScrollView+ScrollPosition.swift:27`).

**Proposal: `scrollOffset` stays the drawn offset, and a glide is a distance.**
A new `ScrollGlide` value sits beside `overscrollState` as a requirement of
`ScrollableOffsetState` (`ScrollableOffsetState.swift:123`). Both
`ScrollViewHandler` and the lists' `ItemListHandler` therefore carry it, and
the horizontal axis's conformer does too. It holds:

- `distance` (signed, in the scrollable's `scrollFine` unit);
- `covered` (how much has been stepped so far);
- the `Animation`;
- `startNanos` (frame clock);
- what to re-apply on landing (the request, or an edge).

Each frame steps the offset by `round(distance × fraction) − covered` through
`scrollFine(by:)`. That step costs O(step), and it is a line step for a list
too (`Sources/TUILists/Focus/ItemListHandler+Keys.swift:551`). The fraction
comes from `Animation.fraction(at:)` and the end from `isFinished(at:)`
(`Sources/TUICore/Animation/Animation.swift:559, 592`). A spring's overshoot
shows inside the content and is clamped at its ends. A repeating animation
glides on its first pass only.

**Why not `AnimationStore`?** It is the shared "where has the picture got to"
store (`Sources/TUIView/Animation/AnimationStore.swift:195`), and
`ChildGlide` uses it (`ChildGlide.swift:259-261`). It does not fit here for
three reasons:

1. Keys and the wheel move the offset at event time, with no context.
2. The store treats every new target as a fresh change, and with no animation
   in force it jumps there (`AnimationStore.swift:256-263`). So the anchor
   adjustments in §2 would abandon a glide.
3. Its live records hold the 30 Hz lattice open (`RenderLoop+Animation.swift:89-95`;
   `AnimationRequest.viewAnimations` is 2 ticks, `AnimationRequest.swift:48`).
   A glide wants 60 Hz frames, and only some of them.

What we lose is the store's velocity-preserving retarget
(`AnimationStore.swift:564-596`). See §2.

**Who advances it.** The render advances it. One shared call,
`settleGlide(context:)`, follows the precedent of `settleOverscroll`, the
spring-back that already steps a scroll a line a frame on wakes it asks for
(`ScrollOverscroll.swift:131-150, 166-177`). On a render pass with a glide:

1. Step the offset to this frame's place before the content draws, where
   `applyPositionOffset` runs (`ScrollView.swift:606`).
2. Declare the frame volatile and ask for one wake, with
   `context.requestWake(token:atNanos:)` (`RenderContext+Animation.swift:93-101`).
   That call also records the render side effect, so no memo above keeps a
   mid-glide frame. The wake is set at the first 1/60 s tick at which the
   rounded position changes. To find that tick, sample the curve forward a
   tick at a time; that is a few curve evaluations per frame.

So a 5-line glide draws 5 frames, not the 21 that 0.35 s holds. The default
spring (`Animation.swift:131-137`) makes its last visible change at about
0.84 s, so no glide draws more than about 50 frames. The landing frame clears
the glide.

**The request frame.** A seek finds its target by drawing the content at it
(`ScrollView.swift:665-670`), and the frame must then show the starting offset.
So it draws again at the start, as `coverSnappedViewport` already does for a
reveal (`ScrollViewReveal.swift:397-418`). That costs one extra O(window)
render per animated request. An edge or offset request knows its target from
arithmetic and needs no second drawing.

**The animation in force** is `canAnimate ? transaction.effectiveAnimation : nil`,
dropped under reduce motion. That is `ChildGlide`'s rule
(`ChildGlide.swift:251-253`).

**Completions.** The glide reports `noteStarted(_:at:key: nil)` to the pass's
completion tracker (`AnimationCompletionTracker.swift:75`). So
`withAnimation(…, completion:)` fires at the animation's deadline, as a
departure's does.

**`.animating`.** `reportScrollPhase` (`ScrollPhase.swift:179-197`) runs only
when there is an observer, so the phase costs nothing without one. It sets
`.animating` on the request frame and `.idle` on the landing frame, with
velocity (0, 0) as everywhere (R1). `settlePhase` (`ScrollPhase.swift:202-216`)
keeps handling `.interacting`. The `.animating` comment
(`ScrollPhase.swift:45-47`) changes to say when it is produced.

### 2. Interactions, each with its rule

- **Scroll anchoring while content changes mid-glide.** The top-row hold
  (`ScrollView+Anchor.swift:204-260`) shifts the offset when rows arrive above
  the top row. The glide is a distance, so the rest of it is unchanged: the
  destination moves with the rows, which is right for an insertion above both.
  An insertion between the viewport and the destination would land the glide
  off by the inserted lines. To correct that, the landing frame re-applies the
  original request without animation (a re-seek, or the edge). That costs one
  seek, and the jump is usually zero lines. A view in the middle of a glide is
  not glued to its tail (`isGluedToBottom`, `ScrollView+Anchor.swift:128`). A
  bottom-edge glide lands through the End path's tail seek
  (`ScrollViewHandler.swift:409-412`), so rows that arrive during it are
  followed from the landing on. `.scrollContentOffsetAdjustmentBehavior(.disabled)`
  needs no rule of its own: it stops the hold, and the glide carries on.
- **`scrollTargetBehavior`.** Programmatic scrolls are not gestures, here as in
  SwiftUI (compatibility guide, Scrolling row, `SwiftUI compatibility guide.md:130`).
  So a `scrollTo` glides to its own target, unsnapped, as it jumps there today.
  A paging key is a gesture. Its landing is the behaviour's target
  (`userScrollStep`, `ScrollableOffsetState.swift:256`, applied in
  `userScrollFine`, `:652-653`), which is snapped first and then glided to.
  Intermediate frames are not landings and do not consult the behaviour. A
  resize in the middle of a glide lands it at its target before
  `settleTargetAfterResize` runs (`ScrollViewReveal.swift:371-389`).
- **Scroll transitions** are worked out from where each view sits at the frame's
  offset (compatibility guide, Scrolling row). Every glide frame is a frame, so
  `.interactive` transitions follow each intermediate line. `.animated` ones
  switch at their threshold and run their own animation there. Under reduce
  motion they already hold their offsets still (A-D3M-1, FU3). No rule is
  needed.
- **User input mid-glide.** A wheel tick, a scrollbar press, a drag's
  auto-scroll, a focus move, or a key during a programmatic glide each stops the
  glide where it stands. The input then acts from there, and the phase becomes
  `.interacting` (`noteUserScroll`, `ScrollViewHandler.swift:374-378`). This
  matches SwiftUI, where a gesture interrupts an animated scroll (not measured
  here). During a key glide, a gliding key retargets from the glide's target,
  not from where it stands, so that N presses move exactly N pages. A
  non-gliding key (an arrow) lands the glide at its target first and then steps.
- **A second `scrollTo` mid-glide** starts a new glide from the drawn offset
  under the new transaction's animation, starting at rest. An unanimated one
  cancels the glide and jumps. Carrying the velocity over would reuse
  `AnimationStore`'s velocity estimate (`AnimationStore.swift:597-616`); that is
  half a day, and only if a port asks.
- **List and Table do not share ScrollView's path.** They resolve `scrollTo` and
  `.scrollPosition` themselves (`_ListCore.swift:1869-1874`,
  `Table.swift:2934-2941`) through `ItemListHandler.scroll(toRow:anchor:)`
  (`ItemListHandler+ScrollTo.swift:23-43`). Because the glide state is on
  `ScrollableOffsetState`, they share the glide but not the seek. The glide
  moves the viewport only; the focus cursor and the selection stay put, as
  `scroll(toRow:)` promises. **A gap found while writing this:** neither reports
  any scroll phase today. No `onScrollPhaseChange` observer is read in
  `TUILists` or `TUITables`, where SwiftUI's `List` is a scroll view and
  reports them. `.animating` on a list needs that reporting first (piece 6).
- **Nested scroll views.** A request is parked on every registered view, and
  each resolves it against its own content (`ScrollViewReader.swift:144-162`).
  So each view that holds the key glides on its own handler, just as each jumps
  today. A wheel in the middle of a glide is spent on the gliding view: it is
  not at an edge, so nothing chains to the enclosing scroller
  (`ScrollableOffsetState.swift:633-690`).
- **Lazy stacks** draw the band at each frame's offset, so each frame is
  O(window) even at millions of rows. Rows the glide passes between two frames
  are never built. Rows a frame shows are built, appear, and report visibility
  (`onScrollVisibilityChange` reports from what each frame draws). The
  intermediate offsets can land on estimated heights (`contentHeightIsEstimate`,
  `ScrollViewHandler.swift:310`); the landing re-seek corrects the end.
- **A bound `.scrollPosition(id:)`** is written back only on landing, not at
  each intermediate row. Written every frame, it would make the app's body
  render again on every glide frame (`ScrollView+ScrollPosition.swift:67-74`).
  SwiftUI's behaviour here is not measured. If a probe shows it reports along
  the way, this becomes a recorded deviation.

### 3. Reduce motion

Under reduce motion every glide is a jump, the scrollTo and the keyboard ones
alike. This is A-D3M-1 (scroll offsets are spatial motion,
`D3M.md:147-160`), applied through `ChildGlide`'s rule
(`ChildGlide.swift:251-253`). Without a scheduler (`canAnimate` false, a
one-off render) it jumps too. A jump changes no phase, as an unanimated
`scrollTo` changes none (measured, B27). D3M's line "Scrolling is never
animated in TUI" (`D3M.md:166`) is rewritten when this ships.

### 4. The TUI-only keyboard opt-in

```swift
extension View {
    /// The animation a scrollable's Page Up/Down and Home/End glide with,
    /// or `nil` (the default) to jump. TUI-specific.
    public func scrollKeyboardAnimation(_ animation: Animation? = .default) -> some View
}
```

It is an environment modifier, as `scrollChainingDelay(_:)` is
(`ScrollableOffsetState.swift:922-924`). It is read once a frame where the
handler is captured, beside `scrollChainingDelay`
(`ScrollView.swift:405-406`), because event time has no environment. It
animates `.pageUp`/`.pageDown`/`.home`/`.end` in `handleKeyEvent`
(`ScrollViewHandler.swift:460-506`):

1. The key computes the landing as now, with the behaviour, edge anchors and
   the tail seek all applied.
2. It puts the offset back.
3. It records the distance.
4. The next render starts the glide.

These do not glide:

- Arrows, Shift-arrows: one line, or five, is already a step.
- Wheel ticks.
- A push into overscroll: a line or two, shown at once.

The phase stays `.interacting`, since B27 defines keys as interaction. Its
250 ms quiet is counted from the landing, so a held Page Down is one
interacting span and does not flip back and forth with `.animating`. List and
Table paging moves their cursor (R1), so it joins later, as piece 7.

### 5. Cost

- **Per glide frame.** The cost equals a one-line wheel step's frame today. No
  scenario measures that on static content (`scrollfollow` and `scrolleager`
  change content every tick, `Sources/Stress/README.md:88-89`), so piece 8 adds
  one. What stays cheap:
  - Rows are drawn with the scroll window cleared (`VStack.swift:860`,
    `StackTargetLayout.swift:70`), so a row's memo does not depend on the
    offset. Rows on screen at consecutive offsets are served from it wherever
    that row memoises.
  - The scroll view and its windowed stack composite again every frame. The
    window, offset included, is part of the environment their memos key on
    (`ScrollContentWindow.swift:13-47`).
  - The scrollbar memo misses whenever the thumb moves
    (`ScrollViewHandler.swift:65-76`).
  - The bytes are the changed viewport lines. Nothing is scrolled in hardware
    yet (`Terminal compatibility survey.md:6787`, O2).
  - The `onScrollGeometryChange` observers run every frame, as they would for
    a wheel.
- **Idle.** One `glide == nil` test per scrollable per render. There are no
  wakes, no volatile reads, and no environment reads beyond the keyboard
  modifier's one lookup per scroll view. That lookup is the one cost to watch:
  `tables-scroll` showed 0.3 µs per scroll view as +4.2% (`Performance pass
  after the SwiftUI API batch (2026-10).md:231-234`). If it shows there, fold it
  into a value already read.

**Price, in landing order (estimates; one commit each):**

| # | Piece | Days |
|---|-------|------|
| 1 | `ScrollGlide` on `ScrollableOffsetState`, `settleGlide`, line-crossing wakes, reduce motion, completions; `ScrollView` vertical `scrollTo` and `ScrollPosition` row requests, including the start-offset redraw | 1.5 |
| 2 | `.animating` reporting in `ScrollView` | 0.25 |
| 3 | Interruptions and retargets, the landing re-seek, the resize landing, edge glides through the tail seek | 1.0 |
| 4 | Horizontal axis: `ScrollPosition` x and column `scrollTo` | 0.5 |
| 5 | `scrollKeyboardAnimation(_:)` for `ScrollView` | 0.75 |
| 6 | `List` and `Table`: animated `scroll(toRow:)` and position requests, plus `onScrollPhaseChange` reporting, which they lack | 1.0 |
| 7 | `List`/`Table` keyboard paging under the modifier (the cursor's page move glides the viewport) | 0.5 |
| 8 | Stress `glide` scenario, profile, docs (R1 rewritten, B27, guide row, D3M:166, `ScrollPhase.swift:18` and `:45-47`, `AccessibilityReduceMotion.swift:39`) | 0.5 |

**Total: about 6 days.** Pieces 1–3 deliver the SwiftUI parity on their own
(about 2.75 days). 4–5 complete the ruling for `ScrollView`, and 6–7 extend it
to the lists.

**Risks.**

- The request frame draws twice.
- The landing re-seek can show a final jump under heavy churn.
- A heavy page pays a full frame for every line step for up to about 0.84 s.
- The scrollTo transaction lasts one frame. A scroll view that does not draw on
  that frame, such as one in a hidden tab, jumps when it next draws.
- The memo verifier cannot see side effects, so test the volatile declaration
  directly.

### 6. Tests that would pin it

Clocks are pinned as the existing tests pin them: `frameNowNanos` on the
context (`Tests/TUIEffectsTests/StackGlideTests.swift:125`) and
`handler.phaseNow` (`Tests/TUIAppTests/OnScrollPhaseChangeTests.swift:45`).

1. An animated `scrollTo` draws the start on its first frame, then whole-line
   offsets that never move backwards under an ease, then the target. An
   unanimated one still jumps.
2. Frames are asked only at ticks where the line changes: an n-line glide asks
   for at most n wakes, all on 1/60 s ticks.
3. Phases: idle → animating → idle, velocity (0, 0) at each. A wheel in the
   middle gives animating → interacting, with no idle in between.
4. Under reduce motion, and with `canAnimate` false, it jumps and reports no
   phase.
5. `withAnimation(…, completion:)` fires once, at the animation's end.
6. An insertion above mid-glide still lands on the row. An insertion between the
   viewport and the row lands on it through the landing re-seek.
7. A second `scrollTo` retargets from the drawn offset. A wheel stops the glide
   where it stands.
8. A `.paging` view's Page Down glides to a page boundary. Three presses
   mid-glide land exactly three pages down. Down mid-glide lands the page and
   then steps.
9. A `.interactive` scroll transition's phase changes on intermediate frames.
10. A lazy stack at 10⁶ rows glides with O(window) rows built per frame.
11. A bound `.scrollPosition(id:)` is written once, on landing.
12. `List` and `Table` glide without moving the cursor or the selection, and
    report the phases.
13. Idle: a settled scroll view requests no wake and serves from its memo.
    Gliding, it declares the frame volatile.
14. Without `scrollKeyboardAnimation`, every key jumps as today (the existing
    key tests are unchanged).

