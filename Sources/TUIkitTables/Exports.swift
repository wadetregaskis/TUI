//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitTables re-exports the modules it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUIkitTables` gives an app
// tables (`Table`, its columns, rows, builders and customization, outline
// rows, the table styles and row drag and drop):
// TUIkitFoundation, and TUIkitLists (a table's rows run on the list's
// row engine: its handler, the row memo, row selection, reorder and context
// menus), so `List` comes with it too (plan §4: "Tables re-exports Lists").
// Beside what it gives an importer, it keeps their names, and through
// TUIkitFoundation's own re-exports the lower and side modules', in scope in
// every file of this module, as they were while TUIkitFoundation (until step
// B6) and then TUIkitLists (until step C2) compiled these files; each file
// imports TUIkitFoundation itself as well, and TUIkitLists where it uses it
// (CONTRIBUTING.md, "Crossing a module boundary"). The umbrella,
// Sources/TUIkit, re-exports this module beside TUIkitFoundation.
@_exported import TUIkitFoundation
@_exported import TUIkitLists
