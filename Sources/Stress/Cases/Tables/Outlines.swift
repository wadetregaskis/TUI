//  🖥️ TUI — A Terminal UI framework for Swift
//  Outlines.swift
//
//  Perf cases: outlines, a tree in a `List` and in a `Table`. See
//  `CaseTable.swift` for the columns, and `CaseVocabulary.swift` for the words.
//
//  Created by Wade Tregaskis
//  License: MIT

extension CaseTables {
    // outline-list / outline-table: a tree of n rows under one root (`CaseRows.tree`), opened all the way by
    //   Option-Right on the root, so n + 1 rows show; then scrolled, paged down, and a branch closed and opened
    //   again (Left walks from a leaf to its group, Left again closes it). Every step must cost the rows on
    //   screen, not the rows open (finding G1, from building tuitree).
    static let outlines = CaseTableSource(file: #fileID, line: #line, """
        id             composition    in     size   n     script                                                        scales  timed  tags
        outline-list   outline.list   alone  80x24  5000  open;key:oright;wheel:+5*10;key:pgdn*3;key:left*2;key:right  flat    -      list,outline,window
        outline-table  outline.table  alone  80x24  5000  open;key:oright;wheel:+5*10;key:pgdn*3;key:left*2;key:right  flat    -      table,outline,window
        """)
}
