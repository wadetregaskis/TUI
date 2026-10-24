# Completing the SwiftUI API: decisions from lane DYNP

*Lane DYNP, 2026-10-10, made `DynamicProperty.update()` write back what it
changes, as SwiftUI's does. That was the owner's ruling on decisions B4 (D6M
lane, 2026-10-05): "that seems like a bug that we should fix … we need to be
very careful about the performance impact". B4 in
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>)
now points here; B-DYNP-1 below supersedes it. This file records what the write-back covers, and where
TUIkit still differs from SwiftUI. Each SwiftUI behaviour below was measured
on macOS 15 with an offscreen `NSHostingView`
([`Tools/SwiftUIProbes/Dynamic properties/dp.swift`](<../../../../Tools/SwiftUIProbes/Dynamic properties/dp.swift>); the case numbers are that probe's). The format is
that of the main decisions file:*

- **A-DYNP-n — needs your decision.** Each says which option TUIkit ships
  until you decide, and what this lane changed in it.
- **B-DYNP-n — shipped the safe option.** Says what the other version would
  be, and its price.
- **C-DYNP-n — declined.** With the reason.

## A-DYNP-1. A property in an optional field: TUIkit treats it as present, SwiftUI ignores it — decided: keep it

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
- **TUIkit.** It looks through the optional, as its property walks always
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

## B-DYNP-1. What `update()` changes is written back, an enum's payload included

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
