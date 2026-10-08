//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitNavigation re-exports the module it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUIkitNavigation` will give an app
// the navigation containers, and the presentations until step C1 peels them
// into TUIkitPresentation, once per-module products ship. Beside what it gives
// an importer, it keeps TUIkitFoundation's names, and through its own
// re-exports the lower and side modules', in scope in every file of this
// target, in both of its directories (Sources/TUIkitNavigation and
// Sources/TUIkitPresentation), as they were while TUIkitFoundation compiled
// these files (until step B5). The umbrella, Sources/TUIkit, re-exports this
// module beside TUIkitFoundation, and so does TUIkitColorPicker.
@_exported import TUIkitFoundation
