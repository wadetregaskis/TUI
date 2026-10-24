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
[FieldDescriptors.swift](../../../../Sources/TUIkitView/Rendering/FieldDescriptors.swift)):

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
owner asked to keep what TUIkit supported: a class wrapper made anew with
each view value (session notes `DYNV2/notes.md` §4.11), and an
`@Environment(Model.self)` inside one, which reading uninstalled traps.

**Shipped** (lane DYNVCLAIM, 2026-10-12; its design, condensed, is
`Documentation/Historical/Class properties held by several views, design (2026-10-12).md`):

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

**Price.** Unmeasured over a frame; the A/Bs are owed (lane DYNVCLAIM §11.4).

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
holds, an existential — keeps what TUIkit gave it beyond SwiftUI: its
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
never held `weak`, where SwiftUI updates nothing. TUIkit applies a modifier
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
applied): TUIkit's `@FocusState`, `@Namespace`, `@FocusedValue` and
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
`StateStorage.inRenderPass(_:)` is public, beside `beginRenderPass()` and
`endRenderPass()`, so a package drawing frames through those can bind it.

**Not chosen:** a clock read in `init` and compared with the pass's start,
+9 to +39 ns in the same probe.
