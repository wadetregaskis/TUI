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
        "outline-scroll": (
            ["bodies", "open misses"],
            "PERFCASE-F14: at 10n a bare outline's first frame runs 15% more bodies and misses 19% more measures, "
                + "and each frame after one more body: likely the measure ladder's extra rung, which builds its "
                + "unmemoised rows' sample and the outline's own body again"
        ),
        "chat-lazy-follow": (
            ["bodies", "misses"],
            "PERFCASE-F3: at 10n the bottom-anchored lazy stack runs 21% more bodies and misses 29% more measures "
                + "at open, and 10% / 19% more per appended row"
        ),
        // Lane L4 (2026-11-17): the first thirty-odd cases over situations not profiled before.
        "chat-tiny": (["bodies", "misses"], "PERFCASE-F3, as chat-lazy-follow, in a 20x6 terminal"),
        "alert-table": (["open cells"], "a .fit column reads every row as its table opens (PERFCASE-F5), as table-fit-tail"),
        "table-fit-tiny": (["open cells"], "a .fit column reads every row as its table opens (PERFCASE-F5), as table-fit-tail"),
        "nsplit-resize": (
            ["listed", "built", "bodies", "misses"],
            "PERFCASE-F6: a NavigationSplitView measures its leading columns offered no height, and a List offered "
                + "none lists, runs and measures every row: about n row boxes a pass"
        ),
        "nsplit-collapse": (["open listed", "open bodies", "open misses"], "PERFCASE-F6, until the split collapses"),
        "nsplit-three": (["listed", "built", "bodies", "misses"], "PERFCASE-F6, in both leading columns"),
        "nsplit-storm": (
            ["listed", "bodies", "misses", "cells"],
            "PERFCASE-F6 at every resize the split is not collapsed, and PERFCASE-F5's .fit reread at each resize"
        ),
        "form-narrow": (
            ["built", "served", "bodies", "misses"],
            "PERFCASE-F7: a Form is an eager stack: it builds every row as it opens, and each frame reads its content "
                + "and asks every row's memo, served, about a body and seven measure misses a row"
        ),
        "form-grouped-tab": (
            ["built", "served", "bodies", "misses"],
            "PERFCASE-F7, and a toggle's write draws every row again: each row's toggle reads the one set of checked rows"
        ),
        "form-columns-tab": (["built", "served", "bodies", "misses"], "PERFCASE-F7, in .columns style"),
        "form-slider": (
            ["built", "served", "bodies", "misses"], "PERFCASE-F7: a slider's step asks every toggle's memo, served"
        ),
        "resize-storm": (
            ["listed", "built", "bodies", "misses"],
            "PERFCASE-F8: a TabView measures its hidden tab (an eager grid of n rows) as it opens and again at every "
                + "resize that narrows it; and the narrowing resizes list and build 7 rows more at 10n (PERFCASE-F12)"
        ),
        "sheet-item-walk": (
            ["open cells"],
            "PERFCASE-F12: the wrapped table behind reads 10 more cell values as it opens at 10n than at n = 1,000"
        ),
        "list-tiny": (["open misses"], "PERFCASE-F12: 4 more measure misses as the list opens in 20x6 at 10n"),
        "split-tiny": (["resize:40x12 misses"], "PERFCASE-F12: 4 fewer measure misses at the resize at 10n"),
    ]
}
