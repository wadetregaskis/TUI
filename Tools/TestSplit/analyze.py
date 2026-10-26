#!/usr/bin/env python3
"""Which library modules each umbrella test file needs, read from the compiler's output.

For the per-module test-target split (owner request B-TC1-1). Two sources, unioned:

- The index store, the main one: every symbol a file references, by USR — a type named only in a
  signature and a call the optimiser inlines included. Each USR is looked up among the declarations
  the index records for the library modules' own files, which says the module that declares it (an
  extension's module for a member declared in an extension elsewhere), and among the test files'
  declarations, which says the helper it is. A USR declared nowhere in the index (a synthesised
  member, a conformance's witness) is read for the TUI module names it spells.
- Each test file's object: the outside symbols it refers to (`nm -u`), whose mangled names spell the
  modules involved. This catches what the index records no occurrence of, a conformance used
  only implicitly, say.

The answer over-approximates a little (a symbol's signature can name a module the file never
mentions, which its declaring module already depends on); the compile check that follows the move
is the final word.

Usage: analyze.py [--build DIR] [--out FILE.json]   (run from the package root after a debug build
with --build-tests)
"""
import argparse, collections, glob, json, os, re, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from indexstore import IndexStore, ROLE_DECLARATION, ROLE_DEFINITION  # noqa: E402

UMBRELLA_TARGETS = ["TUITests", "TUICollectionTests", "TUIControlTests", "TUIAppTests"]
SUPPORT = "TUITestSupport"
IDENT = re.compile(r"(\d+)([A-Za-z_][A-Za-z0-9_]*)")


def package_graph():
    dump = json.loads(subprocess.run(["swift", "package", "dump-package"], capture_output=True, text=True,
                                     check=True).stdout)
    graph = {}
    for target in dump["targets"]:
        deps = []
        for dep in target.get("dependencies", []):
            for kind in ("byName", "target", "product"):
                if kind in dep:
                    deps.append(dep[kind][0])
        graph[target["name"]] = deps
    return graph


def closure(graph, module, memo={}):
    if module not in memo:
        found = set()
        for dep in graph.get(module, []):
            found.add(dep)
            found |= closure(graph, dep)
        memo[module] = found
    return memo[module]


def modules_named(symbol, known):
    """The known module names spelled in a mangled Swift symbol (length-prefixed identifiers)."""
    found = set()
    for match in IDENT.finditer(symbol):
        length, text = int(match.group(1)), match.group(2)
        if length <= len(text) and text[:length] in known:
            found.add(text[:length])
    return found


def symbols(obj):
    out = subprocess.run(["nm", "-g", obj], capture_output=True, text=True).stdout
    defined, undefined = set(), set()
    for line in out.splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[0] == "U":
            undefined.add(parts[1])
        elif len(parts) == 3 and parts[1] in "TDSB":
            defined.add(parts[2])
    return defined, undefined


def from_index(store_path, root, library, test_targets):
    """{test file key: (modules, helpers)} from the index store at `store_path`, for the test targets' files."""
    store = IndexStore(store_path)
    declares = ROLE_DECLARATION | ROLE_DEFINITION
    # Each live source file's record, once: a file compiled into a unit for its own module, whose main file is
    # still where the unit says (a moved or deleted file's unit is stale).
    records = {}
    for unit_name in store.units():
        unit = store.unit(unit_name)
        if unit is None:
            continue
        module, main_file, mtime, deps = unit
        if not main_file:  # a module unit (an imported module's interface), not a compiled file
            continue
        relative = os.path.relpath(main_file, root)
        parts = relative.split(os.sep)
        if len(parts) < 3 or parts[0] not in ("Sources", "Tests") or parts[1] != module:
            continue
        if module not in library and module not in test_targets or not os.path.exists(main_file):
            continue
        for record, path in deps:
            if os.path.realpath(path) == os.path.realpath(main_file):
                previous = records.get(relative)
                if previous is None or previous[2] < mtime:
                    records[relative] = (module, record, mtime)
    declared_in_module, declared_in_test = {}, {}
    references = {}
    for relative, (module, record, _) in records.items():
        key = f"{module}/{os.path.splitext(os.path.basename(relative))[0]}"
        used = set()
        for usr, _, roles in store.occurrences(record):
            if roles & declares:
                if module in library:
                    declared_in_module.setdefault(usr, module)
                else:
                    declared_in_test.setdefault(usr, key)
            else:
                used.add(usr)
        if module in test_targets:
            references[key] = used
    result = {}
    for key, used in references.items():
        modules, helpers = set(), set()
        for usr in used:
            if usr in declared_in_module:
                modules.add(declared_in_module[usr])
            elif usr in declared_in_test:
                if declared_in_test[usr] != key:
                    helpers.add(declared_in_test[usr])
            elif usr.startswith("s:"):
                modules |= modules_named(usr, library)
        result[key] = (modules, helpers)
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", default=".build/arm64-apple-macosx/debug")
    ap.add_argument("--out", default="test-split-analysis.json")
    args = ap.parse_args()
    graph = package_graph()
    library = {t for t in graph if t.startswith("TUI") and not t.endswith("Tests")
               and t not in (SUPPORT, "TUIMacros", "TUIWidthCorpus")}
    files = {}
    definer = {}
    for target in UMBRELLA_TARGETS + [SUPPORT]:
        directory = os.path.join(args.build, f"{target}.build")
        for name in sorted(os.listdir(directory)):
            if not name.endswith(".swift.o"):
                continue
            # An object whose source has gone (moved to another target, or deleted) is stale.
            if not glob.glob(f"Tests/{target}/**/{name[:-len('.o')]}", recursive=True):
                continue
            defined, undefined = symbols(os.path.join(directory, name))
            key = f"{target}/{name[:-len('.swift.o')]}"
            files[key] = {"target": target, "undefined": undefined}
            for symbol in defined:
                definer.setdefault(symbol, key)
    indexed = from_index(os.path.join(args.build, "index/store"), os.getcwd(), library,
                         set(UMBRELLA_TARGETS + [SUPPORT]))
    missing = sorted(set(files) - set(indexed))
    if missing:
        print(f"{len(missing)} files have no index record (stale build?): {missing[:5]}", file=sys.stderr)
    result = {}
    for key, info in files.items():
        modules, helpers = (set(x) for x in indexed.get(key, (set(), set())))
        for symbol in info["undefined"]:
            modules |= modules_named(symbol, library)
            owner = definer.get(symbol)
            if owner and owner != key:
                helpers.add(owner)
        # The tops: modules no other needed module already depends on.
        tops = sorted(m for m in modules if not any(m in closure(graph, other) for other in modules if other != m))
        result[key] = {"target": info["target"], "modules": sorted(modules), "tops": tops,
                       "helpers": sorted(helpers)}
    json.dump({"graph": {k: v for k, v in graph.items() if k in library}, "files": result},
              open(args.out, "w"), indent=1, sort_keys=True)
    tally = collections.Counter(tuple(v["tops"]) for k, v in result.items() if v["target"] != SUPPORT)
    print(f"{len(result)} files; by the modules at the top of what each needs:")
    for tops, count in tally.most_common():
        print(f"{count:6}  {' + '.join(tops) or '(none)'}")


if __name__ == "__main__":
    sys.exit(main())
