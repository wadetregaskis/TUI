//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIEffects

let view = Text("Effects").transition(.opacity)

print("UsesTUIEffects: \(String(reflecting: type(of: view)))")
