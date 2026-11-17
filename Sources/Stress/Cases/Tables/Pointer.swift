//  🖥️ TUI — A Terminal UI framework for Swift
//  Pointer.swift
//
//  Perf cases: hover in a scene whose focus follows the pointer, over tables,
//  split views, outlines and tab views (HOVER-FOCUS b: a hovered row becomes
//  the cursor row and takes the focus). See `CaseTable.swift` for the columns,
//  and `CaseVocabulary.swift` for the words.
//
//  Created by Wade Tregaskis
//  License: MIT

extension CaseTables {
    // table-hover / split-hover / outline-hover / tabs-hover: the pointer moved down rows of each, a row a step:
    //   each step should rebuild nothing and write two rows' bytes, as list-hover does for a list. split-hover
    //   crosses from the list into the table half-way; outline-hover opens the tree first; tabs-hover is the table
    //   as a tab view's selected tab. (A tab switch between hovers does nothing: the focus has followed the pointer
    //   into the content, where Right is the content's.)
    static let pointer = CaseTableSource(file: #fileID, line: #line, """
        id             composition                             in     size    n     script                       scales  timed  tags
        table-hover    follows(table.wrap5)                    alone  120x40  5000  open;hover:+1*20             flat    -      table,hover,bytes
        split-hover    follows(split(list.plain,table.wrap5))  alone  120x40  3000  open;hover:+1*15;hover:-1*5  flat    -      split,hover,bytes
        outline-hover  follows(outline.list)                   alone  80x24   5000  open;key:oright;hover:+1*20  flat    -      outline,hover,bytes
        tabs-hover     follows(tabs(table.wrap5,list.plain))   alone  120x40  3000  open;hover:+1*20             flat    -      tabs,hover,bytes
        """)
}
