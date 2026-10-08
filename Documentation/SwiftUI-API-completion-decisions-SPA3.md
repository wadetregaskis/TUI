# Completing the SwiftUI API: decisions from lane SPA3

*Lane SPA3 carried out step A3 of the module-split plan
([revision 4](Historical/Module%20split%20plan%2C%20revision%204%20%282026-10-07%29.md), §5 "Runtime and the
annotation tiers"). It annotated the 61 declarations of tier 1 and set L (the session notes'
`buildtime/split2/refine/tiers-A1p/`) with `@inlinable`, in the style that step 0b's probes settled. These are
the hot callables that will cross a module boundary once the code is split. Where that work reached a judgement
call the plan did not settle, the safe option shipped and is written up here, in the format of
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md): A for the owner to decide, B for a
basic form shipped with its fuller version priced, C for a refusal recorded in `parity-map.json`. None of this
changes public API or behaviour.*

*The complete record of what A3 annotated is `A3-annotated.json`, beside the tiers: 62 `@inlinable` and 130
`@usableFromInline`, with each declaration and its file:line (the session notes' `SPA3/annotated.py BASE HEAD`
regenerates it). In the source, a comment saying why, with the tag "module split step A3" on one line, sits on
every type, environment key and helper function that A3 made usable from inline code. The tag is not repeated
where such a comment already covers a declaration: the members and witnesses of a tagged type (a key's
`defaultValue`, an `==`, `ClaimingRow`'s members), an environment accessor whose key carries it, or a sibling the
comment names (`register(in:reportingChangesTo:_:)`, `ANSIRenderer.colorize`). Public declarations carry no tag in
their doc comments, which ship in DocC; `Text.init<S>` explains itself in a `//` comment in its body. So a grep
for the tag finds every comment that explains an annotation (86 of the 192 declarations carry one directly), and
the JSON lists every annotation.*

## B. Shipped the safe option

### B-SPA3-1. Focus and mouse registration are annotated in full, though -O inlines neither even inside one module

*`FocusRegistration.register(context:handler:focusID:)`, `MouseEventDispatcher.register(in:_:)`*

**Shipped.** The plan's form:
- Both declarations are `@inlinable`.
- Everything their bodies reach is `@usableFromInline`: 20 declarations for the focus registration (the enum
  itself included, two of them `package` in TUIkitView), and 2 for the mouse one (`registerInterned`, until now
  `private`, and `MouseHandlerLane`).
- One thing the focus registration reaches stays internal: `PersistedFocusable`. `register` re-points a persisted
  handler at its declared id through an out-of-line `@usableFromInline` `repointPersistedHandler(_:to:)`, not
  inline. Usable from inline code, the protocol's settable `focusID` cost every app a dynamic exclusivity check
  per persisted control per frame (the last finding below).

**Measured** in a release (-O, whole-module) build of the tree before A3, by disassembling TUIkit's objects:
- `FocusRegistration.register` is an out-of-line function of 389 instructions, called from 35 functions.
- `register(in:_:)` is 115 instructions, called from 30 functions. That count includes `registerInterned`, which
  was inlined into it.
- The optimiser inlines neither into its callers within the module. A caller in another module that has the body
  would most likely decide the same way, but that is unmeasured: carving and measuring a module is not allowed
  on this disk.

**What the annotation changed inside the module** (the same comparison, after A3):
- `registerInterned` now has public linkage.
- `register(in:_:)` became a 5-instruction wrapper.
- The inliner's choices around it moved:
  - `_TabViewCore.attachTabInteractions`, `_ScrollViewCore.attachIndicatorMouseHandlers` and
    `GestureAttachment.renderToBuffer` grew by 111, 111 and 92 instructions: `registerInterned`'s body is
    inlined there now.
  - `DropdownMenu.popup` shrank by 561 instructions.
  - `HelpModifier` calls `registerInterned` directly.

**The leaner version, and its price.** Leave these two declarations un-annotated, so each stays one ordinary
call per control per render, which is what -O makes of it today. Or make each an `@inlinable` measure-pass guard
over an out-of-line `@usableFromInline` body.
- Gained: 22 declarations stay internal (`repointPersistedHandler` would not need to exist), and the inlining
  around mouse registration stays as it was.
- Lost: whatever a client module's inliner would do with the full body. By the measurement above, probably
  nothing.
- The coordinator's A/B of A2 + A2′ + A3 shows whether the inlining shifts matter. If they do not, this is a
  clean-up for a later step, not a revert.

### B-SPA3-2. TextField's key initializer ends in a concrete core, rather than exporting the field's storage

*`TextField.init(_: LocalizedStringKey, text:)`*

**Shipped.** A pure refactor came first, in its own commit. All four `Label == Text` initializers (two key, two
`StringProtocol`) end in one internal `init(verbatimTitle:text:prompt:)`. The key initializer is `@inlinable`,
and the core is `@usableFromInline` and out of line. This is the shape 0b's probe t13f/g proved for
`Text.init<S>`, which now delegates to `init(verbatim:)` the same way. Annotated as it was, the key initializer
would have called the generic `init<S>(_:text:)` unspecialised from another module.

**The fuller version, and its price.** Make `init<S>(_:text:)` `@inlinable` too, writing the fields itself, so a
client can specialise `TextField(name, text: $value)` with a `String` variable.
- It would export all ten stored properties, and `_FieldValueFormatting` and `_TextSelectionChannel` as well,
  which then lose their implicitly inferred `Sendable`.
- `init<S>(_:text:)` is not in tier 1 or set L, so it belongs to tier 2's A/B-gated pass.

### B-SPA3-3. Four declarations outside the list are `@inlinable` too, where `@usableFromInline` alone would cost

*`ForEach.init(storing:id:directID:content:)`, `HandlerDrawing.reportingChanges(to:around:)`,
`SelectionEmphasisClock.init(environment:)`, `ResolvedScrollIndicators.init(bar:text:)`, and `ClaimingRow.init()`
(which is in the list)*

The rule in RESULTS-0b is that whatever an inlinable body touches must be `@usableFromInline`. Two of the
declarations touched are generic: the internal initializer both `ForEach` initializers end in, and the method the
inlined `register(in:reportingChangesTo:_:)` calls with its own `Drawn`. Left as `@usableFromInline` only, a
client would specialise the outer call and then make an unspecialised generic call inside it, which is the cost
tier 1 exists to remove. Both are small, so they are `@inlinable`.

The three initializers had been implicit, and an implicit initializer can be neither `@usableFromInline` nor
`@inlinable`. They are now spelled out, unchanged, and `@inlinable`.

**The alternative.** Leave the two generic callees as `@usableFromInline` and accept the unspecialised inner
calls until tier 2. That saves nothing measurable: their bodies are 4 and 3 statements.

## Findings for the later tiers (not decisions)

- **`@inlinable` on a member of an internal type that is not itself `@usableFromInline` raises nothing on Swift
  6.2.4, and the body goes unchecked.** `FocusRegistration.register` compiled as `@inlinable` until its enum got
  `@usableFromInline`, and then raised 20 errors. Every type whose members A3 annotated is now public or
  `@usableFromInline`. Set T's and tier 2's annotations should be checked the same way.
- **A type that becomes `@usableFromInline` loses its inferred `Sendable`, and so does every type that stores
  one.** The compiler infers `Sendable` only for types that are not usable from inline code.
  `SelectionContextMenuReference` and `ResolvedScrollIndicators` state it, because without it their
  `static let`s stopped compiling. Four more lost it silently, because nothing asked yet: `ClaimingRow` (and with
  it `ScrollIndicatorLine`, which stores one), `ScrollAnchorMode`, `MouseHandlerLane` and `HandlerDrawing`. They
  state it now, and `UsableFromInlineSendabilityTests` requires it of all seven at compile time. State it
  whenever a value type becomes usable.
- **An environment key that becomes `@usableFromInline` needs its `defaultValue` `@usableFromInline` as well.** A
  usable type's witness to a public protocol's requirement must be usable too. The same goes for an `Equatable`
  `==`.
- **Inside the monolith A3 is not codegen-neutral at -O.**
  - `@usableFromInline` gives a declaration public linkage. A single-caller private helper is then no longer
    folded into its caller and deleted, and the accessors are emitted out of line.
  - Release build of the Stress product: `__text` +20,564 bytes (+0.22%), stripped binary +53,280 bytes
    (+0.41%), exported symbols +655.
  - Across the TUIkit objects, 485 functions outside the accessors' own family changed. 192 of them changed
    size, the largest the mouse-registration paths in B-SPA3-1 and `Text.init<S>`'s and TextField's
    specialisations, which shrank as B-SPA3-2 intended.
  - The other 293 kept their size. What changed in them, in the samples read, was a mangled name, a `#line`
    constant moved by the new doc comments, or a data reference to a newly exported symbol (a key's metadata,
    `ANSIRenderer.reset`), which the objects now load through the GOT (`adrp` + `ldr`, where it was `adrp` +
    `add`). The linker relaxes those again: in the linked Stress executable, the sample read
    (`RenderContext.makeGeometryAsk(role:)`, which reads `MouseEventDispatcherKey`) is `adrp` + `add`, as before.
  - **56 functions that existed before A3 gained a call to `swift_beginAccess`**, a dynamic exclusivity check
    (the session notes' `SPA3/r1/ba2.py`, over the same disassembly):
    - 30 are `focusID` witnesses (getter and setter) of 16 persisted focus handlers: getter 11 → 18 instructions,
      setter 4 → 20. Another 24 such witnesses (`modify`) are new symbols. This was a new cost, and the fix round
      removed it (below).
    - 15 lost a call to a TUIkit function that made the check: 14 mouse-registration paths, through
      `registerInterned` or `register<A>(in:reportingChangesTo:_:)`, and a specialisation of
      `FocusManager.register(_:inSection:)`. The check moved into the caller with the inlining, so it is not a new
      cost.
    - 10 are render functions that lost a call to TUIkitView's `RenderContext.recordingEffectJournal` getter, which
      is now usable and so inlined into them. The check most likely came with it, so these are not a new cost
      either; unmeasured, because the getter's own code is in TUIkitView's objects, which the comparison did not
      cover.
    - 1 is `specialized debugFocusLog(_:)`.
  - **The witnesses' checks came from `PersistedFocusable` being `@usableFromInline`.** A settable requirement of a
    protocol usable from inline code hands every conformer's stored property to callers the whole-module
    optimiser cannot see, so it keeps the check. A probe (`SPA3/probe/r2`: a public `Focusable`, a settable
    `PersistedFocusable` refining it, two handlers, an `@inlinable` register) shows 4 checks in the `focusID`
    witnesses with the protocol usable, and none with it internal and the re-pointing out of line, as before A3.
    The fix round shipped that shape (B-SPA3-1). The whole-module disassembly after the fix is owed with the A/B:
    this lane may not build release.

## Corrections

- **Five of A3's commit messages say A3 is codegen-neutral inside the monolith**: the ones annotating tier 1's
  environment accessors, the Lists group's environment reads, focus and mouse registration, `ClaimingRow`, and
  `publishingContainerSize` with `onTapGesture` ("Inside one module nothing changes", "codegen-neutral inside the
  monolith"). That is wrong. The -O comparison above measured the opposite: accessors emitted out of line,
  symbols loaded through the GOT in the objects, `__text` +0.22%, and the exclusivity checks. The messages stay
  as they are, because the history is not rewritten. This file is the correction.
- `AssignedFocusID.claim(_:)` was made `@usableFromInline` for the `@inlinable` `register`, which never
  calls it: it only asks whether an id is on offer. The attribute is gone. The focus count in B-SPA3-1 is 20,
  where the first version of this file said 21: `claim(_:)` and `PersistedFocusable` left it, and
  `repointPersistedHandler(_:to:)` joined it.
