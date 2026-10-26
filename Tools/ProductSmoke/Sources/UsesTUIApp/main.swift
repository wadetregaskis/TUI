//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIApp

// `App`'s module: a scene, and TUIFoundation's `Text` through its re-export. Not run: that would start the app.
let scene = WindowGroup { Text("Hello, world") }

print("UsesTUIApp: \(String(reflecting: type(of: scene)))")
