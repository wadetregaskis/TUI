//  🖥️ TUI — A Terminal UI framework for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUICommands re-exports the modules it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUICommands` gives an app the
// commands (`Commands`, `CommandMenu`, `CommandGroup` and the placements) and
// the scene they are declared on: TUIApp, whose `Scene` the commands
// modifiers extend, TUIPresentation, whose alert the app menu's About is,
// and TUIFoundation. Beside what it gives an importer, it
// keeps their names, and through their own re-exports the chrome's and the
// lower and side modules', in scope in every file of this module; each file
// imports TUIFoundation itself as well, and TUIApp where it uses it
// (CONTRIBUTING.md, "Crossing a module boundary"). The umbrella, Sources/TUI,
// re-exports this module beside TUIFoundation.
@_exported import TUIApp
@_exported import TUIFoundation
@_exported import TUIPresentation
