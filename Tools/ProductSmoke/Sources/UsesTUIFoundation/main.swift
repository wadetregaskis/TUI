//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// The base every module re-exports: the views and modifiers a library of views is made of.
let view = VStack {
    Text("Foundation").bold()
    Button("Press") {}
    Toggle("On", isOn: .constant(true))
}

print("UsesTUIFoundation: \(String(reflecting: type(of: view)))")
