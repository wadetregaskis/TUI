# Completing the SwiftUI API: decisions from lane SPB5

*Lane SPB5 took step B5 of the module split
([`Module split plan, revision 4`](<../../../Historical/Module split plan, revision 4 (2026-10-07).md>),
§5), 2026-10-08: the carve of the Navigation group, the third module built on
TUIkitFoundation rather than under it, after TUIkitApp and TUIkitColorPicker,
and the first coarse group: one target, TUIkitNavigation, that compiles two
planned modules' directories, `Sources/TUIkitNavigation` and
`Sources/TUIkitPresentation`, until step C1 peels the second into a target of
its own. It changed no public API: the umbrella re-exports TUIkitNavigation
beside TUIkitFoundation, so `import TUIkit` gives an app what it gave before.
This file holds the judgement calls the step reached that the plan did not
already settle, in the format of
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>):*

- **A-SPB5-n — needs your decision.** Nothing has shipped for these.
- **B-SPB5-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPB5-n — declined.** With the reason.

## What an app can see

Not judgement calls: the plan (§5, row C9a) lists these for the release notes,
and C9a writes them. They are recorded here because this step made them. Each
name below was `TUIkitFoundation`'s after step B1, and `TUIkit`'s in v0.6.0.

- **Reflected names.** `String(reflecting:)`, `dump` and the debugger name a
  moved type's new module: `TUIkitNavigation.NavigationPath`,
  `TUIkitNavigation.NavigationSplitViewVisibility`. That includes the types
  of `Sources/TUIkitPresentation`, which compile into TUIkitNavigation until
  step C1: `TUIkitNavigation.Alert<TUIkitFoundation.Button>`,
  `TUIkitNavigation.PresentationDetent`. Those names change again at C1, to
  `TUIkitPresentation.`, so the release notes should give the C1 name for a
  presentation type if C1 ships in the same release. `UmbrellaQualifiedNameTests`
  pins all four.
- **Saved navigation paths.** `NavigationSplitViewVisibility` is the one
  public `Codable` type of the two directories. A
  `NavigationPath.CodableRepresentation` stores each value's mangled type
  name, so a saved path holding one names TUIkitNavigation now, and a path
  saved between steps B1 and B5 (naming TUIkitFoundation) no longer decodes.
  `NavigationPathCodableTests` pins the new name, and `NavigationPath.codable`'s
  doc comment lists it among the types that moved. Paths holding only an
  app's own types, the usual case, are unaffected.
- **The bundle is unchanged.** Neither directory holds a resource (both hold
  Swift files only; the alerts' and dialogs' labels come from TUIkitStrings'
  tables through `LocalizationService`), so the bundle is still
  `TUIkit_TUIkitStrings` (decisions SPB2).
- **The documentation lists the group's modifiers on `View` and on the
  group's own types, not on TUIkitFoundation's.** `symbolgraph-extract` copies
  a protocol extension's members onto the conforming types of its own module
  only. So `Text`'s page no longer lists `sheet(isPresented:onDismiss:content:)`
  among its default implementations, while `View`'s and `NavigationStack`'s
  pages still do, and so does `Text`'s for TUIkitFoundation's
  `popover(isPresented:attachmentAnchor:arrowEdge:content:)` (checked in the
  strict docs build's archive, 2026-10-08). The archive has 63,396 pages
  against step B4's 69,823, on the same tree but for this step; how many of
  the 6,427 are such copies was not counted. Two doc links had resolved only
  through those copies and now name their declaring type
  (`PopoverPresentationModifier.swift`, `NavigationSplitViewStyle+Variants.swift`).
- **`import TUIkitColorPicker` brings the navigation containers too**, once
  per-module products ship: it re-exports TUIkitNavigation, its new direct
  dependency (its panels are `Dialog`s presented through `.modal`). After C1
  it re-exports TUIkitPresentation instead. Under the umbrella, which is the
  only product today, nothing changes.

## B. Shipped

### B-SPB5-1. Tools/ModuleMap checks a coarse group's members as the modules the map plans

*`Tools/ModuleMap` (its README's "Coarse groups") — no API, no code*

The step's brief asked that the module map's upward, witness and lower checks
treat the group as one compile unit until C1, since `map.json` still gives the
files under `Sources/TUIkitPresentation` to TUIkitPresentation while they
compile into TUIkitNavigation.

The checks have never modelled targets. They hold every planned module to the
planned map, including the fifteen that TUIkitFoundation still compiles as one
module, and a group is the same case at a smaller scale. For a group that is
stricter than the build and never looser: the group's target sees everything
its members' planned dependencies give them (TUIkitPresentation's edge to
TUIkitChrome is satisfied inside TUIkitFoundation until step B5b), so what
passes the checks compiles. The only findings a one-unit view would remove are
edges between the two members. Those compile in the group, but step C1 would
have to break each of them before it could peel TUIkitPresentation. On this
tree there are none: `check` reports 0 new findings before and after the
carve, and `assign` moves no declaration.

**Shipped: no change to the checks.** The README documents how the tool reads a
group: the index's units name the group's target, which the tool reads like any
module of the map; a member's file that the group's `sources:` leaves out is an
`uncompiled` finding; and an edge between members stays a finding. Steps B6
and B7 need nothing more here.

**The other version:** a `groups` entry in `rules.json` (`{"TUIkitNavigation":
["TUIkitPresentation"]}`), with `Rules.sees` answering yes between members
until the entry is removed at the peel, so that `upward`, `witness` and `lower`
treat the group as one module. **Price:** about 20 lines in `rules.py` and the
three checks, two unit tests, and one entry per group. The cost is that, until
C1, a reference from `Sources/TUIkitNavigation` to `Sources/TUIkitPresentation`
(or back) passes CI. C1 then has to break that edge, or keep the two modules
together, which the plan's map does not allow. Worth taking only if the owner
wants the coarse stage to allow such edges.

### B-SPB5-2. The group's target lists every other directory under Sources in `exclude:`

*Package.swift — no API*

A target with `path: "Sources"` and a `sources:` list still sees every other
file under `Sources`, and SwiftPM reports each one it does not compile as
unhandled ("found N file(s) which are unhandled", a warning). This was checked
on a three-target probe package, and TUIkitFoundation's own comment says the
same. So TUIkitNavigation's target names its two directories in `sources:` and
the other 31 in `exclude:`, as TUIkitFoundation does.

**Shipped: the literal list.** It stays fixed until C1 (the carves of B5b, B5c,
B6 and B7 exclude directories it already excludes). Only a new directory under
`Sources` changes it, and the zero-warnings gate catches one that is left out.

**The other version:** one list of `Sources`' directories at the top of the
manifest, with each `path: "Sources"` target excluding the complement of its
own `sources:` (TUIkitFoundation's too, and B6's and B7's groups). **Price:**
reworking TUIkitFoundation's declaration as well as the new one, in a pure
refactor commit first. It pays off once B6 and B7 have added two more
31-entry lists, and either step can do it then.
