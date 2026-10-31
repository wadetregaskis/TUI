#!/usr/bin/env python3
"""Check that every tracked path can be checked out on Windows.

A colon, say, is fine in a Git tree and on macOS and Linux, and `git checkout` on
Windows then refuses the whole repository with "invalid path", so every Windows
lane ends at its first step. Two names that differ only in case are one file there
(and on a default macOS volume).

Usage: validate-filenames.py [--self-test]
Exit status: 0 if every path is fine, 1 otherwise.
"""

import re
import subprocess
import sys

INVALID_CHARACTERS = re.compile(r'[<>:"|?*\\\x00-\x1f]')
RESERVED_NAME = re.compile(r"^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(\..*)?$", re.IGNORECASE)


def problems(paths: list[str]) -> list[str]:
    out = []
    seen = {}
    for path in paths:
        for part in path.split("/"):
            if INVALID_CHARACTERS.search(part):
                out.append(f"{path}: {part!r} has a character Windows does not allow")
            if part.endswith((" ", ".")):
                out.append(f"{path}: {part!r} ends in a space or a dot")
            if RESERVED_NAME.match(part):
                out.append(f"{path}: {part!r} is a name Windows reserves")
        other = seen.setdefault(path.casefold(), path)
        if other != path:
            out.append(f"{path}: differs from {other} only in case")
    return out


def self_test() -> None:
    assert not problems(["Sources/A b/C.swift", "con.txt.md".replace("con", "icon")])
    for bad in ["a/b: c.md", "a/b?.md", "dir./x", "a/name ", "NUL", "x/com1.txt", "x\\y"]:
        assert problems([bad]), bad
    assert problems(["A/b.md", "a/b.md"])


def main() -> int:
    if "--self-test" in sys.argv:
        self_test()
        print("validate-filenames: self-test passed")
        return 0
    listed = subprocess.run(["git", "ls-files", "-z"], capture_output=True, text=True, check=True).stdout
    found = problems([path for path in listed.split("\0") if path])
    for problem in found:
        print(problem)
    if found:
        print(f"{len(found)} path(s) cannot be checked out on Windows")
        return 1
    print("validate-filenames: every tracked path can be checked out on Windows")
    return 0


if __name__ == "__main__":
    sys.exit(main())
