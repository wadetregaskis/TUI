//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUITabs

let view = TabView { Tab("One", systemImage: "1.circle") { Text("One") } }

print("UsesTUITabs: \(String(reflecting: type(of: view)))")
