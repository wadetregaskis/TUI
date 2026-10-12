//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitColorPicker

let view = ColorPicker("Tint", selection: .constant(Color.red))

print("UsesTUIkitColorPicker: \(String(reflecting: type(of: view)))")
