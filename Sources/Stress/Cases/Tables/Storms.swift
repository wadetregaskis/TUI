//  🖥️ TUI — A Terminal UI framework for Swift
//  Storms.swift
//
//  Perf cases: resize storms, a page resized ten times in a row, as a window
//  dragged at its corner resizes a terminal: five steps narrower, five back.
//  See `CaseTable.swift` for the columns, and `CaseVocabulary.swift` for the
//  words.
//
//  Created by Wade Tregaskis
//  License: MIT

extension CaseTables {
    // resize-storm: a dashboard-like page (a list beside tabs of a wrapped table and a grid) resized ten times: each
    //   resize should cost the rows shown, and the hidden grid nothing. Timed: a resize redraws every cell, which no
    //   count weighs.
    // nsplit-storm: a navigation split of a list and a `.fit` table through the same storm, ending narrow enough
    //   to collapse and coming back.
    // dashboard-storm: the `dashboard` scenario's panels through the same storm. Timed, as resize-storm.
    static let storms = CaseTableSource(file: #fileID, line: #line, """
        id               composition                    in     size    n    script                                scales  timed  tags
        resize-storm  split(list.plain,tabs(table.wrap5,grid))  alone  160x50  300  open;resize:-16x-5*5;resize:+16x+5*5  flat  t  resize,storm,split,tabs
        nsplit-storm     nsplit(list.plain,table.fit5)  alone  60x20   300  open;resize:-9x-3*5;resize:+9x+3*5    flat    -      resize,storm,navigation
        dashboard-storm  stress:dashboard               -      160x50  1    open;resize:-16x-5*5;resize:+16x+5*5  -       t      resize,storm,appshape
        """)
}
