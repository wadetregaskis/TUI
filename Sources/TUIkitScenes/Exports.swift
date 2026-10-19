//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitScenes re-exports the modules it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUIkitScenes` gives an app the scenes
// presented over its windows (`Settings`, `AlertScene`) and what they are
// declared beside: TUIkitApp, whose `Scene` and presenter they plug into,
// TUIkitPresentation, whose sheet and alert they are drawn with, and
// TUIkitFoundation. Beside what it gives an importer, it keeps their names in
// scope in every file of this module; each file imports TUIkitFoundation
// itself as well, and TUIkitApp and TUIkitPresentation where it uses them
// (CONTRIBUTING.md, "Crossing a module boundary"). The umbrella, Sources/TUIkit,
// re-exports this module beside TUIkitFoundation.
@_exported import TUIkitApp
@_exported import TUIkitFoundation
@_exported import TUIkitPresentation
