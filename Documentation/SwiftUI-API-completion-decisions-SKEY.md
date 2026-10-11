# Completing the SwiftUI API: decisions from lane SKEY

*Lane SKEY, 2026-10-11, fixed two bugs in how TUIkit binds the `@State` inside
an app's `DynamicProperty` (session notes `DYNP/optional/notes.md` §5.5,
`DynamicPropertyStateKeyTests`). A nested `@State` took the next index of its
view's one counter, so what an optional, an existential or an enum case before
it held moved its key, and two `@State`s of one type swapped values. It is now
keyed by where it is declared in the view (`NestedScope`). And a property in an
enum case holding more than one value was never bound. What SwiftUI does was
measured on macOS 15 (SwiftUI 6.5.4) with an offscreen `NSHostingView`
(session notes `SKEY/probe/skey.swift`, outputs `skey.out` and
`skey-optconf.out`):*

- *An enum's case that replaces another, an enum view's or an enum
  property's, starts its `@State` at its defaults, even when the two cases
  hold the same property type; the case left starts at its defaults again
  when it comes back. The case staying while another payload value changes
  keeps its state. TUIkit now does all of this.*
- *An optional property that goes `nil` and comes back finds the state it
  left, with `Optional` made to conform to `DynamicProperty`. Without that
  conformance SwiftUI binds nothing in an optional (decisions-DYNP
  A-DYNP-1). TUIkit, which looks through optionals until A-DYNP-1 is
  decided, now behaves as the conforming build does.*

*The format is that of
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md):*

- **A-SKEY-n — needs your decision.**
- **B-SKEY-n — shipped the safe option.** Says what the fuller version would
  be, and its price.
- **C-SKEY-n — declined.** With the reason.

There is no A or C entry. Both B entries exist only while TUIkit looks
through optionals and existentials; if A-DYNP-1 goes the other way, no walk
reaches either case.

## B. Shipped the safe option

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
Its price: `Mirror` opens an existential, so the walk cannot tell an
existential field from a field of a concrete type by the value it finds.
Every container in every view holding an app property or a modifier would
pay a record lookup on every frame, or the walk would read each type's
declared fields to find its existential ones.

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
too. The walk already counts positions for the containers, so it would cost
nothing per frame. Its price: every composite view's keys and `@FocusState`
and `@Namespace` ids would be renumbered, along with every test that reads a
composite view's state by its index.
