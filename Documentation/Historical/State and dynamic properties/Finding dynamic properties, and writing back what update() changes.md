# Finding dynamic properties, and writing back what update() changes

*How TUI finds the `@State`, `@Environment` and other dynamic properties in a
view — from declared types, not values — binds their keys, and writes back
what `DynamicProperty.update()` changes. Ids: B4, A-DYNP-1, B-DYNP-1 and 2,
B-DYNVFIX-1, 2, 4 to 6, B-SKEY-1 and 2, B-DYNVFIX-4 and 5's rulings; the
investigation of 2026-10-12, appended.*

## In short

Each view type is planned once from its declared fields, and the plan reaches
every property SwiftUI's does and some it does not (a property subclass behind
a plain class field, an optional field) — the owner's "take the best of both".
`update()` writes back what it changes, an enum's payload included. A view's
own `@State`s keep declaration-order keys; an existential property's new type
starts afresh. A stored modifier's properties update only where it is applied,
and one value drawn at two places keeps its properties per place.

## How it unfolded

1. **2026-10-05, B4:** the owner ruled the missing write-back "a bug that we
   should fix", carefully for performance. Lane DYNP (2026-10-10) fixed it at
   no measured per-frame cost.
2. **2026-10-11, lane SKEY** fixed two key-binding bugs.
3. **2026-10-12, the investigation** (appended): finding properties from
   values or from types. Lane DYNVFIX fixed the ten bugs the research
   confirmed, keeping every reach TUI supported; its A/B: `stateful` −46%.
4. **2026-10-18 to 19, settled:** B-DYNVFIX-4 (measure SwiftUI and follow it)
   and B-DYNVFIX-5 (probe first, then follow), both built.

## The record

### B4. `DynamicProperty.update()` writes back (superseded by lane DYNP)

The owner ruled this a bug to fix, carefully for performance (2026-10-05).
Lane DYNP made `update()` write back what it changes, as SwiftUI's does, at
no measured per-frame cost. What the write-back covers, and where TUI
still differs from SwiftUI, is in
[`DynamicProperty update write-back (DYNP).md`](<Finding dynamic properties, and writing back what update() changes.md>),
B-DYNP-1 onwards.

### A-DYNP-1. A property in an optional field: TUI treats it as present, SwiftUI ignores it — decided: keep it

*Decided by the owner (2026-10-11 and 2026-10-12): keep it, "at least until we
find a concrete reason (e.g. correctness issue) not to". Lane DYNVFIX
(2026-10-12) made the walk plan it by type and check it by value: the plan
names the optional field, and each body a `nil` check says whether a property
is there (decisions-DYNVFIX).*

An app's property in an optional field, such as `var p: Shouting? =
Shouting()`, is handled differently by the two frameworks.

- **SwiftUI (measured, cases 2 and 2b).** It never calls `update()` on the
  property, and does not resolve the `@Environment` inside it: body reads
  the environment key's default, where the same property in a plain field
  reads the value set on the view.
- **TUI.** It looks through the optional, as its property walks always
  have. The `@State` inside is bound, the `@Environment` inside is resolved,
  and `update()` runs. Since this lane, what `update()` changes is also
  written back into the optional. What a value of the type gets never
  depends on whether the first value drawn held `nil` (B-DYNP-2).
- **A `weak` field** is an optional field too, `weak var p: Box?`. Its
  `update()` does not run, as SwiftUI's does not (measured, case 4), nor
  does that of anything it holds. What it holds is bound and resolved while
  its object lives, as what any class property holds is: by one view, the
  first drawn that reaches the object, while that view's state lives
  (decisions-DYNVFIX B-DYNVFIX-3). SwiftUI installs nothing inside a class (measured, DYNP
  `op.out` vii-f).

The options:

- **(a) Keep TUI's behaviour (shipped).** An optional property behaves
  as if it were unwrapped. That is more than SwiftUI does. A SwiftUI app
  would notice only if its wrapper relied on not being updated.
- **(b) Match SwiftUI.** No walk would look through an optional: no binding,
  no environment, no `update()`. It is one rule in two walks and the
  write-back. A view holding such an optional would also stop paying for a
  walk on every frame (see B-DYNP-2). But an app that relied on TUI's
  behaviour would see its property's environment go back to the default.
  Whether SwiftUI binds the `@State` inside such a property is unmeasured;
  the probe's value cannot tell.

### B-DYNP-1. What `update()` changes is written back, an enum's payload included

What shipped:

- `update()` runs before each `body`. What it changes in the property's own
  stored values is written into the view whose `body` is then evaluated.
  This covers a struct view's own fields, including a property inside
  another, innermost first.
- The fields are found and written through the runtime's field metadata
  (`RuntimeFields`), planned once per type (decisions-DYNVFIX).
- Only a field whose declared type may hold a property is loaded. Any other
  field may be stored at a layout other than the one the runtime reports.
- A class property, held strongly or `unowned`, is updated through its
  reference, as in SwiftUI (measured, cases 4 and 4b). One held `weak` is not
  updated, as in SwiftUI (measured, case 4).
- What `update()` reads of an `@Observable` object is observed as `body`'s
  reads are, as in SwiftUI (measured, case 5).
- **An enum's payload** — an enum view's, or an enum property's — is written
  back too, as SwiftUI writes it (measured, case 3: a counter that
  `update()` increments in the payload's property reads 1 in `body`). Lane
  DYNVFIX (2026-10-12) shipped what was this entry's fuller version: the
  payload is projected out through the enum's value witnesses
  (`destructiveProjectEnumData`), walked where it lies, and the case put back
  (`destructiveInjectEnumTag`). The case is read the same way
  (`getEnumTag`), and the cases' names and `indirect` flags come from the
  enum's field descriptor. Each payload case's declared type is learned from
  the first value seen holding it, through the runtime's reflection.

The differences left, each written up in decisions-DYNVFIX B-DYNVFIX-2:

- An `indirect` case's payload lies in a box every copy of the enum shares,
  so it is updated on a copy and not written back.
- On WebAssembly, and on Windows (not measured there), the value witnesses
  are not called: every payload is updated on a copy, as before this lane.

### B-DYNP-2. Each type is planned once from its declared fields; open fields are checked by value

*Rewritten by lane DYNVFIX (2026-10-12), which replaced the two `Mirror`
walks and their per-type "nothing here" caches with one walk planned per
type (`PropertyPlans`; decisions-DYNVFIX). The caches decided from declared
types too, but with two holes: an existential field, and a class field whose
subclass is a property, were not counted, so a type first seen holding
nothing there was kept as holding nothing for good.*

**Shipped.** The walk plans each type once, from the runtime's field
metadata: which fields hold a `@State`, an `@Environment`, an id-bound
property, or a property or modifier to look inside, and at which offsets.
A type whose fields can hold none of these is planned as holding nothing,
and its body costs one lookup and no copy. Where a field's declared type is
open, the plan names the field and each body the value says what is there:

- an optional: a `nil` check;
- an existential (`any P`, `Any`; not `any View`, a stored view, which binds
  its own properties when it renders): its dynamic type, read each body, and
  that type's plan;
- an enum (a view that is one, or a property or modifier): its current case,
  each body;
- a plain class, held strongly, `weak` or `unowned`: its object's class,
  read each body, for a subclass that is a property (decisions-DYNVFIX
  B-DYNVFIX-1).

Nothing depends on the first value drawn.

**The cost.** An existential or plain class field costs, per body, a read of
its value's type where it lies and a compare: with the declared class, and
with the two types last found there holding nothing. A view whose planned
fields are all of these is read so before any copy of it is made, and, when
they hold nothing, evaluated as it is. A type not yet known costs a plan
lookup, and one holding a property a copy of the view and of what the field
holds. An enum costs a call of its tag witness
per body, and, for a case whose payload holds something the walk acts on,
two more to project the payload and put the case back (B-DYNP-1). A case
whose payload holds nothing costs nothing more, once its payload's type is
known. Neither is measured; the `stateful` Stress scenario's `existential`
and `enum-rows` variants price them.

### B-DYNVFIX-1. A property subclass behind a plain class field is reached through its object's class each body, held strongly, weak or unowned

*`DynamicProperty`*

A field declared as a plain class, `let delegate: RowDelegate`, can hold a
subclass that is a property, `CachingRowDelegate: RowDelegate,
DynamicProperty`. TUI's walks found it from the value, but kept a view type
as holding nothing when its first value held a plain instance there, so
whether the property was ever updated depended on the first value drawn
(DYNV bug 10). SwiftUI never looks: it decides by the declared type
(measured, `Tools/SwiftUIProbes/Dynamic property discovery/dv2-main.out`,
`subclass`: never updated; declared as
the subclass, updated).

**Shipped:** TUI keeps the reach (the owner's ruling: keep what TUI
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
[FieldDescriptors.swift](../../../Sources/TUIView/Rendering/FieldDescriptors.swift)):

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
  (arm64e, which TUI does not build), and in a module built without
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
2026-10-12). The lane's A/B (2026-10-12, indicative) was flat apart from the
`stateful` scenario's gain, but no scenario has a weak plain-class field, so
this cost is not in it.

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

### B-DYNVFIX-4. A stored modifier's properties are updated only where the modifier is applied

*`ViewModifier`, `DynamicProperty`*

The walks looked inside every `ViewModifier` value, so a modifier stored in a
view's field had its properties bound, resolved, updated and written back as
the view's — and then the copy the view's body applied was updated again: its
`update()` ran twice per body (DYNV bug 5). TUI's own `.transaction(_:)`
and `.animation(_:)` store the modifier they wrap, and `.concat(_:)` the two it
joins, so they did the same. SwiftUI updates only the copy applied, once
(measured: DYNP `op.out` vii-c2; DYNV `dv2-main.out`, `txn`, `concat`).

**Shipped:** a modifier is *applied* only as the `modifier` of the
`ModifiedContent` being drawn, and only there is anything in it updated. One
stored anywhere else — a view's field, a property, the modifier a wrapper
holds, an existential — keeps what TUI gave it beyond SwiftUI: its
`@State` is bound and its `@Environment` resolved, so the holding view's body
can read them. But nothing in it is updated. A modifier class is the
exception since 2026-10-19: a property class wherever it is held (below).

**Lost:** `update()` on the properties of a modifier stored in a field and
never applied. SwiftUI gives such a field nothing. Updating it there, and not
again where it is applied, would need to know, before `body` runs, whether the
copy `body` applies came from that field, which nothing says.

**A class that is both a `DynamicProperty` and a `ViewModifier`** (measured
2026-10-19, `Tools/SwiftUIProbes/Dynamic property discovery/classmod.out`;
decided (b), the owner's rulings applied): held in a view's field and never
applied, SwiftUI runs its `update()` once per body of the view; applied at
all, whether held in a field or made in the body, SwiftUI traps ("view
modifiers must be value types"). So it is a property class wherever it is
held here (`SlotPlan.storedCopySkipsUpdates`): updated before the body of
each view holding it, as a property class held by several views is
(`Class properties held by several views/cls.out`) — in a view's field, held
`unowned`, behind a field declared as a plain class, or in an existential;
never held `weak`, where SwiftUI updates nothing. TUI applies a modifier
class, which SwiftUI does not; one held in a view's field and applied by its
body is then held by two views — the view and the `ModifiedContent` — and
updated before each body, as such a property class is. The set of objects
updated once per pass, which this entry once priced, is not built: a pass is
not always open (a view rendered alone runs none), and the rule of a
property class held twice already says what happens. It ran never where only
stored, until 2026-10-19 (review of 7d935f641, 2026-10-12).

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
modifier class is the exception: its stored and applied copies are one
object, a property class, updated as one wherever it is held (above).

### B-DYNVFIX-5. One value drawn at two places keeps each of its properties for each place

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

**Since 2026-10-19 the other four too** (decided (b), the owner's rulings
applied): TUI's `@FocusState`, `@Namespace`, `@FocusedValue` and
`@FocusedBinding` kept a store every copy shared, and were bound or resolved
through it, so one value drawn at two places ended with the second place's
id or focus manager. SwiftUI gives each place its own namespace (measured,
`Tools/SwiftUIProbes/Dynamic property discovery/twoplaces.out`; focus can
not be measured offscreen, no window there becoming key). Each is now bound
per place: `@Namespace` and `@FocusState` through `PlaceBoundIdentity`,
`@FocusedValue` and `@FocusedBinding` through `PlaceResolvedReader`, both
decided once per type in the walk's plan. The rule is `@State`'s and
`@Environment`'s, kept by a stamp of where and in which pass the shared
reference was last bound (`PlaceStamp`): bound at another place in this pass,
the copy is at a second place and takes a reference of its own; bound
elsewhere in an earlier pass — a value kept across frames and moved — it is
rebound where it lies, so a moved value takes no new reference on every body.
A second place takes one on each walk of a pass, its measure's and its
draw's, keyed by its place, so what it reads and moves is the same.

**Inside a class property** (lane DYNVCLAIM): the ids of an object's
`@FocusState` and `@Namespace` are made from a path of the object's own, not a
view's, so they are the same whichever view draws it, and two objects shown
one after the other by one view no longer share theirs, as they did while the
view that claimed each bound its ids (B-DYNVFIX-3). An object made with each
value of the view holding it takes the ids of the chain of such objects at its
place, so its ids stay the same from frame to frame; an object made before the
pass that first walks it never does, and one found so later takes its own
(decisions-DYNVCLAIM B-DYNVCLAIM-1).

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
after. Over a frame, the A/B on apps holding no class property (2026-10-13,
the full sweep and `stateful`'s variants without objects) showed nothing
slower than +0.5%: the stamp is not measurable, so the choice below was not
needed. Had it shown the stamp above noise, the choice would have been the
owner's, among the options the design priced (§10): keep the stamp; read a
plain process-wide counter instead (about 2 to 3 ns cheaper in the same probe,
and a data race when a `@State` is made off the main actor during a pass);
adopt a place's state only from a dead predecessor (an object made per view
value then restarts every frame while a closure holds the last one); or drop
§4.11, as SwiftUI has nothing of it.

**Left:** a render no pass is bound around takes every object for one made
before it, so an object made with a view value there restarts every frame.
`StateStorage.inRenderPass(_:)` is public, beside `beginRenderPass()` and
`endRenderPass()`, so a package drawing frames through those can bind it.

**Not chosen:** a clock read in `init` and compared with the pass's start,
+9 to +39 ns in the same probe.

### B-SKEY-1. An existential property's new type starts afresh, and an earlier type that comes back finds what it left

A field declared `any DynamicProperty` (or `Any`) can hold one type on one
frame and another on the next. The type is part of the key's scope, so the
new type's `@State` never takes over the old type's value, which it did
before this lane when the two had an `@State` of one type at the same place.
If the old type comes back while the view is still in the tree, its state is
still stored, and it finds it.

SwiftUI has no behaviour to match: it never binds a property in an
existential field (measured, decisions-DYNP A-DYNP-1). An enum case that
comes back is reset, as SwiftUI resets it.

**The fuller version** would reset on every change of type, as for an enum's
case, keeping a record of the type as the walk keeps one of an enum's case.
Its price, now that the walk plans each type and knows its existential fields
(decisions-DYNVFIX): a record lookup per existential field per body, in a view
holding one; and the gain above, an earlier type finding its state again, is
lost.

### B-SKEY-2. A view's own `@State` keep their declaration-order keys

A view's own `@State`, `@FocusState` and `@Namespace` are still keyed by
counting them in declaration order, as before. Their keys and ids are
unchanged. Only a property nested inside another one moved to the
position-and-scope keys.

One case is left where a value moves a key. The view itself has a field of
declared type `State<T>?`, or an `any` or `Any` field holding a `State`. That
field counts only while it holds one, so the `@State`s after it shift. SwiftUI
binds neither (A-DYNP-1), and neither is how `@State` is declared:
`@State var x: T?` is a `State<T?>`, which never shifts anything.

**The fuller version** would key the view's own properties by field position
too. The walk's plan already knows each field's position, so it would cost
nothing per frame. Its price: every composite view's keys and `@FocusState`
and `@Namespace` ids would be renumbered, along with every test that reads a
composite view's state by its index.

## Appendix: finding dynamic properties from values or from types (2026-10-12)

> **Status:** decided and landed. The owner approved building the hybrid on 2026-10-12, keeping TUI's additional
> reaches; optional fields stay supported (the owner's ruling of 2026-10-12). Lane DYNVFIX landed it on 2026-10-12
> (`57dfdb4d2`), and lane DYNVCLAIM replaced its per-object claim for class properties held by several views
> (`1b7fa6ed3`, 2026-10-13; see "How the additions are kept" below). Investigated 2026-10-10 to 2026-10-12. **Working notes** (not in git):
> `DYNP/optional/notes.md` (why SwiftUI ignores an optional field), `DYNV/notes.md` (the ten bugs and the two
> approaches; the failing tests are in its worktree's commits), `DYNV2/notes.md` (the owner's follow-ups),
> `DYNVFIX/design.md` (the design being built), and the critics' reviews in `CRIT/DYNV/` and `CRIT/DYNV2/`.

### Question

Before each `body`, TUI must find a view's dynamic properties (`@State`, `@Environment`, an app's own
`DynamicProperty`) to bind, resolve and update them. It walks the view's stored values with `Mirror`; SwiftUI works
from the declared types of the view's fields. The owner asked three things in turn:

- 2026-10-10, on SwiftUI ignoring a property in an optional field (decisions A-DYNP-1): "Is there a reason for
  SwiftUI's behaviour here?"
- 2026-10-11: "do we *gain* anything by having support for that, which SwiftUI doesn't? … We shouldn't replicate
  SwiftUI's bugs or limitations without very good reason", and "what are the full pros and cons between those two
  approaches? Please do investigate any suspected or possible correctness bugs."
- 2026-10-12, before approving a change: does the hybrid fix all the bugs, can the value-based walk fix them, and
  what are the real-world effects, with examples.

### Answer

- **SwiftUI's optional rule is mechanical; nothing shows it was chosen.** It looks into a field only if the field's declared type
  conforms to `DynamicProperty`, and `Optional` does not. One retroactive line,
  `extension Optional: @retroactive DynamicProperty where Wrapped: DynamicProperty {}`, makes SwiftUI treat an
  optional property exactly like a plain one. One obstacle was measured: with that conformance a `weak` field of a
  class property gets `update()` called with a `self` that is not the object, which is memory-unsafe. Apple's reason
  is undocumented.
- **Keep optional support, decided by type.** It lets a property be present conditionally without moving it into a
  child view, and it keeps its state across a `nil` gap, as SwiftUI does with the conformance. The price is
  portability the other way: on SwiftUI the same code silently skips `update()`. The owner ruled to keep it.
- **The value walk has ten confirmed bugs, each now a failing test.** Six are legal SwiftUI code that fails on TUI
  (two of them crash): one value holding a `@State`, used in two places, has the first place's binding write the
  second's state (1); a custom `Mirror` resets state every frame (2); a stored modifier's `update()` runs twice (5);
  an enum property's payload is not written back (6); class properties that reach each other crash every walk with
  SIGSEGV (8); a dead `unowned` reference that the view never reads traps on its first body (9). Four are bugs in what TUI adds beyond SwiftUI: a shared class
  property's contents leak between views (3, 4), and a result depends on the first value drawn (7, 10).
- **A hybrid fixes all ten:** a plan per view type built from field metadata (as SwiftUI caches one), deciding by
  value only at optional and existential fields; each view copy given its own state box; an enum's payload written
  back through its value witnesses. Deciding by value could fix every bug but 9 (it must load a field to decide,
  and loading a dead `unowned` field is what traps), but `Mirror`, today's mechanism, cannot see past a custom
  mirror (2) or write (1, 6), so those need field metadata either way.
- **In ordinary code, bugs 1 and 9 are the likeliest to bite** (a judgement, not counted).

### Key measurements

SwiftUI 6.5.4 on macOS 15.8.1, an offscreen `NSHostingView`, probes built with Xcode's swiftc 6.2.4 and run with
`OS_ACTIVITY_DT_MODE=YES` so SwiftUI's run-time warnings show. TUI's column was read from its source at
fca696a35; the ten bugs are failing tests on 0064b34bb.

| case (a field of a struct view, holding a property with `update()`, `@Environment` and `@State`) | SwiftUI | SwiftUI with the `Optional` conformance | TUI |
|---|---|---|---|
| a plain field | all four work | all four | all four |
| an optional field, non-nil | none; warns | all four | all four |
| an optional field, `nil` at the first draw | none | all four after it is set | all four after it is set |
| an `any DynamicProperty` field | none | none | all four |
| an enum conforming to `DynamicProperty` | all four | all four | no write-back (bug 6) |

"All four": `update()` ran, its change was written back, the environment resolved and the state installed.

### Reasoning

- **Mechanism and decision are separate questions.** `Mirror` or field metadata is how the fields are found; the
  value or the declared type is what decides. Field metadata is needed for bugs 2 and 9 whatever decides, and it
  lets the answer be cached per type, which also removes the per-frame `Mirror` walks (two per `body`, each child
  boxed; timing owed).
- **How the additions are kept:** the owner chose to keep TUI's reaches rather than drop them to SwiftUI's.
  Per the lane's design, a shared object's contents belonged to the first view in a render pass that reaches it, so
  every holder read one state (bugs 3 and 4 fixed without dropping the reach); that claim did not converge in review,
  and lane DYNVCLAIM replaced it: the object owns its state, every view drawn holding it is redrawn by a write, and
  each reads its own environment while it draws (decisions DYNVCLAIM, below); a `weak` field's contents are bound
  but not updated; a modifier stored in a view has its contents installed but is updated only where it is applied
  (bug 5); the subclass reach behind a plain class field (bug 10) follows the declared type, as SwiftUI does.

### Links

- Deviations [S1, S2 and S3](<../../SwiftUI parity/Deliberate deviations from SwiftUI.md#state-and-data-flow>):
  optional and existential fields, and the value walk.
- Decisions [DYNP](<Finding dynamic properties, and writing back what update() changes.md>) (A-DYNP-1, the
  optional field; B-DYNP-1, enum write-back; B-DYNP-2, the per-type caches) and
  [SKEY](<Finding dynamic properties, and writing back what update() changes.md>) (state keys inside a
  property).
- Decisions [DYNVFIX](<Finding dynamic properties, and writing back what update() changes.md>)
  (the walk planned from declared types) and
  [DYNVCLAIM](<A class property held by several views.md>) (class
  properties held by several views), with the condensed design,
  [Class properties held by several views](<A class property held by several views.md>).

