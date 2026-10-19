# Per-app render state: decisions from lane APPSTATE

*Lane APPSTATE, 2026-10-18, removed `AppState.shared` (CLAUDE.md: "No
Singletons"). Every app — every `TUIContext` — owns its render state: whether
a frame is owed, the transaction the change behind it was made under, the
clocks that ticked and an exit asked for. Two apps in one process, as parallel
tests have, used to draw each other's changes under each other's transactions;
that was the flaky `TransitionMemoTests` (`AppIsolationTests` reproduces it
deterministically). The format is that of the main decisions file:*

- **A-APPSTATE-n — needs your decision.**
- **B-APPSTATE-n — shipped the safe option.** Says what the fuller version
  would be, and its price.
- **C-APPSTATE-n — declined.** With the reason.

## What shipped

- **A `@State` write and an `@Observable` change** ask the app whose render
  cache the view was drawn with: the cache's link holds that app's render
  state, which its `TUIContext` points it at.
- **The run loop's own seams** — its colour and client-capability
  refreshers, the terminal bell, the clipboard writer — ask their context's.
- **The top-level `dismiss()`** is the context's own exit action, put at
  `\.dismiss` in every frame's environment, so a `dismiss` a view read quits
  its own app from wherever it is called.
- **A notification post** asks the apps whose hosts draw the service, which
  note their render cache's link as they draw it.
- **What has no view in hand** asks the app whose work is under way
  (B-APPSTATE-1).

## A. Needs your decision

### A-APPSTATE-1. `LocalizationService.shared` goes with draw-time lookup (LOCALE-B), not before it

*`LocalizationService`, `Text(_:tableName:bundle:comment:)`, `Text(localized:)`,
`LocalizedStringKey.localized`, the `LocalizationKey` initialisers; about 90
sites in the library*

The service holds one language for the process, the strings an app
registered, and the memo of what each key resolved to. Its frame requests no
longer go through a shared render state: `setLanguage(_:)` and
`register(translations:)` ask the app whose work made the change
(B-APPSTATE-1). The service itself is still `LocalizationService.shared`.

Removing it is not a matter of injecting it: most of its readers resolve a key
**when a view is made** — `Text("Cancel")`, `Button(LocalizationKey.Button.ok)`,
an alert preset's title — where there is no environment to read a service
from. A service per app needs every such read to happen when the view is
**drawn**, from the environment, which is the "lazy lookup at draw" of your
ruling on LOCALE-B (2026-10-15), assigned to lane PARITYMISC and in flight
beside this one. Building it here as well would have been the same rewrite of
`Text` twice, in parallel.

Options, once draw-time lookup lands:

- **(a) A service per app.** `TUIContext` owns one, the environment carries it
  (`\.localizationService`, public), views resolve from it at draw, and an app
  changes its language through it. `.shared` is deleted, and
  `LocalizedStringKey.localized` takes a service. About two days after LOCALE-B,
  across about 50 files; an A/B is owed on the Text-heavy scenarios.
- **(b) The locale is the language, as SwiftUI's is.** What LOCALE-B points at:
  `\.locale` picks the language a key is looked up in, per app and per
  subtree, so "the current language" stops being process state at all. The
  service shrinks to the translation tables and the strings the app
  registered — a cache, like SINGLETON-CACHES' two — and the persisted choice
  becomes the app's own `@AppStorage`. About the price of (a), plus moving
  the language picker's API onto `\.locale`.
- **(c) Keep one service for the process.** Two apps in one process share a
  language; an app is one per process outside the tests, which pin English
  (`.rendersEnglishUI`).

**Recommendation: (b)**, built on LOCALE-B, with the tables cache decided
together with SINGLETON-CACHES.

### A-APPSTATE-2. Three more process-wide statics: the notification queue, the default store, the URL opener

*`NotificationService.current`, `StorageDefaults.backend`,
`TerminalURLOpening.runLoopOpener`*

The inventory named four shared instances (census D-7); a search for mutable
statics finds three more. None holds a frame request any longer — a post asks
the apps that draw its host, a store write asks the app whose work made it —
so none can draw one app's change in another. What each still shares:

- **`NotificationService.current`** (public): one queue of toasts for the
  process; two apps in one process show each other's. It is static because a
  post is made at event time, from a closure, where the type's own
  documentation says there is no environment to read. Making it per app is a
  `TUIContext` service published at `\.notificationService` (it already is
  read from there), posted to through a value the view captured at render,
  and `.current` deleted: about half a day, and an API change for every app
  that posts from a button action.
- **`StorageDefaults.backend`** (public): the store `@AppStorage` reads when
  nothing names one. SwiftUI's is `UserDefaults.standard`, itself one per
  process, and an app or a subtree names another with
  `.defaultAppStorage(_:)`, so sharing it is SwiftUI's model.
- **`TerminalURLOpening.runLoopOpener`** (package): the running app's URL
  opener, published for an `OpenURLAction` the app made itself and calls
  directly, which has no environment either. One app runs per process.

**Recommendation:** exempt `StorageDefaults.backend` (SwiftUI's model) and
`runLoopOpener` (one runner per process, package-only), documented on the
CLAUDE.md rule with the caches of SINGLETON-CACHES; make the notification
queue per app in a later lane, with the API change.

## B. Shipped the safe option

### B-APPSTATE-1. A change with no view in hand asks the app whose work made it

*`AmbientApp.renderState`, a task local in TUIkitCore; `StoredKey.didChange()`,
`LocalizationService.setLanguage(_:)`, `register(translations:)`,
`DismissAction()`, `reportObservedChange(at:to:fallback:)`*

A few changes are made with nothing that names an app: an `@AppStorage`
write, whose frame is for a control that read the key unobserved; a change of
language; a bare `DismissAction()`; an observed change drawn with no render
cache. They ask the render state of the app whose work is under way, a task
local that `AppRunner.run()` binds around its whole run and `HeadlessApp`
around each frame and event, and that a `Task` an app starts inherits. A
change made outside every app's work — on a queue a framework calls back on —
asks no app; what read the change under observation still asks its own.

**The fuller version** names the app at every such seam: each `@AppStorage`
key notes, as its property is walked, the apps that draw it, and a write asks
them all, wherever it was made; the localization service is per app
(A-APPSTATE-1). **Price:** a lock and a lookup per `@AppStorage` property per
walk, and a list of weak references per key; about half a day. Nothing seen
so far writes a stored key off every app's task with a reader no observation
saw.

### B-APPSTATE-2. An observed change reported with no transaction takes the next scope's

*`AppState.transactionScopeEnded(_:)`, `withTransaction(_:_:)`,
`RenderCache.Link.invalidateRenderForObservedChange(at:)`*

```swift
model.selection = item
withAnimation { model.isExpanded = true }
```

With one body reading both, the first write fired the body's observation —
it fires once, at the first write to anything the body read — with no
transaction in force, and the animated write found no observation left to
report it: its transaction was recorded nowhere, and the change snapped.
Swapping the two writes animated it. SwiftUI animates it in either order
(`Tools/SwiftUIProbes/Transactions of observed changes/txn.out`).

Observation's public API cannot say which properties a later scope wrote. So
an observed change reported with no transaction is noted, and a
`withTransaction` scope ending in the same app's work before the frame
(`AmbientApp`) gives the frame its transaction if none is pending yet. The
cost of not knowing: an unanimated observed change followed by a
`withAnimation` that changed nothing any body read is drawn animated too,
where SwiftUI draws it unanimated (deviation A7).

**The fuller version** re-arms a fired observation for the rest of the event,
so the later write reports itself with its own transaction. That needs the
access list a scope read, which only Observation's `@_spi(SwiftUI)`
`ObservationTracking._installTracking` exposes: an SPI dependency the Linux,
Windows and WebAssembly toolchains need not keep, and one more registration
a body. Not worth it for a scope that animates nothing.
