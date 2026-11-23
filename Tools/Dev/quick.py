#!/usr/bin/env python3
"""quick.py: the build, test and lint loop, with only what needs reading printed.

    Tools/Dev/quick.py build                     # build with tests; errors and warnings only
    Tools/Dev/quick.py test SuiteA SuiteB ...    # build, then run those suites; failures only
    Tools/Dev/quick.py test --no-build SuiteA    # run only
    Tools/Dev/quick.py lint [BASE]               # SwiftLint --strict on Swift files changed since BASE
    Tools/Dev/quick.py all [BASE] -- SuiteA ...  # build, test, lint

Each prints one verdict line last: "build ok", "tests ok (N)", "lint ok", or what failed.

Why it exists (see README.md): the plain commands print thousands of lines that are then filtered by hand, and each
has a trap that cost a whole build-and-run to find:
- Bare `swift test` doesn't set up the environment CI uses, and colour tests fail spuriously (at 256 colours or none).
  This runs `Tools/ParallelTest/parallel_test.py`, which does.
- A run that ran no tests is not a pass: "tests ok (0)" is never printed. A filter matching nothing, or a run whose
  count does not reconcile, is "tests FAILED".
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


def build():
    code, out = run(["swift", "build", "--build-tests", "-j", str(max(1, (os.cpu_count() or 4) // 3))])
    problems = sorted({relative(l.strip()) for l in out.splitlines()
                       if re.search(r"(error|warning): ", l) and "ld: warning" not in l})
    for line in problems[:40]:
        print(line[:240])
    if len(problems) > 40:
        print(f"… {len(problems) - 40} more")
    if code != 0 or any(" error: " in p or p.startswith("error:") for p in problems):
        print("build FAILED")
        return False
    print("build ok" + (f" ({len(problems)} warnings)" if problems else ""))
    return not problems


def test(suites, build_first=True):
    if build_first and not build():
        return False
    if not suites:
        print("tests: no suites named")
        return False
    command = [sys.executable, "Tools/ParallelTest/parallel_test.py", "-j", "4", "--no-build",
               "--filter", "|".join(suites)]
    code, out = run(command)
    ok, lines = test_verdict(code, out)
    for line in lines:
        print(line)
    return ok


def test_verdict(code, out):
    """parallel_test.py's exit code and output -> (passed, the lines to print, the verdict last).

    A pass is parallel_test's own: exit 0 and a summary that says "passed", which it gives only when every group
    ran exactly the tests the partition proved it selects. Nothing here overrides a FAILED. An earlier version
    passed a FAILED whose only problems were RECONCILIATION lines, to excuse a filter narrower than a suite
    running the whole suite; that also passed a group that ran FEWER tests than planned, or none (H-56). The
    partition selects exactly the filtered tests now, so there is nothing left to excuse.
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
        lines.append(f"tests ok ({n})")
        return True, lines
    if not issues:
        tail = [l for l in out.splitlines() if l.strip()][-12:]
        lines.extend(relative(l)[:240] for l in tail)
    lines.append(f"tests FAILED ({'?' if n is None else n})" + (": no test ran" if n == 0 else ""))
    return False, lines


def lint(base=None):
    if base is None:
        base = subprocess.run(["git", "merge-base", "HEAD", "main"], cwd=REPO, capture_output=True,
                              text=True).stdout.strip() or "HEAD"
    changed = subprocess.run(["git", "diff", "--name-only", base], cwd=REPO, capture_output=True, text=True).stdout
    untracked = subprocess.run(["git", "ls-files", "--others", "--exclude-standard"], cwd=REPO,
                               capture_output=True, text=True).stdout
    files = sorted({f for f in (changed + untracked).split()
                    if f.endswith(".swift") and re.match(r"(Sources|Tests)/", f) and "CompileCorpus" not in f
                    and os.path.exists(os.path.join(REPO, f))})
    if not files:
        print("lint ok (no Swift files changed)")
        return True
    swiftlint = "/opt/homebrew/bin/swiftlint" if os.path.exists("/opt/homebrew/bin/swiftlint") else "swiftlint"
    code, out = run([swiftlint, "lint", "--strict", "--quiet", "--config", ".swiftlint.yml", *files])
    problems = [relative(l)[:240] for l in out.splitlines() if l.strip()]
    for line in problems:
        print(line)
    print("lint ok" if code == 0 else f"lint FAILED ({len(problems)} lines, {len(files)} files)")
    return code == 0


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    verb, rest = argv[0], argv[1:]
    if verb == "build":
        return 0 if build() else 1
    if verb == "test":
        no_build = "--no-build" in rest
        return 0 if test([s for s in rest if s != "--no-build"], build_first=not no_build) else 1
    if verb == "lint":
        return 0 if lint(rest[0] if rest else None) else 1
    if verb == "all":
        base, suites = None, rest
        if "--" in rest:
            split = rest.index("--")
            base = rest[0] if split == 1 else None
            suites = rest[split + 1:]
        ok = test(suites) if suites else build()
        return 0 if lint(base) and ok else 1
    print(f"unknown verb {verb!r}; see --help")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
