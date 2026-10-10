//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitLists re-exports the module it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUIkitLists` will give an app lists,
// and grids until step C4 peels them into TUIkitGrid, once per-module products
// ship. Beside what it gives an importer, it keeps TUIkitFoundation's names,
// and through its own re-exports the lower and side modules', in scope in
// every file of this target, in both of its directories (Sources/TUIkitLists
// and TUIkitGrid), as they were while TUIkitFoundation compiled these files
// (until step B6). Tables were the fourth, until step C2 peeled them into
// TUIkitTables, and tabs the third, until step C3 peeled them into TUIkitTabs;
// each is built on this module and re-exports it. The umbrella,
// Sources/TUIkit, re-exports this module beside TUIkitFoundation, and so do
// TUIkitTables and TUIkitTabs.
@_exported import TUIkitFoundation
