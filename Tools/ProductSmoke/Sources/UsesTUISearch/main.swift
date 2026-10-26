//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUISearch

let view = Text("Search").searchable(text: .constant(""))

print("UsesTUISearch: \(String(reflecting: type(of: view)))")
