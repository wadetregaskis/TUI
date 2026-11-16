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
    static let editors = CaseTableSource(file: #fileID, line: #line, """
        id             composition  in     size    n     script                               scales  timed  tags
        editor-typing  editor.wrap  alone  100x30  2000  open;key:pgdn*10;type:hello;idle*5  flat    t      editor,wrap,invalidate
        """)
}
