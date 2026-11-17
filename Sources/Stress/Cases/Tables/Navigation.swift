//  🖥️ TUI — A Terminal UI framework for Swift
//  Navigation.swift
//
//  Perf cases: tab views of several kinds of content, and navigation split
//  views, resized and collapsed into a stack. See `CaseTable.swift` for the
//  columns, and `CaseVocabulary.swift` for the words.
//
//  Created by Wade Tregaskis
//  License: MIT

extension CaseTables {
    // tabs-kinds: a tab each of a list, a wrapped table, the value controls and an editor, walked to the last and
    //   back: what showing each kind costs, and whether a hidden one costs anything. Eager kinds stay out: a form's
    //   tab (PERFCASE-F7) made the selfcheck's 150 steps of it 95 s, debug, and a grid's fixed work kept `linear`
    //   from holding at any n the selfcheck can afford.
    // tabs-lists: three windowed lists (plain, searchable, an outline) switched between: every switch O(window).
    static let tabViews = CaseTableSource(file: #fileID, line: #line, """
        id          composition                                      in     size    n     script                       scales  timed  tags
        tabs-kinds  tabs(list.plain,table.wrap5,values,editor.wrap)  alone  120x40  2000  open;key:right*3;key:left*3  flat    -      tabs,offscreen
        tabs-lists  tabs(list.plain,list.search,outline.list)  alone  80x24  5000  open;key:right;key:right;key:left;key:left  flat  -  tabs,offscreen
        """)

    // nsplit-resize: a two-column navigation split view narrowed and widened again.
    // nsplit-collapse: the same split narrowed under 21 cells, where it collapses into a stack (decisions A21, B3):
    //   Return on a sidebar row shows the detail and Escape goes back. (nsplit-storm, in Storms.swift, expands it.)
    // nsplit-three: a three-column split walked with the arrows and Tab, then collapsed (under 32 cells).
    static let splitViews = CaseTableSource(file: #fileID, line: #line, """
        id               composition                     in     size    n    script                                          scales  timed  tags
        nsplit-resize    nsplit(list.plain,table.wrap5)  alone  120x40  300  open;resize:80x24;resize:40x12;resize:120x40    flat    -      navigation
        nsplit-collapse  nsplit(list.plain,table.wrap5)  alone  80x24   500  open;resize:20x12;key:down*3;key:enter;key:esc  flat    -      navigation
        nsplit-three  nsplit(list.plain,list.plain,table.wrap5)  alone  120x40  500  open;key:down*5;key:tab*2;key:down*5;resize:30x12  flat  -  navigation
        """)
}
