//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitImage re-exports nothing: `Color` comes from TUIkitStyling's own import, which the TUIkitImage product
// allows without a product of its own, since it brings it (ChoosingProducts).
import TUIkitImage
import TUIkitStyling

let image = RGBAImage(width: 1, height: 1, pixels: [RGBA(r: 255, g: 0, b: 0)])
let palette = ASCIIPalette([Color.red, Color.blue])

print("UsesTUIkitImage: \(String(reflecting: type(of: image))), \(palette.colors.count) colours")
