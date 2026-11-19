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
    // timeline-beside: a second of a launcher's 60 Hz loop beside static, dear
    // content and a 5 Hz preview: no body above the timelines runs, no canvas
    // is drawn, and the preview's content changes five times.
    // timeline-list: a second of a focused List of live previews, the first
    // row selected: every row is drawn at each tick, and each of them once.
    static let adopted = CaseTableSource(file: #fileID, line: #line, """
        id         composition                    in  size    n  script         scales  timed  tags
        mail-idle  stress:app-shapes/mail-client  -   120x40  1  open;idle*200  -       t      appshape
        game-loop  stress:app-shapes/game-loop    -   80x24   1  open;tick:17*60 -      t      appshape,memo
        timeline-beside  stress:app-shapes/timeline-beside  -  80x24  1  open;tick:17*60  -  t  appshape,memo
        timeline-list  stress:app-shapes/timeline-list  -  100x30  1  open;tick:17*60  -  t  appshape,list
        """)
}
