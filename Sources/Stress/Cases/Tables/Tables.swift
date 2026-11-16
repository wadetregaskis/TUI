//  🖥️ TUI — A Terminal UI framework for Swift
//  Tables.swift
//
//  Perf cases: tables. See `CaseTable.swift` for the columns, and
//  `CaseVocabulary.swift` for the words.
//
//  Created by Wade Tregaskis
//  License: MIT

extension CaseTables {
    // table-fit-tail: `.fit` columns with a row appended per frame; the `.fit` memo must look at the new row, not
    // rescan all 2,000 (the O(rows) scan `sweep.py` found, kept from coming back).
    static let tables = CaseTableSource(file: #fileID, line: #line, """
        id              composition  in     size    n     script            scales  timed  tags
        table-fit-tail  table.fit5   alone  120x40  2000  open;append:1*50  flat    t      table,memo,tail
        """)
}
