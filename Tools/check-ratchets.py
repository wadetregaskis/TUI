#!/usr/bin/env python3
"""Fail if a count that is meant only to fall has risen.

Each ratchet is a count of matching lines, and the most it may be. Lower the limit
in the commit that lowers the count, so that the count can't come back.

Usage: check-ratchets.py [--self-test]
Exit status: 0 if no count is over its limit, 1 otherwise.
"""

import re
import subprocess
import sys

RATCHETS = [
    # The exceptions to the SwiftLint rule `concurrency_escape`, each with its reason
    # in a comment. The rule refuses a new one, unless it is disabled on its line.
    # 12 since staging's Windows port (rebased under local work 2026-11-21):
    # ConsoleInput, the console reader's queue, is @unchecked Sendable because its
    # state is guarded by the NSCondition its reader waits on, which no Mutex is.
    {
        "name": "unsafe-concurrency exceptions",
        "pattern": r"disable:this concurrency_escape",
        "paths": ["Sources"],
        "limit": 12,
        "instead": "try dropping Sendable, a Mutex, an Atomic, @MainActor or sending",
    },
    # The exceptions to the SwiftLint rule `safe_escape`: a type marked `@safe`, which
    # silences strict memory safety for every use of it. Each says why on its line.
    {
        "name": "@safe exceptions",
        "pattern": r"disable:this safe_escape",
        "paths": ["Sources", "Tests"],
        "limit": 0,
        "instead": "remove the unsafe storage, or mark the type @unsafe",
    },
    # A test that sleeps is slow, or racy, or both. A thread's sleep is as much
    # one as a task's, so `Thread.sleep`, `usleep` and `nanosleep` count too.
    # 7 since staging's Windows port (rebased under local work 2026-11-21):
    # WindowsSessionEndTests waits twice for what the system's own thread does
    # with the hidden window (its making, and a posted WM_ENDSESSION), which no
    # clock of the test's steps.
    {
        "name": "sleeps in tests",
        "pattern": r"^(?!\s*//).*\b(Task\.sleep|Thread\.sleep|usleep|nanosleep)\b",
        "paths": ["Tests"],
        "limit": 7,
        "instead": "wait for what the test wants, or step a clock of the test's own",
    },
    # Lines that convert to an integer with the TRAPPING initialiser over what reads as
    # a floating-point expression: `Int((x * w).rounded())`, `Int64(seconds * 1e9)`.
    # `Int(_: Double)` traps, in release builds too, on NaN, either infinity and any
    # magnitude past the type's range, and an app's numbers reach every kind (hunt
    # 11-20: thirty crash findings of this one class). Use `Int(clamping:)` or
    # `Int64(clamping:)` (NaN to 0, a magnitude to the nearer bound), `Int(cells:)`
    # (held to +-2^30, for a distance added to a position) or
    # `AnimationClock.deadline` (a wait that may be forever), in
    # TUICore/Extensions/Int+ClampingDouble.swift and AnimatedCellRun.swift.
    #
    # A ratchet, not a SwiftLint rule: a regex cannot tell a `Double` from an `Int`
    # (it misses `Int(seconds)` over a `Double` variable, about 40 of the 265 sites a
    # compiler-checked sweep found) and most of the lines it does match are bounded
    # first (`Int(min(255, max(0, x)))`, a pixel's luminance). A rule would need a
    # disable and a reason on each of those, so the count is held instead.
    {
        "name": "trapping float-to-integer conversions",
        "pattern": (
            r"^(?!\s*//).*?\b(?:U?Int(?:8|16|32|64)?)\("
            r"(?!clamping:|exactly:|truncatingIfNeeded:|bitPattern:|cells:|truncating:)"
            r".*?(?:\.rounded\(|\bDouble\((?!Int)|\bCGFloat\(|\bFloat\(|\.squareRoot\(\)|\bpow\()"
        ),
        "paths": ["Sources"],
        "limit": 183,
        "instead": "convert with Int(clamping:), Int64(clamping:), Int(cells:) or AnimationClock.deadline",
    },
]


def count(pattern, lines):
    """How many of `lines` match `pattern`."""
    compiled = re.compile(pattern)
    return sum(1 for line in lines if compiled.search(line))


def tracked_lines(paths):
    """Every line of the Swift files git tracks under `paths`."""
    listed = subprocess.run(
        ["git", "ls-files", "-z", "--"] + paths, capture_output=True, text=True, check=True
    ).stdout
    lines = []
    for path in listed.split("\0"):
        if path.endswith(".swift"):
            with open(path, encoding="utf-8", errors="replace") as source:
                lines.extend(source)
    return lines


def self_test():
    sleeps = next(ratchet for ratchet in RATCHETS if "sleep" in ratchet["name"])
    assert count(sleeps["pattern"], ["try await Task.sleep(for: .seconds(1))"]) == 1
    assert count(sleeps["pattern"], ["    // Task.sleep here would race"]) == 0
    assert count(sleeps["pattern"], ["clock.sleep(for: .seconds(1))"]) == 0
    assert count(sleeps["pattern"], ["        Thread.sleep(forTimeInterval: 0.8)"]) == 1
    assert count(sleeps["pattern"], ["            usleep(100_000)"]) == 1
    assert count(sleeps["pattern"], ["    /// `usleep` and another sampling"]) == 0
    floats = next(ratchet for ratchet in RATCHETS if "float-to-integer" in ratchet["name"])
    assert count(floats["pattern"], ["        let x = Int((anchor.x * Double(width)).rounded(.down))"]) == 1
    assert count(floats["pattern"], ["    expiry = start &+ Int64(max(0, seconds) * 1e9.rounded())"]) == 1
    assert count(floats["pattern"], ["        let x = Int(clamping: (anchor.x * Double(width)).rounded(.down))"]) == 0
    assert count(floats["pattern"], ["        let x = Int(cells: (anchor.x * Double(width)).rounded(.down))"]) == 0
    assert count(floats["pattern"], ["        let level = UInt8(clamping: Int(clamping: (tone * 255).rounded()))"]) == 0
    assert count(floats["pattern"], ["    // Int((x).rounded()) trapped here"]) == 0
    assert count(floats["pattern"], ["        let sum = Double(Int(r)) * 0.299"]) == 0
    print("check-ratchets: self-test passed")
    return 0


def main():
    if "--self-test" in sys.argv[1:]:
        return self_test()
    failed = False
    for ratchet in RATCHETS:
        found = count(ratchet["pattern"], tracked_lines(ratchet["paths"]))
        limit = ratchet["limit"]
        if found > limit:
            failed = True
            print(f"error: {found} {ratchet['name']}, and the limit is {limit}: {ratchet['instead']}.")
        elif found < limit:
            print(f"{found} {ratchet['name']}, under the limit of {limit}: lower it in Tools/check-ratchets.py.")
        else:
            print(f"{found} {ratchet['name']}, at the limit.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
