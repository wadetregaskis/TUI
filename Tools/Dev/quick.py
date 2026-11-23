#!/usr/bin/env python3
"""quick.py: the build, test and lint loop, with only what needs reading printed.

    Tools/Dev/quick.py build                     # build with tests; errors and warnings only
    Tools/Dev/quick.py test SuiteA SuiteB ...    # build, then run those suites; failures only
    Tools/Dev/quick.py test --no-build SuiteA    # run only
    Tools/Dev/quick.py lint [BASE]               # SwiftLint --strict on Swift files changed since BASE
    Tools/Dev/quick.py all [BASE] [--] SuiteA ...  # build, test, lint

Each prints one verdict line last: "build ok", "tests ok (N)", "lint ok", or what failed, followed by
"in <checkout> @ <HEAD>": the tree that was built and tested.

A warning fails the build ("build FAILED (N warnings)"; zero is the rule), and tests after a failed build are not run,
which "tests not run" says. BASE defaults to where the branch left main; on main itself, to origin/main, so that the
unpushed commits are linted; a lint that had nothing to check says so. With `all`, a first argument that names a commit
is BASE, with or without `--`.

Why it exists (see README.md): the plain commands print thousands of lines that are then filtered by hand, and each
has a trap that cost a whole build-and-run to find:
- Bare `swift test` doesn't set up the environment CI uses, and colour tests fail spuriously (at 256 colours or none).
  This runs `Tools/ParallelTest/parallel_test.py`, which does.
- A run that ran no tests is not a pass: "tests ok (0)" is never printed. A filter matching nothing, or a run whose
  count does not reconcile, is "tests FAILED".
- It builds and tests the checkout it lives in, so it refuses to run from another one, naming both: main's copy
  run by absolute path from a worktree used to test main and pass.
- SwiftLint crashes ("Loading sourcekitdInProc.framework … failed") when DEVELOPER_DIR names the Command Line Tools.
  This points it at Xcode's when that is installed and nothing else was set.

Set TUI_RUN_WRAPPER to a command to prefix the heavy steps with, e.g. a machine-wide build-slot script.
"""

import os
import re
import shlex
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
XCODE = "/Applications/Xcode.app/Contents/Developer"


def env():
    environment = dict(os.environ)
    if "DEVELOPER_DIR" not in environment and os.path.isdir(XCODE):
        environment["DEVELOPER_DIR"] = XCODE
    if os.name != "nt":
        # Windows's toolchains find their SDK, and parallel_test.py its swift-testing, through SDKROOT.
        environment.pop("SDKROOT", None)
    environment.setdefault("TUI_CONFIG_DIR", os.path.join(REPO, ".tuikit-test-config"))
    os.makedirs(environment["TUI_CONFIG_DIR"], exist_ok=True)
    return environment


def wrapped(command):
    wrapper = os.environ.get("TUI_RUN_WRAPPER")
    return shlex.split(wrapper) + command if wrapper else command


def run(command):
    process = subprocess.run(wrapped(command), cwd=REPO, env=env(), capture_output=True, encoding="utf-8",
                             errors="replace")
    return process.returncode, process.stdout + process.stderr


def relative(line):
    return line.replace(REPO + os.sep, "").replace(REPO + "/", "")


def checkout_of(path):
    """The top of the git checkout `path` is in, spelt for comparison, or None outside one (or with no git)."""
    try:
        out = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=path, capture_output=True, text=True)
    except OSError:
        return None
    top = out.stdout.strip()
    return os.path.normcase(os.path.realpath(top)) if out.returncode == 0 and top else None


def wrong_checkout(cwd, repo):
    """None when `cwd` is in the checkout `repo` (this script's); otherwise why not, naming both.

    The script builds and tests the checkout it lives in, whatever the current directory, so main's copy run by
    absolute path from a worktree tested main and passed while the worktree's change sat untested (H-56). Outside
    any checkout (an export with no git) the current directory must be inside `repo`.
    """
    here, mine = checkout_of(cwd), checkout_of(repo) or os.path.normcase(os.path.realpath(repo))
    if here is None:
        inside = os.path.normcase(os.path.realpath(cwd))
        if inside == mine or inside.startswith(mine.rstrip(os.sep) + os.sep):
            return None
        here = inside
    if here == mine:
        return None
    return ("this script is in %s, but the current directory is in %s, and it tests the checkout it is in. "
            "Run %s's copy, or run this one from %s." % (repo, here, here, repo))


def describe_tree(repo):
    """'<repo> @ <short HEAD>', for a verdict line; just the path when git cannot say."""
    try:
        out = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=repo, capture_output=True, text=True)
    except OSError:
        return repo
    head = out.stdout.strip()
    return "%s @ %s" % (repo, head) if out.returncode == 0 and head else repo


_TREE = []


def where():
    """' in <checkout> @ <HEAD>', the suffix of every verdict line; asked of git once."""
    if not _TREE:
        _TREE.append(" in " + describe_tree(REPO))
    return _TREE[0]


def build():
    code, out = run(["swift", "build", "--build-tests", "-j", str(max(1, (os.cpu_count() or 4) // 3))])
    problems = sorted({relative(l.strip()) for l in out.splitlines()
                       if re.search(r"(error|warning): ", l) and "ld: warning" not in l})
    for line in problems[:40]:
        print(line[:240])
    if len(problems) > 40:
        print(f"… {len(problems) - 40} more")
    if code != 0 or any(" error: " in p or p.startswith("error:") for p in problems):
        print("build FAILED" + where())
        return False
    if problems:
        # Zero warnings is the rule, so this fails; it once printed "build ok (N warnings)" and exited 1.
        print(f"build FAILED ({len(problems)} warning{'' if len(problems) == 1 else 's'})" + where())
        return False
    print("build ok" + where())
    return True


def test(suites, build_first=True):
    if build_first and not build():
        print("tests not run: the build failed")
        return False
    if not suites:
        print("tests: no suites named")
        return False
    command = [sys.executable, "Tools/ParallelTest/parallel_test.py", "-j", "4", "--no-build",
               "--filter", "|".join(suites)]
    code, out = run(command)
    ok, lines = test_verdict(code, out, where())
    for line in lines:
        print(line)
    return ok


def test_verdict(code, out, tree=""):
    """parallel_test.py's exit code and output -> (passed, the lines to print, the verdict last).

    A pass is parallel_test's own: exit 0 and a summary that says "passed", which it gives only when every group
    ran exactly the tests the partition proved it selects. Nothing here overrides a FAILED. An earlier version
    passed a FAILED whose only problems were RECONCILIATION lines, to excuse a filter narrower than a suite
    running the whole suite; that also passed a group that ran FEWER tests than planned, or none (H-56). The
    partition selects exactly the filtered tests now, so there is nothing left to excuse. `tree` ends the verdict.
    """
    issues, lines = [], []
    for line in out.splitlines():
        if "recorded an issue" in line or re.search(r"\bFatal error\b|\bcrashed\b|signal \d+", line):
            issue = re.sub(r"^\s*\S*\s*Test ", "Test ", line.strip())
            issue = re.sub(r" with \d+ arguments?", "", issue)
            if issue not in issues:
                issues.append(issue)
    # "1 test in 1 suite" as well as "14 tests in 3 suites".
    summary_re = re.compile(r"^parallel-test: (\d+) tests? in \d+ suites? (passed|FAILED) in ")
    summary = next((m for m in map(summary_re.match, reversed(out.splitlines())) if m), None)
    for issue in issues[:30]:
        lines.append(issue[:240])
    if len(issues) > 30:
        lines.append(f"… {len(issues) - 30} more")
    n = int(summary.group(1)) if summary else None
    if code == 0 and summary and summary.group(2) == "passed" and n:
        lines.append(f"tests ok ({n})" + tree)
        return True, lines
    if not issues:
        tail = [l for l in out.splitlines() if l.strip()][-12:]
        lines.extend(relative(l)[:240] for l in tail)
    lines.append(f"tests FAILED ({'?' if n is None else n})" + (": no test ran" if n == 0 else "") + tree)
    return False, lines


def git(*args, repo=REPO):
    """git's output, stripped; "" when it fails."""
    process = subprocess.run(["git", *args], cwd=repo, capture_output=True, text=True)
    return process.stdout.strip() if process.returncode == 0 else ""


def default_base(repo=REPO):
    """-> (commit, what it is): what `lint` compares with when no BASE is named.

    Where the branch left main. On main itself that is HEAD, which left only the uncommitted files to lint, and on a
    main-only workflow nothing (H-56, TOOLS-14); there it is where main left origin/main, so the unpushed commits are
    linted. HEAD when neither says more.
    """
    head = git("rev-parse", "HEAD", repo=repo)
    fork = git("merge-base", "HEAD", "main", repo=repo)
    if fork and fork != head:
        return fork, "main (" + fork[:9] + ")"
    if git("symbolic-ref", "--short", "-q", "HEAD", repo=repo) == "main":
        pushed = git("merge-base", "HEAD", "origin/main", repo=repo)
        if pushed and pushed != head:
            return pushed, "origin/main (" + pushed[:9] + ")"
    return "HEAD", "HEAD"


def names_commit(argument, repo=REPO):
    return bool(git("rev-parse", "--verify", "-q", argument + "^{commit}", repo=repo))


def lint(base=None):
    described = base
    if base is None:
        base, described = default_base()
    changed = subprocess.run(["git", "diff", "--name-only", base], cwd=REPO, capture_output=True, text=True).stdout
    untracked = subprocess.run(["git", "ls-files", "--others", "--exclude-standard"], cwd=REPO,
                               capture_output=True, text=True).stdout
    files = sorted({f for f in (changed + untracked).split()
                    if f.endswith(".swift") and re.match(r"(Sources|Tests)/", f) and "CompileCorpus" not in f
                    and os.path.exists(os.path.join(REPO, f))})
    if not files:
        print(f"lint ok (no Swift files changed since {described}, so nothing checked)" + where())
        return True
    swiftlint = "/opt/homebrew/bin/swiftlint" if os.path.exists("/opt/homebrew/bin/swiftlint") else "swiftlint"
    code, out = run([swiftlint, "lint", "--strict", "--quiet", "--config", ".swiftlint.yml", *files])
    problems = [relative(l)[:240] for l in out.splitlines() if l.strip()]
    for line in problems:
        print(line)
    print((f"lint ok ({len(files)} files changed since {described})" if code == 0
           else f"lint FAILED ({len(problems)} lines, {len(files)} files)") + where())
    return code == 0


def parse_all(rest, names_commit):
    """`all`'s arguments -> (BASE or None, suites), or what is wrong with them.

    `all BASE` once read BASE as a suite to test, matching nothing (H-56, TOOLS-14). A first argument that names a
    commit is BASE, with or without `--`; after it, or after `--`, come suites.
    """
    if "--" in rest:
        split = rest.index("--")
        if split > 1:
            return "all takes at most one BASE before --, not %s" % " ".join(rest[:split])
        return (rest[0] if split == 1 else None), rest[split + 1:]
    if rest and names_commit(rest[0]):
        return rest[0], rest[1:]
    return None, rest


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    verb, rest = argv[0], argv[1:]
    wrong = wrong_checkout(os.getcwd(), REPO)
    if wrong:
        print("quick.py: " + wrong)
        return 2
    if verb == "build":
        return 0 if build() else 1
    if verb == "test":
        no_build = "--no-build" in rest
        return 0 if test([s for s in rest if s != "--no-build"], build_first=not no_build) else 1
    if verb == "lint":
        return 0 if lint(rest[0] if rest else None) else 1
    if verb == "all":
        parsed = parse_all(rest, names_commit)
        if isinstance(parsed, str):
            print("quick.py: " + parsed)
            return 2
        base, suites = parsed
        ok = test(suites) if suites else build()
        return 0 if lint(base) and ok else 1
    print(f"unknown verb {verb!r}; see --help")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
