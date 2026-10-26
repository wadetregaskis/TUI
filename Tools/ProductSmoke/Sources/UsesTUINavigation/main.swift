//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUINavigation

let view = NavigationStack { Text("Root") }

print("UsesTUINavigation: \(String(reflecting: type(of: view)))")
