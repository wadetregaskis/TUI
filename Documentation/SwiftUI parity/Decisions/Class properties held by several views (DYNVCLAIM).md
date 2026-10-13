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
`obj` and a count per storage). A hub made at a field whose last object was
per-value, or held no `@State` to say, takes that object's path: a chain of
per-value objects at one place keeps one set of ids from frame to frame, as
the design wants. A long-lived object ends the chain, so the next object made
there gets ids of its own.

**Left:** an object holding no `@State` cannot say whether it was made with a
view value, so it always joins the chain at its field: two long-lived objects
holding a `@FocusState` or `@Namespace` but no `@State`, shown one after the
other by one view, share their ids — as every object's did under the claim.
And a measure that reaches a long-lived object before any render walk did binds
no ids, so a body reads an unbound `@Namespace` in that measure, and the
render binds it.

**The fuller version:** `@FocusState` and `@Namespace` note the render pass
they were made in, as `@State` does, so every object can tell. Its price: a
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
