//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIColorPicker

let view = ColorPicker("Tint", selection: .constant(Color.red))

print("UsesTUIColorPicker: \(String(reflecting: type(of: view)))")
