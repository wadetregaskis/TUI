# Completing the SwiftUI API: Wave 10 (scrolling) decisions

*The Wave 10 companion to
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md),
in the same three parts and read the same way: once, at the end of the
straightforward work. Entries are numbered A-W10-1, B-W10-1 and C-W10-1 onwards
so they can sit beside the main document's without colliding.*

- **A. Needs your decision.** Nothing has shipped. Each entry gives the
  options, what each costs, and my recommendation.
- **B. Shipped the safe option.** A basic, honest form is in. Each entry says
  what the fuller version or the alternative reading would be, and what it
  would cost.
- **C. Declined without asking.** Recorded in `parity-map.json` as not
  implementable, because the reason seemed unarguable. Listed so they can be
  vetoed.

SwiftUI behaviour quoted as *measured* was measured on macOS 15 with an
offscreen `NSHostingView` (the probes are in the session notes, `w10/probe`).

---

## A. Needs your decision

## B. Shipped the safe option

### B-W10-1. `ScrollPosition`: the request and the row are read separately, and `viewID` answers sooner than SwiftUI's

*`ScrollPosition.init(idType:edge:)`, `.init(idType:point:)`, `.init(idType:x:)`,
`.init(idType:x:y:)`, `.init(idType:y:)`, `.point`, `.x`, `.y`, `.viewID`,
`.scrollTo(point:)`, `.scrollTo(x:)`, `.scrollTo(x:y:)`; and the behaviour of
`.isPositionedByUser` and `.viewID(type:)`*

Measured in SwiftUI:

- after `scrollTo(y: 100)`, `point`, `viewID` and `edge` are all `nil` and
  `isPositionedByUser` is `false` (so `y` holds the request — `y` itself is
  macOS 26 only and could not be read here);
- after an animated `scrollTo(id: 10)`, `viewID` is `10` and
  `isPositionedByUser` is still `false`.

So SwiftUI's readings are the *request*, until the user scrolls. TUIkit's were
the *report*: every frame the windowed stack named the row at the anchor,
overwrote the request with it, and set `isPositionedByUser` — on the first
frame too, with nobody having touched anything. With `x`, `y` and `point`
added that model would have answered a request for one frame and then
forgotten it.

**Shipped:**

- The request (`edge`, `x`, `y`, `point`, an asked-for row) and the reported
  row are held separately. The request stays readable until the user scrolls,
  which drops it, as SwiftUI's does.
- `isPositionedByUser` is set by a user scroll and nothing else — the wheel,
  the keys, the scrollbar, a drag's auto-scroll, on either axis. Writable, as
  SwiftUI's is: `true` drops an edge or offset request.
- `viewID(type:)` still answers with the row the view reports after a
  programmatic scroll and on the first frame — TUIkit's existing, deliberate
  read-back ("reading tells you where it ended up"). SwiftUI answers `nil`
  there until the user scrolls past a row. A reading SwiftUI would give is
  never different here; it is only present sooner.
- `viewID` (type-erased, `any Hashable & Sendable`) returns a *reported* row
  only when the position was made with `idType:`. A `ForEach` id is only
  `Hashable` by signature, and `Sendable` is a marker protocol no run-time cast
  can recover. An id the app passed in comes back either way.
- `x`, a `CellPoint`, and `.leading`/`.trailing` move the horizontal axis.
  These are arithmetic, not a row seek, so they need nothing from the
  row-windowing handshake that keeps `scrollTo(id:)` vertical.

**The alternative** is SwiftUI's reading exactly: `viewID` stays `nil` until
the user scrolls. That would break the `ScrollPosition` read-back tests (the
first frame and the programmatic scrolls report a row today) and take away
an answer apps can use, for no behaviour SwiftUI code depends on. I don't
recommend it.

### B-W10-2. Content margins: where TUIkit applies them, and what a scroll indicator's margin moves

*`View.contentMargins(_:_:for:)` (both), `View.contentMargins(_:for:)`,
`ContentMarginPlacement` (`.automatic`, `.scrollContent`, `.scrollIndicators`)*

Measured in SwiftUI: a `ScrollView` and a grouped `Form` apply content
margins; `List`, `Table`, `TextEditor` and a columns `Form` ignore them
entirely on macOS. TUIkit matches that list. Its grouped `Form` does not
scroll, so there the margins are padding around the sections — the picture a
scrolled-to-the-top SwiftUI form shows.

**What is a judgement:** the indicator half. SwiftUI's scrollers overlay the
content, and a margin moves an overlay. TUIkit's bar is a column (or row) of
the viewport, so:

- a vertical bar is shortened by the top and bottom margins and moved in by
  the trailing one, and the columns it moves in by come out of the content;
- a horizontal bar is shortened by the leading and trailing margins and lifted
  by the bottom one;
- margins too large for the space leave the bar one cell long rather than
  removing it;
- the "N more above / below" lines (`.scrollIndicatorStyle(.text)`, a TUIkit
  style SwiftUI code never asks for) are lines of the viewport, not a
  scroller, and do not move.

I did not measure where an overlay scroller goes under a cross-axis margin —
the probes read geometry, and an idle overlay scroller is not drawn — so
"moved in" follows `NSScrollView.scrollerInsets`, which insets a scroller
from every edge.

**The alternative** is to inset the bars along their axis only, and leave a
trailing margin to the content alone. That keeps every bar at the viewport's
edge, which a terminal user may find more natural; it is a two-line change if
you prefer it.

### B-W10-3. `safeAreaPadding` is padding, or a scroll view's content margin

*`View.safeAreaPadding(_:)` (both), `View.safeAreaPadding(_:_:)`*

As B6 planned. Measured in SwiftUI: on a vertical `ScrollView`,
`safeAreaPadding(15)` puts 15 of content inset at the top and bottom (it
scrolls with the content, and adds to `contentMargins`) and narrows the view
itself by 30 — across its axis it is padding. Nested calls add.

**Shipped:** exactly that geometry, for a `ScrollView` that is the modifier's
content itself or behind modifiers that only set the environment
(`.scrollIndicators`, `.contentMargins`, `.scrollPosition` and the like).
Anything else — including a scroll view behind `.padding` or `.frame`, which
in SwiftUI does not reach the edges the safe area is on — is padded.
`nil` is one cell, what SwiftUI's 16-point default is to `.padding()`.

**What this gives up**, and B6 already accepted: SwiftUI also extends a
`List` or a `TextEditor` into the safe area and insets its rows (measured: a
`List`'s first row moves down 40 under `safeAreaPadding(.top, 40)`, with the
list itself still at the top). Here those are padded whole, so their chrome
moves in with their rows. The fuller version is B6's real safe area.

### B-W10-4. `ScrollGeometry`: the visible area excludes the bars, and a vertical view's content is as wide as it is shown

*`ScrollGeometry` and its members, `View.onScrollGeometryChange(for:of:action:)`*

Every reading matches SwiftUI's as measured (offset before the origin by the
margins, `bounds` and `visibleRect` at the offset, container less the
insets). Two numbers have no SwiftUI counterpart to measure against:

- **`containerSize` leaves out the bars.** SwiftUI's scrollers overlay the
  content, so its visible area is the frame. TUIkit's bar is a column (or row)
  of the viewport, so the area the content is seen through is the viewport
  less the bar, and less the "N more" lines where `.visible` reserves them.
  That keeps the reading apps rely on exact: `visibleRect.maxY` reaches
  `contentSize.height + contentInsets.bottom` at the bottom, and no further.
- **A vertical-only view's `contentSize.width` is the width it lays its
  content out at**, not the content's own width. The content is not measured
  across separately, and a windowed stack's drawn band is not its whole
  width; SwiftUI's would be the content's frame, which for full-width rows
  (the common case) is the same number.

**The alternative** for the first is the whole frame, bars included, which
makes `visibleRect` one cell wider than what can be seen. I don't recommend
it. For the second, a measure of the content's own width every frame a
geometry observer is attached — the cost `contentExtents` already pays for a
horizontally scrolling view. Cheap to add if a use turns up.

The observers' callbacks are a render side effect, as `onGeometryChange`'s
are, so a memo above a reporting scroll view does not keep its picture.
A/B owed on a scroll-heavy scenario with an observer attached; a scroll view
without one pays one emptiness test per frame.

### B-W10-5. Scroll phases: `.interacting` until a quarter of a second of quiet, and no velocity

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
is no touch, no momentum, and TUIkit does not animate scrolling, so an
animated `scrollTo` is a jump here and changes no phase. `velocity` is always
`nil`; SwiftUI's is optional for the same reason.

**What you might want different:**

- *The quiet interval.* Shorter makes "scrolling ended" arrive sooner and
  splits a slow wheel into several scrolls; longer the reverse. It is one
  constant (`ScrollPhase.quietNanos`).
- *A measured velocity* (lines per second over the last few steps) is cheap
  if a use turns up; I did not invent one nobody reads.
- *`.animating`* comes with animated scrolling, which is its own feature.

### B-W10-6. `scrollIndicatorsFlash` returns the view: the indicators are already showing

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

## C. Declined without asking
