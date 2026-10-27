# A class property held by several views

*What happens when one object, held in a class-typed property, is held by
several views: whose writes redraw whom, and whose environment its closures
read. Ids: B-DYNVFIX-3, B-DYNVCLAIM-1 to 3, B-DYNVFIX-3's ruling; the design
of 2026-10-12, appended.*

## In short

What a class property holds is the object's: every view drawn holding it is
redrawn by its writes, each read. An object's ids come from its own path, so
a chain of objects made with a view's values shares one. A closure dispatched
from inside a holder — a click, a key, a gesture, a `.task` — reads that
holder's environment; a timer or a detached task reads the first holder's.

## How it unfolded

1. **2026-10-12, DYNVFIX then DYNVCLAIM:** the claim model (one view at a time
   holds the object's state) was replaced by the design appended below.
2. **2026-10-23, B-DYNVFIX-3:** asked whether to accept the first-holder limit,
   prototype a cheap fix, or build the full per-dispatch identity.
3. **2026-10-26, the owner:** (c), the dispatching identity, prototyped; then
   (b), then (a), if each is too costly after optimisation ("Fine, (c)" after
   my correctness caveat).
4. **2026-10-27, lane DISPATCHID:** (c) built (below, under B-DYNVFIX-3).
   Its A/B, which decides whether it stays, is owed for a quiet machine.

## The record

### B-DYNVFIX-3. What a class property holds is the object's: every view drawn holding it is redrawn by its writes, each reads its own environment while it draws, and an object made with a view value keeps its view's state

*`DynamicProperty`, `@State`, `@Environment`, `@FocusState`, `@Namespace`*

A class property — an object held strongly, `unowned` or `weak` in a field
declared as a `DynamicProperty` class — can be shared by many views, and one
object has one set of stored properties. The walks bound its `@State` and
resolved its `@Environment` for each holding view in turn, so the last view
drawn won: a write through one view's binding landed in another's state, and
a closure made in one view's body read another's environment (DYNV bugs 3 and
4). SwiftUI installs nothing inside a class: its `@State` is a constant, its
`@Environment` reads its default, and `update()` runs before each holder's
body (measured: DYNP `op.out` vii-f;
`Tools/SwiftUIProbes/Class properties held by several views/cls.out`). The
owner asked to keep what TUI supported: a class wrapper made anew with
each view value (session notes `DYNV2/notes.md` §4.11), and an
`@Environment(Model.self)` inside one, which reading uninstalled traps.

**Shipped** (lane DYNVCLAIM, 2026-10-12; its design, condensed, is
`Documentation/Historical/State and dynamic properties/A class property held by several views.md`):

- **The object's state is its own.** A `@State` inside an object made before
  the pass that walks it is bound to a box of the object's own, which no
  view's key holds. No measure, memo hit, prune, `if`/`else` flip, identity
  change or change of the view holding the object moves, drops or shares it:
  two views showing one object read and write one state; a detail view moving
  between objects never binds one object's state to another's; a holder that
  leaves takes nothing with it. The `@State` in an enum's case inside the
  object is the case's payload's: a case set anew starts at its defaults, and
  a payload the app kept and puts back brings its state back, as the object
  stored it. A value holding a `@State` copied from one live object into
  another is given its own, at its default.
- **Every view drawn holding it is redrawn by a write.** Each is registered
  on the object (an `ObjectHub` per object and storage, the sink of the
  object's boxes; a `HolderToken` among the view's own state, at the reserved
  index -140), and stays registered exactly while its own `@State` would be
  kept: drawn, served from the memo, or retained by a container that windows
  its rows. A write redraws each, a row served from the memo included — as
  SwiftUI redraws every view that read an `@Observable` it is written to, one
  behind an `.equatable()` that compares equal included (measured:
  `Tools/SwiftUIProbes/Class properties held by several views/memo.out`).
  Once no view drawn holds it, a write redraws what was above the last to
  leave, as the claim's box, kept for the last claimant, did.
- **An object made with a view value keeps its view's state.** `let pager =
  Pager()`, made anew with each value of the view holding it, is told from an
  object made before by when its `@State` was made (B-DYNVFIX-6): made in the
  pass that walks it, its state is its place's — the box kept under the first
  holder's key, as a view value's `@State` is — so the next value's object
  takes it. Whether the last value's object is still alive says nothing: a
  `Button`'s action holds it through the next frame's walk. An object takes
  the state its place keeps only if the object the view showed there last was
  itself made so; a long-lived object shown at the place ends that chain, so
  an object made later at the place starts at its default. One that outlives
  the pass it was made in moves to a box of its own, with its value, at its
  next walk — or, if the object made next at its place took that box over,
  with what it held then (decisions-DYNVCLAIM B-DYNVCLAIM-3).
- **Every holder walks it before its body**, measures included: its `@State`
  as above, its ids, its nested properties' `update()` in place, then its own
  `update()`. A measure creates, moves and drops nothing a view's key holds
  for an object: no registration, no place box, no case record. An object
  whose class holds nothing a walk installs — only an `update()` — is not
  registered at all.
- **Ids.** Its `@FocusState` and `@Namespace` ids are made from the object's
  own path, so they are the same whichever view draws it, and two objects
  never share theirs (B-DYNVFIX-5). An object made with a view value takes the
  ids of the chain of such objects at its place; one found made before the
  pass, by the first `@State` in it, never does, and one that took them gives
  them up for its own once a walk finds it so (decisions-DYNVCLAIM
  B-DYNVCLAIM-1).
- **Environment: each holder's while it draws, the first holder's at rest.**
  Every holder's walk, measures included, resolves each `@Environment` in the
  object, in place, to that holder's environment. A walk other than a render
  walk by the object's primary holder — the first view drawn holding it, for
  as long as it holds it — notes what each box held, and the two places a
  body's content is evaluated (a composite view's render and its measure) put
  it back, last first, after the content; the end of the pass puts back what
  is left. The primary's render walk notes nothing outside other holders'
  content; inside one, it notes the enclosing holder's environment, put back
  after the primary's content, and the outermost note for the box puts the
  primary's back, as the object's at rest. A box is never put back to `nil`.
  So:
  - during a holder's walk, its body, and the drawing or measuring of what
    that body built, the object reads that holder's environment — the
    innermost holder's where holders nest, the outer one's again after the
    inner one's content;
  - anywhere else — an event's or a gesture's closure, a task, a timer,
    between passes — it reads its primary's, as of the primary's last render
    walk;
  - before any render walk, the last environment any walk handed it. A
    property set on the object since any walk reached it is resolved by the
    first walk that does, a measure included: its `@Environment(Model.self)`
    never traps for want of one (review5 of DYNVFIX, S1).

  Its other properties that take from the environment — a `@FocusState`'s
  focus manager, `@FocusedValue`, `@FocusedBinding` — keep what they take in
  one store every copy shares, which nothing puts back. No walk drawn as a
  backdrop hands them in — the page beneath a modal, a covered navigation
  root, a `.dimmed()` view — whose focus manager focuses nothing and goes
  with the frame, so a focus set from a closure through it would go nowhere.
  Of the rest, the primary's walks, or any walk before the object has a
  primary, hand them in: the object reads its primary's, never a later
  holder's. While the primary is drawn as a backdrop — a page holding the
  object behind a sheet that holds it too, the page drawn first, at its own
  identity — another holder's walks hand them in (review2 of lane DYNVCLAIM,
  748e897b2); one drawn before the primary in a pass goes by the primary's
  last walk. A walk that hands them nothing still tells the memos above its
  holder that the holder's body reads the object's `@FocusedValue` or
  `@FocusedBinding`, as handing it in does: what it reads follows the focus,
  which no memo keys on. Without that, a page behind a sheet, or a row a memo
  keeps that is not the primary, kept what it drew after the focus moved
  (review of 75c2c226c, S3).

  Why it is sound: a walk, its body and its content run synchronously on the
  main actor, and the only walks that can run in between are those of holders
  nested in that content, put back last first; a primary served from the memo
  cannot have changed environment, which is the memo's condition for serving
  it, so draw order and memo hits never change what closures read; and a
  restore writes only the box, which nothing observes, so it redraws
  nothing. Inside an object there is one box per `@Environment`: the
  per-place boxes a view value's `@Environment` gets (B-DYNVFIX-5) are not
  made there.

**Price.** Measured on 2026-10-13, against the batch before the lane (15 reps,
indicative): nothing slower than +0.5% in the full sweep, and the stripped
binary grew 33 KB. The `stateful` variants without objects were
indistinguishable. With objects, `shared-objects` was 1.5% faster warm and 3.2%
slower cold, and `identity-churn` (a synthetic worst case: an object made anew
for every identity each frame) 1.0% slower warm and 8.9% slower cold (CI 7.5 to
9.3). The lane landed on that, correctness before speed; why cold is so much
slower than warm there was queued for a profile on 2026-10-13.

- Every app: each `@State` notes its pass (B-DYNVFIX-6); and before and after
  every composite body's content, drawn or measured, a load of the restore
  count and a compare.
- An app holding class properties, per object a holder's render walk reaches:
  a lookup of its hub (a hash, a weak load, a compare) and of the view's
  token; per `@State` in it, a load and a pointer compare. A write takes a
  lock and invalidates each holder, usually one to three. Per `@Environment`
  in an object, a store per walk, and for a walk other than the primary's
  render walk a note and its restore; for the primary's render walk inside
  another holder's content, a scan of the notes waiting for the box's
  outermost, and a note. An object made with
  each view value brings a hub (about 64 bytes, estimated) a pass, swept once
  the table has doubled. Nested properties' `update()` inside an object runs
  once per holder walk, as the object's own does; the claim ran them for one
  holder.
- Gone: the claim's scan of the state table whenever a box changed keys —
  quadratic in the row count for rows whose identities change every frame —
  and the weak reference, a side table, every body for an object holding only
  an `update()`.

**Left:**

- A closure made in a holder other than the primary reads the primary's
  environment: a sheet sharing its page's object and calling the object's
  `dismiss` calls the page's, and stays open. Read such an action in the view,
  or hold it in a struct property. When the primary leaves, closures read its
  last environment until the next holder drawn becomes primary, a pass later;
  bodies never lag.
- One object drawn by two contexts: a box has one sink, so a write redraws
  the context that walked the object last. Nothing is lost.
- A view reading an object no walked field reaches — through an `@Observable`
  store, or only from a closure: its `@Environment` is unresolved, and a write
  redraws it only if it lies above the last view drawn holding the object (of
  several that stopped in one pass, whichever the prune dropped last, in no
  set order), or below one still holding it; one no view has ever been drawn
  holding redraws nothing, as before.
- A holder that stops reaching an object without leaving the tree — an
  optional set to `nil`, a case of its own enum left — stays registered until
  it leaves: a write redraws it needlessly.
- A holder whose body a container takes apart rather than draws — a stack or
  a section taking it into its members, a `List` asking it for its rows, a
  `Form` reading its rows through it — or a guide asks for: what its walk
  hands the object's `@Environment`s is put back only after the content of
  the composite around the container, or at the end of the pass. Until then
  its members, and the views drawn after them there, read that holder's
  environment, or a later such holder's: the container draws the members
  among its other children, with no point after one holder's members to put
  it back at.
- An object made on demand in a body and kept — a detail view's model from
  `store.model(for: selection)` — first shown in the pass it was made in,
  looks made with the view's value: if the object the view showed there
  before looked so too, the new one starts from the state the place keeps,
  that object's, not from its defaults. That object, shown again, takes back
  what it held when the new one took the place's state; what was written to
  either in between, through the box they shared, is the new one's
  (decisions-DYNVCLAIM B-DYNVCLAIM-3).
- An object made with a view value is a new object every pass, and a holder
  served from the memo stays registered on the one it last walked, so a write
  to the new one does not redraw it. Only a holder whose `==` ignores the
  object it holds can be served with a new one.
- An object holding no `@State` cannot say whether it was made with a view
  value, so its ids follow the chain at its place: two long-lived objects
  holding none, shown one after the other by one view, share their ids, as
  every object's did under the claim. One made on demand in a body and first
  shown in the pass it was made in shares the chain's for that pass
  (decisions-DYNVCLAIM B-DYNVCLAIM-1).
- A measure made before any render walk reached a long-lived object binds no
  ids: its body reads an unbound `@Namespace` there, and the render binds it.
- A holder whose walk hands the object's `@FocusState` manager,
  `@FocusedValue` and `@FocusedBinding` nothing reads them as the last walk
  that did left them. Its walk still tells the memos above it that it reads a
  `@FocusedValue` or `@FocusedBinding`, so it is drawn again when the focus
  moves. Behind a sheet, the object reads the live focus once any walk has
  handed it the live manager, where a page's own `@FocusedValue` reads the
  backdrop's manager, which focuses nothing.
- The windowed stack's focus-reach probe renders the rows past the focused
  one against a scratch focus manager of its own, not drawn as a backdrop,
  that goes with the probe (`StackFocusReach.swift`). A row it renders that
  hands the object those properties — the object's primary, or, while the
  primary is drawn as a backdrop, any holder — hands them that manager. The
  next walk in the pass to hand them in replaces it, so it bites only when
  the probe's row is the last: until the next pass, the object's
  `@FocusState` reaches no focus that a `.focused` did not wire, and its
  `@FocusedValue` and `@FocusedBinding` read nothing.

**Not chosen:**

- *The claim* — the first walk, then the first view drawn in each pass,
  holding the object's state under its key, in four variants (reviews 1 to 5
  of DYNVFIX, 2026-10-12): a measure-only candidate took it and its key was
  pruned; a memo-served first holder lost it; a claimant drawn in an earlier
  pass kept it a pass too long; the boxes it moved between keys were dropped,
  or taken by another object never bound, and a write redrew only the
  claimant. Each fix opened the next hole.
- *Registering holders through Observation*: 0.40 to 0.53 µs per holder body
  drawn (measured: session notes `DYNVCLAIM/object-owned/obs.out` and
  `marginal.out`), and closures
  reading the last holder drawn, which changes with draw order and memo hits:
  bug 4 again.
- *Taking a place's state only from a predecessor that has died*: a closure
  holding the last value's object — a `Button`'s action, kept by the focus
  ring — keeps it alive, so the object made with each value would restart
  every frame.
- *Keying the object's state by its identity alone*: a freed object's address
  comes straight back (memory note memo-key-hashes-an-address).
- *SwiftUI's, installing nothing*: loses §4.11 and the environment model.

**The fuller version** for closures: a dispatching identity set around every
key, mouse, gesture and task dispatch, and a table of environments by holder
in each object's box, so a closure reads its own holder's. Its price: a branch
on every `@Environment` read in every app, and dispatch plumbing; and it is
still wrong for closures run from timers or detached tasks. A cheaper
candidate, unbuilt and unmeasured: at the end of each pass, make primary the
holder whose subtree holds the focused element.

**Fuller version built (lane DISPATCHID, 2026-10-27; option (c), the owner's
ruling of 2026-10-26).**

- **The dispatching identity.** `StateRegistration.dispatchingIdentity`, a
  task-local, is the view a closure runs for:
  - a key runs as from the focused view (`InputHandler.handle`);
  - a mouse handler, offered an event or handed the rest of its press, runs
    as from the view that registered it, which the handler-id table now
    remembers (`MouseHandlerIDTable.owners`);
  - a gesture's callbacks run as from its view (`GestureArena.Contender.owner`);
  - a `.task` is started inside the scope, so the `Task` carries it.
- **The environments.** Each render walk notes its holder's environment in
  the object's `@Environment` boxes (`EnvironmentBox.noteEnvironment`). They
  are kept in the box, with the object, not on the hub, which the state
  storage keeps: an environment holds the storage, and a hub holding one
  never let the storage go (`DynamicPropertyObjectEnvironmentTests`' leak
  test). A holder that no longer holds the object is forgotten at the next
  note.
- **The read.** While a dispatch runs, an object held by more than one view
  reads the environment of the innermost holder that is the dispatching view
  or one of its ancestors. Elsewhere it reads the box's, as before: its own
  holder's while it draws, the primary's at rest. An `@Environment` outside
  every object pays one test of its box's holder count.
- **Still the primary's:** a timer, a detached task, GCD, a hover handler
  (`onHover`, `.help`, which the prototype does not bind), and a held press's
  click on a pane's background (`PressRole`).

**Owed:** the A/B. The ruling keeps (c) only if its cost after optimisation
is acceptable, falling back to (b) and then (a). The tests are
`DispatchedObjectEnvironmentTests`.

### B-DYNVCLAIM-1. An object's ids are made from its own path, and a chain of objects made with a view's values shares one

*`@FocusState`, `@Namespace` inside a class `DynamicProperty`*

The design binds a long-lived object's ids from a path of the object's own,
and a per-value object's — one made anew with each value of the view holding
it — from its place, so the next value's object keeps them. But whether an
object is per-value is known only from a `@State` it holds, when the walk
reaches one (`StateBacking.createdIn`), and a `@FocusState` can be declared
before it, or with none at all.

**Shipped:** every object's ids are made from its hub's path (`ObjectHub.idPath`,
`obj` and a count per storage). A hub made at a field whose last object looked
per-value, or held no `@State` to say, takes that object's path — joins its
chain — unless the new object says it was made before the pass: its first
`@State` at an offset fixed for its class (not behind an optional, an
existential, an enum's case or another object), read before any of its ids is
bound, was not made in the pass, or is already the object's own
(`FieldsPlan.objectKind(at:in:)`). So a chain of per-value objects at one
place keeps one set of ids from frame to frame, as the design wants; a
long-lived object ends the chain, and gets ids of its own, though the object
before it looked per-value only because it was made in the pass it was first
shown in (a `@State` initial value in the first frame; review1 of lane
DYNVCLAIM, a7d1f8e75 (a)). A hub on a chain's path takes one of its own once a
walk finds its object made before the pass: at the walk's start where its
first `@State` says so, at its end otherwise. Before, it kept the chain's for
good (review1, ac4bf0644).

**Left:**

- An object made on demand in a body and kept, first shown in the pass it was
  made in after an object that looked per-value at the same place, looks
  per-value too: it shares that object's ids for that pass, as it takes its
  place's state (B-DYNVCLAIM-3), and has its own from its next walk on. Its
  `@FocusState` and `@Namespace` ids so change once, after that pass: what
  that frame keyed by them — a `@FocusState`'s mapping in the focus manager,
  a `matchedGeometryEffect` pairing — is keyed by the new ones a frame later
  (review2 of lane DYNVCLAIM, 69d852485).
- An object whose `@State` lies only behind an optional, an existential, an
  enum's case or a nested object says what it is only when the walk reaches
  that: it may share a chain's ids for the one walk that finds it long-lived.
- An object holding no `@State` cannot say whether it was made with a view
  value, so it always joins the chain at its field: two long-lived objects
  holding a `@FocusState` or `@Namespace` but no `@State`, shown one after the
  other by one view, share their ids — as every object's did under the claim.
- A measure that reaches a long-lived object before any render walk did binds
  no ids, so a body reads an unbound `@Namespace` in that measure, and the
  render binds it.

**The fuller version:** `@FocusState` and `@Namespace` note the render pass
they were made in, as `@State` does, so every object can tell, and the first
of them at a fixed offset says so before any id is bound. Its price: a
task-local read in each one's `init`, in every app — every view holding a
`@FocusState` makes one per value — 4.5 to 7.7 ns each (measured for
`@State`: `Tools/SwiftUIProbes/Swift runtime layouts/stamp.out`), a `UInt32`
in each one's store, and a new requirement on the public
`RenderIdentityBindable`, or a package one beside it.

### B-DYNVCLAIM-2. A holder served from the memo is redrawn by a write to the object it last walked, not to one made with a later view value

*Class `DynamicProperty` made anew with each view value*

Every view drawn holding an object is registered on that object's hub, and
stays registered while its own state is kept, a memo hit included. An object
made with each value of the view holding it is a new object, with a new hub,
every pass; a holder served from the memo in a pass walks nothing, so it stays
registered on the object it walked last. A write to the new object's state
redraws the holders that walked it in its pass, and not that one.

**Shipped:** as designed. Only a holder whose `==` ignores the object it holds
can be served with a new one — `ForEach`'s rows and `.equatable()` views that
compare the object by identity draw it anew — so the holder shows the value of
its last drawing until something else redraws it.

**The fuller version:** a hub made for an object that joins a per-value chain
takes the holders of the chain's last hub, so a write to any object of the
chain redraws every holder of the chain. Its price: a copy of the holder table,
under its lock, per such object per pass, on the per-value path alone; and a
holder that has left stays in the new hub's table until that hub's object goes,
a pass later, so a write in between redraws an identity no longer drawn, which
costs a lookup and does nothing.

### B-DYNVCLAIM-3. An object made on demand and taken for one made with a view value gives back what it took over

*Class `DynamicProperty` made on demand in a body*

An object made with each value of the view holding it (session notes
`DYNV2/notes.md` §4.11) is told from one made before by when its `@State` was
made: in the pass that walks it (B-DYNVFIX-6). An object made on demand in a
body and kept — a detail view's model from `store.model(for: selection)` —
and first shown in the pass it was made in looks the same there. If the object the view showed at that place before
looked so as well, the new one took the place's box, which was that object's,
and the two shared it: what the new one wrote was the old one's, and the old
one, shown again, moved to a box of its own holding the new one's value
(review1 of lane DYNVCLAIM, a7d1f8e75).

**Shipped:** the new object still takes the place's box: nothing in that pass
tells it from one made with the view's value, and a `Button`'s action keeps the
last value's object alive through the next frame's walk, so neither does
whether the old object is alive. But the old object, if alive, is left what
the box held then (`ObjectHub.keep(_:handedOverWith:)`): a walk that finds it
again — so it outlived its pass, and was never made with a view value — takes
that back rather than the box. The design's §8.5 residual stays: the new
object starts from the old one's state, not its defaults, and what is written
to either before the old one is walked again goes into the box they share and
is the new one's.

**Price:** on the per-value path alone, per `@State` of an object taking its
place's box while the last one is alive (a `Button`'s action keeps it so), a
box made and a dictionary entry on the old object's hub, which go with that
hub once the object has gone and either the hub table is swept or an object
made at the gone one's address takes its entry; nothing for an app holding no
object made in a pass. The sweep waits for the table to double, and in the
common form the allocator hands the new objects a few freed addresses round,
so the table holds a handful of hubs and is not swept: a gone object's hub
waits for its address to be given again, which may never come (the loop of
`perValueObjectsHubGoesAfterTheNextOneTookItsPlace`, unpinned: its first hub
stayed in 12 runs of 20, its object gone, held by its entry alone). Bounded:
after a pass, the table holds at most 64 hubs past twice what the last sweep
kept. The box is kept with no sink until a walk takes it back: sunk to the
hub that keeps it, the two kept each other, and every such pass leaked a hub
and its boxes (review2 of lane DYNVCLAIM, d29a46eaf). One left to an object
walked earlier in the same pass, which has a box of its own by then, is never
taken, and stays until the object goes.

**The fuller version:** none without losing §4.11's common form. Taking a
place's state only from a predecessor that has died tells the two apart only
where nothing keeps the old object alive, and a `Button`'s action holding it
does (the design's option (c), §10): such objects would restart every frame.

## Appendix: the class properties design (2026-10-12)

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
TUI installs what it holds, and the owner ruled to keep that, together with an
object made anew with each view value (`let pager = Pager()`, session notes
`DYNV2/notes.md` §4.11) and an `@Environment(Model.self)` inside one. Lane DYNVFIX
gave the object's contents to one view at a time, its *claimant*; four review
rounds did not converge on it. Three designs were drawn up and judged; this is the
winner, *swiftui-first*, with grafts from the other two.

### 2. The failure catalogue

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

### 4. The design

#### 4.1 Principle

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

#### 4.2 Data

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

#### 4.3 Binding a `@State` inside an object

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

#### 4.4 A holder's walk

Dedupe by the objects reached. A class whose contents hold nothing installable
runs only its `update()`s: no hub, no token. A render walk looks up or makes the
hub, registers the holder (making it primary if the hub has none), and reads the
token's note before walking the leaves and writes it after. The contents are
walked in place, then the object's own `update()` runs, before each holder's body
as SwiftUI runs it. *Built: an object's contents are walked in scopes rooted at the
object, so its ids are the same whichever field and view hold it; a per-value
object's `@State` keys and enum records are made at the holder from those scopes
XORed with the field's.*

#### 4.5 Environment

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
the object has a primary, as before the lane's C3 — and (review2) by no walk
drawn as a backdrop, whose focus manager focuses nothing, and by another
holder's while the primary is drawn as one: a modal draws the page beneath it
first, at the page's identity, so the page is the primary. A walk that resolves
none of them still tells the memos above its holder that the holder reads a
`@FocusedValue` or `@FocusedBinding`, which follows the focus (review of
75c2c226c).*

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

#### 4.6 Ids

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

#### 4.7 – 4.9 A memo hit, a write, a pass

A memo hit does nothing new: it retains its subtree's state, the holder's token
among it. A write calls the box's sink, the hub, which invalidates every holder.
*Built (review1 of the lane): once no holder is left, the last to leave, as the
claim's box redrew its last claimant's place.*
Each pass takes a serial; the end of the pass prunes tokens of holders neither
drawn nor retained, clears a primary pruned with its token, pops leftover
restores, and sweeps the hubs of dead objects once the table has doubled. A holder
leaving takes only its token; the object's state is not in the storage's values.

#### 4.10 Enums inside objects

Long-lived: an enum's case state lives in its payload's own backings. Setting a
case anew brings new backings at their defaults; a payload kept and put back
brings its state back. No case records are kept. Per-value: their state binds at
place keys, so the walk's case records apply, as for a view value.

#### 4.11 Measures

A measure never creates, moves or drops anything keyed by a view. It may mark a
long-lived backing `.own`, give a value copied from another live object its own
backing, and bind a per-value object provisionally to a box its place already
keeps. Its environment writes are undone after its content.

#### 4.12 What it removes

The claim (`objectClaims`, `ObjectClaim`, `claimObjectContents`), `keep(_:for:)`
and its scan of the state table, the claim's pass counter and its branches at the
pass's end, in `invalidateDescendants` and in `reset`; `StatePlace`; the claim's
case depth in the walk; and, inside objects, the per-place `@Environment` boxes.

### 9. Rejected designs

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

