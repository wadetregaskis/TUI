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
/// counts named are excused — a bare count (`"cells"`) in every phase, a count
/// after a phase's label (`"open cells"`) in that phase alone — and any other
/// count that breaks the class fails. The fix of a finding takes its entry out.
///
/// The scaling rerun's own counts are still recorded and compared exactly
/// (the `@10n` / `@2n` lines), so a finding that gets worse fails there.
/// Each is described in the design's "Findings" (`Documentation/Historical/
/// Performance/A declarative perf-case table.md`).
enum CaseKnownIssues {
    static let scaling: [String: (counts: Set<String>, finding: String)] = [
        "table-fit-tail": (
            ["open cells"],
            "a .fit column reads every row as its table opens, which is what .fit means (5n cell values), and "
                + "again for each whole-cache clear of the open's frames (PERFCASE-F5)"
        ),
        "tabs-switch": (
            ["open cells", "key:right cells"],
            "the hidden tab's table reads its .fit columns at open (5n cell values), measured for the panel's size, "
                + "and again at the first switch to it, whose frame clears the whole cache (PERFCASE-F5)"
        ),
        "split-resize": (
            ["open cells", "resize:80x24 cells", "resize:200x60 cells", "misses"],
            "PERFCASE-F5: a resize clears the whole cache, and a .fit column's kept walk with it; and the narrow "
                + "resize misses 12 more measures at 10n than at n"
        ),
        "outline-rows": (
            ["listed"],
            "G1-rows: a Table whose tree is row content (DisclosureTableRow) runs the row builders of every open row "
                + "on every pass (n + 1 a frame): the tree exists only as those closures"
        ),
        "outline-rows-stacked": (
            ["listed"],
            "G1-rows, as outline-rows: every open row's row builders run on every pass that lays the table out"
        ),
        "outline-table": (
            ["key:oright listed"],
            "Option-Right on the root opens all n rows, and lists them: that is its change, not a finding"
        ),
        "outline-children-bound": (
            ["key:oright listed"],
            "as outline-table: Option-Right on the root opens all n rows, and lists them"
        ),
        "outline-toggle": (
            ["open listed"],
            "the tree starts open, so its first frame lists its n + 1 rows: what opening it costs, not a finding"
        ),
        "chat-lazy-follow": (
            ["bodies", "misses"],
            "PERFCASE-F3: at 10n the bottom-anchored lazy stack runs 21% more bodies and misses 29% more measures "
                + "at open, and 10% / 19% more per appended row"
        ),
    ]
}
