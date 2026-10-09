# Completing the SwiftUI API: decisions from lane SPB5b

*Lane SPB5b took step B5b of the module split
([`Module split plan, revision 4`](Historical/Module%20split%20plan,%20revision%204%20(2026-10-07).md),
§5), 2026-10-09: the carve of three leaves built on TUIkitFoundation, each a
module of the plan's map and a target of its own, not a coarse group:
TUIkitChrome (`Sources/TUIkitChrome`: the status bar view, toolbars,
notifications, tooltips and `.help`, the window chrome host, the overlay
compositor, the screen selection's highlight and Copy menu), TUIkitEffects
(`Sources/TUIkitEffects`: transitions, content transitions, `.symbolEffect`,
`.visualEffect`, `.scrollTransition` and the colour effects) and TUIkitMenus
(`Sources/TUIkitMenus`: `Menu`, `ControlGroup`, `.contextMenu`, `.menuStyle`
and the menu styles). It changed no public API: the umbrella re-exports all
three beside TUIkitFoundation, so `import TUIkit` gives an app what it gave
before. This file holds the judgement calls the step reached that the plan did
not already settle, in the format of
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md):*

- **A-SPB5b-n — needs your decision.** Nothing has shipped for these.
- **B-SPB5b-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPB5b-n — declined.** With the reason.

## What an app can see

Not judgement calls: the plan (§5, row C9a) lists these for the release notes,
and C9a writes them. They are recorded here because this step made them. Each
name below was `TUIkitFoundation`'s after step B1, and `TUIkit`'s in v0.6.0.

- **Reflected names.** `String(reflecting:)`, `dump` and the debugger name a
  moved type's new module: `TUIkitChrome.StatusBar`,
  `TUIkitChrome.NotificationService`, `TUIkitChrome.ToolbarItem<…>`,
  `TUIkitEffects.AnyTransition`, `TUIkitEffects.ScrollTransitionPhase`,
  `TUIkitMenus.Menu<…>`, `TUIkitMenus.MenuOrder`. `UmbrellaQualifiedNameTests`
  pins one from each module. The plan's map moves no type between these
  modules later, so these names are final.
- **Saved state is unaffected.** None of the three declares a `Codable` type.
  Three of their public types are `Hashable` (`TransitionPhase`,
  `ScrollTransitionPhase`, `MenuOrder`) and so can be values of a
  `NavigationPath`, but a path holding one has no `codable` representation,
  which is the only saved form that stores type names (decisions SPB5, "Saved
  navigation paths").
- **The bundle is unchanged.** The three directories hold Swift files only, so
  the bundle is still `TUIkit_TUIkitStrings` (decisions SPB2).
- **The documentation lists the three modules' modifiers on `View` and on
  their own types, not on TUIkitFoundation's.** As at steps B5 and B6:
  `symbolgraph-extract` copies a protocol extension's members onto the
  conforming types of its own module only, so `Text`'s page no longer lists
  `toolbar(content:)`, `help(_:)`, `transition(_:)`, `contextMenu(menuItems:)`
  or `menuStyle(_:)` among its default implementations, while `View`'s page
  still does, and so do the new modules' own types' (`Menu`'s lists
  `contextMenu` and `menuStyle`, `StatusBar`'s `help` and `toolbar`):
  checked in the strict docs build's archive, 2026-10-09. The archive has
  55,840 pages against step B6's 59,764; how many of the 3,924 are such
  copies was not counted. No doc link had resolved only through one: the
  strict build reports nothing.
- **The modules' edges, which is what each import will bring once per-module
  products ship.** Each of the three depends on TUIkitFoundation alone and
  re-exports it. TUIkitApp depends on TUIkitChrome (the run loop draws the
  window chrome, the status bar and the notifications around the content) and
  re-exports it, so `import TUIkitApp` brings `.toolbar`, `.help` and
  `.statusBarItems`, as plan §4 has it. TUIkitNavigation depends on
  TUIkitChrome too (the map's edge from Presentation, whose directory it
  compiles until step C1: a presentation draws its notifications with
  `notificationHost(width:)`, and a modal docks its presenter through the
  presentation dock) and re-exports it, so `import TUIkitNavigation` brings
  the window chrome as well. No module depends on TUIkitEffects or
  TUIkitMenus but the umbrella: `import TUIkitApp` does not bring `Menu`,
  `.contextMenu` or `.transition` (plan §4, "…with row context menus:
  + TUIkitMenus"). TUIkitLists and TUIkitColorPicker gained no edge: the
  pre-carve index records no reference from either to a declaration of the
  three (and neither did the build ask for one).

## B. Shipped

### B-SPB5b-1. The three modules are targets at their default paths, not `directories:` targets of one directory each

*Package.swift — no API*

The step's brief asked for the three targets "using the `directories:` helper
B6 added". The manifest's own rule, beside that helper, is the other way:
the helper is for "a target that compiles more than one" directory under
Sources, and "a carve adds `.target(name: "TUIkitX", …)` at its default path"
(TUIkitFoundation's comment), as steps B2, B3 and B4 did.

**Shipped:** `.target(name: "TUIkitChrome", dependencies: ["TUIkitFoundation"],
…)` and the same for the other two, at `Sources/TUIkitChrome` and so on, as
TUIkitApp is. SwiftPM compiles the same files either way.

**The other version:** `.target(name: "TUIkitChrome", …, directories:
["TUIkitChrome"])`, which passes `path: "Sources"`, `sources:` the one
directory and `exclude:` the rest. **Price:** none in the build; the
helper's comment and TUIkitFoundation's would then have to say that a single
module may use it too, and every later single-module carve would choose.

### B-SPB5b-2. The presentation dock reaches the focus manager's pane ledger through methods, not through `panes`

*Sources/TUIkitFoundation/Focus/FocusManagerPanes.swift, Sources/TUIkitChrome/Focus/FocusManagerPresentationDock.swift — no API*

`FocusManagerPresentationDock.swift`, which the map puts in TUIkitChrome,
extends `FocusManager` and read and wrote its `panes`, a stored property of
the class that holds the docks each live sheet posts. CONTRIBUTING.md
("Crossing a module boundary") forbids widening a class's stored property and
offers a `package` accessor over private storage instead. A `get`/`set`
accessor over the whole ledger would copy it at every write through it, and
each write here changes one of its dictionaries or sets in place
(`docks[id] = …`, `dockedBeforeTheWalk.insert(id)`): each would copy that
collection.

**Shipped:** seven small `package` members on `FocusManager`, beside the
pane members in FocusManagerPanes.swift, one per thing the dock does
(`postDock(inSection:presenter:resolver:)`, `postedDocks`,
`previouslyPostedDocks`, `noteDockedBeforeTheWalk(_:)`,
`anyDockedBeforeTheWalk`, `noteDocksLeftUndrawn(windowedOut:)`,
`isUndrawnUnderItsDock(_:)`). `panes` stays internal; `PaneLedger` and its
`PostedDock` are `package` only because two of those members return the
docks. Each runs once per frame, or once per live sheet per frame.

**The other version:** a `package func updatePanes(_ body: (inout
PaneLedger) -> Void)`, one member in place of seven. **Price:** every field
of the ledger would be `package`, and the dock's code would mutate the
ledger inside a closure.

### B-SPB5b-3. The colour effects call `SGRColorRewrite.rewriting` out of line, not `@inlinable`

*Sources/TUIkitFoundation/Modifiers/OpacityModifier.swift — no API*

The plan (§5, "The per-row crossings") names `@inlinable package` on
`rewriting` as the remedy if the colour effects' crossing shows. The static
picture in a release `Stress` (Xcode's Swift 6.2.4) says it would cost more
than it saves:

- Before the carve, `rewriting` was inlined into the effects' per-line
  closures, and its per-escape call went to a copy of `rewritingSGR`
  specialised with its `emitted` parameter's default (a closure that does
  nothing) propagated and removed.
- After it, each line makes one direct call to `rewriting` (268 bytes, in
  TUIkitFoundation), whose per-escape call still goes to that specialised
  copy. The `transform` closure is called once per colour code in both, as
  before: no specialisation of the transform existed before the carve either.
- `@inlinable` on `rewriting` would inline it into TUIkitEffects, which cannot
  see `rewritingSGR`'s body: each escape sequence would then call the general
  `rewritingSGR` with the default `emitted`, an indirect call per colour code
  in place of one direct call per line.

**Shipped:** neither annotation; one call per line. The coordinator's A/B
measures it (`modifiers --variant color-effects`).

**The other version:** `@inlinable` on both `rewriting` and `rewritingSGR`
(and `@usableFromInline` on `SGRColorRewrite`, `extendedColor`,
`rewrittenBasic` and `colonFormColor`), so that TUIkitEffects specialises the
whole rewrite. **Price:** about 3 KB of `rewritingSGR` compiled again in
TUIkitEffects, and five more declarations exposed, for one call per line. Or
the plan's other remedy, `ColorEffectModifiers.swift` back in TUIkitFoundation
(≈0.1 s of its build).

### B-SPB5b-4. An open menu's popup draws through the unspecialised `renderMenuPopup`

*Sources/TUIkitFoundation/Modifiers/MenuPopover.swift — no API*

Before the carve, TUIkitFoundation held two specialisations of
`renderMenuPopup<Items>`, for `MenuStyleConfiguration.Content` (a `Menu`'s
popup) and for `Button` (the screen selection's Copy menu), 4,716 bytes each
(c181ec0f9 held four, 18.9 KB, which option S1a's no-specialise attribute was
to save). Their callers moved to TUIkitMenus and TUIkitChrome, which call
`presentMenuPopover<Items>` across the boundary, unspecialised, as the lists'
and tables' row menus have since step B6: the carve removes both copies
(−9.4 KB), so S1a has nothing left to save. What runs unspecialised is the
popup's frame, once per frame while a menu is open: the column's stack over
its items (`_MenuSectionedItems<Items>`), its anchor and placement. Each row
reaches that stack as a type-erased child either way, and draws through
TUIkitFoundation's menu engine (the row, its highlight, the row sink), which
did not move.

**Shipped:** nothing; the coordinator's A/B measures it (`menus`).

**The other version:** `@_specialize(exported: true, where Items ==
MenuStyleConfiguration.Content)` on `presentMenuPopover`, which TUIkitFoundation
can name because the type is its own: the copy comes back, and TUIkitMenus
calls it. **Price:** an underscored attribute (the owner's call, as SPH3's
B-SPH3-1 put it), and the 4.7 KB back. `@inlinable` instead would need the
whole popup machinery `@usableFromInline`.

## C. Declined

### C-SPB5b-1. Step 0a, the profile of M3's cold truncate and app-shapes runs, is not run

*Plan §5, row 0a — nothing*

The plan made step 0a binding before B5b, because M3's trial split held 22
of the 42 files TUIkitChrome and TUIkitEffects take, and its app-shapes cold
regression (+2.3%) was never attributed. Since step B5 each carve is checked
by another method, which this step follows: static gates in a release
`Stress` against the pre-modularisation build's (c181ec0f9) and against the
carve's base, the coordinator's A/B against c181ec0f9, and a profile of any
residual before landing (SPH, SPH2, SPH3). That method measures this carve's
own boundary, where 0a would have profiled a different split's; the brief
for this step marks 0a superseded.
