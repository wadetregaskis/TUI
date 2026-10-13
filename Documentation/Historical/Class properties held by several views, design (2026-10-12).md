# Class properties held by several views: the design (DYNVCLAIM)

> **Historical (committed 2026-10-12).** The design lane DYNVCLAIM built, condensed
> from the judged design in the maintainers' working notes (`DYNVCLAIM/design.md`):
> its failure catalogue (§2), the design (§4) and the designs it rejected (§9). It
> describes the code as the lane built it, which may have moved since; the live
> record is decisions-DYNVFIX B-DYNVFIX-3, B-DYNVFIX-5 and B-DYNVFIX-6, and
> deviation S6. Where the build departed from this text, a note in *italics* says
> how.

A class `DynamicProperty` — an object a view holds in a property field — can be
held by many views, and one object has one set of stored properties. SwiftUI
installs nothing inside a class (measured: its `@State` is a constant, its
`@Environment` reads its default, and `update()` runs before each holder's body).
TUIkit installs what it holds, and the owner ruled to keep that, together with an
object made anew with each view value (`let pager = Pager()`, session notes
`DYNV2/notes.md` §4.11) and an `@Environment(Model.self)` inside one. Lane DYNVFIX
gave the object's contents to one view at a time, its *claimant*; four review
rounds did not converge on it. Three designs were drawn up and judged; this is the
winner, *swiftui-first*, with grafts from the other two.

## 2. The failure catalogue

"Holder" is a view whose walk reaches the object through a property field. Status
is that of the claim at the DYNVFIX head the design was judged against.

**A. The base bugs, and what must keep working**

1. One object's `@State`, shared by two views: a write through either is the one
   both draw (DYNV bug 3). *Fixed by the claim.*
2. An `@Environment` in an object shown under two environments: a closure made in
   the first view's body must not read the second's (DYNV bug 4). *Fixed.*
3. Objects that reach each other must draw, not exhaust the stack (DYNV bug 8).
   *Fixed.*
4. An object made with each view value keeps its state from frame to frame, and an
   `@Environment(Model.self)` in it resolves — also when the body's
   `Button("Next") { pager.next() }` captures it, whose action the focus ring keeps
   alive through the next frame's walk. *Worked.*
5. A property subclass behind a plain-class field, held strongly, `weak` or
   `unowned`, and an `unowned` class-bound existential, are reached. *Fixed; out of
   scope.*
6. A `weak` object's contents are bound while it lives; once it dies the field
   reads `nil`. *Fixed.*
7. An `update()` that reads the owner's enum through `weak var parent` sees its own
   case. *Fixed.*

**B. Holder changes, measures and the memo**

8. A `ViewThatFits` candidate only measured must not keep the object's state
   under its pruned key. *Fixed.*
9. A memo-served first holder: both holders read the one state. *Fixed.*
10. A pass that walks the tree twice: at rest, the object reads the drawn walk's
    environment. *Fixed.*
11. A holder change (a resize between candidates, a row removed, a tab switched)
    keeps the state from the first frame drawn with the new holder. *Fixed.*
12. A memo-served holder is redrawn by a write: the first holder memo-served while
    the other writes; the holder left memo-served; display-only memoised rows
    beside a detail view that writes. *Open: a write redrew only the claimant.*
13. A detail view moving between memo-served rows' objects keeps each object's
    state. *Fixed for top-level state; open inside an enum case.*
14. An `if`/`else` swapping the holder below the branch root keeps the state.
    *Same.*
15. The holder left is memo-served as the first leaves: the value is kept, and a
    write must redraw it. *Redraw open.*

**C. State identity between objects**

16. A detail view moving to an object never drawn must not bind the previous
    object's box, kept under its key. *Open: two objects shared one state.*
17. Two objects at one place then swapped one box between their holders' keys every
    frame, two scans of the state table a frame, invalidating the wrong view.
    *Open.*
18. In-case state (`enum Mode { case editing(Cursor) }` in the object) bound to
    another object's box. *Open.*
19. In-case state lost when the holder's record of the case did not match the
    object's case. *Open.*
20. In-case state lost across a holder change. *Open for two of four shapes.*
21. A box moved to another holder's key was missing from that holder's case record,
    so a case that left came back with its old state. *Open.*

**D. Reads before resolution, and the environment**

22. A holder's body reading an `@Environment(Model.self)` set on the object since
    any walk reached it trapped, on the measure path. *Open, then guarded.*
23. A holder drawn before the first holder read a stale environment. *Open.*
24. Holders under two environments both read the claimant's in their own bodies.
    *Open by design.*
25. A holder's measure and draw read different environments. *Open.*
26. An environment-scoped action — a sheet's Done calling its page's `dismiss`
    through a shared object — acts for the first holder. *Residual in every
    design.*

**E. Idling, costs, measures and docs**

27. A holder under `.id(UUID())` must leave the app idle. *Idle.*
28. Rows whose identities change every frame paid a scan of the state table per
    `@State` per row, quadratic; an object holding only `update()` took a claim and
    a weak side table every body. *Open.*
29. A memoised successor was not redrawn after the claimant left through a branch.
    *Open.*
30. Costs on the hot paths: an append per memo hit, an index per pass, a chain
    compare per body. *Mostly reverted.*
31. Measures changed ownership and state: a provisional claim made a box under the
    measured view's key. *Open.*
32. Ids inside an object followed the claimant: two objects first claimed at one
    view and field shared them, and they changed with the claimant. *Open.*
33. Stale test names and docs. *Open.*

Edges no review had failed: a value holding a `@State` copied between live objects
(E1); one object in two contexts (E2); a view reading an object no walked field
reaches (E3); objects made lazily inside a body, shown one after another at one
place (E4); a render entry that does not go through the render loop (E5).

## 4. The design

### 4.1 Principle

1. What a class property stores is the object's. A long-lived object's `@State`
   lives in its backing's own box, which no view's key holds, so no measure, memo
   hit, prune, branch flip, identity change or holder change can move, drop or
   share it.
2. The one exception is §4.11: an object made during the pass that walks it takes
   its `@State` from its place, as a view value's does, so the next view value's
   object finds it.
3. Every view drawn holding the object is registered on it, and a write redraws
   all of them.
4. Every holder walks the object before its body, measures included. While its
   body and content run, the object reads that holder's environment; at rest, its
   primary holder's.

There is no claim, successor, hand-off, keep or revival.

### 4.2 Data

- `StateBacking`: `bound`, a one-byte `BackingBinding` — `.unbound` (its own box,
  holding what is written before any walk), `.place` (a box the storage keeps
  under a view's key), `.provisional` (a measure's binding of a per-value object
  to a box its place already keeps), `.own` (an object's own box); and
  `createdIn: UInt32`, the render pass it was made in, from a task local read in
  `init` (`StateRegistration.renderPass`), `0` outside every pass. *Built:
  `malloc_size` of `StateBacking<Int>`, `<String>` and `<Bool>` unchanged, 48
  bytes each.*
- `StateRegistration.renderPass`, bound around each frame by every render entry
  point; not around input dispatch, so an object made in an event handler is
  long-lived.
- `StateStorage`: `currentPass`, a serial from one count for the process, never
  `0`; `objectHubs`, by object, weak-checked and swept of dead objects once
  doubled; the environment restore stack.
- `ObjectHub`, one per storage and object whose class may hold a `@State`,
  `@Environment`, `@FocusState` or `@Namespace`: the object, weakly; the cache's
  link; the holders, counted, under a lock; the id path; the primary holder; the
  primary's environment at rest; a count of the primary's walks. A write calls
  each holder's invalidation.
- `HolderToken`, kept among the storage's values at the holder's identity and a
  reserved index, -140, at the field's scope: it holds the hub, so pruning,
  memo-hit retention and invalidation treat it as the holder's own state; and it
  notes whether the holder's last object at that field was made per value.

### 4.3 Binding a `@State` inside an object

| The backing is | Render walk | Measure walk |
|---|---|---|
| `.own`, its box's sink this object's hub | nothing | nothing |
| `.own`, the sink another live object's hub (E1) | a new backing of its own, at its default | the same |
| `.own`, no sink, or a dead object's hub | sink := this hub | nothing |
| `.unbound`, made in another pass (long-lived) | `.own` on its own box, sink := hub | `.own`, no sink change |
| `.unbound`, made in this pass (per value) | bind the place's box, adopting one already there only if the holder's last object at this field was per value, else putting the backing's own box there; `.place`, sink := hub, set after the storage stamps the box | `.provisional` to a box the place already keeps, if adopting; else unbound |
| `.place` or `.provisional`, made in this pass | keep: the first holder drawn decides (`.provisional` is bound as above) | keep |
| `.place` or `.provisional`, made in an earlier pass | convert: `.own` on a new box holding the value | read through |

A per-value object adopts its place's state only while that place's chain of
per-value objects is unbroken: a long-lived object shown at the field ends it, so
an object made lazily later there starts at its default (E4). *Built (review1 of
the lane): a long-lived object made lazily in the pass it is first shown in looks
per value then, so it keeps the chain going, and the next such object adopted its
box, which the two then shared until one was walked again. Now an adopting
object leaves its live predecessor what the box held, and a walk that finds the
predecessor again gives it that back; the new object's inheriting at its first
show remains (§8.5's residual; decisions-DYNVCLAIM B-DYNVCLAIM-3).*

### 4.4 A holder's walk

Dedupe by the objects reached. A class whose contents hold nothing installable
runs only its `update()`s: no hub, no token. A render walk looks up or makes the
hub, registers the holder (making it primary if the hub has none), and reads the
token's note before walking the leaves and writes it after. The contents are
walked in place, then the object's own `update()` runs, before each holder's body
as SwiftUI runs it. *Built: an object's contents are walked in scopes rooted at the
object, so its ids are the same whichever field and view hold it; a per-value
object's `@State` keys and enum records are made at the holder from those scopes
XORed with the field's.*

### 4.5 Environment

Every walk resolves each `@Environment` inside the object in place. A render walk
by the primary pushes nothing: it stores its environment as the object's at rest,
and counts its walk. Every other walk — a non-primary render, any measure — first
pushes the box's previous environment. After the holder's content, entries pushed
since the holder's mark are popped, last first, at the two places a body's content
is evaluated (the composite render site and the composite measure); the pass's end
pops whatever is left. A pop restores the previous environment, never `nil`; if the
primary walked inside the scope, the object's at rest instead. *Built (review1 of
the lane): a primary nested in another holder's content pushed nothing, so the
outer holder's content after it read the primary's, and every entry pushed before
the primary's walk, a middle holder's too, popped to the object's at rest. Now a
primary walk inside another holder's content pushes the enclosing holder's
environment and sets the box's outermost entry to put the primary's back; only
that entry restores the object's at rest. The hub keeps neither an environment at
rest nor a count of the primary's walks: the environment at rest held the storage,
which keeps the hub, so no storage that drew an object ever went. And the object's
properties that take from the environment but keep it in a store every copy shares
(a `@FocusState`'s focus manager, `@FocusedValue`, `@FocusedBinding`), which no
pop puts back, are resolved by the primary's walks alone, or by any walk before
the object has a primary, as before the lane's C3.*

Whose environment a shared object's `@Environment` reads: during a holder's walk,
its body, and the drawing or measuring of what that body built — that holder's,
the innermost holder's when they nest; anywhere else (event and gesture closures,
tasks, timers, between passes) — the primary's, as of its last render walk; before
any render walk — the last any walk resolved.

Why it is sound: a walk, its body and its content are synchronous on the main
actor, and the only walks that can run in between are of holders nested in that
content, undone last first; a primary served from the memo cannot have changed
environment, which is the memo's condition for serving it; a restore writes only
the box, which nothing observes; and no path sets a resolved box back to `nil`.

The limit: an object has one stored field per `@Environment`, and a closure
reaches it through the object, carrying no holder. So a closure made in a
non-primary holder's body and run later reads the primary's environment (item 26).

### 4.6 Ids

Long-lived objects bind `@FocusState` and `@Namespace` from the hub's id path, so
ids are stable for the object and distinct between objects. Per-value objects bind
from the place. *Built: per-value-ness is known only from a `@State`, and ids may
be met first, so every object binds from its hub's path; a new hub at a field
whose last object was per value, or held no `@State` to say, takes that object's
path, so a chain of per-value objects keeps one set of ids. After review1 of the
lane, only if the new object's first `@State` at a fixed offset, read before its
ids are bound, does not say it was made before the pass; and a hub on a chain's
path takes its own once a walk finds its object long-lived (decisions-DYNVCLAIM
B-DYNVCLAIM-1).*

### 4.7 – 4.9 A memo hit, a write, a pass

A memo hit does nothing new: it retains its subtree's state, the holder's token
among it. A write calls the box's sink, the hub, which invalidates every holder.
Each pass takes a serial; the end of the pass prunes tokens of holders neither
drawn nor retained, clears a primary pruned with its token, pops leftover
restores, and sweeps the hubs of dead objects once the table has doubled. A holder
leaving takes only its token; the object's state is not in the storage's values.

### 4.10 Enums inside objects

Long-lived: an enum's case state lives in its payload's own backings. Setting a
case anew brings new backings at their defaults; a payload kept and put back
brings its state back. No case records are kept. Per-value: their state binds at
place keys, so the walk's case records apply, as for a view value.

### 4.11 Measures

A measure never creates, moves or drops anything keyed by a view. It may mark a
long-lived backing `.own`, give a value copied from another live object its own
backing, and bind a per-value object provisionally to a box its place already
keeps. Its environment writes are undone after its content.

### 4.12 What it removes

The claim (`objectClaims`, `ObjectClaim`, `claimObjectContents`), `keep(_:for:)`
and its scan of the state table, the claim's pass counter and its branches at the
pass's end, in `invalidateDescendants` and in `reset`; `StatePlace`; the claim's
case depth in the walk; and, inside objects, the per-place `@Environment` boxes.

## 9. Rejected designs

- **Object-owned (D1):** the best cost profile for apps without class properties,
  and Observation registration a tidy reuse. Rejected: per-value objects took their
  place's state only from a dead predecessor, which a `Button`'s action prevents;
  closures read the last holder drawn, which changes with draw order and memo hits
  (bug 4 again); and registration cost 0.40 to 0.53 µs per drawn holder body
  (measured), plus a whole-cache clear per holder type learned as reading. Kept
  from it: ids per object, the pure-move first commit, its probes.
- **Lifecycle (D2):** the same dead-predecessor rule, a false premise about the
  focus ring dropping last frame's closures, and the claim, successor, hand-off
  and settle that four rounds had not converged, with a new journal entry replayed
  on every memo hit. Kept from it: ids per object, `invalidateDescendants` leaving
  objects alone, its SwiftUI probe.
- **Also rejected:** walk-history heuristics for §4.11 (a never-drawn long-lived
  object looks exactly like a replacement); a plain process-wide pass counter read
  in `init` (cheaper, but a data race when a `@State` is made off the main actor
  during a pass; kept only as an owner option should the stamp's A/B show it);
  keying object state by the object's identity alone (a freed address comes back).
