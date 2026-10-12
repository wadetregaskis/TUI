# Completing the SwiftUI API: decisions from lane DYNP

*Lane DYNP, 2026-10-10, made `DynamicProperty.update()` write back what it
changes, as SwiftUI's does. That was the owner's ruling on decisions B4 (D6M
lane, 2026-10-05): "that seems like a bug that we should fix … we need to be
very careful about the performance impact". B4 in
[`SwiftUI API completion decisions.md`](<SwiftUI API completion decisions.md>)
now points here; B-DYNP-1 below supersedes it. This file records what the write-back covers, and where
TUIkit still differs from SwiftUI. Each SwiftUI behaviour below was measured
on macOS 15 with an offscreen `NSHostingView` (session notes
`DYNP/probe/dp.swift`; the case numbers are that probe's). The format is
that of the main decisions file:*

- **A-DYNP-n — needs your decision.** Each says which option TUIkit ships
  until you decide, and what this lane changed in it.
- **B-DYNP-n — shipped the safe option.** Says what the other version would
  be, and its price.
- **C-DYNP-n — declined.** With the reason.

## A-DYNP-1. A property in an optional field: TUIkit treats it as present, SwiftUI ignores it

An app's property in an optional field, such as `var p: Shouting? =
Shouting()`, is handled differently by the two frameworks.

- **SwiftUI (measured, cases 2 and 2b).** It never calls `update()` on the
  property, and does not resolve the `@Environment` inside it: body reads
  the environment key's default, where the same property in a plain field
  reads the value set on the view.
- **TUIkit.** It looks through the optional, as its property walks always
  have. The `@State` inside is bound, the `@Environment` inside is resolved,
  and `update()` runs. Since this lane, what `update()` changes is also
  written back into the optional, and a type is no longer kept as holding
  nothing because it was first drawn with the optional `nil` (B-DYNP-2).
- **A `weak` field** is an optional field too, `weak var p: Box?`. Its
  `update()` does not run, as SwiftUI's does not (measured, case 4), and it
  does not make its view one the write-back visits. What it holds is bound
  and resolved, as for any optional; whether SwiftUI does that is
  unmeasured.

The options:

- **(a) Keep TUIkit's behaviour (shipped).** An optional property behaves
  as if it were unwrapped. That is more than SwiftUI does. A SwiftUI app
  would notice only if its wrapper relied on not being updated.
- **(b) Match SwiftUI.** No walk would look through an optional: no binding,
  no environment, no `update()`. It is one rule in two walks and the
  write-back. A view holding such an optional would also stop paying for a
  walk on every frame (see B-DYNP-2). But an app that relied on TUIkit's
  behaviour would see its property's environment go back to the default.
  Whether SwiftUI binds the `@State` inside such a property is unmeasured;
  the probe's value cannot tell.

## B-DYNP-1. What `update()` changes is written back, except in an enum view's payload

What shipped:

- `update()` runs before each `body`. What it changes in the property's own
  stored values is written into the view whose `body` is then evaluated.
  This covers a struct view's own fields, including a property inside
  another, innermost first.
- The fields are found and written through the runtime's field metadata
  (`RuntimeFields`), and only for a view type that holds an app property.
- Only a field whose declared type may hold a property is loaded. Any other
  field may be stored at a layout other than the one the runtime reports.
- A class property, held strongly or `unowned`, is updated through its
  reference, as in SwiftUI (measured, cases 4 and 4b). One held `weak` is not
  updated, as in SwiftUI (measured, case 4).
- What `update()` reads of an `@Observable` object is observed as `body`'s
  reads are, as in SwiftUI (measured, case 5).

The difference left: an enum view's payload. SwiftUI writes it back
(measured, case 3: a counter that `update()` increments in the payload's
property reads 1 in `body`). TUIkit runs `update()` on a copy, so `body` sees
only what that copy changes by reference. The payload is not written in place
because a multi-payload enum may keep its case in the payload's spare bits,
which a write would clear.

**The fuller version** would write the payload back through the enum's
value witnesses. Project the payload out
(`destructiveProjectEnumData`), update it, then put the tag back
(`destructiveInjectEnumTag`). The price:

- The value witness table would be read by its ABI layout: one more runtime
  layout to depend on, beside the field metadata.
- The payload's type would come from the value, not from the field metadata.
- The cost would land only in views that are enums.

Worth it when an app needs it.

## B-DYNP-2. The per-type "nothing here" caches decide from declared types

The binding walk and the environment walk each keep, per view type, whether
the type holds nothing to bind or resolve, so they can skip it on every later
frame. What a walk finds can depend on the value: a `nil` optional of a
property holds nothing, a present one does, and an enum view's children are
its current case's payload.

**Shipped.** A type is kept only if its declared fields say no value of it
can hold more. That rules out an enum, and a struct with a field that is an
optional of something a walk acts on: a `@State`, a property bound to its
view's identity, an `@Environment`, an app's property, or a modifier. The
same is asked of every property and modifier the walks descend into, at any
depth, since a walk finds their fields as it finds the view's: a modifier
holding an optional property makes its `ModifiedContent` count, and so does
a property or modifier field that is an enum or a class (what a class
instance holds can change). Such a type is walked on every frame, as a type
with state already is. Each type is decided once, from the runtime's field
metadata, so a `ModifiedContent` whose modifier holds none of these is still
kept.

**Not counted.** An existential field, and a class field whose subclass is
a property. What either holds is known only from its value, so a type first
seen holding nothing there is still kept as holding nothing.

**The fuller version** would count those too. Its price: every view holding
an `any` field would be walked on every frame, whatever it holds.

**The cost of counting every enum.** A view that is an enum, and a property
or modifier that is one, counts whatever its cases hold. That includes one
with no property anywhere, such as `enum Tab: View { case home, settings }`,
which until this lane was kept after its first sighting. It is now walked on
every frame: two `Mirror` walks per `body`, a cast, and four hash lookups.
That is unmeasured; no A/B scenario has an enum view, and TUIkit's own
`ConditionalView` is drawn without a `body`, so the walks never see it.
Narrowing it to the enums whose payloads can hold a property would need each
case's payload type. The runtime's mirror entry points list no fields for an
enum type (`swift_reflectionMirror_recursiveCount` answers 0 for one with
three cases, two with payloads; session notes `DYNP/probe/enumfields`), so
those types would have to be read from the enum's field descriptor and
resolved from their mangled names: a second runtime layout to depend on,
beside the field metadata. Worth it if an app's enum views show up in a
profile.
