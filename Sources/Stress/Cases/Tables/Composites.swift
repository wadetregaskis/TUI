//  🖥️ TUI — A Terminal UI framework for Swift
//  Composites.swift
//
//  Perf cases: controls holding other controls — tab views, split views. See
//  `CaseTable.swift` for the columns, and `CaseVocabulary.swift` for the words.
//
//  Created by Wade Tregaskis
//  License: MIT

extension CaseTables {
    // tabs-switch: whether a hidden tab's table is built, measured or drawn, and what a switch costs on each side,
    //   the first time and again. The tab strip holds the focus as the page opens, so Right and Left switch (the
    //   design's `key:tab;key:right*10` moved the focus into the list, where Right does nothing: 0 bytes).
    // split-resize: a list beside a table, resized narrow and back: rows rebuilt per resize, and whether `.fit`
    // widths are computed once or once per pass.
    static let composites = CaseTableSource(file: #fileID, line: #line, """
        id            composition                   in     size    n     script                                    scales  timed  tags
        tabs-switch   tabs(list.plain,table.fit5)   alone  120x40  3000  open;key:right;key:left;key:right;key:left  flat    -      tabs,offscreen
        split-resize  split(list.plain,table.fit5)  alone  200x60  3000  open;resize:80x24;resize:200x60*5         flat    -      split,resize,narrow
        """)
}
