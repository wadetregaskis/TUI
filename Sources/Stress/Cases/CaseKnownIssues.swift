//  🖥️ TUI — A Terminal UI framework for Swift
//  CaseKnownIssues.swift
//
//  The cases whose counts do not keep the scaling class the case states: a
//  finding, measured and filed, not yet fixed. A case states what it is FOR
//  (the table's `scales` column); this says where the code falls short of it.
//
//  Created by Wade Tregaskis
//  License: MIT

/// Findings a case's scaling rerun shows, by case: printed as `KNOWN` on every
/// run, and failed for nothing, as a session's `knownIssues` are. Only the
/// counts named are excused; any other count that breaks the class fails.
/// The fix of a finding takes its entry out.
///
/// The scaling rerun's own counts are still recorded and compared exactly
/// (the `@10n` / `@2n` lines), so a finding that gets worse fails there.
/// Each is described in the design's "Findings" (`Documentation/Historical/
/// Performance/A declarative perf-case table.md`).
enum CaseKnownIssues {
    static let scaling: [String: (counts: Set<String>, finding: String)] = [
        "table-fit-tail": (
            ["cells"],
            "PERFCASE-F1: every appended row rescans all n rows of every .fit column (5n cell values a frame): "
                + "the fit-width memo is keyed by the rows, which an append changes"
        ),
        "tabs-switch": (
            ["cells"],
            "PERFCASE-F2: the hidden tab's table scans its .fit columns at open (5n cell values) though it draws "
                + "nothing, and every switch to it scans them again (PERFCASE-F1's memo, dropped while hidden)"
        ),
        "split-resize": (
            ["cells", "misses"],
            "PERFCASE-F1 again, per resize; and the narrow resize misses 12 more measures at 10n than at n"
        ),
        "chat-lazy-follow": (
            ["bodies", "misses"],
            "PERFCASE-F3: at 10n the bottom-anchored lazy stack runs 21% more bodies and misses 29% more measures "
                + "at open, and 10% / 19% more per appended row"
        ),
    ]
}
