//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitApp

// `App`'s module: a scene, and TUIkitFoundation's `Text` through its re-export. Not run: that would start the app.
let scene = WindowGroup { Text("Hello, world") }

print("UsesTUIkitApp: \(String(reflecting: type(of: scene)))")
