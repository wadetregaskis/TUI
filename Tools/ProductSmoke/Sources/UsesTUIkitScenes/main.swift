//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitScenes

let settings = Settings { Text("Settings") }

print("UsesTUIkitScenes: \(String(reflecting: type(of: settings)))")
