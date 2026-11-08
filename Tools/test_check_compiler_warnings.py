#!/usr/bin/env python3
"""
Tests for check-compiler-warnings.py's reading of a build log: no build, no toolchain.

    python3 -m unittest discover -s Tools -p test_check_compiler_warnings.py

The log lines are Swift 6.4's, as Swift Build writes them into a file: coloured, the
diagnostic group a hyperlink, a source excerpt under each diagnostic.
"""

import importlib.util
import os
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location("check_compiler_warnings", os.path.join(_HERE, "check-compiler-warnings.py"))
checker = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(checker)

ROOT = "/work/TUI"
UNSAFE = "expression uses unsafe constructs but is not marked with 'unsafe'"
# The diagnostic group, as 6.4 writes it: a hyperlink around its name.
GROUP = " [#\x1b]8;;https://docs.swift.org/compiler/documentation/diagnostics/strict-memory-safety\x1b\\StrictMemorySafety\x1b]8;;\x1b\\]"


def in_expansion(path, line, col, macro_col):
    """A warning in an `#expect`'s expansion, as 6.4 logs it, from `path:line:col`."""
    return [
        f"\x1b[1;39mmacro expansion #expect:1:{macro_col}: \x1b[1;33mwarning: \x1b[1;39m{UNSAFE}{GROUP}\x1b[0;0m",
        f"`- {ROOT}/{path}:{line}:{col}: note: expanded code originates here",
        f" {line} |         #expect(",
        "    |         |- note: in expansion of macro 'expect' here",
        f"    |         `- \x1b[1;33mwarning: \x1b[1;39m{UNSAFE}{GROUP}\x1b[0;0m",
    ]


class ParseTests(unittest.TestCase):
    def test_a_warning_in_a_macro_expansion_is_found_at_the_line_it_expands_from(self):
        own, dependencies = checker.parse(in_expansion("Tests/ATests/A.swift", 58, 17, 157))
        self.assertEqual(dependencies, set())
        self.assertEqual(len(own), 1, own)
        [(line, place)] = own.items()
        self.assertEqual(
            line, f"{ROOT}/Tests/ATests/A.swift:58:17: warning: {UNSAFE} [#StrictMemorySafety] (in the expansion of #expect)")
        self.assertEqual((place["path"], place["line"], place["col"]), (f"{ROOT}/Tests/ATests/A.swift", "58", "17"))

    def test_the_same_warning_in_two_files_is_two_warnings(self):
        # Both say `macro expansion #expect:1:157`: by that alone they are one.
        log = in_expansion("Tests/ATests/A.swift", 58, 17, 157) + in_expansion("Tests/BTests/B.swift", 85, 17, 157)
        own, _ = checker.parse(log)
        self.assertEqual(len(own), 2, own)

    def test_one_warning_logged_twice_is_one(self):
        # A target built twice (its tests and a product) logs its warnings twice.
        log = in_expansion("Tests/ATests/A.swift", 58, 17, 157) * 2
        own, _ = checker.parse(log)
        self.assertEqual(len(own), 1, own)

    def test_the_excerpt_under_a_located_warning_is_not_another(self):
        log = [
            f"{ROOT}/Sources/A/A.swift:35:42: \x1b[1;33mwarning: \x1b[1;39m'f()' is deprecated\x1b[0;0m",
            " 35 |         try await f()",
            "    |                   `- \x1b[1;33mwarning: \x1b[1;39m'f()' is deprecated\x1b[0;0m",
        ]
        own, _ = checker.parse(log)
        self.assertEqual(list(own), [f"{ROOT}/Sources/A/A.swift:35:42: warning: 'f()' is deprecated"])

    def test_an_expansion_in_a_dependency_is_theirs(self):
        log = in_expansion(".build/checkouts/dep/Sources/D.swift", 3, 1, 9)
        own, dependencies = checker.parse(log)
        self.assertEqual(own, {})
        self.assertEqual(len(dependencies), 1)

    def test_an_expansion_without_its_origin_still_counts(self):
        # Cut short, the log holds no note: the warning is not lost.
        own, _ = checker.parse(in_expansion("Tests/ATests/A.swift", 58, 17, 157)[:1])
        self.assertEqual(len(own), 1, own)
        self.assertIsNone(next(iter(own.values())))

    def test_unlocated_warnings_still_count(self):
        own, _ = checker.parse([
            "warning: 'TUI': found 1 file(s) which are unhandled",
            "ld: warning: ignoring duplicate libraries: '-lc++'",
            "Compiling TUI A.swift",
        ])
        self.assertEqual(len(own), 2, own)


if __name__ == "__main__":
    unittest.main()
