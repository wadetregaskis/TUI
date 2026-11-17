//  🖥️ TUI — A Terminal UI framework for Swift
//  Adopted.swift
//
//  Perf cases: existing `Stress` scenarios adopted as rows, with no new code,
//  so the table can take over the timed sweep's scenarios one by one. See
//  `CaseTable.swift` for the columns.
//
//  Created by Wade Tregaskis
//  License: MIT

extension CaseTables {
    // mail-idle: the `app-shapes` mail client, at rest.
    // game-loop: the `app-shapes` game, a second of its 60 Hz loop: the canvases
    // beside the timeline are drawn when the board moves, not on every frame.
    static let adopted = CaseTableSource(file: #fileID, line: #line, """
        id         composition                    in  size    n  script         scales  timed  tags
        mail-idle  stress:app-shapes/mail-client  -   120x40  1  open;idle*200  -       t      appshape
        game-loop  stress:app-shapes/game-loop    -   80x24   1  open;tick:17*60 -      t      appshape,memo
        """)
}
