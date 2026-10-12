//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitGrid re-exports the module it is built on, as each module of the split
// re-exports its direct dependencies (Documentation/Historical/Module split
// plan, revision 4, §4), so `import TUIkitGrid` gives an app grids
// (`Grid`, `GridRow`, `LazyVGrid`, `LazyHGrid` and `GridItem`).
// Beside what it gives an importer, it keeps TUIkitFoundation's
// names, and through its own re-exports the lower and side modules', in scope
// in every file of this module, as they were while TUIkitFoundation (until step
// B6) and then TUIkitLists (until step C4) compiled these files; each file
// imports TUIkitFoundation itself as well (CONTRIBUTING.md, "Crossing a module
// boundary"). The umbrella, Sources/TUIkit, re-exports this module beside
// TUIkitFoundation, and nothing else does.
@_exported import TUIkitFoundation
