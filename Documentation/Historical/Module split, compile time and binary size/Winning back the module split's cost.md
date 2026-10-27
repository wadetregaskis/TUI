# Winning back the module split's cost

*What splitting the module cost at run time — calls that crossed a module
boundary unspecialised, storage that went behind resilience, a menu column,
the lists and tables — and the lanes that won it back. The lanes' own records
follow, in order.*

## In short

Each step's A/B showed what crossing a module boundary costs: generic code
not specialised across it, and storage reached through accessors. The
recovery lanes took it back with `@inlinable` audits, package storage, list
and table remedies and the inline menu column, until the last warm residuals
(RES) were within the owner's tolerance (a few percent is fine; about 10%
means optimise first).

## Completing the SwiftUI API: decisions from lane SPH

*Lane SPH, 2026-10-08, recovered the run-time costs that module split steps B4, B5 and B6 added at the module
boundaries they drew, by the rules SPB5's diagnosis set for every carve: a plain import of what each file uses,
accessors rather than widened class storage, no stored-property defaults under an `@inlinable` initializer, and tier
2's `@inlinable` on the per-row and per-cell crossings. It changed no public API and no behaviour. This file holds the
judgement calls it reached that the plan did not settle, in the format of
[the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>):*

- **A-SPH-n — needs your decision.** Nothing has shipped for these.
- **B-SPH-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPH-n — declined.** With the reason.

### B. Shipped

#### B-SPH-1. Tier 2 covers the per-row crossings that inline as annotated, not the ones that would need more

*Sources/TUIFoundation (RowBackground, ListRowSeparatorLine, ListSeparatorPreference, the line-limit and
truncation-mode environment), Sources/TUIStyling (HighlightFill) — no API*

The brief allowed `@inlinable` on the crossings that the plan's tier 2 or set T lists, or that step B6's inventory
names per row or per cell, and asked that each one's call be gone from the release Stress binary, or go to a
specialised or inlined body. Annotating is not enough for that, as two measurements showed:

- **An `@inlinable package` member of a type that is only `package` is not serialized.** A `-emit-sil` probe
  against the release modules sees `ListRowSeparatorLine.init(tint:leading:trailing:)`,
  `ListSeparatorPreference.overridden(by:)` and `RowBackground`'s getters as `package_external` declarations with
  no body, so the release Stress still called all of them. With the types (and the fields and members the bodies
  read) `@usableFromInline`, which is the style step A3 used for `ClaimingRow`, the bodies are there to inline. The
  type checker accepts the first form without a word.
- **`-O` does not inline a generic into an unspecialised generic caller.** `Button.init(action:label:)` and
  `HStack.init(alignment:spacing:content:)` made `@inlinable` were still called, unspecialised, from
  `_NavigationLinkCore.button` and `_OutlineRow.branchRow`, which are generic over the app's views and are not
  specialised in TUINavigation or TUILists. The same holds for `extractBadgeValue(from:)` and
  `staticListRowID(of:ordinal:as:)`, which `_ListCore.extractRows(ofUnwrapped:context:)` calls, generic over the
  row. `HorizontalAlignment.childOffset(childWidth:in:)`, made `@inlinable` with `ViewDimensions`' initializer and
  subscripts, was serialized but not inlined: with the guides' dictionary lookup inlined into it, it is past the
  inliner's size limit.

**Shipped:** `@inlinable` on `RowBackground.tint(_:)`, `claimableFill`, `stepNow` and `pulseTiming`,
`ListRowSeparatorLine.init(tint:leading:trailing:)`, `ListSeparatorPreference.overridden(by:)`, and the
`lineLimit` and `truncationMode` environment accessors (tier 2), with what their bodies read
`@usableFromInline`: the three types and the two structs' fields, `RowBackground.Paint`, `HighlightFill`,
`SelectionEmphasisCycle.timing` and `isAnimating(dim:bright:)`, `IndicatorCycleTiming`, and the two environment
keys. No class's stored property, and no type that conservative cross-module optimisation reads differently: all
of them were `package` already. The annotations that did not inline (`Button.init(action:label:)`,
`HStack.init`, `childOffset`) were taken out again rather than left as decoration.

**The other version,** crossing by crossing, and its price:

- **`ANSIRenderer.colorize` and `TextStyle.init()` / `foregroundColor` (tier 2).** `colorize` builds a
  `TextStyle`, so all three need `TextStyle` usable from inline code: its fourteen stored properties and the
  three `Stated…` enums `@usableFromInline`, and its four enum-case defaults deleted and assigned in its
  initializer (CONTRIBUTING.md, "Crossing a module boundary"). The price is also a layout change: with `TextStyle`'s
  fields usable from inline code, conservative CMO can serialise more of `Text`'s public modifiers into every app,
  as B5's widening of the type did for `bold()` (SPB5's diagnosis, §3.1 and §6.4), which moves every address after
  them. Worth an A/B of its own, once the coordinator's A/B shows whether the table rows (`table*`) still need it.
- **`Button.init(action:label:)` and `HStack.init` (B5's `NavigationLink` row).** Only `@inline(__always)`, or
  `@_specialize` on the callers, would remove the call; neither is in the plan's annotation style (step 0b), and
  both cost code size in every specialisation.
- **`childOffset` (per table cell, per tab-strip line).** `@inline(__always)`, or splitting it so the common
  case (no explicit guide) is a few arithmetic instructions. The work in its body, a dictionary lookup and a call
  through the alignment's `AlignmentID` metatype, would stay.
- **Not annotated, their own work being the cost (the tier cut's "left out as their own work"):**
  `ANSIRenderer.styleSequence(for:)`, `applyPersistentDim(_:)`, `PaintRenderer.band`, `RampSampler.alphaClaims`,
  `RowBackground`'s `painting(_:padding:)`, `framePaints`, `stillLines(_:)` and `Paint`'s, and
  `ListRowSeparatorLine.drawn(width:palette:)`. `LazyListRowContent.init(buffer:badge:)` initializes a class's
  stored properties, which would have to become `@usableFromInline`: the first rule of the diagnosis forbids it.

## Completing the SwiftUI API: decisions from lane SPH2

*Lane SPH2, 2026-10-08, finished what lane SPH found of the module split's run-time costs: it audited every
`@inlinable` added since the pre-modularisation baseline c181ec0f9 for annotations that do not inline, converted the
class stored properties and statics steps B2 and B3 had widened to `package`, and looked again at the per-row
generic crossings SPH left as calls. It changed no public API and no behaviour. This file holds what it found that
the brief did not settle, in the format of
[the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>):*

- **A-SPH2-n — needs your decision.** Nothing has shipped for these.
- **B-SPH2-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPH2-n — declined.** With the reason.

Every count below is a static count of call sites in a release `Stress` (Xcode's Swift 6.2.4,
`swift build -c release --product Stress -Xswiftc -g`, `otool -tV`, each function attributed to its module by the
debug map), at c181ec0f9 against this lane's last commit, with callers matched by name across the split (module
qualifiers and private discriminators removed). None is a timing; the coordinator's A/B measures time.

### A. Needs your decision

#### A-SPH2-1. A `static let` read from another module calls its addressor — decided: keep the addressor

*Every module boundary — no API*

**Owner (2026-10-12): keep the addressor.** A read of a global from another module stays one call, as shipped.
Computed constants (`@inlinable static var` in place of `static let`, for the per-row readers named below) stay a
future optimisation, taken up only if a profile shows a real-world cost from these calls; they are recorded in
[Future options](<../../Future options.md#computed-constants-for-globals-read-across-modules>). The ruling does not cover
`LocalizationService.shared`'s 157 sites: removing them belongs to replacing the singleton, a design change of its
own.

Inside one module the optimiser inlines a global's addressor into each read: a check of the global's once-token,
`swift_once` on the slow path, and a load. From another module it cannot see the addressor's body, so each read is a
call to `….unsafeMutableAddressor`. The split moved readers and globals apart, and the counts show the trade:
addressor call sites 672 at c181ec0f9, 1,064 now (+392), and `swift_once` call sites 2,117, now 1,688 (−429). Each
moved read costs one call and return more, whatever the global. The largest:

| global | new cross-module sites | where |
|---|---|---|
| `LocalizationService.shared` (TUIStrings since B2) | 157 | every localized label the substrate and the carved modules look up |
| `VerticalAlignment.center`, `HorizontalAlignment.leading` / `.center`, `Alignment.topLeading` | 26, 24, 16, 9 | default arguments of `HStack`/`VStack`/`ZStack` built in a carved module, among them `_NavigationLinkCore.button`'s and `_OutlineRow.branchRow`'s, per row |
| `ButtonRole.cancel` | 16 | dialogs and alerts |
| `ANSIRenderer.reset`, and 12 sites of its other escape strings | 14 + 12 | `reset` per list and table row (`_TableCore.renderRowUncached`, `renderMultiLineRow`, `ListRowContent.init`) and per frame; the others at startup and shutdown |
| `CursorTimer.standardFrameSeconds`, `TerminalHost.isTmux` / `.isAppleTerminal` / … | 11, 11 + 17 | per frame or per wake |

The plan's toolbox has nothing for it: `@inlinable` does not apply to a stored global, and Swift 6.2 has no way to
hand another module a global's constant value. The options:

- **Accept it** (what ships). One call per read; no row path found is dominated by it.
- **Computed constants on the per-row paths.** `@inlinable static var center: VerticalAlignment { … }` in place of
  `static let` inlines into the reader. SwiftUI declares these `static let center: VerticalAlignment`
  (`sdoc.py 'VerticalAlignment.center'`), so for the public ones it is a declaration-kind deviation: every read still
  compiles, but the API parity tool would need a map entry per constant. The `package` ones have no such price:
  `ANSIRenderer.reset` (an interpolation today, `"\(csi)0m"`, so a literal in its place) and
  `CursorTimer.standardFrameSeconds`. `TerminalHost.isTmux` and its kin are read once from the process environment and must stay
  stored.
- **`LocalizationService.shared`.** Handing the service down through the context or the environment instead of the
  singleton read would remove the 157 sites, and is the "No Singletons" rule's direction too; it is a design change
  of its own, not an annotation.

#### A-SPH2-2. A feature-object slot costs a cast on every read — decided: the cast stays

*Sources/TUIFoundation/Environment/FeatureObjectSlots.swift (step K1, a2195f6bd) — no API*

**Owner (2026-10-12): keep the `as?`.** TUI uses `unsafeDowncast` only where the cast is guaranteed by
construction, and here it is not. That a slot holds its accessor's type is a convention: `subscript(featureObject:)`
is `package`, so any module of the package can write any object into any slot, and only review would notice. With
`as?` a wrong object reads as absent; with `unsafeDowncast` it would be undefined behaviour in release. The second
option below rests on that convention, so it is not taken. A design that does make the cast provable, typed slot
keys written through one generic subscript into private storage, is recorded in
[Future options](<../../Future options.md#typed-feature-object-keys>); it needs storage of its own in `EnvironmentValues`,
at a price not measured.

K1 made the navigation coordinator, the dialog suppression toggle, the search objects and the notification service
`AnyObject?` environment slots that the substrate declares and clears, each read through its feature's typed
accessor (`self[featureObject: .navigationCoordinator] as? NavigationCoordinator`). A read is still one call into the
environment's storage, as the typed key's was at c181ec0f9, so `@inlinable` on the slot subscript would remove
nothing; what the slot adds is the `as?` (`swift_dynamicCastClass`) and an unknown-object release. TUINavigation
reads or writes a slot at 10 call sites (none at c181ec0f9, where each was a typed key's getter): per
`NavigationLink` row (`_NavigationLinkCore.button`), and in `NavigationStack`'s, the alerts' and the destination
and presentation modifiers' renders. The options:

- **Accept it** (what ships).
- **`unsafeDowncast(_:to:)` in the typed accessors.** The slot is written only through its accessor, and
  `FeatureObjectSlot`'s fixed set means nothing else can write it, so the object is always of the accessor's type; a
  debug build would still check. It removes the cast in release, at the price of trusting that invariant.

#### A-SPH2-3. A list row's buffer is borrowed through an out-of-line coroutine — superseded

*Sources/TUIFoundation/Views/LazyListRowContent.swift (`buffer`), TUILists' row code — no API*

**Superseded on 2026-10-08: fixed, not accepted.** This entry recommended accepting the 25 read-coroutine calls step
B6 left in TUILists' row code, and priced them at two calls per read. That price was wrong. Each read also
heap-allocated the coroutine's 88-byte frame, copied the 64-byte `FrameBuffer` into it, and freed it in the
continuation, and the callers added outlined `FrameBuffer` copies. The profile that found it estimated the cost at
about 3% of a `megalist` frame and 2.3% of a `kitchensink` one.

The owner approved the remedy. `buffer` and `badge` are `@inlinable` over a `@usableFromInline` `cached` and
`resolveIfNeeded()`, so TUILists calls `resolveIfNeeded()` directly, as c181ec0f9's list code did. It is the one
exception to CONTRIBUTING.md's rule on class stored properties ("Crossing a module boundary"), allowed because every
access to `cached` was already dynamic. `LazyListRowContent.cached`'s doc comment holds the evidence.
`ANSIRenderer.colorize` (31 sites from TUILists), which this entry also mentioned, is B-SPH-1's, priced there.

### C. Declined

#### C-SPH2-1. The per-row generic crossings SPH left as calls are not split costs

*`_NavigationLinkCore.button`, `_OutlineRow.branchRow`, `_ListCore.extractRows(ofUnwrapped:context:)` — no API*

SPH (B-SPH-1) found that `Button.init(action:label:)`, `HStack.init(alignment:spacing:content:)`,
`extractBadgeValue(from:)` and `staticListRowID(of:ordinal:as:)` stay calls when annotated, because their callers are
unspecialised generics. At c181ec0f9 the same three callers were unspecialised generics too, and made the same calls:
one each, to the same unspecialised bodies (the same 28 functions in that family at c181ec0f9 and now, all of them
unspecialised, the three callers' bodies within 4% of their sizes). A cross-module `bl` to a statically linked function is the instruction an intra-module one was, so these
four crossings cost nothing the split added. Specialising the callers (a concrete overload for the common row type, or
`@_specialize`) would make them faster than the baseline: an optimisation the owner's brief for this work excludes.
What the split did add to these rows is A-SPH2-1's `VerticalAlignment.center` read and, for `NavigationLink`,
A-SPH2-2's cast.

## Completing the SwiftUI API: decisions from lane SPH3

*Lane SPH3, 2026-10-08, landed the three remedies the profile of step B6 against the pre-modularisation baseline
c181ec0f9 named: a list or table specialises its shortcut table's build (R1), a table cell's unstyled-text check
compares in TUIFoundation (R2), and a list reads its rows' buffers and badges in place (R3). It changed no public
API and no behaviour. This file holds what it found that the brief did not settle, in the format of
[the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>):*

- **A-SPH3-n — needs your decision.** Nothing has shipped for these.
- **B-SPH3-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPH3-n — declined.** With the reason.

Every count below is a static count in a release `Stress` (Xcode's Swift 6.2.4,
`swift build -c release --product Stress -Xswiftc -g`, `otool -tV`, each function attributed to its module by the
debug map). None is a timing; the coordinator's A/B measures time.

### B. Shipped the safe option

#### B-SPH3-1. R1 also changes one function in TUIApp, which links before TUICore

*Sources/TUIFoundation/Views/KeyboardShortcut.swift (`Trigger`), TUIApp's `ScreenSelection.handleKey` — no API*

R1 makes `KeyboardShortcut.Trigger` `@usableFromInline`, because `ShortcutTable.triggerTable`'s body names it. A
type that is effectively public gets its conformances' witness tables serialised, so other modules can now see
`Trigger`'s synthesised `==`. One function outside the lists uses that: `ScreenSelection.handleKey` in TUIApp,
which compares the incoming chord with the copy chord once per key event. It used to call `Equatable`'s dispatch
thunk through the witness-table accessor, and now compares inline, as the single module did. TUIApp grows by
108 bytes, and nothing else changes outside TUILists and TUIFoundation. But TUIApp links before
TUICore, so everything after it moves by 108 bytes: the layout change the plan's gate checks for.

What ships is R1 as the brief gave it. The other versions:

- **Keep TUIApp's code as it was.** Write `Trigger`'s `==` and `hash(into:)` by hand with
  `@_semantics("optimize.no.crossmodule")`, so that no other module inlines them. The price: synthesis on a
  three-case enum is given up, and the attribute is underscored, so it is the owner's call. It would also keep
  the witness dispatch in TUIApp that the single module never had.
- **R1's structural fallback.** A non-generic entry in TUIFoundation would expose nothing, and would recover
  less (the diagnosis, section 2).

The paired A/B on the layout-sensitive set (geometry, customlayout, app-shapes, deep) decides. R1 is its own commit
for that reason.

R1 also leaves three callees out of line in TUILists' specialisation that c181ec0f9's inlined or never called.
`trigger` (it calls a private helper) has three call sites and `resolved(commandKey:)` one; with no overrides each
runs once per default chord, 16 times per build of a list's or table's shortcut table (`RowAction`'s 14 cases bind 16
chords). The third is `ShortcutSet.default`'s addressor, one call site (how often it runs is unmeasured: the source
reads `.default` for each action with no override, and the optimiser may hoist the call); c181ec0f9's specialisation
calls no addressor. `@inlinable` on `resolved(commandKey:)` would inline it, as the single module did. Its body names
only public members, so nothing more needs widening. But TUIApp (`Scene+TextSelection`) and TUINavigation
(`NavigationSplitViewToggle`) call it too, so TUIApp's code would change again. The brief asked for
`@usableFromInline`, which is what ships.

### C. Declined

#### C-SPH3-1. The list-row residuals the profile could not explain are not split costs

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
  of them are generic callers, unspecialised at c181ec0f9 too. Where a caller moved to TUILists, the call is the
  same `bl` to the same statically linked body.
- **`ForEach.element(at:)`** is the same 360-byte body, with the same six callers, all in TUIFoundation: no call
  crosses a module.

A profile on the tip, which these static counts cannot replace, is the way to find the rest. The lane's notes
(`SPH3/static/rowpath-new-edges.txt`) list the cross-module calls the row path makes that c181ec0f9 did not. Three
are already recorded: `ANSIRenderer.reset`'s addressor (A-SPH2-1), `ANSIRenderer.colorize` (B-SPH-1), and the
`package` accessors over `RowEditRestrictions`' private storage (0f28cc996, CONTRIBUTING's rule): three per list
per frame, and two per rendered row from its separator decision. The rest are one or two calls each per row or per list:
`String.withPersistentBackground`, `BadgeValue.displayText`, `FrameBuffer.resolvingOpacity`,
`RenderContext.requestWake`, and environment-key getters that were specialised and serialised but not inlined.

## Completing the SwiftUI API: decisions from lane SPM1

*Lane SPM1, 2026-10-09, landed remedy M1 of the profile diagnosis of module split step B5b (session notes,
`SPB5b/regress/diagnosis.md`): the inline menu's column is built in TUIFoundation again, so that it is
specialised and resolves no opaque type at run time. It changed no public API and no behaviour. This file holds what
it found that the brief did not settle, in the format of
[the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>):*

- **A-SPM1-n — needs your decision.** Nothing has shipped for these.
- **B-SPM1-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPM1-n — declined.** With the reason.

Every count below is a static count in a release `Stress` (Xcode's Swift 6.2.4,
`swift build -c release --product Stress -Xswiftc -g`, `otool -tV`, each function attributed to its module by the
debug map), against the binary of 4771bb09c (steps B5b and B5c). None is a timing; the coordinator's A/B measures
time.

### B. Shipped the safe option

#### B-SPM1-1. The inline menu's core and column stay in TUIFoundation, not in TUIMenus as the plan maps them

*Sources/TUIFoundation/Rendering/_InlineMenuCore.swift, MenuColumnLayout.swift — no API*

Plan revision 4 maps `_InlineMenuCore` and the menu column's layout to TUIMenus, and step B5b carved them there.
From TUIMenus the column could not see the types it is made of: `View.bordered`'s result names the internal
`_BorderRings` and `foregroundStyle(_:)`'s the internal `_StyleEnvironmentView`, so the column looked both up at run
time on every call (`swift_getOpaqueTypeConformance2`, four call sites), and it called `bordered`, a `package`
generic, unspecialised. The diagnosis priced these frames at about 0.24 of B5b's menus-cold time against B6s's code
(from profile shares, not times; net about -0.1 to +0.2 on the same path). What ships is its remedy M1: both files
compile in TUIFoundation, as they did until B5b; `_InlineMenuCore` is `package` so that `InlineMenuStyle`
(TUIMenus) can make it; and the nine declarations the carve widened for these two files alone are internal again.
Five are the diagnosis's: `View.bordered`, `EnvironmentValues.isInsideMenu` and `menuRowWidth`, `_MenuSectionedItems`
and `_MenuItemButtonStyle`. Four more the diagnosis did not name: `ScrollView`'s `withoutFocusStop()` and
`asChrome()`, which the column sets on its scroller, and `FocusManager.SubtreeFocusJump` and
`moveFocus(inSubtreeAt:jump:)`, which the core's paging keys call (Page Up and Down, Home and End). The index store
finds no file of another module that names any of the nine (session notes, `plan/overwide.py`: every `package`
declaration of TUIFoundation's six directories that gained `package` since fc6f6b7db and that no other module
references). The map follows the files (Tools/ModuleMap's map.json and the TUIMenus entry of rules.json). One type
widens and nine narrow; nothing becomes usable from outside the package.

The other versions, as the diagnosis priced them:

- **M1′: keep `_InlineMenuCore` in TUIMenus** and give it two non-generic `package` entries in TUIFoundation
  that build the column there (`measureInlineMenuColumn(label:content:context:capHeight:)` and a render twin). The
  same recovery, the map unchanged for `_InlineMenuCore.swift`, at the price of two new names where M1 widens one
  type. Choose it if the plan's map matters more than the smaller surface.
- **Widen `_BorderRings` and `_StyleEnvironmentView` to `package`.** Removes the run-time lookups but not the
  unspecialised `bordered`, and every app could then see through `.border()` and `.foregroundStyle()` too (Stress
  has 6 and 37 such symbols): the app's own code would change, so no A/B could separate the remedy from the app
  change. Declined by the brief.
- **`@inlinable` on `bordered`** (with `@usableFromInline` on what it names). TUIMenus would specialise it, but
  `_BorderRings` becomes effectively public, the same app change, and it does nothing for `foregroundStyle`.
  Declined by the brief.

The price of what ships: about 420 lines compile in TUIFoundation's job again (about 0.1 s at the carve's own
rate), and two files depart from the plan's map. A third part of the price comes due only when the package ships a
product per module, which none does yet: an app that links TUIFoundation but not TUIMenus would still carry
`_InlineMenuCore` and its specialised column, which its protocol conformance records keep from being dead-stripped.
How many bytes that is, is unmeasured.

#### B-SPM1-2. `_InlineMenuCore.swift` imports TUIView itself, which M1 did not ask for

*Sources/TUIFoundation/Rendering/_InlineMenuCore.swift — no API*

Back in TUIFoundation, the inline menu's paging-key replay closure carried a `swift_task_isCurrentExecutor`
check that it had not carried in TUIMenus. Swift 6.2.4 marks a closure literal for that check unless the callee's
module is one the calling file imports and is concurrency-checked, or is the caller's own module (CSApply.cpp
L6283-6299). The closure goes to `EffectJournal.Entry` (TUIView), and TUIFoundation reaches TUIView only
through its Exports.swift's `@_exported import`, which counts for no other file. The file in TUIMenus imported
TUIFoundation, and so TUIView. B6s's file imported only TUICore, and had the check too. What ships is one
`import TUIView` in that file, with a comment saying why: the replay, which runs whenever a memo serves an inline
menu, checks the executor no more, as at 4771bb09c.

The fuller version is an audit. The same rule applies to every file the TUIFoundation target compiles that passes
a closure literal to TUIView's (or TUIStyling's, or TUICore's) API without importing that module. At lane SPM1,
before step B7, the target compiled 571 files from six directories (Sources/TUIFoundation and the five planned
modules not yet carved: TUINumericControls, TUITextInput, TUIPickers, TUIForms, TUISearch;
Package.swift's `directories:`), and 124 of them import TUIView (117 of Sources/TUIFoundation's 476). How many of
TUIFoundation's 607 check sites, a count over the whole module, that accounts for is unmeasured, and so is how many
of them run per frame. Its price: an import per file where the index shows such a closure, and Tools/ModuleMap's
`imports` check, which skips TUIFoundation's own files today, extended to them for the lower modules. It is not a
split regression (no carve changed those files' imports), so it belongs to a lane of its own, measured first.

#### B-SPM1-3. Two static totals stay above the base's: every extra site is B6s's, and none adds a check at run time

*`View.bordered`, `renderMenuColumn`, `_InlineMenuCore.registerPagingKeys` — no API*

The brief's gate asks that `swift_task_isCurrentExecutor`, `swift_beginAccess` and stored-property initialiser sites
not exceed 4771bb09c's (1,398, 4,061, 60). After M1 and B-SPM1-2 they are 1,401, 4,063 and 60. Each extra site is in
a function that xc-spB6s, step B6's binary (before B5b), has with the same site:

- **Two executor checks, in `bordered`'s two specialisations,** which M1 brings back. Each copies the generic
  entry's check, which guards the `reduce` closure that nests a second ring around the first. That closure runs only
  for a border wider than one cell, so no menu reaches it.
- **One executor check, in the scrolled branch of `renderMenuColumn`:** `View.frame(width:height:alignment:)`'s
  own check, inlined. 4771bb09c called `frame` out of line and ran the same check inside it.
- **Two exclusivity checks, in `registerPagingKeys` and its replay closure:**
  `KeyEventDispatcher.addHandler(sectionID:_:)`, inlined. 4771bb09c called it out of line and ran the same accesses
  inside it.

What ships leaves them. The other version: `bordered` nests its rings in a loop rather than through `reduce`, which
removes the check from the generic entry and both specialisations (-3: 1,398 in all). The price is a change to code
that every app's `.border()` and `Box` run, made for a static count, with a run-time effect only on borders wider
than one cell. The inlined checks could go only by calling `frame` and `addHandler` out of line again, which is the
kind of cost M1 removes.

### C. Declined

#### C-SPM1-1. Two other opaque results the carved modules resolve at run time

*TUIChrome's `_ToolbarModifier.presentationEntries(depth:context:)`, TUIMenus' `_MenuPopupCore` — no API*

The predictor fix this lane made (session notes, `plan/crossing_hazards.py`, called by the newest carve predictor
`SPB5c/predict.py` and crossing report `SPB5c/xings_b5c.py`) flags, over B5b's and B5c's four modules after M1, two
callees besides the column's:

- **`keyboardShortcut(_:)`**, whose result names the internal `KeyboardShortcutModifier`, from the toolbar rows of a
  presentation (`ToolbarPresentationRows.swift`, a confirmation or cancellation item). The release binary confirms
  one `swift_getOpaqueTypeConformance2` site in `presentationEntries`, which runs whenever that function builds
  such an item's row. Stress uses neither placement, so no benchmark scenario reaches it; how often an app does is
  unmeasured.
- **`focusable(_:)`**, whose result names the internal `FocusableModifier`, from `_MenuPopupCore`. The binary calls
  the runtime only from a lazy witness-table accessor, which caches what it finds, so the lookup happens once per
  process.

Neither is changed here: the first is the same class as M1's, but on no measured path (the remedy would be M1's
pattern, a concrete entry in TUIFoundation), and the second costs nothing per call.

## Completing the SwiftUI API: decisions from lane RES

*Lane RES took the remedies that lane CTL's diagnosis named for the module
split's last two warm residuals against the pre-split build, 2026-10-10:
`controls` (+0.55%, six placements) and `table-tail` (+0.6%, one placement).
R1 makes `Gesture.onEnded(_:)` `@inlinable`; R2 inlines `ItemListHandler`'s
selection getters into `isSelected(at:)`; R3 inlines
`BorderRenderer.standardContentLines` into `_ContainerViewCore`'s
`renderStandardStyle`. None changes public API. This file holds the judgement
call the lane reached that its brief did not already settle, in the format of
[the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>):*

- **A-RES-n — needs your decision.** Nothing has shipped for these.
- **B-RES-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-RES-n — declined.** With the reason.

#### B-RES-1. A container's footer lines are still built by an out-of-line call

*Sources/TUIFoundation/Rendering/BorderRenderer.swift — no API*

**Shipped:** `@inline(__always)` on `standardContentLines`, whose one caller,
`renderStandardStyle`, calls it twice: once for the body's lines, once for the
footer's. Before the split it inlined both; since, neither. Swift 6.2.4 honours
the attribute only while the caller has under 64 basic blocks or the callee at
most 64 (`isInlineAlwaysCallSite` in PerformanceInliner.cpp). This callee has
more, so the body's call, the first, is inlined, and the footer's falls back to
the inliner's cost model, which declines it as on main. Measured in a release
`Stress` (Xcode 6.2.4): `renderStandardStyle` builds the body's lines in its
own code, as the pre-split build did, and makes one call for the footer's
(main: two); `__text` +964 B, against an estimate of about +1.7 KB for both.

The body is what every bordered container draws; the footer is drawn only by a
container that has one, and costs the one call per footer per draw that it
cost on main.

**The other version:** both calls inlined, as before the split. Two ways:

- `@_transparent` instead: the mandatory inliner takes it at every call site,
  but in debug builds too, where stepping into the function stops working; no
  file in `Sources` uses the attribute yet.
- One call site: `renderStandardStyle` builds the body's and the footer's
  lines through one call. The divider between them and the body's known width
  (which the footer's lines do not have) make that a change to a drawing path.

**Price:** about +0.7 KB more `__text` (the estimate for both, less what
shipped; unmeasured), for a gain only where a container has a footer
(unmeasured; one call per footer per draw at most). If the coordinator's
`table-tail` A/B still shows a residual, this is not where it is: that
scenario's bordered container is its `Table`'s, which `Table` builds without
a footer.
