//  🖥️ TUI — A Terminal UI framework for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIDocuments re-exports the modules it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUIDocuments` gives an app
// `DocumentGroup` and what a document app is written with: TUIApp, whose `App`
// and `Scene` it plugs into, TUICommands, whose menu bar its File commands are
// in, TUIFilePanels, whose panels open and save and which holds `FileDocument`,
// `ReferenceFileDocument` and, where Foundation has none, `FileWrapper`,
// TUIPresentation, whose alerts ask about unsaved changes, and TUIFoundation.
// Beside what it gives an importer, it keeps their names in scope in every file
// of this module; each file imports them itself where it uses them
// (CONTRIBUTING.md, "Crossing a module boundary"). The umbrella, Sources/TUI,
// re-exports this module beside TUIFoundation.
//
// It does NOT re-export UniformTypeIdentifiers, as SwiftUI does not
// (Sources/TUIFilePanels/Exports.swift).
@_exported import TUIApp
@_exported import TUICommands
@_exported import TUIFilePanels
@_exported import TUIFoundation
@_exported import TUIPresentation
