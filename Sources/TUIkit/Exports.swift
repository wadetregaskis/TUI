//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by LAYERED.work
//  License: MIT

// The umbrella: `import TUIkit` is the whole framework. It declares nothing of
// its own (Tools/ModuleMap's `umbrella` check holds it to imports): the views,
// modifiers and the rest are TUIkitFoundation's, which compiles every module
// of the planned split until each is carved into a target of its own
// (Documentation/Historical/Module split plan, revision 4); the lower four are
// the substrate beneath it. A module already carved out that TUIkitFoundation
// is built on (TUIkitStrings, TUIkitTerminalHost) comes through
// TUIkitFoundation's own re-exports; one carved out that is built on
// TUIkitFoundation (TUIkitApp: `App`, `Scene` and the run loop, since step B3)
// is re-exported here. A qualified name in an app, `TUIkit.Label`, still
// resolves through these re-exports.
@_exported import TUIkitApp
@_exported import TUIkitCore
@_exported import TUIkitFoundation
@_exported import TUIkitImage
@_exported import TUIkitStyling
@_exported import TUIkitView
