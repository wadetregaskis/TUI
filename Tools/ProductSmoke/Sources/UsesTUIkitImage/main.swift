//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitImage

let value = RGBAImage(width: 1, height: 1, pixels: [RGBA(r: 255, g: 0, b: 0)])

print("UsesTUIkitImage: \(String(reflecting: type(of: value)))")
