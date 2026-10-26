# Completing the SwiftUI API: decisions from lane SPH2

*Lane SPH2, 2026-10-08, finished what lane SPH found of the module split's run-time costs: it audited every
`@inlinable` added since the pre-modularisation baseline c181ec0f9 for annotations that do not inline, converted the
class stored properties and statics steps B2 and B3 had widened to `package`, and looked again at the per-row
generic crossings SPH left as calls. It changed no public API and no behaviour. This file holds what it found that
the brief did not settle, in the format of
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>):*

- **A-SPH2-n — needs your decision.** Nothing has shipped for these.
- **B-SPH2-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPH2-n — declined.** With the reason.

Every count below is a static count of call sites in a release `Stress` (Xcode's Swift 6.2.4,
`swift build -c release --product Stress -Xswiftc -g`, `otool -tV`, each function attributed to its module by the
debug map), at c181ec0f9 against this lane's last commit, with callers matched by name across the split (module
qualifiers and private discriminators removed). None is a timing; the coordinator's A/B measures time.

## A. Needs your decision

### A-SPH2-1. A `static let` read from another module calls its addressor — decided: keep the addressor

*Every module boundary — no API*

**Owner (2026-10-12): keep the addressor.** A read of a global from another module stays one call, as shipped.
Computed constants (`@inlinable static var` in place of `static let`, for the per-row readers named below) stay a
future optimisation, taken up only if a profile shows a real-world cost from these calls; they are recorded in
[Future options](<../../../Future options.md#computed-constants-for-globals-read-across-modules>). The ruling does not cover
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

### A-SPH2-2. A feature-object slot costs a cast on every read — decided: the cast stays

*Sources/TUIFoundation/Environment/FeatureObjectSlots.swift (step K1, a2195f6bd) — no API*

**Owner (2026-10-12): keep the `as?`.** TUI uses `unsafeDowncast` only where the cast is guaranteed by
construction, and here it is not. That a slot holds its accessor's type is a convention: `subscript(featureObject:)`
is `package`, so any module of the package can write any object into any slot, and only review would notice. With
`as?` a wrong object reads as absent; with `unsafeDowncast` it would be undefined behaviour in release. The second
option below rests on that convention, so it is not taken. A design that does make the cast provable, typed slot
keys written through one generic subscript into private storage, is recorded in
[Future options](<../../../Future options.md#typed-feature-object-keys>); it needs storage of its own in `EnvironmentValues`,
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

### A-SPH2-3. A list row's buffer is borrowed through an out-of-line coroutine — superseded

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

## C. Declined

### C-SPH2-1. The per-row generic crossings SPH left as calls are not split costs

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
