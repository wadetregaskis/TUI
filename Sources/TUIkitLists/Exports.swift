//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitLists re-exports the module it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUIkitLists` will give an app lists,
// and tabs and grids until steps C3 and C4 peel them into TUIkitTabs and
// TUIkitGrid, once per-module products ship. Beside what it gives an
// importer, it keeps TUIkitFoundation's names, and through its own re-exports
// the lower and side modules', in scope in every file of this target, in all
// three of its directories (Sources/TUIkitLists, TUIkitTabs and TUIkitGrid),
// as they were while TUIkitFoundation compiled these files (until step B6).
// Tables were the fourth, until step C2 peeled them into TUIkitTables, which
// is built on this module and re-exports it. The umbrella, Sources/TUIkit,
// re-exports this module beside TUIkitFoundation, and so do TUIkitColorPicker
// and TUIkitTables.
@_exported import TUIkitFoundation
