#!/usr/bin/env python3
"""
Unit tests for quick.py's verdicts: what it calls a pass, on output written here.

    python3 -m unittest discover -s Tools/Dev -p 'test_*.py'

No build, no toolchain. Every case is a way quick.py once printed a pass, or
nothing at all, for a run that did not happen (H-56).
"""

import importlib.util
import os
import subprocess
import tempfile
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location("quick", os.path.join(_HERE, "quick.py"))
quick = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(quick)


def run_output(summary, groups=(), problems=()):
    """parallel_test.py's output, from its own line shapes."""
    lines = ["parallel-test: 3 tests in 2 suites, 2 processes", ""]
    lines += ["  group %s: %5d tests    0.50s wall     1.0s cpu  %s" % g for g in groups]
    lines += ["", summary]
    lines += ["  RECONCILIATION: %s" % p for p in problems]
    return "\n".join(lines) + "\n"


class TestVerdict(unittest.TestCase):
    def test_a_passing_run_passes_with_its_count(self):
        out = run_output("parallel-test: 14 tests in 3 suites passed in 1.20s across 2 processes "
                         "(1.50s end to end, 2.0 cpu-s, 1.7x cores) with 0 known issues",
                         [("g0", 7, "ok"), ("g1", 7, "ok")])
        self.assertEqual(quick.test_verdict(0, out), (True, ["tests ok (14)"]))

    def test_one_test_is_counted_too(self):
        # parallel_test says "1 test in 1 suite"; this once read as no summary at all.
        out = run_output("parallel-test: 1 test in 1 suite passed in 0.20s across 1 process "
                         "(0.50s end to end, 0.2 cpu-s, 1.0x cores) with 0 known issues", [("g0", 1, "ok")])
        self.assertEqual(quick.test_verdict(0, out), (True, ["tests ok (1)"]))

    def test_a_group_that_ran_fewer_tests_than_planned_fails(self):
        # Every group printed ok, and the only problems were RECONCILIATION lines: the waiver passed this.
        out = run_output("parallel-test: 10 tests in 2 suites FAILED in 1.20s across 1 process "
                         "(1.50s end to end, 2.0 cpu-s, 1.7x cores) with 0 known issues",
                         [("g0", 10, "ok")],
                         ["group g0 ran 10 tests, the partition predicted 14",
                          "union 10 of 14 expected — 4 missing, 0 extra, 0 duplicated"])
        ok, lines = quick.test_verdict(1, out)
        self.assertFalse(ok)
        self.assertEqual(lines[-1], "tests FAILED (10)")

    def test_a_group_that_ran_more_tests_than_planned_fails(self):
        out = run_output("parallel-test: 3 tests in 1 suite FAILED in 0.20s across 1 process "
                         "(0.50s end to end, 0.2 cpu-s, 1.0x cores) with 0 known issues",
                         [("g0-TUIViewTests", 3, "ok")],
                         ["group g0-TUIViewTests ran 3 tests, the partition predicted 1"])
        self.assertFalse(quick.test_verdict(1, out)[0])

    def test_no_test_run_is_never_a_pass(self):
        out = run_output("parallel-test: 0 tests in 0 suites passed in 0.00s across 1 process "
                         "(0.10s end to end, 0.0 cpu-s, 0.0x cores) with 0 known issues")
        ok, lines = quick.test_verdict(0, out)
        self.assertFalse(ok)
        self.assertEqual(lines[-1], "tests FAILED (0): no test ran")
        self.assertNotIn("tests ok (0)", lines)

    def test_a_filter_matching_nothing_fails(self):
        out = "parallel-test: --filter 'NoSuchSuite' matched no tests\n"
        ok, lines = quick.test_verdict(1, out)
        self.assertFalse(ok)
        self.assertEqual(lines[-1], "tests FAILED (?)")
        self.assertIn("matched no tests", "\n".join(lines))


def make_checkouts(test):
    """Two fresh git checkouts, each with a subdirectory, removed after the test."""
    folder = tempfile.TemporaryDirectory()
    test.addCleanup(folder.cleanup)
    trees = []
    for name in ("main", "worktree"):
        path = os.path.realpath(os.path.join(folder.name, name))
        os.makedirs(os.path.join(path, "Tools", "Dev"))
        subprocess.run(["git", "init", "-q", path], check=True)
        trees.append(path)
    return trees


class TestCheckout(unittest.TestCase):
    """The script tests the checkout it lives in, so it must be run from there (H-56, TOOLS-6)."""

    def test_another_checkout_is_refused_naming_both(self):
        main, worktree = make_checkouts(self)
        why = quick.wrong_checkout(worktree, main)
        self.assertIsNotNone(why)
        self.assertIn(main, why)
        self.assertIn(os.path.normcase(worktree), why)

    def test_its_own_checkout_is_fine_from_any_directory_in_it(self):
        main, _ = make_checkouts(self)
        self.assertIsNone(quick.wrong_checkout(main, main))
        self.assertIsNone(quick.wrong_checkout(os.path.join(main, "Tools", "Dev"), main))

    def test_outside_any_checkout_it_must_be_run_from_inside_its_tree(self):
        with tempfile.TemporaryDirectory() as folder:
            tree = os.path.realpath(os.path.join(folder, "export"))
            os.makedirs(os.path.join(tree, "Tools"))
            elsewhere = os.path.realpath(os.path.join(folder, "elsewhere"))
            os.makedirs(elsewhere)
            self.assertIsNone(quick.wrong_checkout(os.path.join(tree, "Tools"), tree))
            self.assertIn(tree, quick.wrong_checkout(elsewhere, tree) or "")

    def test_the_verdict_names_the_tree_and_its_head(self):
        main, _ = make_checkouts(self)
        self.assertEqual(quick.describe_tree(main), main)  # no commit yet: git cannot say
        subprocess.run(["git", "-C", main, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q",
                        "--allow-empty", "-m", "x"], check=True)
        head = subprocess.run(["git", "-C", main, "rev-parse", "--short", "HEAD"], capture_output=True,
                              text=True).stdout.strip()
        self.assertEqual(quick.describe_tree(main), "%s @ %s" % (main, head))
        out = run_output("parallel-test: 2 tests in 1 suite passed in 0.20s across 1 process "
                         "(0.50s end to end, 0.2 cpu-s, 1.0x cores) with 0 known issues", [("g0", 2, "ok")])
        self.assertEqual(quick.test_verdict(0, out, " in " + quick.describe_tree(main))[1][-1],
                         "tests ok (2) in %s @ %s" % (main, head))


if __name__ == "__main__":
    unittest.main(verbosity=2)
