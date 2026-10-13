# Completing the SwiftUI API: decisions from lane DYNVFIX

*Lane DYNVFIX, 2026-10-12, fixed the ten dynamic-property bugs the DYNV
research confirmed (session notes `DYNV/notes.md`, `DYNV2/notes.md`), keeping
every reach TUIkit supported, as the owner asked: "Take the best of both as
much as you can; 'hybrid', but try not to lose anything that we currently
support, even if SwiftUI doesn't support it." The property walk is now
planned once per type from the runtime's field metadata (`PropertyPlans`),
not reflected from each value with `Mirror`. SwiftUI's behaviour was measured
with SwiftUI 6.5.4 on macOS 15.8.1 with offscreen `NSHostingView`s (probes in
`Tools/SwiftUIProbes/Dynamic property discovery/`; the Swift runtime's layouts
the walk reads, in `Tools/SwiftUIProbes/Swift runtime layouts/`). The format
is that of the main decisions file:*

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
(measured, `Tools/SwiftUIProbes/Dynamic property discovery/dv2-main.out`,
`subclass`: never updated; declared as
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
[FieldDescriptors.swift](../../../Sources/TUIkitView/Rendering/FieldDescriptors.swift)):

- **Strong:** the class is read where the reference lies.
- **`weak`**, a plain class or a class-bound existential (`weak var delegate:
  (any RowDelegating)?`): the object is loaded each body, where the field
  lies, as Swift loads a weak reference — `nil` once it has gone — and its
  class read. It is not updated, as a property held `weak` is not.
- **`unowned`**, a plain class or a class-bound existential: the class is
  read where the reference lies, whose memory the unowned count keeps, dead
  or alive. An object of a class that is not a property is never loaded, so
  a dead one never traps (DYNV bug 9); one of a property subclass is loaded
  as Swift loads it, and traps if it has gone, as a dead `unowned` property
  does (decided for a field declared as a property class). It is updated,
  unless the field is optional.

**Not reached:**

- `unowned(unsafe)`: nothing keeps the object's memory, so nothing of it is
  read.
- `unowned` of a class with an Objective-C ancestor, on Apple platforms:
  the runtime keeps such a reference as an Objective-C weak reference, which
  only the runtime reads, and it traps on one whose object has gone. A class
  with none, and every class on Linux, is read in place.
- An object of such a class held `unowned` in a class-bound existential, on
  Apple platforms: kept the same way. The reference says so — it is the
  address of a cell the runtime allocates, marked by its lowest bit, where a
  native object's reference is the object's aligned address (measured on
  macOS 15 arm64, alive, gone and for a tagged pointer:
  `Tools/SwiftUIProbes/Swift runtime layouts/unex.swift`; x86_64 unmeasured)
  — so a native object in such a
  field is read in place, and this one is left. On Linux every object is a
  native one, its reference its address (unmeasured: it follows from Swift
  keeping one kind of reference there). Before fix round 3 no `unowned`
  existential was reached anywhere (review of 6c8fe3d2b, 2026-10-12), where
  the walk before the plans reached one.
- A field whose descriptor cannot be read: where pointers are signed
  (arm64e, which TUIkit does not build), and in a module built without
  reflection metadata, whose fields are not listed at all.

The fuller version, for `unowned` on Apple platforms, checks whether the
object has gone before loading it. The runtime's check (`swift_isDeallocating`)
is a name the compiler reserves (binding it warns that it "will become an
error"), so it would mean reading the object's reference count bits, whose
layout is the runtime's private one.

**The price**, per body, per such field: a load of the reference and of its
class and a compare, held strongly or `unowned`; a weak load — the runtime's,
which retains the object and releases it after — its class and a compare,
held `weak`. In every view holding an object — an `@Observable` model passed
as `let model: Model` among them. A view holding nothing else the walk acts
on, however it holds its objects, is probed where it lies before any copy of
it is made (`SlotPlan.probes`), and evaluated as it is when its objects are
of their declared classes, or of classes found holding nothing. A field held
`weak` or `unowned` is loaded where it lies, as Swift loads it, read as a
reference to `AnyObject` held the same way: each way of holding a reference
has one layout whatever its class (measured on macOS arm64,
`Tools/SwiftUIProbes/Swift runtime layouts/typedref.swift`), so no copy of the
view is made to load it, as a
load through the runtime's reflection made two (review of 6c8fe3d2b,
2026-10-12). Unmeasured: the A/B is owed.

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
an error"; `Tools/SwiftUIProbes/Swift runtime layouts/pb.swift`). For
WebAssembly, a call
through the `swiftcc` convention: a `@convention(thin)` function type, which
Swift does not offer.

### B-DYNVFIX-3. What a class property holds is the object's: every view drawn holding it is redrawn by its writes, and an object made with a view value keeps its view's state

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
owner asked to keep what TUIkit supported: a class wrapper made anew with
each view value (session notes `DYNV2/notes.md` §4.11), and an
`@Environment(Model.self)` inside one, which reading uninstalled traps.

**Shipped** (lane DYNVCLAIM, 2026-10-12):

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
  next walk.
- **Every holder walks it before its body**, measures included: its `@State`
  as above, its ids, its nested properties' `update()` in place, then its own
  `update()`. A measure creates, moves and drops nothing a view's key holds
  for an object: no registration, no place box, no case record. An object
  whose class holds nothing a walk installs — only an `update()` — is not
  registered at all.
- **Ids.** Its `@FocusState` and `@Namespace` ids are made from the object's
  own path, so they are the same whichever view draws it, and two objects
  never share theirs (B-DYNVFIX-5). An object made with a view value takes the
  ids of the chain of such objects at its place.
- **Environment.** Its `@Environment` is resolved by its primary holder — the
  first view drawn holding it, for as long as that view holds it; a holder
  drawn after the primary's token went becomes the next. Every other holder
  hands an `@Environment` there only an environment it has none of, so no
  body reads one never resolved: one set on the object since the primary
  last walked it, read first by another holder's measure, no longer traps
  (review5 of DYNVFIX, S1). So two holders under different environments both
  read the primary's, in their bodies and their closures alike.

**Price.** Unmeasured over a frame; the A/Bs are owed (lane DYNVCLAIM §11.4).

- Every app: each `@State` notes its pass (B-DYNVFIX-6).
- An app holding class properties, per object a holder's render walk reaches:
  a lookup of its hub (a hash, a weak load, a compare) and of the view's
  token; per `@State` in it, a load and a pointer compare. A write takes a
  lock and invalidates each holder, usually one to three. An object made with
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
  or hold it in a struct property.
- One object drawn by two contexts: a box has one sink, so a write redraws
  the context that walked the object last. Nothing is lost.
- A view reading an object no walked field reaches — through an `@Observable`
  store, or only from a closure: its `@Environment` is unresolved, and a write
  redraws nothing, as before.
- A holder that stops reaching an object without leaving the tree — an
  optional set to `nil`, a case of its own enum left — stays registered until
  it leaves: a write redraws it needlessly.
- An object made with a view value is a new object every pass, and a holder
  served from the memo stays registered on the one it last walked, so a write
  to the new one does not redraw it. Only a holder whose `==` ignores the
  object it holds can be served with a new one.
- An object holding no `@State` cannot say whether it was made with a view
  value, so its ids follow the chain at its place: two long-lived objects
  holding none, shown one after the other by one view, share their ids, as
  every object's did under the claim.
- A measure made before any render walk reached a long-lived object binds no
  ids: its body reads an unbound `@Namespace` there, and the render binds it.

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

**Unmeasured against SwiftUI:** a class that is both a `DynamicProperty` and
a `ViewModifier`, held in a field declared as that class — strongly since
DYNV bug 5's fix, and held `weak` or `unowned` since fix round 2 — is a
stored modifier here, and its `update()` does not run. SwiftUI finds dynamic
properties by a field's declared type, and runs `update()` on a property
class held `unowned` (measured, DYNP case 4), so it very likely runs this
one's; no type that is both was measured (review of 7d935f641, 2026-10-12).
Left as it is, a deviation within the stored-modifier rule, until measured.

**The fuller version, and why there is none at a small price** (fix round 2,
2026-10-12, asked to keep it if cheap): updating the stored copy before
`body` and skipping the applied copy when it is "the same" needs an identity
for a struct value, which Swift does not give. Comparing the applied copy's
bytes with the stored one's after `update()` would skip a modifier `body`
builds afresh with equal contents, which must be updated, and an `update()`
that changes nothing leaves the two equal either way. Running `update()` after
`body`, on the stored copy only when no applied copy matched, comes too late
for `body` to read it. Each is a change to when properties are updated, for
every modifier, to serve one SwiftUI does not serve: left for the owner. A
modifier class is the exception to the first argument: its stored and
applied copies are one object, so a set of the objects updated in a pass
would update it once, whichever copy the walk reached first — a lookup per
modifier class per body, the price the review of 2866cb305 named; not built,
as it is the owner's call above.

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

**Inside a class property** (lane DYNVCLAIM): the ids of an object's
`@FocusState` and `@Namespace` are made from a path of the object's own, not a
view's, so they are the same whichever view draws it, and two objects shown
one after the other by one view no longer share theirs, as they did while the
view that claimed each bound its ids (B-DYNVFIX-3). An object made with each
value of the view holding it takes the ids of the chain of such objects at its
place, so its ids stay the same from frame to frame.

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

### B-DYNVFIX-6. Each `@State` notes the render pass it was made in

*`@State`, `DynamicProperty`*

An object made with each value of the view that holds it (session notes
`DYNV2/notes.md` §4.11: `let pager = Pager()`) and another object made
earlier, never yet drawn where it is now (a detail view's next item), look
alike when the walk first reaches them: never walked, nothing bound, at the
same place. Whether the old object is still alive does not tell them apart —
a `Button`'s action holding it keeps it alive, as the focus ring keeps the
last frame's actions through the next frame's walk — and neither does the
history of the walks. When the object was made does (lane DYNVCLAIM, session
notes `DYNVCLAIM/design.md` F4).

**Shipped:** each `@State`'s backing notes the render pass it was made in
(`StateBacking.createdIn`), read in its `init` from a task local,
`StateRegistration.renderPass`, which whatever draws a frame binds around the
frame, the views its bodies make included (`StateStorage.inRenderPass(_:)`):
the run loop (and so `HeadlessApp`), a snapshot render, Stress's harness, and
the test harnesses' frames. A pass is a serial from one count for the process
(`StateStorage.currentPass`), so one context's pass is never another's, and
never `0`, which a `@State` made outside every pass notes: in an event handler,
a task, a timer, or a render no pass is bound around. Nothing reads the stamp
yet; B-DYNVFIX-3 does.

**Price:** every app pays it, holding a class property or not: one task-local
read per `@State` made, +4.5 to +7.7 ns over a 92 ns `init` (measured in
isolation, arm64 `-O`: `Tools/SwiftUIProbes/Swift runtime layouts/stamp.out`),
plus a task-local binding per frame and a lock per pass for the serial. No
memory: the `UInt32` shares the word the binding byte pads out, so
`StateBacking<Int>`, `<String>` and `<Bool>` keep their instance sizes (40, 48
and 40 bytes) and their `malloc_size` (48, 48 and 48), measured before and
after. Unmeasured over a frame: an A/B on apps holding no class property
(`megalist`, `controls` or `kitchensink`, `menus`, `stateful`'s variants
without objects) is owed. If it shows the stamp above noise, the choice is the
owner's, among the options the design priced (§10): keep the stamp; read a
plain process-wide counter instead (about 2 to 3 ns cheaper in the same probe,
and a data race when a `@State` is made off the main actor during a pass);
adopt a place's state only from a dead predecessor (an object made per view
value then restarts every frame while a closure holds the last one); or drop
§4.11, as SwiftUI has nothing of it.

**Left:** a render no pass is bound around takes every object for one made
before it, so an object made with a view value there restarts every frame.

**Not chosen:** a clock read in `init` and compared with the pass's start,
+9 to +39 ns in the same probe.
