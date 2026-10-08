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
@_exported import TUIkitCore
@_exported import TUIkitImage
@_exported import TUIkitStyling
@_exported import TUIkitView
