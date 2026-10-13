# Completing the SwiftUI API: decisions from lane DYNVFIX

*Lane DYNVFIX, 2026-10-12, fixed the ten dynamic-property bugs the DYNV
research confirmed (session notes `DYNV/notes.md`, `DYNV2/notes.md`), keeping
every reach TUIkit supported, as the owner asked: "Take the best of both as
much as you can; 'hybrid', but try not to lose anything that we currently
support, even if SwiftUI doesn't support it." The property walk is now
planned once per type from the runtime's field metadata (`PropertyPlans`),
not reflected from each value with `Mirror`. SwiftUI's behaviour was measured
with SwiftUI 6.5.4 on macOS 15.8.1 with offscreen `NSHostingView`s (probes in
the session notes, `DYNV/probe/`, `DYNP/optional/`). The format is that of
the main decisions file:*

- **A-DYNVFIX-n — needs your decision.**
- **B-DYNVFIX-n — shipped the safe option.** Says what the fuller version
  would be, and its price.
- **C-DYNVFIX-n — declined.** With the reason.

## B. Shipped the safe option

### B-DYNVFIX-1. A property subclass behind a plain class field is reached through its object's class each body, held strongly, weak or unowned

*`DynamicProperty`*

A field declared as a plain class, `let delegate: RowDelegate`, can hold a
subclass that is a property, `CachingRowDelegate: RowDelegate,
DynamicProperty`. TUIkit's walks found it from the value, but kept a view type
as holding nothing when its first value held a plain instance there, so
whether the property was ever updated depended on the first value drawn
(DYNV bug 10). SwiftUI never looks: it decides by the declared type
(measured, `DYNV/probe/dv2-main.out`, `subclass`: never updated; declared as
the subclass, updated).

**Shipped:** TUIkit keeps the reach (the owner's ruling: keep what TUIkit
supports). Each body, a field whose declared type is a plain class has its
object's class read; an object of a subclass that is a property is walked as
any class property is (B-DYNVFIX-3) — its `@State` bound, its `@Environment`
resolved, its `update()` run — whatever the field held first. An
`@Environment(Model.self)` in such a subclass, which traps when read
unresolved, reads the model. A class found not to be a property is noted in
the field's plan, so the next body that finds it there reads no further. A
Core Foundation or Objective-C class is not looked into: no Swift subclass of
it is declared there.

How the field holds the object decides how its class is read. The field
metadata says of a field only whether it is strong, so the ownership is read
from the field's mangled type name in its field descriptor, once per type
(`Xw` for `weak`, `Xo` for `unowned`, `Xu` for `unowned(unsafe)`;
[FieldDescriptors.swift](../Sources/TUIkitView/Rendering/FieldDescriptors.swift)):

- **Strong:** the class is read where the reference lies.
- **`weak`**, a plain class or a class-bound existential (`weak var delegate:
  (any RowDelegating)?`): the object is loaded each body, through the
  runtime's own reflection entry point — `nil` once it has gone — and its
  class read. It is not updated, as a property held `weak` is not.
- **`unowned`:** the class is read where the reference lies, whose memory the
  unowned count keeps, dead or alive. An object of a class that is not a
  property is never loaded, so a dead one never traps (DYNV bug 9); one of a
  property subclass is loaded as Swift loads it, and traps if it has gone, as
  a dead `unowned` property does (decided for a field declared as a property
  class). It is updated, unless the field is optional.

**Not reached:**

- `unowned(unsafe)`: nothing keeps the object's memory, so nothing of it is
  read.
- `unowned` of a class with an Objective-C ancestor, on Apple platforms:
  the runtime keeps such a reference as an Objective-C weak reference, which
  only the runtime reads, and it traps on one whose object has gone. A class
  with none, and every class on Linux, is read in place.
- `unowned` of an existential: on Apple platforms it is kept the same way
  whenever its object could be an Objective-C one, and elsewhere it is left
  out with it, its storage unmeasured.
- A field whose descriptor cannot be read: where pointers are signed
  (arm64e, which TUIkit does not build), and in a module built without
  reflection metadata, whose fields are not listed at all.

The fuller version, for `unowned` on Apple platforms, checks whether the
object has gone before loading it. The runtime's check (`swift_isDeallocating`)
is a name the compiler reserves (binding it warns that it "will become an
error"), so it would mean reading the object's reference count bits, whose
layout is the runtime's private one.

**The price**, per body, per such field: a load of the reference and of its
class and a compare, held strongly or `unowned`; a call into the runtime's
reflection, held `weak`. In every view holding an object — an `@Observable`
model passed as `let model: Model` among them. A view holding nothing else
the walk acts on, held strongly or `unowned`, is probed where it lies before
any copy of it is made (`SlotPlan.probes`), and evaluated as it is when its
objects are of their declared classes; one holding an object `weak` is copied
and walked on every body. Unmeasured: the A/B is owed.

### B-DYNVFIX-2. An `indirect` enum case's payload, and every payload on WebAssembly and Windows, is updated on a copy

*`DynamicProperty`*

An enum's payload is now walked where it lies: projected out through the
enum's value witnesses, updated, and its case put back, so what `update()`
changes in it is written back, as SwiftUI writes it (DYNV bug 6;
decisions-DYNP B-DYNP-1). An enum in a class property's storage is walked so
on a copy and assigned back: while its payload is projected out the field
holds no valid value, and an `update()` in the payload can read it through
the object. The calls were measured on macOS arm64 only; Linux, on arm64 and
x86_64, follows from the calling conventions and is not measured.

**Shipped:** two kinds of payload are still walked on a copy the runtime
makes, as every payload was before. Their `@Environment` is resolved and
`update()` runs, but what `update()` changes in the payload's own values is
not written back.

- An `indirect` case's payload lies in a box every copy of the enum shares.
  Written in place, it would change the caller's value and every copy of it
  (`DynamicPropertyCopyGuardTests`).
- On WebAssembly an indirect call checks the callee's signature, and a
  value witness, a `swiftcc` function, does not match the C function type it
  is called through here. Windows was not measured. Both use the copy.

**The fuller version:** for an `indirect` case, allocate a new box holding the
updated payload and store it in the view's copy of the enum. That needs the
box's layout, or the runtime's `swift_allocBox` and `swift_projectBox`, whose
names the compiler reserves to itself (binding one warns that it "will become
an error"; session notes `DYNVFIX/probe/pb.swift`). For WebAssembly, a call
through the `swiftcc` convention: a `@convention(thin)` function type, which
Swift does not offer.

### B-DYNVFIX-3. What a class property holds belongs to one view, the first drawn in each pass that reaches it, and its state goes with it

*`DynamicProperty`, `@State`, `@Environment`*

A class property — an object held strongly, `unowned` or `weak` in a field
declared as a `DynamicProperty` class — can be shared by many views, and one
object has one set of stored properties. The walks bound its `@State` and
resolved its `@Environment` for each holding view in turn, so the last view
drawn won: a write through one view's binding landed in another's state, and
a closure made in one view's body read another's environment (DYNV bugs 3 and
4). SwiftUI installs nothing inside a class (measured, DYNP `op.out` vii-f).
The owner asked to keep what TUIkit supported: a class wrapper made anew with
each view value (session notes `DYNV2/notes.md` §4.11), and an
`@Environment(Model.self)` inside one, which reading uninstalled traps.

**Shipped:** what the object holds belongs to one view at a time, its
claimant: in each render pass, the first view drawn whose walk reaches the
object. A view only measured — a `ViewThatFits` candidate, the first frame's
walk for the window chrome — never takes it from another view, and claims it
only until a view drawn reaches it. When a view drawn takes it from another
— a claimant that has left (a `ViewThatFits` switch on a resize, a row
removed, a tab switched), or is only measured or served from the memo in
this pass — the object's `@State` goes with it: each box it holds is kept
under the new claimant's key from then on, so the new claimant draws the
object's state, and what it writes is kept. The claimant walks what the
object holds on each of its own walks — its
`@State` bound to the claimant's key (its identity, and the object's position
and type there, as before), its `@Environment` resolved to the claimant's
environment, its nested properties updated in place — and the last walk of a
pass that walks the tree twice decides. Every other holder leaves it as the
claimant left it, so all holders read and write one state — one object, one
state — and an object made anew per view value, held by that view alone,
keeps its state from frame to frame. The object's own `update()` still runs
before each holder's body, as SwiftUI runs it.

A claim with no holder drawn lasts while the claimant's state does: it is
dropped at the end of a pass in which the claimant was neither drawn nor kept
(by a memo hit, or a container that windows its rows), and the next holder to
reach the object claims it then. The object's state is not dropped with the
claim. Each `@State` box the object holds is the object's: the storage keeps
it under its claimant's key, and keeps it again, with its value, under the
key of whichever view next claims the object, however the storage came to
drop it — a holder served from the memo in the pass its claimant left (it
walks nothing, and cannot take the claim), an `if`/`else` that swapped the
holder and dropped the old branch's state, or another object's box given the
claimant's key (a detail view moving from one row's object to the next). Only
a `@State` inside an enum's case inside the object starts again at its
default then, as a case's state does when its case comes back: a dropped box
there cannot be told from one whose case left. The record holds each object
weakly, so an object at a freed one's address is never taken for it.

Two holders under different environments both read the claimant's. That is
the rule's price, and the reason it is not "per reading view": a closure made
in a view's body reads the object when it runs, after every holder has drawn,
and nothing then says which view it came from. And a write to the object's
`@State` redraws the claimant, as a `@State` write redraws the view it is
keyed to; another holder served from the memo draws the new value when it is
next drawn for another reason.

**Not chosen:**

- *Keyed by the object's identity*: a freed object's address comes straight
  back (memory note memo-key-hashes-an-address), and an object made per view
  value would start afresh every frame, losing §4.11.
- *The last view's, as before*: bug 4 — a closure in the first view reads the
  second view's environment.
- *The first walk in each render pass*, as this lane first shipped it: a
  measure is a walk, so a candidate measured and never drawn took the claim
  every pass, its key pruned at each pass's end and the drawn candidate's
  writes with it; and a holder served from the memo walks nothing, so on such
  a frame the next holder took the claim and the object's `@State` flipped to
  that holder's key, at its default (review, 2026-10-12). Measures now never
  take a claim from another view, and the state goes with a claim.
- *The first view drawn, for as long as its state lives*, as this lane next
  shipped it: a claimant drawn in an earlier pass kept the claim in a pass
  that only measured it, or did not reach it, so the view drawn instead read
  the old claimant's state for that pass and claimed a pass late, at its
  default, and a write it made in between went into the old claimant's box,
  dropped with it (review of 5af4853ba, 2026-10-12).
- *SwiftUI's, installing nothing*: loses §4.11 and the environment model.

**The fuller version:** none found that gives each holder its own environment
in closures. Within `body`, each holder could read its own by resolving the
object for the body and restoring it after; closures and anything evaluated
later (a `ForEach` row, a `GeometryReader`) would then read the restored one,
which is less coherent than one environment per object.

### B-DYNVFIX-4. A stored modifier's properties are updated only where the modifier is applied

*`ViewModifier`, `DynamicProperty`*

The walks looked inside every `ViewModifier` value, so a modifier stored in a
view's field had its properties bound, resolved, updated and written back as
the view's — and then the copy the view's body applied was updated again: its
`update()` ran twice per body (DYNV bug 5). TUIkit's own `.transaction(_:)`
and `.animation(_:)` store the modifier they wrap, and `.concat(_:)` the two it
joins, so they did the same. SwiftUI updates only the copy applied, once
(measured: DYNP `op.out` vii-c2; DYNV `dv2-main.out`, `txn`, `concat`).

**Shipped:** a modifier is *applied* only as the `modifier` of the
`ModifiedContent` being drawn, and only there is anything in it updated. One
stored anywhere else — a view's field, a property, the modifier a wrapper
holds, an existential, a modifier class held `weak` or `unowned` or behind a
field declared as a plain class — keeps what TUIkit gave it beyond SwiftUI: its
`@State` is bound and its `@Environment` resolved, so the holding view's body
can read them. But nothing in it is updated.

**Lost:** `update()` on the properties of a modifier stored in a field and
never applied. SwiftUI gives such a field nothing. Updating it there, and not
again where it is applied, would need to know, before `body` runs, whether the
copy `body` applies came from that field, which nothing says.

**The fuller version, and why there is none at a small price** (fix round 2,
2026-10-12, asked to keep it if cheap): updating the stored copy before
`body` and skipping the applied copy when it is "the same" needs an identity
for a struct value, which Swift does not give. Comparing the applied copy's
bytes with the stored one's after `update()` would skip a modifier `body`
builds afresh with equal contents, which must be updated, and an `update()`
that changes nothing leaves the two equal either way. Running `update()` after
`body`, on the stored copy only when no applied copy matched, comes too late
for `body` to read it. Each is a change to when properties are updated, for
every modifier, to serve one SwiftUI does not serve: left for the owner.

### B-DYNVFIX-5. One value drawn at two places keeps a `@State` and an `@Environment` for each place; TUIkit's other wrappers still share one

*`@State`, `@Environment`, `@FocusState`, `@Namespace`, `@FocusedValue`,
`@FocusedBinding`*

Every copy of a property wrapper shares what it keeps behind a reference, and
the walk bound it for each place in turn, so one view value drawn at two
places — `HStack { tally; tally }`, or one property value handed to two child
views — ended bound to the second place (DYNV bug 1). SwiftUI installs each
place's state in that place's copy (measured, DYNV `dv.out`, `twice` and
`value`).

**Shipped:** `@State` and `@Environment` are bound once; a place whose copy
holds one bound to another place is given its own, in that copy. Each place
reads and writes its own state, and a closure made in its body reads its own
environment. A value drawn at one place pays, per wrapper per body, a
pointer compare for a `@State` and an identity compare for an
`@Environment`, which stops at the first node the two identities share: at
once for a value its parent's body made, along the whole chain for one kept
from an earlier frame. A `@State` whose box the storage has dropped — its
place pruned, the storage reset, its enum case left — is bound afresh,
wherever the value is next drawn: a value kept across frames reads its
place's state again, an `indirect` case's included, and is not given a
backing of its own on every body from then on. An `@Environment` resolved
for a place that a pass finding the value elsewhere does not draw is
unplaced at that pass's end, and resolved where it lies from then on.

**Left, the same class:** TUIkit's `@FocusState`, `@Namespace`,
`@FocusedValue` and `@FocusedBinding` keep a store that every copy shares, and
are bound or resolved through it. One value drawn at two places still ends
with the second place's id or focus manager.

**The fuller version** gives each the same treatment: a binding at the
property's address, and a store of its own for a copy at a second place. Its
price: each wrapper's binding moves from an instance method its public
protocol (`RenderIdentityBindable`, `EnvironmentResolvable`) declares to one
at an address, in TUIkitFoundation, where they live, and the case is rare:
the same focus field or namespace drawn twice at once. Telling a second place
in one pass from a value kept and moved between frames, as `@State` does with
its dropped boxes and `@Environment` with its displaced ones, needs the same
bookkeeping again for each store (fix round 2, 2026-10-12, asked to fix it if
cheap): not a small change, so left for the owner.
