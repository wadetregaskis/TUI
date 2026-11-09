#!/usr/bin/env python3
"""Record TUI's public API, one declaration per line, and check it against the record.

    Tools/Release/api_baseline.py                # build, extract, rewrite api-baseline/
    Tools/Release/api_baseline.py --check        # report additions and removals; exit 1 if any
    Tools/Release/api_baseline.py --skip-build   # either mode, against the modules already built

This is the API-stability baseline for 1.0: `api-baseline/<Module>.txt` holds
every `public` and `open` declaration in that module, sorted, one per line:

    View.padding(_:_:) | func padding(_ edges: Edge.Set = .all, _ length: Int? = nil) -> some View

that is, the declaration's path (its owner and name), then its declaration as
the compiler prints it, then — where they apply — the constraints of the
extension it sits in (`where Self : Equatable`) and `[deprecated: …]`.

An unconditionally unavailable declaration — the `@available(*, unavailable,
message:)` stubs that turn SwiftUI's deprecated spellings into a compile error
with a migration message — is not listed: `swift symbolgraph-extract` leaves
them out and has no flag to keep them. That is the right answer for this
record anyway. No program that builds can call one, so removing one breaks
nothing that compiled.

What the record is NOT, so a diff is read correctly:

  * It is source API, not ABI. Bodies (`@inlinable`, `@_alwaysEmitIntoClient`)
    and layout are not in it.
  * It is macOS's view, with the package's default traits. API behind
    `#if os(Linux)` or `#if canImport(AppKit)` is listed or not as macOS
    compiles it; `TUIAppKit` and `TUIFilePanelsAppKit` only exist there.
  * A symbol graph is only reproducible against the toolchain that made it,
    so each file is stamped with the compiler and target. `--check` against a
    different toolchain says so before it lists differences: some of them may
    be the compiler's, not the package's.
  * Underscored names are listed like everything else. Whether they are
    covered by a stability promise is a policy question, not this tool's.
    (Extracted at `-minimum-access-level public`, symbolgraph-extract drops
    them without a word, so the graphs are extracted at `internal` and
    filtered to `public` and `open` here.)

The modules are every library target under `Sources/` (from `swift package
dump-package`): the products, and the targets that are not products but whose
public API reaches clients through `@_exported` re-exports. A C target has no
symbol graph and is skipped.

`--check` is not wired into CI; that is the owner's call. The extraction is
`Tools/APIParity/api_parity.py`'s (same flags, same search paths), so the two
tools always agree on what TUI's public API is.

Requires macOS with Xcode.
"""
import argparse
import json
import os
import re
import shutil
import sys
import tempfile
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
BASELINE_DIR = os.path.join(HERE, "api-baseline")
sys.path.insert(0, os.path.join(REPO, "Tools", "APIParity"))

import api_parity  # noqa: E402  (the path has to be set up first)

DEFAULT_TARGET = "arm64-apple-macosx26.0"
CONSTRAINT_OPERATORS = {"conformance": ":", "superclass": ":", "sameType": "=="}


def constraints_text(constraints):
    return ", ".join(
        f"{c['lhs']} {CONSTRAINT_OPERATORS.get(c['kind'], c['kind'])} {c['rhs']}"
        for c in constraints)


def line_for(symbol):
    """One line for one declaration: path | declaration [where …] [flags]."""
    path = ".".join(symbol.get("pathComponents") or [symbol["names"]["title"]])
    declaration = "".join(
        fragment.get("spelling", "") for fragment in symbol.get("declarationFragments", []))
    declaration = re.sub(r"\s+", " ", declaration).strip()
    line = f"{path} | {declaration}"
    extension = (symbol.get("swiftExtension") or {}).get("constraints") or []
    if extension:
        line += f" [extension where {constraints_text(extension)}]"
    deprecated = api_parity.deprecation(symbol)
    if deprecated:
        line += f" [deprecated: {deprecated}]"
    return line


def module_lines(directory, module):
    """Every public declaration the module declares, including its extensions
    of other modules' types (`TUICore@Swift.symbols.json`), sorted."""
    lines = []
    for entry in sorted(os.listdir(directory)):
        if not entry.endswith(".symbols.json"):
            continue
        if entry.split(".symbols.json")[0].split("@")[0] != module:
            continue
        with open(os.path.join(directory, entry)) as handle:
            graph = json.load(handle)
        for symbol in graph.get("symbols", []):
            # One protocol-extension member replicated onto each conforming
            # type: one declaration, recorded once under the protocol.
            if "::SYNTHESIZED::" in symbol.get("identifier", {}).get("precise", ""):
                continue
            if symbol.get("accessLevel") not in ("public", "open"):
                continue
            lines.append(line_for(symbol))
    return sorted(lines)


def header(module, is_product, toolchain, target):
    role = "library product" if is_product else "not a product: public API reaches clients by re-export"
    return [
        f"# {module} public API ({role}).",
        f"# {toolchain}; {target}. Written by Tools/Release/api_baseline.py: do not edit by hand.",
    ]


def read_baseline(path):
    """(stamp lines, declaration lines) of one committed file."""
    with open(path) as handle:
        lines = handle.read().splitlines()
    return ([line for line in lines if line.startswith("#")],
            [line for line in lines if line and not line.startswith("#")])


def check(current, toolchain, target):
    """Print additions and removals per module; True if anything differs."""
    recorded = {name[:-len(".txt")] for name in os.listdir(BASELINE_DIR) if name.endswith(".txt")} \
        if os.path.isdir(BASELINE_DIR) else set()
    differs = False
    stamp_mismatch = False
    for module in sorted(set(current) | recorded):
        path = os.path.join(BASELINE_DIR, module + ".txt")
        stamps, old = read_baseline(path) if module in recorded else ([], [])
        new = current.get(module, [])
        if module in recorded and not any(f"{toolchain}; {target}." in stamp for stamp in stamps):
            stamp_mismatch = True
        added = Counter(new) - Counter(old)
        removed = Counter(old) - Counter(new)
        if module not in current:
            print(f"{module}: module removed ({len(old)} declarations)")
        elif module not in recorded:
            print(f"{module}: module added ({len(new)} declarations)")
        for line in sorted(removed.elements()):
            print(f"- {module}: {line}")
        for line in sorted(added.elements()):
            print(f"+ {module}: {line}")
        differs = differs or bool(added or removed) or (module in current) != (module in recorded)
    if stamp_mismatch:
        print(f"Note: the baseline was recorded with a different toolchain or target than {toolchain}; "
              f"{target}. That alone can move lines; compare with a matching one before reading a "
              "difference as the package's.")
    return differs


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true",
                        help="compare with the committed baseline; exit 1 on any addition or removal")
    parser.add_argument("--skip-build", action="store_true",
                        help="use the modules already built instead of running `swift build`")
    parser.add_argument("--work-dir", help="keep the symbol graphs here")
    parser.add_argument("--target", default=DEFAULT_TARGET)
    args = parser.parse_args()

    sdk = api_parity.sdk_path()
    toolchain = api_parity.toolchain_version()
    modules = api_parity.library_modules()
    search_paths = api_parity.tui_search_paths(build=not args.skip_build)
    work = args.work_dir or tempfile.mkdtemp(prefix="api-baseline-")
    try:
        # `internal`, then filtered to public and open in `module_lines`:
        # extracted at `public`, the graph silently drops every name with a
        # leading underscore, and the members of underscored types with them.
        api_parity.extract(sorted(modules), work, search_paths, sdk, args.target, access_level="internal")
        current = {module: module_lines(work, module) for module in modules}
    finally:
        if not args.work_dir:
            shutil.rmtree(work, ignore_errors=True)

    if args.check:
        if check(current, toolchain, args.target):
            print("\nThe public API differs from Tools/Release/api-baseline/. If the change is "
                  "intended, rerun without --check and commit the result with it.")
            return 1
        print(f"public API matches the baseline ({sum(map(len, current.values()))} declarations)")
        return 0

    os.makedirs(BASELINE_DIR, exist_ok=True)
    for name in os.listdir(BASELINE_DIR):
        if name.endswith(".txt") and name[:-len(".txt")] not in current:
            os.remove(os.path.join(BASELINE_DIR, name))
    for module, lines in sorted(current.items()):
        with open(os.path.join(BASELINE_DIR, module + ".txt"), "w") as handle:
            handle.write("\n".join(header(module, modules[module], toolchain, args.target) + lines) + "\n")
    print(f"wrote {sum(map(len, current.values()))} declarations in {len(current)} modules "
          f"to {os.path.relpath(BASELINE_DIR, REPO)}/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
