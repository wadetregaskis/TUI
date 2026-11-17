//  🖥️ TUI — A Terminal UI framework for Swift
//  Narrow.swift
//
//  Perf cases: the main containers in narrow and tiny terminals, 40x12 and
//  20x6, where a narrow terminal takes other paths (truncation, wrapping,
//  columns that do not fit). See `CaseTable.swift` for the columns, and
//  `CaseVocabulary.swift` for the words.
//
//  Created by Wade Tregaskis
//  License: MIT

extension CaseTables {
    // list-tiny: a windowed list scrolled and walked in 20x6.
    // table-narrow / table-fit-tiny: a wrapped table in 40x12, and `.fit` columns in 20x6 that cannot all fit.
    // split-tiny: a split view of a list and a table in 20x6, then widened.
    // form-narrow: a form of a toggle per row in 40x12, walked by Tab and scrolled: a form is a list on macOS, so
    //   its work should be O(window).
    // chat-tiny: the bottom-anchored conversation in 20x6, a message appended a frame.
    // editor-tiny: a wrapped editor in 20x6, paged and typed into: every line wraps at 20 columns.
    static let narrow = CaseTableSource(file: #fileID, line: #line, """
        id              composition                    in      size   n      script                        scales  timed  tags
        list-tiny       list.plain                     alone   20x6   10000  open;wheel:+5*10;key:down*5   flat    -      list,window,tiny
        table-narrow    table.wrap5                    alone   40x12  5000   open;wheel:+5*10;key:down*5   flat    -      table,wrap,narrow
        table-fit-tiny  table.fit5                     alone   20x6   2000   open;wheel:+5*5               flat    -      table,tiny
        split-tiny      split(list.plain,table.wrap5)  alone   20x6   3000   open;wheel:+5*5;resize:40x12  flat    -      split,tiny,resize
        form-narrow     form.grouped                   alone   40x12  5      open;key:tab*8;wheel:+5*5     flat    -      form,narrow,focus
        chat-tiny       chat.lazy                      bottom  20x6   2000   open;append:1*20              flat    -      scroll,anchor,lazy,tiny
        editor-tiny     editor.wrap                    alone   20x6   500    open;key:pgdn*5;type:abc      flat    -      editor,wrap,tiny,typing
        """)
}
