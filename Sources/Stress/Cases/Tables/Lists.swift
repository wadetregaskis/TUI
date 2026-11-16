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
    // list-search: `.searchable` over 10,000 rows; whether filtered-out rows still run. `flat`, not the design's
    //   `linear`: the O(n) filter is the app's own code, which no count sees, and the framework's work is O(window)
    //   (measured 2026-11-15). Tab first: the list holds the focus as the page opens, as on macOS (`InboxSession`).
    static let lists = CaseTableSource(file: #fileID, line: #line, """
        id           composition  in     size   n      script                           scales  timed  tags
        list-wheel   list.plain   alone  80x24  10000  open;wheel:+5*20                 flat    t      list,window
        list-hover   list.plain   alone  80x24  10000  open;hover:+1*20                 flat    -      list,hover,bytes
        list-search  list.search  alone  80x24  10000  open;key:tab;type:ab;key:bksp*2  flat    -      list,search,invalidate
        """)
}
