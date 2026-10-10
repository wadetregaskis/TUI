# Tools/ModuleMap

TUIkit is to be split into à-la-carte modules: the substrate (TUIkitFoundation), side modules that compile beside the
lower ones, feature leaves over the substrate, TUIkitApp and a thin `TUIkit` umbrella. `rules.json` lists them and
what each holds. Since step A5 each module's files sit in a directory of their own, `Sources/<module>`
(`Sources/TUIkitFoundation`, `Sources/TUIkitLists` …), where the module lives once a step of Phase B carves it out;
from step B1 the one `TUIkitFoundation` target compiled them all (`TUIkit` is the umbrella, which only re-exports),
until step B7 carved the last of them out. Carved: TUIkitStrings and TUIkitTerminalHost (step B2), targets of their
own that TUIkitFoundation depends on and re-exports, and TUIkitApp (step B3), TUIkitColorPicker (step B4),
TUIkitNavigation (step B5), TUIkitLists (step B6), TUIkitChrome, TUIkitEffects and TUIkitMenus (step B5b),
TUIkitBitmaps (step B5c), TUIkitTextInput (step B7), TUIkitPresentation (step C1), TUIkitTables and TUIkitTabs
(steps C2 and C3, which also depend on TUIkitLists), TUIkitGrid (step C4), TUIkitForms (step C6) and TUIkitSearch
(step C5, which also depends on TUIkitTextInput), targets of their own that depend on TUIkitFoundation and that the
umbrella re-exports. TUIkitTextInput is a **coarse group**: one target compiling several planned modules'
directories, `Sources/TUIkitTextInput`, `TUIkitPickers` and `TUIkitNumericControls`, until steps C7 and C8 peel the
last two (and `TUIkitForms` and `TUIkitSearch` until steps C6 and C5 peeled them). TUIkitNavigation was one, over
`Sources/TUIkitNavigation` and `Sources/TUIkitPresentation`, until step C1 peeled the second into a target of its own,
and TUIkitLists another, over `Sources/TUIkitLists`, `TUIkitTables`, `TUIkitTabs` and `TUIkitGrid`, until steps C2 to
C4 peeled the last three (see [Coarse groups](#coarse-groups)).
`TUIkitFoundation` is an ordinary target at `Sources/TUIkitFoundation` since step B7. **A file's directory is its module**: moving a file to another module is a `git mv`. This tool holds:

- the planned map: which module each declaration will live in;
- the assigner that computes the map from a short list of rules;
- the checks that report what the map would break.

The checks run on the **assignment**, not on real modules. A finding says that, under the map, this code would
reference something its module cannot see, or would fall into one of the other traps below. New code therefore
cannot add a cycle that the migration would later have to break.

```bash
swift build                                         # any debug build writes the index store this reads
python3 Tools/ModuleMap/modulemap.py check          # findings under map.json; exit 1 on a new one
python3 Tools/ModuleMap/modulemap.py assign         # re-run the assigner; what would change in map.json
python3 Tools/ModuleMap/modulemap.py assign --write # ... and rewrite map.json (review the diff)
python3 Tools/ModuleMap/modulemap.py explain 'ViewRenderer'   # where those declarations go, and why
python3 -m unittest discover -s Tools/ModuleMap     # the tool's own tests: no build, no index
```

It needs only Python 3's standard library and the toolchain's `libIndexStore`, which it loads through `ctypes`.
It finds the library beside the `swift` that `xcrun` or `PATH` resolves to; set `MODULEMAP_LIBINDEXSTORE` to
override. It reads the index store a debug build on macOS wrote last: `.build/<triple>/debug/index/store` from
SwiftPM's native build system, or `.build/out` from Swift Build (`--build-system swiftbuild`, SwiftPM's default
from 6.4; 6.2.4's Swift Build wrote no store). Pass `--store` to use another. If a source file is newer than its
index unit, it warns: rebuild, then check again.

**Cost.** Measured on HEAD 4611730eb, 793 files and 262k index occurrences:
- reading the store: about 2 s;
- `check`: 2.3–2.9 s in all;
- `assign`: 0.2 s more.

## Files

| File | What it is | Who edits it |
|---|---|---|
| `rules.json` | The modules and what each depends on. The declaration placements. The scheduled refactors, the accepted findings, the POSIX API list, and the witness pairs. | You, by hand |
| `map.json` | The assignment: a module for each file, since A5 the file's directory. A split file names a module for each of its declarations. | `assign --write` only |
| `modulemap.py` | The command line, plus reading and writing `map.json` | |
| `model.py` | The declaration graph, from the index and the sources | |
| `assigner.py` | rules + graph → assignment | |
| `checks.py` | The checks | |
| `indexstore.py`, `swiftsource.py` | Reading the index store, and just enough of a Swift lexer | |

The design behind the map is `Documentation/Historical/Module split plan, revision 4 (2026-10-07).md` (the refined
plan, after the owner's answers of 2026-10-07; why it exists is in `Compile time and binary size analysis
(2026-10-07).md` beside it). This tool is the plan's step A1; `rules.json` is revision 4's map, committed at step A1′
with the `lower` lists, and its base module is named TUIkitFoundation (the owner's choice, after the plan was written). The assigner is the research assigner
(`split2/plan/w/sassign.py` + `finalize.py`) ported. On HEAD 4611730eb it gave every one of the 4,127 declarations the
same module as the re-indexed research run (`split2/reindex/`).

## The graph

- **A declaration** is a top-level one: a type, an extension, a protocol, or a top-level function, variable or
  typealias. Members belong to it, because the split moves whole declarations and cuts nothing inside one.
- **An edge** A → B counts A's references to B. Two kinds of occurrence count:
  - a reference;
  - an *implicit* occurrence that records a conformance taking its witness from a default implementation in an
    extension. That makes the extension a dependency of the conforming type.
- **Charging a reference.** A reference the index gives a container is charged to that container's declaration. A
  reference with no container is charged **by span**: to the declaration whose text (doc comment and attributes
  included) holds the line. Typealias right-hand sides, inheritance and `where` clauses are the usual cases.
  - The research graph charged such a reference to the next declaration within three lines. That hid two cycles
    (plan §4, X1 and X2).
- **Labels.** A declaration is named `path::Name`. An extension is `path::Name(ext)#first`: `first` is its first
  member (`View(ext)#listStyle(_:)`), or for an extension with no members the protocols it conforms to
  (`T(ext)#Equatable&Sendable`). A label comes from the declaration's own text, not its position, so an extension
  added above another does not take over its entry in `map.json`. Labels still equal in one file (constrained
  extensions that open with the same initializer) get `#2`, `#3` … in source order.

## The checks

Every finding has a key. A finding listed under `scheduled` or `accepted` in `rules.json` is reported but does
not count as new. Only new findings fail `check`, or raise an annotation in CI.

### `uncompiled`: a file in a module's directory that no target compiles

`TUIkitStrings: TUIkitStrings/Localization/Foo.swift is compiled by no target, though the last build ran after it was written: …`

From step A5 to step B7 the one target that compiled them (`TUIkitFoundation` from step B1) named the module
directories in its `sources:` (Package.swift; its `directories:` from step B6, which the manifest passes to SwiftPM
as `sources:`, with every other directory of the manifest's `sourcesDirectories` list as `exclude:`); a coarse group
still does. So a module directory added to `rules.json` and to no target (its own, or a group's `directories:`) is
compiled by no target, and its declarations, public API included, are simply missing. Until step B2 carved it, TUIkitStrings was listed below its
own directory, one entry per subdirectory and per `Localization/*.swift` file, because a resource may not sit under
a declared source path, so a new file there was the same case; its own target takes every file in its directory now.
SwiftPM says nothing about such a directory once it is in `sourcesDirectories`, as the manifest asks of every
directory under Sources: each target over several directories then excludes it. Left out of that list, it is
reported, but only as a warning ("found N file(s) which are unhandled"), and CI does not fail on warnings. This
check fails either way, and in the first case it is the only signal. It reads the index: a file with no unit, older
than the newest unit the store holds, was there when the last build compiled the others, and that build did not
compile it. Name it in Package.swift (its module's own target, or its coarse group's `directories:`). A file with no unit that is NEWER than the last build is only new, and is reported as stale
(rebuild, then check); so is one whose build failed before reaching it.

### `upward`: a reference its module cannot see

`TUIkitFoundation -> TUIkitLists: TUIkitFoundation/Views/Foo.swift::Foo uses TUIkitLists/Views/List.swift::ListThing (3 references)`

Once split, this is a compile error, or a cycle. Fix it in one of these ways:
- Move the user up: `git mv` its file into the higher module's directory, or move the one declaration into a file
  there.
- Move the used declaration down, the same way, into a lower module's directory.
- Break the edge with a protocol, an injected value or an opaque slot, as plan §4's K1–K5 do.

Then run `assign` to see what else moves, and `assign --write` to record it.

The K refactors that have not landed yet are `scheduled` entries, with the step they land in. When one lands, its
entry matches nothing any more, and the `rules` check asks you to delete it.

### `owns-neither`: a conformance in a module that owns neither the type nor the protocol

That is the debug-runtime crash class: Package.swift's note on `Color: View`, and M3's "failed to demangle witness
… TabsPage: View". Move the conformance next to the type or the protocol. Conformances whose type and protocol
both live outside the map's directories are skipped: TUIkit owns neither of those today either.

### `witness`: a conformance that cannot see the constrained default it relies on

`T: View is declared in TUIkitFoundation (…), which cannot see T: Renderable in TUIkitLists (…)`

`extension View where Self: Renderable` supplies a View requirement. That witness is picked where `T: View` is
checked. If `T: Renderable` sits in a module that site cannot see, the unconstrained default wins, and nothing
says so: it compiles and draws blank. That was M3's blank render.

The pairs come from `witness_pairs` in `rules.json`, plus every `extension P where Self: Q` found in `Sources/`.
Fix it by declaring both conformances in one module (the assigner ties a type's conformance extensions to it), or
the second one lower.

### `public-above`: public API placed above the type it belongs to

There are two forms:
- `public API of ListStyle (TUIkitFoundation) is declared in TUIkitLists: …`. An app that imports only the type's module
  does not get this API.
  - Not reported when the extension's header (conformance list or `where` clause) names a declaration of its own
    module. Such API only works with that module's types: `extension PickerStyle where Self == MenuPickerStyle`,
    or `extension ForEach: TableRowContent`.
- `public API on View carried from TUIkitFoundation up to TUIkitPresentation by the assigner: …`. A modifier block on a
  type from below the map, which the assigner lifted away from its file's module for its dependencies.
  - `public API on View placed in TUIkitBitmaps by a declarations rule, above its file's TUIkitFoundation: …`. The same
    move made by a `declarations` rule: a placement someone chose, so it is reported **accepted**, with the rule's
    reason, never new. It is reported at all so that `-v` lists the block's public members: a rule is written for the
    members its author had in mind, and the block may hold others.

The key is the block's label, which names only its first member, so each finding ends by listing every public
member the block declares: `(public: statusBarItems(_:), focusSection(_:))`, as the `.statusBarItems` block read
before A4's S2 split it. A member counts when it is `public` or
`open`, or has no access modifier of its own in a `public extension`; a nested type's members are named `Type.member`.
That is what a review reads. Placing a block moves all of its public members, and the refined plan found four that
had moved module unseen behind another block's first member (`.focusSection`, `.aspectRatio`, `.scaledToFit`,
`.scaledToFill`); the last three sit in a block a rule places, which is why rule-placed blocks are reported too. `-v`
prints the accepted ones.

A placement you have reviewed goes into `accepted`, with the reason. The plan's own reviews are recorded there: the
ones found at 0c, and `.modal`, `.listStyle` and `.statusBarItems` until A4 gave each a file of its module (no longer
a finding; their reasons went to those files' `files` rules, which A5 replaced by the directories, so they are in
`rules.json` as it was before A5). An accepted entry covers the block as it changes: when a public
member joins an accepted block, re-read the finding with `-v`.

A member that does not belong with the rest of its block, and that a refactor will split out, is a `scheduled` entry:
`from` matches the block's label, `to` the member's name as the list prints it. The finding is scheduled while a
flagged block holds the member, and the entry goes stale once none does. It follows the member, not the block: a block
split out but still placed above its file's module (by the assigner, or by a broad declarations rule, as TUIkitBitmaps'
`Views/Image.swift::…View\(ext\)` was until A4) keeps it open. Members no entry names keep an unaccepted block's finding new, so a
split scheduled for one member cannot hide the rest. The refined plan's S1 (the layout trio and the cell-aspect option,
out of the image-option blocks) and S2 (`.focusSection`, out of the `.statusBarItems` block) were recorded this way
until step A4 landed them.

### `posix`: a POSIX-only API outside TUIkitApp

`TUIkitFoundation: TUIkitFoundation/Rendering/Foo.swift::Bar uses isatty, which only POSIX platforms have`

CLAUDE.md keeps termios, ioctl, signals and stdin dispatch sources out of the modules that must build on Windows.
The plan puts the console layer in TUIkitApp, so a use elsewhere is reported. Since the owner relaxed the Windows rule
(CLAUDE.md, 2026-10-07: POSIX-only code may live in any module, isolated, never in a module that builds on Windows
today), `rules.json`'s `posix.informational` marks such a finding accepted — information, not a new finding — unless
a `scheduled` refactor covers it. A use counts as isolated when it sits in an `#if` branch that neither Windows nor
WASI compiles. The check evaluates each enclosing branch's condition on those two platforms (`os(…)`, `canImport(…)` of
a libc or an Apple-only framework, `arch(wasm32)`, `!`, `&&`, `||`); a branch is ruled out where its condition is
surely false or an earlier branch of its chain surely true. So `#if canImport(Darwin)` and its `#elseif
canImport(Glibc)` guard, and so does the `#else` of `#if canImport(WASILibc) || os(Windows)`. The `#else` of `#if
canImport(WASILibc)` does not, because Windows compiles it, and nor does a branch that depends on anything else
(`arch(x86_64)`, `compiler(…)`, a build flag). The
`posix` section of `rules.json` lists the APIs: C functions, types (`pid_t`), structs and macros, plus the two
Dispatch sources. The
check also reports an unguarded `import Darwin` (or Glibc, Musl …) in a file with code outside TUIkitApp.

### `umbrella`: code in the umbrella, or a module it does not re-export

`TUIkit does not re-export TUIkitNavigation`

The `TUIkit` umbrella re-exports and holds nothing else. No declaration may be assigned to it, and its files may
hold only imports. And it re-exports, by name, every module carved out above `TUIkitFoundation` (the `default` in
`rules.json`): a module whose files `@_exported import` TUIkitFoundation, or a module that does (TUIkitApp,
TUIkitColorPicker, TUIkitNavigation since step B5, TUIkitLists since step B6, TUIkitChrome, TUIkitEffects and
TUIkitMenus since step B5b, TUIkitBitmaps since step B5c, TUIkitTextInput since step B7, TUIkitPresentation since
step C1, TUIkitTables since step C2, TUIkitTabs since step C3, TUIkitGrid since step C4, TUIkitForms since step
C6, TUIkitSearch since step C5). TUIkitFoundation cannot re-export a module built on it, so `import TUIkit` has it
only through the umbrella.
Reaching it through a sibling instead compiles the same: TUIkitApp and TUIkitPresentation re-export TUIkitChrome,
which they depend on, for good (TUIkitNavigation did from step B5b until step C1, only because its target compiled
the TUIkitPresentation directory, whose entry depends on TUIkitChrome). TUIkitColorPicker re-exports
TUIkitPresentation since step C1 (TUIkitNavigation from B5 until then; it used nothing of the navigation
containers'), so an umbrella without TUIkitPresentation's line still gives an app `TUIkit.Alert`, and only the
umbrella re-exports TUIkitNavigation now. It re-exports TUIkitTabs since step C3, which depends on TUIkitLists and
re-exports it (plan §4), as TUIkitColorPicker did directly from step B6 until then. So an umbrella without TUIkitTabs'
line still gives an app `TUIkit.TabView`, and without TUIkitLists' line `TUIkit.List`; TUIkitTables re-exports
TUIkitLists too since step C2, and TUIkitSearch re-exports TUIkitTextInput since step C5. Nothing but the umbrella
re-exports TUIkitTables, TUIkitGrid, TUIkitForms or TUIkitSearch. No build notices a missing line; this check does.
A coarse group's other members (TUIkitPickers and the rest, until their peels) have no Exports.swift, so they
re-export nothing and are not asked for,
as a module TUIkitFoundation compiled was not until step B7; nor is a module below
TUIkitFoundation (TUIkitStrings), which TUIkitFoundation re-exports. Fix it by adding `@_exported import` of the
module to `Sources/TUIkit/Exports.swift`.

### `lower`: a lower module the module's `lower` list does not name

`TUIkitStrings: TUIkitStrings/Localization/Foo.swift::Foo uses TUIkitView.AppState.shared, and TUIkitStrings's lower list does not name TUIkitView`

The lower modules are the package's other modules in `Sources`, beside the map's directories, that its sources
import, and what those
re-export with `@_exported import` (TUIkitCore, TUIkitStyling, TUIkitView, TUIkitImage today). The map does not split
them. A module's `lower` list in `rules.json` names the ones it may use; a
module without a list may use them all. Once split, the module would not depend on the one it uses, so this is a
compile error. The lists also keep a module off the critical path it was placed to avoid: a side module compiles
beside TUIkitView only for as long as nothing in it uses TUIkitView, and a module that must build without
TUIkitImage stays without it.

There is one finding per declaration and symbol, with its references counted. Fix it as for `upward`: move the user,
or break the edge (inject the value, or split the code that needs the lower module into an extension in a module
that may use it). A refactor that will remove one is a `scheduled` entry whose `to` matches the symbol as the finding
names it: its module, then the types it is nested in or extends, then its name (`^TUIkitView\.AppState\.shared$`; an
accessor is `AppState.getter:shared`). A bare name would make every `shared` or `init(_:)` of the module one finding,
and one pattern would cover them all.

The check reads which lower module defines each symbol from the same index store, in one more pass over its units:
about 0.3 s on a `swift build --build-tests` store (measured on HEAD c181ec0f9; reading every other module in
`Sources`, Example and Stress included, cost 0.6–0.9 s). Two things are errors, not a silent pass: a `lower`
list naming a module that is not one of these, and an index with no definitions of one of these (even one no list
names: a list denies what it leaves out, and a module the index lacks would deny nothing).

### `imports`: a file of a carved module that uses another module without importing it

`TUIkitLists/Views/Foo.swift uses TUIkitFoundation (RowBackground, ANSIRenderer; 3 references) without importing it, …`

Unlike the checks above, this one is about the build as it is, not the map. A module carved out above
TUIkitFoundation (TUIkitApp, TUIkitColorPicker, TUIkitNavigation, TUIkitLists …) re-exports it from its
`Exports.swift`, so every one of its files can name TUIkitFoundation's declarations without importing it, and
compiles. But Swift decides whether a closure passed to a function needs a run-time check that it runs on the main
actor by the calling **file's** imports (`CSApply.cpp`, `closuresRequireDynamicIsolationChecking`, through
`ValueDecl::findImport`, Swift 6.2.4): a callee from a module the file imports, directly or through the re-exports of
a module it imports, is trusted; one from a module it reaches only through another file's `@_exported import` is
not, and every closure passed to it gets a `swift_task_isCurrentExecutor` call: steps B4 to B6 added 190 of them
to a release Stress (1,482 call sites at B3, 1,672 at B6). So a file of such a module must import, itself, every module whose
declarations it uses: TUIkitFoundation (whose re-exports bring the lower modules and the side modules), and any other
carved module (a ColorPicker file that lays out a `TabView` imports TUIkitTabs).

The modules are the targets as the build compiled them: the index unit of each file names its target, so a file of
`Sources/TUIkitPickers` is TUIkitTextInput's until step C8, and needs no import to use a declaration of
`Sources/TUIkitTextInput` (as a file of `Sources/TUIkitTables` or `TUIkitTabs` was TUIkitLists' until step C2 or C3; since then each imports
TUIkitLists where it uses it). A reference to a lower
module (TUIkitCore, TUIkitView …) counts too; any import that re-exports it answers it. Today that is
`import TUIkitFoundation`, whose `Exports.swift` re-exports every lower and side module: no lower module re-exports
another in this tree, though the check would follow one that did (`reexports_of`). One finding per file and
module, with the declarations it names and the references counted. TUIkitFoundation's own files and the side
modules below it are not checked: no carve changed what they import. Fix it by adding the `import` to the file.

### `rules`: a `scheduled` or `accepted` entry that matches nothing

The refactor landed, or the code moved. Delete the entry, so the rules stay a list of open items. If the finding
is still there under another key (its declaration was renamed, or an extension now opens with another member),
give the entry the key the report now prints instead.

## Coarse groups

Phase B carves some planned modules as a **coarse group**: one target that compiles several modules' directories
(declared with `directories:` in Package.swift: `path: "Sources"`, each of its directories in `sources:`, every other
directory under Sources in `exclude:`), and phase C peels each member into a target of its own. Step B5's
`TUIkitNavigation` compiled `Sources/TUIkitNavigation` and `Sources/TUIkitPresentation` until step C1 peeled the
second into `TUIkitPresentation`, which left `TUIkitNavigation` an ordinary target at its default path; step B6's
`TUIkitLists` compiled `Sources/TUIkitLists`, `TUIkitTables`, `TUIkitTabs` and `TUIkitGrid` until steps C2 to C4
peeled the last three into `TUIkitTables` and `TUIkitTabs`, each built on `TUIkitLists`, and `TUIkitGrid`, which left
`TUIkitLists` an ordinary target at its default path; step
B7's `TUIkitTextInput` compiled `Sources/TUIkitForms` until step C6 peeled it into `TUIkitForms`, built on
`TUIkitFoundation` alone, and `Sources/TUIkitSearch` until step C5 peeled it into `TUIkitSearch`, built on
`TUIkitTextInput`, and compiles `Sources/TUIkitTextInput`, `TUIkitPickers` and `TUIkitNumericControls` until steps C7
and C8. Nothing here changes for a group, at its carve or at its peels:

- `map.json` and the findings name the planned module. A file under `Sources/TUIkitPresentation` is
  `TUIkitPresentation`'s, as its directory says, and the peel moves it to its own target with no edit here: at step
  C1, `map.json` gained the new module's Exports.swift (`assign --write`) and nothing else, and no declaration
  changed module.
- The index records the group's target as the module of each of its files' units. The tool reads the units of every
  module `rules.json` names, so it reads them whichever of those targets compiled them. A member's directory that the
  group's `directories:` leaves out is compiled by no target, so each of its files is an `uncompiled` finding.
- The checks hold the members to the planned map, as they held the modules TUIkitFoundation compiled together until
  step B7. That is stricter than the build, never looser. The group's target sees everything its members' planned
  dependencies give them (TUIkitFoundation, and TUIkitChrome for TUIkitPresentation from step B5b until C1), so what
  passes the checks compiles. An edge between two members compiles in the group but is still a finding, because the
  peel would have to break it; so a peel starts with no finding to fix. Step C1 did: `check` reported 0 findings
  before and after it, and the build needed no declaration widened. Treating a group as one module would let such edges
  in until the peel (decisions B-SPB5-1).

## The assigner

Since step A5 `rules.json` has no `files` list: each declaration is seeded in its file's directory, and every file is
pinned, so the assigner moves nothing and `map.json` mirrors the directories. What follows is the research mode, with
a `files` list, which computed the map and which the unit tests still exercise.

1. **Seed.** Each declaration starts in the module its file's first matching `files` rule names, else in the
   default (TUIkitFoundation). An extension in a default-module file goes where the type it extends is seeded.
   - Fixed: pinned file rules, and `declarations` rules (minus `unpin`).
2. **Atomic groups**, which move as one:
   - an overload set (the same member name on one type, in files seeded to one module);
   - a protocol, with the extensions that implement its requirements (its default witnesses);
   - a type, with the extensions that add conformances its seed module can see.
3. **Fixpoint.** These steps repeat until nothing moves:
   1. Up to dependencies: a group that cannot see what it uses goes up to the lowest module that sees it all, if
      its users still see that module.
   2. Down: a group used from below goes down to where its users and it meet.
   3. Up: a group that is not public API, and that only one module above uses, goes up to that module.
4. **Post-passes.**
   - A group lifted only transiently returns to its seed.
   - A conformance in a module that owns neither its type nor its protocol moves to the type's module (else the
     protocol's), if that breaks nothing.

References that a `scheduled` rule matches are left out of the fixpoint, so a refactor that has not landed does
not drag declarations down.

## Editing the rules

- **`modules`**: names, dependencies, optionally a `lower` list (the lower modules it may use; without one, all of
  them), and a one-line description of what belongs there. Dependencies form a DAG; the loader rejects a cycle, and
  a `lower` list naming a module of the map.
- **The directories**: a file's path, relative to `Sources` (`source`), starts with its module's directory, and
  that is its module. Only the directories of the modules listed here are read.
- **`files`** (removed at step A5, when the directories took over; the research mode still reads it): `{module, pin,
  match, why}`. The first rule whose `match` regex hits the path seeds the file. A pinned file stays put. An unpinned
  one is a starting point that the fixpoint may move. The reasons the r4 rules gave are in `git log` before A5.
- **`declarations`**: `{module, match, why}` over labels: a pattern is tried on the printed label
  (`path::Name(ext)#first`, as `explain` shows it) and on the base label (`path::Name(ext)`), so a copied label pins that
  one declaration and a pattern ending at `(ext)` pins every extension of the type in the file. These pin single
  declarations. Use them for a placement decision (plan §4's X1, X2 and FormControlRow, `renderOnce` to TUIkitApp), or
  to undo an assigner drift. Where several match one declaration, the **last** wins, so a narrower rule placed after a
  broader one is an exception to it (TUIkitFoundation's three image layout keys after TUIkitBitmaps' `Image.*Key`).
- **`unpin`**: declarations in pinned files that may move anyway, such as value types inside POSIX files. The list is
  empty since step A4. A declaration that moved out of its pinned file would split that file again, and A4 left
  every file whole: `RenderLoop.swift`'s value types went to `RenderFrameValues.swift`, and the last entry,
  `RenderActivity`, was removed because only TUIkitApp uses it, so it never moved.
- **`scheduled`**: `{id, check, from, to, why}`. A known finding (`upward`, `posix`, `lower` or `public-above`) that a
  refactor will remove. `from` and `to` match labels (the printed label or the base label without its
  `#discriminator`); for `posix`, `to` matches the API's name, for `lower`, `Module.Type.name`, and for `public-above`,
  the name of the public member the refactor moves out of the block.
- **`accepted`**: `{check, key, why}`. A reviewed finding that stays. The key is what the report prints.

**Renaming a module.** Module names live in `rules.json`, the generated `map.json` and the directory names: rename
it everywhere in `rules.json`, `git mv` its directory (and fix Package.swift: `sourcesDirectories`, and the module's
own target, or its coarse group's `directories:`), then
`assign --write`. Names are free to change until per-module products
ship.

After editing, run `assign`. It prints the module table and how many declarations would change module. Read the
`explain` output for anything surprising, then `assign --write`, and commit `rules.json` and `map.json` together.

**When code changes.** New files and new declarations are placed by the rules (a new file by its directory) until
the next `assign --write`; `check` says how many there are. An edited declaration in a split file keeps its entry: when its label changes (a
member added above its first one, or that member renamed) and exactly one entry of the same name (`View(ext)`)
no longer matches anything, that entry is taken to be its. With two such edits to one name in one file, both are
placed by the rules. Refresh the map whenever a change adds files or moves code between them.

**Every file is in one module.** Since step A4 no file holds declarations of two modules, so step A5 moved whole
files into per-module directories, and a file's directory now places it. When `assign` shows a split entry again, a
`declarations` rule has put a declaration of one module into a file of another's directory: move it to a file of its
own module, or start one, rather than keep the split (a carve could not compile it).

## Limits

- The index records only the code macOS compiles. A reference inside a `#if os(Linux)` or `#if os(Windows)` arm is
  invisible to every check that reads references: `upward`, `lower` (a Linux-only use of a lower module a list leaves
  out), `posix`, `owns-neither`, `witness` and `imports` (a Linux-only closure into a module the file does not
  import). The plan checked HEAD's 464 macOS-inactive lines by hand (§4, guard 7).
  The refined plan's correction 2 was this class (a Linux-only call the index never saw), so every carve also runs its
  inactive-arm scan and the Linux cross-compile before landing.
- Only the map's directories (`Sources/<module>` for each module in `rules.json`) are mapped. Tests, Example and
  Stress import the umbrella and are not checked.
- Line weights, which decide an unpinned group's module by majority, are each declaration's share of its file,
  up to the next declaration.

## In CI

CI runs the check on the `macOS 15 · Xcode 26` lane, right after its debug build, so it reads that build's index
store. It needs no extra build; the step itself takes a few seconds.

The lane's Xcode floats from Swift 6.2 to 6.3, and the index differs a little between them. On HEAD a 6.3.3
index has 18 more edges than a 6.2.4 one, all of them references to a result builder (`SceneBuilder`,
`ToolbarContentBuilder` …; why 6.3 records them was not investigated), and 38 more conformance records. The
check's findings and the assignment are the same from both (measured 2026-10-07).

**It gates.** Plan steps A2 (the K refactors) and A4 (the file splits and placement moves) have landed, so the map
has no new finding (what it still reports is `scheduled` or `accepted`), and the step runs `check --github`: a new
finding fails it, so that no new upward reference can arrive during the migration. Each new finding is an error
annotation (GitHub keeps 10 per step; past that, the tenth says how many more the step's log lists). A failure of the
tool itself (no index store, a libIndexStore that will not load, a bug) fails the step too, with one error annotation
saying that nothing was checked. `--exit-zero` is still there for a local run that should only report: with it, new
findings and a failure of the tool are warning annotations and the exit status is 0. The parity job runs the tool's
own unit tests.
