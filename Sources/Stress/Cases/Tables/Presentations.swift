//  🖥️ TUI — A Terminal UI framework for Swift
//  Presentations.swift
//
//  Perf cases: sheets, item sheets, popovers and alerts, presented, used and
//  dismissed. See `CaseTable.swift` for the columns, and
//  `CaseVocabulary.swift` for the words.
//
//  Created by Wade Tregaskis
//  License: MIT

extension CaseTables {
    // sheet-present: a list presents a sheet of another list, which is scrolled, dismissed with Escape and presented
    //   again: what presenting costs the page behind, and whether the second presentation starts over (a dismissed
    //   sheet's content loses its state).
    // sheet-search: a sheet holding a searchable list over a wrapped table, searched in and dismissed: a keystroke in
    //   a sheet must not cost the page behind it. Find first: the field leaves the first focus to the list, and a key
    //   typed there is the list's type select (PERFCASE-F11, which the script first measured); the first Escape ends
    //   the search, the second dismisses the sheet.
    // sheet-item-switch / sheet-item-walk: `.sheet(item:)`, which keeps each item's state while it is up (W17): an
    //   item's list scrolled, another item shown, the first shown again with its scroll kept; and a walk through 20
    //   items, past the 16 left behind that are kept, back to the first, whose content's state has been let go (the
    //   value controls are bound to the case's model, so what an item keeps there is its focus).
    // popover-values: a popover of the value controls over a list, its slider moved and the popover dismissed: the
    //   popover's cost beside the page's. The session's loop presents it again, which is PERFCASE-F13's script: the
    //   list behind it, stored as the popover came back with the focus not yet landed, was served beside its
    //   scrollbar after the Tab into the popover, a cell narrower than its cache-cleared twin's.
    // alert-list / alert-table: an alert over a list and over a `.fit` table, answered by Escape and by Return:
    //   whether presenting an alert costs the page behind it a rebuild, and whether it reads a `.fit` column again.
    // sheet-tiny: a sheet in a 20x6 terminal, scrolled and dismissed.
    static let presentations = CaseTableSource(file: #fileID, line: #line, """
        id              composition                     in     size    n     script                                   scales  timed  tags
        sheet-present   sheet(list.plain,list.plain)    alone  80x24   2000  open;present;wheel:+5*5;key:esc;present  flat    -      sheet,list
        sheet-search  sheet(table.wrap5,list.search)  alone  120x40  2000  open;present;key:find;type:ab;key:bksp*2;key:esc*2  flat  -  sheet,search,invalidate
        sheet-item-switch  sheetitem(list.plain,list.plain)  alone  80x24  2000  open;item:1;wheel:+5*4;item:2;item:1;key:esc  flat  -  sheet,list,offscreen
        sheet-item-walk  sheetitem(table.wrap5,values)  alone  120x40  1000  open;item:0;key:right*3;item:+1*20;item:0;dismiss  flat  -  sheet,values,offscreen
        popover-values  popover(list.plain,values)      alone  80x24   2000  open;present;key:tab;key:right*10;key:esc  flat    -      popover,values
        alert-list      alert(list.plain)               alone  80x24   2000  open;present;key:esc;present;key:enter   flat    -      alert,list
        alert-table     alert(table.fit5)               alone  120x40  2000  open;present;key:esc                     flat    -      alert,table,memo
        sheet-tiny      sheet(list.plain,list.plain)    alone  20x6    1000  open;present;wheel:+5*5;key:esc          flat    -      sheet,tiny
        """)
}
