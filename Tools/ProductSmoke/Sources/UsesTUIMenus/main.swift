//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIMenus

let view = Menu("Menu") { Button("Item") {} }

print("UsesTUIMenus: \(String(reflecting: type(of: view)))")
