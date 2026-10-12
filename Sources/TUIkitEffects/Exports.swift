//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitEffects re-exports the module it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUIkitEffects` gives an app the
// transitions and the visual, symbol, scroll and colour effects.
// Beside what it gives an importer, it keeps
// TUIkitFoundation's names, and through its own re-exports the lower and side
// modules', in scope in every file of this module, as they were while
// TUIkitFoundation compiled these files (until step B5b); each file imports
// TUIkitFoundation itself as well (CONTRIBUTING.md, "Crossing a module
// boundary"). The umbrella, Sources/TUIkit, re-exports this module beside
// TUIkitFoundation.
@_exported import TUIkitFoundation
