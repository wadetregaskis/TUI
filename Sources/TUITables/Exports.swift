//  🖥️ TUI — A Terminal UI framework for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUITables re-exports the modules it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUITables` gives an app
// tables (`Table`, its columns, rows, builders and customization, outline
// rows, the table styles and row drag and drop):
// TUIFoundation, and TUILists (a table's rows run on the list's
// row engine: its handler, the row memo, row selection, reorder and context
// menus), so `List` comes with it too (plan §4: "Tables re-exports Lists").
// Beside what it gives an importer, it keeps their names, and through
// TUIFoundation's own re-exports the lower and side modules', in scope in
// every file of this module, as they were while TUIFoundation (until step
// B6) and then TUILists (until step C2) compiled these files; each file
// imports TUIFoundation itself as well, and TUILists where it uses it
// (CONTRIBUTING.md, "Crossing a module boundary"). The umbrella,
// Sources/TUI, re-exports this module beside TUIFoundation.
@_exported import TUIFoundation
@_exported import TUILists
