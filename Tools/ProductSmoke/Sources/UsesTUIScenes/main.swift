//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIScenes

let settings = Settings { Text("Settings") }

print("UsesTUIScenes: \(String(reflecting: type(of: settings)))")
