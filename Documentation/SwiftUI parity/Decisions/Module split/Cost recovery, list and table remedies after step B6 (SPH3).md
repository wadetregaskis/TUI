# Completing the SwiftUI API: decisions from lane SPH3

*Lane SPH3, 2026-10-08, landed the three remedies the profile of step B6 against the pre-modularisation baseline
c181ec0f9 named: a list or table specialises its shortcut table's build (R1), a table cell's unstyled-text check
compares in TUIkitFoundation (R2), and a list reads its rows' buffers and badges in place (R3). It changed no public
API and no behaviour. This file holds what it found that the brief did not settle, in the format of
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>):*

- **A-SPH3-n — needs your decision.** Nothing has shipped for these.
- **B-SPH3-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPH3-n — declined.** With the reason.

Every count below is a static count in a release `Stress` (Xcode's Swift 6.2.4,
`swift build -c release --product Stress -Xswiftc -g`, `otool -tV`, each function attributed to its module by the
debug map). None is a timing; the coordinator's A/B measures time.

## B. Shipped the safe option

### B-SPH3-1. R1 also changes one function in TUIkitApp, which links before TUIkitCore

*Sources/TUIkitFoundation/Views/KeyboardShortcut.swift (`Trigger`), TUIkitApp's `ScreenSelection.handleKey` — no API*

R1 makes `KeyboardShortcut.Trigger` `@usableFromInline`, because `ShortcutTable.triggerTable`'s body names it. A
type that is effectively public gets its conformances' witness tables serialised, so other modules can now see
`Trigger`'s synthesised `==`. One function outside the lists uses that: `ScreenSelection.handleKey` in TUIkitApp,
which compares the incoming chord with the copy chord once per key event. It used to call `Equatable`'s dispatch
thunk through the witness-table accessor, and now compares inline, as the single module did. TUIkitApp grows by
108 bytes, and nothing else changes outside TUIkitLists and TUIkitFoundation. But TUIkitApp links before
TUIkitCore, so everything after it moves by 108 bytes: the layout change the plan's gate checks for.

What ships is R1 as the brief gave it. The other versions:

- **Keep TUIkitApp's code as it was.** Write `Trigger`'s `==` and `hash(into:)` by hand with
  `@_semantics("optimize.no.crossmodule")`, so that no other module inlines them. The price: synthesis on a
  three-case enum is given up, and the attribute is underscored, so it is the owner's call. It would also keep
  the witness dispatch in TUIkitApp that the single module never had.
- **R1's structural fallback.** A non-generic entry in TUIkitFoundation would expose nothing, and would recover
  less (the diagnosis, section 2).

The paired A/B on the layout-sensitive set (geometry, customlayout, app-shapes, deep) decides. R1 is its own commit
for that reason.

R1 also leaves three callees out of line in TUIkitLists' specialisation that c181ec0f9's inlined or never called.
`trigger` (it calls a private helper) has three call sites and `resolved(commandKey:)` one; with no overrides each
runs once per default chord, 16 times per build of a list's or table's shortcut table (`RowAction`'s 14 cases bind 16
chords). The third is `ShortcutSet.default`'s addressor, one call site (how often it runs is unmeasured: the source
reads `.default` for each action with no override, and the optimiser may hoist the call); c181ec0f9's specialisation
calls no addressor. `@inlinable` on `resolved(commandKey:)` would inline it, as the single module did. Its body names
only public members, so nothing more needs widening. But TUIkitApp (`Scene+TextSelection`) and TUIkitNavigation
(`NavigationSplitViewToggle`) call it too, so TUIkitApp's code would change again. The brief asked for
`@usableFromInline`, which is what ships.

## C. Declined

### C-SPH3-1. The list-row residuals the profile could not explain are not split costs

*`LazyListRowContent.__deallocating_deinit`, `Collection.map`, `ForEach.element(at:)` — no API*

The diagnosis estimates that megalist and kitchensink keep ≈+0.8–1.2% each after R1–R3 (its section 6.1, from
the B6h profile's shares; no profile after R1–R3 exists yet), and that profile has three rows it could not explain.
Statically, none of them is a crossing the split added:

- **The deinit's extra `swift_release`** is where a helper sits, not extra code. The deinit releases the same
  fields in the same way as c181ec0f9's: three optional closures through a helper, two class references, the cached
  render and the weak decider. The helper is a symbol-less, four-instruction "release this closure context if
  there is one" (`cbz`, `mov`, `b swift_release`, `ret`). The linker placed it right after the deinit, inside the
  deinit's symbol range, so a static count and the profiler both file it under the deinit. At c181ec0f9 the same
  helper sat inside `specialized SelectableListRow.rowIdentity.getter`'s range: every c181ec0f9 profile shows
  self time in that getter (1–6 ms), and no B6h profile shows the getter at all. That accounts for the deinit's 30 → 34 instructions.
  Its inclusive time is flat: megalist 349 / 376 / 341 ms at c181ec0f9 against 345 / 379 / 314 at B6h, and
  kitchensink 311 / 272 / 305 against 274 / 276 / 263.
- **`Collection.map<A, B>`, unspecialised**, is the same 792-byte body in both builds (`Collection+Offsets.swift.o`),
  with the same callers and call counts. The row path calls it from `ForEach.extractListRows` and `_ListCore`'s
  `renderRow`, `rowWidth`, `buildPopulatedContent`, `decorateForReorder`, `composeRowLines` and `publishRowBands`. All
  of them are generic callers, unspecialised at c181ec0f9 too. Where a caller moved to TUIkitLists, the call is the
  same `bl` to the same statically linked body.
- **`ForEach.element(at:)`** is the same 360-byte body, with the same six callers, all in TUIkitFoundation: no call
  crosses a module.

A profile on the tip, which these static counts cannot replace, is the way to find the rest. The lane's notes
(`SPH3/static/rowpath-new-edges.txt`) list the cross-module calls the row path makes that c181ec0f9 did not. Three
are already recorded: `ANSIRenderer.reset`'s addressor (A-SPH2-1), `ANSIRenderer.colorize` (B-SPH-1), and the
`package` accessors over `RowEditRestrictions`' private storage (0f28cc996, CONTRIBUTING's rule): three per list
per frame, and two per rendered row from its separator decision. The rest are one or two calls each per row or per list:
`String.withPersistentBackground`, `BadgeValue.displayText`, `FrameBuffer.resolvingOpacity`,
`RenderContext.requestWake`, and environment-key getters that were specialised and serialised but not inlined.
