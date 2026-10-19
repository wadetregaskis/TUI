//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitCommands re-exports the modules it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUIkitCommands` gives an app the
// commands (`Commands`, `CommandMenu`, `CommandGroup` and the placements) and
// the scene they are declared on: TUIkitApp, whose `Scene` the commands
// modifiers extend, TUIkitPresentation, whose alert the app menu's About is,
// and TUIkitFoundation. Beside what it gives an importer, it
// keeps their names, and through their own re-exports the chrome's and the
// lower and side modules', in scope in every file of this module; each file
// imports TUIkitFoundation itself as well, and TUIkitApp where it uses it
// (CONTRIBUTING.md, "Crossing a module boundary"). The umbrella, Sources/TUIkit,
// re-exports this module beside TUIkitFoundation.
@_exported import TUIkitApp
@_exported import TUIkitFoundation
@_exported import TUIkitPresentation
