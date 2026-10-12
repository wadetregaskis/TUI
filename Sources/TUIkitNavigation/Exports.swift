//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitNavigation re-exports the module it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUIkitNavigation` gives an app
// the navigation containers. Beside what it
// gives an importer, it keeps TUIkitFoundation's names, and through its own
// re-exports the lower and side modules', in scope in every file of this
// module, as they were while TUIkitFoundation compiled these files (until step
// B5); each file imports TUIkitFoundation itself as well (CONTRIBUTING.md,
// "Crossing a module boundary"). From step B5 until step C1 this target also
// compiled the presentations' directory, Sources/TUIkitPresentation, and
// re-exported TUIkitChrome for them (since step B5b); TUIkitPresentation is a
// module of its own since C1, and the navigation containers use neither it nor
// TUIkitChrome. The umbrella, Sources/TUIkit, re-exports this module beside
// TUIkitFoundation.
@_exported import TUIkitFoundation
