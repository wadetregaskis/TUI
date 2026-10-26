//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

// The umbrella: one import, every module.
let view = VStack {
    Text("TUI")
    List { Text("A row") }
    Slider(value: .constant(0.5))
}
let scene = WindowGroup { view }

print("UsesTUI: \(String(reflecting: type(of: scene)))")
