#!/usr/bin/env python3
"""
Unit tests for quick.py's verdicts: what it calls a pass, on output written here.

    python3 -m unittest discover -s Tools/Dev -p 'test_*.py'

No build, no toolchain. Every case is a way quick.py once printed a pass, or
nothing at all, for a run that did not happen (H-56).
"""

import contextlib
import importlib.util
import io
import os
import subprocess
import tempfile
import unittest
from unittest import mock

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


def commit(repo, message):
    subprocess.run(["git", "-C", repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q",
                    "--allow-empty", "-m", message], check=True)
    return subprocess.run(["git", "-C", repo, "rev-parse", "HEAD"], capture_output=True,
                          text=True).stdout.strip()


class TestSaysWhatItSkipped(unittest.TestCase):
    """Nothing is skipped or misread silently (H-56, TOOLS-14)."""

    def quietly(self, call):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), mock.patch.object(quick, "where", lambda: ""):
            result = call()
        return result, out.getvalue().splitlines()

    def test_a_warning_fails_the_build_and_the_tests_say_they_did_not_run(self):
        built = (0, "/x/Sources/A.swift:1:1: warning: unused\nBuild complete!\n")
        with mock.patch.object(quick, "run", side_effect=[built]) as run:
            ok, lines = self.quietly(lambda: quick.test(["SuiteA"]))
        self.assertFalse(ok)
        self.assertEqual(run.call_count, 1)
        self.assertEqual(lines[-2:], ["build FAILED (1 warning)", "tests not run: the build failed"])

    def test_a_clean_build_is_ok(self):
        with mock.patch.object(quick, "run", return_value=(0, "Build complete!\n")):
            ok, lines = self.quietly(quick.build)
        self.assertEqual((ok, lines), (True, ["build ok"]))

    def test_all_reads_a_commit_as_base_with_or_without_the_separator(self):
        is_commit = {"origin/main", "HEAD~2"}.__contains__
        self.assertEqual(quick.parse_all(["origin/main"], is_commit), ("origin/main", []))
        self.assertEqual(quick.parse_all(["HEAD~2", "SuiteA"], is_commit), ("HEAD~2", ["SuiteA"]))
        self.assertEqual(quick.parse_all(["origin/main", "--", "SuiteA"], is_commit), ("origin/main", ["SuiteA"]))
        self.assertEqual(quick.parse_all(["--", "SuiteA"], is_commit), (None, ["SuiteA"]))
        self.assertEqual(quick.parse_all(["SuiteA", "SuiteB"], is_commit), (None, ["SuiteA", "SuiteB"]))
        self.assertIsInstance(quick.parse_all(["a", "b", "--", "SuiteA"], is_commit), str)

    def test_lint_on_main_compares_with_what_is_pushed(self):
        repo, _ = make_checkouts(self)
        subprocess.run(["git", "-C", repo, "checkout", "-q", "-b", "main"], check=True)
        pushed = commit(repo, "pushed")
        self.assertEqual(quick.default_base(repo), ("HEAD", "HEAD"))  # no origin/main: nothing more to say
        subprocess.run(["git", "-C", repo, "update-ref", "refs/remotes/origin/main", pushed], check=True)
        commit(repo, "unpushed")
        self.assertEqual(quick.default_base(repo), (pushed, "origin/main (%s)" % pushed[:9]))
        self.assertTrue(quick.names_commit("origin/main", repo))
        self.assertFalse(quick.names_commit("SuiteA", repo))

    def test_lint_on_a_branch_compares_with_where_it_left_main(self):
        repo, _ = make_checkouts(self)
        subprocess.run(["git", "-C", repo, "checkout", "-q", "-b", "main"], check=True)
        fork = commit(repo, "main")
        subprocess.run(["git", "-C", repo, "checkout", "-q", "-b", "lane"], check=True)
        self.assertEqual(quick.default_base(repo), ("HEAD", "HEAD"))  # nothing committed on the lane yet
        commit(repo, "lane")
        self.assertEqual(quick.default_base(repo), (fork, "main (%s)" % fork[:9]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
