//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIImage re-exports TUIStyling, whose `Color` its API names (its Exports.swift), so this one import gives a
// file `Color` too (ChoosingProducts).
import TUIImage

let image = RGBAImage(width: 1, height: 1, pixels: [RGBA(r: 255, g: 0, b: 0)])
let palette = ASCIIPalette([Color.red, Color.blue])

print("UsesTUIImage: \(String(reflecting: type(of: image))), \(palette.colors.count) colours")
