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

### B-DYNVFIX-1. A property subclass behind a field declared as a plain class is not updated

*`DynamicProperty`*

A field declared as a plain class, `let delegate: RowDelegate`, can hold a
subclass that is a property, `CachingRowDelegate: RowDelegate,
DynamicProperty`. TUIkit's walks found it from the value, but kept a view type
as holding nothing when its first value held a plain instance there, so
whether the property was ever updated depended on the first value drawn
(DYNV bug 10).

**Shipped:** the declared type decides, as SwiftUI decides it (measured,
`DYNV/probe/dv2-main.out`, `subclass`: never updated; declared as the
subclass, updated). To have the property updated, declare the field as the
subclass, or make the base class the property.

**The fuller version** would look at every object field's value each body.
Its price: a load of the reference and a compare of its class per object
field per body, in every view that holds any object, such as an
`@Observable` model passed as `let model: Model`, whatever it holds. No use
of the reach was found (DYNV §3).

### B-DYNVFIX-2. An `indirect` enum case's payload, and every payload on WebAssembly and Windows, is updated on a copy

*`DynamicProperty`*

An enum's payload is now walked where it lies: projected out through the
enum's value witnesses, updated, and its case put back, so what `update()`
changes in it is written back, as SwiftUI writes it (DYNV bug 6;
decisions-DYNP B-DYNP-1).

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

### B-DYNVFIX-3. What a class property holds belongs to the first view in each render pass that reaches it

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

**Shipped:** what the object holds is walked once per render pass, by the
first view whose walk reaches it: its `@State` bound to that view's key (its
identity, and the object's position and type there, as before), its
`@Environment` resolved to that view's environment, its nested properties
updated in place. Every later holder in the pass leaves it as it is, so all
holders read and write one state — one object, one state — and an object made
anew per view value, held by that view alone, keeps its state from frame to
frame. The object's own `update()` still runs before each holder's body, as
SwiftUI runs it. The pass's record holds each object weakly, so an object at a
freed one's address is never taken for it.

Two holders under different environments both read the first holder's. That
is the rule's price, and the reason it is not "per reading view": a closure
made in a view's body reads the object when it runs, after every holder has
drawn, and nothing then says which view it came from.

**Not chosen:**

- *Keyed by the object's identity*: a freed object's address comes straight
  back (memory note memo-key-hashes-an-address), and an object made per view
  value would start afresh every frame, losing §4.11.
- *The last view's, as before*: bug 4 — a closure in the first view reads the
  second view's environment.
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
holds — keeps what TUIkit gave it beyond SwiftUI: its `@State` is bound and its
`@Environment` resolved, so the holding view's body can read them. But nothing
in it is updated.

**Lost:** `update()` on the properties of a modifier stored in a field and
never applied. SwiftUI gives such a field nothing. Updating it there, and not
again where it is applied, would need to know, before `body` runs, whether the
copy `body` applies came from that field, which nothing says.

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
environment. A value drawn at one place pays one pointer compare per wrapper
per body. A `@State` whose box the storage has dropped — its place pruned,
the storage reset, its enum case left — is bound afresh, wherever the value
is next drawn: a value kept across frames reads its place's state again,
an `indirect` case's included, and is not given a backing of its own on
every body from then on.

**Left, the same class:** TUIkit's `@FocusState`, `@Namespace`,
`@FocusedValue` and `@FocusedBinding` keep a store that every copy shares, and
are bound or resolved through it. One value drawn at two places still ends
with the second place's id or focus manager.

**The fuller version** gives each the same treatment: a binding at the
property's address, and a store of its own for a copy at a second place. Its
price: each wrapper's binding moves from an instance method its public
protocol (`RenderIdentityBindable`, `EnvironmentResolvable`) declares to one
at an address, in TUIkitFoundation, where they live, and the case is rare:
the same focus field or namespace drawn twice at once.
