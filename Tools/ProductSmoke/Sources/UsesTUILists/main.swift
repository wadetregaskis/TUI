//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUILists

let view = List { Text("A row") }

print("UsesTUILists: \(String(reflecting: type(of: view)))")
