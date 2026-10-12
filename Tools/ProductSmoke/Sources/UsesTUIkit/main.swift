//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// The umbrella: one import, every module.
let view = VStack {
    Text("TUIkit")
    List { Text("A row") }
    Slider(value: .constant(0.5))
}
let scene = WindowGroup { view }

print("UsesTUIkit: \(String(reflecting: type(of: scene)))")
