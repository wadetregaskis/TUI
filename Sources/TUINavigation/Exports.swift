//  🖥️ TUI — A Terminal UI framework for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUINavigation re-exports the module it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUINavigation` gives an app
// the navigation containers. Beside what it
// gives an importer, it keeps TUIFoundation's names, and through its own
// re-exports the lower and side modules', in scope in every file of this
// module, as they were while TUIFoundation compiled these files (until step
// B5); each file imports TUIFoundation itself as well (CONTRIBUTING.md,
// "Crossing a module boundary"). From step B5 until step C1 this target also
// compiled the presentations' directory, Sources/TUIPresentation, and
// re-exported TUIChrome for them (since step B5b); TUIPresentation is a
// module of its own since C1, and the navigation containers use neither it nor
// TUIChrome. The umbrella, Sources/TUI, re-exports this module beside
// TUIFoundation.
@_exported import TUIFoundation
