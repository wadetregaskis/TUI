//  🖥️ TUI — A Terminal UI framework for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIView re-exports the modules it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4): its API names TUICore's `FrameBuffer`
// (`Renderable`) and TUIStyling's `Color` (a `View` here), so a client of
// the TUIView product alone writes one import (decisions C9B, B-C9B-3).
@_exported import TUICore
@_exported import TUIStyling
