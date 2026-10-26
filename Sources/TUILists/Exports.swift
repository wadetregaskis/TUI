//  🖥️ TUI — A Terminal UI framework for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUILists re-exports the module it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUILists` gives an app lists.
// Beside what it gives an importer, it keeps
// TUIFoundation's names, and through its own re-exports the lower and side
// modules', in scope in every file of this module, as they were while
// TUIFoundation compiled these files (until step B6). This target compiled
// three more directories from step B6: the tables until step C2, the tab
// views until step C3 and the grids until step C4 peeled each into a module of
// its own (TUITables, TUITabs, TUIGrid). The first two are built on
// this module and re-export it; the grids use nothing of it. The umbrella,
// Sources/TUI, re-exports this module beside TUIFoundation, and so do
// TUITables and TUITabs.
@_exported import TUIFoundation
