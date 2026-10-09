//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitFoundation re-exports the modules it is built on, as each module of
// the split re-exports its direct dependencies (Documentation/Historical/
// Module split plan, revision 4, §4). Beside what it gives an importer, it
// keeps these modules' names in scope in every file of this one, as they were
// when this file's imports sat in the single TUIkit module's Exports.swift:
// most of its files use `FrameBuffer`, `RenderContext` or `Color` without
// naming the module that declares them. The umbrella, Sources/TUIkit, re-exports
// this module in turn.
//
// TUIkitStrings and TUIkitTerminalHost were compiled here until step B2 carved
// them out. No app imports either (plan §4: "Base re-exports them"), so
// `LocalizationService`, `TerminalClient` and the rest reach an app, and every
// file of this module, through these two lines.
//
// Not TUIkitImage, since step B5c carved the bitmap path out into
// TUIkitBitmaps: this module no longer depends on it (Package.swift). The
// modules that use it name it themselves: TUIkitBitmaps and TUIkitColorPicker,
// which re-export it, as does the umbrella, and TUIkitAppKit, which builds
// `RGBAImage` values and sits outside the split's module map.
@_exported import TUIkitCore
@_exported import TUIkitStrings
@_exported import TUIkitStyling
@_exported import TUIkitTerminalHost
@_exported import TUIkitView
