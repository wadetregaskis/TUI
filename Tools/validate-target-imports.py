#!/usr/bin/env python3
"""validate-target-imports.py: every import of one of this package's own modules is a declared dependency.

A target that imports a module of the package it does not depend on, directly or through its dependencies, builds
under macOS's native build system with Swift 6.2, which puts every module in one directory, and fails elsewhere. On
2026-11-10 `TUIImage` imported `TUICore` without depending on it: the 6.2 gates passed, then Swift 6.4's link of
`TUIImageTests` lacked TUICore's symbols and the WebAssembly build could not find TUICore's own dependency
(`CWASIStack`). This finds that in seconds, from the manifest, before any build.

What it checks: for every target, each `import M` in its Swift sources (any attributes or access level, `@testable`,
`import struct M.T`) where M is a target of this package must be M itself or in the target's dependency closure
(`dependencies:` by name or `.target`, transitively; a platform condition counts as a dependency, so an import that
needs the condition is still accepted). Modules from other packages and the SDK are not this check's business.
`validate-test-boundaries.sh` is the stricter rule for the per-module test targets, and runs beside this.

Usage: Tools/validate-target-imports.py [DUMP.json]  (reads `swift package dump-package` when no file is given)
Exit status: 0 when every import is declared, 1 when one is not, 2 when the manifest cannot be read.
"""

import json
import os
import re
import subprocess
import sys

IMPORT = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|package|internal|fileprivate|private)\s+)?"
    r"import\s+(?:(?:struct|class|enum|protocol|typealias|func|var|let)\s+)?([A-Za-z_][A-Za-z0-9_]*)"
)


def manifest(argv):
    if len(argv) > 1:
        with open(argv[1]) as handle:
            return json.load(handle)
    swift = os.environ.get("SWIFT", "swift").split()
    result = subprocess.run(swift + ["package", "dump-package"], capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        sys.exit(2)
    return json.loads(result.stdout)


def names(dependencies):
    """The package-local names a target's `dependencies:` lists (by name or `.target`; not `.product`)."""
    for dependency in dependencies:
        for kind in ("byName", "target"):
            if kind in dependency:
                yield dependency[kind][0]


def main(argv):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    package = manifest(argv)
    targets = {target["name"]: target for target in package["targets"]}
    direct = {name: set(names(target.get("dependencies", []))) & targets.keys() for name, target in targets.items()}

    def closure(name, seen=None):
        seen = set() if seen is None else seen
        for dependency in direct.get(name, ()):
            if dependency not in seen:
                seen.add(dependency)
                closure(dependency, seen)
        return seen

    violations = 0
    for name, target in sorted(targets.items()):
        if target["type"] in ("system", "binary", "plugin"):
            continue
        folder = target.get("path") or os.path.join("Tests" if target["type"] == "test" else "Sources", name)
        directory = os.path.join(root, folder)
        if not os.path.isdir(directory):
            continue
        allowed = closure(name) | {name}
        for base, _, files in os.walk(directory):
            for file in sorted(files):
                if not file.endswith(".swift"):
                    continue
                path = os.path.join(base, file)
                with open(path, encoding="utf-8") as handle:
                    for number, line in enumerate(handle, 1):
                        match = IMPORT.match(line)
                        if not match:
                            continue
                        module = match.group(1)
                        if module in targets and module not in allowed:
                            print(f"✘ {os.path.relpath(path, root)}:{number} imports {module}, which {name} does "
                                  f"not depend on. Add it to {name}'s dependencies in Package.swift, or drop the import.")
                            violations += 1
    if violations:
        print(f"\n✘ {violations} import(s) of an undeclared module of this package.")
        return 1
    print(f"✓ Every import of this package's modules is declared ({len(targets)} targets).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
