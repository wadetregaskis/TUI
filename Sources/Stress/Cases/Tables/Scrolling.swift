//  🖥️ TUI — A Terminal UI framework for Swift
//  Scrolling.swift
//
//  Perf cases: scroll views. See `CaseTable.swift` for the columns, and
//  `CaseVocabulary.swift` for the words.
//
//  Created by Wade Tregaskis
//  License: MIT

extension CaseTables {
    // chat-lazy-follow: bottom-anchored, variable-height rows, one appended a frame: `scrollfollow`'s claim
    // (O(window) at any n), with a count that fails if it breaks.
    // chat-eager-follow: the eager half of the `chat` pair, timed because the pair is the measurement, and `linear`
    // because an eager stack is meant to be.
    static let scrolling = CaseTableSource(file: #fileID, line: #line, """
        id                 composition  in      size   n     script             scales  timed  tags
        chat-lazy-follow   chat.lazy    bottom  80x24  5000  open;append:1*100  flat    -      scroll,anchor,lazy
        chat-eager-follow  chat.eager   bottom  80x24  500   open;append:1*20   linear  t      scroll,anchor,eager
        """)
}
