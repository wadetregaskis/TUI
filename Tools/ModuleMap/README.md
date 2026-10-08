# Tools/ModuleMap

TUIkit is to be split into à-la-carte modules: the substrate (TUIkitFoundation), side modules that compile beside the
lower ones, feature leaves over the substrate, TUIkitApp and a thin `TUIkit` umbrella. `rules.json` lists them and
what each holds. Today all of that code is one module, `Sources/TUIkit`. This tool holds:

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
| `rules.json` | The modules and what each depends on. The contents rules: which files and declarations go where. The scheduled refactors, the accepted findings, the POSIX API list, and the witness pairs. | You, by hand |
| `map.json` | The assignment: a module for each file. A split file names a module for each of its declarations. | `assign --write` only |
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

### `upward`: a reference its module cannot see

`TUIkitFoundation -> TUIkitLists: Views/Foo.swift::Foo uses Views/List.swift::ListThing (3 references)`

Once split, this is a compile error, or a cycle. Fix it in one of these ways:
- Move the user up. If it is a whole file, add or adjust a `files` rule; for one declaration, a `declarations`
  rule.
- Move the used declaration down, with a rule for its file or for the declaration. Or drop the pin that keeps it
  up, and the assigner pulls it down by itself.
- Break the edge with a protocol, an injected value or an opaque slot, as plan §4's K1–K5 do.

Then run `assign` to see what else moves, and `assign --write` to record it.

The K refactors that have not landed yet are `scheduled` entries, with the step they land in. When one lands, its
entry matches nothing any more, and the `rules` check asks you to delete it.

### `owns-neither`: a conformance in a module that owns neither the type nor the protocol

That is the debug-runtime crash class: Package.swift's note on `Color: View`, and M3's "failed to demangle witness
… TabsPage: View". Move the conformance next to the type or the protocol. Conformances whose type and protocol
both live outside `Sources/TUIkit` are skipped: TUIkit owns neither of those today either.

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
a finding, so their reasons moved to those files' rules). An accepted entry covers the block as it changes: when a public
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

`TUIkitFoundation: Rendering/Foo.swift::Bar uses isatty, which only POSIX platforms have`

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

### `umbrella`: code in the umbrella

The `TUIkit` umbrella re-exports and holds nothing else. No declaration may be assigned to it, and its files may
hold only imports.

### `lower`: a lower module the module's `lower` list does not name

`TUIkitStrings: Localization/Foo.swift::Foo uses TUIkitView.AppState.shared, and TUIkitStrings's lower list does not name TUIkitView`

The lower modules are the package's other modules beside `Sources/TUIkit` that its sources import, and what those
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
about 0.3 s on a `swift build --build-tests` store (measured on HEAD c181ec0f9; reading every module beside
`Sources/TUIkit`, Example and Stress included, cost 0.6–0.9 s). Two things are errors, not a silent pass: a `lower`
list naming a module that is not one of these, and an index with no definitions of one of these (even one no list
names: a list denies what it leaves out, and a module the index lacks would deny nothing).

### `rules`: a `scheduled` or `accepted` entry that matches nothing

The refactor landed, or the code moved. Delete the entry, so the rules stay a list of open items. If the finding
is still there under another key (its declaration was renamed, or an extension now opens with another member),
give the entry the key the report now prints instead.

## The assigner

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
- **`files`**: `{module, pin, match, why}`. The first rule whose `match` regex hits the path (relative to
  `Sources/TUIkit`) seeds the file. A pinned file stays put. An unpinned one is a starting point that the
  fixpoint may move.
- **`declarations`**: `{module, match, why}` over labels: a pattern is tried on the printed label
  (`path::Name(ext)#first`, as `explain` shows it) and on the base label (`path::Name(ext)`), so a copied label pins that
  one declaration and a pattern ending at `(ext)` pins every extension of the type in the file. These pin single
  declarations. Use them for a placement decision (plan §4's X1, X2 and FormControlRow, `renderOnce` to TUIkitApp), or
  to undo an assigner drift. Where several match one declaration, the **last** wins, so a narrower rule placed after a
  broader one is an exception to it (TUIkitFoundation's three image layout keys after TUIkitBitmaps' `Image.*Key`).
- **`unpin`**: declarations in pinned files that may move anyway. These are value types inside POSIX files.
- **`scheduled`**: `{id, check, from, to, why}`. A known finding (`upward`, `posix`, `lower` or `public-above`) that a
  refactor will remove. `from` and `to` match labels (the printed label or the base label without its
  `#discriminator`); for `posix`, `to` matches the API's name, for `lower`, `Module.Type.name`, and for `public-above`,
  the name of the public member the refactor moves out of the block.
- **`accepted`**: `{check, key, why}`. A reviewed finding that stays. The key is what the report prints.

**Renaming a module.** Module names live in `rules.json` (and the generated `map.json`) and nowhere else in the tool:
rename it everywhere in `rules.json`, then `assign --write`. Names are free to change until per-module products ship.

After editing, run `assign`. It prints the module table and how many declarations would change module. Read the
`explain` output for anything surprising, then `assign --write`, and commit `rules.json` and `map.json` together.

**When code changes.** New files and new declarations are placed by the rules until the next `assign --write`;
`check` says how many there are. An edited declaration in a split file keeps its entry: when its label changes (a
member added above its first one, or that member renamed) and exactly one entry of the same name (`View(ext)`)
no longer matches anything, that entry is taken to be its. With two such edits to one name in one file, both are
placed by the rules. Refresh the map whenever a change adds files or moves code between them.

**Every file is in one module.** Since step A4 no file holds declarations of two modules: `map.json` names one module
per file, and a file rule places each (the declaration pins on the files A4 cut became file rules), so step A5 can
move whole files into per-module directories. When `assign` shows a split entry again, a change has put a declaration
of one module into a file of another: move it to a file of its own module, or start one, rather than keep the split.

## Limits

- The index records only the code macOS compiles. A reference inside a `#if os(Linux)` or `#if os(Windows)` arm is
  invisible to every check that reads references: `upward`, `lower` (a Linux-only use of a lower module a list leaves
  out), `posix`, `owns-neither` and `witness`. The plan checked HEAD's 464 macOS-inactive lines by hand (§4, guard 7).
  The refined plan's correction 2 was this class (a Linux-only call the index never saw), so every carve also runs its
  inactive-arm scan and the Linux cross-compile before landing.
- Only `Sources/TUIkit` is mapped. Tests, Example and Stress import the umbrella and are not checked.
- Line weights, which decide an unpinned group's module by majority, are each declaration's share of its file,
  up to the next declaration.

## In CI

CI runs the check on the `macOS 15 · Xcode 26` lane, right after its debug build, so it reads that build's index
store. It needs no extra build; the step itself takes a few seconds.

The lane's Xcode floats from Swift 6.2 to 6.3, and the index differs a little between them. On HEAD a 6.3.3
index has 18 more edges than a 6.2.4 one, all of them references to a result builder (`SceneBuilder`,
`ToolbarContentBuilder` …; why 6.3 records them was not investigated), and 38 more conformance records. The
check's findings and the assignment are the same from both (measured 2026-10-07).

For now it only warns: it runs with `--github --exit-zero`, and every new finding becomes a warning annotation
(GitHub keeps 10 per step; past that, the tenth says how many more the step's log lists). With `--exit-zero`, a
failure of the tool itself (no index store, a libIndexStore that will not load, a bug) is one warning annotation
too, and the step has `continue-on-error` for anything that escapes Python. Once plan steps A2 (the K refactors)
and A4 (the placement moves) have landed, drop both, so that no new upward reference can arrive during the
migration. The parity job runs the tool's own unit tests.
