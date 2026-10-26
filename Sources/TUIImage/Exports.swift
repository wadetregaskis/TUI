//  🖥️ TUI — A Terminal UI framework for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIImage re-exports the module its API names, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4): `ASCIIPalette` is made of TUIStyling's
// `Color`, so a client of the TUIImage product alone writes one import
// (decisions C9B, B-C9B-3). Its other dependency, the stb_image C module, is
// its own business.
@_exported import TUIStyling
