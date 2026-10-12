# Finding dynamic properties from values or from types

> **Status:** open until its implementation lands. The owner approved building the hybrid on 2026-10-12, keeping
> TUIkit's additional reaches (lane DYNVFIX, running when this was written); optional fields stay supported (his
> ruling of 2026-10-12). Investigated 2026-10-10 to 2026-10-12. **Working notes** (not in git):
> `DYNP/optional/notes.md` (why SwiftUI ignores an optional field), `DYNV/notes.md` (the ten bugs and the two
> approaches; the failing tests are in its worktree's commits), `DYNV2/notes.md` (the owner's follow-ups),
> `DYNVFIX/design.md` (the design being built), and the critics' reviews in `CRIT/DYNV/` and `CRIT/DYNV2/`.

## Question

Before each `body`, TUIkit must find a view's dynamic properties (`@State`, `@Environment`, an app's own
`DynamicProperty`) to bind, resolve and update them. It walks the view's stored values with `Mirror`; SwiftUI works
from the declared types of the view's fields. The owner asked three things in turn:

- 2026-10-10, on SwiftUI ignoring a property in an optional field (decisions A-DYNP-1): "Is there a reason for
  SwiftUI's behaviour here?"
- 2026-10-11: "do we *gain* anything by having support for that, which SwiftUI doesn't? … We shouldn't replicate
  SwiftUI's bugs or limitations without very good reason", and "what are the full pros and cons between those two
  approaches? Please do investigate any suspected or possible correctness bugs."
- 2026-10-12, before approving a change: does the hybrid fix all the bugs, can the value-based walk fix them, and
  what are the real-world effects, with examples.

## Answer

- **SwiftUI's optional rule is mechanical, not chosen.** It looks into a field only if the field's declared type
  conforms to `DynamicProperty`, and `Optional` does not. One retroactive line,
  `extension Optional: @retroactive DynamicProperty where Wrapped: DynamicProperty {}`, makes SwiftUI treat an
  optional property exactly like a plain one. One obstacle was measured: with that conformance a `weak` field of a
  class property gets `update()` called with a `self` that is not the object, which is memory-unsafe. Apple's reason
  is undocumented.
- **Keep optional support, decided by type.** It lets a property be present conditionally without moving it into a
  child view, and it keeps its state across a `nil` gap, as SwiftUI does with the conformance. The price is
  portability the other way: on SwiftUI the same code silently skips `update()`. The owner ruled to keep it.
- **The value walk has ten confirmed bugs, each now a failing test.** Six are legal SwiftUI code that fails on TUIkit
  (two of them crash): one value holding a `@State`, used in two places, has the first place's binding write the
  second's state (1); a custom `Mirror` resets state every
  frame (2); a stored modifier's `update()` runs twice (5); an enum property's payload is not written back (6);
  class properties that reach each other crash every walk with SIGSEGV (8); a dead `unowned` reference that the
  view never reads traps on its first body (9). Four are bugs in what TUIkit adds beyond SwiftUI: a shared class
  property's contents leak between views (3, 4), and a result depends on the first value drawn (7, 10).
- **A hybrid fixes all ten:** a plan per view type built from field metadata (as SwiftUI caches one), deciding by
  value only at optional and existential fields; each view copy given its own state box; an enum's payload written
  back through its value witnesses. Deciding by value could fix every bug but 9 (it must load a field to decide,
  and loading a dead `unowned` field is what traps), but `Mirror`, today's mechanism, cannot see past a custom
  mirror (2) or write (1, 6), so those need field metadata either way.
- **In ordinary code, bugs 1 and 9 are the likeliest to bite** (a judgement, not counted).

## Key measurements

SwiftUI 6.5.4 on macOS 15.8.1, an offscreen `NSHostingView`, probes built with Xcode's swiftc 6.2.4 and run with
`OS_ACTIVITY_DT_MODE=YES` so SwiftUI's run-time warnings show. TUIkit's column was read from its source at
fca696a35; the ten bugs are failing tests on 0064b34bb.

| case (a field of a struct view, holding a property with `update()`, `@Environment` and `@State`) | SwiftUI | SwiftUI with the `Optional` conformance | TUIkit |
|---|---|---|---|
| a plain field | all four work | all four | all four |
| an optional field, non-nil | none; warns | all four | all four |
| an optional field, `nil` at the first draw | none | all four after it is set | all four after it is set |
| an `any DynamicProperty` field | none | none | all four |
| an enum conforming to `DynamicProperty` | all four | all four | no write-back (bug 6) |

"All four": `update()` ran, its change was written back, the environment resolved and the state installed.

## Reasoning

- **Mechanism and decision are separate questions.** `Mirror` or field metadata is how the fields are found; the
  value or the declared type is what decides. Field metadata is needed for bugs 2 and 9 whatever decides, and it
  lets the answer be cached per type, which also removes the per-frame `Mirror` walks (two per `body`, each child
  boxed; timing owed).
- **Cost of keeping the additions:** the owner chose to keep TUIkit's reaches rather than drop them to SwiftUI's.
  Per the lane's design, a shared object's contents belong to the first view in a render pass that reaches it, so
  every holder reads one state (bugs 3 and 4 fixed without dropping the reach); a `weak` field's contents are bound
  but not updated; a modifier stored in a view has its contents installed but is updated only where it is applied
  (bug 5); the subclass reach behind a plain class field (bug 10) follows the declared type, as SwiftUI does.

## Links

- Deviations [S1, S2 and S3](<../SwiftUI parity/Deliberate deviations from SwiftUI.md#state-and-data-flow>):
  optional and existential fields, and the value walk.
- Decisions [DYNP](<../SwiftUI parity/Decisions/DynamicProperty update write-back (DYNP).md>) (A-DYNP-1, the
  optional field; B-DYNP-1, enum write-back; B-DYNP-2, the per-type caches) and
  [SKEY](<../SwiftUI parity/Decisions/State keys inside a DynamicProperty (SKEY).md>) (state keys inside a
  property).
