//  🖥️ TUI — A Terminal UI framework for Swift
//  Editors.swift
//
//  Perf cases: text editors. See `CaseTable.swift` for the columns, and
//  `CaseVocabulary.swift` for the words.
//
//  Created by Wade Tregaskis
//  License: MIT

extension CaseTables {
    // editor-typing: a wrapped `TextEditor` paged to its middle and typed into: the work per keystroke must not
    // depend on the document's length.
    // editor-mid-typing: a mid-size document (300 lines) in 80x24, paged to its middle, a sentence typed, three new
    //   lines and ten characters taken back: a keystroke's work, and a new line's, must not depend on the length.
    //   Timed: a keystroke's cost is in the text storage and the wrap, which no count weighs.
    // editor-sheet-typing: the same typing in an editor in a sheet over a list: whether a keystroke in the sheet
    //   costs the page behind it.
    static let editors = CaseTableSource(file: #fileID, line: #line, """
        id                 composition  in     size    n     script                                                      scales  timed  tags
        editor-typing      editor.wrap  alone  100x30  2000  open;key:pgdn*10;type:hello;idle*5                          flat    t      editor,wrap,invalidate
        editor-mid-typing  editor.wrap  alone  80x24   300   open;key:pgdn*4;type:the_quick_fox;key:enter*3;key:bksp*10  flat    t      editor,typing
        editor-sheet-typing  sheet(list.plain,editor.wrap)  alone  80x24  300  open;present;key:pgdn*3;type:hello;key:bksp*5  flat  -  editor,sheet,typing
        """)
}
