//  🖥️ TUI — A Terminal UI framework for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIGrid re-exports the module it is built on, as each module of the split
// re-exports its direct dependencies (Documentation/Historical/Module split
// plan, revision 4, §4), so `import TUIGrid` gives an app grids
// (`Grid`, `GridRow`, `LazyVGrid`, `LazyHGrid` and `GridItem`).
// Beside what it gives an importer, it keeps TUIFoundation's
// names, and through its own re-exports the lower and side modules', in scope
// in every file of this module, as they were while TUIFoundation (until step
// B6) and then TUILists (until step C4) compiled these files; each file
// imports TUIFoundation itself as well (CONTRIBUTING.md, "Crossing a module
// boundary"). The umbrella, Sources/TUI, re-exports this module beside
// TUIFoundation, and nothing else does.
@_exported import TUIFoundation
