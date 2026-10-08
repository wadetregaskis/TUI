//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitLists re-exports the module it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUIkitLists` will give an app lists,
// and tables, tabs and grids until steps C2 to C4 peel them into TUIkitTables,
// TUIkitTabs and TUIkitGrid, once per-module products ship. Beside what it
// gives an importer, it keeps TUIkitFoundation's names, and through its own
// re-exports the lower and side modules', in scope in every file of this
// target, in all four of its directories (Sources/TUIkitLists, TUIkitTables,
// TUIkitTabs and TUIkitGrid), as they were while TUIkitFoundation compiled
// these files (until step B6). The umbrella, Sources/TUIkit, re-exports this
// module beside TUIkitFoundation, and so does TUIkitColorPicker.
@_exported import TUIkitFoundation
