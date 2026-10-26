//  🖥️ TUI — A Terminal UI framework for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIScenes re-exports the modules it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUIScenes` gives an app the scenes
// presented over its windows (`Settings`, `AlertScene`) and what they are
// declared beside: TUIApp, whose `Scene` and presenter they plug into,
// TUIPresentation, whose sheet and alert they are drawn with, and
// TUIFoundation. Beside what it gives an importer, it keeps their names in
// scope in every file of this module; each file imports TUIFoundation
// itself as well, and TUIApp and TUIPresentation where it uses them
// (CONTRIBUTING.md, "Crossing a module boundary"). The umbrella, Sources/TUI,
// re-exports this module beside TUIFoundation.
@_exported import TUIApp
@_exported import TUIFoundation
@_exported import TUIPresentation
