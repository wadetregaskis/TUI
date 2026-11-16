//  🖥️ TUI — A Terminal UI framework for Swift
//  Outlines.swift
//
//  Perf cases: outlines, a tree in a `List` and in a `Table`. See
//  `CaseTable.swift` for the columns, and `CaseVocabulary.swift` for the words.
//
//  Created by Wade Tregaskis
//  License: MIT

extension CaseTables {
    // outline-list / outline-table / outline-rows / outline-section: a tree of n rows under one root
    //   (`CaseRows.tree`), opened all the way by Option-Right on the root, so n + 1 rows show; then scrolled, paged
    //   down, and a branch closed and opened again (Left walks from a leaf to its group, Left again closes it). Every
    //   step must cost the rows on screen, not the rows open (finding G1, from building tuitree). outline-rows is
    //   the table tuitree draws: its rows written as `Table(of:columns:rows:)` content, a `DisclosureTableRow` for
    //   each branch; outline-rows-stacked is that table under a title in a `VStack`, as tuitree's page holds it,
    //   where the stack measures the table before it is drawn; outline-section is the list's outline inside a
    //   `Section`. outline-children-bound is outline-table with the app keeping its expansion
    //   (`Table(_:children:expansion:)`, the windowed way to a tree that starts open, G1-rows (d)): the keys write
    //   the app's set, and every count is outline-table's.
    static let outlines = CaseTableSource(file: #fileID, line: #line, """
        id               composition      in     size   n     script                                                       scales  timed  tags
        outline-list     outline.list     alone  80x24  5000  open;key:oright;wheel:+5*10;key:pgdn*3;key:left*2;key:right  flat    -      list,outline,window
        outline-table    outline.table    alone  80x24  5000  open;key:oright;wheel:+5*10;key:pgdn*3;key:left*2;key:right  flat    -      table,outline,window
        outline-rows     outline.rows     alone  80x24  5000  open;key:oright;wheel:+5*10;key:pgdn*3;key:left*2;key:right  flat    -      table,outline,window
        outline-section  outline.section  alone  80x24  5000  open;key:oright;wheel:+5*10;key:pgdn*3;key:left*2;key:right  flat    -      list,outline,window
        outline-rows-stacked  outline.rows  stacked  80x24  5000  open;key:oright;wheel:+5*10;key:pgdn*3;key:left*2;key:right  flat  -  table,outline,window
        outline-children-bound  outline.bound  alone  80x24  5000  open;key:oright;wheel:+5*10;key:pgdn*3;key:left*2;key:right  flat  -  table,outline,window
        """)
}
