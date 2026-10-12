//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitLists re-exports the module it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUIkitLists` gives an app lists.
// Beside what it gives an importer, it keeps
// TUIkitFoundation's names, and through its own re-exports the lower and side
// modules', in scope in every file of this module, as they were while
// TUIkitFoundation compiled these files (until step B6). This target compiled
// three more directories from step B6: the tables until step C2, the tab
// views until step C3 and the grids until step C4 peeled each into a module of
// its own (TUIkitTables, TUIkitTabs, TUIkitGrid). The first two are built on
// this module and re-export it; the grids use nothing of it. The umbrella,
// Sources/TUIkit, re-exports this module beside TUIkitFoundation, and so do
// TUIkitTables and TUIkitTabs.
@_exported import TUIkitFoundation
