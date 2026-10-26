//  🖥️ TUI — A Terminal UI framework for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIChrome re-exports the module it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUIChrome` gives an app the
// window chrome (the status bar, toolbars, notifications, tooltips and
// `.help`). Beside what it gives an importer, it
// keeps TUIFoundation's names, and through its own re-exports the lower and
// side modules', in scope in every file of this module, as they were while
// TUIFoundation compiled these files (until step B5b); each file imports
// TUIFoundation itself as well (CONTRIBUTING.md, "Crossing a module
// boundary"). The umbrella, Sources/TUI, re-exports this module beside
// TUIFoundation, and so do TUIApp and TUIPresentation, which depend on
// it (and TUINavigation did, from step B5b until step C1 peeled the
// presentations out of it).
@_exported import TUIFoundation
