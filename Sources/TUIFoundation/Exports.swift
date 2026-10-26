//  🖥️ TUI — A Terminal UI framework for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIFoundation re-exports the modules it is built on, as each module of
// the split re-exports its direct dependencies (Documentation/Historical/
// Module split plan, revision 4, §4). Beside what it gives an importer, it
// keeps these modules' names in scope in every file of this one, as they were
// when this file's imports sat in the single TUI module's Exports.swift:
// most of its files use `FrameBuffer`, `RenderContext` or `Color` without
// naming the module that declares them. The umbrella, Sources/TUI, re-exports
// this module in turn.
//
// TUIStrings and TUITerminalHost were compiled here until step B2 carved
// them out. No app imports either (plan §4: "Base re-exports them"), so
// `LocalizationService`, `TerminalClient` and the rest reach an app, and every
// file of this module, through these two lines.
//
// Not TUIImage, since step B5c carved the bitmap path out into
// TUIBitmaps: this module no longer depends on it (Package.swift). The
// modules that use it name it themselves: TUIBitmaps and TUIColorPicker,
// which re-export it, as does the umbrella, and TUIAppKit, which builds
// `RGBAImage` values and sits outside the split's module map.
@_exported import TUICore
@_exported import TUIStrings
@_exported import TUIStyling
@_exported import TUITerminalHost
@_exported import TUIView
