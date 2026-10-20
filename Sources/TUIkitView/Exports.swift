//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitView re-exports the modules it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4): its API names TUIkitCore's `FrameBuffer`
// (`Renderable`) and TUIkitStyling's `Color` (a `View` here), so a client of
// the TUIkitView product alone writes one import (decisions C9B, B-C9B-3).
@_exported import TUIkitCore
@_exported import TUIkitStyling
