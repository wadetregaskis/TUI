# Completing the SwiftUI API: decisions from lane SPB5

*Lane SPB5 took step B5 of the module split
([`Module split plan, revision 4`](Historical/Module%20split%20plan,%20revision%204%20(2026-10-07).md),
§5), 2026-10-08: the carve of the Navigation group, the third module built on
TUIkitFoundation rather than under it, after TUIkitApp and TUIkitColorPicker,
and the first coarse group: one target, TUIkitNavigation, that compiles two
planned modules' directories, `Sources/TUIkitNavigation` and
`Sources/TUIkitPresentation`, until step C1 peels the second into a target of
its own. It changed no public API: the umbrella re-exports TUIkitNavigation
beside TUIkitFoundation, so `import TUIkit` gives an app what it gave before.
This file holds the judgement calls the step reached that the plan did not
already settle, in the format of
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md):*

- **A-SPB5-n — needs your decision.** Nothing has shipped for these.
- **B-SPB5-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPB5-n — declined.** With the reason.

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
