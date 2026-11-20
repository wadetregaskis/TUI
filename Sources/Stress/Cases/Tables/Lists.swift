//  🖥️ TUI — A Terminal UI framework for Swift
//  Lists.swift
//
//  Perf cases: lists. See `CaseTable.swift` for the columns, and
//  `CaseVocabulary.swift` for the words.
//
//  Created by Wade Tregaskis
//  License: MIT

extension CaseTables {
    // list-wheel: the windowed list's steady scroll; rows built per wheel step must not depend on n.
    // list-hover: the owner's 2026-11-10 ruling that hover moves the list row; what a hover step rebuilds and writes.
    //   `follows(…)`: the ruling (HOVER-FOCUS b) is for a scene whose focus follows the pointer; without it a hover
    //   rightly moves nothing (PERFCASE-F4, the case's own mistake).
    // list-search: `.searchable` over 10,000 rows; whether filtered-out rows still run. `flat`, not the design's
    //   `linear`: the O(n) filter is the app's own code, which no count sees, and the framework's work is O(window)
    //   (measured 2026-11-15). Tab first: the list holds the focus as the page opens, as on macOS (`InboxSession`).
    // list-typeselect / table-typeselect: a key typed into a focused list or table is type select, and a prefix no
    //   row starts with ("ab") asks every row for its text: a list draws each row it passes as a measure (a row the
    //   app built from views has no other way to its words; a plain `Text` is read), a table reads its first column's
    //   cell. `linear` by design (`TypeSelectScanTests`). PERFCASE-F11 was this, in a sheet, read as a search.
    // list-breath: a second of a focused list of plain rows at rest, so the one change from frame to frame is the
    //   cursor row's breath (the focus indicator always breathes): what a frame of breathing costs the list.
    static let lists = CaseTableSource(file: #fileID, line: #line, """
        id           composition          in     size   n      script                           scales  timed  tags
        list-wheel   list.plain           alone  80x24  10000  open;wheel:+5*20                 flat    t      list,window
        list-hover   follows(list.plain)  alone  80x24  10000  open;hover:+1*20                 flat    -      list,hover,bytes
        list-search  list.search          alone  80x24  10000  open;key:tab;type:ab;key:bksp*2  flat    -      list,search,invalidate
        list-typeselect   list.plain   alone  80x24   1000  open;type:ab  linear  -  list,typing,offscreen
        list-breath  list.plain  alone  80x24  30  open;tick:17*60  flat  t  list,focus
        table-typeselect  table.wrap5  alone  120x40  10000  open;type:ab  linear  -  table,typing,offscreen
        """)
}
