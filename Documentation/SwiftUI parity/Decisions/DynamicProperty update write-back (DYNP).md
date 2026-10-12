# Completing the SwiftUI API: decisions from lane DYNP

*Lane DYNP, 2026-10-10, made `DynamicProperty.update()` write back what it
changes, as SwiftUI's does. That was the owner's ruling on decisions B4 (D6M
lane, 2026-10-05): "that seems like a bug that we should fix … we need to be
very careful about the performance impact". B4 in
[`SwiftUI API completion decisions.md`](<SwiftUI API completion decisions.md>)
now points here; B-DYNP-1 below supersedes it. This file records what the write-back covers, and where
TUIkit still differs from SwiftUI. Each SwiftUI behaviour below was measured
on macOS 15 with an offscreen `NSHostingView`
([`Tools/SwiftUIProbes/Dynamic properties/dp.swift`](<../../../Tools/SwiftUIProbes/Dynamic properties/dp.swift>); the case numbers are that probe's). The format is
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

## B-DYNP-2. Each type is planned once from its declared fields; open fields are checked by value

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
  each body.

Nothing depends on the first value drawn. A field declared as a plain class
is not looked into, whatever subclass it holds, as SwiftUI decides it
(decisions-DYNVFIX B-DYNVFIX-1).

**The cost.** An existential field costs a copy of what it holds and a plan
lookup per body, in every view holding one, whatever it holds: the fuller
version this entry used to price. An enum costs its case read per body,
through the runtime's reflection: a copy of the payload and its case's name.
Neither is measured; the `stateful` Stress scenario's `existential` and
`enum-rows` variants price them.
