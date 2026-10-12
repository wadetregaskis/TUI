# Completing the SwiftUI API: decisions from lane SKEY

*Lane SKEY, 2026-10-11, fixed two bugs in how TUIkit binds the `@State` inside
an app's `DynamicProperty` ([`Tools/SwiftUIProbes/Dynamic property discovery/notes.md`](<../../../Tools/SwiftUIProbes/Dynamic property discovery/notes.md>) §5.5,
`DynamicPropertyStateKeyTests`). A nested `@State` took the next index of its
view's one counter, so what an optional, an existential or an enum case before
it held moved its key, and two `@State`s of one type swapped values. It is now
keyed by where it is declared in the view (`NestedScope`). And a property in an
enum case holding more than one value was never bound. What SwiftUI does was
measured on macOS 15 (SwiftUI 6.5.4) with an offscreen `NSHostingView`
([`Tools/SwiftUIProbes/State keys in dynamic properties/skey.swift`](<../../../Tools/SwiftUIProbes/State keys in dynamic properties/skey.swift>), outputs `skey.out` and
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
[`SwiftUI API completion decisions.md`](<SwiftUI API completion decisions.md>):*

- **A-SKEY-n — needs your decision.**
- **B-SKEY-n — shipped the safe option.** Says what the fuller version would
  be, and its price.
- **C-SKEY-n — declined.** With the reason.

There is no A or C entry. Both B entries exist because TUIkit looks through
optionals and existentials, which the owner decided to keep (decisions-DYNP
A-DYNP-1, 2026-10-12; existential fields, 2026-10-12). Since lane DYNVFIX
(2026-10-12) the walk plans each type from its declared fields
(decisions-DYNVFIX), which changes the price of each fuller version below.

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
