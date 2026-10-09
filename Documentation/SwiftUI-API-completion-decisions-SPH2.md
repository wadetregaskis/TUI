# Completing the SwiftUI API: decisions from lane SPH2

*Lane SPH2, 2026-10-08, finished what lane SPH found of the module split's run-time costs: it audited every
`@inlinable` added since the pre-modularisation baseline c181ec0f9 for annotations that do not inline, converted the
class stored properties and statics steps B2 and B3 had widened to `package`, and looked again at the per-row
generic crossings SPH left as calls. It changed no public API and no behaviour. This file holds what it found that
the brief did not settle, in the format of
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md):*

- **A-SPH2-n — needs your decision.** Nothing has shipped for these.
- **B-SPH2-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPH2-n — declined.** With the reason.

Every count below is a static count of call sites in a release `Stress` (Xcode's Swift 6.2.4,
`swift build -c release --product Stress -Xswiftc -g`, `otool -tV`, each function attributed to its module by the
debug map), at c181ec0f9 against this lane's last commit, with callers matched by name across the split (module
qualifiers and private discriminators removed). None is a timing; the coordinator's A/B measures time.

## A. Needs your decision

### A-SPH2-1. A `static let` read from another module calls its addressor

*Every module boundary — no API*

Inside one module the optimiser inlines a global's addressor into each read: a check of the global's once-token,
`swift_once` on the slow path, and a load. From another module it cannot see the addressor's body, so each read is a
call to `….unsafeMutableAddressor`. The split moved readers and globals apart, and the counts show the trade:
addressor call sites 672 at c181ec0f9, 1,064 now (+392), and `swift_once` call sites 2,117, now 1,688 (−429). Each
moved read costs one call and return more, whatever the global. The largest:

| global | new cross-module sites | where |
|---|---|---|
| `LocalizationService.shared` (TUIkitStrings since B2) | 157 | every localized label the substrate and the carved modules look up |
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

### A-SPH2-2. A feature-object slot costs a cast on every read

*Sources/TUIkitFoundation/Environment/FeatureObjectSlots.swift (step K1, a2195f6bd) — no API*

K1 made the navigation coordinator, the dialog suppression toggle, the search objects and the notification service
`AnyObject?` environment slots that the substrate declares and clears, each read through its feature's typed
accessor (`self[featureObject: .navigationCoordinator] as? NavigationCoordinator`). A read is still one call into the
environment's storage, as the typed key's was at c181ec0f9, so `@inlinable` on the slot subscript would remove
nothing; what the slot adds is the `as?` (`swift_dynamicCastClass`) and an unknown-object release. TUIkitNavigation
reads or writes a slot at 10 call sites (none at c181ec0f9, where each was a typed key's getter): per
`NavigationLink` row (`_NavigationLinkCore.button`), and in `NavigationStack`'s, the alerts' and the destination
and presentation modifiers' renders. The options:

- **Accept it** (what ships).
- **`unsafeDowncast(_:to:)` in the typed accessors.** The slot is written only through its accessor, and
  `FeatureObjectSlot`'s fixed set means nothing else can write it, so the object is always of the accessor's type; a
  debug build would still check. It removes the cast in release, at the price of trusting that invariant.

### A-SPH2-3. A list row's buffer is borrowed through an out-of-line coroutine

*Sources/TUIkitFoundation/Views/LazyListRowContent.swift (`buffer`), TUIkitLists' row code — no API*

`LazyListRowContent.buffer` is a `_read` accessor, deliberately: it lends the row's `FrameBuffer` rather than copying
it, because a copy (six arrays retained and released) was 1.7% of a `megalist` frame (its doc comment). Inside one
module the accessor inlined. Since step B6 the list's row code is in TUIkitLists, and each read calls the read
coroutine and then its continuation: 25 call sites now, 1 at c181ec0f9, among them `_ListCore.renderRow` (3),
`attachRowPayloads` (5), and the scrollbar, width and overflow walks. Several run per drawn row, on `megalist`'s path.

The toolbox does not reach it. `@inlinable` on the accessor needs the row's cache (`cached`, a class's private stored
property) usable from inline code, which the diagnosis's first rule forbids. It would also buy nothing: a read from
another module would then pay `swift_beginAccess` and `swift_endAccess`, two calls, the coroutine's count. The
options:

- **Accept it** (what ships).
- **Fewer reads.** Each per-row function in TUIkitLists reads its row's buffer once, binding what it uses (`lines`,
  `height`). That is a change to the row code, and each bound array costs a retain.
- **Package queries for the common reads**, such as the height and width, out of line but one call instead of two;
  `renderRow`'s reads of the lines still borrow.
- **Untracked storage** for the resolved buffer (a `ManagedBuffer`, or a pointer), which no exclusivity check covers:
  unsafe, and a design change.

The lane's notes (`SPH2/remaining-cross.txt`) list every call site the release Stress has from one module into
another that c181ec0f9 did not have, with callers matched by name; this and A-SPH2-1's addressors are the largest on
the row paths that no annotation removes. `ANSIRenderer.colorize` (31 sites from TUIkitLists) is B-SPH-1's, priced
there.

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
