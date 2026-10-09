# Completing the SwiftUI API: decisions from lane SPC1

*Lane SPC1 took step C1 of the module split
([`Module split plan, revision 4`](Historical/Module%20split%20plan,%20revision%204%20(2026-10-07).md),
§5), 2026-10-09: the first PEEL. `Sources/TUIkitPresentation` left the
Navigation group of step B5 for a target of its own, TUIkitPresentation, built
on TUIkitFoundation and TUIkitChrome; the residual TUIkitNavigation compiles
only the navigation containers, on TUIkitFoundation alone. Neither module
depends on the other. The step changed no public API: the umbrella re-exports
TUIkitPresentation beside TUIkitNavigation, so `import TUIkit` gives an app
what it gave before. This file holds the judgement calls the step reached that
the plan did not already settle, in the format of
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md):*

- **A-SPC1-n — needs your decision.** Nothing has shipped for these.
- **B-SPC1-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPC1-n — declined.** With the reason.

## What an app can see

Not judgement calls: the plan (§5, row C9a) lists these for the release notes,
and C9a writes them. They are recorded here because this step made them. Each
name below was `TUIkitNavigation`'s from step B5, `TUIkitFoundation`'s after
step B1, and `TUIkit`'s in v0.6.0.

- **Reflected names.** `String(reflecting:)`, `dump` and the debugger name a
  presentation type's new module: `TUIkitPresentation.Alert<TUIkitFoundation.Button>`,
  `TUIkitPresentation.PresentationDetent`. They
  read `TUIkitNavigation.` from step B5 until this step (decisions SPB5, "What
  an app can see", said they would change here), so a release that ships both
  steps should give the C1 name. `UmbrellaQualifiedNameTests` pins the alert
  and the detent. The navigation containers' names are unchanged
  (`TUIkitNavigation.NavigationPath`).
- **Saved state is unaffected.** No declaration of `Sources/TUIkitPresentation`
  is `Codable` (checked by grep, 2026-10-09), so no saved
  `NavigationPath.CodableRepresentation` names one. The one `Codable` type of
  the two directories, `NavigationSplitViewVisibility`, stays in
  TUIkitNavigation (decisions SPB5, "Saved navigation paths").
- **The bundle is unchanged.** The directory holds Swift files only, so the
  bundle is still `TUIkit_TUIkitStrings` (decisions SPB2).
- **The documentation lists each module's modifiers on `View` and on that
  module's own types only.** `symbolgraph-extract` copies a protocol
  extension's members onto the conforming types of its own module only, and
  the two directories are two modules now: `NavigationStack`'s page lists
  neither `sheet` nor `alert` among its default implementations (it listed
  `sheet` after step B5, decisions SPB5), and `Dialog`'s and `Alert`'s list
  no `inspector`, while `View`'s lists all three (checked in the strict docs
  build's archive, 2026-10-09). The archive has 46,868 pages against step B7's
  47,313. No doc link had resolved only through such a copy: the strict build
  reports nothing.
- **`import TUIkitColorPicker` brings the presentations, and no longer the
  navigation containers**, once per-module products ship: it re-exports
  TUIkitPresentation in place of TUIkitNavigation (its panels are `Dialog`s
  presented through `.modal`; it names nothing of the navigation
  containers'). Through TUIkitPresentation it brings TUIkitChrome as well.
- **`import TUIkitNavigation` no longer brings the presentations, nor
  TUIkitChrome**, once per-module products ship: an app that presents a sheet
  from a `NavigationStack` imports both modules, as plan §4's "Typical" row
  already lists TUIkitPresentation. Under the umbrella, which is the only
  product today, nothing changes.
- **No other module gained an edge.** TUIkitApp, TUIkitChrome, TUIkitLists,
  TUIkitMenus and TUIkitTextInput name no declaration of either directory (the
  pre-peel index: 0 references), and no build error asked for one.

## B. Shipped

### B-SPC1-1. Both modules are ordinary targets at their default paths

*Package.swift — no API*

The brief for this step described the peel in terms of the coarse groups'
`directories:` helper: TUIkitNavigation's list drops
`Sources/TUIkitPresentation`, and a new target compiles that directory.

**Shipped:** each of the two compiles one directory, so each is declared as
an ordinary target at its default path (`Sources/TUIkitNavigation`,
`Sources/TUIkitPresentation`), as TUIkitFoundation became once step B7 took the
last group out of it. Package.swift's own rule says `directories:` (`path:
"Sources"` with the other 32 directories excluded) is for a target that
compiles more than one directory. The files each compiles are the same either
way (the build, and Tools/ModuleMap's `uncompiled` check: 0).

**The other version:** `directories: ["TUIkitNavigation"]` and
`directories: ["TUIkitPresentation"]` through the helper. **Price:** two more
targets over the whole of `Sources` with a 32-entry `exclude:` each, which the
next peel would carry, for no difference in what compiles.

### B-SPC1-2. TUIkitPresentation depends on TUIkitChrome as well as TUIkitFoundation

*Package.swift — no API*

The brief named TUIkitFoundation as the new module's one dependency, citing
plan §1's Presentation row; that row, and `rules.json`'s entry, give it
TUIkitChrome as well.

**Shipped:** both, as the map has them and as the build needs: the
presentations name four TUIkitChrome declarations (the index, 2026-10-09): a
presentation draws its notifications with `NotificationHostModifier`'s
`init(content:width:)` (`View+Presentation.swift`), and a modal docks its
presenter's focus through `notePresentationDock(id:presenter:resolver:)` and
`presenterWentUndrawnUnderItsDock(_:)` (`ModalPresentationModifier+Live.swift`).
The navigation containers name none, so TUIkitNavigation drops the TUIkitChrome
edge it had since step B5b only for the presentations.

**The other version:** TUIkitPresentation on TUIkitFoundation alone. **Price:**
the notification host and the presentation dock move from TUIkitChrome into
TUIkitFoundation, or behind a slot of K1's kind in TUIkitFoundation; step B5b
put both in TUIkitChrome deliberately (the window chrome the run loop draws),
and TUIkitApp, which draws them, would then reach them through
TUIkitFoundation.

### B-SPC1-3. A presentation's background view goes on in TUIkitFoundation; the navigation stack's bar keeps its three run-time type lookups

*Sources/TUIkitPresentation/Views/PresentationBackground.swift, Sources/TUIkitNavigation/Views/NavigationStack.swift — no API*

The crossing predictor, re-pointed at both sides of the peel, flags one
opaque-result hazard on each side; the release Stress shows which run on
every call (SPC1/opqdis.py, on the base's binary and the peel's, which
agree). Both have been there since step B5 carved the two directories out of
TUIkitFoundation, before the predictor had the check (lane SPM1); neither is
the peel's.

- **TUIkitPresentation:** `_PresentationBackgroundView.presentationBackground(behind:)`
  resolved `background(alignment:content:)`'s result at run time on every
  frame of a presentation with a background view. Fixed in this lane: the
  modifier is applied in TUIkitFoundation (`erasedBackground(alignment:_:)`,
  B-SPB7-1's pattern), where the presenter already received an `AnyView`, so
  nothing else changed (opaque-runtime call sites 498 -> 496).
- **TUIkitNavigation:** `_NavigationStackCore`'s bar, drawn on every frame a
  screen is pushed, asks for three conformances: `buttonStyle(_:)`'s result
  (the primitive-style overload, for the Back button's `.borderless`), once in
  `renderBar` and once in `navigationBar`, and `layoutPriority(_:)`'s (the
  subtitle's `-1`) in `navigationBar`, each `swift_getOpaqueTypeConformance2`.
  Stress reaches it in the inbox session's pushed variant and in the notes
  session while a note is open. The predictor sees only `layoutPriority`:
  `buttonStyle(_:)`'s underlying type names an internal type through a generic
  argument (the environment key's value), which it cannot see.

**Shipped for TUIkitNavigation: nothing.** The lookups predate this step and
were inside the coarse stage's measurements, which the coordinator found
neutral against c181ec0f9; the remedy changes what the bar is made of, which
the peel itself does not touch.

**The other version:** B-SPB7-1's: `erasedButtonStyle(_:)` and
`erasedLayoutPriority(_:)` on `View` in TUIkitFoundation, and the bar's Back
button and subtitle built through them. **Price:** two `AnyView`s per pushed
frame (one boxing each, and a render-cache probe on each draw and measure),
unmeasured against the three lookups they replace; the Back button then sits
inside an `AnyView`, so a test that pins its focus identity must be checked;
and the commit's A/B owes the inbox session's pushed variant and the notes
session. Or, without erasure, a `package` view type per modifier in
TUIkitFoundation whose body applies it (the bar names the type, whose `View`
conformance is concrete, and the body's type is resolved inside
TUIkitFoundation). **Price:** two more types, each of which must forward what
its content's type tells a container (B-SPB7-1's caution).

