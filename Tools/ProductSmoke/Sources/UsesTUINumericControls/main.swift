//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUINumericControls

let view = Slider(value: .constant(0.5))

print("UsesTUINumericControls: \(String(reflecting: type(of: view)))")
