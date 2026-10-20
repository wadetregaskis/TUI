#!/usr/bin/env python3
"""check-compiler-warnings.py — fail on any warning a build log holds from TUIkit's own code.

TUIkit keeps a zero-warning build, every target included (CONTRIBUTING.md, "What CI
covers"): a warning left standing trains everyone to read past the next one, and
this codebase's have been real findings — a flag returned and read by nobody, a test
whose `#require` meant it had never asserted anything. CI builds from a clean checkout
with no cache, so every file is compiled and a warning cannot hide behind an
incremental build, which is the trap when counting by hand.

Reads one or more build logs (`swift build … 2>&1 | tee LOG`) and reports each
distinct warning once: compiler diagnostics with a location, and the build system's
own (`warning: 'TUIkit': found 1 file(s) which are unhandled`, a linker's `ld:
warning:`). A diagnostic in a dependency's checkout (`…/checkouts/…`) is not
TUIkit's to fix and is counted apart, printed, and not failed on.

Usage:
    Tools/check-compiler-warnings.py [--github] LOG [LOG …]

--github writes each finding as an error annotation as well.

Exit status: 0 if no log holds a warning from TUIkit's code, 1 if one does, 2 if a
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
# Colour. Swift Build (6.4's default build system) colours its diagnostics even
# into a pipe or a file, and `warning:` behind `ESC[1;33m` matches neither
# pattern above, so a coloured log read raw would pass whatever it held.
COLOUR = re.compile(r"\x1b\[[0-9;]*m")


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
        for line in lines:
            line = COLOUR.sub("", line).rstrip()
            located = LOCATED.match(line)
            if located:
                if DEPENDENCY in located["path"]:
                    dependencies.add(line)
                else:
                    own.setdefault(line, located)
            elif UNLOCATED.search(line):
                own.setdefault(line, None)
    for line in sorted(dependencies):
        print(f"(a dependency's, not counted) {line}")
    if not own:
        print(f"No compiler warnings from TUIkit's code in {len(paths)} build log(s).")
        return 0
    print(f"error: {len(own)} warning(s) from TUIkit's code — the build must have none:")
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
