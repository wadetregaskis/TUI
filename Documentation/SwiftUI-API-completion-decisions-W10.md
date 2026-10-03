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

## C. Declined without asking
