#!/usr/bin/env python3
"""check-compiler-warnings.py — fail on any warning a build log holds from TUI's own code.

TUI keeps a zero-warning build, every target included (CONTRIBUTING.md, "What CI
covers"): a warning left standing trains everyone to read past the next one, and
this codebase's have been real findings — a flag returned and read by nobody, a test
whose `#require` meant it had never asserted anything. CI builds from a clean checkout
with no cache, so every file is compiled and a warning cannot hide behind an
incremental build, which is the trap when counting by hand.

Reads one or more build logs (`swift build … 2>&1 | tee LOG`) and reports each
distinct warning once: compiler diagnostics with a location, and the build system's
own (`warning: 'TUI': found 1 file(s) which are unhandled`, a linker's `ld:
warning:`). A diagnostic in a dependency's checkout (`…/checkouts/…`) is not
TUI's to fix and is counted apart, printed, and not failed on.

A warning inside a macro's expansion — an unsafe expression inside `#expect`,
say — names the expansion rather than a file (`macro expansion #expect:1:157:
warning: …`), and the line after it says where the expansion came from (`…/X.swift:58:17:
note: expanded code originates here`). It is counted, and reported, at that
place: told apart by its file and line, which two in different files saying
the same thing would otherwise not be. The source excerpt the compiler draws
under a diagnostic (`   |  `- warning: …`) repeats it, and is not a second one.

The tests: `python3 -m unittest discover -s Tools -p test_check_compiler_warnings.py`.

Usage:
    Tools/check-compiler-warnings.py [--github] LOG [LOG …]

--github writes each finding as an error annotation as well.

Exit status: 0 if no log holds a warning from TUI's code, 1 if one does, 2 if a
log cannot be read.
"""

import os
import re
import sys

# `path:line:col: warning: message`, the compiler's (and clang's) spelling.
LOCATED = re.compile(r"^(?P<path>/[^:]+):(?P<line>\d+):(?P<col>\d+): warning: (?P<message>.*)$")
# Any other line that is a warning: SwiftPM's, the linker's, a driver's.
UNLOCATED = re.compile(r"(^|\s)warning: ")
# Swift Build and SwiftPM print a dependency's diagnostics with its checkout's path.
DEPENDENCY = "/checkouts/"
# `macro expansion #expect:1:157: warning: message`: a warning in a macro's
# expansion, whose own place is in the expanded code, not in a file.
IN_EXPANSION = re.compile(r"^macro expansion (?P<macro>#?[\w.]+):\d+:\d+: warning: (?P<message>.*)$")
# The line after it: where in a file the expansion came from.
EXPANDED_FROM = re.compile(r"(?P<path>/[^:]+):(?P<line>\d+):(?P<col>\d+): note: expanded code originates here")
# How many lines after the warning the note may come.
EXPANDED_FROM_WITHIN = 3
# A line of the source excerpt the compiler draws under a diagnostic, which
# repeats the diagnostic: `   |  `- warning: …`, ` 51 |  …`.
EXCERPT = re.compile(r"^\s*(\d+\s*)?\|")
# Colour. Swift Build (6.4's default build system) colours its diagnostics even
# into a pipe or a file, and `warning:` behind `ESC[1;33m` matches neither
# pattern above, so a coloured log read raw would pass whatever it held. And the
# hyperlink 6.4 wraps a diagnostic's group name in (`ESC]8;;URL ESC\`).
COLOUR = re.compile(r"\x1b\[[0-9;]*m|\x1b\]8;;[^\x1b]*\x1b\\")


def parse(lines):
    """The warnings in a build log's `lines`: `(own, dependencies)`.

    `own` maps each distinct warning from TUI's code, as reported, to its place
    (a dict with `path`, `line`, `col` and `message`) or `None` when it has
    none; `dependencies` is the set of a dependency's.
    """
    own, dependencies = {}, set()
    lines = [COLOUR.sub("", line).rstrip() for line in lines]
    for index, line in enumerate(lines):
        if "warning: " not in line or EXCERPT.match(line):
            continue
        located = LOCATED.match(line)
        expansion = None if located else IN_EXPANSION.match(line)
        if expansion:
            following = lines[index + 1:index + 1 + EXPANDED_FROM_WITHIN]
            origin = next(filter(None, (EXPANDED_FROM.search(after) for after in following)), None)
            if origin:
                located = {
                    "path": origin["path"], "line": origin["line"], "col": origin["col"],
                    "message": f"{expansion['message']} (in the expansion of {expansion['macro']})",
                }
                line = f"{origin['path']}:{origin['line']}:{origin['col']}: warning: {located['message']}"
        if located:
            if DEPENDENCY in located["path"]:
                dependencies.add(line)
            else:
                own.setdefault(line, located)
        elif UNLOCATED.search(line):
            own.setdefault(line, None)
    return own, dependencies


def main(argv):
    github = "--github" in argv
    paths = [arg for arg in argv if arg != "--github"]
    if not paths:
        print(__doc__.strip().splitlines()[0], file=sys.stderr)
        print("usage: check-compiler-warnings.py [--github] LOG [LOG …]", file=sys.stderr)
        return 2
    own, dependencies = {}, set()
    for path in paths:
        try:
            with open(path, encoding="utf-8", errors="replace") as log:
                lines = log.read().splitlines()
        except OSError as error:
            print(f"error: cannot read {path}: {error}", file=sys.stderr)
            return 2
        found, theirs = parse(lines)
        for line, located in found.items():
            own.setdefault(line, located)
        dependencies |= theirs
    for line in sorted(dependencies):
        print(f"(a dependency's, not counted) {line}")
    if not own:
        print(f"No compiler warnings from TUI's code in {len(paths)} build log(s).")
        return 0
    print(f"error: {len(own)} warning(s) from TUI's code — the build must have none:")
    for line, located in own.items():
        print(f"  {line}")
        if github:
            if located:
                # Relative to the checkout, which is where an annotation's file is looked up.
                where = os.path.relpath(located["path"]) if located["path"].startswith(os.getcwd()) else located["path"]
                print(f"::error file={where},line={located['line']},col={located['col']}"
                      f"::{located['message']}")
            else:
                print(f"::error::{line.strip()}")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
