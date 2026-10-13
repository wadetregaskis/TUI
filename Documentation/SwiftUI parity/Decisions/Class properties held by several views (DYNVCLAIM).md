# Completing the SwiftUI API: decisions from lane DYNVCLAIM

*Lane DYNVCLAIM, 2026-10-12, replaced the claim lane DYNVFIX gave a class
property's contents — one view at a time holding the object's state under its
key — with the judged design condensed in
[`Documentation/Historical/Class properties held by several views, design (2026-10-12).md`](<../../Historical/Class properties held by several views, design (2026-10-12).md>):
the object's `@State` is its own, every view drawn holding it is redrawn by its
writes, each reads its own environment while it draws, and an object made with
a view value keeps its view's state. The rule shipped is recorded in
decisions-DYNVFIX B-DYNVFIX-3, B-DYNVFIX-5 and B-DYNVFIX-6. These are the
calls the lane made where the design left one open. The format is that of the
main decisions file:*

- **A-DYNVCLAIM-n — needs your decision.**
- **B-DYNVCLAIM-n — shipped the safe option.** Says what the fuller version
  would be, and its price.
- **C-DYNVCLAIM-n — declined.** With the reason.

## B. Shipped the safe option

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
