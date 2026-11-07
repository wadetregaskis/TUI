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
- parallel_test.py reports FAILED when a filter selects more tests than its partition predicted (a RECONCILIATION
  line), though every group passed. That case is reported here as a pass, with the count.
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
    environment.pop("SDKROOT", None)
    environment.setdefault("TUI_CONFIG_DIR", os.path.join(REPO, ".tuikit-test-config"))
    os.makedirs(environment["TUI_CONFIG_DIR"], exist_ok=True)
    return environment


def wrapped(command):
    wrapper = os.environ.get("TUI_RUN_WRAPPER")
    return shlex.split(wrapper) + command if wrapper else command


def run(command):
    process = subprocess.run(wrapped(command), cwd=REPO, env=env(), capture_output=True, text=True)
    return process.returncode, process.stdout + process.stderr


def relative(line):
    return line.replace(REPO + "/", "")


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
    command = ["python3", "Tools/ParallelTest/parallel_test.py", "-j", "4", "--no-build",
               "--filter", "|".join(suites)]
    code, out = run(command)
    issues = []
    for line in out.splitlines():
        if "recorded an issue" in line or re.search(r"\bFatal error\b|\bcrashed\b|signal \d+", line):
            issue = re.sub(r"^\s*\S*\s*Test ", "Test ", line.strip())
            issue = re.sub(r" with \d+ arguments?", "", issue)
            if issue not in issues:
                issues.append(issue)
    summary = next((l for l in reversed(out.splitlines()) if l.startswith("parallel-test:") and "tests in" in l), "")
    groups_ok = all(" ok" in l for l in out.splitlines() if re.match(r"\s+group g\d+:", l)) and \
        any(re.match(r"\s+group g\d+:", l) for l in out.splitlines())
    reconciliation_only = "FAILED" in summary and not issues and groups_ok and "RECONCILIATION" in out
    for issue in issues[:30]:
        print(issue[:240])
    if len(issues) > 30:
        print(f"… {len(issues) - 30} more")
    count = re.search(r"(\d+) tests in", summary)
    n = count.group(1) if count else "?"
    if (code == 0 and "passed" in summary) or reconciliation_only:
        print(f"tests ok ({n})" + (" — the filter matched tests beyond its plan; every group passed"
                                    if reconciliation_only else ""))
        return True
    if not issues:
        tail = [l for l in out.splitlines() if l.strip()][-12:]
        print("\n".join(relative(l)[:240] for l in tail))
    print(f"tests FAILED ({n})")
    return False


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
