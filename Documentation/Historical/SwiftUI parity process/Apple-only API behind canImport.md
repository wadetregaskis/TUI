# Apple-only API behind canImport

*Whether TUI may ship API that exists only on Apple platforms, and what that
opened. Ids: A18, A-PARITYMISC-1, A-O10-1 (in [File panels](<../Presentation and windows/File panels.md>)).*

## In short

The owner, 2026-10-12: "Yes, we can use platform-specific API. I prefer not
to if we have a reasonable alternative, but certainly if it's intrinsically
tied to a specific platform … then that's fine." `@AppStorage`'s `store:`
`UserDefaults` forms shipped behind `canImport` (2026-10-13). Core Data's
`FetchRequest` family became possible, not required; whether to build it now
(A-PARITYMISC-1) was never answered (recommended: when an app asks).

## The record

### A18. Apple-only public API behind `#if canImport`: allowed or not?

**Owner, 2026-10-12 (second message):** option 1. "Yes, we can use platform-specific API. I prefer not to if we
have a reasonable alternative, but certainly if it's intrinsically tied to a specific platform (or the presence of a
specific supporting package/module/whatever), then that's fine." So the `store: UserDefaults` spellings and
`defaultAppStorage(_:)` ship behind `canImport`, Core Data's `FetchRequest` becomes possible for Apple-only apps, and
O10's Linux file exporter may be absent where its type is Apple-only. Lane owed.

**Shipped 2026-10-13** (the storage half; Core Data and O10 remain). On Apple platforms `@AppStorage`'s `store:` takes
a `UserDefaults` in every form SwiftUI has (the tab view and table column customization forms, and `@SceneStorage`'s
tab view one, included), and `View.defaultAppStorage(_:)` and `Scene.defaultAppStorage(_:)` take one; on every
platform both also take a TUI `StorageBackend`. An `@AppStorage` that names no store reads and writes the one set
nearest above its view, found before its body runs and kept in a lock-guarded box the property's copies share — so a
closure the body made writes where the body read — and `StorageDefaults.backend` where none is set. **Which stores
share change announcements** (decided in the lane, a technical call): a `UserDefaults` cannot name its domain, and two
made for one suite — `UserDefaults(suiteName:)` written in a view makes one each time the view is made — are two
objects, so every `UserDefaultsStorage` shares one `StoredKey` per key name. A write through any store over a domain
redraws the readers that read the key through any other; a key of that name in another domain costs its readers a
redraw that finds nothing new. The table lives with `UserDefaultsStorage`, not on the app, because the process's
default store exists before any app does. The alternative, documenting "pass a long-lived `UserDefaults`", would have
left the inline spelling SwiftUI code commonly uses showing stale values.

*Policy, with these symbols waiting on it: `AppStorage`/`SceneStorage`'s
`store: UserDefaults` spellings, `View.defaultAppStorage(_:)`,
`Scene.defaultAppStorage(_:)`; and, if allowed, Core Data's `FetchRequest`
family (declined in the map today)*

The Wave 17 review treats "no Apple-only public API surface" as settled (its
`SectionedFetchRequest` note). The batch has not kept to it:

- **Wave 7** shipped `onDrag`, `onDrop(of:…)`, `DropDelegate`, `itemProvider`
  and the `onCopyCommand`/`onCutCommand` forms that take `NSItemProvider`,
  behind `#if canImport(UniformTypeIdentifiers)`.
- **Wave 13** shipped `Color(cgColor:)`, `Color(nsColor:)`, `NSColor(_:)` and
  `Color.Resolved.cgColor`, behind `canImport(AppKit)`/`(CoreGraphics)`.

Each is honoured where it exists, and absent elsewhere. A Linux build simply
does not offer it, so it cannot compile there and do nothing.

**Options.**

1. **Allow it, behind `canImport`, where the feature is honoured on Apple
   platforms.** Then `store: UserDefaults` and `defaultAppStorage(_:)` ship
   (`UserDefaultsStorage` gains an `init(_ defaults: UserDefaults)`), and Core
   Data's `FetchRequest` becomes possible for macOS-only apps (a few days).
2. **Forbid it.** Remove the Wave 7 and Wave 13 surfaces above, and keep the
   storage spellings TUI's own (`StorageBackend`), with
   `defaultAppStorage(_:)` taking one. A ported `@AppStorage(…, store:
   UserDefaults(…))` then fails to compile.
3. **Allow bridges and value conversions only** (colours, item providers),
   not frameworks (Core Data).

**Recommendation:** 1, with "honoured where it exists" as the test, which is
the rule the batch has been following in practice.
`defaultAppStorage(_:)` also needs `@AppStorage` to resolve its store from
the environment at render, through a nested `@Environment`; that part is
half a day whichever option is chosen.

**Your answer of 2026-10-04:** `canImport` is fine if it fails gracefully.
Absence at compile time is ideal; a failure at run time is acceptable only for
icing, or with a capability query beside it (as the kitty keyboard protocol
has). The shipped bridges meet that: each is honoured where it compiles.
Whether that admitted option 1's framework spellings was left open on
2026-10-04, and answered on 2026-10-12 (above): it does. What remains is
Core Data's `FetchRequest`, unbuilt; O10's file panels shipped with
`FileDocument` on Apple platforms only.

*Wave 9's entries (A20–A25, B34–B41, C9; A19 shipped 2026-10-06): SwiftUI's behaviour is from its own doc comments unless an entry says it was measured.*

### A-PARITYMISC-1. Core Data's FetchRequest family: build it now, or when an app asks?

*`FetchRequest`, `FetchedResults`, `SectionedFetchRequest`,
`SectionedFetchResults`, `EnvironmentValues.managedObjectContext`*

Your A18 ruling (2026-10-12, option 1) allows Apple-only API behind
`#if canImport` where it is honoured on Apple platforms, and says Core Data's
`FetchRequest` "becomes possible" — not that it be built. Nothing is built;
the parity map now says the family is permitted and waiting on this, where it
used to say a policy forbade it.

**Options.**

1. **Build it now.** The property wrappers over `NSFetchRequest` (entity,
   sort descriptors, predicate, animation, and the `fetchRequest:` forms),
   the results collections with their settable `nsPredicate`,
   `sortDescriptors` and section identifier, and `\.managedObjectContext`;
   redrawn when the context announces changes
   (`NSManagedObjectContextObjectsDidChange`), tested on an in-memory store.
   Honoured on macOS, absent on Linux and Windows. *Price:* three to four
   days, and an Apple-only surface to keep working on every macOS SDK the CI
   builds.
2. **When an app asks.** Leave it permitted and unbuilt; the map says why.
   *Price:* nothing now; Core Data code that ports does not compile until
   then.
3. **Decline it after all.** *Price:* nothing; it contradicts nothing in A18,
   which allowed rather than required it.

**Recommendation:** 2. A Core Data app is a GUI app's data layer; a
terminal port of one is rare, and the work is days.
