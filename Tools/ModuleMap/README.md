# Tools/ModuleMap

TUIkit is to be split into à-la-carte modules: TUIkitStrings, TUIkitBase, TUIkitApp, twelve feature modules and a
thin `TUIkit` umbrella. Today all of that code is one module, `Sources/TUIkit`. This tool holds:

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
override. It reads the newest `.build/*/debug/index/store`, which SwiftPM writes on every macOS debug build; pass
`--store` to use another. If a source file is newer than its index unit, it warns: rebuild, then check again.

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

The design behind the map is in the session notes' `buildtime/split2/plan.md`. This tool is that plan's step A1. The
assigner is the research assigner (`split2/plan/w/sassign.py` + `finalize.py`) ported. On HEAD 4611730eb it gives
every one of the 4,127 declarations the same module as the re-indexed research run (`split2/reindex/`).

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
- **Labels.** A declaration is named `path::Name`. An extension gets `(ext)` after its name, and `#2`, `#3` … tell
  apart declarations that share a label in one file.

## The checks

Every finding has a key. A finding listed under `scheduled` or `accepted` in `rules.json` is reported but does
not count as new. Only new findings fail `check`, or raise an annotation in CI.

### `upward`: a reference its module cannot see

`TUIkitBase -> TUIkitLists: Views/Foo.swift::Foo uses Views/List.swift::ListThing (3 references)`

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

`T: View is declared in TUIkitBase (…), which cannot see T: Renderable in TUIkitControls (…)`

`extension View where Self: Renderable` supplies a View requirement. That witness is picked where `T: View` is
checked. If `T: Renderable` sits in a module that site cannot see, the unconstrained default wins, and nothing
says so: it compiles and draws blank. That was M3's blank render.

The pairs come from `witness_pairs` in `rules.json`, plus every `extension P where Self: Q` found in `Sources/`.
Fix it by declaring both conformances in one module (the assigner ties a type's conformance extensions to it), or
the second one lower.

### `public-above`: public API placed above the type it belongs to

There are two forms:
- `public API of ListStyle (TUIkitBase) is declared in TUIkitLists: …`. An app that imports only the type's module
  does not get this API.
  - Not reported when the extension's header (conformance list or `where` clause) names a declaration of its own
    module. Such API only works with that module's types: `extension PickerStyle where Self == MenuPickerStyle`,
    or `extension ForEach: TableRowContent`.
- `public API on View carried from TUIkitBase up to TUIkitPresentation by the assigner: …`. A modifier block on a
  type from below the map, which the assigner lifted away from its file's module for its dependencies.

A placement you have reviewed goes into `accepted`, with the reason. The plan's own reviews are recorded there:
`.modal`, `.listStyle`, and the ones found at 0c.

### `posix`: a POSIX-only API outside TUIkitApp

`TUIkitBase: Rendering/Foo.swift::Bar uses isatty, which only POSIX platforms have`

CLAUDE.md keeps termios, ioctl, signals and stdin dispatch sources out of the modules that must build on Windows.
TUIkitApp is the one POSIX module. A use elsewhere must sit in an `#if canImport(Darwin)` / `Glibc` / `Musl` /
`os(macOS)` … arm. An `#else` arm is what the other platforms compile, so it never counts as guarded. The
`posix` section of `rules.json` lists the APIs: C functions, structs and macros, plus the two Dispatch sources. The
check also reports an unguarded `import Darwin` (or Glibc, Musl …) in a file with code outside TUIkitApp.

### `umbrella`: code in the umbrella

The `TUIkit` umbrella re-exports and holds nothing else. No declaration may be assigned to it, and its files may
hold only imports.

### `rules`: a `scheduled` or `accepted` entry that matches nothing

The refactor landed, or the code moved. Delete the entry, so the rules stay a list of open items.

## The assigner

1. **Seed.** Each declaration starts in the module its file's first matching `files` rule names, else in the
   default (TUIkitBase). An extension in a default-module file goes where the type it extends is seeded.
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

- **`modules`**: names, dependencies, and a one-line description of what belongs there. Dependencies form a DAG;
  the loader rejects a cycle.
- **`files`**: `{module, pin, match, why}`. The first rule whose `match` regex hits the path (relative to
  `Sources/TUIkit`) seeds the file. A pinned file stays put. An unpinned one is a starting point that the
  fixpoint may move.
- **`declarations`**: `{module, match, why}` over labels. These pin single declarations. Use them for a placement
  decision (plan §4's X1, X2 and FormControlRow, `renderOnce` to TUIkitApp), or to undo an assigner drift.
- **`unpin`**: declarations in pinned files that may move anyway. These are value types inside POSIX files.
- **`scheduled`**: `{id, check, from, to, why}`. A known finding (`upward` or `posix`) that a refactor will
  remove. `from` and `to` match labels; for `posix`, `to` matches the API's name.
- **`accepted`**: `{check, key, why}`. A reviewed finding that stays. The key is what the report prints.

After editing, run `assign`. It prints the module table and how many declarations would change module. Read the
`explain` output for anything surprising, then `assign --write`, and commit `rules.json` and `map.json` together.

**When code changes.** New files and new declarations are placed by the rules until the next `assign --write`;
`check` says how many there are. A renamed declaration in a split file loses its entry the same way. Refresh the
map whenever a change adds files or moves code between them.

## Limits

- The index records only the code macOS compiles. A reference inside a `#if os(Linux)` or `#if os(Windows)` arm is
  invisible to `upward`. The plan checked HEAD's 464 macOS-inactive lines by hand (§4, guard 7).
- Only `Sources/TUIkit` is mapped. Tests, Example and Stress import the umbrella and are not checked.
- Line weights, which decide an unpinned group's module by majority, are each declaration's share of its file,
  up to the next declaration.
