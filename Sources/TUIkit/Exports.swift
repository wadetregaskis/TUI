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
// TUIkitFoundation is re-exported here: TUIkitApp (`App`, `Scene` and the run
// loop, since step B3), TUIkitColorPicker (`ColorPicker` and its editors, since
// step B4) and TUIkitNavigation (the navigation containers, and the
// presentations until step C1 peels them into TUIkitPresentation; since step
// B5). A qualified name in an app, `TUIkit.Label`, still resolves through these
// re-exports.
@_exported import TUIkitApp
@_exported import TUIkitColorPicker
@_exported import TUIkitCore
@_exported import TUIkitFoundation
@_exported import TUIkitImage
@_exported import TUIkitNavigation
@_exported import TUIkitStyling
@_exported import TUIkitView
